--!strict
-- Roblox adapter. Only this server script can award cells, pay coins, or unlock cosmetics.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("BrainrotShared"):WaitForChild("Config"))
local RoundMachine = require(script.Parent.core.RoundMachine)
local PickupLedger = require(script.Parent.core.PickupLedger)
local MovementGuard = require(script.Parent.core.MovementGuard)
local WorldService = require(script.Parent.WorldService)
local WorldData = require(script.Parent.WorldData)

local settings = table.clone(Config)
local fast = RunService:IsStudio() and Config.StudioFastMode
settings.Timing = if fast then Config.FastTiming else Config.Timing
local machine = RoundMachine.new(settings)
local random = Random.new()
local ledger = PickupLedger.new(WorldData.PickupPositions, Config.Kinds, Config.PickupRadius, Config.PickupRespawn, function()
	return random:NextNumber()
end)
local movement = MovementGuard.new(Config.MaxHorizontalSpeed, Config.MovementSlack, Config.SpawnProtection)
local world = WorldService.new()
Workspace.Gravity = Config.NormalGravity
Workspace.FallenPartsDestroyHeight = -160
Players.RespawnTime = 2

local remotes = Instance.new("Folder")
remotes.Name = "BrainrotRemotes"
local stateRemote = Instance.new("RemoteEvent")
stateRemote.Name = "State"
stateRemote.Parent = remotes
local pickupRemote = Instance.new("RemoteEvent")
pickupRemote.Name = "Pickup"
pickupRemote.Parent = remotes
local requestRemote = Instance.new("RemoteEvent")
requestRemote.Name = "Request"
requestRemote.Parent = remotes
remotes.Parent = ReplicatedStorage

local pickupFolder = Instance.new("Folder")
pickupFolder.Name = "BrainrotPickups"
pickupFolder.Parent = Workspace
local pickupParts: { [number]: Part } = {}
type Record = { spawnIndex: number, connection: RBXScriptConnection?, requests: { [string]: number } }
local records: { [number]: Record } = {}
local nextSpawn = 0
local dirty = true
local lastBroadcast = 0
local lastBoardSecond = -1

local function position(v: Vector3)
	return { x = v.X, y = v.Y, z = v.Z }
end

local function syncStats()
	for _, player in Players:GetPlayers() do
		local data = machine.players[player.UserId]
		local stats = player:FindFirstChild("leaderstats")
		if data and stats then
			local cells = stats:FindFirstChild("Brain Cells") :: IntValue
			local coins = stats:FindFirstChild("Coins") :: IntValue
			local wins = stats:FindFirstChild("Wins") :: IntValue
			cells.Value = data.score
			coins.Value = data.coins
			wins.Value = data.wins
		end
	end
end

local function snapshot()
	local state = machine:snapshot()
	-- Only plain serializable arrays / string-key dictionaries cross remotes.
	return {
		phase = state.phase, roundId = state.roundId, phaseEndsAt = state.phaseEndsAt,
		eventActive = state.eventActive, eventEndsAt = state.eventEndsAt,
		rows = state.rows, results = state.results,
		fastMode = fast, version = Config.Version,
	}
end

local function applyHalo(player: Player)
	local character = player.Character
	local data = machine.players[player.UserId]
	if not character then
		return
	end
	local previous = character:FindFirstChild("PulseHalo")
	if previous then
		previous:Destroy()
	end
	local head = character:FindFirstChild("Head")
	if not data or not data.haloEquipped or not head or not head:IsA("BasePart") then
		return
	end
	local model = Instance.new("Model")
	model.Name = "PulseHalo"
	for i = 0, 7 do
		local angle = i * math.pi / 4
		local segment = Instance.new("Part")
		segment.Name = "Glow"
		segment.Size = Vector3.new(0.8, 0.16, 0.25)
		segment.Material = Enum.Material.Neon
		segment.Color = Color3.fromRGB(83, 238, 255)
		segment.CanCollide = false
		segment.CanTouch = false
		segment.CanQuery = false
		segment.Massless = true
		segment.CastShadow = false
		segment.CFrame = head.CFrame * CFrame.new(math.cos(angle)*1.3, 1.4, math.sin(angle)*1.3) * CFrame.Angles(0, -angle+math.pi/2, 0)
		segment.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = segment
		weld.Parent = segment
	end
	model.Parent = character
end

local function teleport(player: Player, arena: boolean, now: number)
	local character = player.Character
	local record = records[player.UserId]
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not character or not record or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end
	local target = world:spawnCFrame(arena, record.spawnIndex)
	character:PivotTo(target)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	humanoid.WalkSpeed = Config.WalkSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = Config.JumpPower
	movement:teleport(player.UserId, position(target.Position), now)
end

local function updatePickup(slotId: number)
	local slot = ledger.slots[slotId]
	local part = pickupParts[slotId]
	if not part then
		return
	end
	local kind = Config.Kinds[slot.kindIndex]
	part.Color = Color3.fromRGB(kind.Color[1], kind.Color[2], kind.Color[3])
	part.Transparency = if slot.available then 0 else 1
	part:SetAttribute("Kind", kind.Name)
	part:SetAttribute("Value", kind.Value)
	part:SetAttribute("Generation", slot.generation)
	part:SetAttribute("Active", slot.available)
end

local function spawnPickups()
	pickupFolder:ClearAllChildren()
	table.clear(pickupParts)
	for _, slot in ledger.slots do
		local part = Instance.new("Part")
		part.Name = "BrainCell_" .. slot.id
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(1.7, 1.7, 1.7)
		part.Position = Vector3.new(slot.position.x, slot.position.y, slot.position.z)
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part:SetAttribute("SlotId", slot.id)
		pickupParts[slot.id] = part
		updatePickup(slot.id)
		part.Parent = pickupFolder
	end
end

local function setGravity(active: boolean)
	Workspace.Gravity = if active then Config.LowGravity else Config.NormalGravity
	world:setLowGravity(active)
end

local function checkInvariants()
	if not RunService:IsStudio() then
		return
	end
	assert(ledger.running == (machine.phase == "Playing"), "Pickup lifecycle diverged")
	assert(math.abs(Workspace.Gravity - (if machine.eventActive then Config.LowGravity else Config.NormalGravity)) < 0.01, "Gravity failed to reset")
	local previous = math.huge
	for _, row in machine:rows() do
		assert(row.score >= 0 and row.score % 1 == 0 and row.score <= previous, "Invalid score ordering")
		assert(row.coins >= 0 and row.coins % 1 == 0, "Invalid coin balance")
		previous = row.score
	end
	if ledger.running then
		assert(#pickupFolder:GetChildren() == #WorldData.PickupPositions, "Missing pickup replicas")
	else
		assert(#pickupFolder:GetChildren() == 0, "Pickups leaked outside round")
	end
end

local function handleEffects(effects, now: number)
	for _, effect in effects do
		dirty = true
		if effect.kind == "event" then
			setGravity(effect.active == true)
			print("[Brainrot] Low gravity " .. (if effect.active then "ON" else "OFF"))
		elseif effect.kind == "phase" then
			if machine.phase == "Playing" then
				ledger:beginRound(machine.roundId)
				spawnPickups()
				for _, player in Players:GetPlayers() do
					teleport(player, true, now)
				end
			else
				ledger:clear()
				pickupFolder:ClearAllChildren()
				table.clear(pickupParts)
				setGravity(false)
				if machine.phase == "Results" then
					for _, player in Players:GetPlayers() do
						teleport(player, false, now)
					end
				end
			end
			print(string.format("[Brainrot] %s • round %d", machine.phase, machine.roundId))
		end
	end
	if #effects > 0 then
		checkInvariants()
	end
end

local function characterAdded(player: Player, character: Model)
	-- Do not yield the authority loop. Character preparation runs independently.
	task.spawn(function()
		local root = character:WaitForChild("HumanoidRootPart", 10)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not root or not humanoid or player.Parent ~= Players or player.Character ~= character then
			return
		end
		teleport(player, machine:isParticipating(player.UserId), Workspace:GetServerTimeNow())
		applyHalo(player)
	end)
end

local function playerAdded(player: Player)
	if records[player.UserId] then
		return
	end
	local accepted = machine:addPlayer(player.UserId, player.DisplayName)
	assert(accepted, "Could not register Roblox player")
	nextSpawn += 1
	local record: Record = { spawnIndex = nextSpawn, connection = nil, requests = {} }
	records[player.UserId] = record
	player.RespawnLocation = world.lobbySpawn
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	for _, name in { "Brain Cells", "Coins", "Wins" } do
		local value = Instance.new("IntValue")
		value.Name = name
		value.Parent = stats
	end
	stats.Parent = player
	record.connection = player.CharacterAdded:Connect(function(character)
		characterAdded(player, character)
	end)
	if player.Character then
		characterAdded(player, player.Character)
	end
	dirty = true
end

Players.PlayerAdded:Connect(playerAdded)
Players.PlayerRemoving:Connect(function(player)
	local record = records[player.UserId]
	if record and record.connection then
		record.connection:Disconnect()
	end
	records[player.UserId] = nil
	movement:remove(player.UserId)
	machine:removePlayer(player.UserId)
	dirty = true
end)
for _, player in Players:GetPlayers() do
	playerAdded(player)
end

requestRemote.OnServerEvent:Connect(function(player: Player, action: any, ...: any)
	-- Whitelist small verbs, reject extra arguments, and rate-limit per player/action.
	-- There is intentionally NO score, pickup ID, position, price, or coin amount API.
	if typeof(action) ~= "string" or (action ~= "Snapshot" and action ~= "Halo") or select("#", ...) ~= 0 then
		return
	end
	local record = records[player.UserId]
	if not record then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local last = record.requests[action] or -math.huge
	if now - last < (if action == "Snapshot" then 1 else 0.75) then
		return
	end
	record.requests[action] = now
	if action == "Halo" then
		local ok, message = machine:haloAction(player.UserId)
		if ok then
			applyHalo(player)
			syncStats()
			dirty = true
		end
		stateRemote:FireClient(player, snapshot(), message)
	else
		stateRemote:FireClient(player, snapshot())
	end
end)

local accumulator = 0
RunService.Heartbeat:Connect(function(dt: number)
	accumulator += dt
	if accumulator < Config.ServerStep then
		return
	end
	accumulator = 0
	local now = Workspace:GetServerTimeNow()
	handleEffects(machine:step(now), now)

	if machine.phase == "Playing" then
		for _, id in ledger:step(now) do
			updatePickup(id)
		end
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
			continue
		end
		local p = root.Position
		if p.Y < Config.RescueBelowY then
			teleport(player, machine:isParticipating(player.UserId), now)
			continue
		end
		local allowed, correction = movement:observe(player.UserId, position(p), now)
		if correction then
			root.CFrame = CFrame.new(correction.x, correction.y, correction.z)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			movement:teleport(player.UserId, correction, now)
			continue
		end
		if not allowed or not machine:isParticipating(player.UserId) then
			continue
		end
		local context = { userId = player.UserId, roundId = machine.roundId, active = true, alive = true, position = position(p) }
		for _, slot in ledger.slots do
			if slot.available then
				local receipt = ledger:tryClaim(slot.id, slot.generation, context, now)
				if receipt then
					assert(machine:award(receipt.userId, receipt.value, receipt.roundId), "Atomic award rejected")
					updatePickup(slot.id)
					pickupRemote:FireAllClients(receipt)
					dirty = true
				end
			end
		end
	end

	local second = math.ceil(now)
	if second ~= lastBoardSecond then
		lastBoardSecond = second
		world:setStatus(machine.phase, math.max(0, math.ceil(machine.phaseEndsAt - now)))
	end
	if (dirty and now - lastBroadcast >= Config.SnapshotInterval) or now - lastBroadcast >= 1 then
		syncStats()
		stateRemote:FireAllClients(snapshot())
		dirty = false
		lastBroadcast = now
	end
end)

print(string.format("[Brainrot] v%s ready • %s • %d pickup slots • %ds rounds", Config.Version, if fast then "STUDIO QUICK TEST" else "STANDARD", #ledger.slots, settings.Timing.Round))
