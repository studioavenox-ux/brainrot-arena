--!nonstrict
-- Lightweight local cosmetics. The server's invisible pickup positions never move.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Iconography = require(script.Parent.Iconography)
local Creatures = require(script.Parent.Creatures)
local CreatureData = require(script.Parent.CreatureData)
local Effects = {}
Effects.__index = Effects

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
	local self = setmetatable({ hud = hud, config = config, visuals = {}, connections = {}, accumulator = 0, eventActive = false, lastTone = 0 }, Effects)
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

function Effects:refresh(part)
	local view = self.visuals[part]
	if not view then return end
	view.active = part:GetAttribute("Active") == true
	local value = part:GetAttribute("Value") or 1
	local base = part.Color
	for _, kind in self.config.Kinds do
		if kind.Value == value then
			base = Color3.fromRGB(kind.Color[1], kind.Color[2], kind.Color[3])
			break
		end
	end
	self:syncCreature(view, value, base)
	local shown = view.active and view.near
	for _, item in view.creature.parts do
		item.Transparency = if shown then 0 else 1
	end
	-- One neutral self-lit ring per cell: guarantees separation from pale sand and
	-- stone without tinting the creature itself.
	view.halo.Transparency = if shown then .34 else 1
	view.halo.Color = Color3.new(1, 1, 1)
	Iconography.apply(view.marks, view.value, base, shown)
end

function Effects:add(part)
	if not part:IsA("BasePart") or self.visuals[part] then return end
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
		creature = nil, value = 0, marks = nil,
		active = true, near = true, phase = slotId * .77,
	}
	model.Parent = self.folder
	self.visuals[part] = view
	view.connection = part.AttributeChanged:Connect(function() self:refresh(part) end)
	self:refresh(part)
end

-- Rebuild only when the rarity (and therefore the creature family) changes.
function Effects:syncCreature(view, value, base)
	if view.value ~= value or not view.creature then
		if view.creature then
			for _, item in view.creature.parts do item:Destroy() end
		end
		view.creature = Creatures.build(view.model, view.slotId, value, base)
		view.value = value
		if view.marks then
			for _, item in view.marks.parts do item:Destroy() end
		end
		view.marks = Iconography.marks(view.model, base, CreatureData.Mark[value] or "none")
		Iconography.apply(view.marks, value, base, view.active and view.near)
	else
		Creatures.recolour(view.creature, base)
	end
end

function Effects:remove(part)
	local view = self.visuals[part]
	if not view then return end
	view.connection:Disconnect()
	view.model:Destroy()
	self.visuals[part] = nil
end

function Effects:step(dt)
	self.accumulator += dt
	if self.accumulator < 1/30 then return end
	self.accumulator = 0
	local camera = Workspace.CurrentCamera
	if not camera then return end
	local now = Workspace:GetServerTimeNow()
	local reduced = self.hud.reducedMotion
	local eye = camera.CFrame.Position
	for part, view in self.visuals do
		local near = (part.Position - eye).Magnitude < 150
		if view.near ~= near then
			view.near = near
			self:refresh(part)
		end
		if view.active and near then
			local phase = now + view.phase
			local hover = if reduced then 0 else math.sin(phase * 1.9) * .24
			local spin = if reduced then 0 else (phase * .55) % (math.pi * 2)
			-- Rare cells breathe a little more so value reads before the player is close.
		local flourish = if reduced or view.value == 1 then 0
				else math.sin(phase * 2.6) * (if view.value == 10 then .07 else .04)
			local tilt = if reduced then 0 else math.sin(phase * 1.1) * .05
			-- Rare cells breathe: the ring tells you it is worth more before you read it.
			if view.value > 1 then
				view.halo.Transparency = .26 + math.sin(phase * 3.1) * .1
			end
			view.model:PivotTo(
				CFrame.new(part.Position + Vector3.new(0, hover, 0))
					* CFrame.Angles(tilt, spin, 0)
					* CFrame.new(0, flourish, 0)
			)
		end
	end
end

function Effects:update(state)
	if state.eventActive == self.eventActive then return end
	self.eventActive = state.eventActive
	local properties = {
		TintColor = if state.eventActive then Color3.fromRGB(236, 246, 255) else Color3.new(1, 1, 1),
		Saturation = if state.eventActive then .05 else 0,
		Brightness = if state.eventActive then .02 else 0,
	}
	if self.hud.reducedMotion then
		for key, value in properties do self.tint[key] = value end
	else
		TweenService:Create(self.tint, TweenInfo.new(.6), properties):Play()
	end
end

function Effects:pickup(receipt)
	local own = receipt.userId == Players.LocalPlayer.UserId
	local pos = Vector3.new(receipt.position.x, receipt.position.y, receipt.position.z)
	local color = self.config.Kinds[receipt.kindIndex].Color
	local tint = Color3.fromRGB(color[1], color[2], color[3])
	if own then
		self.hud:pulse()
		local now = os.clock()
		if self.hud.soundOn and now-self.lastTone > .07 then
			self.lastTone = now
			local sound = Instance.new("Sound")
			sound.Name = "CellChime"
			-- Roblox's bundled short tone; no uploaded or third-party sound assets required.
			sound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
			sound.Volume = .2
			sound.PlaybackSpeed = .95 + receipt.kindIndex*.12
			sound.Parent = SoundService
			sound:Play()
			Debris:AddItem(sound, 3)
		end
		local anchor = fxPart(self.folder, "ScorePopup", Vector3.new(.1, .1, .1), tint)
		anchor.Position, anchor.Transparency = pos+Vector3.new(0, 2, 0), 1
		local gui = Instance.new("BillboardGui")
		gui.Size, gui.AlwaysOnTop, gui.MaxDistance = UDim2.fromOffset(100, 50), true, 100
		gui.Parent = anchor
		local label = Instance.new("TextLabel")
		label.Size, label.BackgroundTransparency = UDim2.fromScale(1, 1), 1
		label.Text, label.TextColor3 = "+" .. receipt.value, tint
		label.Font, label.TextSize, label.TextStrokeTransparency = Enum.Font.GothamBlack, 32, .6
		label.Parent = gui
		TweenService:Create(anchor, TweenInfo.new(.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = anchor.Position+Vector3.new(0, 2.8, 0) }):Play()
		TweenService:Create(label, TweenInfo.new(.7), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		Debris:AddItem(anchor, .8)
	end
	local camera = Workspace.CurrentCamera
	if self.hud.reducedMotion or not camera or (camera.CFrame.Position-pos).Magnitude > 100 then return end
	for i = 1, 7 do
		local spark = fxPart(self.folder, "Spark", Vector3.new(.3, .3, .3), tint)
		spark.Shape, spark.Material, spark.Position = Enum.PartType.Ball, Enum.Material.Neon, pos
		local angle = i*math.pi*2/7
		local target = pos + Vector3.new(math.cos(angle)*2.2, 1.5+(i%3)*.6, math.sin(angle)*2.2)
		TweenService:Create(spark, TweenInfo.new(.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = target, Size = Vector3.new(.05, .05, .05), Transparency = 1 }):Play()
		Debris:AddItem(spark, .5)
	end
end

function Effects:destroy()
	for _, connection in self.connections do connection:Disconnect() end
	local parts = {}
	for part in self.visuals do table.insert(parts, part) end
	for _, part in parts do self:remove(part) end
	self.folder:Destroy()
	self.tint:Destroy()
end

return Effects
