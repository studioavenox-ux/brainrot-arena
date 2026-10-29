--!nonstrict
-- Original responsive UI. No score, currency, or reward decisions are made here.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Hud = {}
Hud.__index = Hud

local C = {
	Ink = Color3.fromRGB(18, 22, 46), Panel = Color3.fromRGB(27, 32, 64),
	Line = Color3.fromRGB(73, 82, 122), Muted = Color3.fromRGB(167, 181, 210),
	White = Color3.fromRGB(244, 249, 255), Pink = Color3.fromRGB(255, 102, 192),
	Cyan = Color3.fromRGB(83, 238, 255), Gold = Color3.fromRGB(255, 216, 83),
	Purple = Color3.fromRGB(172, 124, 255),
}
local function make(className, properties, parent)
	local instance = Instance.new(className)
	for key, value in properties do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end
local function corner(parent, radius)
	make("UICorner", { CornerRadius = UDim.new(0, radius or 16) }, parent)
end
local function stroke(parent, color, transparency)
	return make("UIStroke", { Color = color or C.Line, Thickness = 1, Transparency = transparency or 0.2 }, parent)
end
local function panel(parent, name, size, pos, anchor)
	local f = make("Frame", {
		Name = name, Size = size, Position = pos, AnchorPoint = anchor or Vector2.zero,
		BackgroundColor3 = C.Ink, BackgroundTransparency = 0.07, BorderSizePixel = 0,
	}, parent)
	corner(f, 18)
	stroke(f)
	return f
end
local function text(parent, name, content, size, pos, color, font, textSize)
	return make("TextLabel", {
		Name = name, Text = content, Size = size, Position = pos,
		BackgroundTransparency = 1, TextColor3 = color or C.White,
		Font = font or Enum.Font.GothamBold, TextSize = textSize or 16,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
		RichText = false, BorderSizePixel = 0,
	}, parent)
end
local function centerLabel(parent, name, content, size, pos, color, font, textSize)
	local label = text(parent, name, content, size, pos, color, font, textSize)
	label.TextXAlignment = Enum.TextXAlignment.Center
	return label
end
local function button(parent, name, content, size, pos, color)
	local b = make("TextButton", {
		Name = name, Text = content, Size = size, Position = pos,
		BackgroundColor3 = color or C.Panel, BorderSizePixel = 0,
		Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.White,
		AutoButtonColor = true,
	}, parent)
	corner(b, 12)
	stroke(b)
	return b
end
local function brainIcon(parent, position, scale)
	local frame = make("Frame", { Name = "BrainIcon", Size = UDim2.fromOffset(48*scale, 44*scale), Position = position, BackgroundTransparency = 1 }, parent)
	for side = 0, 1 do
		for row = 0, 2 do
			local lobe = make("Frame", {
				Size = UDim2.fromOffset(24*scale, 22*scale),
				Position = UDim2.fromOffset((side*18+2)*scale, (row*10+1)*scale),
				BackgroundColor3 = if row == 1 then Color3.fromRGB(255, 142, 211) else C.Pink,
				BorderSizePixel = 0,
			}, frame)
			corner(lobe, 20)
		end
	end
	return frame
end
local function timeString(remaining)
	local seconds = math.max(0, math.ceil(remaining))
	return string.format("%02d:%02d", math.floor(seconds/60), seconds%60)
end

function Hud.new(config, request)
	local self = setmetatable({}, Hud)
	self.config, self.request = config, request
	self.soundOn, self.reducedMotion = true, false
	self.state, self.rows, self.connections = nil, {}, {}
	self.noticeToken, self.lastPhase, self.lastEvent = 0, "", false
	self.userId = Players.LocalPlayer.UserId
	self.screen = make("ScreenGui", {
		Name = "BrainrotHUD", ResetOnSpawn = false, IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 10,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	}, Players.LocalPlayer:WaitForChild("PlayerGui"))
	self.root = make("Frame", { Name = "SafeArea", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, self.screen)

	self.brand = make("Frame", { Name = "Brand", Size = UDim2.fromOffset(220, 88), Position = UDim2.fromOffset(22, 16), BackgroundTransparency = 1 }, self.root)
	text(self.brand, "Wordmark", "BRAINROT", UDim2.fromOffset(220, 32), UDim2.fromOffset(0, 0), C.Gold, Enum.Font.GothamBlack, 28)
	text(self.brand, "Arena", "A R E N A", UDim2.fromOffset(220, 27), UDim2.fromOffset(1, 30), C.Pink, Enum.Font.GothamBlack, 23)
	text(self.brand, "Tagline", "A VERY UNREASONABLE SPORT.", UDim2.fromOffset(220, 18), UDim2.fromOffset(2, 60), C.Muted, Enum.Font.GothamMedium, 10)

	self.timerPanel = panel(self.root, "RoundClock", UDim2.fromOffset(288, 98), UDim2.new(.5, 0, 0, 12), Vector2.new(.5, 0))
	self.phaseLabel = centerLabel(self.timerPanel, "Phase", "SYNCING YOUR BRAIN…", UDim2.new(1, -16, 0, 22), UDim2.fromOffset(8, 9), C.Cyan, nil, 12)
	self.timeLabel = centerLabel(self.timerPanel, "Countdown", "--:--", UDim2.new(1, 0, 0, 48), UDim2.fromOffset(0, 31), C.White, Enum.Font.GothamBlack, 40)
	centerLabel(self.timerPanel, "MapName", "S Y N A P S E   C I R C U I T", UDim2.new(1, -10, 0, 14), UDim2.fromOffset(5, 80), C.Muted, Enum.Font.GothamMedium, 9)

	self.eventPanel = panel(self.root, "Chaos", UDim2.fromOffset(350, 46), UDim2.new(.5, 0, 0, 120), Vector2.new(.5, 0))
	self.eventPanel.BackgroundColor3 = Color3.fromRGB(55, 37, 90)
	self.eventLabel = centerLabel(self.eventPanel, "Event", "GRAB THE GLOW. TOP THE BOARD.", UDim2.new(1, -16, 1, 0), UDim2.fromOffset(8, 0), C.Muted, nil, 12)

	self.scorePanel = panel(self.root, "YourCells", UDim2.fromOffset(252, 78), UDim2.new(.5, 0, 1, -22), Vector2.new(.5, 1))
	self.scoreIcon = brainIcon(self.scorePanel, UDim2.fromOffset(18, 17), 1)
	self.scoreScale = make("UIScale", { Scale = 1 }, self.scoreIcon)
	self.scoreLabel = text(self.scorePanel, "Score", "0", UDim2.fromOffset(150, 42), UDim2.fromOffset(88, 4), C.White, Enum.Font.GothamBlack, 36)
	text(self.scorePanel, "Caption", "YOUR BRAIN CELLS", UDim2.fromOffset(155, 22), UDim2.fromOffset(89, 46), C.Pink, nil, 11)
	self.legend = make("Frame", { Name = "RarityKey", Size = UDim2.fromOffset(360, 24), Position = UDim2.new(.5, 0, 1, -112), AnchorPoint = Vector2.new(.5, 1), BackgroundTransparency = 1 }, self.root)
	for index, entry in { {"PINK +1", C.Pink}, {"GOLD +5", C.Gold}, {"PRISM +10", C.Cyan} } do
		centerLabel(self.legend, "Rarity" .. index, entry[1], UDim2.fromOffset(120, 24), UDim2.fromOffset((index-1)*120, 0), entry[2], nil, 12)
	end

	self.coinsPanel = panel(self.root, "Coins", UDim2.fromOffset(238, 78), UDim2.new(1, -20, 0, 16), Vector2.new(1, 0))
	text(self.coinsPanel, "Caption", "SESSION COINS", UDim2.new(1, -30, 0, 20), UDim2.fromOffset(16, 8), C.Gold, nil, 10)
	self.coinsLabel = text(self.coinsPanel, "Amount", "0", UDim2.new(1, -30, 0, 38), UDim2.fromOffset(16, 28), C.White, Enum.Font.GothamBlack, 30)

	self.ranksButton = button(self.root, "Ranks", "RANKS  /  TAB", UDim2.fromOffset(128, 36), UDim2.new(1, -148, 0, 104))
	self.board = panel(self.root, "Leaderboard", UDim2.fromOffset(238, 310), UDim2.new(1, -20, 0, 150), Vector2.new(1, 0))
	text(self.board, "Heading", "THIS ROUND", UDim2.new(1, -30, 0, 27), UDim2.fromOffset(15, 7), C.White, nil, 13)
	self.boardHint = text(self.board, "Subheading", "MOST CELLS WINS", UDim2.new(1, -30, 0, 17), UDim2.fromOffset(15, 32), C.Muted, Enum.Font.GothamMedium, 9)
	self.roster = make("ScrollingFrame", {
		Name = "Players", Position = UDim2.fromOffset(10, 57), Size = UDim2.new(1, -20, 1, -68),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.Purple, CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, self.board)
	make("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, self.roster)

	self.helpButton = button(self.root, "Help", "HOW TO PLAY  /  H", UDim2.fromOffset(146, 44), UDim2.new(0, 22, 1, -68))
	self.rewardsButton = button(self.root, "Rewards", "REWARDS", UDim2.fromOffset(112, 44), UDim2.new(0, 178, 1, -68))
	self.rewardsButton.TextColor3 = C.Gold
	self.soundButton = button(self.root, "Sound", "SFX ON", UDim2.fromOffset(84, 36), UDim2.new(0, 22, 1, -112))
	self.noticePanel = panel(self.root, "Notice", UDim2.fromOffset(420, 48), UDim2.new(.5, 0, 0, 180), Vector2.new(.5, 0))
	self.noticePanel.Visible = false
	self.noticeLabel = centerLabel(self.noticePanel, "Message", "", UDim2.new(1, -24, 1, 0), UDim2.fromOffset(12, 0), C.White, nil, 13)
	self.noticeLabel.TextWrapped = true

	-- Results are non-modal: players can still move around the lobby.
	self.resultsPanel = panel(self.root, "Results", UDim2.fromOffset(468, 264), UDim2.fromScale(.5, .49), Vector2.new(.5, .5))
	self.resultsPanel.Visible = false
	self.resultsPanel.ZIndex = 5
	centerLabel(self.resultsPanel, "Eyebrow", "ROUND COMPLETE", UDim2.new(1, -36, 0, 24), UDim2.fromOffset(18, 18), C.Cyan, nil, 12)
	self.resultTitle = centerLabel(self.resultsPanel, "Title", "BIG BRAIN ENERGY", UDim2.new(1, -32, 0, 46), UDim2.fromOffset(16, 51), C.Gold, Enum.Font.GothamBlack, 27)
	self.resultName = centerLabel(self.resultsPanel, "Winner", "", UDim2.new(1, -40, 0, 54), UDim2.fromOffset(20, 99), C.White, nil, 22)
	self.resultName.TextWrapped = true
	self.resultName.TextScaled = true
	make("UITextSizeConstraint", { MinTextSize = 12, MaxTextSize = 22 }, self.resultName)
	self.resultTitle.TextScaled = true
	make("UITextSizeConstraint", { MinTextSize = 12, MaxTextSize = 27 }, self.resultTitle)
	self.resultReward = centerLabel(self.resultsPanel, "Reward", "", UDim2.new(1, -40, 0, 34), UDim2.fromOffset(20, 166), C.Pink, nil, 18)
	self.resultNext = centerLabel(self.resultsPanel, "Next", "Next round soon. Keep your neurons warm.", UDim2.new(1, -28, 0, 32), UDim2.fromOffset(14, 213), C.Muted, Enum.Font.GothamMedium, 11)

	self.modal = make("Frame", { Name = "ModalLayer", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Ink, BackgroundTransparency = .24, Visible = false, ZIndex = 20, Active = true }, self.root)
	self.modalPanel = panel(self.modal, "Card", UDim2.fromOffset(468, 374), UDim2.fromScale(.5, .5), Vector2.new(.5, .5))
	self.modalPanel.ZIndex = 21
	self.modalTitle = text(self.modalPanel, "Title", "A QUICK BRAIN BRIEF", UDim2.new(1, -100, 0, 40), UDim2.fromOffset(24, 18), C.Gold, Enum.Font.GothamBlack, 22)
	self.modalBody = text(self.modalPanel, "Body", "", UDim2.new(1, -48, 1, -180), UDim2.fromOffset(24, 70), C.White, Enum.Font.GothamMedium, 16)
	self.modalBody.TextWrapped = true
	self.modalBody.TextYAlignment = Enum.TextYAlignment.Top
	self.modalBody.TextScaled = true
	make("UITextSizeConstraint", { MinTextSize = 11, MaxTextSize = 16 }, self.modalBody)
	self.modalAction = button(self.modalPanel, "Action", "LET'S GO", UDim2.new(1, -48, 0, 46), UDim2.new(0, 24, 1, -102), Color3.fromRGB(104, 62, 185))
	self.motionButton = button(self.modalPanel, "Motion", "REDUCED MOTION: OFF", UDim2.new(.5, -30, 0, 44), UDim2.new(0, 24, 1, -52))
	self.motionButton.TextSize = 10
	self.modalSoundButton = button(self.modalPanel, "ModalSound", "SFX ON", UDim2.new(.5, -30, 0, 44), UDim2.new(.5, 6, 1, -52))
	self.modalSoundButton.TextSize = 10
	self.closeButton = button(self.modalPanel, "Close", "X", UDim2.fromOffset(44, 44), UDim2.new(1, -64, 0, 16))
	self.closeButton.TextSize = 10
	-- Descendants share their panel's stacking context; the modal is above the whole HUD.
	for _, descendant in self.modal:GetDescendants() do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = 21
		end
	end

	self.ranksButton.Activated:Connect(function()
		self.board.Visible = not self.board.Visible
		self.ranksTouched = true
	end)
	self.helpButton.Activated:Connect(function() self:showModal("Help") end)
	self.rewardsButton.Activated:Connect(function() self:showModal("Rewards") end)
	self.closeButton.Activated:Connect(function() self.modal.Visible = false end)
	local function toggleSound()
		self.soundOn = not self.soundOn
		self.soundButton.Text = if self.soundOn then "SFX ON" else "SFX OFF"
		self.modalSoundButton.Text = self.soundButton.Text
	end
	self.soundButton.Activated:Connect(toggleSound)
	self.modalSoundButton.Activated:Connect(toggleSound)
	self.motionButton.Activated:Connect(function()
		self.reducedMotion = not self.reducedMotion
		self.motionButton.Text = "REDUCED MOTION: " .. (if self.reducedMotion then "ON" else "OFF")
	end)
	self.modalAction.Activated:Connect(function()
		if self.modalKind == "Rewards" then
			self.request("Halo")
		else
			self.modal.Visible = false
		end
	end)
	table.insert(self.connections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then return end
		if input.KeyCode == Enum.KeyCode.Tab then
			self.board.Visible = not self.board.Visible
			self.ranksTouched = true
		elseif input.KeyCode == Enum.KeyCode.H then
			if self.modal.Visible then self.modal.Visible = false else self:showModal("Help") end
		elseif input.KeyCode == Enum.KeyCode.Escape and self.modal.Visible then
			self.modal.Visible = false
		end
	end))
	table.insert(self.connections, self.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() self:resize() end))
	self:resize()
	return self
end

function Hud:resize()
	local width, height = self.root.AbsoluteSize.X, self.root.AbsoluteSize.Y
	if width < 1 or height < 1 then return end
	local compact = width < 760
	local short = height < 500
	local portraitTouch = compact and not short
	self.scorePanel.Size = UDim2.fromOffset(if portraitTouch then 208 else 252, if portraitTouch then 68 else 78)
	self.scorePanel.Position = UDim2.new(.5, 0, 1, if portraitTouch then -116 else -22)
	self.scoreLabel.Size = UDim2.new(1, -88, 0, if portraitTouch then 36 else 42)
	self.scoreLabel.TextSize = if portraitTouch then 30 else 36
	self.scorePanel.Caption.Position = UDim2.fromOffset(89, if portraitTouch then 40 else 46)
	self.scorePanel.Caption.Size = UDim2.new(1, -94, 0, 20)
	self.scorePanel.Caption.TextSize = if portraitTouch then 9 else 11
	self.compact = compact
	self.brand.Visible = not compact and not short
	self.timerPanel.Size = UDim2.fromOffset(if compact then math.clamp(width-168, 160, 208) else 288, if short then 82 else 98)
	self.timeLabel.TextSize = if short then 32 else 40
	self.timeLabel.Size = UDim2.new(1, 0, 0, if short then 35 else 48)
	self.timerPanel.MapName.Visible = not short
	self.phaseLabel.TextSize = if compact then 10 else 12
	self.eventPanel.Size = UDim2.fromOffset(math.min(width-32, if compact then 300 else 350), 38)
	self.eventPanel.Position = UDim2.new(.5, 0, 0, if short then 101 else 120)
	self.eventLabel.TextSize = if compact then 10 else 12
	self.ranksButton.Size = UDim2.fromOffset(if compact or short then 66 else 128, 44)
	self.ranksButton.Position = if compact or short then UDim2.new(1, -80, 0, 18) else UDim2.new(1, -148, 0, 104)
	self.ranksButton.Text = if compact or short then "RANKS" else "RANKS / TAB"
	self.board.Size = UDim2.fromOffset(if compact then 220 else 238, math.min(310, height-110))
	self.board.Position = UDim2.new(1, -14, 0, if compact or short then 76 else 150)
	if not self.ranksTouched then self.board.Visible = not compact and not short end
	self.coinsPanel.Size = UDim2.fromOffset(if compact or short then 170 else 238, if compact or short then 36 else 78)
	self.coinsPanel.AnchorPoint = if compact or short then Vector2.new(.5, 1) else Vector2.new(1, 0)
	self.coinsPanel.Position = if compact or short then UDim2.new(.5, 0, 1, if portraitTouch then -190 else -106) else UDim2.new(1, -20, 0, 16)
	self.coinsPanel.Caption.Visible = not compact and not short
	self.coinsLabel.Position = if compact or short then UDim2.fromOffset(12, 0) else UDim2.fromOffset(16, 28)
	self.coinsLabel.Size = if compact or short then UDim2.new(1, -24, 1, 0) else UDim2.new(1, -30, 0, 38)
	self.coinsLabel.TextSize = if compact or short then 13 else 30
	self.coinsLabel.TextXAlignment = if compact or short then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
	self.legend.Visible = not compact and not short
	self.helpButton.Text = if compact or short then "?" else "HOW TO PLAY / H"
	self.helpButton.Size = UDim2.fromOffset(if compact or short then 44 else 146, 44)
	self.helpButton.Position = if compact or short then UDim2.fromOffset(14, 18) else UDim2.new(0, 22, 1, -68)
	self.rewardsButton.Position = if compact or short then UDim2.fromOffset(14, 76) else UDim2.new(0, 178, 1, -68)
	self.rewardsButton.Size = UDim2.fromOffset(if compact then 60 elseif short then 92 else 112, 44)
	self.rewardsButton.TextSize = if compact then 9 else 12
	self.soundButton.Position = if compact or short then UDim2.fromOffset(14, 128) else UDim2.new(0, 22, 1, -112)
	self.soundButton.Size = UDim2.fromOffset(if compact or short then 92 else 84, 36)
	self.soundButton.Visible = not compact and not short
	self.resultsPanel.Size = UDim2.fromOffset(math.min(width-32, 468), math.min(264, height-32))
	self.resultTitle.TextSize = if compact then 22 else 27
	self.modalPanel.Size = UDim2.fromOffset(math.min(width-28, 468), math.min(height-24, 374))
	self.modalTitle.TextSize = if compact then 19 else 22
	self.modalBody.TextSize = if short then 13 elseif compact then 14 else 16
	self.noticePanel.Size = UDim2.fromOffset(math.min(width-32, 420), 48)
	self.noticePanel.Position = UDim2.new(.5, 0, 0, if short then 145 else 174)
	if self.state then self:updateLocalValues() end
end

function Hud:showModal(kind)
	self.modalKind = kind
	self.modal.Visible = true
	if kind == "Rewards" then
		self:updateRewardModal()
	else
		self.modalTitle.Text = "A QUICK BRAIN BRIEF"
		self.modalBody.Text = "01   COLLECT THE GLOW\nPink +1 • Gold +5 • Prism +10\n\n02   KEEP YOUR COOL\nLow gravity hits mid-round. Fall? You pop back with your score.\n\n03   BE THE BIGGEST BRAIN\nMost cells wins. Ties share the crown. Rounds start automatically."
		self.modalAction.Text = "LET'S GO"
	end
end

function Hud:updateRewardModal()
	local row = self.localRow
	self.modalTitle.Text = "YOUR NEXT FLEX"
	local owned = row and row.haloOwned
	local balance = if row then row.coins else 0
	self.modalBody.Text = "PULSE HALO\nA cyan orbit for a truly overactive brain.\n\n" .. (if owned then "You own this glow for the current session." else "Unlock with " .. self.config.HaloCost .. " coins earned by playing.") .. "\nBalance: " .. balance .. " session coins.\n\nCoins and unlocks reset when you leave. No Robux. No purchases."
	self.modalAction.Text = if owned then (if row.haloEquipped then "UNEQUIP HALO" else "EQUIP HALO") else "UNLOCK PULSE HALO  •  " .. self.config.HaloCost
end

function Hud:updateLocalValues()
	local row = self.localRow
	local coins = if row then row.coins else 0
	self.scoreLabel.Text = tostring(if row then row.score else 0)
	self.coinsLabel.Text = if self.compact or self.root.AbsoluteSize.Y < 500 then (tostring(coins) .. "  SESSION COINS") else tostring(coins)
	if self.modal.Visible and self.modalKind == "Rewards" then self:updateRewardModal() end
end

function Hud:update(state)
	self.state = state
	self.localRow = nil
	local found = {}
	for index, row in state.rows do
		found[row.id] = true
		if row.id == self.userId then self.localRow = row end
		local view = self.rows[row.id]
		if not view then
			local frame = make("Frame", { Name = "Player_" .. row.id, Size = UDim2.new(1, -4, 0, 34), BackgroundColor3 = C.Panel, BorderSizePixel = 0 }, self.roster)
			corner(frame, 9)
			view = {
				frame = frame,
				rank = text(frame, "Rank", "", UDim2.fromOffset(30, 34), UDim2.fromOffset(8, 0), C.Muted, nil, 11),
				name = text(frame, "Player", "", UDim2.new(1, -82, 1, 0), UDim2.fromOffset(36, 0), C.White, Enum.Font.GothamMedium, 11),
				score = text(frame, "Cells", "", UDim2.fromOffset(38, 34), UDim2.new(1, -44, 0, 0), C.White, nil, 14),
			}
			view.score.TextXAlignment = Enum.TextXAlignment.Right
			view.name.TextTruncate = Enum.TextTruncate.AtEnd
			self.rows[row.id] = view
		end
		view.frame.LayoutOrder = index
		view.frame.BackgroundColor3 = if row.id == self.userId then Color3.fromRGB(70, 48, 113) else C.Panel
		view.rank.Text = string.format("%02d", index)
		view.rank.TextColor3 = if index == 1 then C.Gold else C.Muted
		view.name.Text = row.name .. (if row.id == self.userId then " (you)" else "")
		view.score.Text = tostring(row.score)
	end
	for id, view in self.rows do
		if not found[id] then view.frame:Destroy(); self.rows[id] = nil end
	end
	self:updateLocalValues()
	self.resultsPanel.Visible = state.phase == "Results"
	if state.phase == "Results" and state.results then
		local results = state.results
		local winners = results.winners
		if #winners == 0 then
			self.resultTitle.Text = "THE BRAINS ARE WARMING UP"
			self.resultName.Text = "No cells collected this time.\nNext round is yours."
		elseif #winners == 1 then
			self.resultTitle.Text = "BIG BRAIN ENERGY"
			self.resultName.Text = winners[1].name .. " wins!\n" .. results.topScore .. " Brain Cells"
		else
			self.resultTitle.Text = "A MEETING OF MINDS!"
			local names = {}
			for index, row in winners do
				if index <= 3 then table.insert(names, row.name) end
			end
			self.resultName.Text = table.concat(names, ", ") .. (if #winners > 3 then " + more" else "") .. "\nTied at " .. results.topScore .. " cells"
		end
		local reward = results.rewards[tostring(self.userId)] or 0
		self.resultReward.Text = if reward > 0 then ("+" .. reward .. " SESSION COINS") else "YOUR NEXT ROUND STARTS SOON"
	end
	if state.phase ~= self.lastPhase then
		if state.phase == "Playing" then self:notice("GRAB THE GLOW! Pink +1 • Gold +5 • Prism +10") end
		self.lastPhase = state.phase
	end
	if state.eventActive and not self.lastEvent then self:notice("LOW GRAVITY! Moon feet. Same mission.") end
	self.lastEvent = state.eventActive
	self:tick()
end

function Hud:tick()
	local state = self.state
	if not state then return end
	local now = Workspace:GetServerTimeNow()
	local remaining = math.max(0, state.phaseEndsAt-now)
	self.timeLabel.Text = if state.phase == "Waiting" then "--:--" else timeString(remaining)
	local phase = if state.phase == "Playing" then string.format("ROUND %02d • COLLECT", state.roundId)
		elseif state.phase == "Intermission" then "GET READY • AUTO JOIN"
		elseif state.phase == "Results" then "ROUND COMPLETE" else "WAITING FOR BRAINS"
	self.phaseLabel.Text = phase .. (if state.fastMode then " • TEST" else "")
	self.timeLabel.TextColor3 = if state.phase == "Playing" and remaining <= 15 then C.Pink else C.White
	if state.eventActive then
		self.eventLabel.Text = "LOW GRAVITY  /  " .. timeString(state.eventEndsAt-now)
		self.eventLabel.TextColor3 = C.Cyan
		self.eventPanel.BackgroundColor3 = Color3.fromRGB(64, 40, 111)
	else
		self.eventLabel.Text = if state.phase == "Playing" then "GRAB THE GLOW. TOP THE BOARD." else "NEXT ROUND IS AUTOMATIC. YOU'RE IN."
		self.eventLabel.TextColor3 = C.Muted
		self.eventPanel.BackgroundColor3 = C.Ink
	end
	self.resultNext.Text = "INTERMISSION IN " .. timeString(remaining) .. "  •  KEEP YOUR NEURONS WARM."
end

function Hud:notice(message)
	self.noticeToken += 1
	local token = self.noticeToken
	self.noticeLabel.Text = message
	self.noticePanel.Visible = true
	task.delay(3.5, function()
		if self.noticeToken == token then self.noticePanel.Visible = false end
	end)
end

function Hud:pulse()
	if self.reducedMotion then return end
	self.scoreScale.Scale = 1.16
	TweenService:Create(self.scoreScale, TweenInfo.new(.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

function Hud:destroy()
	for _, connection in self.connections do connection:Disconnect() end
	self.screen:Destroy()
end

return Hud
