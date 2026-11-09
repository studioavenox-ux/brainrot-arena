--!nonstrict
-- Top HUD, leaderboard, bottom action bar, centre toasts and the lobby banner.
--
-- Every number on screen comes from the server snapshot (`hud:update(state)`).
-- Nothing here invents a player, a score or a timer: if the server has not sent a
-- roster yet, the panels show their empty state.
local Players = game:GetService("Players")
local Kit = require(script.Parent.Kit)
local T = require(script.Parent.Theme)
local Iconography = require(script.Parent.Iconography)

local Panels = {}

local C, Type, Space, Motion, Copy = T.Colors, T.Type, T.Space, T.Motion, T.Copy

-- Glyphs are frames and corners only: no images, no asset ids.
local function glyph(parent, kind, color, size)
	local box = Kit.instance("Frame", {
		Name = "Glyph_" .. kind,
		Size = UDim2.fromOffset(size or 20, size or 20),
		BackgroundTransparency = 1,
	}, parent)
	local spec = T.Glyph[kind]
	local accent = color or C[(spec and spec.Accent) or "Cyan"]
	local function piece(name, w, h, x, y, round, transparency)
		local pieceFrame = Kit.instance("Frame", {
			Name = name,
			Size = UDim2.fromOffset(w, h),
			Position = UDim2.fromOffset(x, y),
			BackgroundColor3 = accent,
			BackgroundTransparency = transparency or 0,
			BorderSizePixel = 0,
		}, box)
		if round then
			Kit.corner(pieceFrame, round)
		end
		return pieceFrame
	end
	local s = size or 20
	local u = s / 20
	if kind == "cell" then
		-- three lobes, two rows: a readable brain at 20px
		piece("LobeA", 9 * u, 9 * u, 5.5 * u, 2 * u, 9 * u)
		piece("LobeB", 8 * u, 8 * u, 2 * u, 8 * u, 8 * u)
		piece("LobeC", 8 * u, 8 * u, 9 * u, 8.5 * u, 8 * u)
		piece("Stem", 3 * u, 4 * u, 8.5 * u, 15 * u, 2 * u, .25)
	elseif kind == "coin" then
		piece("Rim", 18 * u, 18 * u, 1 * u, 1 * u, 18 * u)
		local inner = piece("Inner", 9 * u, 9 * u, 5.5 * u, 5.5 * u, 9 * u)
		inner.BackgroundColor3 = C.Navy
		inner.BackgroundTransparency = 0
	elseif kind == "clock" then
		local ring = piece("Ring", 18 * u, 18 * u, 1 * u, 1 * u, 18 * u, .18)
		ring.BackgroundTransparency = .18
		piece("Hand", 2 * u, 6 * u, 9 * u, 4 * u, 1 * u)
		piece("Tick", 5 * u, 2 * u, 9 * u, 9 * u, 1 * u)
	elseif kind == "rank" then
		piece("Chevron", 8 * u, 8 * u, 3 * u, 3 * u, 2 * u)
	elseif kind == "shop" then
		piece("Bag", 14 * u, 12 * u, 3 * u, 6 * u, 3 * u)
		piece("Handle", 8 * u, 5 * u, 6 * u, 2 * u, 5 * u, .35)
	elseif kind == "inventory" then
		for row = 0, 1 do
			for column = 0, 1 do
				piece("Cell", 7 * u, 7 * u, (3 + column * 8) * u, (3 + row * 8) * u, 2 * u,
					if row == 0 and column == 1 then .45 else 0)
			end
		end
	elseif kind == "hook" then
		-- a hooked hand: palm block, thumb, curved finger
		piece("Palm", 11 * u, 10 * u, 4 * u, 4 * u, 3 * u)
		piece("Thumb", 4 * u, 6 * u, 1.5 * u, 6 * u, 2 * u)
		piece("Finger", 8 * u, 3 * u, 9 * u, 8 * u, 1.5 * u)
		piece("Hook", 3 * u, 7 * u, 15 * u, 8 * u, 1.5 * u)
	elseif kind == "bolt" then
		piece("A", 5 * u, 8 * u, 7 * u, 2 * u, 1 * u)
		piece("B", 6 * u, 7 * u, 4 * u, 8 * u, 1 * u)
		piece("C", 4 * u, 4 * u, 8 * u, 6 * u, 1 * u)
	elseif kind == "settings" then
		piece("Ring", 12 * u, 12 * u, 4 * u, 4 * u, 12 * u, .25)
		piece("Hub", 6 * u, 6 * u, 7 * u, 7 * u, 6 * u)
		for i = 0, 3 do
			local a = i * math.pi / 2
			piece("Tooth", 3 * u, 5 * u, (8.5 + math.cos(a) * 7) * u, (8.5 + math.sin(a) * 7) * u, 1 * u)
		end
	else
		piece("Dot", 8 * u, 8 * u, 6 * u, 6 * u, 8 * u)
	end
	return box
end

Panels.glyph = glyph

-- --------------------------------------------------------------------------- #
-- Top HUD: brand, brain-cell counter, round clock, coin counter
-- --------------------------------------------------------------------------- #
function Panels.topHud(parent, handlers)
	local root = Kit.instance("Frame", {
		Name = "TopHud",
		Size = UDim2.new(1, 0, 0, 96),
		BackgroundTransparency = 1,
	}, parent)

	-- brand lockup
	local brand = Kit.instance("Frame", {
		Name = "Brand",
		Size = UDim2.fromOffset(196, 58),
		Position = UDim2.fromOffset(Space.xl, Space.lg),
		BackgroundTransparency = 1,
	}, root)
	Kit.text(brand, "Wordmark", Copy.BrandTop, "Title", {
		size = UDim2.fromOffset(196, 26), color = C.White, zIndex = 3,
	})
	local bar = Kit.instance("Frame", {
		Name = "AccentBar", Size = UDim2.fromOffset(34, 3),
		Position = UDim2.fromOffset(1, 27), BackgroundColor3 = C.Cyan, BorderSizePixel = 0,
	}, brand)
	Kit.corner(bar, 2)
	Kit.text(brand, "Arena", Copy.BrandBottom, "Label", {
		size = UDim2.fromOffset(196, 16), position = UDim2.fromOffset(1, 32), color = C.Violet,
	})
	-- The tagline is inside the brand frame, so hiding the lockup hides all of it.
	local tagline = Kit.text(brand, "Tagline", Copy.BrandTag, "Micro", {
		size = UDim2.fromOffset(196, 12), position = UDim2.fromOffset(2, 47), color = C.Dim,
	})

	-- brain-cell counter (left, under the brand)
	local cells = Kit.panel(root, "CellCounter", UDim2.fromOffset(196, 52), UDim2.fromOffset(Space.xl, 78), {
		zIndex = 2,
	})
	glyph(cells, "cell", C.Cyan, 22).Position = UDim2.fromOffset(Space.md, Space.md + 2)
	local cellValue = Kit.text(cells, "Value", "0", "Title", {
		size = UDim2.fromOffset(64, 26), position = UDim2.fromOffset(40, 6), color = C.White, zIndex = 3,
	})
	Kit.text(cells, "Caption", Copy.CellsLabel, "Micro", {
		size = UDim2.fromOffset(120, 12), position = UDim2.fromOffset(41, 31), color = C.Muted,
	})
	local cellScale = Kit.instance("UIScale", { Scale = 1 }, cells)

	-- round clock (centre, top)
	local clock = Kit.panel(root, "RoundClock", UDim2.fromOffset(212, 76), UDim2.new(.5, 0, 0, Space.lg), {
		anchor = Vector2.new(.5, 0), zIndex = 2, color = C.NavyRaised,
	})
	local phase = Kit.text(clock, "Phase", Copy.WaitingStatus, "Label", {
		size = UDim2.new(1, -20, 0, 14), position = UDim2.fromOffset(10, 7),
		color = C.Cyan, xAlign = Enum.TextXAlignment.Center, zIndex = 3,
	})
	local time = Kit.text(clock, "Countdown", "--:--", "Display", {
		size = UDim2.new(1, -20, 0, 40), position = UDim2.fromOffset(10, 19),
		color = C.White, xAlign = Enum.TextXAlignment.Center, zIndex = 3,
	})
	local clockDivider = Kit.divider(clock, 60, 30)
	local roundLabel = Kit.text(clock, "RoundNo", "AUTO JOIN • EVERY ROUND", "Micro", {
		size = UDim2.new(1, -20, 0, 12), position = UDim2.fromOffset(10, 63),
		color = C.Dim, xAlign = Enum.TextXAlignment.Center, zIndex = 3, truncate = true,
	})

	-- coin counter (right)
	local coins = Kit.panel(root, "CoinCounter", UDim2.fromOffset(152, 52), UDim2.new(1, -Space.xl, 0, Space.lg), {
		anchor = Vector2.new(1, 0), zIndex = 2,
	})
	glyph(coins, "coin", C.Amber, 22).Position = UDim2.fromOffset(Space.md, Space.md + 2)
	local coinValue = Kit.text(coins, "Value", "0", "Title", {
		size = UDim2.fromOffset(96, 26), position = UDim2.fromOffset(40, 6), color = C.Amber, zIndex = 3,
	})
	Kit.text(coins, "Caption", Copy.CoinsLabel, "Micro", {
		size = UDim2.fromOffset(100, 12), position = UDim2.fromOffset(41, 31), color = C.Muted,
	})
	local coinScale = Kit.instance("UIScale", { Scale = 1 }, coins)

	-- Collection progress chip: always-on reminder that there are six specimens,
	-- with a live count of how many this player has logged. Clicking opens the log.
	-- Right-anchored like the coin chip above it: without this the offset was read
	-- from the left edge and the chip hung off the right of every viewport.
	local specimens = Kit.button(root, "Specimens", "", UDim2.fromOffset(152, 34),
		UDim2.new(1, -Space.xl, 0, Space.lg + 60), function()
			if handlers and handlers.Specimens then handlers.Specimens() end
		end, { accent = C.Cyan, zIndex = 2, radius = 10, variant = "Micro",
			anchor = Vector2.new(1, 0) })
	specimens.Label.Size = UDim2.new(1, -12, 1, 0)
	specimens.Label.TextXAlignment = Enum.TextXAlignment.Center
	local specimenText = specimens.Label

	return {
		root = root,
		specimens = specimens,
		specimenText = specimenText,
		brand = brand,
		brandTag = tagline,
		cells = cells,
		cellValue = cellValue,
		cellScale = cellScale,
		clock = clock,
		phase = phase,
		time = time,
		roundLabel = roundLabel,
		divider = clockDivider,
		coins = coins,
		coinValue = coinValue,
		coinScale = coinScale,
	}
end

-- --------------------------------------------------------------------------- #
-- Right-hand leaderboard
-- --------------------------------------------------------------------------- #
function Panels.leaderboard(parent)
	local board = Kit.panel(parent, "Leaderboard", UDim2.fromOffset(232, 292), UDim2.new(1, -Space.lg, 0, 162), {
		anchor = Vector2.new(1, 0), zIndex = 2,
	})
	local title = Kit.text(board, "Heading", Copy.BoardTitle, "Heading", {
		size = UDim2.new(1, -24, 0, 18), position = UDim2.fromOffset(Space.md, Space.md), color = C.White,
	})
	local sub = Kit.text(board, "Subheading", Copy.BoardSub, "Micro", {
		size = UDim2.new(1, -24, 0, 12), position = UDim2.fromOffset(Space.md, Space.md + 19), color = C.Dim,
	})
	Kit.divider(board, Space.md + 35, Space.md)
	local roster = Kit.instance("ScrollingFrame", {
		Name = "Players",
		Position = UDim2.fromOffset(Space.md - 2, Space.md + 42),
		Size = UDim2.new(1, -Space.md * 2, 1, -(Space.md + 52)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = C.NavyEdge,
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 2,
	}, board)
	Kit.instance("UIListLayout", {
		Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder,
	}, roster)
	return { board = board, title = title, sub = sub, roster = roster, rows = {} }
end

function Panels.row(roster, id, order)
	local frame = Kit.instance("Frame", {
		Name = "Player_" .. tostring(id),
		Size = UDim2.new(1, -4, 0, 30),
		BackgroundColor3 = C.NavyRaised,
		BackgroundTransparency = .35,
		BorderSizePixel = 0,
		LayoutOrder = order,
		ZIndex = 3,
	}, roster)
	Kit.corner(frame, 9)
	local accent = Kit.instance("Frame", {
		Name = "Accent", Size = UDim2.fromOffset(3, 18), Position = UDim2.fromOffset(0, 6),
		BackgroundColor3 = C.Cyan, BackgroundTransparency = .4, BorderSizePixel = 0, ZIndex = 4,
	}, frame)
	Kit.corner(accent, 2)
	local rank = Kit.text(frame, "Rank", "", "Micro", {
		size = UDim2.fromOffset(24, 30), position = UDim2.fromOffset(8, 0), color = C.Muted, zIndex = 4,
	})
	local name = Kit.text(frame, "Player", "", "Label", {
		size = UDim2.new(1, -96, 1, 0), position = UDim2.fromOffset(32, 0), color = C.White,
		zIndex = 4, truncate = true,
	})
	name.Font = Enum.Font.GothamMedium
	name.TextSize = Type.Label
	local score = Kit.text(frame, "Cells", "", "Body", {
		size = UDim2.fromOffset(46, 30), position = UDim2.new(1, -52, 0, 0), color = C.Cyan,
		zIndex = 4, xAlign = Enum.TextXAlignment.Right,
	})
	score.Font = Enum.Font.GothamBold
	return { frame = frame, accent = accent, rank = rank, name = name, score = score }
end

-- --------------------------------------------------------------------------- #
-- Bottom action bar: shop / inventory / settings, all wired to real panels
-- --------------------------------------------------------------------------- #
function Panels.actionBar(parent, handlers)
	local bar = Kit.instance("Frame", {
		Name = "ActionBar",
		Size = UDim2.fromOffset(268, 52),
		Position = UDim2.new(.5, 0, 1, -Space.lg - 52),
		AnchorPoint = Vector2.new(.5, 0),
		BackgroundTransparency = 1,
	}, parent)
	local buttons = {}
	-- Bar captions are short forms; the modal titles carry the full name.
	local entries = {
		{ "Shop", "shop", Copy.ShopBar, C.Amber },
		{ "Inventory", "inventory", Copy.InventoryBar, C.Cyan },
		{ "Settings", "settings", Copy.SettingsBar, C.Violet },
	}
	for index, entry in entries do
		local name, kind, label, accent = entry[1], entry[2], entry[3], entry[4]
		local slot = Kit.button(bar, name, "", UDim2.fromOffset(84, 52),
			UDim2.fromOffset((index - 1) * 92, 0), function()
				handlers[name]()
			end, { accent = accent, zIndex = 4 })
		slot.Label.Text = ""
		glyph(slot, kind, accent, 20).Position = UDim2.fromOffset(32, 10)
		Kit.text(slot, "Caption", label, "Micro", {
			size = UDim2.new(1, 0, 0, 12), position = UDim2.fromOffset(0, 32),
			color = C.Muted, xAlign = Enum.TextXAlignment.Center, zIndex = 5,
		})
		-- tooltip-free: the caption is the label, the glyph is the icon
		buttons[name] = slot
	end
	return { bar = bar, buttons = buttons }
end

-- --------------------------------------------------------------------------- #
-- Steal action: a big tag button with a live cooldown, plus the carried/banked
-- readout that explains what is at risk.
-- --------------------------------------------------------------------------- #
function Panels.stealPanel(parent, onSteal)
	local root = Kit.instance("Frame", {
		Name = "StealPanel",
		Size = UDim2.fromOffset(186, 52),
		Position = UDim2.new(1, -Space.lg, 1, -Space.lg - 52),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, parent)

	local button = Kit.button(root, "Steal", "", UDim2.fromOffset(186, 52), UDim2.fromOffset(0, 0),
		function() onSteal() end, { accent = C.Danger, zIndex = 4, color = C.NavyRaised })
	glyph(button, "hook", C.Danger, 22).Position = UDim2.fromOffset(14, 15)
	local label = Kit.text(button, "State", Copy.StealReady, "Heading", {
		size = UDim2.new(1, -46, 0, 20), position = UDim2.fromOffset(42, 7),
		color = C.White, zIndex = 5, truncate = true,
	})
	local caption = Kit.text(button, "Caption", "8s COOLDOWN", "Micro", {
		size = UDim2.new(1, -46, 0, 12), position = UDim2.fromOffset(42, 28),
		color = C.Muted, zIndex = 5, truncate = true,
	})
	-- Cooldown veil: covers the button from the left, so "how much longer" reads
	-- at a glance without a second number.
	local veil = Kit.instance("Frame", {
		Name = "Cooldown",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.Void,
		BackgroundTransparency = .45,
		BorderSizePixel = 0,
		ZIndex = 6,
	}, button)
	Kit.corner(veil, 12)

	-- Carried / banked readout stacked above the button. It is a child of the panel,
	-- so it follows the panel wherever the HUD anchors it (right on desktop and
	-- portrait, left on short landscape).
	local readout = Kit.panel(root, "Carried", UDim2.fromOffset(186, 30), UDim2.fromOffset(0, -38), {
		zIndex = 4, radius = 10, color = C.NavyRaised,
	})
	glyph(readout, "cell", C.Cyan, 14).Position = UDim2.fromOffset(Space.sm, Space.sm)
	local carried = Kit.text(readout, "Carried", "0", "Label", {
		size = UDim2.fromOffset(60, 14), position = UDim2.fromOffset(26, 2),
		color = C.Amber, zIndex = 5,
	})
	local banked = Kit.text(readout, "Banked", "0", "Micro", {
		size = UDim2.fromOffset(96, 12), position = UDim2.fromOffset(26, 15),
		color = C.Muted, zIndex = 5, truncate = true,
	})

	return {
		root = root, button = button, label = label, caption = caption,
		veil = veil, readout = readout, carried = carried, banked = banked,
	}
end

-- --------------------------------------------------------------------------- #
-- Centre toast + event banner + lobby banner
-- --------------------------------------------------------------------------- #
-- The ability button. Q on a keyboard, or this button on a touch screen. The cooldown
-- veil drains left to right, the same way the steal veil does.
function Panels.abilityPanel(parent, onUse)
	local root = Kit.instance("Frame", {
		Name = "AbilityPanel",
		Size = UDim2.fromOffset(150, 52),
		Position = UDim2.new(1, -Space.lg, 1, -Space.lg - 52),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, parent)
	local button = Kit.button(root, "AbilityButton", "", UDim2.fromOffset(150, 52), UDim2.fromOffset(0, 0),
		function() onUse() end, { accent = C.Violet, zIndex = 4, color = C.NavyRaised })
	glyph(button, "bolt", C.Violet, 20).Position = UDim2.fromOffset(12, 16)
	local label = Kit.text(button, "Title", "ABILITY", "Heading", {
		size = UDim2.new(1, -44, 0, 20), position = UDim2.fromOffset(38, 7),
		color = C.White, zIndex = 5, truncate = true,
	})
	local caption = Kit.text(button, "Caption", "Q • READY", "Micro", {
		size = UDim2.new(1, -44, 0, 12), position = UDim2.fromOffset(38, 28),
		color = C.Muted, zIndex = 5, truncate = true,
	})
	local veil = Kit.instance("Frame", {
		Name = "Cooldown",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.Void,
		BackgroundTransparency = .45,
		BorderSizePixel = 0,
		ZIndex = 6,
	}, button)
	Kit.corner(veil, 12)
	return { root = root, button = button, label = label, caption = caption, veil = veil }
end

-- Six numbered chips, one per character in slot order, with the active one lit. Keys 1-6
-- or a tap both switch. The readout names the active character and the switches left.
function Panels.characterStrip(parent, onPick, count)
	local root = Kit.instance("Frame", {
		Name = "CharacterStrip",
		Size = UDim2.fromOffset(6 * 32 + 5 * 4, 46),
		Position = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, parent)
	local readout = Kit.text(root, "Readout", "", "Micro", {
		size = UDim2.new(1, 0, 0, 14), position = UDim2.fromOffset(0, 0),
		color = C.Muted, zIndex = 5, truncate = true,
	})
	local chips = {}
	for slot = 1, count do
		local chip = Kit.button(root, "Slot" .. slot, tostring(slot), UDim2.fromOffset(32, 28),
			UDim2.fromOffset((slot - 1) * 36, 18), function() onPick(slot) end,
			{ accent = C.Cyan, zIndex = 5, color = C.NavyRaised })
		chip.Label.TextSize = Type.Label
		chips[slot] = chip
	end
	return { root = root, readout = readout, chips = chips }
end

function Panels.toast(parent)
	local toast = Kit.panel(parent, "Toast", UDim2.fromOffset(432, 56), UDim2.new(.5, 0, 0, 112), {
		anchor = Vector2.new(.5, 0), zIndex = 6, visible = false,
	})
	local accent = Kit.instance("Frame", {
		Name = "Accent", Size = UDim2.fromOffset(4, 36), Position = UDim2.fromOffset(Space.md, 10),
		BackgroundColor3 = C.Cyan, BorderSizePixel = 0, ZIndex = 7,
	}, toast)
	Kit.corner(accent, 2)
	local label = Kit.text(toast, "Message", "", "Body", {
		size = UDim2.new(1, -52, 1, -8), position = UDim2.fromOffset(32, 4),
		color = C.White, zIndex = 7, wrapped = true,
	})
	label.Font = Enum.Font.GothamBold
	return { frame = toast, label = label, accent = accent }
end

function Panels.eventBanner(parent)
	local banner = Kit.panel(parent, "EventBanner", UDim2.fromOffset(320, 34), UDim2.new(.5, 0, 0, 174), {
		anchor = Vector2.new(.5, 0), zIndex = 5, visible = false, color = C.NavyRaised,
	})
	local dot = Kit.instance("Frame", {
		Name = "Pulse", Size = UDim2.fromOffset(8, 8), Position = UDim2.fromOffset(Space.md, 13),
		BackgroundColor3 = C.Cyan, BorderSizePixel = 0, ZIndex = 6,
	}, banner)
	Kit.corner(dot, 8)
	local label = Kit.text(banner, "Label", "", "Label", {
		size = UDim2.new(1, -40, 1, 0), position = UDim2.fromOffset(30, 0),
		color = C.Cyan, zIndex = 6,
	})
	return { frame = banner, label = label, dot = dot }
end

-- Lobby banner: welcome, next-round countdown and an explicit arena status line.
function Panels.lobbyBanner(parent)
	local banner = Kit.panel(parent, "LobbyBanner", UDim2.fromOffset(420, 92), UDim2.new(.5, 0, 0, 236), {
		anchor = Vector2.new(.5, 0), zIndex = 4,
	})
	Kit.text(banner, "Title", Copy.LobbyWelcome, "Heading", {
		size = UDim2.new(1, -32, 0, 20), position = UDim2.fromOffset(Space.lg, Space.md), color = C.White,
		xAlign = Enum.TextXAlignment.Center,
	})
	local sub = Kit.text(banner, "Sub", Copy.LobbySub, "Micro", {
		size = UDim2.new(1, -32, 0, 14), position = UDim2.fromOffset(Space.lg, Space.md + 21),
		color = C.Muted, xAlign = Enum.TextXAlignment.Center,
	})
	local status = Kit.text(banner, "Status", Copy.WaitingStatus, "Label", {
		size = UDim2.new(1, -32, 0, 16), position = UDim2.fromOffset(Space.lg, Space.md + 44),
		color = C.Cyan, xAlign = Enum.TextXAlignment.Center,
	})
	local countdown = Kit.text(banner, "Countdown", "", "Micro", {
		size = UDim2.new(1, -32, 0, 14), position = UDim2.fromOffset(Space.lg, Space.md + 64),
		color = C.Dim, xAlign = Enum.TextXAlignment.Center,
	})
	return { frame = banner, title = banner.Title, sub = sub, status = status, countdown = countdown }
end

return Panels
