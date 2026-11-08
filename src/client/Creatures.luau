--!nonstrict
-- The cast — six original characters, built as real Roblox Models.
--
-- One table (tools/creatures.py → CreatureData) drives everything here: geometry,
-- rarity colouring, the animation joints, the floating name card and the collection
-- card art. Nothing is an uploaded asset; every character is primitives, so it is
-- cheap on mobile and identical in the place export and at runtime.
--
-- Rarity colouring: a character's body is tinted from the CELL's rarity colour, which
-- the server owns. Shape carries the identity, colour carries the value, and the
-- floating label names both.
local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("BrainrotShared"):WaitForChild("Creatures"))
local CreatureData = require(script.Parent.CreatureData)

local Creatures = {}

Creatures.Data = CreatureData
Creatures.Shared = Shared

local FIXED = {}
for role, rgb in CreatureData.Fixed do
	FIXED[role] = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- Mirror of tools/preview.py:tint, so plates and the game agree.
function Creatures.tint(base, role)
	if role == "body" or role == "neon" then
		return base
	elseif role == "body_light" then
		return base:Lerp(Color3.new(1, 1, 1), .26)
	elseif role == "body_dark" then
		return base:Lerp(Color3.fromRGB(34, 40, 50), .42)
	elseif role == "blush" then
		return base:Lerp(Color3.fromRGB(255, 150, 190), .55)
	end
	return FIXED[role] or base
end

-- Rarity colours are the server's contract (Config.Kinds). Kept here only as a
-- rendering fallback when a caller has no kind colour to hand.
local RARITY_FALLBACK = {
	[1] = Color3.fromRGB(255, 94, 190),
	[5] = Color3.fromRGB(255, 213, 67),
	[10] = Color3.fromRGB(83, 238, 255),
}

function Creatures.colorFor(value)
	return RARITY_FALLBACK[value] or RARITY_FALLBACK[1]
end

local SHAPE = {
	box = Enum.PartType.Block,
	ball = Enum.PartType.Ball,
	cyl = Enum.PartType.Cylinder,
}

local function makePart(spec, base, parent)
	local part = Instance.new("Part")
	part.Name = spec.Name
	part.Shape = SHAPE[spec.Kind] or Enum.PartType.Block
	part.Size = Vector3.new(spec.Size[1], spec.Size[2], spec.Size[3])
	part.Material = Enum.Material[spec.Material] or Enum.Material.SmoothPlastic
	part.Color = Creatures.tint(base, spec.Role)
	part.Anchored = true
	part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = false, false, false, false
	part.Massless = true
	part.Transparency = 0
	part.Locked = true
	part.CFrame = CFrame.new(spec.At[1], spec.At[2], spec.At[3])
		* CFrame.Angles(math.rad(spec.Rot[1]), math.rad(spec.Rot[2]), math.rad(spec.Rot[3]))
	part.Parent = parent
	return part
end

-- --------------------------------------------------------------------------- #
-- Label: the floating name + rarity card every character carries
-- --------------------------------------------------------------------------- #
local RARITY_COLOR = {
	Common = Color3.fromRGB(255, 118, 196),
	Rare = Color3.fromRGB(255, 213, 67),
	Legendary = Color3.fromRGB(83, 238, 255),
}

function Creatures.attachLabel(model, name, value, options)
	local o = options or {}
	local spec = CreatureData.Creatures[name]
	if not spec then
		return nil
	end
	local anchor = Instance.new("Part")
	anchor.Name = "LabelAnchor"
	anchor.Size = Vector3.new(.1, .1, .1)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide, anchor.CanTouch, anchor.CanQuery, anchor.CastShadow = false, false, false, false
	anchor.Massless = true
	anchor.CFrame = CFrame.new(0, spec.LabelHeight, 0)
	anchor.Parent = model

	local gui = Instance.new("BillboardGui")
	gui.Name = "NameTag"
	gui.Size = UDim2.fromOffset(o.width or 132, o.height or 40)
	gui.StudsOffset = Vector3.new(0, 0, 0)
	gui.AlwaysOnTop = o.alwaysOnTop ~= false
	gui.MaxDistance = o.maxDistance or 120
	gui.LightInfluence = 0
	gui.Parent = anchor

	local title = Instance.new("TextLabel")
	title.Name = "Name"
	title.Size = UDim2.new(1, 0, 0, 24)
	title.Position = UDim2.fromOffset(0, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 18
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextStrokeTransparency = .35
	title.Text = spec.Label
	title.Parent = gui

	local rarity = Instance.new("TextLabel")
	rarity.Name = "Rarity"
	rarity.Size = UDim2.new(1, 0, 0, 14)
	rarity.Position = UDim2.fromOffset(0, 23)
	rarity.BackgroundTransparency = 1
	rarity.Font = Enum.Font.GothamBold
	rarity.TextSize = 12
	rarity.TextColor3 = RARITY_COLOR[spec.Rarity] or RARITY_COLOR.Common
	rarity.TextStrokeTransparency = .45
	rarity.Text = string.upper(spec.Rarity) .. "  •  +" .. spec.Value
	rarity.Parent = gui

	return { anchor = anchor, gui = gui, name = title, rarity = rarity }
end

-- --------------------------------------------------------------------------- #
-- Build one character as a Model named after its label.
--   Build(parent, "sock", value, baseColor) -> view
--   view = { model, name, value, parts, joints, idle, collect, label }
-- --------------------------------------------------------------------------- #
function Creatures.Build(parent, name, value, base, options)
	local o = options or {}
	local spec = CreatureData.Creatures[name]
	assert(spec, "Unknown character: " .. tostring(name))
	local tint = base or Creatures.colorFor(value)

	local model = Instance.new("Model")
	model.Name = spec.Label
	model:SetAttribute("Character", name)
	model:SetAttribute("Rarity", spec.Rarity)
	model:SetAttribute("Value", spec.Value)

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(.4, .4, .4)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide, root.CanTouch, root.CanQuery, root.CastShadow = false, false, false, false
	root.Massless = true
	root.CFrame = CFrame.new(0, 0, 0)
	root.Parent = model
	model.PrimaryPart = root

	local parts = {}
	local joints = { head = {}, jaw = {}, armL = {}, armR = {}, tail = {} }
	for _, partSpec in spec.Parts do
		local part = makePart(partSpec, tint, model)
		local entry = {
			part = part, home = part.CFrame, joint = partSpec.Join, spec = partSpec,
			homeSize = Vector3.new(partSpec.Size[1], partSpec.Size[2], partSpec.Size[3]),
		}
		table.insert(parts, entry)
		if partSpec.Join and joints[partSpec.Join] then
			table.insert(joints[partSpec.Join], entry)
		end
	end

	local view = {
		model = model,
		root = root,
		name = name,
		value = value,
		base = tint,
		spec = spec,
		parts = parts,
		joints = joints,
		idle = spec.Idle,
		collect = spec.Collect,
		phase = o.phase or 0,
		label = nil,
	}
	if o.label ~= false then
		view.label = Creatures.attachLabel(model, name, value, o)
	end
	model.Parent = parent
	return view
end

-- Recolour in place: the rarity colour can change without rebuilding geometry.
-- Each part remembers its own role, so this can never drift out of order.
function Creatures.SetColor(view, base)
	if not view then
		return
	end
	view.base = base
	for _, entry in view.parts do
		entry.part.Color = Creatures.tint(base, entry.spec.Role)
	end
end

-- --------------------------------------------------------------------------- #
-- Motion. Everything is driven from one clock so a cell never desyncs from its
-- neighbours, and every amplitude collapses to zero under reduced motion.
-- --------------------------------------------------------------------------- #
function Creatures.Idle(view, now, reduced)
	if not view then
		return
	end
	local idle = view.idle
	local t = now * idle.Rate + view.phase
	if reduced then
		view.model:PivotTo(view.root.CFrame)
		return
	end
	local bob = math.sin(t * 1.6) * idle.Bob
	local sway = math.sin(t) * idle.Sway
	local tilt = math.sin(t * .7) * idle.Sway * .5
	-- Torso lean, applied around the model's own pivot.
	local pivot = CFrame.new(0, bob, 0) * CFrame.Angles(0, sway, tilt)
	-- Joints: head sway, jaw chatter, arm swing, tail wag.
	for _, entry in view.joints.head do
		entry.part.CFrame = pivot * entry.home
			* CFrame.Angles(math.sin(t * .9) * .06, math.sin(t * 1.3) * .10, 0)
	end
	for _, entry in view.joints.jaw do
		entry.part.CFrame = pivot * entry.home * CFrame.Angles(math.max(0, math.sin(t * 2.4)) * .10, 0, 0)
	end
	for _, entry in view.joints.armL do
		entry.part.CFrame = pivot * entry.home * CFrame.Angles(0, 0, math.sin(t * 1.7) * .18)
	end
	for _, entry in view.joints.armR do
		entry.part.CFrame = pivot * entry.home * CFrame.Angles(0, 0, -math.sin(t * 1.7 + .6) * .18)
	end
	for _, entry in view.joints.tail do
		entry.part.CFrame = pivot * entry.home * CFrame.Angles(0, math.sin(t * 2.1) * .20, 0)
	end
	for _, entry in view.parts do
		if not entry.joint then
			entry.part.CFrame = pivot * entry.home
		end
	end
	-- The invisible root carries the whole model's placement.
	view.root.CFrame = view.model:GetPivot()
end

-- Spin + pop used at pickup (and by the collection card preview).
function Creatures.Collect(view, progress, reduced)
	if not view or not view.model.Parent then
		return
	end
	if reduced then
		return
	end
	local clamped = math.clamp(progress, 0, 1)
	local pop = 1 + math.sin(clamped * math.pi) * (view.collect.Pop - 1)
	local spin = clamped * view.collect.Spin * math.pi * 2
	local rise = clamped * .9
	-- Pop by scaling each part about its own centre, then spin + lift the model.
	for _, entry in view.parts do
		entry.part.Size = entry.homeSize * pop
	end
	view.model:PivotTo(CFrame.new(0, rise, 0) * CFrame.Angles(0, spin, 0))
end

-- --------------------------------------------------------------------------- #
-- Small helpers used by Effects and the collection UI
-- --------------------------------------------------------------------------- #
function Creatures.variantFor(slotId, value)
	return Shared.SpeciesOf(slotId or 0, value)
end

function Creatures.label(value)
	local family = Shared.Family[value] or Shared.Family[1]
	local spec = Shared.Characters[family[1]]
	return spec and spec.Label or "BRAINY"
end

function Creatures.nameOf(name)
	local spec = Shared.Characters[name]
	return spec and spec.Label or "BRAINY"
end

function Creatures.rarityOf(name)
	local spec = Shared.Characters[name]
	return spec and spec.Rarity or "Common"
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

-- The six collection entries, in display order.
function Creatures.catalogue()
	local out = {}
	for index, name in Shared.Order do
		local spec = Shared.Characters[name]
		local data = CreatureData.Creatures[name]
		table.insert(out, {
			index = index,
			name = name,
			label = spec.Label,
			title = spec.Title,
			rarity = spec.Rarity,
			value = spec.Value,
			blurb = spec.Blurb,
			lore = spec.Lore,
			height = data.Height,
			color = RARITY_FALLBACK[spec.Value],
			rarityColor = RARITY_COLOR[spec.Rarity],
		})
	end
	return out
end

return Creatures
