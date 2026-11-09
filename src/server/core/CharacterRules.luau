--!strict
-- Pure character state: which character each player holds, how many switches they
-- have left, and when each character's ability is ready again. No Roblox services.
--
-- Rules:
--   * One active character at a time. Everyone starts a round on Order[1].
--   * Normal switches: Config.Characters.SwitchesNormal per round, any time in Playing.
--   * Bonus switch: Config.Characters.SwitchesBonus per round, only while the Chaos Event
--     is active. Four switches at most in total.
--   * Cooldowns are stored per player AND per character. A switch never resets or
--     copies a cooldown, so switching away and back cannot clear one.
--   * beginRound() clears every cooldown and every switch quota.
local CharacterRules = {}
CharacterRules.__index = CharacterRules

export type Options = {
	phase: string,
	participating: boolean,
	chaos: boolean?,
}

export type Player = {
	active: string,
	normalLeft: number,
	bonusLeft: number,
	readyAt: { [string]: number },
}

export type Rules = typeof(setmetatable({} :: {
	order: { string },
	roster: { [string]: { Ability: string, Cooldown: number } },
	normalMax: number,
	bonusMax: number,
	players: { [number]: Player },
}, CharacterRules))

function CharacterRules.new(characters: any): Rules
	assert(typeof(characters) == "table", "characters config required")
	assert(#characters.Order == 6, "exactly six characters are required")
	local seen: { [string]: boolean } = {}
	for _, key in characters.Order do
		assert(characters.Roster[key] ~= nil, "missing roster entry: " .. key)
		assert(not seen[key], "duplicate character: " .. key)
		seen[key] = true
		assert(characters.Roster[key].Cooldown > 0, "cooldown must be positive: " .. key)
	end
	assert(characters.SwitchesNormal >= 0 and characters.SwitchesBonus >= 0, "switch quotas cannot be negative")
	return setmetatable({
		order = characters.Order,
		roster = characters.Roster,
		normalMax = characters.SwitchesNormal,
		bonusMax = characters.SwitchesBonus,
		players = {},
	}, CharacterRules) :: any
end

local function freshPlayer(self: Rules): Player
	return { active = self.order[1], normalLeft = self.normalMax, bonusLeft = self.bonusMax, readyAt = {} }
end

-- Starts a new round for these players. Every cooldown and quota is reset here, and
-- nowhere else, so "cooldowns reset at the next round" has exactly one implementation.
function CharacterRules.beginRound(self: Rules, userIds: { number })
	self.players = {}
	for _, userId in userIds do
		self.players[userId] = freshPlayer(self)
	end
end

-- A player who joins mid-round gets a full quota and fresh cooldowns.
function CharacterRules.ensure(self: Rules, userId: number): Player
	local player = self.players[userId]
	if player == nil then
		player = freshPlayer(self)
		self.players[userId] = player
	end
	return player
end

function CharacterRules.clear(self: Rules, userId: number)
	self.players[userId] = nil
end

-- Returns (ok, reason). reason is "" on success.
function CharacterRules.switch(self: Rules, userId: number, slot: any, options: Options): (boolean, string)
	if options.phase ~= "Playing" then
		return false, "phase"
	end
	if not options.participating then
		return false, "not-participating"
	end
	if typeof(slot) ~= "number" or slot ~= math.floor(slot) or slot < 1 or slot > #self.order then
		return false, "bad-slot"
	end
	local player = CharacterRules.ensure(self, userId)
	local target = self.order[slot]
	if target == player.active then
		return false, "same-character"
	end
	local chaos = options.chaos == true
	if player.normalLeft > 0 then
		player.normalLeft -= 1
	elseif player.bonusLeft > 0 and chaos then
		player.bonusLeft -= 1
	elseif player.bonusLeft > 0 then
		return false, "bonus-during-chaos-only"
	else
		return false, "no-switches"
	end
	player.active = target
	return true, ""
end

-- Starts the active character's ability. Returns (ok, reason, abilityKey).
function CharacterRules.ability(self: Rules, userId: number, now: number, options: Options): (boolean, string, string)
	if options.phase ~= "Playing" then
		return false, "phase", ""
	end
	if not options.participating then
		return false, "not-participating", ""
	end
	local player = CharacterRules.ensure(self, userId)
	local ready = player.readyAt[player.active] or 0
	if now < ready then
		return false, "cooling", ""
	end
	local entry = self.roster[player.active]
	player.readyAt[player.active] = now + entry.Cooldown
	return true, "", entry.Ability
end

-- Seconds until a character's ability is ready again, never negative.
function CharacterRules.remaining(self: Rules, userId: number, characterId: string, now: number): number
	local player = self.players[userId]
	if player == nil then
		return 0
	end
	return math.max(0, (player.readyAt[characterId] or 0) - now)
end

-- The per-player view the client renders. Cooldowns are sent as server-clock deadlines,
-- so the client can count down without the server re-sending every second.
function CharacterRules.view(self: Rules, userId: number, chaos: boolean): { [string]: any }
	local player = CharacterRules.ensure(self, userId)
	local readyAt: { [string]: number } = {}
	for id, value in player.readyAt do
		readyAt[id] = value
	end
	return {
		active = player.active,
		normalLeft = player.normalLeft,
		bonusLeft = if chaos then player.bonusLeft else 0,
		bonusTotal = self.bonusMax,
		normalTotal = self.normalMax,
		readyAt = readyAt,
	}
end

return CharacterRules
