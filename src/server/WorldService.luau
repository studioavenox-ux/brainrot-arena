--!strict
-- The downloadable place already contains the map. Rojo users get this exact map at runtime.
local Workspace = game:GetService("Workspace")
local Data = require(script.Parent.WorldData)
local WorldService = {}
WorldService.__index = WorldService

local function rgb(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end
local function vector(values: { number }): Vector3
	return Vector3.new(values[1], values[2], values[3])
end

local function makeSign(parent: BasePart, lines)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(1200, math.max(100, math.floor(1200 * parent.Size.Y / parent.Size.X)))
	gui.LightInfluence = 0
	gui.Parent = parent
	local total = 0
	for _, line in lines do
		total += line.Fraction
	end
	local y = 0.04
	for index, line in lines do
		local label = Instance.new("TextLabel")
		label.Name = "Line" .. index
		local height = 0.92 * line.Fraction / total
		label.Position = UDim2.fromScale(0.04, y)
		label.Size = UDim2.fromScale(0.92, height)
		label.BackgroundTransparency = 1
		label.Text = line.Text
		label.TextColor3 = rgb(line.Color)
		label.TextScaled = true
		label.TextWrapped = true
		label.Font = Enum.Font.GothamBold
		label.TextStrokeTransparency = 0.8
		label.Parent = gui
		y += height
	end
end

function WorldService.new()
	local root = Workspace:FindFirstChild("BrainrotWorld")
	if not root then
		local model = Instance.new("Model")
		model.Name = "BrainrotWorld"
		local lookup: { [string]: BasePart } = {}
		for _, spec in Data.Parts do
			local part = Instance.new(spec.Class) :: BasePart
			part.Name = spec.Name
			part.Size = vector(spec.Size)
			part.CFrame = CFrame.new(vector(spec.Position)) * CFrame.Angles(
				math.rad(spec.Rotation[1]), math.rad(spec.Rotation[2]), math.rad(spec.Rotation[3])
			)
			part.Color = rgb(spec.Color)
			part.Material = Enum.Material[spec.Material]
			part.Anchored = true
			part.CanCollide = spec.Collide
			part.CanTouch = spec.Class == "SpawnLocation"
			part.CanQuery = spec.Collide
			part.CastShadow = spec.Material ~= "Neon"
			part.Transparency = spec.Transparency
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			if part:IsA("Part") then
				part.Shape = Enum.PartType[spec.Shape]
			end
			if part:IsA("SpawnLocation") then
				part.Neutral = true
				part.Duration = 0
				part.AllowTeamChangeOnTouch = false
			end
			if spec.Name == "ChaosAccent_BeaconTop" then
				local light = Instance.new("PointLight")
				light.Name = "BeaconLight"
				light.Color = Color3.fromRGB(255, 130, 221)
				light.Brightness = 1.5
				light.Range = 28
				light.Parent = part
			end
			part.Parent = model
			lookup[spec.Name] = part
		end
		for _, sign in Data.Signs do
			makeSign(lookup[sign.Part], sign.Lines)
		end
		model.Parent = Workspace
		root = model
	end
	local spawn = root:FindFirstChild("LobbySpawn")
	assert(spawn and spawn:IsA("SpawnLocation"), "BrainrotWorld is missing LobbySpawn")
	local queueBoard = root:FindFirstChild("QueueStatusBoard")
	assert(queueBoard, "Missing queue board")
	local status = queueBoard:FindFirstChild("Line1", true) :: TextLabel?
	local accents: { BasePart } = {}
	for _, child in root:GetChildren() do
		if child:IsA("BasePart") and string.sub(child.Name, 1, 12) == "ChaosAccent_" then
			table.insert(accents, child)
			child:SetAttribute("RestColor", child.Color)
		end
	end
	return setmetatable({ root = root, lobbySpawn = spawn, status = status, accents = accents }, WorldService)
end

function WorldService.spawnCFrame(_self, arena: boolean, index: number): CFrame
	local positions = if arena then Data.ArenaSpawns else Data.LobbySpawns
	local position = vector(positions[(index - 1) % #positions + 1])
	local target = if arena then Vector3.new(0, position.Y, 0) else Vector3.new(0, position.Y, 155)
	return CFrame.lookAt(position, target)
end

function WorldService.setLowGravity(self, active: boolean)
	for _, part in self.accents do
		part.Color = if active then Color3.fromRGB(177, 122, 255) else part:GetAttribute("RestColor")
	end
end

function WorldService.setStatus(self, phase: string, remaining: number)
	if not self.status then
		return
	end
	if phase == "Playing" then
		self.status.Text = "ROUND LIVE • AUTO JOIN"
	elseif phase == "Intermission" then
		self.status.Text = string.format("AUTO JOIN IN %02d:%02d", math.floor(remaining / 60), remaining % 60)
	elseif phase == "Results" then
		self.status.Text = "NICE BRAIN. NEXT ROUND SOON."
	else
		self.status.Text = "AUTO JOIN • EVERY ROUND"
	end
end

return WorldService
