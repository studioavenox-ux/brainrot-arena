--!strict
-- Engine-independent authority. No task.wait(), remotes, or Roblox objects live here.
local RoundMachine = {}
RoundMachine.__index = RoundMachine

export type Timing = {
	Intermission: number, Round: number, Results: number, EventStart: number, EventDuration: number,
}
export type Settings = {
	Timing: Timing, ParticipationCoins: number, CoinsPerPoint: number, WinnerCoins: number, HaloCost: number,
}
export type Player = {
	id: number, name: string, score: number, coins: number, wins: number, pickups: number,
	participating: boolean, haloOwned: boolean, haloEquipped: boolean,
}
export type Row = {
	id: number, name: string, score: number, coins: number, wins: number, pickups: number,
	haloOwned: boolean, haloEquipped: boolean,
}
export type Results = {
	roundId: number, winners: { Row }, topScore: number, rewards: { [string]: number },
}
export type Effect = { kind: string, phase: string?, active: boolean? }
type Fields = {
	config: Settings, players: { [number]: Player }, phase: string, roundId: number,
	phaseStartedAt: number, phaseEndsAt: number, eventActive: boolean, eventEndsAt: number,
	eventFinished: boolean, lastNow: number, lastResults: Results?,
}
export type Machine = typeof(setmetatable({} :: Fields, RoundMachine))

local function finite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

function RoundMachine.new(config: Settings): Machine
	assert(config.Timing.Intermission > 0 and config.Timing.Round > 0 and config.Timing.Results > 0, "Positive phase durations required")
	assert(config.Timing.EventStart >= 0 and config.Timing.EventDuration > 0, "Invalid event timing")
	assert(config.Timing.EventStart + config.Timing.EventDuration < config.Timing.Round, "Chaos event must fit inside the round")
	return setmetatable({
		config = config, players = {}, phase = "Waiting", roundId = 0,
		phaseStartedAt = 0, phaseEndsAt = 0, eventActive = false, eventEndsAt = 0,
		eventFinished = false, lastNow = 0, lastResults = nil,
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
	}
	return true
end

function RoundMachine.removePlayer(self: Machine, id: number)
	self.players[id] = nil
end

function RoundMachine.isParticipating(self: Machine, id: number): boolean
	local player = self.players[id]
	return self.phase == "Playing" and player ~= nil and player.participating
end

function RoundMachine.award(self: Machine, id: number, value: number, roundId: number): boolean
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
	return true
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
		return false, "Not enough session coins"
	end
	player.coins -= self.config.HaloCost
	player.haloOwned = true
	player.haloEquipped = true
	return true, "Pulse Halo unlocked for this session!"
end

function RoundMachine.rows(self: Machine): { Row }
	local rows: { Row } = {}
	for _, player in self.players do
		table.insert(rows, {
			id = player.id, name = player.name, score = player.score, coins = player.coins,
			wins = player.wins, pickups = player.pickups,
			haloOwned = player.haloOwned, haloEquipped = player.haloEquipped,
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
		player.participating = false
	end
	self.lastResults = { roundId = self.roundId, winners = winners, topScore = topScore, rewards = rewards }
end

function RoundMachine.setPhase(self: Machine, phase: string, now: number, effects: { Effect })
	self.phase = phase
	self.phaseStartedAt = now
	if phase == "Playing" then
		self.roundId += 1
		self.lastResults = nil
		self.eventFinished = false
		self.phaseEndsAt = now + self.config.Timing.Round
		for _, player in self.players do
			player.score = 0
			player.pickups = 0
			player.participating = true
		end
	elseif phase == "Intermission" then
		self.phaseEndsAt = now + self.config.Timing.Intermission
	elseif phase == "Results" then
		self:finishRound()
		self.phaseEndsAt = now + self.config.Timing.Results
	else
		self.phaseEndsAt = 0
		self.lastResults = nil
		for _, player in self.players do
			player.participating = false
		end
	end
	table.insert(effects, { kind = "phase", phase = phase })
end

function RoundMachine.step(self: Machine, now: number): { Effect }
	assert(finite(now) and now >= self.lastNow, "Server clock must be finite and monotonic")
	self.lastNow = now
	local effects: { Effect } = {}
	if next(self.players) == nil then
		if self.eventActive then
			self.eventActive = false
			self.eventEndsAt = 0
			table.insert(effects, { kind = "event", active = false })
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
		if self.eventActive then
			self.eventActive = false
			self.eventEndsAt = 0
			table.insert(effects, { kind = "event", active = false })
		end
		self:setPhase("Results", now, effects)
	elseif self.phase == "Results" and now >= self.phaseEndsAt then
		self:setPhase("Intermission", now, effects)
	end

	if self.phase == "Playing" then
		local startAt = self.phaseStartedAt + self.config.Timing.EventStart
		local endAt = startAt + self.config.Timing.EventDuration
		if now >= endAt then
			self.eventFinished = true
			if self.eventActive then
				self.eventActive = false
				self.eventEndsAt = 0
				table.insert(effects, { kind = "event", active = false })
			end
		elseif now >= startAt and not self.eventFinished and not self.eventActive then
			self.eventActive = true
			self.eventEndsAt = endAt
			table.insert(effects, { kind = "event", active = true })
		end
	end
	return effects
end

function RoundMachine.snapshot(self: Machine)
	return {
		phase = self.phase, roundId = self.roundId, phaseEndsAt = self.phaseEndsAt,
		eventActive = self.eventActive, eventEndsAt = self.eventEndsAt,
		rows = self:rows(), results = self.lastResults,
	}
end

return RoundMachine
