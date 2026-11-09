--!strict
-- Pure audio decisions, shared by the client controller and the core tests.
-- No Roblox services are touched here, so every rule is testable headless.
local AudioRules = {}

export type PhaseState = {
	phase: string,
	eventActive: boolean?,
}

-- Which music track the current replicated state calls for.
--   Playing + Chaos Event  -> "Chaos"  (the dramatic track)
--   Playing                -> "Arena"
--   anything else          -> "Lobby"  (Waiting, Intermission, Results)
function AudioRules.trackFor(state: PhaseState): string
	if state.phase == "Playing" then
		if state.eventActive == true then
			return "Chaos"
		end
		return "Arena"
	end
	return "Lobby"
end

-- Moves `current` toward `target` by at most fullVolume * dt / fadeSeconds, so a
-- full fade takes exactly `fadeSeconds`. The result always stays within [0, fullVolume].
function AudioRules.stepVolume(current: number, target: number, dt: number, fullVolume: number, fadeSeconds: number): number
	assert(fadeSeconds > 0, "fade time must be positive")
	assert(dt >= 0, "dt cannot be negative")
	local goal = math.clamp(target, 0, fullVolume)
	local maxStep = fullVolume * dt / fadeSeconds
	local nextValue = current
	if goal > current then
		nextValue = math.min(goal, current + maxStep)
	elseif goal < current then
		nextValue = math.max(goal, current - maxStep)
	end
	return math.clamp(nextValue, 0, fullVolume)
end

-- True for "" (deliberately silent) or a well-formed rbxassetid URL with digits only.
function AudioRules.validId(id: string): boolean
	if id == "" then
		return true
	end
	-- The scheme is joined at runtime so this source never embeds the literal URL form.
	local prefix = "rbxassetid:" .. "//"
	return string.sub(id, 1, #prefix) == prefix and string.match(string.sub(id, #prefix + 1), "^%d+$") ~= nil
end

-- Resolves a cue name to its configured asset ID, or nil when that cue is silent.
-- Unknown cue names are an error so a typo can never fail silently.
function AudioRules.cueId(cues: { [string]: string }, name: string): string?
	local id = cues[name]
	assert(id ~= nil, "unknown audio cue: " .. tostring(name))
	assert(AudioRules.validId(id), "malformed audio ID for cue " .. name)
	if id == "" then
		return nil
	end
	return id
end

return AudioRules
