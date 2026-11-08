--!nonstrict
-- The collection screen: six cards, one per character.
--
-- Every card is a live 3D viewport of the real model (the same Model class the
-- arena uses), so what the player sees in the log is literally the thing they
-- collect. Data comes from the server's per-player collection record: the name,
-- rarity, reward, how many were caught and whether it has been seen at all. There
-- are no placeholder stats — an uncollected card says so.
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local Creatures = require(script.Parent.Creatures)

local Collection = {}
Collection.__index = Collection

local C, Type, Space, Motion, Copy = Theme.Colors, Theme.Type, Theme.Space, Theme.Motion, Theme.Copy

local RARITY = {
	Common = { color = C.Cyan, label = "COMMON" },
	Rare = { color = C.Amber, label = "RARE" },
	Legendary = { color = C.Violet, label = "LEGENDARY" },
}

-- A stage for one card: a turntable camera, a soft key light, and the model itself.
local function buildStage(card, character, size, reducedMotion)
	local viewport = Kit.instance("ViewportFrame", {
		Name = "Preview",
		Size = UDim2.fromOffset(size, size),
		Position = UDim2.fromOffset(0, 0),
		BackgroundColor3 = C.Navy,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 4,
	}, card)
	Kit.instance("UICorner", { CornerRadius = UDim.new(0, 10) }, viewport)

	local camera = Instance.new("Camera")
	camera.Name = "StageCamera"
	-- Slightly above and in front of the character: the same angle the arena uses.
	camera.CFrame = CFrame.lookAt(Vector3.new(0, .55, 2.9), Vector3.new(0, .05, 0))
	camera.FieldOfView = 34
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local stage = Instance.new("Model")
	stage.Name = "Stage_" .. character.name
	stage.Parent = viewport

	-- Plinth: the same idea as the lobby exhibit, so the cards feel like a museum.
	local plinth = Instance.new("Part")
	plinth.Name = "Plinth"
	plinth.Size = Vector3.new(1.7, .12, 1.7)
	plinth.CFrame = CFrame.new(0, -.86, 0)
	plinth.Anchored = true
	plinth.CanCollide, plinth.CanTouch, plinth.CanQuery, plinth.CastShadow = false, false, false, false
	plinth.Material = Enum.Material.SmoothPlastic
	plinth.Color = C.NavyRaised
	plinth.Parent = stage

	-- A rim of the rarity colour, so the card is readable at a glance.
	local rim = Instance.new("Part")
	rim.Name = "Rim"
	rim.Size = Vector3.new(.06, 1.9, 1.9)
	rim.Shape = Enum.PartType.Cylinder
	rim.CFrame = CFrame.new(0, -.80, 0) * CFrame.Angles(0, 0, math.pi / 2)
	rim.Anchored = true
	rim.CanCollide, rim.CanTouch, rim.CanQuery, rim.CastShadow = false, false, false, false
	rim.Material = Enum.Material.Neon
	rim.Color = RARITY[character.rarity].color
	rim.Transparency = .35
	rim.Parent = stage

	local view = Creatures.Build(stage, character.name, character.value, character.color, {
		label = false, phase = character.index * .7,
	})
	view.model.Name = character.label
	-- Models are authored around their own origin; the camera frames that origin.
	view.model:PivotTo(CFrame.new(0, -.62, 0))

	return {
		viewport = viewport,
		camera = camera,
		stage = stage,
		plinth = plinth,
		rim = rim,
		view = view,
		spin = 0,
		reducedMotion = reducedMotion,
	}
end

function Collection.new(parent, config)
	local self = setmetatable({}, Collection)
	self.config = config
	self.cards = {}
	self.entries = Creatures.catalogue()

	-- Full-screen layer under the modal card, so the collection is its own screen.
	self.frame = Kit.instance("Frame", {
		Name = "Collection",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 30,
	}, parent)
	self.scrim = Kit.instance("Frame", {
		Name = "Scrim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Void,
		BackgroundTransparency = .18,
		BorderSizePixel = 0,
		ZIndex = 30,
	}, self.frame)

	local panel = Kit.panel(self.frame, "Panel", UDim2.new(1, -48, 1, -48), UDim2.fromScale(.5, .5), {
		anchor = Vector2.new(.5, .5), zIndex = 31, padding = Space.xl, radius = 18,
	})
	self.panel = panel

	self.heading = Kit.text(panel, "Title", Copy.CollectionTitle, "Title", {
		size = UDim2.new(1, -220, 0, 26), color = C.White, zIndex = 32,
	})
	self.subtitle = Kit.text(panel, "Subtitle", "", "Label", {
		size = UDim2.new(1, -220, 0, 16), position = UDim2.fromOffset(0, 28),
		color = C.Muted, zIndex = 32,
	})
	self.progress = Kit.text(panel, "Progress", "", "Title", {
		size = UDim2.fromOffset(200, 24), position = UDim2.new(1, -208, 0, 2),
		color = C.Cyan, xAlign = Enum.TextXAlignment.Right, zIndex = 32,
	})
	self.hint = Kit.text(panel, "Hint", Copy.CollectionHint, "Micro", {
		size = UDim2.new(1, -220, 0, 14), position = UDim2.fromOffset(0, 46),
		color = C.Dim, zIndex = 32,
	})

	self.close = Kit.button(panel, "Close", "X", UDim2.fromOffset(36, 36), UDim2.new(1, -36, 0, 0),
		function() self:hide() end, { accent = C.NavyEdge, zIndex = 32 })
	self.close.Label.TextSize = Type.Body

	self.grid = Kit.instance("Frame", {
		Name = "Grid",
		-- Starts below the hint line: the grid can never overlap the header text.
		Size = UDim2.new(1, 0, 1, -Space.xl - 64),
		Position = UDim2.fromOffset(0, Space.xl + 64),
		BackgroundTransparency = 1,
		ZIndex = 31,
	}, panel)
	local layout = Kit.instance("UIGridLayout", {
		CellSize = UDim2.fromOffset(150, 196),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirectionMaxCells = 6,
	}, self.grid)
	self.layout = layout

	-- Resize hooks: the grid adapts to width, the cards keep a 3:4-ish shape.
	self.layout.FillDirectionMaxCells = 3
	self.cards = {}
	for _, entry in self.entries do
		table.insert(self.cards, self:buildCard(entry))
	end
	self.frame.Visible = false
	return self
end

function Collection:buildCard(entry)
	local rarity = RARITY[entry.rarity] or RARITY.Common
	local card = Kit.panel(self.grid, "Card_" .. entry.name, UDim2.fromOffset(150, 196), UDim2.fromOffset(0, 0), {
		zIndex = 32, radius = 12, color = C.NavyRaised, transparency = .5,
	})
	card.LayoutOrder = entry.index

	local stage = buildStage(card, entry, 150, false)
	stage.viewport.Size = UDim2.fromOffset(146, 108)
	stage.viewport.Position = UDim2.fromOffset(2, 2)

	local status = Kit.instance("Frame", {
		Name = "Status",
		Size = UDim2.fromOffset(10, 10),
		Position = UDim2.fromOffset(10, 116),
		BackgroundColor3 = C.Dim,
		BorderSizePixel = 0,
		ZIndex = 34,
	}, card)
	Kit.corner(status, 10)

	local name = Kit.text(card, "Name", entry.label, "Label", {
		size = UDim2.new(1, -26, 0, 16), position = UDim2.fromOffset(24, 112),
		color = C.White, zIndex = 34, truncate = true,
	})
	-- Starts after the status dot, so the rarity and the dot never collide.
	local rarityLabel = Kit.text(card, "Rarity", string.upper(entry.rarity) .. "  +" .. entry.value, "Micro", {
		size = UDim2.new(1, -34, 0, 12), position = UDim2.fromOffset(24, 130),
		color = rarity.color, zIndex = 34, truncate = true,
	})
	local count = Kit.text(card, "Count", "", "Body", {
		size = UDim2.new(1, -16, 0, 18), position = UDim2.fromOffset(9, 146),
		color = C.Muted, zIndex = 34, truncate = true,
	})
	count.Font = Enum.Font.GothamBold
	local blurb = Kit.text(card, "Blurb", entry.blurb, "Micro", {
		size = UDim2.new(1, -16, 0, 24), position = UDim2.fromOffset(9, 166),
		color = C.Dim, zIndex = 34, wrapped = true,
	})
	blurb.Font = Enum.Font.GothamMedium

	return {
		entry = entry,
		frame = card,
		stage = stage,
		status = status,
		name = name,
		rarity = rarityLabel,
		count = count,
		blurb = blurb,
		seen = false,
		amount = 0,
	}
end

-- `row` is the local player's server row: row.collection[name] -> count.
function Collection:update(row)
	local caught = 0
	for _, card in self.cards do
		local amount = (row and row.collection and row.collection[card.entry.name]) or 0
		card.amount = amount
		card.seen = amount > 0
		if card.seen then
			caught += 1
		end
		card.status.BackgroundColor3 = if card.seen then RARITY[card.entry.rarity].color else C.Dim
		card.name.TextColor3 = if card.seen then C.White else C.Dim
		card.rarity.TextTransparency = if card.seen then 0 else .45
		card.count.Text = if card.seen
			then Copy.CollectionCount .. "  ×" .. amount
			else Copy.CollectionMissing
		card.count.TextColor3 = if card.seen then C.Muted else C.Dim
		-- Uncollected specimens are shown as silhouettes: you can see what you are
		-- missing without the log pretending you caught it.
		for _, part in card.stage.view.parts do
			part.part.Transparency = if card.seen then 0 else .72
		end
		for _, item in card.stage.stage:GetChildren() do
			if item:IsA("BasePart") and (item.Name == "Plinth" or item.Name == "Rim") then
				item.Transparency = if card.seen then (if item.Name == "Rim" then .35 else 0) else .85
			end
		end
		card.stage.rim.Color = RARITY[card.entry.rarity].color
	end
	if row then
		self.subtitle.Text = string.format(
			"%d / %d CHARACTERS LOGGED  •  %d CELLS CAUGHT THIS SESSION  •  %d COINS",
			caught, #self.cards, row.pickups or 0, row.coins or 0)
	else
		self.subtitle.Text = string.format("%d / %d CHARACTERS LOGGED", caught, #self.cards)
	end
	self.progress.Text = string.format("%d / %d", caught, #self.cards)
	self.progress.TextColor3 = if caught == #self.cards then C.Amber else C.Cyan
end

function Collection:resize(width, height)
	local compact = width < 780
	local columns = if compact then 2 else 3
	self.layout.FillDirectionMaxCells = columns
	self.layout.CellSize = if compact then UDim2.fromOffset(140, 178)
		else UDim2.fromOffset(150, 196)
	self.panel.Size = UDim2.new(1, -24, 1, -24)
	self.heading.TextSize = if compact then 18 else Type.Title
	self.subtitle.Visible = not compact
	self.hint.Visible = not compact
	for _, card in self.cards do
		card.frame.Size = self.layout.CellSize
		local cardWidth = self.layout.CellSize.X.Offset
		local cardHeight = self.layout.CellSize.Y.Offset
		card.stage.viewport.Size = UDim2.fromOffset(cardWidth - 4, cardHeight - 88)
		card.name.Position = UDim2.fromOffset(24, cardHeight - 84)
		card.rarity.Position = UDim2.fromOffset(24, cardHeight - 66)
		card.count.Position = UDim2.fromOffset(9, cardHeight - 50)
		card.blurb.Position = UDim2.fromOffset(9, cardHeight - 30)
		card.status.Position = UDim2.fromOffset(10, cardHeight - 72)
	end
	self.visibleHeight = height
end

function Collection:show()
	self.frame.Visible = true
end

function Collection:hide()
	self.frame.Visible = false
end

function Collection:isVisible()
	return self.frame.Visible == true
end

-- Turntable + idle animation for every visible card. Called from the HUD tick.
function Collection:step(now, reducedMotion)
	if not self.frame.Visible then
		return
	end
	for _, card in self.cards do
		local stage = card.stage
		local idle = stage.view.idle
		if reducedMotion then
			stage.view.model:PivotTo(CFrame.new(0, -.62, 0))
		else
			-- A slow turntable plus the character's own idle: it reads as a display
			-- case, not a static thumbnail.
			local spin = (now * .45 + card.entry.index * .6) % (math.pi * 2)
			local bob = math.sin(now * idle.Rate * 1.4 + card.entry.index) * .04
			Creatures.Idle(stage.view, now + card.entry.index * .7, false)
			stage.view.model:PivotTo(CFrame.new(0, -.62 + bob, 0) * CFrame.Angles(0, spin, 0))
		end
	end
end

function Collection:destroy()
	self.frame:Destroy()
end

return Collection
