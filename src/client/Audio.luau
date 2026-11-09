--!strict
-- Client-side music and cue playback. It follows the replicated state, and every
-- decision (which track, when a cue fires) comes from AudioRules. Nothing here is
-- authoritative: audio never changes gameplay.
--
-- Behaviour:
--   * One looped Sound per CONFIGURED music track. An empty ID creates no Sound.
--   * Track changes crossfade over Config.Audio.CrossfadeSeconds. Volume moves a
--     fixed step per frame, so a fade always takes the same wall time.
--   * Stingers fire on the server-driven edges: round start/end, Chaos start/end.
--   * The Settings "Sound" toggle (hud.soundOn) mutes music and cues together.
--   * destroy() removes every Sound this module created.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local AudioRules = require(ReplicatedStorage:WaitForChild("BrainrotShared"):WaitForChild("AudioRules"))

local Audio = {}
Audio.__index = Audio

export type Track = { sound: Sound?, wanted: boolean }

export type Controller = typeof(setmetatable({} :: {
	config: any,
	folder: Folder,
	tracks: { [string]: Track },
	wanted: string,
	enabled: boolean,
	lastPhase: string?,
	lastEvent: string,
	cueCount: number,
}, Audio))

function Audio.new(config: any): Controller
	local folder = Instance.new("Folder")
	folder.Name = "BrainrotAudio"
	folder.Parent = SoundService
	local tracks: { [string]: Track } = {}
	for name, id in config.Audio.Tracks do
		assert(AudioRules.validId(id), "Invalid music ID for track " .. name)
		local track: Track = { sound = nil, wanted = false }
		if id ~= "" then
			local sound = Instance.new("Sound")
			sound.Name = "Music_" .. name
			sound.Looped = true
			sound.Volume = 0
			sound.SoundId = id
			sound.Parent = folder
			track.sound = sound
		end
		tracks[name] = track
	end
	return setmetatable({
		config = config, folder = folder, tracks = tracks, wanted = "Lobby",
		enabled = true, lastPhase = nil, lastEvent = "", cueCount = 0,
	}, Audio) :: any
end

-- Plays a one-shot cue. Returns true only when a sound actually started.
function Audio.cue(self: Controller, name: string): boolean
	local id = AudioRules.cueId(self.config.Audio.Cues, name)
	if id == nil or not self.enabled then
		return false
	end
	local sound = Instance.new("Sound")
	self.cueCount += 1
	sound.Name = "Cue_" .. name .. "_" .. self.cueCount
	sound.SoundId = id
	sound.Volume = self.config.Audio.CueVolume
	sound.Parent = self.folder
	sound:Play()
	Debris:AddItem(sound, 8)
	return true
end

-- Reacts to a replicated state snapshot. Only edges trigger stingers, so joining
-- mid-event does not replay anything from the past.
function Audio.setState(self: Controller, state: any)
	self.wanted = AudioRules.trackFor(state)
	local phase = state.phase
	local event = if state.eventActive then tostring(state.eventKind or "") else ""
	-- The first snapshot only records where things stand. A player who joins mid-round
	-- or mid-event hears the right music but not a stinger for something already past.
	if self.lastPhase == nil then
		self.lastPhase = phase
		self.lastEvent = event
		return
	end
	if phase ~= self.lastPhase then
		if phase == "Playing" then
			Audio.cue(self, "RoundStart")
		elseif self.lastPhase == "Playing" then
			Audio.cue(self, "RoundEnd")
		end
		self.lastPhase = phase
	end
	if event ~= self.lastEvent then
		if event ~= "" then
			Audio.cue(self, "ChaosStart")
		else
			Audio.cue(self, "ChaosEnd")
		end
		self.lastEvent = event
	end
end

-- Advances every crossfade by `dt` seconds. `enabled` is the Sound setting.
function Audio.tick(self: Controller, dt: number, enabled: boolean)
	self.enabled = enabled
	local fade = self.config.Audio.CrossfadeSeconds
	local full = self.config.Audio.MusicVolume
	for name, track in self.tracks do
		local sound = track.sound
		if sound then
			local target = if enabled and self.wanted == name then full else 0
			if target > 0 and not track.wanted then
				track.wanted = true
				sound:Play()
			elseif target == 0 then
				track.wanted = false
			end
			sound.Volume = AudioRules.stepVolume(sound.Volume, target, dt, full, fade)
		end
	end
end

function Audio.destroy(self: Controller)
	self.folder:Destroy()
	table.clear(self.tracks)
end

return Audio
