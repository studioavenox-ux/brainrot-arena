--!nonstrict
-- The interface. Every value shown here arrives in a server snapshot; nothing is
-- invented locally. Layout is responsive (desktop / tablet / phone portrait and
-- landscape) and every button opens a real panel or sends a whitelisted request.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local Panels = require(script.Parent.Panels)
local Iconography = require(script.Parent.Iconography)
local Collection = require(script.Parent.Collection)
local CreatureData = require(script.Parent.CreatureData)
local Hud = {}
Hud.__index = Hud

local C, Type, Space, Motion, Copy = Theme.Colors, Theme.Type, Theme.Space, Theme.Motion, Theme.Copy

local function timeString(remaining)
	local seconds = math.max(0, math.ceil(remaining))
	return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function phaseWord(phase, fastMode)
	if phase == "Playing" then
		return Copy.PlayingStatus
	elseif phase == "Intermission" then
		return Copy.IntermissionStatus
	elseif phase == "Results" then
		return Copy.ResultsStatus
	end
	return Copy.WaitingStatus
end

-- Chaos Event kinds -> the words the player reads. Mirrors RoundMachine's LABEL, which
-- the server also sends in the snapshot schedule.
local EVENT_LABEL = {
	LowGravity = "LOW GRAVITY",
	BouncyWorld = "BOUNCY WORLD",
	SlipperyChaos = "SLIPPERY CHAOS",
	BrainCellRush = "BRAIN CELL RUSH",
}

local function eventLabel(kind)
	if type(kind) ~= "string" or kind == "" then
		return Copy.EventBanner
	end
	return EVENT_LABEL[kind] or string.upper(kind)
end

function Hud.new(config, request)
	local self = setmetatable({}, Hud)
	self.config, self.request = config, request
	self.soundOn, self.reducedMotion = true, false
	self.state, self.rows, self.connections = nil, {}, {}
	self.noticeToken, self.noticeSerial = 0, 0
	self.lastPhase, self.lastEvent = "", false
	self.modalKind = nil
	self.userId = Players.LocalPlayer.UserId

	self.screen = Kit.instance("ScreenGui", {
		Name = "BrainrotHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	}, Players.LocalPlayer:WaitForChild("PlayerGui"))
	self.root = Kit.instance("Frame", {
		Name = "SafeArea", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
	}, self.screen)
	-- Scrims are built after `root` exists; declared here so resize() can see them.

	-- ---- legibility scrims (never interactive) ------------------------------
	-- The world is bright; a soft navy wash at the top and bottom keeps translucent
	-- panels readable without dimming the play space in the middle of the screen.
	self.scrimTop = Kit.scrim(self.root, 170, true, { zIndex = 0 })
	self.scrimBottom = Kit.scrim(self.root, 130, false, { zIndex = 0 })

	-- ---- top HUD: brand, brain cells, round timer, coins --------------------
	self.top = Panels.topHud(self.root, {
		Specimens = function() self:showCollection() end,
	})

	-- ---- leaderboard (right) ----------------------------------------------
	self.board = Panels.leaderboard(self.root)
	self.boardVisible = true
	self.ranksTouched = false

	-- ---- bottom action bar: shop / inventory / settings --------------------
	self.actions = Panels.actionBar(self.root, {
		Shop = function() self:showModal("Shop") end,
		Inventory = function() self:showCollection() end,
		Settings = function() self:showModal("Settings") end,
	})

	-- ---- steal action (right, above the bottom edge) -----------------------
	-- The only offensive verb in the game. It sends a whitelisted request with no
	-- arguments; the server decides who is in range and what (if anything) moves.
	self.steal = Panels.stealPanel(self.root, function() self:requestSteal() end)

	-- ---- stage chip (left, under the cells) --------------------------------
	self.stageChip = Kit.panel(self.root, "StageChip", UDim2.fromOffset(196, 28), UDim2.fromOffset(Space.xl, 136), {
		zIndex = 2, radius = 10, color = C.NavyRaised, visible = false,
	})
	self.stageText = Kit.text(self.stageChip, "Stage", "", "Label", {
		size = UDim2.new(1, -16, 1, 0), position = UDim2.fromOffset(8, 0),
		color = C.Amber, zIndex = 3, truncate = true,
	})

	-- ---- centre messaging --------------------------------------------------
	self.toast = Panels.toast(self.root)
	self.event = Panels.eventBanner(self.root)
	self.lobby = Panels.lobbyBanner(self.root)

	-- ---- rarity key above the action bar -----------------------------------
	self.legend = Kit.panel(self.root, "RarityKey", UDim2.fromOffset(368, 26), UDim2.new(.5, 0, 1, -Space.lg - 52 - 32), {
		anchor = Vector2.new(.5, 0), radius = 10, transparency = .3, zIndex = 2,
	})
	for index, entry in { { "+1  BRAIN / FROG", C.Cyan, 1 }, { "+5  FISH / GOOSE", C.Amber, 5 }, { "+10  TOAST / SOCK", C.Violet, 10 } } do
		local slot = Kit.instance("Frame", {
			Name = "Rarity" .. index,
			Size = UDim2.fromOffset(120, 26),
			Position = UDim2.fromOffset(6 + (index - 1) * 120, 0),
			BackgroundTransparency = 1,
			ZIndex = 3,
		}, self.legend)
		local label = Kit.text(slot, "Label", entry[1], "Micro", {
			size = UDim2.new(1, -24, 1, 0), position = UDim2.fromOffset(22, 0),
			color = entry[2], truncate = true, zIndex = 4,
		})
		label.Font = Enum.Font.GothamMedium
		Iconography.glyph(slot, entry[3], entry[2]).Position = UDim2.fromOffset(3, 5)
	end

	-- ---- results card ------------------------------------------------------
	self.results = Kit.panel(self.root, "Results", UDim2.fromOffset(468, 268), UDim2.fromScale(.5, .44), {
		anchor = Vector2.new(.5, .5), zIndex = 8, visible = false, padding = Space.xl,
	})
	Kit.text(self.results, "Eyebrow", Copy.ResultsStatus, "Label", {
		size = UDim2.new(1, 0, 0, 16), color = C.Cyan, xAlign = Enum.TextXAlignment.Center,
	})
	self.resultTitle = Kit.text(self.results, "Title", Copy.WinBanner, "Display", {
		size = UDim2.new(1, 0, 0, 44), position = UDim2.fromOffset(0, 22),
		color = C.Amber, xAlign = Enum.TextXAlignment.Center, truncate = true,
	})
	self.resultName = Kit.text(self.results, "Winner", "", "Heading", {
		size = UDim2.new(1, 0, 0, 52), position = UDim2.fromOffset(0, 70),
		color = C.White, xAlign = Enum.TextXAlignment.Center, wrapped = true,
	})
	self.resultCast = Kit.text(self.results, "Cast", "", "Micro", {
		size = UDim2.new(1, 0, 0, 14), position = UDim2.fromOffset(0, 124),
		color = C.Dim, xAlign = Enum.TextXAlignment.Center, truncate = true,
	})
	Kit.divider(self.results, 146, Space.xl)
	self.resultReward = Kit.text(self.results, "Reward", "", "Title", {
		size = UDim2.new(1, 0, 0, 30), position = UDim2.fromOffset(0, 158),
		color = C.Amber, xAlign = Enum.TextXAlignment.Center,
	})
	self.resultNext = Kit.text(self.results, "Next", "", "Micro", {
		size = UDim2.new(1, 0, 0, 30), position = UDim2.fromOffset(0, 196),
		color = C.Muted, xAlign = Enum.TextXAlignment.Center, wrapped = true,
	})

	-- ---- modal: shop / inventory / settings / help --------------------------
	self.modal = Kit.instance("Frame", {
		Name = "ModalLayer", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Void,
		BackgroundTransparency = .35, Visible = false, ZIndex = 20, Active = true,
	}, self.root)
	self.modalCard = Kit.panel(self.modal, "Card", UDim2.fromOffset(468, 348), UDim2.fromScale(.5, .5), {
		anchor = Vector2.new(.5, .5), zIndex = 21, padding = Space.xl,
	})
	self.modalTitle = Kit.text(self.modalCard, "Title", Copy.ShopTitle, "Title", {
		size = UDim2.new(1, -60, 0, 26), color = C.Amber, zIndex = 22,
	})
	self.modalBody = Kit.text(self.modalCard, "Body", "", "Body", {
		size = UDim2.new(1, 0, 1, -120), position = UDim2.fromOffset(0, 34),
		color = C.White, wrapped = true, zIndex = 22,
	})
	self.modalBody.TextYAlignment = Enum.TextYAlignment.Top
	self.modalFocus = nil
	self.modalPrimary = Kit.button(self.modalCard, "Action", "UNLOCK", UDim2.new(1, -56, 0, 44),
		UDim2.new(0, 0, 1, -44), function() self:activateModal() end,
		{ accent = C.Amber, zIndex = 22 })
	self.modalSound = Kit.button(self.modalCard, "ModalSound", "SFX ON", UDim2.fromOffset(110, 34),
		UDim2.new(0, 0, 1, -88), function() self:toggleSound() end, { accent = C.Cyan, zIndex = 22 })
	self.modalMotion = Kit.button(self.modalCard, "ModalMotion", "MOTION: FULL", UDim2.fromOffset(132, 34),
		UDim2.new(0, 118, 1, -88), function() self:toggleMotion() end, { accent = C.Violet, zIndex = 22 })
	self.modalClose = Kit.button(self.modalCard, "Close", "X", UDim2.fromOffset(36, 36),
		UDim2.new(1, -36, 0, 0), function() self:closeModal() end, { accent = C.NavyEdge, zIndex = 22 })
	self.modalClose.Label.TextSize = Type.Body

	-- ---- collection screen (six 3D specimen cards) --------------------------
	self.collection = Collection.new(self.root, self.config)

	-- ---- persistent secondary buttons -------------------------------------
	self.helpButton = Kit.button(self.root, "Help", "?", UDim2.fromOffset(36, 36),
		UDim2.fromOffset(Space.xl, 148), function() self:showModal("Help") end,
		{ accent = C.Cyan, zIndex = 3 })
	-- AnchorPoint (1,0) so every Position below is measured from the right edge.
	self.ranksButton = Kit.button(self.root, "Ranks", "RANKS", UDim2.fromOffset(84, 32),
		UDim2.new(1, -Space.lg - 84, 0, 128), function() self:toggleBoard() end,
		{ accent = C.Violet, zIndex = 3, anchor = Vector2.new(1, 0) })

	-- ---- input -------------------------------------------------------------
	self.modal.Parent = self.root
	self.ranksButton.Activated:Connect(function() self.ranksTouched = true end)
	table.insert(self.connections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then return end
		if input.KeyCode == Enum.KeyCode.Tab then
			self:toggleBoard()
			self.ranksTouched = true
		elseif input.KeyCode == Enum.KeyCode.H then
			if self.modal.Visible then self:closeModal() else self:showModal("Help") end
		elseif input.KeyCode == Enum.KeyCode.Escape and self.collection:isVisible() then
			self:hideCollection()
		elseif input.KeyCode == Enum.KeyCode.Escape and self.modal.Visible then
			self:closeModal()
		elseif input.KeyCode == Enum.KeyCode.C then
			if self.collection:isVisible() then self:hideCollection() else self:showCollection() end
		elseif input.KeyCode == Enum.KeyCode.B then
			self:showModal("Shop")
		elseif input.KeyCode == Enum.KeyCode.E then
			self:requestSteal()
		end
	end))
	table.insert(self.connections, self.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:resize()
	end))
	self:resize()
	return self
end

-- --------------------------------------------------------------------------- #
-- Layout
-- --------------------------------------------------------------------------- #
function Hud:resize()
	local size = self.root.AbsoluteSize
	local width, height = size.X, size.Y
	if width < 1 or height < 1 then return end
	local compact = width < 780
	local short = height < 520
	local portrait = width < height
	self.compact, self.short, self.portrait = compact, short, portrait

	local top = self.top
	self.scrimTop.Size = UDim2.new(1, 0, 0, math.min(190, math.max(120, height * .26)))
	self.scrimBottom.Size = UDim2.new(1, 0, 0, math.min(150, math.max(100, height * .2)))
	self.scrimBottom.Position = UDim2.new(0, 0, 1, -self.scrimBottom.Size.Y.Offset)
	-- Brand lockup: desktop only. Phones hide the whole cluster (wordmark AND
	-- tagline) because the cell counter already carries the identity up there and
	-- a stray tagline was showing through behind the coin panel.
	top.brand.Visible = not compact and not short
	top.brand.Position = UDim2.fromOffset(Space.xl, Space.lg)
	if top.brandTag then
		top.brandTag.Visible = top.brand.Visible
	end

	-- brain-cell counter: under the brand on desktop, top-left on compact
	-- Narrow phones cannot fit a 128px cell chip, a 96px clock and a 112px coin
	-- chip side by side (they summed to 336 on a 320pt screen), so the two end
	-- chips give way first.
	local narrow = compact and width < 380
	top.cells.Size = UDim2.fromOffset(if narrow then 92 elseif compact then 128 else 196,
		if short then 44 else 52)
	top.cells.Position = if compact then UDim2.fromOffset(Space.md, Space.md)
		else UDim2.fromOffset(Space.xl, 78)

	-- coin counter: top-right, never overlapping the clock. Sized before the clock
	-- because the clock's phone width is derived from the space it leaves.
	local coinWidth = if narrow then 96 elseif compact then 112 else 152
	top.coins.Size = UDim2.fromOffset(coinWidth, if short then 44 else 52)
	top.coins.Position = UDim2.new(1, -Space.md, 0, if compact then Space.sm else Space.lg)

	-- round clock: always centred at the top, shrinks on phones
	-- The clock keeps its centre line and narrows to whatever the two chips leave,
	-- so all three chips stay in one band. 88px is the floor where "00:00" reads.
	local clockWidth = math.clamp(width - 340, 150, 212)
	if compact then
		local cellChipRight = Space.md + top.cells.Size.X.Offset
		local coinChipLeft = width - Space.md - coinWidth
		clockWidth = math.clamp(coinChipLeft - cellChipRight - Space.lg, 88, 190)
	end
	top.clock.Size = UDim2.fromOffset(clockWidth, if short then 62 else 76)
	top.clock.Position = UDim2.new(.5, 0, 0, if short then Space.sm else Space.lg)
	top.time.TextSize = if short then 26 elseif compact then 30 else Type.Display
	top.roundLabel.Visible = not short
	top.divider.Visible = not short
	top.coinValue.TextSize = if compact then 18 else Type.Title
	top.coinValue.Size = UDim2.new(1, -40, 0, 24)
	-- Specimen chip sits under the coin counter, same width, so the right column
	-- reads as one stack.
	top.specimens.Size = UDim2.fromOffset(if compact then coinWidth else 152, 30)
	-- Phones: the coin chip is 112 wide and right-anchored, so it eats into the
	-- centre. The specimen chip tucks under it and clears the clock in both
	-- directions — it used to sit at y=66, straight through a 76px-tall clock.
	local clockRightHalf = (clockWidth * .5) + Space.xs
	local specimenX = if compact then clockRightHalf + Space.md + 4 else Space.md
	-- The clock sits at Space.sm from the top on short screens and Space.lg otherwise.
	local specimenY = (if short then Space.sm else Space.lg) + top.clock.Size.Y.Offset + Space.xs
	top.specimens.Position = UDim2.new(1, -specimenX, 0,
		if compact then specimenY else (Space.lg + 60))

	-- leaderboard
	local board = self.board
	board.board.Visible = self:boardShown()
	board.board.Size = UDim2.fromOffset(if compact then 196 else 232,
		math.clamp(height - (if short then 232 elseif compact then 190 else 230),
			if short then 96 else 150, 320))
	board.board.Position = UDim2.new(1, -Space.md, 0, if short then 118 elseif compact then 118 else 162)
	-- The RANKS chip sits below the specimen chip on phones (they used to overlap)
	-- and hides itself while the board is open, because then it would be a button
	-- for the thing already on screen.
	self.ranksButton.Visible = (compact or short) and not ((compact or short) and self:boardShown())
	-- Right-aligned with the coin/specimen stack, and on short landscape it sits in
	-- the 54..96 gap between the coin chip and the specimen chip. It used to tuck up
	-- to y=40, which put it straight through the bottom of the coin chip.
	local ranksWidth = if compact then 68 else 84
	local ranksTop = if compact then top.specimens.Position.Y.Offset + top.specimens.Size.Y.Offset + Space.xs
		else 128
	self.ranksButton.Size = UDim2.fromOffset(ranksWidth, 32)
	self.ranksButton.Position = UDim2.new(1, -Space.md - ranksWidth, 0, ranksTop)

	-- Action bar. On phones it sits above the thumbstick and jump zones so a tap on
	-- the shop never registers as a jump; on desktop it hugs the bottom edge.
	local barLift = if compact then 118 else Space.lg
	self.actions.bar.Position = UDim2.new(.5, 0, 1, -barLift - 52)
	self.actions.bar.Visible = true
	for _, name in { "Shop", "Inventory", "Settings" } do
		local button = self.actions.buttons[name]
		button.Size = UDim2.fromOffset(if compact then 76 else 84, 52)
		button.Position = UDim2.fromOffset(
			(if name == "Shop" then 0 elseif name == "Inventory" then (if compact then 84 else 92) else (if compact then 168 else 184)),
			0)
	end
	self.actions.bar.Size = UDim2.fromOffset(if compact then 252 else 268, 52)
	self.legend.Visible = not compact and not short
	self.legend.Position = UDim2.new(.5, 0, 1, -barLift - 52 - 32)

	-- help button sits under the stage chip on desktop, beside the cell counter on
	-- phones; either way it is clear of every other control.
	self.helpButton.Position = if compact then UDim2.new(0, Space.md, 0, 74) else UDim2.fromOffset(Space.xl, 172)

	-- toasts and banners. Two placements, decided by the width actually free at the
	-- top: a wide-short landscape phone keeps them in the corridor between the cell
	-- chip and the right-hand column, while a portrait phone has no corridor at all
	-- and stacks them under the whole top block. Pinning them at a fixed 112/174
	-- used to run the toast straight through the specimen chip.
	local corridor = (width - Space.md - coinWidth) - (Space.md + top.cells.Size.X.Offset)
		- Space.md * 2
	local stacked = corridor < 360
	local bandTop = if stacked
		then math.max(top.specimens.Position.Y.Offset + top.specimens.Size.Y.Offset,
			ranksTop + self.ranksButton.Size.Y.Offset) + Space.sm
		else (if short then 84 else 112)
	local toastWidth = math.min(width - 32, 432, if stacked then width - 32 else corridor)
	self.toast.frame.Size = UDim2.fromOffset(toastWidth, 56)
	self.toast.frame.Position = UDim2.new(.5, 0, 0, bandTop)
	local eventTop = bandTop + self.toast.frame.Size.Y.Offset + Space.sm
	self.event.frame.Size = UDim2.fromOffset(math.min(width - 40, 320), 34)
	self.event.frame.Position = UDim2.new(.5, 0, 0, eventTop)
	local lobbyTop = eventTop + self.event.frame.Size.Y.Offset + Space.sm
	self.lobby.frame.Size = UDim2.fromOffset(math.min(width - 32, 420), 92)
	self.lobby.frame.Position = UDim2.new(.5, 0, 0, lobbyTop)

	-- Steal action. Portrait/desktop: bottom-right. Short landscape: bottom-LEFT,
	-- above the thumbstick, so it cannot sit under the leaderboard or the jump pad.
	local stealLift = if compact then 118 else Space.lg
	if short then
		self.steal.root.Position = UDim2.fromOffset(Space.md, height - stealLift - 52)
	else
		self.steal.root.Position = UDim2.new(1, -Space.md, 1, -stealLift - 52)
	end
	self.steal.root.Size = UDim2.fromOffset(if compact then 150 else 186, 52)
	self.steal.button.Size = self.steal.root.Size
	self.steal.readout.Size = UDim2.fromOffset(if compact then 150 else 186, 30)
	self.steal.readout.Position = UDim2.fromOffset(0, -38)
	self.steal.label.TextSize = if compact then 13 else Type.Heading
	self.steal.caption.TextSize = Type.Micro
	self.steal.carried.TextSize = if compact then Type.Micro else Type.Label
	self.steal.banked.Visible = not compact

	-- Stage chip: desktop only, under the cell counter and above the help chip. On
	-- phones the stage is named by the clock header instead, which keeps the top of
	-- a small screen uncrowded and still answers "how long until the next bank?".
	self.stageChip.Visible = not compact and not short
		and self.state ~= nil and (self.state.stage or "") ~= ""
	self.stageChip.Size = UDim2.fromOffset(196, 26)
	self.stageChip.Position = UDim2.fromOffset(Space.xl, 136)

	-- cards
	self.results.Size = UDim2.fromOffset(math.min(width - 32, 468), math.min(height - 32, 268))
	self.resultTitle.TextSize = if compact then 24 else Type.Display
	self.modalCard.Size = UDim2.fromOffset(math.min(width - 28, 468), math.min(height - 24, 348))
	self.modalPrimary.Size = UDim2.new(1, -56, 0, 44)
	self.modalBody.TextSize = if short then 12 elseif compact then 13 else Type.Body
	self.modalTitle.TextSize = if compact then 18 else Type.Title
	self.collection:resize(width, height)

	if self.state then self:updateLocalValues() end
end

-- True when the leaderboard is actually on screen for this viewport. On phones and
-- on short landscape screens the board is opt-in (RANKS), because at 354 px of
-- height it would otherwise sit under the action bar and the steal panel.
function Hud:boardShown()
	return self.boardVisible and not ((self.compact or self.short) and not self.ranksTouched)
end

function Hud:toggleBoard()
	self.boardVisible = not self.boardVisible
	self.board.board.Visible = self.boardVisible
	-- The RANKS chip and the board are mutually exclusive on phones.
	self:resize()
end

-- --------------------------------------------------------------------------- #
-- Server state
-- --------------------------------------------------------------------------- #
function Hud:update(state)
	self.state = state
	self.localRow = nil
	-- The server sends rows in rank order; sort defensively so a stale snapshot can
	-- never show a lower score above a higher one.
	local ordered = table.clone(state.rows)
	table.sort(ordered, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		return a.name < b.name
	end)
	local found = {}
	for index, row in ordered do
		found[row.id] = true
		if row.id == self.userId then self.localRow = row end
		local view = self.rows[row.id]
		if not view then
			view = Panels.row(self.board.roster, row.id, index)
			self.rows[row.id] = view
		end
		local mine = row.id == self.userId
		view.frame.LayoutOrder = index
		view.frame.BackgroundColor3 = if mine then C.NavyRaised else C.Navy
		view.frame.BackgroundTransparency = if mine then .05 else .4
		view.accent.BackgroundColor3 = if index == 1 then C.Amber else (if mine then C.Cyan else C.NavyEdge)
		view.accent.BackgroundTransparency = if index == 1 or mine then 0 else .5
		view.rank.Text = string.format("%02d", index)
		view.rank.TextColor3 = if index == 1 then C.Amber else C.Dim
		view.name.Text = row.name .. (if mine then "  • you" else "")
		view.score.Text = tostring(row.score)
		view.score.TextColor3 = if index == 1 then C.Amber else C.Cyan
	end
	for id, view in self.rows do
		if not found[id] then
			view.frame:Destroy()
			self.rows[id] = nil
		end
	end
	-- Stage chip: the server names the stage; the copy explains what is at risk.
	local stage = state.stage or ""
	local stageCopy = {
		Collect = Copy.StageCollect, Compete = Copy.StageCompete,
		Chaos = Copy.StageChaos, Final = Copy.StageFinal,
	}
	self.stageChip.Visible = stage ~= "" and not self.short and not self.compact
	self.stageText.Text = stageCopy[stage] or string.upper(stage)
	self.stageText.TextColor3 = if stage == "Final" then C.Danger
		elseif stage == "Chaos" then C.Violet else C.Amber
	self:updateLocalValues()
	self:updateResults(state)
	self:updateBanners(state)
	self.collection:update(self.localRow)
	self:tick()
end

-- Every steal control reads the server's own cooldown / protection timestamps, so
-- the button never promises something the server would refuse.
function Hud:refreshSteal()
	local row = self.localRow
	local now = Workspace:GetServerTimeNow()
	local playing = self.state and self.state.phase == "Playing"
	local readyAt = if row then (row.stealReadyAt or 0) else 0
	local cooldown = math.max(0, readyAt - now)
	local protected = if row then math.max(0, (row.protectedUntil or 0) - now) else 0
	local carried = if row then (row.carriedValue or 0) else 0
	local carriedCount = if row then (row.carried or 0) else 0
	self.stealCooldown = cooldown

	local label, caption, color = Copy.StealReady, "8s COOLDOWN", C.White
	if not playing then
		label, caption, color = Copy.StealBar, "COLLECT PHASE", C.Muted
	elseif protected > 0 then
		label, caption, color = Copy.StealProtected, string.format("%.0fs", math.ceil(protected)), C.Cyan
	elseif cooldown > 0 then
		label = string.format("%.1fs", cooldown)
		caption, color = Copy.StealCooldown, C.Muted
	end
	self.steal.label.Text = label
	self.steal.label.TextColor3 = color
	self.steal.caption.Text = caption
	-- Veil drains left-to-right as the cooldown expires.
	local span = self.config and self.config.Steal and self.config.Steal.Cooldown or 8
	self.steal.veil.Size = UDim2.fromScale(math.clamp(cooldown / span, 0, 1), 1)
	self.steal.carried.Text = tostring(carried)
	self.steal.carried.TextColor3 = if carried > 0 then C.Amber else C.Muted
	self.steal.banked.Text = string.format("%d IN %d CELLS", carried, carriedCount)
end

function Hud:updateLocalValues()
	local row = self.localRow
	local cells = if row then row.score else 0
	local coins = if row then row.coins else 0
	self.top.cellValue.Text = tostring(cells)
	self.top.coinValue.Text = tostring(coins)
	local collected = if row then row.collected else 0
	self.top.specimenText.Text = if self.compact
		then "SPECS  " .. collected .. "/6"
		else "SPECIMENS  " .. collected .. " / 6"
	self.top.specimenText.TextColor3 = if collected >= 6 then C.Amber else C.Cyan
	if self.state then
		-- On phones the clock is narrow: the round number alone still fits.
		local round = string.format("ROUND %02d", self.state.roundId or 0)
		self.top.roundLabel.Text = if self.compact then round
			else round .. "  •  " .. (if self.state.fastMode then "QUICK TEST" else self.config.ArenaName)
	end
	if self.modal.Visible then
		self:refreshModal()
	end
end

function Hud:updateResults(state)
	local showing = state.phase == "Results" and state.results ~= nil
	if showing ~= self.results.Visible then
		self.results.Visible = showing
		if showing then
			Kit.enter(self.results, { reducedMotion = self.reducedMotion, rise = 16 })
		end
	end
	if not showing then
		return
	end
	local results = state.results
	local winners = results.winners
	if #winners == 0 then
		self.resultTitle.Text = Copy.NoScoreBanner
		self.resultName.Text = "No cells collected this time.\nThe next round is yours."
	elseif #winners == 1 then
		self.resultTitle.Text = Copy.WinBanner
		self.resultName.Text = winners[1].name .. " wins!\n" .. results.topScore .. " brain cells"
	else
		self.resultTitle.Text = Copy.TieBanner
		local names = {}
		for index, row in winners do
			if index <= 3 then table.insert(names, row.name) end
		end
		self.resultName.Text = table.concat(names, ", ") .. (if #winners > 3 then " + more" else "")
			.. "\nTied at " .. results.topScore .. " cells"
	end
	-- Phase 5 results now name the steal stat, because stealing is how a round is won.
	local me = self.localRow
	if me then
		self.resultCast.Text = string.format("%s  •  %d %s  •  %d %s",
			self:castLine(results.roundId), me.steals or 0, Copy.ResultsSteals, me.lost or 0, Copy.ResultsLost)
	else
		self.resultCast.Text = self:castLine(results.roundId)
	end
	local reward = results.rewards[tostring(self.userId)] or 0
	self.resultReward.Text = if reward > 0 then "+" .. reward .. " COINS" else "NEXT ROUND SOON"
end

function Hud:updateBanners(state)
	self.lobby.frame.Visible = state.phase ~= "Playing"
	if self.lobby.frame.Visible then
		local remaining = math.max(0, (state.phaseEndsAt or 0) - Workspace:GetServerTimeNow())
		self.lobby.status.Text = phaseWord(state.phase, state.fastMode)
		self.lobby.status.TextColor3 = if state.phase == "Results" then C.Amber else C.Cyan
		if state.phase == "Intermission" then
			self.lobby.countdown.Text = "ARENA OPENS IN " .. timeString(remaining)
		elseif state.phase == "Results" then
			self.lobby.countdown.Text = "NEXT ROUND IN " .. timeString(remaining)
		else
			self.lobby.countdown.Text = "WAITING FOR THE FIRST PLAYER"
		end
	end
	-- Event banner: shows the incoming warning first, then the live window, both
	-- straight from the server's own schedule.
	local now = Workspace:GetServerTimeNow()
	local warning = state.eventWarning or ""
	if state.eventActive then
		self.event.frame.Visible = true
		self.event.label.Text = string.upper(eventLabel(state.eventKind))
			.. "  •  " .. Copy.EventLive .. "  " .. timeString(state.eventEndsAt - now)
		self.event.label.TextColor3 = C.Cyan
		self.event.dot.BackgroundColor3 = C.Cyan
	elseif warning ~= "" then
		self.event.frame.Visible = true
		self.event.label.Text = Copy.EventIncoming .. ": " .. string.upper(eventLabel(warning))
			.. "  •  " .. timeString((state.eventWarningEndsAt or 0) - now)
		self.event.label.TextColor3 = C.Amber
		self.event.dot.BackgroundColor3 = C.Amber
	else
		self.event.frame.Visible = false
	end
end

function Hud:tick()
	local state = self.state
	if not state then return end
	local now = Workspace:GetServerTimeNow()
	local remaining = math.max(0, (state.phaseEndsAt or 0) - now)
	self.top.time.Text = if state.phase == "Waiting" then "--:--" else timeString(remaining)
	self.top.time.TextColor3 = if state.phase == "Playing" and remaining <= 15 then C.Danger else C.White
	-- While a round is live the clock's header names the STAGE, so the one number
	-- that matters most (time until the next bank) reads first. Phases keep their
	-- own words; the stage chip is the long form.
	local stageWord = self.stageText and self.stageText.Text or ""
	self.top.phase.Text = if state.phase == "Playing" and stageWord ~= ""
		then string.upper(string.match(stageWord, "^%S+") or Copy.PlayingStatus)
		else phaseWord(state.phase, state.fastMode)
	self.top.phase.TextColor3 = if state.phase == "Playing" then C.Cyan
		elseif state.phase == "Results" then C.Amber else C.Violet
	self:updateBanners(state)
	if self.lobby.frame.Visible then
		if state.phase == "Intermission" then
			self.lobby.countdown.Text = "ARENA OPENS IN " .. timeString(remaining)
		elseif state.phase == "Results" then
			self.lobby.countdown.Text = "NEXT ROUND IN " .. timeString(remaining)
		end
	end
	if state.eventActive then
		self.event.label.Text = string.upper(eventLabel(state.eventKind)) .. "  •  " .. Copy.EventLive
			.. "  " .. timeString(state.eventEndsAt - now)
	elseif (state.eventWarning or "") ~= "" then
		self.event.label.Text = Copy.EventIncoming .. ": " .. string.upper(eventLabel(state.eventWarning))
			.. "  •  " .. timeString((state.eventWarningEndsAt or 0) - now)
	end
	if self.results.Visible then
		self.resultNext.Text = "INTERMISSION IN " .. timeString(remaining)
	end
	self.collection:step(now, self.reducedMotion)
	self:refreshSteal()
end

-- --------------------------------------------------------------------------- #
-- Toast
-- --------------------------------------------------------------------------- #
function Hud:notice(message, accent)
	self.noticeToken += 1
	local token = self.noticeToken
	self.toast.label.Text = message
	self.toast.accent.BackgroundColor3 = accent or C.Cyan
	self.toast.frame.Visible = true
	Kit.enter(self.toast.frame, { reducedMotion = self.reducedMotion, rise = 10, duration = Motion.Toast })
	task.delay(Motion.Notice, function()
		if self.noticeToken == token then
			self.toast.frame.Visible = false
		end
	end)
end

function Hud:pulse()
	if self.reducedMotion then return end
	self.top.cellScale.Scale = 1.14
	TweenService:Create(self.top.cellScale, TweenInfo.new(Motion.Fast, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

-- --------------------------------------------------------------------------- #
-- Shop / inventory / settings / help
-- --------------------------------------------------------------------------- #
function Hud:showModal(kind)
	self.modalKind = kind
	self.modal.Visible = true
	self:refreshModal()
end

function Hud:closeModal()
	self.modal.Visible = false
	self.modalKind = nil
end

-- The steal request carries no target, no distance and no value: the server
-- resolves everything from its own state.
function Hud:requestSteal()
	if self.modal.Visible or self.collection:isVisible() then
		return
	end
	if not self.state or self.state.phase ~= "Playing" then
		self:notice(Copy.StealBar .. " • " .. Copy.IntermissionStatus, C.Muted)
		return
	end
	if (self.stealCooldown or 0) > 0 then
		return
	end
	self.request("Steal")
	-- Optimistic veil only: the visible countdown still comes from the server row.
	self.stealCooldown = self.config.Steal.Cooldown
	self.steal.label.TextColor3 = C.Muted
end

-- The server's verdict, shown as a short toast. A refusal always explains itself.
function Hud:stealResult(result, value)
	local messages = {
		ok = { "STEAL!  +" .. tostring(value), C.Success },
		empty = { Copy.StealEmpty, C.Muted },
		["out-of-range"] = { Copy.StealOutOfRange, C.Muted },
		["cooldown"] = { Copy.StealCooldown, C.Muted },
		["protected"] = { Copy.StealProtected, C.Muted },
		["immune"] = { Copy.StealImmune, C.Muted },
		["repeat"] = { Copy.StealRepeat, C.Muted },
		["self"] = { Copy.StealEmpty, C.Muted },
		["inactive-round"] = { Copy.StealBar, C.Muted },
	}
	local entry = messages[result] or { Copy.StealOutOfRange, C.Muted }
	self:notice(entry[1], entry[2])
	if result == "ok" then
		self:pulse()
	end
end

function Hud:showCollection()
	self.collection:show()
	self.collection:update(self.localRow)
end

function Hud:hideCollection()
	self.collection:hide()
end

function Hud:refreshModal()
	local kind = self.modalKind
	local row = self.localRow
	local owned = row and row.haloOwned
	local equipped = row and row.haloEquipped
	local coins = if row then row.coins else 0
	if kind == "Shop" then
		self.modalTitle.Text = Copy.ShopTitle
		self.modalTitle.TextColor3 = C.Amber
		self.modalBody.Text = Copy.ShopBody .. "\n\nPULSE HALO — " .. self.config.HaloCost .. " session coins."
			.. "\n\nBalance: " .. coins .. " coins."
			.. (if owned then "\n\nYou already own this glow for the session." else "")
		self.modalPrimary.Label.Text = if owned then (if equipped then "UNEQUIP" else "EQUIP") else "UNLOCK  •  " .. self.config.HaloCost
		self.modalPrimary.Visible = true
	elseif kind == "Inventory" then
		self.modalTitle.Text = Copy.InventoryTitle
		self.modalTitle.TextColor3 = C.Cyan
		local lines = {}
		if row then
			table.insert(lines, string.format("ROUND SCORE      %d", row.score))
			table.insert(lines, string.format("ROUNDS WON      %d", row.wins))
			table.insert(lines, string.format("CELLS CLAIMED   %d", row.pickups))
			table.insert(lines, string.format("SESSION COINS   %d", row.coins))
			table.insert(lines, "")
			if owned then
				table.insert(lines, "PULSE HALO      " .. (if equipped then "EQUIPPED" else "OWNED"))
			else
				table.insert(lines, "PULSE HALO      NOT OWNED")
			end
		else
			table.insert(lines, Copy.InventoryEmpty)
		end
		self.modalBody.Text = table.concat(lines, "\n")
		self.modalPrimary.Visible = owned
		self.modalPrimary.Label.Text = if equipped then "UNEQUIP" else "EQUIP"
	elseif kind == "Settings" then
		self.modalTitle.Text = Copy.SettingsTitle
		self.modalTitle.TextColor3 = C.Violet
		self.modalBody.Text = "Sound and music: " .. (if self.soundOn then "ON" else "OFF")
			.. "\nMotion: " .. (if self.reducedMotion then "REDUCED" else "FULL")
			.. "\n\nREDUCED MOTION turns off camera-shaking effects, halo breathing and\npanel transitions. It never changes gameplay."
		self.modalPrimary.Visible = false
	else
		self.modalTitle.Text = "HOW TO PLAY"
		self.modalTitle.TextColor3 = C.Cyan
		self.modalBody.Text = "01   COLLECT THE CAST\nBrain or frog +1  •  fish or goose +5  •  toast or sock +10"
			.. "\n\n02   BANK, THEN STEAL\nEach stage banks what you carry. Between banks, tap STEAL (or E) beside a rival to take one cell they are carrying."
			.. "\n\n03   SURVIVE THE CHAOS\nOne Chaos Event per round, 35 seconds: low gravity, bouncy jumps, slippery stone or Brain Cell Rush. Each one warns you first."
			.. "\n\n04   BE THE BIGGEST BRAIN\nMost cells after the Final Rush wins. Ties share the crown."
		self.modalPrimary.Visible = false
	end
	self.modalSound.Label.Text = if self.soundOn then "SFX ON" else "SFX OFF"
	self.modalMotion.Label.Text = if self.reducedMotion then "REDUCED MOTION: ON" else "MOTION: FULL"
end

function Hud:activateModal()
	local kind = self.modalKind
	if kind == "Shop" or kind == "Inventory" then
		-- The only cosmetic verb the server accepts. Ownership is decided server-side.
		self.request("Halo")
	end
end

function Hud:toggleSound()
	self.soundOn = not self.soundOn
	self:refreshModal()
end

function Hud:toggleMotion()
	self.reducedMotion = not self.reducedMotion
	self:refreshModal()
end

-- Deterministic flavour line, chosen from the round id only. No gameplay meaning.
function Hud:castLine(roundId)
	local round = math.max(1, math.floor(tonumber(roundId) or 1))
	local value = if round % 3 == 0 then 10 elseif round % 3 == 1 then 1 else 5
	local family = CreatureData.Family[value]
	local spec = CreatureData.Creatures[family[(round % 2) + 1]]
	return spec.Label .. "  •  " .. spec.Blurb
end

function Hud:destroy()
	for _, connection in self.connections do connection:Disconnect() end
	self.collection:destroy()
	self.screen:Destroy()
end

return Hud
