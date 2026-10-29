--!strict
-- A modest server-side teleport/speed sanity check, not a claim of exploit-proof physics.
-- Vertical motion is unrestricted so low-gravity jumps and falling remain valid.
local MovementGuard = {}
MovementGuard.__index = MovementGuard

export type Position = { x: number, y: number, z: number }
type Track = { position: Position, at: number, unlockAt: number }
type Fields = { tracks: { [number]: Track }, speed: number, slack: number, protection: number }
export type Guard = typeof(setmetatable({} :: Fields, MovementGuard))

local function valid(p: Position): boolean
	return p.x == p.x and p.y == p.y and p.z == p.z
		and math.abs(p.x) < 100000 and math.abs(p.y) < 100000 and math.abs(p.z) < 100000
end

function MovementGuard.new(speed: number, slack: number, protection: number): Guard
	return setmetatable({ tracks = {}, speed = speed, slack = slack, protection = protection }, MovementGuard)
end

function MovementGuard.teleport(self: Guard, id: number, position: Position, now: number)
	self.tracks[id] = { position = position, at = now, unlockAt = now + self.protection }
end

function MovementGuard.remove(self: Guard, id: number)
	self.tracks[id] = nil
end

function MovementGuard.observe(self: Guard, id: number, position: Position, now: number): (boolean, Position?)
	local track = self.tracks[id]
	if not valid(position) then
		return false, if track then track.position else nil
	end
	if not track then
		self:teleport(id, position, now)
		return false, nil
	end
	local dt = math.clamp(now - track.at, 0, 1)
	local dx = position.x - track.position.x
	local dz = position.z - track.position.z
	local limit = self.speed * dt + self.slack
	if dx * dx + dz * dz > limit * limit then
		track.at = now
		track.unlockAt = now + self.protection
		return false, track.position
	end
	track.position = position
	track.at = now
	return now >= track.unlockAt, nil
end

return MovementGuard
