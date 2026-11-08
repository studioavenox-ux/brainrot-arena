--!nonstrict
-- Lightweight local cosmetics. The server's invisible pickup positions never move.
--
-- Each server cell gets one real character Model (src/client/Creatures.luau) with a
-- floating name + rarity card, an idle animation, a shared hover ring and a pickup
-- burst. Everything is built from the generated part tables, so what a client draws
-- is exactly what the server says that cell is.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Iconography = require(script.Parent.Iconography)
local Creatures = require(script.Parent.Creatures)
local Effects = {}
Effects.__index = Effects

local RARITY_COLOR = {
	Common = Color3.fromRGB(255, 118, 196),
	Rare = Color3.fromRGB(255, 213, 67),
	Legendary = Color3.fromRGB(83, 238, 255),
}

local function fxPart(parent, name, size, color)
	local p = Instance.new("Part")
	p.Name, p.Size, p.Color = name, size, color
	p.Anchored = true
	p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = false, false, false, false
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

function Effects.new(hud, config)
	local self = setmetatable({
		hud = hud, config = config, visuals = {}, connections = {}, accumulator = 0,
		eventActive = false, lastTone = 0, bursts = {},
	}, Effects)
	self.folder = Instance.new("Folder")
	self.folder.Name = "BrainrotClientFX"
	self.folder.Parent = Workspace
	-- Owned by the client so the low-gravity pulse is purely local feedback.
	-- Saturation stays near neutral: the environment must never look washed out.
	self.tint = Instance.new("ColorCorrectionEffect")
	self.tint.Name = "BrainrotEventTint"
	self.tint.Parent = Lighting
	local pickups = Workspace:WaitForChild("BrainrotPickups")
	for _, child in pickups:GetChildren() do self:add(child) end
	table.insert(self.connections, pickups.ChildAdded:Connect(function(child) self:add(child) end))
	table.insert(self.connections, pickups.ChildRemoved:Connect(function(child) self:remove(child) end))
	table.insert(self.connections, RunService.RenderStepped:Connect(function(dt) self:step(dt) end))
	return self
end

local function kindColor(config, value)
	for _, kind in config.Kinds do
		if kind.Value == value then
			return Color3.fromRGB(kind.Color[1], kind.Color[2], kind.Color[3])
		end
	end
	return Color3.new(1, 1, 1)
end

function Effects:refresh(part)
	local view = self.visuals[part]
	if not view then
		return
	end
	view.active = part:GetAttribute("Active") == true
	view.value = part:GetAttribute("Value") or 1
	view.species = part:GetAttribute("Species") or view.species
	view.displayId = part:GetAttribute("DisplayId") or view.displayId
	self:syncCharacter(view)
	local shown = view.active and view.near
	for _, entry in view.character.parts do
		entry.part.Transparency = if shown then 0 else 1
	end
	if view.character.label then
		view.character.label.gui.Enabled = shown
	end
	-- One neutral self-lit ring per cell: guarantees separation from pale sand and
	-- stone without tinting the character itself.
	view.halo.Transparency = if shown then .34 else 1
	view.halo.Color = Color3.new(1, 1, 1)
	Iconography.apply(view.marks, view.value, view.base, shown)
end

function Effects:add(part)
	if not part:IsA("BasePart") or self.visuals[part] then
		return
	end
	part.LocalTransparencyModifier = 1
	local slotId = part:GetAttribute("SlotId") or 0
	local model = Instance.new("Model")
	model.Name = "CellVisual_" .. tostring(slotId)
	local pivot = fxPart(model, "Pivot", Vector3.new(.1, .1, .1), part.Color)
	pivot.Transparency = 1
	pivot.CFrame = CFrame.new(part.Position)
	model.PrimaryPart = pivot
	local halo = Creatures.halo(model)
	local view = {
		model = model, pivot = pivot, halo = halo, slotId = slotId,
		character = nil, species = nil, displayId = nil, value = 0, base = part.Color,
		marks = nil, active = true, near = true, phase = slotId * .77,
		previous = nil,
	}
	model.Parent = self.folder
	self.visuals[part] = view
	view.connection = part.AttributeChanged:Connect(function()
		self:refresh(part)
	end)
	self:refresh(part)
end

-- Build (or rebuild) the character model for a cell. A rebuild only happens when the
-- server says a different character now occupies the slot — a respawn of the same
-- character just resets it, and a rarity change swaps it with a small pop.
function Effects:syncCharacter(view)
	local value = view.value
	local species = view.species or Creatures.variantFor(view.slotId, value)
	local base = kindColor(self.config, value)
	view.base = base
	local stale = view.character and (view.character.name ~= species
		or view.character.value ~= value
		or (view.displayId ~= nil and view.character.displayId ~= view.displayId))
	if not stale then
		if view.character then
			-- Same character: only the rarity tint can have changed.
			Creatures.SetColor(view.character, base)
			return
		end
	end
	if view.character then
		view.previous = { model = view.character.model, at = os.clock() }
		local previous = view.previous
		task.delay(.32, function()
			-- Retire the outgoing model a beat later so a swap never pops.
			if previous.model and previous.model.Parent then
				previous.model:Destroy()
			end
		end)
	end
	if view.marks then
		for _, item in view.marks.parts do
			item:Destroy()
		end
	end
	local character = Creatures.Build(view.model, species, value, base, { phase = view.phase })
	character.displayId = view.displayId
	view.character = character
	-- Rarity mark in world space, so shape reads value before the label is legible.
	view.marks = Iconography.marks(view.model, base,
		if value == 5 then "crown" elseif value == 10 then "arms" else "none")
	Iconography.apply(view.marks, value, base, view.active and view.near)
	-- Placement: the model's parts are authored around a local origin, so the whole
	-- cell is positioned by moving the pivot (the Model primary part).
	character.model:PivotTo(CFrame.new(view.pivot.Position))
end

function Effects:remove(part)
	local view = self.visuals[part]
	if not view then
		return
	end
	view.connection:Disconnect()
	view.model:Destroy()
	self.visuals[part] = nil
end

function Effects:step(dt)
	self.accumulator += dt
	if self.accumulator < 1 / 30 then
		return
	end
	self.accumulator = 0
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local reduced = self.hud.reducedMotion
	local eye = camera.CFrame.Position
	for part, view in self.visuals do
		local near = (part.Position - eye).Magnitude < 150
		if view.near ~= near then
			view.near = near
			self:refresh(part)
		end
		if view.active and near and view.character then
			local character = view.character
			local hover = if reduced then 0
				else math.sin((now + view.phase) * character.idle.Rate * 1.6) * character.idle.Bob
			local spin = if reduced then 0 else ((now + view.phase) * character.idle.Spin) % (math.pi * 2)
			-- Rare and legendary characters breathe a little more, so value reads
			-- before the player is close enough for the name card.
			if view.value > 1 and not reduced then
				view.halo.Transparency = .24 + math.sin((now + view.phase) * 3.1) * .1
			end
			-- Idle animations (bob, sway, jaw, arm swing, tail wag) run per character.
			Creatures.Idle(character, now + view.phase, reduced)
			character.model:PivotTo(
				CFrame.new(part.Position + Vector3.new(0, hover, 0))
					* CFrame.Angles(0, spin, 0)
			)
		end
	end
end

function Effects:update(state)
	if state.eventActive == self.eventActive then
		return
	end
	self.eventActive = state.eventActive
	local properties = {
		TintColor = if state.eventActive then Color3.fromRGB(236, 246, 255) else Color3.new(1, 1, 1),
		Saturation = if state.eventActive then .05 else 0,
		Brightness = if state.eventActive then .02 else 0,
	}
	if self.hud.reducedMotion then
		for key, value in properties do
			self.tint[key] = value
		end
	else
		TweenService:Create(self.tint, TweenInfo.new(.6), properties):Play()
	end
end

-- The pickup effect: a collect animation on the character that was just taken, a
-- burst of the rarity colour, and the score popup.
function Effects:pickup(receipt)
	local own = receipt.userId == Players.LocalPlayer.UserId
	local pos = Vector3.new(receipt.position.x, receipt.position.y, receipt.position.z)
	local tint = kindColor(self.config, receipt.value)
	if receipt.kindIndex and self.config.Kinds[receipt.kindIndex] then
		local kind = self.config.Kinds[receipt.kindIndex]
		tint = Color3.fromRGB(kind.Color[1], kind.Color[2], kind.Color[3])
	end
	local species = receipt.species
	-- Collect animation: the collected character spins, pops and lifts away.
	if species then
		local model = Creatures.Build(self.folder, species, receipt.value, tint,
			{ label = false, phase = 0 })
		model.root.Transparency = 1
		local label = Creatures.attachLabel(model.model, species, receipt.value,
			{ width = 140, height = 44 })
		if label then
			label.name.Text = "+" .. tostring(receipt.value)
			label.rarity.Text = string.upper(Creatures.rarityOf(species))
		end
		self:collectAnimation(model, pos, tint)
	end
	if own then
		self.hud:pulse()
		local now = os.clock()
		if self.hud.soundOn and now - self.lastTone > .07 then
			self.lastTone = now
			local sound = Instance.new("Sound")
			sound.Name = "CellChime"
			-- Roblox's bundled short tone; no uploaded or third-party sound assets required.
			sound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
			sound.Volume = .2
			sound.PlaybackSpeed = .95 + (receipt.kindIndex or 1) * .12
			sound.Parent = SoundService
			sound:Play()
			Debris:AddItem(sound, 3)
		end
		local anchor = fxPart(self.folder, "ScorePopup", Vector3.new(.1, .1, .1), tint)
		anchor.Position, anchor.Transparency = pos + Vector3.new(0, 2, 0), 1
		local gui = Instance.new("BillboardGui")
		gui.Size, gui.AlwaysOnTop, gui.MaxDistance = UDim2.fromOffset(100, 50), true, 100
		gui.Parent = anchor
		local label = Instance.new("TextLabel")
		label.Size, label.BackgroundTransparency = UDim2.fromScale(1, 1), 1
		label.Text, label.TextColor3 = "+" .. receipt.value, tint
		label.Font, label.TextSize, label.TextStrokeTransparency = Enum.Font.GothamBlack, 32, .6
		label.Parent = gui
		TweenService:Create(anchor, TweenInfo.new(.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = anchor.Position + Vector3.new(0, 2.8, 0) }):Play()
		TweenService:Create(label, TweenInfo.new(.7), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		Debris:AddItem(anchor, .8)
	end
	local camera = Workspace.CurrentCamera
	if self.hud.reducedMotion or not camera or (camera.CFrame.Position - pos).Magnitude > 100 then
		return
	end
	-- Burst: a ring of neon sparks in the rarity colour, plus a rising halo ring that
	-- expands and fades. Deliberately cheap: 8 parts, all recycled by Debris.
	for i = 1, 7 do
		local spark = fxPart(self.folder, "Spark", Vector3.new(.3, .3, .3), tint)
		spark.Shape, spark.Material, spark.Position = Enum.PartType.Ball, Enum.Material.Neon, pos
		local angle = i * math.pi * 2 / 7
		local target = pos + Vector3.new(math.cos(angle) * 2.2, 1.5 + (i % 3) * .6, math.sin(angle) * 2.2)
		TweenService:Create(spark, TweenInfo.new(.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = target, Size = Vector3.new(.05, .05, .05), Transparency = 1 }):Play()
		Debris:AddItem(spark, .5)
	end
	local ring = fxPart(self.folder, "BurstRing", Vector3.new(.06, .8, .8), tint)
	ring.Shape, ring.Material, ring.Position = Enum.PartType.Cylinder, Enum.Material.Neon, pos
	ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2)
	TweenService:Create(ring, TweenInfo.new(.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(.06, 3.4, 3.4), Transparency = 1 }):Play()
	Debris:AddItem(ring, .55)
end

-- 0.5 s collect flourish on a throwaway model, then it is destroyed.
function Effects:collectAnimation(view, pos, tint)
	local start = os.clock()
	view.model:PivotTo(CFrame.new(pos))
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local progress = (os.clock() - start) / .5
		if progress >= 1 or not view.model.Parent then
			connection:Disconnect()
			view.model:Destroy()
			return
		end
		if self.hud.reducedMotion then
			return
		end
		Creatures.Collect(view, progress, false)
		-- The character itself lifts to the player's eye line as it flies away.
		local lifted = pos + Vector3.new(0, 1.2 + progress * 2.4, 0)
			+ Vector3.new(math.sin(progress * 6) * .3, 0, 0)
		view.model:PivotTo(CFrame.new(lifted) * CFrame.Angles(0, progress * math.pi * 2, 0))
		for _, entry in view.parts do
			entry.part.Transparency = math.max(0, (progress - .55) / .45)
		end
		if view.label then
			view.label.name.TextTransparency = math.max(0, (progress - .4) / .4)
			view.label.rarity.TextTransparency = view.label.name.TextTransparency
		end
	end)
	table.insert(self.connections, connection)
end

function Effects:destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	local parts = {}
	for part in self.visuals do
		table.insert(parts, part)
	end
	for _, part in parts do
		self:remove(part)
	end
	self.folder:Destroy()
	self.tint:Destroy()
end

return Effects
