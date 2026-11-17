--!nonstrict
-- Persistence for the things that survive a round: coins, the specimen log,
-- lifetime stats and cosmetic choices. Round score never lands here.
--
-- Design rules:
--   * The server is the only writer. The client can *ask* for a cosmetic change
--     (a halo, a colour) and the server validates and stores it; the client can
--     never write a number.
--   * Loading is lazy and cached. A player who joins while a round is live gets
--     their saved state the moment the round ends, never mid-round.
--   * Every write is schema-checked before it is saved, and every read is
--     repaired field by field, so one corrupt key cannot break a profile.
--   * DataStore calls are all pcall-protected with bounded retries. If the service
--     is unavailable the session continues in memory; nothing is lost that the
--     player did this session, it simply is not durable, and we say so in the log.
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Persistence = {}

local VERSION = 1
local MAX_RETRIES = 3
local RETRY_DELAY = 1.5

-- --------------------------------------------------------------------------- #
-- Namespace. Production has exactly one name and it never changes: existing
-- player keys (`p_<userId>`) live in it. An acceptance run must select a
-- DIFFERENT name, and only a name carrying this prefix is accepted for that.
-- `Persistence.new` refuses (asserts) anything else, so a typo cannot point a
-- test run at live progression. Selection is server-side only — see
-- `Persistence.resolveStoreName` and `Main.server`; no client input reaches it.
-- --------------------------------------------------------------------------- #
local PRODUCTION_STORE = "BrainrotArenaProfiles"
local ACCEPTANCE_PREFIX = "BrainrotArenaAcceptance_"

-- --------------------------------------------------------------------------- #
-- Loading states. A profile is only writable in LOADED, which is reached only
-- by a GetAsync that returned (or a confirmed nil, meaning a new player). Any
-- other state refuses writes, so an outage or a race can never replace a real
-- record with a default one.
-- --------------------------------------------------------------------------- #
local LOADING = "Loading"
local LOADED = "Loaded"
local FAILED = "Failed"
-- Set by `release` (player left). Late async work checks this and stops, so a
-- finished read cannot resurrect a disconnected session or write for it.
local LEAVING = "Leaving"

-- How long the shutdown drain is allowed to hold the server open. Roblox gives
-- every function bound with `game:BindToClose` up to 30 s before the instance is
-- terminated regardless; this budget stays well inside it and leaves room for a
-- slow final round trip. Kept in one place so the adapter and the tests agree.
local SHUTDOWN_BUDGET = 20
local SHUTDOWN_POLL = 0.1

-- The one definition of a valid profile. `sanitise` is the only way a profile is
-- built, so a hostile or corrupted table cannot reach gameplay code.
local DEFAULTS = {
	Version = VERSION,
	Coins = 0,
	Halo = "None",
	Specimens = {},      -- species -> count (session-persistent)
	Rounds = 0,
	Wins = 0,
	BestScore = 0,
	TotalScore = 0,
	Steals = 0,
	Lost = 0,
	Picked = 0,          -- lifetime pickups
}

local HALOS = { None = true, Cyan = true, Violet = true, Gold = true }

local function clampInt(value, low, high)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return low
	end
	return math.clamp(math.floor(value), low, high)
end

function Persistence.sanitise(raw)
	local profile = table.clone(DEFAULTS)
	profile.Specimens = {}
	if type(raw) ~= "table" then
		return profile
	end
	profile.Coins = clampInt(raw.Coins, 0, 1000000000)
	profile.Halo = if type(raw.Halo) == "string" and HALOS[raw.Halo] then raw.Halo else "None"
	profile.Rounds = clampInt(raw.Rounds, 0, 1000000000)
	profile.Wins = clampInt(raw.Wins, 0, 1000000000)
	profile.BestScore = clampInt(raw.BestScore, 0, 1000000)
	profile.TotalScore = clampInt(raw.TotalScore, 0, 1000000000)
	profile.Steals = clampInt(raw.Steals, 0, 1000000000)
	profile.Lost = clampInt(raw.Lost, 0, 1000000000)
	profile.Picked = clampInt(raw.Picked, 0, 1000000000)
	-- Only the six known species, and only plausible counts.
	if type(raw.Specimens) == "table" then
		for species, count in raw.Specimens do
			if type(species) == "string" and #species <= 16 and (count :: any) > 0 then
				profile.Specimens[species] = clampInt(count, 0, 100000)
			end
		end
	end
	-- Wins can never exceed rounds played.
	if profile.Wins > profile.Rounds then
		profile.Wins = profile.Rounds
	end
	return profile
end

-- Apply a round's outcome to a profile. This is the ONLY place that adds coins or
-- stats, and it takes the machine's own result, never a number from a client.
function Persistence.applyRound(profile, result)
	if type(profile) ~= "table" or type(result) ~= "table" then
		return profile
	end
	profile.Rounds += 1
	profile.TotalScore += clampInt(result.score, 0, 1000000)
	profile.Steals += clampInt(result.steals, 0, 1000000)
	profile.Lost += clampInt(result.lost, 0, 1000000)
	profile.Picked += clampInt(result.pickups, 0, 1000000)
	if result.score > profile.BestScore then
		profile.BestScore = clampInt(result.score, 0, 1000000)
	end
	if result.won then
		profile.Wins += 1
	end
	profile.Coins += clampInt(result.coins, 0, 100000)
	if type(result.collection) == "table" then
		for species, count in result.collection do
			if type(species) == "string" then
				profile.Specimens[species] = (profile.Specimens[species] or 0) + clampInt(count, 0, 1000)
			end
		end
	end
	return profile
end

-- --------------------------------------------------------------------------- #
-- Store
-- --------------------------------------------------------------------------- #

local Store = {}
Store.__index = Persistence

-- `options` is optional and every field is optional. The DEFAULTS matter:
--   * memoryOnly defaults to FALSE — a live server persists unless it is told not
--     to. (An earlier expression, `o.memoryOnly ~= false`, made `new({})` memory
--     only, so the production path never opened a DataStore at all.)
--   * Studio is the exception: it is memory-only unless `persistInStudio = true`
--     is passed explicitly, so local playtests never contend for the live keys.
--   * `readOnly = true` opens no DataStore at all. It exists for isolated tests
--     and offline tooling, not for the game.
--   * `storeName` selects the namespace. It defaults to production and is
--     validated by `Persistence.resolveStoreName`: only a name with the
--     acceptance prefix may differ from the production one. Passing the
--     acceptance name requires `acceptance = true` as well, so the two halves of
--     the switch must agree before a test run can write anywhere.
function Persistence.resolveStoreName(options)
	local o = options or {}
	local requested = o.storeName
	if requested == nil or requested == "" then
		if o.acceptance == true then
			-- An acceptance run that forgot its namespace must not fall back to
			-- production. Fail closed, loudly.
			error("acceptance persistence requires an explicit acceptance storeName", 2)
		end
		return PRODUCTION_STORE
	end
	if type(requested) ~= "string" then
		error("storeName must be a string", 2)
	end
	if requested == PRODUCTION_STORE then
		if o.acceptance == true then
			error("refusing to run an acceptance store against the production namespace", 2)
		end
		return PRODUCTION_STORE
	end
	if string.sub(requested, 1, #ACCEPTANCE_PREFIX) ~= ACCEPTANCE_PREFIX then
		error("unknown DataStore namespace (expected the acceptance prefix)", 2)
	end
	if o.acceptance ~= true then
		error("an acceptance namespace requires acceptance = true", 2)
	end
	if #requested <= #ACCEPTANCE_PREFIX then
		error("acceptance namespace needs a run id after the prefix", 2)
	end
	return requested
end

function Persistence.new(options)
	local o = options or {}
	local self = setmetatable({}, Store)
	-- Tests can force the degraded path (an unavailable DataStore) without
	-- needing to break the service itself.
	local forcedFailure = o.storeFail == true
	self.available = false
	self.store = nil
	self.profiles = {}       -- userId -> profile (cache: the session's truth)
	self.states = {}         -- userId -> LOADING | LOADED | FAILED | LEAVING
	self.generations = {}    -- userId -> monotonic token, invalidates stale async work
	self.savedAt = {}
	self.memoryOnly = (o.memoryOnly == true) or (o.readOnly == true)
		or (RunService:IsStudio() and o.persistInStudio ~= true)
	-- Resolved before any store is opened, and asserted here so a bad namespace
	-- fails at start-up instead of at the first write.
	self.storeName = Persistence.resolveStoreName(o)
	self.acceptance = o.acceptance == true
	self.writes = 0
	self.reads = 0
	self.errors = 0
	self.refusedSaves = 0
	-- Shutdown bookkeeping. `inflight` is the single-flight register: a player's
	-- id is present while that profile has a write in progress, so a second save
	-- (a concurrent PlayerRemoving and BindToClose) attaches instead of stacking.
	self.inflight = {}      -- userId -> true
	self.lastPayload = {}   -- userId -> the exact table last written, for dedupe
	self.shutdownSaves = 0
	self.shutdownSkipped = 0
	self.shutdownFailed = 0
	self.shuttingDown = false
	-- Monotonic count of successful writes. Comparing this before and after a
	-- drain is how the report knows a write actually landed (comparing payload
	-- identity is wrong: a retry reuses the same table).
	self.writeSerial = 0

	if not self.memoryOnly then
		local ok, result = pcall(function()
			if forcedFailure then
				error("DataStore forced unavailable")
			end
			return DataStoreService:GetDataStore(self.storeName)
		end)
		if ok and result then
			self.store = result
			self.available = true
		else
			self.errors += 1
			warn("[Brainrot] DataStore unavailable; this server runs in memory only")
		end
	end
	return self
end

function Persistence.key(userId)
	return "p_" .. tostring(userId)
end

function Persistence.profile(self, userId)
	return self.profiles[userId]
end

-- The load state for a player: LOADING, LOADED, FAILED, LEAVING, or nil when
-- they were never seen. Only LOADED makes `save` write.
function Persistence.state(self, userId)
	return self.states[userId]
end

-- True when this profile may be written. Kept as one function so every caller
-- (round payout, halo purchase, PlayerRemoving) agrees on the rule.
function Persistence.isWritable(self, userId)
	return self.states[userId] == LOADED and self.profiles[userId] ~= nil
end

-- Marks a player as gone. Bumps the generation so any in-flight read for them
-- is discarded when it lands, and drops the cache entry. A later `load` for the
-- same id starts a fresh generation, so a fast rejoin is independent of the
-- session that just ended.
function Persistence.release(self, userId)
	self.generations[userId] = (self.generations[userId] or 0) + 1
	self.states[userId] = LEAVING
	self.profiles[userId] = nil
end

-- Forget a player entirely (the adapter calls this after its final save).
function Persistence.forget(self, userId)
	self.generations[userId] = (self.generations[userId] or 0) + 1
	self.states[userId] = nil
	self.profiles[userId] = nil
	self.savedAt[userId] = nil
end

-- Read one profile. Returns the cached copy immediately and refreshes it in the
-- background; the caller never yields on a DataStore.
--
-- States, and why each matters:
--   memory-only store  -> LOADED immediately. There is nothing durable to lose,
--                         so a writable default is correct (Studio playtesting).
--   read returned data -> LOADED, merged over anything earned meanwhile.
--   read returned nil  -> LOADED. A confirmed new player: a default profile is
--                         the real record and may be written.
--   read failed        -> FAILED. The profile stays non-writable, so the next
--                         `save` is refused instead of overwriting the record we
--                         could not read. A caller may retry with `retry = true`.
function Persistence.load(self, userId, callback, options)
	local o = options or {}
	local existing = self.states[userId]
	if existing == LOADED then
		local cached = self.profiles[userId]
		if callback then callback(cached) end
		return cached
	end
	if existing == LOADING then
		-- A load is already in flight for this session; never start a second one.
		return self.profiles[userId]
	end
	if existing == FAILED and o.retry ~= true then
		return self.profiles[userId]
	end

	-- New session (or an explicit retry): claim a generation. Anything that
	-- lands from an older generation is ignored below.
	local generation = (self.generations[userId] or 0) + 1
	self.generations[userId] = generation
	-- The cached shell is only a display value while LOADING; `writable` is
	-- false, so no caller can persist it.
	local shell = table.clone(DEFAULTS)
	shell.Specimens = {}
	self.profiles[userId] = shell
	self.states[userId] = LOADING

	if not self.store then
		self.states[userId] = LOADED
		if callback then callback(self.profiles[userId]) end
		return self.profiles[userId]
	end

	task.spawn(function()
		local function current(): boolean
			return self.generations[userId] == generation
		end
		local key = Persistence.key(userId)
		local data = nil
		local ok = false
		for attempt = 1, MAX_RETRIES do
			if not current() then
				return
			end
			ok = pcall(function()
				local value = self.store:GetAsync(key)
				data = value
				return true
			end)
			if ok then
				self.reads += 1
				break
			end
			self.errors += 1
			warn(string.format("[Brainrot] profile read failed (attempt %d/%d)", attempt, MAX_RETRIES))
			if attempt < MAX_RETRIES then
				task.wait(RETRY_DELAY * attempt)
			end
		end
		-- The player left, or was reloaded, while this was in flight. Do not
		-- touch the cache and do not call back: a stale completion must not
		-- resurrect a disconnected session.
		if not current() then
			return
		end
		if not ok then
			-- FAILED is terminal until someone asks for a retry. The shell stays
			-- readable for the UI but `writable` is false, so it can never be
			-- saved over the record we failed to read.
			self.states[userId] = FAILED
			self.errors += 1
			warn("[Brainrot] profile unavailable; this session will not be saved")
			if callback then callback(self.profiles[userId], FAILED) end
			return
		end
		-- ok with data == nil is a confirmed new player: the default is the truth.
		-- Shape the merge against what the cache holds now (it may have been
		-- touched while the read was in flight).
		local merged = Persistence.sanitise(data)
		merged = Persistence.merge(merged, self.profiles[userId])
		if not current() then
			return
		end
		self.profiles[userId] = merged
		self.states[userId] = LOADED
		if callback then callback(merged, LOADED) end
	end)
	return self.profiles[userId]
end

-- Keep the larger of two values for monotonic counters and the union of the
-- specimen log, so a slow load can never erase a session's progress.
function Persistence.merge(older, newer)
	if type(older) ~= "table" then
		return Persistence.sanitise(newer)
	end
	if type(newer) ~= "table" then
		return Persistence.sanitise(older)
	end
	local out = Persistence.sanitise(older)
	out.Coins = math.max(out.Coins, clampInt(newer.Coins, 0, 1000000000))
	for _, field in { "Rounds", "Wins", "BestScore", "TotalScore", "Steals", "Lost", "Picked" } do
		out[field] = math.max(out[field], clampInt(newer[field], 0, 1000000000))
	end
	if type(newer.Specimens) == "table" then
		for species, count in newer.Specimens do
			if type(species) == "string" then
				out.Specimens[species] = math.max(out.Specimens[species] or 0, clampInt(count, 0, 100000))
			end
		end
	end
	if out.Halo == "None" and type(newer.Halo) == "string" and HALOS[newer.Halo] then
		out.Halo = newer.Halo
	end
	return out
end

-- Save one profile. Schema-checked, retried, and never raises into a gameplay
-- loop: a failed save is logged and retried on the next save point.
--
-- Refuses (returns false, reason "not-ready") unless the profile reached LOADED.
-- That single rule is what makes a DataStore outage harmless: a session whose
-- read failed keeps playing in memory, and nothing it does can replace the real
-- record. The in-memory profile is never mutated by a failed write either, so a
-- later successful save is still correct.
function Persistence.save(self, userId, callback)
	local reason, write = Persistence.beginSave(self, userId)
	if not reason then
		self.refusedSaves += 1
		if callback then callback(false, write) end
		return false, write
	end
	if write == nil then
		-- Joined an in-flight write, or the payload is unchanged.
		if callback then callback(true, "joined") end
		return true, "joined"
	end
	-- Queued: the caller never yields on a DataStore, so a round payout or a
	-- halo purchase cannot stall the authority loop.
	task.spawn(write)
	return true, "queued"
end

-- Await a write for one player, for callers that are allowed to yield: the
-- shutdown drain, which is inside `BindToClose` and must not return until the
-- data is durable. Returns (wrote, reason) where `wrote` reports whether the
-- record is now durably up to date.
function Persistence.saveAwait(self, userId)
	local reason, write = Persistence.beginSave(self, userId)
	if not reason then
		return false, write
	end
	if write == nil then
		-- An in-flight write for this player is already the newest state. The
		-- drain waits for the register to clear, so this is never returned to
		-- the shutdown path before the bytes are durable.
		return true, reason
	end
	return write(), reason
end

-- Validate, dedupe and claim the single-flight slot for one player.
-- Returns (ok, write-or-reason):
--   false, reason  -> refused; nothing was claimed
--   true, nil      -> nothing to do (in flight, or unchanged since last write)
--   true, function -> the caller owns the write and must run it exactly once
function Persistence.beginSave(self, userId)
	if not self:isWritable(userId) then
		return false, "not-ready"
	end
	-- Single flight. A PlayerRemoving save and a BindToClose save for the same
	-- player are the same write, so the second attaches to the first rather than
	-- racing it: two unordered SetAsync calls could otherwise land out of order
	-- and persist an older table.
	if self.inflight[userId] then
		return true, nil
	end
	local generation = self.generations[userId]
	local payload = Persistence.sanitise(self.profiles[userId])
	-- Nothing changed since the last successful write, so re-writing the same
	-- bytes only burns request budget. A failed write never records a payload,
	-- so a retry is never suppressed.
	if self.lastPayload[userId] ~= nil and Persistence.equal(self.lastPayload[userId], payload) then
		return true, nil
	end
	if not self.store then
		-- Memory-only (Studio): there is nothing durable to write. Recording the
		-- payload keeps the dedupe honest for repeated saves in one session.
		self.savedAt[userId] = os.time()
		self.lastPayload[userId] = payload
		return true, nil
	end

	self.inflight[userId] = true
	local write = function(): boolean
		local key = Persistence.key(userId)
		for attempt = 1, MAX_RETRIES do
			if self.generations[userId] ~= generation then
				-- The player left or reloaded; abandoning this write is correct.
				self.inflight[userId] = nil
				return false
			end
			local ok, result = pcall(function()
				return self.store:SetAsync(key, payload)
			end)
			if ok then
				self.writes += 1
				self.writeSerial += 1
				self.savedAt[userId] = os.time()
				self.lastPayload[userId] = payload
				self.inflight[userId] = nil
				return true
			end
			self.errors += 1
			warn(string.format("[Brainrot] profile write failed (attempt %d/%d)", attempt, MAX_RETRIES))
			if attempt < MAX_RETRIES then
				task.wait(RETRY_DELAY * attempt)
			end
		end
		self.inflight[userId] = nil
		return false
	end
	return true, write
end

-- Structural equality for two sanitised profiles. Used only to decide whether a
-- write would change anything; both arguments came from `sanitise`, so the shape
-- is known and small (flat fields plus one string-keyed map).
function Persistence.equal(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in a do
		if type(value) ~= "table" then
			if b[key] ~= value then
				return false
			end
		end
	end
	for key, value in b do
		if type(value) ~= "table" then
			if a[key] ~= value then
				return false
			end
		end
	end
	local sa, sb = a.Specimens, b.Specimens
	if type(sa) ~= "table" or type(sb) ~= "table" then
		return false
	end
	for species, count in sa do
		if sb[species] ~= count then
			return false
		end
	end
	for species in sb do
		if sa[species] == nil then
			return false
		end
	end
	return true
end

-- --------------------------------------------------------------------------- #
-- Shutdown.
--
-- Roblox runs every `game:BindToClose` callback concurrently and terminates the
-- instance at most 30 s after the close begins, whether or not the callbacks have
-- finished. Two consequences shape this code:
--
--   * The drain must be BOUNDED. It waits for outstanding writes only until
--     SHUTDOWN_BUDGET, then returns and lets the server die with whatever is
--     durable. Waiting longer does not buy more time; the engine ignores it.
--   * It must not start writes it cannot finish. Only profiles that are already
--     LOADED are flushed — the same `isWritable` rule every other save point
--     uses — so a shutdown can never turn an unread profile into a default record.
--
-- A player saved by PlayerRemoving a moment earlier has nothing to do here: the
-- payload is unchanged, so `beginSave` returns no work and no duplicate
-- SetAsync is issued.
-- --------------------------------------------------------------------------- #

-- Save every writable profile and wait, bounded, for those writes to finish.
-- Returns a small report; the adapter prints it so a live run is auditable.
function Persistence.shutdownSave(self, budget)
	if self.shuttingDown then
		return { players = 0, saved = 0, skipped = 0, failed = 0, pending = 0, already = true }
	end
	self.shuttingDown = true
	local limit = budget or SHUTDOWN_BUDGET
	local ids: { number } = {}
	for userId, state in self.states do
		if state == LOADED and self.profiles[userId] ~= nil then
			table.insert(ids, userId)
		end
	end
	table.sort(ids)
	local report = { players = #ids, saved = 0, skipped = 0, failed = 0, pending = 0, already = false }
	if #ids == 0 then
		return report
	end

	-- Kick off every write first so they overlap, then wait once for all of them.
	local serialBefore = self.writeSerial
	local started: { [number]: boolean } = {}
	for _, userId in ids do
		local ok, write = Persistence.beginSave(self, userId)
		if not ok then
			report.failed += 1
		elseif write == nil then
			-- Already in flight (a concurrent PlayerRemoving), or unchanged since
			-- the last successful write. Either way, not a second SetAsync.
			report.skipped += 1
		else
			started[userId] = true
			task.spawn(write)
		end
	end

	local deadline = os.clock() + limit
	while os.clock() < deadline do
		local busy = false
		for _, userId in ids do
			if self.inflight[userId] then
				busy = true
				break
			end
		end
		if not busy then
			break
		end
		task.wait(SHUTDOWN_POLL)
	end

	local landed = self.writeSerial - serialBefore
	-- `landed` can exceed the number of players when a previously queued write
	-- (a concurrent PlayerRemoving) also completed during the drain. Never let
	-- that inflate the count above the number actually started here.
	report.saved = math.min(landed, (function()
		local count = 0
		for _ in started do count += 1 end
		return count
	end)())
	report.failed += (function()
		local count = 0
		for _ in started do count += 1 end
		return count
	end)() - report.saved
	for _, userId in ids do
		if self.inflight[userId] then
			-- Still writing when the budget ran out. The engine terminates the
			-- instance regardless, so report it rather than claiming success.
			report.pending += 1
		end
	end
	self.shutdownSaves += report.saved
	self.shutdownSkipped += report.skipped
	self.shutdownFailed += report.failed
	return report
end

-- A cosmetic purchase. `cost` is a server constant, never a client argument.
function Persistence.buyHalo(self, userId, halo, cost)
	local profile = self.profiles[userId]
	if not profile then
		return false, "no-profile"
	end
	if not HALOS[halo] or halo == "None" then
		return false, "unknown-halo"
	end
	if profile.Halo == halo then
		return false, "already-owned"
	end
	if profile.Coins < cost then
		return false, "poor"
	end
	profile.Coins -= cost
	profile.Halo = halo
	return true, "ok"
end

function Persistence.stats(self)
	local loading, failed, loaded = 0, 0, 0
	for _, state in self.states do
		if state == LOADING then
			loading += 1
		elseif state == FAILED then
			failed += 1
		elseif state == LOADED then
			loaded += 1
		end
	end
	return {
		available = self.available, memoryOnly = self.memoryOnly,
		storeName = self.storeName, acceptance = self.acceptance,
		reads = self.reads, writes = self.writes, errors = self.errors,
		refusedSaves = self.refusedSaves,
		loading = loading, loaded = loaded, failed = failed,
		tracked = (function()
			local count = 0
			for _ in self.profiles do count += 1 end
			return count
		end)(),
	}
end

return Persistence
