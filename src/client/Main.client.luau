--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Config = require(ReplicatedStorage:WaitForChild("BrainrotShared"):WaitForChild("Config"))
local Hud = require(script.Parent.Hud)
local Effects = require(script.Parent.Effects)
local remotes = ReplicatedStorage:WaitForChild("BrainrotRemotes")
local stateRemote = remotes:WaitForChild("State") :: RemoteEvent
local pickupRemote = remotes:WaitForChild("Pickup") :: RemoteEvent
local requestRemote = remotes:WaitForChild("Request") :: RemoteEvent

local hud = Hud.new(Config, function(action: string)
	requestRemote:FireServer(action)
end)
local effects = Effects.new(hud, Config)
local connections: { RBXScriptConnection } = {}

table.insert(connections, stateRemote.OnClientEvent:Connect(function(state, notice)
	hud:update(state)
	effects:update(state)
	if typeof(notice) == "string" then hud:notice(notice) end
end))
table.insert(connections, pickupRemote.OnClientEvent:Connect(function(receipt)
	effects:pickup(receipt)
end))
local accumulator = 0
table.insert(connections, RunService.RenderStepped:Connect(function(dt)
	accumulator += dt
	if accumulator >= .1 then
		accumulator = 0
		hud:tick()
	end
end))

-- Request AFTER listeners connect. Periodic server snapshots also recover missed joins.
requestRemote:FireServer("Snapshot")
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
	hud:destroy()
end)
