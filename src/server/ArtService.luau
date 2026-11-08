--!nonstrict
-- Applies the art-direction lighting rig at runtime (Rojo workflow, or if the
-- baked Lighting children are ever missing). The exported place already contains
-- this exact rig; applying it twice is idempotent, so both workflows match.
--
-- Performance: a handful of singleton Lighting instances, no loops per frame and
-- no post-processing beyond the four cheap standard effects. Nothing here touches
-- gameplay, scoring, pickups, rounds or networking.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ArtDirection = require(ReplicatedStorage:WaitForChild("BrainrotShared"):WaitForChild("ArtDirection"))

local ArtService = {}

local function rgb(values)
	return Color3.fromRGB(values[1], values[2], values[3])
end

local function applyProperties(instance, properties)
	for key, value in properties do
		instance[key] = if typeof(value) == "table" then rgb(value) else value
	end
end

-- Instances this module owns, so it never depends on children order.
local owned = {}

local function acquire(class, name)
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == class then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local instance = Instance.new(class)
	instance.Name = name
	instance.Parent = Lighting
	return instance
end

function ArtService.apply()
	-- Renderer technology is a place/Studio setting, not script authority; the rig
	-- below is authored for the default (shadowed) renderer.
	applyProperties(Lighting, ArtDirection.Lighting)
	for class, spec in ArtDirection.Effects do
		local instance = acquire(class, spec.Name)
		local properties = table.clone(spec.Properties)
		if class == "Sky" then
			for face, url in ArtDirection.Skybox do
				properties["Skybox" .. face] = url
			end
		end
		applyProperties(instance, properties)
		owned[class] = instance
	end
	-- Remove any legacy grade left in an older place so the look cannot drift.
	for _, child in Lighting:GetChildren() do
		if child:IsA("ColorCorrectionEffect") and child.Name ~= ArtDirection.Effects.ColorCorrectionEffect.Name then
			child:Destroy()
		end
	end
	return owned
end

return ArtService
