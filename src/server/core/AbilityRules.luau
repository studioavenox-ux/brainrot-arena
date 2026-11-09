--!strict
-- Pure ability geometry and status bookkeeping. No Roblox services, no cells, no score.
-- Positions are plain {x, y, z} tables, the same convention as ArenaRoute and MovementGuard.
local AbilityRules = {}

export type Vec = { x: number, y: number, z: number }
export type Candidate = { userId: number, position: Vec }
export type Hit = { userId: number, distance: number }
export type Statuses = { [number]: { factor: number, untilAt: number } }

local function distance(a: Vec, b: Vec): number
	local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Every eligible opponent inside `radius` of the caster, nearest first. The caster is
-- always excluded, so an ability can never hit its own user.
function AbilityRules.targetsIn(origin: Vec, candidates: { Candidate }, radius: number, casterId: number): { Hit }
	assert(radius > 0, "radius must be positive")
	local hits: { Hit } = {}
	for _, candidate in candidates do
		if candidate.userId ~= casterId then
			local d = distance(origin, candidate.position)
			if d <= radius then
				table.insert(hits, { userId = candidate.userId, distance = d })
			end
		end
	end
	table.sort(hits, function(a: Hit, b: Hit): boolean
		if a.distance == b.distance then
			return a.userId < b.userId
		end
		return a.distance < b.distance
	end)
	return hits
end

-- Unit horizontal direction from `from` to `to`. Falls back to `fallback` when the two
-- points coincide, so a launch always has a defined direction.
function AbilityRules.horizontalDirection(from: Vec, to: Vec, fallback: Vec): Vec
	local dx, dz = to.x - from.x, to.z - from.z
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 1e-6 then
		dx, dz = fallback.x, fallback.z
		length = math.sqrt(dx * dx + dz * dz)
		if length < 1e-6 then
			return { x = 0, y = 0, z = 1 }
		end
	end
	return { x = dx / length, y = 0, z = dz / length }
end

-- Knockback: a horizontal push away from the caster plus a small lift.
function AbilityRules.knockbackVelocity(direction: Vec, push: number, lift: number): Vec
	return { x = direction.x * push, y = lift, z = direction.z * push }
end

-- Upward launch with no horizontal component.
function AbilityRules.launchVelocity(lift: number): Vec
	return { x = 0, y = lift, z = 0 }
end

-- Bubble Dash: horizontal only, along the caster's facing, so it cannot be used to fly.
function AbilityRules.dashVelocity(look: Vec, speed: number): Vec
	local dx, dz = look.x, look.z
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 1e-6 then
		return { x = 0, y = 0, z = 0 }
	end
	return { x = dx / length * speed, y = 0, z = dz / length * speed }
end

-- Keeps the strongest slow on a player: the lowest factor wins, and the longest expiry wins.
-- Re-applying an ability never weakens a slow that is already stronger.
function AbilityRules.applySlow(statuses: Statuses, userId: number, factor: number, untilAt: number)
	assert(factor > 0 and factor <= 1, "slow factor must be in (0, 1]")
	local current = statuses[userId]
	if current == nil then
		statuses[userId] = { factor = factor, untilAt = untilAt }
		return
	end
	current.factor = math.min(current.factor, factor)
	current.untilAt = math.max(current.untilAt, untilAt)
end

-- The speed multiplier in force right now. 1 means no effect.
function AbilityRules.speedFactor(statuses: Statuses, userId: number, now: number): number
	local current = statuses[userId]
	if current == nil or now >= current.untilAt then
		return 1
	end
	return current.factor
end

-- Drops every slow that has expired.
function AbilityRules.prune(statuses: Statuses, now: number)
	for userId, current in statuses do
		if now >= current.untilAt then
			statuses[userId] = nil
		end
	end
end

return AbilityRules
