--!strict
-- Atomic, non-yielding collectible ownership. Positions and values originate on the server.
local PickupLedger = {}
PickupLedger.__index = PickupLedger

export type Position = { x: number, y: number, z: number }
export type Kind = { Name: string, Value: number, Weight: number, Color: { number } }
export type Slot = {
	id: number, position: Position, generation: number, available: boolean,
	readyAt: number, kindIndex: number,
}
export type Context = {
	userId: number, roundId: number, active: boolean, alive: boolean, position: Position,
}
export type Receipt = {
	userId: number, roundId: number, slotId: number, generation: number,
	kindIndex: number, value: number, position: Position,
}
type Fields = {
	slots: { Slot }, kinds: { Kind }, radius: number, respawn: number,
	roundId: number, running: boolean, choose: () -> number,
}
export type Ledger = typeof(setmetatable({} :: Fields, PickupLedger))

local function finite(n: number): boolean
	return n == n and n > -math.huge and n < math.huge
end
local function validPosition(p: Position): boolean
	return finite(p.x) and finite(p.y) and finite(p.z)
end

function PickupLedger.new(positions: { Position }, kinds: { Kind }, radius: number, respawn: number, choose: () -> number): Ledger
	assert(radius > 0 and respawn > 0 and #kinds > 0, "Invalid pickup rules")
	for _, kind in kinds do
		assert(kind.Value == 1 or kind.Value == 5 or kind.Value == 10, "Invalid server denomination")
		assert(kind.Weight > 0, "Positive rarity weights required")
	end
	local slots: { Slot } = {}
	for id, position in positions do
		assert(validPosition(position), "Invalid server spawn point")
		table.insert(slots, { id = id, position = position, generation = 0, available = false, readyAt = 0, kindIndex = 1 })
	end
	return setmetatable({
		slots = slots, kinds = kinds, radius = radius, respawn = respawn,
		roundId = 0, running = false, choose = choose,
	}, PickupLedger)
end

function PickupLedger.rollKind(self: Ledger): number
	local total = 0
	for _, kind in self.kinds do
		total += kind.Weight
	end
	local roll = math.clamp(self.choose(), 0, 0.999999) * total
	for index, kind in self.kinds do
		roll -= kind.Weight
		if roll < 0 then
			return index
		end
	end
	return #self.kinds
end

function PickupLedger.beginRound(self: Ledger, roundId: number)
	self.roundId = roundId
	self.running = true
	for _, slot in self.slots do
		slot.generation += 1
		slot.available = true
		slot.readyAt = 0
		slot.kindIndex = self:rollKind()
	end
end

function PickupLedger.clear(self: Ledger)
	self.running = false
	for _, slot in self.slots do
		slot.available = false
		slot.readyAt = math.huge
	end
end

function PickupLedger.tryClaim(self: Ledger, slotId: number, generation: number, context: Context, now: number): (Receipt?, string)
	if not finite(now) or not self.running or not context.active or context.roundId ~= self.roundId then
		return nil, "inactive-round"
	end
	if not finite(context.userId) or context.userId == 0 or context.userId % 1 ~= 0 or not context.alive then
		return nil, "invalid-player"
	end
	if not finite(slotId) or slotId % 1 ~= 0 then
		return nil, "invalid-slot"
	end
	local slot = self.slots[slotId]
	if not slot or not slot.available or slot.generation ~= generation then
		return nil, "unavailable"
	end
	if not validPosition(context.position) then
		return nil, "invalid-position"
	end
	local dx = slot.position.x - context.position.x
	local dy = slot.position.y - context.position.y
	local dz = slot.position.z - context.position.z
	if dx * dx + dy * dy + dz * dz > self.radius * self.radius then
		return nil, "out-of-range"
	end
	-- Consume BEFORE returning. Two players in the same simulation tick cannot both win it.
	slot.available = false
	slot.readyAt = now + self.respawn
	return {
		userId = context.userId, roundId = self.roundId, slotId = slotId, generation = generation,
		kindIndex = slot.kindIndex, value = self.kinds[slot.kindIndex].Value, position = slot.position,
	}, "ok"
end

function PickupLedger.step(self: Ledger, now: number): { number }
	local changed: { number } = {}
	if not self.running then
		return changed
	end
	for _, slot in self.slots do
		if not slot.available and now >= slot.readyAt then
			slot.generation += 1
			slot.kindIndex = self:rollKind()
			slot.available = true
			table.insert(changed, slot.id)
		end
	end
	return changed
end

return PickupLedger
