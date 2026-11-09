--!strict
-- Roblox adapter for character abilities. Every decision comes from the pure modules
-- (AbilityRules for geometry and statuses, CharacterRules for cooldowns and switching).
-- This module only turns those decisions into parts, velocities and walk speeds.
--
-- Hard rules, all enforced here or by the caller:
--   * Nothing in this module touches Brain Cells, scores, coins or the round machine.
--   * The caster is never a target of their own ability.
--   * Ability-driven movement is granted to MovementGuard for its exact duration only.
--   * Every effect is removed on round end (reset) and when a player leaves (forget).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Config = require(ReplicatedStorage:WaitForChild("BrainrotShared"):WaitForChild("Config"))
local AbilityRules = require(script.Parent.core.AbilityRules)
local MovementGuard = require(script.Parent.core.MovementGuard)

local AbilityService = {}
AbilityService.__index = AbilityService

export type Candidate = { player: Player, root: BasePart, humanoid: Humanoid }
export type Service = typeof(setmetatable({} :: {
	movement: MovementGuard.Guard,
	statuses: AbilityRules.Statuses,
	decoys: { [number]: { model: Model, untilAt: number } },
	dashes: { [number]: { x: number, z: number, untilAt: number } },
}, AbilityService))

function AbilityService.new(movement: MovementGuard.Guard): Service
	return setmetatable({
		movement = movement,
		statuses = {},
		decoys = {},
		dashes = {},
	}, AbilityService) :: any
end

local function planar(position: Vector3): AbilityRules.Vec
	return { x = position.X, y = position.Y, z = position.Z }
end

local function toVector3(v: AbilityRules.Vec): Vector3
	return Vector3.new(v.x, v.y, v.z)
end

local function removeDecoy(self: Service, userId: number)
	local decoy = self.decoys[userId]
	if decoy then
		decoy.model:Destroy()
		self.decoys[userId] = nil
	end
end

-- A visual decoy: anchored, non-colliding copies of the caster's visible parts, shown a
-- few studs to the side. It is not a character, has no Humanoid, and is never targeted.
local function spawnDecoy(self: Service, caster: Player, character: Model, root: BasePart, entry: any, now: number)
	removeDecoy(self, caster.UserId)
	local model = Instance.new("Model")
	model.Name = "MindTrick_" .. tostring(caster.UserId)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			local copy = part:Clone()
			copy.Anchored = true
			copy.CanCollide = false
			copy.CanTouch = false
			copy.CanQuery = false
			copy.Transparency = math.max(copy.Transparency, .35)
			copy.Parent = model
		end
	end
	model.Parent = Workspace
	model:PivotTo(root.CFrame * CFrame.new(entry.Offset, 0, 0))
	self.decoys[caster.UserId] = { model = model, untilAt = now + entry.Duration }
end

-- Performs one ability for `caster`. `candidates` lists every participating player with a
-- live root (the caster may be among them; they are always excluded). Returns the players
-- who were actually affected, nearest first, so the caller can notify them.
function AbilityService.perform(self: Service, caster: Player, character: Model, root: BasePart,
	entry: any, candidates: { Candidate }, now: number): { Player }
	local casterPos = planar(root.Position)
	local look = planar(root.CFrame.LookVector)
	local lookFallback = { x = look.x, y = 0, z = look.z }
	local pool: { AbilityRules.Candidate } = {}
	local byId: { [number]: Candidate } = {}
	for _, candidate in candidates do
		table.insert(pool, { userId = candidate.player.UserId, position = planar(candidate.root.Position) })
		byId[candidate.player.UserId] = candidate
	end

	local affected: { Player } = {}
	local ability = entry.Ability
	if ability == "MindTrick" then
		spawnDecoy(self, caster, character, root, entry, now)
		return affected
	end

	if ability == "BubbleDash" then
		local velocity = AbilityRules.dashVelocity(look, entry.Speed)
		self.dashes[caster.UserId] = { x = velocity.x, z = velocity.z, untilAt = now + entry.Duration }
		self.movement:grant(caster.UserId, entry.Speed + Config.Characters.MovementMargin,
			now + entry.Duration + Config.Characters.GrantSeconds, now)
		table.insert(affected, caster)
		return affected
	end

	local hits = AbilityRules.targetsIn(casterPos, pool, entry.Radius, caster.UserId)
	for _, hit in hits do
		local victim = byId[hit.userId]
		if victim then
			local victimPos = planar(victim.root.Position)
			if ability == "BellyBounce" then
				local direction = AbilityRules.horizontalDirection(casterPos, victimPos, lookFallback)
				local velocity = AbilityRules.knockbackVelocity(direction, entry.Push, entry.Lift)
				victim.root.AssemblyLinearVelocity = toVector3(velocity)
				self.movement:grant(victim.player.UserId, entry.Push + Config.Characters.MovementMargin,
					now + Config.Characters.GrantSeconds, now)
			elseif ability == "ToastLaunch" then
				victim.root.AssemblyLinearVelocity = toVector3(AbilityRules.launchVelocity(entry.Lift))
			elseif ability == "HonkWave" or ability == "SockSnare" then
				AbilityRules.applySlow(self.statuses, victim.player.UserId, entry.SlowFactor, now + entry.Duration)
			end
			table.insert(affected, victim.player)
		end
	end
	return affected
end

-- Walk speed for a player right now: the base speed, scaled by any active slow.
function AbilityService.walkSpeed(self: Service, userId: number, now: number): number
	return Config.WalkSpeed * AbilityRules.speedFactor(self.statuses, userId, now)
end

-- Runs every frame: keeps dash velocity applied for its duration and keeps each walk speed
-- equal to the live value. Writes happen only on change.
function AbilityService.drive(self: Service, now: number, players: { Candidate })
	for _, candidate in players do
		local humanoid = candidate.humanoid
		local wanted = AbilityService.walkSpeed(self, candidate.player.UserId, now)
		if humanoid.WalkSpeed ~= wanted then
			humanoid.WalkSpeed = wanted
		end
		local dash = self.dashes[candidate.player.UserId]
		if dash and now < dash.untilAt then
			local vy = candidate.root.AssemblyLinearVelocity.Y
			candidate.root.AssemblyLinearVelocity = Vector3.new(dash.x, vy, dash.z)
		end
	end
end

-- Ends expired effects. Called from the authority step.
function AbilityService.prune(self: Service, now: number)
	AbilityRules.prune(self.statuses, now)
	for userId, decoy in self.decoys do
		if now >= decoy.untilAt then
			removeDecoy(self, userId)
		end
	end
	for userId, dash in self.dashes do
		if now >= dash.untilAt then
			self.dashes[userId] = nil
		end
	end
end

-- Removes every effect at once. Called at the end of each round.
function AbilityService.reset(self: Service)
	for userId in self.decoys do
		removeDecoy(self, userId)
	end
	table.clear(self.statuses)
	table.clear(self.dashes)
end

-- Removes one player's effects. Called when they leave.
function AbilityService.forget(self: Service, userId: number)
	removeDecoy(self, userId)
	self.statuses[userId] = nil
	self.dashes[userId] = nil
end

function AbilityService.decoyCount(self: Service): number
	local count = 0
	for _ in self.decoys do
		count += 1
	end
	return count
end

return AbilityService
