--!nonstrict
-- Lightweight local cosmetics. The server's invisible pickup positions never move.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
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
	self.tint = Instance.new("ColorCorrectionEffect")
	self.tint.Name = "BrainrotChaosTint"
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
	view.value = part:GetAttribute("Value") or 1
	local base = part.Color
	for _, kind in self.config.Kinds do
		if kind.Value == view.value then base = Color3.fromRGB(kind.Color[1], kind.Color[2], kind.Color[3]); break end
	end
	for index, lobe in view.lobes do
		lobe.Color = if view.value == 10 and index%2 == 0 then Color3.fromRGB(193, 122, 255) else base:Lerp(Color3.new(1, 1, 1), if index%3 == 0 then .13 else 0)
		lobe.Material = if view.value == 1 then Enum.Material.SmoothPlastic else Enum.Material.Neon
		lobe.Transparency = if view.active and view.near then 0 else 1
	end
	view.seam.Transparency = if view.active and view.near then 0 else 1
end

function Effects:add(part)
	if not part:IsA("BasePart") or self.visuals[part] then return end
	part.LocalTransparencyModifier = 1
	local model = Instance.new("Model")
	model.Name = "CellVisual_" .. tostring(part:GetAttribute("SlotId") or 0)
	local pivot = fxPart(model, "Pivot", Vector3.new(.1, .1, .1), part.Color)
	pivot.Transparency = 1
	pivot.CFrame = CFrame.new(part.Position)
	model.PrimaryPart = pivot
	local lobes = {}
	for side = -1, 1, 2 do
		for row = 1, 3 do
			local lobe = fxPart(model, "Lobe", Vector3.new(.98, 1.1, .92), part.Color)
			lobe.Shape = Enum.PartType.Ball
			lobe.CFrame = CFrame.new(part.Position) * CFrame.new(side*.38, if row == 2 then .15 else 0, (row-2)*.46)
			table.insert(lobes, lobe)
		end
	end
	local seam = fxPart(model, "Split", Vector3.new(.09, .95, 1.35), Color3.fromRGB(144, 61, 178))
	seam.CFrame = CFrame.new(part.Position + Vector3.new(0, .08, 0))
	model.Parent = self.folder
	local view = { model = model, lobes = lobes, seam = seam, active = true, near = true, value = 1, phase = (part:GetAttribute("SlotId") or 0)*.77 }
	self.visuals[part] = view
	view.connection = part.AttributeChanged:Connect(function() self:refresh(part) end)
	self:refresh(part)
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
	for part, view in self.visuals do
		local near = (part.Position-camera.CFrame.Position).Magnitude < 150
		if view.near ~= near then view.near = near; self:refresh(part) end
		if view.active and near then
			local bob = if self.hud.reducedMotion then 0 else math.sin(now*2+view.phase)*.28
			local angle = if self.hud.reducedMotion then 0 else (now*.7+view.phase) % (math.pi*2)
			view.model:PivotTo(CFrame.new(part.Position + Vector3.new(0, bob, 0)) * CFrame.Angles(0, angle, 0))
		end
	end
end

function Effects:update(state)
	if state.eventActive == self.eventActive then return end
	self.eventActive = state.eventActive
	local properties = {
		TintColor = if state.eventActive then Color3.fromRGB(238, 228, 255) else Color3.new(1, 1, 1),
		Saturation = if state.eventActive then .08 else 0,
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
