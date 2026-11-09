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
		-- The single Chaos Event of a round: one window, exactly ChaosDuration long,
		-- starting inside the Chaos stage (105 s - 150 s). See Chaos below.
		ChaosStart = 105,
		ChaosDuration = 35,
		Warning = 6,
	},
	FastTiming = {
		Intermission = 4,
		-- Studio QuickTest. The round is longer than the 35 s event so the event is
		-- exercised exactly as in production, and it still fits with time to spare.
		Round = 50,
		Results = 5,
		ChaosStart = 8,
		ChaosDuration = 35,
		Warning = 3,
	},
	NormalGravity = 196.2,
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
	-- Chaos Event. Exactly ONE per round, drawn uniformly by the server from
	-- `Kinds` when the round starts. The window never overlaps another event.
	-- Per-kind effects are defined in src/server/core/ChaosRules.luau.
	-- ------------------------------------------------------------------ #
	Chaos = {
		Kinds = { "LowGravity", "BouncyWorld", "SlipperyChaos", "BrainCellRush" },
		LowGravity = 62,         -- studs/s^2 (normal is 196.2)
		BouncyJumpScale = 1.8,   -- jump power multiplier while Bouncy World runs
		RushRarityScale = 3,     -- weight multiplier for Rare and Prismatic cells
	},

	-- ------------------------------------------------------------------ #
	-- Audio. Every sound ID is configured HERE. An empty string means "no sound":
	-- nothing is invented, and no uploaded or third-party asset is required to run.
	-- To enable a slot, paste an rbxassetid URL (the scheme, a colon, two slashes, then
	-- the number) for an audio asset you own or are licensed to use.
	-- docs/AUDIO.md lists every slot and its behaviour.
	-- ------------------------------------------------------------------ #
	Audio = {
		CrossfadeSeconds = 1.5,  -- time to fade one music track out and the next in
		MusicVolume = .35,       -- loudest level for a music track
		CueVolume = .6,          -- level for one-shot cues
		Tracks = {
			Lobby = "",          -- Waiting / Intermission / Results
			Arena = "",          -- Playing, no Chaos Event
			Chaos = "",          -- Playing, a Chaos Event is active
		},
		-- One-shot cues. Ability cues are added here, one key per ability, when the
		-- abilities exist (for example "Ability.Dash"). Playing an unlisted cue is an
		-- error, so a typo cannot fail silently.
		Cues = {
			RoundStart = "",
			RoundEnd = "",
			ChaosStart = "",
			ChaosEnd = "",
			Steal = "",
			Ability = "",
		},
	},

	-- ------------------------------------------------------------------ #
	-- Characters. Six playable characters, all free, one active at a time. Every
	-- character has one ability, and each ability has its own cooldown. Cooldowns are
	-- per player and per character, persist across switches within a round, and reset
	-- at the next round. Abilities never award, steal or move Brain Cells.
	-- Roster keys are the cell species keys in Creatures.luau.
	-- ------------------------------------------------------------------ #
	Characters = {
		-- Slot 1..6 is the order the client shows and the order the server accepts.
		Order = { "brain", "frog", "fish", "goose", "toast", "sock" },
		SwitchesNormal = 3,   -- switches usable at any time during Playing
		SwitchesBonus = 1,    -- one extra switch, usable only during the Chaos Event
		Roster = {
			brain = { Ability = "MindTrick", Title = "MIND TRICK", Cooldown = 20, Duration = 6, Offset = 6 },
			frog = { Ability = "BellyBounce", Title = "BELLY BOUNCE", Cooldown = 15, Radius = 10, Push = 55, Lift = 18 },
			fish = { Ability = "BubbleDash", Title = "BUBBLE DASH", Cooldown = 12, Speed = 70, Duration = .35 },
			goose = { Ability = "HonkWave", Title = "HONK WAVE", Cooldown = 18, Radius = 14, SlowFactor = .5, Duration = 2.5 },
			toast = { Ability = "ToastLaunch", Title = "TOAST LAUNCH", Cooldown = 16, Radius = 8, Lift = 60 },
			sock = { Ability = "SockSnare", Title = "SOCK SNARE", Cooldown = 14, Radius = 12, SlowFactor = .4, Duration = 4 },
		},
		-- Ability-driven movement gets a temporary speed allowance from MovementGuard.
		-- Margin is added on top of the expected speed, so ordinary rounding never trips it.
		MovementMargin = 8,
		GrantSeconds = .8,
	},

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

	-- Sticky floor while Slippery Chaos runs.
	SlipperyFriction = 0.06,
	-- Respawn seconds during Brain Cell Rush, and during the Final Rush.
	RushRespawn = 1.5,
	FinalRespawn = 2,

	Kinds = {
		{ Name = "Common", Value = 1, Weight = 78, Color = { 255, 94, 190 } },
		{ Name = "Rare", Value = 5, Weight = 18, Color = { 255, 213, 67 } },
		{ Name = "Prismatic", Value = 10, Weight = 4, Color = { 83, 238, 255 } },
	},
}

return table.freeze(Config)
