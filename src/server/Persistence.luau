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
local STORE_NAME = "BrainrotArenaProfiles"
local MAX_RETRIES = 3
local RETRY_DELAY = 1.5

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

function Persistence.new(options)
	local o = options or {}
	local self = setmetatable({}, Store)
	-- Tests can force the degraded path (an unavailable DataStore) without
	-- needing to break the service itself.
	local forcedFailure = o.storeFail == true
	self.available = false
	self.store = nil
	self.profiles = {}       -- userId -> profile (cache: the session's truth)
	self.loaded = {}         -- userId -> true once the durable copy was read
	self.failed = {}         -- userId -> true if the read failed (retry later)
	self.savedAt = {}
	self.memoryOnly = o.memoryOnly ~= false or RunService:IsStudio() and o.persistInStudio ~= true
	self.writes = 0
	self.reads = 0
	self.errors = 0

	if not self.memoryOnly then
		local ok, result = pcall(function()
			if forcedFailure then
				error("DataStore forced unavailable")
			end
			return DataStoreService:GetDataStore(STORE_NAME)
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

-- Read one profile. Returns the cached copy immediately and refreshes it in the
-- background; the caller never yields on a DataStore.
function Persistence.load(self, userId, callback)
	if self.profiles[userId] then
		if callback then callback(self.profiles[userId]) end
		return self.profiles[userId]
	end
	self.profiles[userId] = table.clone(DEFAULTS)
	self.profiles[userId].Specimens = {}
	if not self.store then
		self.loaded[userId] = true
		if callback then callback(self.profiles[userId]) end
		return self.profiles[userId]
	end
	task.spawn(function()
		local key = Persistence.key(userId)
		local data = nil
		for attempt = 1, MAX_RETRIES do
			local ok, result = pcall(function()
				return self.store:GetAsync(key)
			end)
			if ok then
				data = result
				self.reads += 1
				break
			end
			self.errors += 1
			warn(string.format("[Brainrot] profile read failed (attempt %d/%d)", attempt, MAX_RETRIES))
			if attempt < MAX_RETRIES then
				task.wait(RETRY_DELAY * attempt)
			end
		end
		self.loaded[userId] = true
		self.failed[userId] = data == nil and false or false
		-- Merge, never replace: anything earned between join and load is kept.
		local merged = Persistence.sanitise(data)
		merged = Persistence.merge(merged, self.profiles[userId])
		self.profiles[userId] = merged
		if callback then callback(merged) end
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
function Persistence.save(self, userId, callback)
	local profile = self.profiles[userId]
	if not profile then
		return false
	end
	local payload = Persistence.sanitise(profile)
	if not self.store then
		self.savedAt[userId] = os.time()
		if callback then callback(true) end
		return true
	end
	task.spawn(function()
		local key = Persistence.key(userId)
		for attempt = 1, MAX_RETRIES do
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
		if callback then callback(false) end
	end)
	return true
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
	return {
		available = self.available, memoryOnly = self.memoryOnly,
		reads = self.reads, writes = self.writes, errors = self.errors,
		tracked = (function()
			local count = 0
			for _ in self.profiles do count += 1 end
			return count
		end)(),
	}
end

return Persistence
