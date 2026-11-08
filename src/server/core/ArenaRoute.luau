--!strict
-- Arena routing: where a player belongs, and whether they are actually there.
--
-- Pure logic, no Roblox objects, no remotes, no yielding. The Roblox adapter
-- (Main.server) owns the teleport call; this module owns *deciding* it is needed.
--
-- Why this exists
-- ---------------
-- Phase 1/2 shipped a single fire-and-forget `character:PivotTo(target)` on the
-- phase change. That is not a reliable transition:
--   * PivotTo can return while the humanoid is still unseated, and the engine's
--     own state machine (PlatformStand, Seats, terrain) can own the root for a
--     moment and drop the character back where it was;
--   * a character that spawns during the same frame the phase flips is skipped,
--     and nothing ever retries;
--   * a player killed/respawned mid-round is only rescued by the void check;
--   * nothing verifies the character ended up in the arena at all.
--
-- So the route is a small state machine: the server *asserts* a destination and
-- keeps asserting it (with backoff) until the character is measurably there, then
-- goes quiet. Every decision below is a pure function so it can be tested without
-- an engine.
local ArenaRoute = {}
ArenaRoute.__index = ArenaRoute

export type Position = { x: number, y: number, z: number }

-- Tuning. Exported so the adapter and the tests can reason about the same numbers.
--
-- The archipelago runs along +Z: the arena disc and its four satellites occupy
-- z <= ~90, the garden lobby sits around z = 180, and a north causeway links them.
-- Deciding "which half is this player in" is therefore a plane test, not a radius:
-- a radius test was wrong in both directions (arena pads sit 36 studs out, while
-- the west dock reaches x = 94).
ArenaRoute.ARENA_MAX_Z = 92      -- south of this is arena, north is lobby
ArenaRoute.LOBBY_MIN_Z = 140     -- the lobby island's southern shore
ArenaRoute.ARENA_CENTRE = { x = 0, y = 21, z = 0 }
ArenaRoute.LOBBY_CENTRE = { x = 0, y = 21, z = 180 }
ArenaRoute.LOBBY_RADIUS = 46     -- spawn spacing / reporting only
ArenaRoute.RETRY_DELAY = 0.45    -- seconds between re-assertions
ArenaRoute.MAX_ATTEMPTS = 4      -- per destination (≈1.8 s), then escalate to the fallback
ArenaRoute.GRACE = 0.6           -- let the engine seat the character before judging
ArenaRoute.CELL_SIZE = 8         -- sweep cadence: one eighth of the roster per step

export type Verdict = "arrived" | "pending" | "retry" | "give-up" | "idle"
export type Zone = "arena" | "transit" | "lobby"

type Track = {
	target: string?,      -- "arena" | "lobby" | nil (open union: nil is valid)
	attempts: number,
	lastAttempt: number,
	firstAttempt: number,
	cooldownUntil: number,
}

type Fields = {
	tracks: { [number]: Track },
	corrections: number,
	fallbacks: number,
	arrivals: number,
}

export type Router = typeof(setmetatable({} :: Fields, ArenaRoute))

local function distance(a: Position, b: Position): number
	local dx, dz = a.x - b.x, a.z - b.z
	return math.sqrt(dx * dx + dz * dz)
end

ArenaRoute.distance = distance

-- The causeway is neutral ground: walking it must never start a teleport/return
-- loop in either direction, so "in transit" counts as arrived for both targets.
function ArenaRoute.zone(position: Position): Zone
	if position.z >= ArenaRoute.LOBBY_MIN_Z then
		return "lobby"
	elseif position.z <= ArenaRoute.ARENA_MAX_Z then
		return "arena"
	end
	return "transit"
end

function ArenaRoute.new(): Router
	return setmetatable({ tracks = {}, corrections = 0, fallbacks = 0, arrivals = 0 }, ArenaRoute)
end

function ArenaRoute.track(self: Router, id: number): Track
	local existing = self.tracks[id]
	if existing then
		return existing
	end
	local fresh: Track = { attempts = 0, lastAttempt = -math.huge, firstAttempt = 0, cooldownUntil = 0 }
	self.tracks[id] = fresh
	return fresh
end

function ArenaRoute.remove(self: Router, id: number)
	self.tracks[id] = nil
end

-- Which destination a player should be standing in, by phase and eligibility.
-- Idle players (spectating between rounds) are never moved.
function ArenaRoute.desired(phase: string, participating: boolean): string?
	if phase == "Playing" and participating then
		return "arena"
	end
	if phase == "Intermission" or phase == "Results" or phase == "Waiting" then
		return "lobby"
	end
	return nil
end

-- Is a position inside its destination? Generous on purpose: this asks "did the
-- character leave the other half of the map?", not "is it on a spawn pad?".
function ArenaRoute.atDestination(destination: string, position: Position): boolean
	local side = ArenaRoute.zone(position)
	if destination == "arena" then
		return side ~= "lobby"
	elseif destination == "lobby" then
		return side ~= "arena"
	end
	return false
end

-- Record that the adapter teleported this player now.
function ArenaRoute.attempt(self: Router, id: number, destination: string, now: number)
	local track = self:track(id)
	if track.target ~= destination then
		track.target = destination
		track.attempts = 0
		track.firstAttempt = now
	end
	track.attempts += 1
	track.lastAttempt = now
	track.cooldownUntil = now + ArenaRoute.RETRY_DELAY
end

-- The decision. `ready` means the adapter is willing to move the character at all
-- (character exists, humanoid alive, root present) — the caller must not teleport
-- when this is false.
--
--   arrived  -> the character is measurably at the destination; stop asserting
--   pending  -> moved recently, or the engine is still seating it; do nothing yet
--   retry    -> assert the destination again (the adapter teleports)
--   give-up  -> attempts exhausted; the adapter should escalate (fallback path)
--   idle     -> the player belongs nowhere this phase
function ArenaRoute.evaluate(
	self: Router,
	id: number,
	phase: string,
	participating: boolean,
	position: Position?,
	ready: boolean,
	now: number
): (Verdict, string?)
	local destination = ArenaRoute.desired(phase, participating)
	local track = self:track(id)
	if not destination then
		track.target = nil
		track.attempts = 0
		return "idle", nil
	end
	if not ready or not position then
		-- Character is dead, loading or unseated. Not a failure: wait for it. A
		-- respawn fires CharacterAdded, which resets this track.
		return "pending", destination
	end
	if ArenaRoute.atDestination(destination, position) then
		if track.target ~= nil and track.target ~= destination then
			-- Travelling the other way: the position still reads as the old
			-- destination for a frame. Fall through to a fresh attempt.
			track.attempts = 0
		else
			if track.target ~= destination then
				self.arrivals += 1
			end
			track.target = destination
			track.attempts = 0
			return "arrived", destination
		end
	end
	-- Wrong place. Fresh intent (phase flip or first sight of this player)?
	if track.target ~= destination then
		if track.cooldownUntil > now then
			return "pending", destination
		end
		return "retry", destination
	end
	-- Already asserting this destination.
	if now - track.lastAttempt < ArenaRoute.RETRY_DELAY then
		return "pending", destination
	end
	if track.attempts < ArenaRoute.MAX_ATTEMPTS then
		return "retry", destination
	end
	-- The normal path has failed repeatedly. The adapter escalates: it re-seats the
	-- character (reparent, humanoid state reset, teleport again) and this counter
	-- is what proves in the log that a fallback actually ran.
	track.attempts = 0
	track.firstAttempt = now
	self.fallbacks += 1
	self.corrections += 1
	return "give-up", destination
end

-- Cheap round-robin sweep so a full server does not re-evaluate 12 characters on
-- every heartbeat. Returns the slice of ids to examine this step.
function ArenaRoute.slice(ids: { number }, step: number): { number }
	local out: { number } = {}
	local size = math.max(1, ArenaRoute.CELL_SIZE)
	local cells = math.ceil(#ids / size)
	if cells <= 1 then
		for _, id in ids do
			table.insert(out, id)
		end
		return out
	end
	local cell = step % cells
	for index, id in ids do
		if (index - 1) // size == cell then
			table.insert(out, id)
		end
	end
	return out
end

function ArenaRoute.stats(self: Router)
	return {
		arrivals = self.arrivals,
		fallbacks = self.fallbacks,
		corrections = self.corrections,
		tracked = (function()
			local count = 0
			for _ in self.tracks do
				count += 1
			end
			return count
		end)(),
	}
end

return ArenaRoute
