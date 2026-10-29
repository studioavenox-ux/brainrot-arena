--!strict
-- All rewards and timings are read by the SERVER. There is no client scoring API.
local Config = {
	Version = "0.1.0",
	WorldVersion = 1,
	Brand = "BRAINROT ARENA",
	ArenaName = "SYNAPSE CIRCUIT",
	StudioFastMode = false, -- The generated QuickTest place changes ONLY this flag.

	Timing = {
		Intermission = 12,
		Round = 180,
		Results = 9,
		EventStart = 60,
		EventDuration = 25,
	},
	FastTiming = {
		Intermission = 4,
		Round = 30,
		Results = 5,
		EventStart = 8,
		EventDuration = 10,
	},
	NormalGravity = 196.2,
	LowGravity = 62,
	WalkSpeed = 22,
	JumpPower = 50,
	ServerStep = 0.1,
	SnapshotInterval = 0.25,
	RescueBelowY = 0,
	SpawnProtection = 0.65,
	PickupRadius = 4.5,
	PickupRespawn = 5,
	MaxHorizontalSpeed = 65,
	MovementSlack = 9,
	ParticipationCoins = 10,
	CoinsPerPoint = 2,
	WinnerCoins = 30,
	HaloCost = 100,

	Kinds = {
		{ Name = "Common", Value = 1, Weight = 78, Color = { 255, 94, 190 } },
		{ Name = "Rare", Value = 5, Weight = 18, Color = { 255, 213, 67 } },
		{ Name = "Prismatic", Value = 10, Weight = 4, Color = { 83, 238, 255 } },
	},
}

return table.freeze(Config)
