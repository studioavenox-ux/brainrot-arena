--!strict
-- All rewards and timings are read by the SERVER. There is no client scoring API.
local Config = {
	Version = "0.2.0",
	WorldVersion = 2,
	Brand = "BRAINROT ARENA",
	ArenaName = "SYNAPSE CIRCUIT",
	StudioFastMode = false, -- The generated QuickTest place changes ONLY this flag.

	Timing = {
		Intermission = 12,
		Round = 180,
		Results = 9,
		-- Kept for the first (low gravity) window, so older reads stay correct.
		EventStart = 60,
		EventDuration = 25,
		Warning = 6,
	},
	FastTiming = {
		Intermission = 4,
		Round = 30,
		Results = 5,
		EventStart = 8,
		EventDuration = 10,
		Warning = 3,
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
	SaveInterval = 60,

	-- ------------------------------------------------------------------ #
	-- Round stages. Elapsed seconds from the start of a Playing round.
	-- Each stage boundary banks every player's carried cells: what you have
	-- banked is safe, what you are carrying can be stolen. See RoundMachine.
	-- ------------------------------------------------------------------ #
	Stages = {
		{ Name = "Collect", At = 0, Label = "COLLECT" },
		{ Name = "Compete", At = 45, Label = "COMPETE" },
		{ Name = "Chaos", At = 105, Label = "CHAOS" },
		{ Name = "Final", At = 150, Label = "FINAL RUSH" },
	},
	FastStages = {
		{ Name = "Collect", At = 0, Label = "COLLECT" },
		{ Name = "Compete", At = 8, Label = "COMPETE" },
		{ Name = "Chaos", At = 18, Label = "CHAOS" },
		{ Name = "Final", At = 24, Label = "FINAL RUSH" },
	},

	-- ------------------------------------------------------------------ #
	-- Survival events. One window at a time; `Wildcard` resolves to one of
	-- the four wildcards below, rotated deterministically by round number so
	-- consecutive rounds are different but every client agrees.
	-- ------------------------------------------------------------------ #
	Events = {
		{ Kind = "LowGravity", At = 60, Duration = 25 },
		{ Kind = "Wildcard", At = 108, Duration = 18 },
	},
	FastEvents = {
		{ Kind = "LowGravity", At = 8, Duration = 10 },
		{ Kind = "Wildcard", At = 22, Duration = 6 },
	},
	Wildcards = { "Slippery", "MovingPlatforms", "CollectibleRush", "VanishingPaths" },

	-- ------------------------------------------------------------------ #
	-- Stealing. A short-range tag that moves ONE carried cell from the victim
	-- to the thief. Banked cells are never at risk, and nothing leaves the round.
	-- ------------------------------------------------------------------ #
	Steal = {
		Range = 13,          -- studs, centre-to-centre, checked on the server
		Cooldown = 8,        -- seconds, per thief, exactly as specified
		Protection = 3,      -- spawn / respawn immunity
		Immunity = 4,        -- post-steal immunity for the victim
		RepeatWindow = 12,   -- no re-tagging the same victim inside this window
	},

	-- Sticky floor while the Slippery wildcard runs.
	SlipperyFriction = 0.06,
	-- Respawn seconds while CollectibleRush runs, and during the Final Rush.
	RushRespawn = 1.5,
	FinalRespawn = 2,

	Kinds = {
		{ Name = "Common", Value = 1, Weight = 78, Color = { 255, 94, 190 } },
		{ Name = "Rare", Value = 5, Weight = 18, Color = { 255, 213, 67 } },
		{ Name = "Prismatic", Value = 10, Weight = 4, Color = { 83, 238, 255 } },
	},
}

return table.freeze(Config)
