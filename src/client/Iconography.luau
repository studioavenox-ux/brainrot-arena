--!nonstrict
-- Procedural recognisability layer.
--
-- Every gameplay object keeps a unique silhouette *in addition to* its colour, so
-- the redesign stays readable for colour-blind players and on washed-out phone
-- screens:
--   pink  +1  -> six-lobed brain with a pale equatorial halo (no extra parts)
--   gold  +5  -> the same brain plus one vertical crown spike
--   prism +10 -> the same brain plus two crossed arms
-- Built from part/UI primitives only; no images, decals or asset IDs.
local Iconography = {}

local KIND_ORDER = { 1, 5, 10 }        -- value -> silhouette index

local KINDS = {}
for index, value in KIND_ORDER do
	KINDS[value] = index
end

-- Silhouette marks, allocated lazily inside the cell model so common cells cost
-- zero extra parts. Only the rarer cells pay for their own silhouette.
local MARK_LAYOUT = {
	crown = { Size = Vector3.new(.18, .72, .18), Node = Vector3.new(0, .86, 0), Yaw = .785, Name = "Crown" },
	armX = { Size = Vector3.new(.13, .13, .96), Node = Vector3.new(0, 0, 0), Yaw = 0, Name = "Arm" },
	armZ = { Size = Vector3.new(.13, .13, .96), Node = Vector3.new(0, 0, 0), Yaw = math.pi / 2, Name = "Arm" },
}

function Iconography.marks(model, _color)
	-- Returns a lightweight handle; no parts are created here.
	return { model = model, parts = {} }
end

local function ensure(marks, key, color)
	local existing = marks.parts[key]
	if existing then
		existing.Color = color
		return existing
	end
	local layout = MARK_LAYOUT[key]
	local part = Instance.new("Part")
	part.Name = layout.Name
	part.Size = layout.Size
	part.Color = color
	part.CFrame = CFrame.new(layout.Node) * CFrame.Angles(0, layout.Yaw, 0)
	part.Anchored = true
	part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = false, false, false, false
	part.Massless = true
	part.Material = Enum.Material.Neon
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
	local kind = KINDS[value] or 1
	local shown = visible == true
	if shown and kind >= 2 then
		-- Created on first use, then reused while the model lives.
		ensure(marks, "crown", color)
		ensure(marks, "armX", color)
		ensure(marks, "armZ", color)
	end
	for key, part in marks.parts do
		local active = (kind == 2 and key == "crown") or (kind == 3 and key ~= "crown")
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
