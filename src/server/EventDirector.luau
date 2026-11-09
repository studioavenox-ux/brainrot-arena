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
--   * Parts that were destroyed while a surface was altered are skipped on restore.
local ChaosRules = require(script.Parent.core.ChaosRules)

local EventDirector = {}
EventDirector.__index = EventDirector

export type Director = typeof(setmetatable({} :: {
	normalGravity: number,
	frictionOn: boolean,
	saved: { [BasePart]: PhysicalProperties | boolean },
}, EventDirector))

function EventDirector.new(normalGravity: number): Director
	assert(normalGravity == normalGravity and normalGravity > 0, "Normal gravity must be positive")
	return setmetatable({
		normalGravity = normalGravity,
		frictionOn = false,
		saved = {},
	}, EventDirector) :: any
end

-- Records the authored physical properties of every surface the first time friction
-- is changed. Characters and pickups are included; the pickup named BrainCell is not
-- a walkable surface and is excluded, as before.
local function captureSurfaces(self: Director)
	for _, part in (workspace :: any):GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "BrainCell" and self.saved[part] == nil then
			self.saved[part] = part.CustomPhysicalProperties or false
		end
	end
end

local function setFriction(self: Director, value: number)
	if not self.frictionOn then
		captureSurfaces(self)
	end
	for part in self.saved do
		if part.Parent ~= nil then
			part.CustomPhysicalProperties = PhysicalProperties.new(.7, value, .5, 1, 1)
		end
	end
	self.frictionOn = true
end

local function restoreFriction(self: Director)
	if not self.frictionOn then
		return
	end
	for part, original in self.saved do
		if part.Parent ~= nil then
			part.CustomPhysicalProperties = if original == false then nil else original :: PhysicalProperties
		end
	end
	table.clear(self.saved)
	self.frictionOn = false
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

return EventDirector
