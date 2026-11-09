--!strict
-- Roblox adapter. Only this server script can award cells, pay coins, or unlock cosmetics.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("BrainrotShared")
local Config = require(Shared:WaitForChild("Config"))
local CharacterManifest = require(Shared:WaitForChild("Creatures"))
local RoundMachine = require(script.Parent.core.RoundMachine)
local PickupLedger = require(script.Parent.core.PickupLedger)
local MovementGuard = require(script.Parent.core.MovementGuard)
local ArenaRoute = require(script.Parent.core.ArenaRoute)
local EventDirector = require(script.Parent.EventDirector)
local ChaosRules = require(script.Parent.core.ChaosRules)
local Persistence = require(script.Parent.Persistence)
local WorldService = require(script.Parent.WorldService)
local WorldData = require(script.Parent.WorldData)
local ArtService = require(script.Parent.ArtService)

local settings = table.clone(Config)
local fast = RunService:IsStudio() and Config.StudioFastMode
settings.Timing = if fast then Config.FastTiming else Config.Timing
local random = Random.new()
-- Chaos draws are server-side and uniform over the configured pool. Clamped so a
-- rounding edge can never index past the end of the list.
local machine = RoundMachine.new(settings, function(n: number): number
	return math.min(n, math.floor(random:NextNumber() * n) + 1)
end)
-- Species is rolled here, on the server, from the ledger's own slot id and rarity, so
-- the receipt a client animates names the character that player really collected.
local ledger = PickupLedger.new(WorldData.PickupPositions, Config.Kinds, Config.PickupRadius, Config.PickupRespawn, function()
	return random:NextNumber()
end, function(slotId: number, value: number): string
	return CharacterManifest.SpeciesOf(slotId, value)
end)
local movement = MovementGuard.new(Config.MaxHorizontalSpeed, Config.MovementSlack, Config.SpawnProtection)
-- Arena access. Every rail trip goes through this router: it asserts a destination
-- and keeps asserting it until the character is measurably there.
local route = ArenaRoute.new()
local routeStep = 0
-- Appearance only. Idempotent with the lighting rig baked into the place file.
ArtService.apply()
local world = WorldService.new()
-- Animates the baked event geometry by name. Owns gravity/friction *inside* an
-- event window only; the round machine owns when a window opens.
local director = EventDirector.new(Config.NormalGravity)
-- The live Chaos modifiers. Only syncChaos() writes this, so every consumer (jump,
-- respawn, rarity, gravity, friction) agrees on the same snapshot of the event.
local appliedChaos = ""
local chaos: ChaosRules.Modifiers = ChaosRules.modifiers("", Config)
-- Coins, the specimen log, lifetime stats and cosmetics live here. Round score
-- does not: it is created and destroyed by the round.
local profiles = Persistence.new({})
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
type Record = {
	spawnIndex: number, connection: RBXScriptConnection?, requests: { [string]: number },
}
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
		eventKind = state.eventKind, eventWarning = state.eventWarning,
		eventWarningEndsAt = state.eventWarningEndsAt, events = state.events,
		stage = state.stage, stageIndex = state.stageIndex, stageEndsAt = state.stageEndsAt,
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
		segment.Color = Color3.fromRGB(126, 226, 250)
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

local function characterReady(player: Player)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not character or not humanoid or not root or not root:IsA("BasePart") then
		return nil
	end
	if humanoid.Health <= 0 then
		return nil
	end
	return character, humanoid, root
end

-- One rail move. Returns true only if the character was actually relocated.
local function movePlayer(player: Player, arena: boolean, now: number, escalate: boolean): boolean
	local record = records[player.UserId]
	local character, humanoid, root = characterReady(player)
	if not record or not character or not humanoid or not root then
		return false
	end
	local target = world:spawnCFrame(arena, record.spawnIndex)
	-- Fallback path: an unseated or seated humanoid will silently refuse a PivotTo.
	-- Detach it from the seat, stop physics, then pivot; the engine re-seats it.
	if escalate then
		-- An unseated or platform-standing humanoid silently refuses a PivotTo.
		-- Detach it, stop the assembly, then pivot twice: the second call lands after
		-- the engine has reset the root from the first.
		humanoid.Sit = false
		humanoid.PlatformStand = false
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		character:PivotTo(target)
		character:PivotTo(target)
	else
		character:PivotTo(target)
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	humanoid.WalkSpeed = Config.WalkSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = Config.JumpPower * chaos.JumpScale
	movement:teleport(player.UserId, position(target.Position), now)
	route:attempt(player.UserId, if arena then "arena" else "lobby", now)

	-- Verify, do not assume. A PivotTo can be silently ignored (seated humanoid,
	-- platform stand, a physics owner mid-step). If the character did not move, open
	-- the retry window immediately instead of waiting out the backoff.
	local landed = (root.Position - target.Position).Magnitude <= 16
	if not landed then
		local track = route:track(player.UserId)
		track.lastAttempt = now - ArenaRoute.RETRY_DELAY + 0.02
		route.corrections += 1
	end
	return landed
end

-- One routing decision for one player. This is the only place that decides whether
-- a character belongs in the arena, and it retries until the character is there.
local function routePlayer(player: Player, now: number, force: boolean)
	local _, _, root = characterReady(player)
	local trackPosition = if root then position(root.Position) else nil
	if force then
		-- A phase flip should be acted on in this very step. Clearing the backoff is
		-- not a bypass of the verification: the move is still an ordinary attempt,
		-- and only repeated failures escalate to the fallback path.
		local track = route:track(player.UserId)
		track.cooldownUntil = -math.huge
		track.attempts = 0
	end
	local verdict, destination = route:evaluate(
		player.UserId,
		machine.phase,
		machine:isParticipating(player.UserId),
		trackPosition,
		root ~= nil,
		now
	)
	if verdict == "retry" and destination then
		local placed = movePlayer(player, destination == "arena", now, false)
		-- A refused pivot opens the retry window immediately (movePlayer already
		-- reset the backoff), so no extra bookkeeping is needed here.
	elseif verdict == "give-up" and destination then
		-- Escalation: re-seat the character. The router has already counted this as
		-- a fallback, so the log line below is evidence, not decoration.
		local escaped = (function()
			local _, humanoid = characterReady(player)
			return humanoid ~= nil and (humanoid.Sit == true or humanoid.PlatformStand == true)
		end)()
		movePlayer(player, destination == "arena", now, true)
		local fallbacks = (player:GetAttribute("ArenaRouteFallbacks") or 0) + 1
		player:SetAttribute("ArenaRouteFallbacks", fallbacks)
		print(string.format(
			"[Brainrot] route fallback #%d • %s -> %s%s",
			fallbacks, player.Name, destination,
			if escaped then " (detached from seat)" else " (re-seat + pivot)"))
	elseif force and destination then
		-- Character just loaded, or the phase just flipped: assert the destination
		-- now. Still the ordinary attempt, so a failure is visible and escalates.
		movePlayer(player, destination == "arena", now, false)
	end
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
	-- A display id that changes with every generation, so the client can tell "the
	-- same cell respawned" from "a different character took its place" and animate
	-- the swap instead of silently recolouring.
	part:SetAttribute("Species", slot.species)
	part:SetAttribute("DisplayId", slot.species .. ":" .. slot.generation)
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

-- --------------------------------------------------------------------------- #
-- Stealing. The client sends ONE word and no arguments. Everything that decides
-- the outcome — who is nearest, how far away they are, whether this thief is on
-- cooldown, whether the victim was just hit — is resolved here, from server state.
-- --------------------------------------------------------------------------- #
local STEAL_MESSAGES = {
	ok = "Steal",
	["empty"] = "Nothing carried",
	["out-of-range"] = "No rival in reach",
	["cooldown"] = "Steal recharging",
	["protected"] = "Spawn protection",
	["immune"] = "They just got hit",
	["repeat"] = "Same target too soon",
	["self"] = "That is you",
	["inactive-round"] = "Round not live",
	["missing-player"] = "No rival in reach",
	["invalid-player"] = "No rival in reach",
}

local function resolveSteal(thief: Player, now: number): (string, number, Player?)
	local thiefCharacter, thiefHumanoid, thiefRoot = characterReady(thief)
	if not thiefCharacter or not thiefHumanoid or not thiefRoot then
		return "invalid-player", 0, nil
	end
	if not machine:isParticipating(thief.UserId) then
		return "inactive-round", 0, nil
	end
	-- Short range, measured on the server from the same parts the engine moves.
	local bestDistance: number = math.huge
	local bestVictim: Player? = nil
	for _, other in Players:GetPlayers() do
		if other ~= thief then
			local _, otherHumanoid, otherRoot = characterReady(other)
			if otherRoot and otherHumanoid and machine:isParticipating(other.UserId) then
				local distance = (otherRoot.Position - thiefRoot.Position).Magnitude
				if distance < bestDistance then
					bestDistance, bestVictim = distance, other
				end
			end
		end
	end
	if not bestVictim then
		return "out-of-range", 0, nil
	end
	local outcome, value = machine:trySteal(thief.UserId, bestVictim.UserId, bestDistance, now, machine.roundId)
	return outcome, value, bestVictim
end

local function checkInvariants()
	if not RunService:IsStudio() then
		return
	end
	assert(ledger.running == (machine.phase == "Playing"), "Pickup lifecycle diverged")
	-- Gravity is normal unless the *low gravity* Chaos Event is the live one. Other
	-- kinds leave it alone, so the assertion names the only cause.
	local low = machine.eventActive and machine.eventKind == "LowGravity"
	assert(math.abs(Workspace.Gravity - (if low then Config.Chaos.LowGravity else Config.NormalGravity)) < 0.01, "Gravity failed to reset")
	-- Nothing can be negative, and carried values always sum to the round score.
	for _, player in machine.players do
		assert(player.carriedValue >= 0, "Negative carried value")
		assert(player.score >= player.carriedValue, "Score below the carried stack")
	end
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

-- Make the world match the live Chaos Event. Runs every step, so a missed effect can
-- never leave gravity, friction, jump power or rarity stuck after the window closes.
local function syncChaos()
	local kind = if machine.eventActive then machine.eventKind else ""
	if kind == appliedChaos then
		return
	end
	appliedChaos = kind
	chaos = ChaosRules.modifiers(kind, Config)
	director:apply(chaos)
	world:setLowGravity(kind == "LowGravity")
	ledger:setRareScale(chaos.RareScale)
end

local function handleEffects(effects, now: number)
	for _, effect in effects do
		dirty = true
		if effect.kind == "event" then
			-- The world itself is changed by syncChaos(), which reconciles on every step.
			if effect.active then
				print(string.format("[Brainrot] chaos ON • %s", tostring(effect.event)))
			else
				print("[Brainrot] chaos OFF")
			end
		elseif effect.kind == "warning" then
			print(string.format("[Brainrot] event warning • %s in %.0fs", tostring(effect.event),
				math.max(0, (effect.at or now) - now)))
		elseif effect.kind == "stage" then
			print(string.format("[Brainrot] stage • %s (banked all carried cells)", tostring(effect.stage)))
		elseif effect.kind == "phase" then
			if machine.phase == "Results" and machine.lastResults then
				-- Pay the round into each profile once, from the machine's own result.
				local winners = {}
				for _, row in machine.lastResults.winners do
					winners[row.id] = true
				end
				for _, row in machine:rows() do
					local profile = profiles:profile(row.id)
					if profile then
						local paid = (machine.lastResults.rewards[tostring(row.id)] or 0)
						Persistence.applyRound(profile, {
							score = row.score, steals = row.steals, lost = row.lost,
							pickups = row.pickups, coins = paid, won = winners[row.id] == true,
							collection = row.collection,
						})
						-- The machine owns live coins; keep them in step with the profile.
						profiles:save(row.id)
					end
				end
			end
			if machine.phase == "Playing" then
				ledger:beginRound(machine.roundId)
				spawnPickups()
				-- Route every player (including a player whose character is still
				-- loading: routePlayer re-asserts on the next sweep and on
				-- CharacterAdded). Never yields, never blocks the authority loop.
				for _, player in Players:GetPlayers() do
					routePlayer(player, now, true)
				end
			else
				ledger:clear()
				pickupFolder:ClearAllChildren()
				table.clear(pickupParts)
				director:reset()
				if machine.phase == "Intermission" or machine.phase == "Results" or machine.phase == "Waiting" then
					for _, player in Players:GetPlayers() do
						routePlayer(player, now, true)
					end
				end
			end
			print(string.format("[Brainrot] %s • round %d", machine.phase, machine.roundId))
		end
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
		-- Characters spawn in the lobby; the router decides where they belong and
		-- keeps asserting it. This covers respawns mid-round and joins mid-round.
		route:remove(player.UserId)
		local now = Workspace:GetServerTimeNow()
		-- Spawn protection is real: the machine's clock, not a client's.
		machine:spawnProtect(player.UserId, now)
		routePlayer(player, now, true)
		applyHalo(player)
	end)
end

local function playerAdded(player: Player)
	if records[player.UserId] then
		return
	end
	local accepted = machine:addPlayer(player.UserId, player.DisplayName)
	assert(accepted, "Could not register Roblox player")
	-- Seed the session from the saved profile as soon as it is available. The
	-- machine's numbers stay authoritative for the round; the profile is what
	-- survives it.
	profiles:load(player.UserId, function(profile)
		if machine.players[player.UserId] then
			machine:seedProfile(player.UserId, profile.Coins, profile.Halo)
			applyHalo(player)
			syncStats()
			dirty = true
		end
	end)
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
	-- Persist what this session earned before the machine forgets the player.
	local data = machine.players[player.UserId]
	local profile = profiles:profile(player.UserId)
	if data and profile then
		local coins, halo = machine:cosmetics(player.UserId)
		profile.Coins = math.max(profile.Coins, coins)
		profile.Halo = halo
		for species, amount in data.collection do
			profile.Specimens[species] = math.max(profile.Specimens[species] or 0, amount)
		end
		profiles:save(player.UserId)
	end
	records[player.UserId] = nil
	movement:remove(player.UserId)
	route:remove(player.UserId)
	machine:removePlayer(player.UserId)
	dirty = true
end)
for _, player in Players:GetPlayers() do
	playerAdded(player)
end

requestRemote.OnServerEvent:Connect(function(player: Player, action: any, ...: any)
	-- Whitelist small verbs, reject extra arguments, and rate-limit per player/action.
	-- There is intentionally NO score, pickup ID, position, price, or coin amount API.
	if typeof(action) ~= "string" or (action ~= "Snapshot" and action ~= "Halo" and action ~= "Steal") or select("#", ...) ~= 0 then
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
	if action == "Steal" then
		-- Mirrors the server's own 8-second rule; the machine enforces it again.
		if now - (record.requests.StealSent or -math.huge) < Config.Steal.Cooldown then
			stateRemote:FireClient(player, snapshot(), STEAL_MESSAGES["cooldown"])
			return
		end
		record.requests.StealSent = now
		local outcome, value, victim = resolveSteal(player, now)
		print(string.format("[Brainrot] steal %s • %s -> %s (+%d)", outcome, player.Name,
			if victim then victim.Name else "nobody", value))
		-- A steal moves score between two players: refresh leaderstats immediately
		-- so the board never shows the old owner for even one frame.
		if outcome == "ok" then
			syncStats()
		end
		if outcome == "ok" and victim then
			-- The victim sees exactly what they lost, from the server's own answer.
			stateRemote:FireClient(victim, snapshot(),
				string.format("STEAL: %s took %d from you", player.DisplayName, value))
			dirty = true
		end
		stateRemote:FireClient(player, snapshot(), STEAL_MESSAGES[outcome] or "Steal refused")
		return
	end
	if action == "Halo" then
		local ok, message = machine:haloAction(player.UserId)
		if ok then
			-- Coins are spent inside the round, then written to the profile: one
			-- transition, one save. A client never sends the price.
			local coins, halo = machine:cosmetics(player.UserId)
			local profile = profiles:profile(player.UserId)
			if profile then
				profile.Coins = coins
				profile.Halo = halo
				profiles:save(player.UserId)
			end
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
	-- Carry the remainder forward so the authority step keeps its 0.1 s cadence and does not
	-- drift with frame timing. The carry is capped at one step, so a long stall cannot cause a
	-- burst of catch-up steps.
	accumulator = math.min(accumulator - Config.ServerStep, Config.ServerStep)
	local now = Workspace:GetServerTimeNow()
	local effects = machine:step(now)
	handleEffects(effects, now)
	syncChaos()
	if #effects > 0 then
		-- Checked after the world has been reconciled, so the invariant sees the result.
		checkInvariants()
	end

	if machine.phase == "Playing" then
		for _, id in ledger:step(now) do
			updatePickup(id)
		end
		ledger.respawn = if chaos.Respawn then chaos.Respawn
			elseif machine.stage == "Final" then Config.FinalRespawn
			else Config.PickupRespawn
	else
		ledger.respawn = Config.PickupRespawn
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		-- Bouncy World: the jump scale follows the live event. Written only on change.
		if humanoid and humanoid.JumpPower ~= Config.JumpPower * chaos.JumpScale then
			humanoid.JumpPower = Config.JumpPower * chaos.JumpScale
		end
		if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
			continue
		end
		local p = root.Position
		if p.Y < Config.RescueBelowY then
			route:remove(player.UserId)
			routePlayer(player, now, true)
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
					assert(machine:award(receipt.userId, receipt.value, receipt.roundId, receipt.species),
						"Atomic award rejected")
					updatePickup(slot.id)
					pickupRemote:FireAllClients(receipt)
					dirty = true
				end
			end
		end
	end

	-- On-demand fallback: a light round-robin sweep proves everyone's destination
	-- every step, so a failed transition self-heals within a fraction of a second
	-- even if the phase effect was missed entirely.
	if machine.phase == "Playing" or machine.phase == "Results" or machine.phase == "Intermission" then
		routeStep += 1
		local ids: { number } = {}
		local byId: { [number]: Player } = {}
		for _, player in Players:GetPlayers() do
			table.insert(ids, player.UserId)
			byId[player.UserId] = player
		end
		for _, id in ArenaRoute.slice(ids, routeStep) do
			local player = byId[id]
			if player then
				routePlayer(player, now, false)
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
