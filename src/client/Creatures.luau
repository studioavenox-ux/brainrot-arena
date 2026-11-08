--!nonstrict
-- Original collectible cast — runtime builder.
--
-- Every slot shows one of six silly low-poly critters. The server only owns a
-- cell's rarity *value*; which variant a slot shows is derived here from its slot
-- id, so appearance can never feed back into scoring, claiming or respawn timing.
--
-- Geometry comes from the generated `CreatureData` table, which in turn comes from
-- tools/creatures.py — the same data the review plates are rendered from.
local CreatureData = require(script.Parent.CreatureData)

local Creatures = {}

local FIXED = {}
for role, rgb in CreatureData.Fixed do
	FIXED[role] = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function tint(base, role)
	if role == "body" then
		return base
	elseif role == "body_light" then
		return base:Lerp(Color3.new(1, 1, 1), .24)
	elseif role == "body_dark" then
		return base:Lerp(Color3.new(.14, .16, .20), .40)
	elseif role == "neon" then
		return base
	end
	return FIXED[role] or base
end

local function makePart(spec)
	local part
	if spec.Shape == "WedgePart" then
		part = Instance.new("WedgePart")
	elseif spec.Shape == "Cylinder" then
		part = Instance.new("Part")
		part.Shape = Enum.PartType.Cylinder
	elseif spec.Shape == "Ball" then
		part = Instance.new("Part")
		part.Shape = Enum.PartType.Ball
	else
		part = Instance.new("Part")
		part.Shape = Enum.PartType.Block
	end
	part.Name = spec.Name
	part.Size = Vector3.new(spec.Size[1], spec.Size[2], spec.Size[3])
	part.Material = Enum.Material[spec.Material] or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = false, false, false, false
	part.Massless = true
	part.CFrame = CFrame.new(spec.Offset[1], spec.Offset[2], spec.Offset[3])
		* CFrame.Angles(math.rad(spec.Rotation[1]), math.rad(spec.Rotation[2]), math.rad(spec.Rotation[3]))
	return part
end

-- Deterministic variant choice: the same slot always shows the same critter.
function Creatures.variantFor(slotId, value)
	local family = CreatureData.Family[value] or CreatureData.Family[1]
	return family[(slotId or 0) % #family + 1]
end

function Creatures.label(value)
	local family = CreatureData.Family[value] or CreatureData.Family[1]
	local spec = CreatureData.Creatures[family[1]]
	return spec and spec.Label or "BRAIN CELL"
end

-- Build the creature for `value` inside `model`.
-- Returns { name, parts } so the caller can recolour without rebuilding.
function Creatures.build(model, slotId, value, base)
	local name = Creatures.variantFor(slotId, value)
	local spec = CreatureData.Creatures[name]
	assert(spec, "Unknown creature variant: " .. tostring(name))
	local parts = {}
	for _, partSpec in spec.Parts do
		local part = makePart(partSpec)
		part.Color = tint(base, partSpec.Role)
		part.Parent = model
		table.insert(parts, part)
	end
	return { name = name, parts = parts }
end

function Creatures.recolour(view, base)
	if not view then
		return
	end
	local spec = CreatureData.Creatures[view.name]
	for index, part in view.parts do
		part.Color = tint(base, spec.Parts[index].Role)
	end
end

-- Shared hover ring: the one part every cell keeps, whatever its rarity.
function Creatures.halo(model)
	local spec = CreatureData.Halo
	local part = Instance.new("Part")
	part.Name = spec.Name
	part.Size = Vector3.new(spec.Size[1], spec.Size[2], spec.Size[3])
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material[spec.Material] or Enum.Material.SmoothPlastic
	part.Color = Color3.new(1, 1, 1)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = false, false, false, false
	part.Massless = true
	part.CFrame = CFrame.Angles(0, 0, math.pi / 2)
	part.Parent = model
	return part
end

return Creatures
