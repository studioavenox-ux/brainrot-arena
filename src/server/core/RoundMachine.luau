--!strict
-- Engine-independent authority. No task.wait(), remotes, or Roblox objects live here.
--
-- Phase 5 additions, all inside the same non-yielding model:
--   * staged rounds      Collect -> Compete -> Chaos -> Final Rush, each boundary
--                        banks every player's carried cells (see `bank`)
--   * survival events    a scheduled timeline (low gravity + one rotating wildcard)
--                        with a public warning window, so timing is predictable
--   * stealing           short-range tag that moves ONE *carried* cell between two
--                        players. Banked score can never be taken, and nothing
--                        leaves the round: the total stays conserved.
local RoundMachine = {}
RoundMachine.__index = RoundMachine

export type Timing = {
	Intermission: number, Round: number, Results: number,
	ChaosStart: number, ChaosDuration: number, Warning: number,
}
export type Stage = { Name: string, At: number, Label: string }
export type StealRules = {
	Range: number, Cooldown: number, Protection: number, Immunity: number, RepeatWindow: number,
}
export type Settings = {
	Timing: Timing,
	Stages: { Stage }?, Chaos: { Kinds: { string } },
	Steal: StealRules,
	ParticipationCoins: number, CoinsPerPoint: number, WinnerCoins: number, HaloCost: number,
	SlipperyFriction: number?, RushRespawn: number?, FinalRespawn: number?,
}
export type Player = {
	id: number, name: string, score: number, coins: number, wins: number, pickups: number,
	participating: boolean, haloOwned: boolean, haloEquipped: boolean,
	collection: { [string]: number },
	-- Round inventory. `carried` holds the values not yet banked, so a stolen cell
	-- can be removed from exactly the right place.
	carried: { number }, carriedValue: number,
	stealReadyAt: number, protectedUntil: number, immuneUntil: number,
	lastVictim: number, lastStealAt: number, steals: number, lost: number,
}
export type Row = {
	id: number, name: string, score: number, coins: number, wins: number, pickups: number,
	haloOwned: boolean, haloEquipped: boolean, collection: { [string]: number },
	collected: number, carried: number, carriedValue: number,
	steals: number, lost: number, stealReadyAt: number, protectedUntil: number, immuneUntil: number,
}
export type Results = {
	roundId: number, winners: { Row }, topScore: number, rewards: { [string]: number },
}
export type Effect = {
	kind: string, phase: string?, active: boolean?, event: string?, stage: string?,
	label: string?, at: number?, endsAt: number?,
}
export type Scheduled = { Kind: string, StartsAt: number, EndsAt: number, WarningAt: number }
export type StealOutcome = 'ok' | 'inactive-round' | 'invalid-player' | 'missing-player'
	| 'self' | 'cooldown' | 'protected' | 'immune' | 'repeat' | 'out-of-range' | 'empty'

type Fields = {
	config: Settings, players: { [number]: Player }, phase: string, roundId: number,
	phaseStartedAt: number, phaseEndsAt: number, eventActive: boolean, eventEndsAt: number,
	eventKind: string, eventFinished: boolean, eventWarning: string, warningEndsAt: number,
	stage: string, stageIndex: number, stageEndsAt: number, schedule: { Scheduled },
	lastNow: number, lastResults: Results?,
	choose: (number) -> number, chaosKind: string,
}
export type Machine = typeof(setmetatable({} :: Fields, RoundMachine))

local function finite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

-- Public names for each event. The client prints these verbatim, so every client
-- shows the same words for the same server event.
local LABEL: { [string]: string } = {
	LowGravity = "LOW GRAVITY",
	BouncyWorld = "BOUNCY WORLD",
	SlipperyChaos = "SLIPPERY CHAOS",
	BrainCellRush = "BRAIN CELL RUSH",
}

RoundMachine.Label = LABEL

local DEFAULT_STAGES: { Stage } = {
	{ Name = "Collect", At = 0, Label = "COLLECT" },
	{ Name = "Compete", At = 45, Label = "COMPETE" },
	{ Name = "Chaos", At = 105, Label = "CHAOS" },
	{ Name = "Final", At = 150, Label = "FINAL RUSH" },
}
local DEFAULT_KINDS = { "LowGravity", "BouncyWorld", "SlipperyChaos", "BrainCellRush" }

-- `choose(n)` returns an integer in 1..n. The server passes its own RNG; tests pass a
-- scripted one. Defaults to math.random so the pure module runs standalone.
function RoundMachine.new(config: Settings, choose: ((number) -> number)?): Machine
	assert(config.Timing.Intermission > 0 and config.Timing.Round > 0 and config.Timing.Results > 0, "Positive phase durations required")
	assert(config.Timing.ChaosStart >= 0 and config.Timing.ChaosDuration > 0, "Invalid Chaos Event timing")
	assert(config.Timing.ChaosStart + config.Timing.ChaosDuration < config.Timing.Round, "Chaos event must fit inside the round")
	assert(#(config.Stages or DEFAULT_STAGES) > 0, "At least one stage required")
	assert((config.Stages or DEFAULT_STAGES)[1].At == 0, "The first stage must start at zero")
	-- A config can legitimately carry a longer timeline than the round it is paired
	-- with (a quick-test round is shorter than the stage plan). Boundaries past the
	-- deadline are dropped rather than trimmed, so a stage never starts at an instant
	-- the round cannot reach.
	local stages: { Stage } = {}
	for _, stage in config.Stages or DEFAULT_STAGES do
		assert(stage.At >= 0, "Stage outside the round")
		if stage.At < config.Timing.Round then
			if #stages > 0 then
				assert(stage.At > stages[#stages].At, "Stages must be strictly increasing")
			end
			table.insert(stages, stage)
		end
	end
	local kinds = if config.Chaos then config.Chaos.Kinds else DEFAULT_KINDS
	assert(#kinds > 0, "The Chaos pool needs at least one kind")
	local seen: { [string]: boolean } = {}
	for _, kind in kinds do
		assert(LABEL[kind] ~= nil, "Unknown Chaos Event kind: " .. tostring(kind))
		assert(not seen[kind], "Duplicate Chaos Event kind: " .. kind)
		seen[kind] = true
	end
	config = table.clone(config) :: Settings
	config.Stages = stages
	config.Chaos = { Kinds = table.clone(kinds) }
	assert(config.Steal.Range > 0 and config.Steal.Cooldown > 0, "Invalid steal rules")
	return setmetatable({
		config = config, players = {}, phase = "Waiting", roundId = 0,
		phaseStartedAt = 0, phaseEndsAt = 0, eventActive = false, eventEndsAt = 0,
		eventKind = "", eventFinished = false, eventWarning = "", warningEndsAt = 0,
		stage = stages[1].Name, stageIndex = 1, stageEndsAt = 0, schedule = {},
		lastNow = 0, lastResults = nil,
		choose = choose or function(n: number): number return math.random(1, n) end,
		chaosKind = "",
	}, RoundMachine)
end

function RoundMachine.addPlayer(self: Machine, id: number, name: string): boolean
	-- Studio local clients use negative UserIds. Never reject those.
	if not finite(id) or id % 1 ~= 0 or id == 0 or self.players[id] then
		return false
	end
	self.players[id] = {
		id = id, name = string.sub(name, 1, 50), score = 0, coins = 0, wins = 0, pickups = 0,
		participating = self.phase == "Playing", haloOwned = false, haloEquipped = false,
		collection = {}, carried = {}, carriedValue = 0,
		-- A player who joins mid-round is protected for the usual spawn window.
		stealReadyAt = 0, protectedUntil = 0, immuneUntil = 0,
		lastVictim = 0, lastStealAt = -math.huge, steals = 0, lost = 0,
	}
	if self.phase == "Playing" then
		self.players[id].protectedUntil = self.lastNow + self.config.Steal.Protection
	end
	return true
end

function RoundMachine.removePlayer(self: Machine, id: number)
	self.players[id] = nil
end

function RoundMachine.isParticipating(self: Machine, id: number): boolean
	local player = self.players[id]
	return self.phase == "Playing" and player ~= nil and player.participating
end

-- Spawn / respawn protection. Called by the server when a character (re)spawns or
-- is routed into the arena, so the window is real rather than wall-clock guesswork.
function RoundMachine.spawnProtect(self: Machine, id: number, now: number)
	local player = self.players[id]
	if player then
		player.protectedUntil = now + self.config.Steal.Protection
	end
end

-- --------------------------------------------------------------------------- #
-- Inventory: carried (stealable) vs banked (safe). `score` is always the sum of
-- both, so nothing a player collected is ever lost — a steal only moves it.
-- --------------------------------------------------------------------------- #
local function bankPlayer(player: Player): number
	local amount = player.carriedValue
	table.clear(player.carried)
	player.carriedValue = 0
	return amount
end

-- Bank everything now. Returns the value that became safe.
function RoundMachine.bank(self: Machine, id: number): number
	local player = self.players[id]
	if not player then
		return 0
	end
	return bankPlayer(player)
end

function RoundMachine.carriedValue(self: Machine, id: number): number
	local player = self.players[id]
	return if player then player.carriedValue else 0
end

-- `species` is the character the player actually collected. It is recorded for the
-- collection screen only: it never changes the reward, which stays pinned to the
-- server's denomination table.
function RoundMachine.award(
	self: Machine,
	id: number,
	value: number,
	roundId: number,
	species: string?
): boolean
	if roundId ~= self.roundId or not self:isParticipating(id) then
		return false
	end
	-- Only the server's three collectible denominations are permitted.
	if value ~= 1 and value ~= 5 and value ~= 10 then
		return false
	end
	local player = self.players[id]
	player.score += value
	player.pickups += 1
	-- Every award is carried until the next stage boundary; that is the risk window.
	table.insert(player.carried, value)
	player.carriedValue += value
	if species and species ~= "" then
		player.collection[species] = (player.collection[species] or 0) + 1
	end
	return true
end

-- --------------------------------------------------------------------------- #
-- Stealing. The server resolves distance and eligibility; this function only
-- decides. `distance` is passed in so the rule stays engine-independent.
-- --------------------------------------------------------------------------- #
function RoundMachine.stealBlockedReason(self: Machine, id: number, now: number): string?
	local player = self.players[id]
	if not player then
		return "missing-player"
	end
	if now < player.protectedUntil then
		return "protected"
	end
	if now < player.stealReadyAt then
		return "cooldown"
	end
	if now < player.immuneUntil then
		return "immune"
	end
	return nil
end

function RoundMachine.canSteal(self: Machine, id: number, now: number): boolean
	return self:stealBlockedReason(id, now) == nil and self:isParticipating(id)
end

function RoundMachine.trySteal(
	self: Machine,
	thiefId: number,
	victimId: number,
	distance: number,
	now: number,
	roundId: number
): (StealOutcome, number)
	if roundId ~= self.roundId or self.phase ~= "Playing" then
		return "inactive-round", 0
	end
	if not finite(thiefId) or not finite(victimId) or thiefId == 0 or victimId == 0 then
		return "invalid-player", 0
	end
	if thiefId == victimId then
		return "self", 0
	end
	local thief, victim = self.players[thiefId], self.players[victimId]
	if not thief or not victim then
		return "missing-player", 0
	end
	if not thief.participating or not victim.participating then
		return "missing-player", 0
	end
	if not finite(distance) or distance > self.config.Steal.Range then
		return "out-of-range", 0
	end
	local blocked = self:stealBlockedReason(thiefId, now)
	if blocked then
		return (blocked :: any) :: StealOutcome, 0
	end
	-- The victim needs their own protection too: no tagging a player who just spawned.
	if now < victim.protectedUntil or now < victim.immuneUntil then
		return "immune", 0
	end
	-- No repeated unfair targeting: the same pair cannot re-tag inside the window.
	if thief.lastVictim == victimId and now - thief.lastStealAt < self.config.Steal.RepeatWindow then
		return "repeat", 0
	end
	if #victim.carried == 0 then
		return "empty", 0
	end
	-- Steal the biggest cell the victim is carrying; ties take the first.
	local best = 1
	for index = 2, #victim.carried do
		if victim.carried[index] > victim.carried[best] then
			best = index
		end
	end
	local value = victim.carried[best]
	table.remove(victim.carried, best)
	victim.carriedValue -= value
	if math.abs(victim.carriedValue) < 1e-6 then
		victim.carriedValue = 0
	end
	victim.score -= value
	victim.immuneUntil = now + self.config.Steal.Immunity
	victim.lost += value

	-- The cell arrives in the thief's own carried pile, so it can be taken back.
	table.insert(thief.carried, value)
	thief.carriedValue += value
	thief.score += value
	thief.steals += 1
	thief.stealReadyAt = now + self.config.Steal.Cooldown
	thief.lastVictim = victimId
	thief.lastStealAt = now
	return "ok", value
end

-- Number of distinct characters collected this session (0-6).
function RoundMachine.distinct(self: Machine, id: number): number
	local player = self.players[id]
	if not player then
		return 0
	end
	local count = 0
	for _, amount in player.collection do
		if amount > 0 then
			count += 1
		end
	end
	return count
end

-- Persistent profile -> round session. The machine still owns the live numbers
-- (so a purchase is atomic inside the round), but they start from the saved copy
-- and are written back after every change.
function RoundMachine.seedProfile(self: Machine, id: number, coins: number, halo: string): boolean
	local player = self.players[id]
	if not player then
		return false
	end
	player.coins = math.max(0, math.floor(coins))
	player.haloOwned = halo ~= nil and halo ~= "None" and halo ~= ""
	player.haloEquipped = player.haloOwned
	return true
end

-- What the adapter needs to persist after a halo purchase / equip.
function RoundMachine.cosmetics(self: Machine, id: number): (number, string)
	local player = self.players[id]
	if not player then
		return 0, "None"
	end
	return player.coins, if player.haloEquipped or player.haloOwned then "Cyan" else "None"
end

function RoundMachine.haloAction(self: Machine, id: number): (boolean, string)
	local player = self.players[id]
	if not player then
		return false, "Player missing"
	end
	if player.haloOwned then
		player.haloEquipped = not player.haloEquipped
		return true, if player.haloEquipped then "Halo equipped" else "Halo unequipped"
	end
	if player.coins < self.config.HaloCost then
		return false, "Not enough coins — collect cells to earn them"
	end
	player.coins -= self.config.HaloCost
	player.haloOwned = true
	player.haloEquipped = true
	return true, "Pulse Halo unlocked for this session!"
end

function RoundMachine.rows(self: Machine): { Row }
	local rows: { Row } = {}
	for _, player in self.players do
		local collection: { [string]: number } = {}
		local collected = 0
		for species, amount in player.collection do
			collection[species] = amount
			if amount > 0 then
				collected += 1
			end
		end
		table.insert(rows, {
			id = player.id, name = player.name, score = player.score, coins = player.coins,
			wins = player.wins, pickups = player.pickups,
			haloOwned = player.haloOwned, haloEquipped = player.haloEquipped,
			collection = collection, collected = collected,
			carried = #player.carried, carriedValue = player.carriedValue,
			steals = player.steals, lost = player.lost,
			stealReadyAt = player.stealReadyAt, protectedUntil = player.protectedUntil,
			immuneUntil = player.immuneUntil,
		})
	end
	table.sort(rows, function(a: Row, b: Row)
		return if a.score == b.score then a.id < b.id else a.score > b.score
	end)
	return rows
end

function RoundMachine.finishRound(self: Machine)
	local rows = self:rows()
	local topScore = if rows[1] then rows[1].score else 0
	local winners: { Row } = {}
	local rewards: { [string]: number } = {}
	for _, row in rows do
		local player = self.players[row.id]
		if player.participating then
			local won = topScore > 0 and row.score == topScore
			local amount = self.config.ParticipationCoins + row.score * self.config.CoinsPerPoint
			if won then
				amount += self.config.WinnerCoins
				player.wins += 1
				table.insert(winners, row)
			end
			player.coins += amount
			rewards[tostring(row.id)] = amount
		end
		-- Round inventory never survives the round; the score that already counted
		-- it is what gets paid and recorded.
		bankPlayer(player)
		player.participating = false
	end
	self.lastResults = { roundId = self.roundId, winners = winners, topScore = topScore, rewards = rewards }
end

-- Which stage an elapsed time falls in. Pure, so both the machine and tests agree.
function RoundMachine.stageAt(self: Machine, elapsed: number): (number, Stage)
	local stages = self.config.Stages or DEFAULT_STAGES
	local index = 1
	for position, stage in stages do
		if elapsed >= stage.At then
			index = position
		end
	end
	return index, stages[index]
end

-- Draw the single Chaos Event for a round. Uniform over the configured pool, decided
-- on the server at round start, and sent to clients inside the snapshot.
function RoundMachine.drawChaos(self: Machine): string
	local kinds = self.config.Chaos.Kinds
	local raw = self.choose(#kinds)
	local index = if finite(raw) then math.clamp(math.floor(raw), 1, #kinds) else 1
	return kinds[index]
end

-- The round's timeline: exactly one window, warned in advance. A kind can be given
-- explicitly (tests, replays); the live machine uses the kind drawn for this round.
function RoundMachine.buildSchedule(self: Machine, kind: string?): { Scheduled }
	local chosen = kind or self.chaosKind
	if chosen == "" then
		return {}
	end
	local start = self.config.Timing.ChaosStart
	return {{
		Kind = chosen,
		StartsAt = start,
		EndsAt = start + self.config.Timing.ChaosDuration,
		WarningAt = math.max(0, start - (self.config.Timing.Warning or 0)),
	}}
end

function RoundMachine.eventLabel(kind: string): string
	return LABEL[kind] or string.upper(kind)
end

function RoundMachine.setPhase(self: Machine, phase: string, now: number, effects: { Effect })
	self.phase = phase
	self.phaseStartedAt = now
	if phase == "Playing" then
		self.roundId += 1
		self.lastResults = nil
		self.eventFinished = false
		self.eventActive = false
		self.eventEndsAt = 0
		self.eventKind = ""
		self.eventWarning = ""
		self.warningEndsAt = 0
		self.phaseEndsAt = now + self.config.Timing.Round
		self.chaosKind = self:drawChaos()
		self.schedule = self:buildSchedule(self.chaosKind)
		local _, stage = self:stageAt(0)
		self.stage = stage.Name
		self.stageIndex = 1
		self.stageEndsAt = now + self.config.Timing.Round
		for _, player in self.players do
			player.score = 0
			player.pickups = 0
			player.participating = true
			table.clear(player.carried)
			player.carriedValue = 0
			player.stealReadyAt = 0
			player.protectedUntil = now + self.config.Steal.Protection
			player.immuneUntil = 0
			player.lastVictim = 0
			player.lastStealAt = -math.huge
			player.steals = 0
			player.lost = 0
		end
	elseif phase == "Intermission" then
		self.phaseEndsAt = now + self.config.Timing.Intermission
		self.stage = ""
		self.stageIndex = 0
		self.stageEndsAt = 0
		self.eventActive = false
		self.eventEndsAt = 0
		self.eventKind = ""
		self.eventWarning = ""
		self.schedule = {}
		self.chaosKind = ""
	elseif phase == "Results" then
		self:finishRound()
		self.phaseEndsAt = now + self.config.Timing.Results
		self.eventActive = false
		self.eventEndsAt = 0
		self.eventKind = ""
		self.eventWarning = ""
	else
		self.phaseEndsAt = 0
		self.lastResults = nil
		self.stage = ""
		self.stageIndex = 0
		self.stageEndsAt = 0
		self.eventActive = false
		self.eventEndsAt = 0
		self.eventKind = ""
		self.eventWarning = ""
		self.schedule = {}
		self.chaosKind = ""
		for _, player in self.players do
			player.participating = false
			table.clear(player.carried)
			player.carriedValue = 0
		end
	end
	table.insert(effects, { kind = "phase", phase = phase })
end

local function closeEvent(self: Machine, effects: { Effect })
	if self.eventActive then
		self.eventActive = false
		self.eventEndsAt = 0
		table.insert(effects, { kind = "event", active = false, event = self.eventKind })
	end
	self.eventKind = ""
end

function RoundMachine.step(self: Machine, now: number): { Effect }
	assert(finite(now) and now >= self.lastNow, "Server clock must be finite and monotonic")
	self.lastNow = now
	local effects: { Effect } = {}
	if next(self.players) == nil then
		if self.eventActive then
			closeEvent(self, effects)
		end
		if self.phase ~= "Waiting" then
			self:setPhase("Waiting", now, effects)
		end
		return effects
	end

	-- End first: a stalled server must never award a pickup after the deadline.
	if self.phase == "Waiting" then
		self:setPhase("Intermission", now, effects)
	elseif self.phase == "Intermission" and now >= self.phaseEndsAt then
		self:setPhase("Playing", now, effects)
	elseif self.phase == "Playing" and now >= self.phaseEndsAt then
		closeEvent(self, effects)
		self:setPhase("Results", now, effects)
	elseif self.phase == "Results" and now >= self.phaseEndsAt then
		self:setPhase("Intermission", now, effects)
	end

	if self.phase == "Playing" then
		local elapsed = now - self.phaseStartedAt

		-- Stage boundaries bank everything carried. A player who never competes
		-- still keeps what they collected, which is the point of banking.
		local desiredIndex, desiredStage = self:stageAt(elapsed)
		if desiredIndex > self.stageIndex then
			for _, player in self.players do
				bankPlayer(player)
			end
			self.stageIndex = desiredIndex
			self.stage = desiredStage.Name
			table.insert(effects, { kind = "stage", stage = desiredStage.Name, label = desiredStage.Label })
		end
		local stages = self.config.Stages or DEFAULT_STAGES
		local nextStage = stages[self.stageIndex + 1]
		self.stageEndsAt = if nextStage then self.phaseStartedAt + nextStage.At else self.phaseEndsAt

		-- Event timeline: warnings first, then the window itself.
		for _, entry in self.schedule do
			if elapsed >= entry.WarningAt and elapsed < entry.StartsAt and self.eventWarning ~= entry.Kind then
				self.eventWarning = entry.Kind
				self.warningEndsAt = self.phaseStartedAt + entry.StartsAt
				table.insert(effects, {
					kind = "warning", event = entry.Kind,
					label = RoundMachine.eventLabel(entry.Kind),
					at = self.phaseStartedAt + entry.StartsAt,
				})
			end
		end
		if self.eventActive and elapsed >= self.eventEndsAt - self.phaseStartedAt then
			closeEvent(self, effects)
		end
		if not self.eventActive then
			for _, entry in self.schedule do
				if elapsed >= entry.StartsAt and elapsed < entry.EndsAt then
					self.eventActive = true
					self.eventKind = entry.Kind
					self.eventEndsAt = self.phaseStartedAt + entry.EndsAt
					self.eventWarning = ""
					table.insert(effects, {
						kind = "event", active = true, event = entry.Kind,
						label = RoundMachine.eventLabel(entry.Kind), endsAt = self.eventEndsAt,
					})
					break
				end
			end
		end
		local finished = true
		for _, entry in self.schedule do
			if elapsed < entry.EndsAt then
				finished = false
			end
		end
		self.eventFinished = finished
		if finished and self.eventWarning ~= "" then
			self.eventWarning = ""
		end
	end
	return effects
end

function RoundMachine.snapshot(self: Machine)
	local schedule: { { Kind: string, Label: string, At: number, Duration: number } } = {}
	local base = self.phaseStartedAt
	for _, entry in self.schedule do
		table.insert(schedule, {
			Kind = entry.Kind, Label = RoundMachine.eventLabel(entry.Kind),
			At = base + entry.StartsAt, Duration = entry.EndsAt - entry.StartsAt,
		})
	end
	return {
		phase = self.phase, roundId = self.roundId, phaseEndsAt = self.phaseEndsAt,
		eventActive = self.eventActive, eventEndsAt = self.eventEndsAt,
		eventKind = self.eventKind,
		eventWarning = self.eventWarning, eventWarningEndsAt = self.warningEndsAt,
		stage = self.stage, stageIndex = self.stageIndex, stageEndsAt = self.stageEndsAt,
		events = schedule,
		rows = self:rows(), results = self.lastResults,
	}
end

return RoundMachine
