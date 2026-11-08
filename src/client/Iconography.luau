--!nonstrict
-- Procedural recognisability layer.
--
-- Every gameplay object keeps a unique silhouette *in addition to* its colour, so
-- the redesign stays readable for colour-blind players and on washed-out phone
-- screens:
--   pink  +1  -> critter only (no extra parts)
--   gold  +5  -> critter plus one floating ring
--   prism +10 -> critter plus two crossed arms
-- Built from part/UI primitives only; no images, decals or asset IDs.
local Iconography = {}

local KIND_ORDER = { 1, 5, 10 }        -- value -> silhouette index

local KINDS = {}
for index, value in KIND_ORDER do
	KINDS[value] = index
end

-- Rarity marks sit *outside* the creature silhouette so the critter stays legible:
--   gold  +5  -> one floating ring above the head (single part, Neon)
--   prism +10 -> two crossed arms in front of the chest (two parts, Neon)
-- Only rarer cells pay for these parts; +1 cells cost nothing.
local MARK_LAYOUT = {
	Crown = { Size = Vector3.new(.10, .74, .74), Node = Vector3.new(0, 1.12, 0), Pitch = 0,
		Name = "MarkCrown", Shape = Enum.PartType.Cylinder },
	ArmX = { Size = Vector3.new(.12, .12, .92), Node = Vector3.new(0, -.06, .62), Pitch = math.rad(38),
		Name = "MarkArm", Shape = Enum.PartType.Block },
	ArmZ = { Size = Vector3.new(.92, .12, .12), Node = Vector3.new(0, -.06, .62), Pitch = -math.rad(38),
		Name = "MarkArm", Shape = Enum.PartType.Block },
}

-- A mark handle. No parts are created here; `apply` allocates on demand.
function Iconography.marks(model, color, kind)
	return { model = model, color = color, kind = kind or "none", parts = {} }
end

local function ensure(marks, key, color)
	local existing = marks.parts[key]
	if existing then
		existing.Color = color
		return existing
	end
	local layout = MARK_LAYOUT[key]
	local part = Instance.new("Part")
	part.Name, part.Size, part.Shape = layout.Name, layout.Size, layout.Shape
	part.Material = Enum.Material.Neon
	part.Color = color
	part.CFrame = CFrame.new(layout.Node) * CFrame.Angles(0, 0, layout.Pitch)
	if key == "Crown" then
		-- Roblox cylinders are X-axis; lay it flat so it reads as a ring.
		part.CFrame = CFrame.new(layout.Node) * CFrame.Angles(0, 0, math.pi / 2)
	end
	part.Anchored = true
	part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = false, false, false, false
	part.Massless = true
	part.Transparency = 1
	part.Parent = marks.model
	marks.parts[key] = part
	return part
end

-- Show only the marks belonging to `value`.
function Iconography.apply(marks, value, color, visible)
	if not marks then
		return
	end
	local kind = marks.kind or "none"
	local shown = visible == true
	if kind == "crown" then
		ensure(marks, "Crown", color)
	elseif kind == "arms" then
		ensure(marks, "ArmX", color)
		ensure(marks, "ArmZ", color)
	end
	for key, part in marks.parts do
		local active = (kind == "crown" and key == "Crown")
			or (kind == "arms" and (key == "ArmX" or key == "ArmZ"))
		part.Transparency = if shown and active then 0 else 1
	end
end

-- ---------------------------------------------------------------------------
-- HUD helper: a small glyph mirroring the in-world silhouette, for the rarity key
-- and reward rows. Parent must be a Frame.
-- ---------------------------------------------------------------------------
function Iconography.glyph(parent, value, color)
	local index = KINDS[value] or 1
	local box = Instance.new("Frame")
	box.Name = "Glyph_" .. tostring(value)
	box.Size = UDim2.fromOffset(18, 18)
	box.BackgroundTransparency = 1
	box.Parent = parent

	local function square(name, size, position, hex)
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.Size = UDim2.fromOffset(size, size)
		frame.Position = UDim2.fromOffset(position[1], position[2])
		frame.BackgroundColor3 = color
		frame.BorderSizePixel = 0
		frame.Parent = box
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, hex and 0 or size)
		corner.Parent = frame
		return frame
	end

	-- All three glyphs share a round base dot; the extra mark disambiguates them.
	square("Base", 8, { 5, 5 }, false)
	if index == 2 then
		square("TipTop", 5, { 6, -1 }, true)
		square("TipBottom", 5, { 6, 14 }, true)
	elseif index == 3 then
		square("ArmUp", 4, { 7, -1 }, true)
		square("ArmDown", 4, { 7, 15 }, true)
		square("ArmLeft", 4, { -1, 7 }, true)
		square("ArmRight", 4, { 15, 7 }, true)
	end
	return box
end

return Iconography
