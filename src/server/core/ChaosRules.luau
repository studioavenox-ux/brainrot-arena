--!strict
-- Pure, engine-independent rules for the Chaos Event. Given the live kind (or ""),
-- returns the complete set of modifiers the server should apply right now.
--
-- Every value is read from Config.Chaos or Config; nothing is duplicated here.
-- The server reconciles to `modifiers(machine.eventKind)` on every step, so the
-- neutral set is always what remains after an event ends. Cleanup therefore does
-- not depend on remembering to undo one specific effect.
local ChaosRules = {}

export type Modifiers = {
	Kind: string,
	Gravity: number,       -- Workspace.Gravity
	Friction: number?,     -- nil = surfaces keep their own physical properties
	JumpScale: number,     -- multiplier on Config.JumpPower
	RareScale: number,     -- weight multiplier for Rare and Prismatic cells
	Respawn: number?,      -- nil = normal respawn rules apply
}

export type Config = {
	NormalGravity: number,
	SlipperyFriction: number,
	RushRespawn: number,
	Chaos: {
		Kinds: { string },
		LowGravity: number,
		BouncyJumpScale: number,
		RushRarityScale: number,
	},
}

local function neutral(config: Config): Modifiers
	return {
		Kind = "",
		Gravity = config.NormalGravity,
		Friction = nil,
		JumpScale = 1,
		RareScale = 1,
		Respawn = nil,
	}
end

-- The set of kinds the server may draw from. Used by the round machine's validation.
function ChaosRules.isKnown(kind: string): boolean
	return kind == "LowGravity" or kind == "BouncyWorld" or kind == "SlipperyChaos" or kind == "BrainCellRush"
end

function ChaosRules.modifiers(kind: string, config: Config): Modifiers
	local result = neutral(config)
	if kind == "" then
		return result
	end
	result.Kind = kind
	if kind == "LowGravity" then
		result.Gravity = config.Chaos.LowGravity
	elseif kind == "BouncyWorld" then
		result.JumpScale = config.Chaos.BouncyJumpScale
	elseif kind == "SlipperyChaos" then
		result.Friction = config.SlipperyFriction
	elseif kind == "BrainCellRush" then
		result.RareScale = config.Chaos.RushRarityScale
		result.Respawn = config.RushRespawn
	else
		error("Unknown Chaos Event kind: " .. tostring(kind), 2)
	end
	return result
end

ChaosRules.neutral = neutral

return table.freeze(ChaosRules)
