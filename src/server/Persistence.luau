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
	if not self.profiles[userId] then
		return false, "missing"
	end
	if not self:isWritable(userId) then
		self.refusedSaves += 1
		if callback then callback(false, "not-ready") end
		return false, "not-ready"
	end
	local profile = self.profiles[userId]
	local generation = self.generations[userId]
	local payload = Persistence.sanitise(profile)
	if not self.store then
		self.savedAt[userId] = os.time()
		if callback then callback(true) end
		return true, "ok"
	end
	task.spawn(function()
		local key = Persistence.key(userId)
		for attempt = 1, MAX_RETRIES do
			if self.generations[userId] ~= generation then
				-- The player left or reloaded; abandoning this write is correct.
				if callback then callback(false, "stale") end
				return
			end
			local ok, result = pcall(function()
				return self.store:SetAsync(key, payload)
			end)
			if ok then
				self.writes += 1
				self.savedAt[userId] = os.time()
				if callback then callback(true, result) end
				return
			end
			self.errors += 1
			warn(string.format("[Brainrot] profile write failed (attempt %d/%d)", attempt, MAX_RETRIES))
			if attempt < MAX_RETRIES then
				task.wait(RETRY_DELAY * attempt)
			end
		end
		if callback then callback(false, "failed") end
	end)
	return true, "ok"
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
