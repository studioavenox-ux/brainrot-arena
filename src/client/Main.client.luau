--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Config = require(ReplicatedStorage:WaitForChild("BrainrotShared"):WaitForChild("Config"))
-- Loaded before the HUD so rarity glyphs exist on the first frame.
local Iconography = require(script.Parent.Iconography)
local Hud = require(script.Parent.Hud)
local Effects = require(script.Parent.Effects)
local Audio = require(script.Parent.Audio)

-- A startup failure must be visible in Play mode, not silent. The player sees this panel,
-- and the same text goes to Output as a warning.
local function showStartupError(message: string)
	warn("[Brainrot] " .. message)
	local gui = Instance.new("ScreenGui")
	gui.Name = "BrainrotStartupError"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1000
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -40, 0, 150)
	label.Position = UDim2.new(0, 20, 0, 20)
	label.BackgroundColor3 = Color3.fromRGB(120, 20, 20)
	label.BackgroundTransparency = 0.1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextWrapped = true
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = "BRAINROT ARENA UI DID NOT START\n" .. message .. "\nOpen View > Output and send the first red error."
	label.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- Bounded waits: a missing server piece becomes a visible message, not a silent hang.
local WAIT_SECONDS = 15
local remotes = ReplicatedStorage:WaitForChild("BrainrotRemotes", WAIT_SECONDS)
if not remotes then
	showStartupError("The server did not publish BrainrotRemotes within " .. WAIT_SECONDS .. " seconds. Check the server Output for an error.")
	return
end
local function remote(name: string): RemoteEvent?
	return remotes:WaitForChild(name, WAIT_SECONDS) :: RemoteEvent?
end
local stateRemote = remote("State")
local pickupRemote = remote("Pickup")
local requestRemote = remote("Request")
local abilityRemote = remote("Ability")
local characterRemote = remote("Character")
local characterStateRemote = remote("CharacterState")
if not (stateRemote and pickupRemote and requestRemote and abilityRemote and characterRemote and characterStateRemote) then
	showStartupError("A server remote is missing from BrainrotRemotes. The server may be an older build. Check the server Output.")
	return
end
local state: RemoteEvent = stateRemote :: RemoteEvent
local pickup: RemoteEvent = pickupRemote :: RemoteEvent
local request: RemoteEvent = requestRemote :: RemoteEvent
local ability: RemoteEvent = abilityRemote :: RemoteEvent
local character: RemoteEvent = characterRemote :: RemoteEvent
local characterState: RemoteEvent = characterStateRemote :: RemoteEvent

local okHud, hud = pcall(function()
	return Hud.new(Config, function(action: string)
		request:FireServer(action)
	end, {
		-- Each verb has its own remote. Neither sends an effect, a target or a cell.
		ability = function()
			ability:FireServer()
		end,
		switch = function(slot: number)
			character:FireServer(slot)
		end,
	})
end)
if not okHud then
	showStartupError("The HUD failed to build: " .. tostring(hud))
	return
end
print("[Brainrot] HUD built")
local effects = Effects.new(hud, Config)
local audio = Audio.new(Config)
local connections: { RBXScriptConnection } = {}

table.insert(connections, state.OnClientEvent:Connect(function(state, notice)
	hud:update(state)
	effects:update(state)
	audio:setState(state)
	if typeof(notice) == "string" then hud:notice(notice) end
end))
table.insert(connections, characterState.OnClientEvent:Connect(function(view)
	hud:setCharacters(view)
end))
table.insert(connections, pickup.OnClientEvent:Connect(function(receipt)
	effects:pickup(receipt)
end))
local accumulator = 0
table.insert(connections, RunService.RenderStepped:Connect(function(dt)
	-- Fades run every frame so a crossfade keeps the same wall-clock length.
	audio:tick(dt, hud.soundOn)
	accumulator += dt
	if accumulator >= .1 then
		accumulator = 0
		hud:tick()
	end
end))

-- Request AFTER listeners connect. Periodic server snapshots also recover missed joins.
request:FireServer("Snapshot")
task.spawn(function()
	for _ = 1, 5 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if ok then break end
		task.wait(.5)
	end
end)

script.Destroying:Connect(function()
	for _, connection in connections do connection:Disconnect() end
	effects:destroy()
	audio:destroy()
	hud:destroy()
end)
