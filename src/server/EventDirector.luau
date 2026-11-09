-- Applies the physical side of the Chaos Event to the live world: gravity and
-- surface friction. Nothing here decides *when* or *which* event runs. The server
-- hands this module the complete modifier set from ChaosRules, every tick, and the
-- director makes the world match it.
--
-- Cleanup rules:
--   * Gravity is written only when it differs, and always returns to the normal value
--     from the neutral modifier set.
--   * Friction is applied by overriding each part's CustomPhysicalProperties. The
--     first override records every part's ORIGINAL value, and restoring writes those
--     exact values back (or nil where a part had none). Nothing is left behind.
--   * While friction is active, a DescendantAdded watcher adopts every new surface
--     (newly spawned or respawned characters, rebuilt pickups) so it gets the same
--     friction at once and is restored with everything else.
--   * Friction is written only when its value changes, never once per tick.
--   * Parts that were destroyed while a surface was altered are skipped on restore.
local ChaosRules = require(script.Parent.core.ChaosRules)

local EventDirector = {}
EventDirector.__index = EventDirector

export type Director = typeof(setmetatable({} :: {
	normalGravity: number,
	frictionOn: boolean,
	frictionValue: number?,
	saved: { [BasePart]: PhysicalProperties | boolean },
	watcher: RBXScriptConnection?,
}, EventDirector))

function EventDirector.new(normalGravity: number): Director
	assert(normalGravity == normalGravity and normalGravity > 0, "Normal gravity must be positive")
	return setmetatable({
		normalGravity = normalGravity,
		frictionOn = false,
		frictionValue = nil,
		saved = {},
		watcher = nil,
	}, EventDirector) :: any
end

-- Pickups named BrainCell are not walkable surfaces and are excluded, as before.
local function isSurface(instance: Instance): boolean
	return instance:IsA("BasePart") and instance.Name ~= "BrainCell"
end

-- Records a part's authored properties once, then overrides them while friction is on.
local function adopt(self: Director, part: BasePart, props: PhysicalProperties)
	if self.saved[part] == nil then
		self.saved[part] = part.CustomPhysicalProperties or false
	end
	if part.Parent ~= nil then
		part.CustomPhysicalProperties = props
	end
end

local function setFriction(self: Director, value: number)
	if self.frictionOn and self.frictionValue == value then
		return -- already in force; nothing to write
	end
	local props = PhysicalProperties.new(.7, value, .5, 1, 1)
	self.frictionValue = value
	if not self.frictionOn then
		self.frictionOn = true
		for _, part in (workspace :: any):GetDescendants() do
			if isSurface(part) and self.saved[part] == nil then
				self.saved[part] = part.CustomPhysicalProperties or false
			end
		end
		self.watcher = (workspace :: any).DescendantAdded:Connect(function(instance: Instance)
			if self.frictionOn and isSurface(instance) then
				adopt(self, instance :: BasePart, PhysicalProperties.new(.7, self.frictionValue or value, .5, 1, 1))
			end
		end)
	end
	for part in self.saved do
		if part.Parent ~= nil then
			part.CustomPhysicalProperties = props
		end
	end
end

local function restoreFriction(self: Director)
	if not self.frictionOn then
		return
	end
	if self.watcher then
		self.watcher:Disconnect()
		self.watcher = nil
	end
	for part, original in self.saved do
		if part.Parent ~= nil then
			part.CustomPhysicalProperties = if original == false then nil else original :: PhysicalProperties
		end
	end
	table.clear(self.saved)
	self.frictionOn = false
	self.frictionValue = nil
end

-- Make the world match `mods`. Idempotent: calling it twice with the same modifiers
-- changes nothing the second time.
function EventDirector.apply(self: Director, mods: ChaosRules.Modifiers)
	local host: any = workspace
	if host.Gravity ~= mods.Gravity then
		host.Gravity = mods.Gravity
	end
	if mods.Friction ~= nil then
		setFriction(self, mods.Friction)
	else
		restoreFriction(self)
	end
end

-- Called on every phase change and when the server shuts an event down. Returns the
-- world to the state it had before any event touched it.
function EventDirector.reset(self: Director)
	local host: any = workspace
	host.Gravity = self.normalGravity
	restoreFriction(self)
end

-- Number of parts currently overridden. Exposed for tests and the invariant checks.
function EventDirector.adoptedCount(self: Director): number
	local count = 0
	for _ in self.saved do
		count += 1
	end
	return count
end

return EventDirector
