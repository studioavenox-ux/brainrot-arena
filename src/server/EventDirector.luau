--!strict
-- Event director: the only place that turns the round machine's event state into
-- things a player can feel. Everything here is driven by names baked into the map
-- by tools/events.py, so a server can find the geometry without any registry.
--
-- Rules this file holds:
--   * Nothing here decides *when* an event happens. The round machine owns the
--     clock; the director only reacts to the effects it is handed.
--   * Gravity, walking friction, raft motion and path solidity are all reset the
--     moment an event closes, and again on every phase change, so a dropped effect
--     can never leave the arena in a broken state.
local EventDirector = {}
EventDirector.__index = EventDirector

local RAFT_PREFIX = "EventRaft_"
local PATH_PREFIX = "EventPath_"

export type Geometry = {
	rafts: { [string]: BasePart },       -- suffix -> deck part
	paths: { [string]: { BasePart } },   -- index -> spans
	glows: { [string]: { BasePart } },
	tracks: { [string]: { BasePart } },
}

-- The baked pose of everything the director moves. Captured once at start-up from
-- the geometry itself (the place is the source of truth), so parking a raft and
-- dropping a span are exact restores rather than recomputed guesses.
type Rest = {
	raftPose: { [string]: CFrame },
	pathPose: { [BasePart]: CFrame },
	-- Each span's glow strip, so the light rides with the surface it belongs to.
	pathGlow: { [BasePart]: { BasePart } },
}

export type State = {
	kind: string,
	endsAt: number,
	elapsed: number,
}

type Fields = {
	world: Model?,
	rest: Rest,
	geometry: Geometry,
	normalGravity: number,
	lowGravity: number,
	normalFriction: number,
	slipperyFriction: number,
	active: string,
	endsAt: number,
	startedAt: number,
	pathLift: number,
	period: number,
	parked: boolean,
	raftsMoved: number,
	lastPathSolid: boolean,
}
export type Director = typeof(setmetatable({} :: Fields, EventDirector))

EventDirector.__index = EventDirector

-- Mirrors tools/events.py. Kept as literals so the server never parses Python.
local PLATFORMS = {
	{ Suffix = "A", Phase = math.pi / 4, Radius = 25.5, Top = 21.9 },
	{ Suffix = "B", Phase = math.pi * 11 / 12, Radius = 25.5, Top = 21.9 },
	{ Suffix = "C", Phase = math.pi * 19 / 12, Radius = 25.5, Top = 21.9 },
}
local PLATFORM_HEIGHT = 0.55
local PERIOD = 30
local PATH_COUNT = 4
local PATH_SEGMENTS = 3
local PATH_LIFT = 0.9

function EventDirector.new(world: Model, normalGravity: number, lowGravity: number,
	normalFriction: number, slipperyFriction: number): Director
	local rafts: { [string]: BasePart } = {}
	local rest: Rest = { raftPose = {}, pathPose = {}, pathGlow = {} }
	local pendingGlows: { [string]: BasePart } = {}
	local paths: { [string]: { BasePart } } = {}
	local glows: { [string]: { BasePart } } = {}
	local tracks: { [string]: { BasePart } } = {}
	-- Find baked geometry by name. A server started from an older place simply
	-- reports nothing found, and every event still works (gravity + friction do not
	-- need geometry).
	for _, item in world:GetDescendants() do
		if not item:IsA("BasePart") then
			continue
		end
		local name = item.Name
		if string.sub(name, 1, #RAFT_PREFIX) == RAFT_PREFIX then
			local suffix = string.sub(name, #RAFT_PREFIX + 1, #RAFT_PREFIX + 1)
			if string.find(name, "_Deck", 1, true) then
				rafts[suffix] = item
				rest.raftPose[suffix] = item.CFrame
			elseif string.find(name, "_Glow", 1, true) or string.find(name, "_Lip", 1, true) then
				glows[suffix] = glows[suffix] or {}
				table.insert(glows[suffix], item)
			elseif string.find(name, "_Track", 1, true) then
				tracks[suffix] = tracks[suffix] or {}
				table.insert(tracks[suffix], item)
			end
		elseif string.sub(name, 1, #PATH_PREFIX) == PATH_PREFIX then
			local index = string.match(name, "^EventPath_(%d+)_Span_%d+$")
			if index then
				paths[index] = paths[index] or {}
				table.insert(paths[index], item)
				rest.pathPose[item] = item.CFrame
			elseif string.match(name, "^EventPath_%d+_Glow_%d+$") then
				-- Glow strips are paired with their span after the sweep.
				pendingGlows[string.gsub(name, "_Glow_", "_Span_")] = item
			end
		end
	end
	-- Pair every glow strip with the span of the same index, and record both rest
	-- poses. A span without a strip (or the reverse) is simply skipped.
	for _, group in paths do
		for _, span in group do
			local glow = pendingGlows[span.Name]
			if glow then
				rest.pathGlow[span] = rest.pathGlow[span] or {}
				table.insert(rest.pathGlow[span], glow)
				rest.pathPose[glow] = glow.CFrame
			end
		end
	end
	return setmetatable({
		world = world, rest = rest,
		geometry = { rafts = rafts, paths = paths, glows = glows, tracks = tracks },
		normalGravity = normalGravity, lowGravity = lowGravity,
		normalFriction = normalFriction, slipperyFriction = slipperyFriction,
		active = "", endsAt = 0, startedAt = 0, pathLift = PATH_LIFT, period = PERIOD,
		parked = true, raftsMoved = 0, lastPathSolid = false,
	}, EventDirector)
end

function EventDirector.counts(self: Director): (number, number)
	local rafts, paths = 0, 0
	for _ in self.geometry.rafts do
		rafts += 1
	end
	for _, group in self.geometry.paths do
		paths += #group
	end
	return rafts, paths
end

-- Where a raft should be at `elapsed` seconds into the round.
function EventDirector.raftPose(self: Director, entry: { Suffix: string, Phase: number, Radius: number, Top: number },
	elapsed: number): (number, number)
	local angle = entry.Phase + elapsed * math.tau / self.period
	return math.cos(angle) * entry.Radius, math.sin(angle) * entry.Radius
end

local function setPaths(self: Director, solid: boolean)
	for _, group in self.geometry.paths do
		for _, span in group do
			span.CanCollide = solid
			span.Transparency = if solid then 0 else 1
			-- Lift so the walkable surface lands flush with the arena floor while
			-- solid. Baked at its rest pose, so dropping it back is exact.
			local restPose = self.rest.pathPose[span]
			if restPose then
				span.CFrame = if solid
					then restPose + Vector3.new(0, self.pathLift, 0)
					else restPose
			end
			-- The glow strip rides with the span, so the light never floats where the
			-- surface is not.
			for _, glow in self.rest.pathGlow[span] or {} do
				local glowRest = self.rest.pathPose[glow]
				if glowRest then
					glow.CFrame = if solid then glowRest + Vector3.new(0, self.pathLift, 0) else glowRest
				end
			end
		end
	end
	self.lastPathSolid = solid
end

local function parkRafts(self: Director)
	-- Back to exactly the pose baked into the place, so a stopped server and a
	-- freshly opened place look identical.
	for _, entry in PLATFORMS do
		local deck = self.geometry.rafts[entry.Suffix]
		if deck then
			local pose = self.rest.raftPose[entry.Suffix]
			if pose then
				deck.CFrame = pose
			end
		end
		for _, glow in self.geometry.glows[entry.Suffix] or {} do
			glow.Transparency = 0
		end
		for _, track in self.geometry.tracks[entry.Suffix] or {} do
			track.Transparency = 0
		end
	end
end

function EventDirector.start(self: Director, kind: string, now: number, duration: number)
	self.active = kind
	self.endsAt = now + duration
	self.startedAt = now
	-- Clear whatever ran before. Events never overlap, but a dropped stop must not
	-- leave low gravity or ice running underneath the next one.
	self:setGravity(self.normalGravity)
	for _, group in self.geometry.paths do
		for _, span in group do
			span.CanCollide = false
			span.Transparency = 1
		end
	end
	if kind == "LowGravity" then
		self:setGravity(self.lowGravity)
	elseif kind == "Slippery" then
		self:setFriction(self.slipperyFriction)
	elseif kind == "VanishingPaths" then
		setPaths(self, true)
	elseif kind == "MovingPlatforms" then
		self.parked = false
	end
end

function EventDirector.stop(self: Director)
	self.active = ""
	self.endsAt = 0
	self:setGravity(self.normalGravity)
	self:setFriction(self.normalFriction)
	setPaths(self, false)
	parkRafts(self)
	self.parked = true
end

-- Gravity is a property of the DataModel, which `workspace` *is*: writing it here
-- is the same write the engine does, and it is the single property the adapter's
-- own invariant check asserts on.
function EventDirector.setGravity(self: Director, value: number)
	local host: any = workspace
	host.Gravity = value
end

function EventDirector.setFriction(self: Director, value: number)
	-- Terrain friction is the only global surface control in the engine. Setting it
	-- is instantaneous and free, which is why "slippery" is a global event.
	for _, part in (workspace :: any):GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "BrainCell" then
			part.CustomPhysicalProperties = PhysicalProperties.new(.7, value, .5, 1, 1)
		end
	end
end

function EventDirector.step(self: Director, now: number, elapsed: number)
	if self.active == "" then
		return
	end
	if now >= self.endsAt then
		if self.active == "VanishingPaths" then
			-- The last two seconds blink, so nobody is standing on a span when it
			-- goes: a fair warning for a fair mechanic.
			local left = self.endsAt - now
			if left > -2 then
				setPaths(self, true)
				for _, group in self.geometry.paths do
					for _, span in group do
						span.Transparency = if math.floor(now * 6) % 2 == 0 then 0 else .45
					end
				end
			end
		end
		self:stop()
		return
	end
	if self.active == "MovingPlatforms" then
		for _, entry in PLATFORMS do
			local deck = self.geometry.rafts[entry.Suffix]
			if deck then
				local x, z = self:raftPose(entry, elapsed)
				deck.CFrame = CFrame.new(x, entry.Top - PLATFORM_HEIGHT / 2, z)
				self.raftsMoved += 1
			end
		end
	end
	-- The last three seconds of the vanishing path are visible as a blink.
	if self.active == "VanishingPaths" and self.endsAt - now < 3 then
		local on = math.floor(now * 4) % 2 == 0
		for _, group in self.geometry.paths do
			for _, span in group do
				span.Transparency = if on then 0 else .55
			end
		end
	end
end

-- Called on every phase change, whatever the event state says.
function EventDirector.reset(self: Director)
	self:stop()
end

return EventDirector
