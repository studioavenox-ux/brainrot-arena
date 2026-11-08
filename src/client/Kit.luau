--!nonstrict
-- UI kit: the only place that constructs HUD primitives.
--
-- Every panel in the interface comes from `Kit.panel`, `Kit.button`, `Kit.text`
-- and friends, so the design system in `Theme` (generated from tools/ui.py) is
-- actually enforced instead of being a suggestion. No images, no asset ids, no
-- uploaded fonts: corners, strokes, gradients and glyph frames only.
--
-- Everything here is presentation. It reads no gameplay state and writes none.
local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.Theme)

local Kit = {}

local C = Theme.Colors
local Alpha = Theme.Alpha
local Type = Theme.Type
local Space = Theme.Space
local Motion = Theme.Motion
local Fonts = Theme.Fonts

Kit.Colors = C
Kit.Theme = Theme

-- --------------------------------------------------------------------------- #
-- primitives
-- --------------------------------------------------------------------------- #

-- Kinds that never take input. Screenshot-only framing or decoration, so a click
-- passes through to whatever is underneath.
local PASSIVE = {
	Frame = true,
	TextLabel = true,
	ImageLabel = true,
}

function Kit.instance(className, properties, parent)
	local object = Instance.new(className)
	if PASSIVE[className] then
		object.Active = false
		object.Interactable = false
	end
	for key, value in properties do
		object[key] = value
	end
	if parent then
		object.Parent = parent
	end
	return object
end

function Kit.corner(parent, radius)
	return Kit.instance("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Radius) }, parent)
end

function Kit.stroke(parent, color, transparency, thickness)
	return Kit.instance("UIStroke", {
		Color = color or C.NavyEdge,
		Thickness = thickness or 1,
		Transparency = transparency or Alpha.Hairline,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

function Kit.padding(parent, left, top, right, bottom)
	return Kit.instance("UIPadding", {
		PaddingLeft = UDim.new(0, left or Space.md),
		PaddingTop = UDim.new(0, top or Space.md),
		PaddingRight = UDim.new(0, right or left or Space.md),
		PaddingBottom = UDim.new(0, bottom or top or Space.md),
	}, parent)
end

-- Vertical gradient. Degrades to a flat fill if the client cannot build one.
function Kit.gradient(parent, top, bottom, rotation)
	if type(ColorSequence) ~= "table" or not ColorSequence.new then
		return nil
	end
	return Kit.instance("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = rotation or 90,
	}, parent)
end

-- A panel: navy, translucent, rounded, hairline edge, gentle top-light gradient.
function Kit.panel(parent, name, size, position, options)
	local o = options or {}
	local frame = Kit.instance("Frame", {
		Name = name,
		Size = size,
		Position = position,
		AnchorPoint = o.anchor or Vector2.zero,
		BackgroundColor3 = o.color or C.Navy,
		BackgroundTransparency = o.transparency or Alpha.Panel,
		BorderSizePixel = 0,
		ClipsDescendants = o.clip == true,
		Visible = if o.visible == nil then true else o.visible,
		ZIndex = o.zIndex or 1,
	}, parent)
	Kit.corner(frame, o.radius or Theme.Radius)
	Kit.stroke(frame, o.edge or C.NavyEdge, o.edgeTransparency or Alpha.Hairline)
	Kit.gradient(frame, (o.color or C.NavyRaised), (o.color or C.Navy))
	if o.padding then
		Kit.padding(frame, o.padding, o.padding, o.padding, o.padding)
	end
	return frame
end

-- A legibility scrim: a soft navy gradient that darkens the edge of the screen so
-- translucent panels always sit on a controlled background, even against a bright
-- sky. Degrades to nothing if NumberSequence is unavailable.
function Kit.scrim(parent, height, fromTop, options)
	local o = options or {}
	local frame = Kit.instance("Frame", {
		Name = o.name or (if fromTop then "ScrimTop" else "ScrimBottom"),
		Size = UDim2.new(1, 0, 0, height),
		Position = if fromTop then UDim2.fromOffset(0, 0) else UDim2.new(0, 0, 1, -height),
		BackgroundColor3 = o.color or C.Void,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = o.zIndex or 0,
	}, parent)
	if type(NumberSequence) ~= "table" or not NumberSequence.new then
		frame.BackgroundTransparency = o.fallback or .55
		return frame
	end
	-- Near the edge the wash is strong enough that `Muted` body text clears 4.5:1
	-- against it; it fades out before it reaches the play space.
	local strength = o.strength or .8
	local stops = if fromTop
		then { NumberSequenceKeypoint.new(0, 1 - strength), NumberSequenceKeypoint.new(.5, 1 - strength * .45), NumberSequenceKeypoint.new(1, 1) }
		else { NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(.5, 1 - strength * .45), NumberSequenceKeypoint.new(1, 1 - strength) }
	Kit.instance("UIGradient", {
		Color = ColorSequence.new(C.Void, C.Void),
		Transparency = NumberSequence.new(stops),
		Rotation = 90,
	}, frame)
	return frame
end

-- Text. `variant` picks the type scale + font pairing; never inline ad-hoc sizes.
function Kit.text(parent, name, content, variant, options)
	local o = options or {}
	local size = o.size or UDim2.new(1, 0, 0, Type[variant or "Body"] + 4)
	local label = Kit.instance("TextLabel", {
		Name = name,
		Text = content,
		Size = size,
		Position = o.position or UDim2.fromOffset(0, 0),
		AnchorPoint = o.anchor or Vector2.zero,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		TextColor3 = o.color or C.White,
		TextSize = Type[variant or "Body"],
		Font = o.font or Fonts[variant or "Body"],
		TextXAlignment = o.xAlign or Enum.TextXAlignment.Left,
		TextYAlignment = o.yAlign or Enum.TextYAlignment.Center,
		TextWrapped = o.wrapped == true,
		RichText = false,
		TextTransparency = o.transparency or 0,
		TextStrokeTransparency = if o.stroke then 0.55 else 1,
		LayoutOrder = o.order or 0,
		ZIndex = o.zIndex or 2,
	}, parent)
	if o.truncate then
		label.TextTruncate = Enum.TextTruncate.AtEnd
	end
	return label
end

function Kit.divider(parent, y, inset)
	return Kit.instance("Frame", {
		Name = "Divider",
		Size = UDim2.new(1, -(inset or Space.lg) * 2, 0, 1),
		Position = UDim2.new(0, inset or Space.lg, 0, y),
		BackgroundColor3 = C.NavyEdge,
		BackgroundTransparency = Alpha.Hairline,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, parent)
end

-- A button that always does something: the caller must pass a handler, and the
-- handler is wired here. There is no such thing as a decorative button in this UI.
function Kit.button(parent, name, label, size, position, onClick, options)
	local o = options or {}
	local button = Kit.instance("TextButton", {
		Name = name,
		Text = "",
		Size = size,
		Position = position,
		AnchorPoint = o.anchor or Vector2.zero,
		BackgroundColor3 = o.color or C.NavyRaised,
		BackgroundTransparency = o.transparency or Alpha.PanelRaised,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		TextColor3 = C.White,
		ZIndex = o.zIndex or 3,
	}, parent)
	assert(type(onClick) == "function", "every button must be wired to a handler: " .. name)
	Kit.corner(button, o.radius or 12)
	Kit.stroke(button, o.edge or C.NavyEdge, Alpha.Hairline)
	Kit.gradient(button, (o.color or C.NavyRaised), C.Navy)
	local text = Kit.text(button, "Label", label, o.variant or "Label", {
		size = UDim2.fromScale(1, 1),
		color = o.textColor or C.White,
		xAlign = Enum.TextXAlignment.Center,
		zIndex = (o.zIndex or 3) + 1,
	})
	local accent = Kit.instance("Frame", {
		Name = "Accent",
		Size = UDim2.new(0, o.accentWidth or 3, 1, -10),
		Position = UDim2.new(0, 0, 0, 5),
		BackgroundColor3 = o.accent or C.Cyan,
		BorderSizePixel = 0,
		ZIndex = (o.zIndex or 3) + 1,
	}, button)
	Kit.corner(accent, 2)

	local scale = Kit.instance("UIScale", { Scale = 1 }, button)
	local hovered = false
	local function tween(property, value, duration)
		if o.reducedMotion and o.reducedMotion() then
			scale.Scale = value
			return
		end
		TweenService:Create(scale, TweenInfo.new(duration or Motion.Fast), { Scale = value }):Play()
	end
	button.MouseEnter:Connect(function()
		hovered = true
		tween("Scale", 1.03, Motion.Fast)
		text.TextColor3 = o.textColor or C.White
		accent.BackgroundColor3 = o.accent or C.Cyan
		button.BackgroundColor3 = o.hoverColor or C.NavyRaised
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		tween("Scale", 1, Motion.Fast)
		button.BackgroundColor3 = o.color or C.NavyRaised
	end)
	button.Activated:Connect(function()
		if o.reducedMotion and o.reducedMotion() then
			onClick()
			return
		end
		tween("Scale", .96, Motion.Snap)
		task.delay(Motion.Snap, function()
			tween("Scale", 1, Motion.Fast)
		end)
		onClick()
	end)
	button.__hovered = function()
		return hovered
	end
	return button, text
end

-- Tween that respects reduced motion by snapping.
function Kit.animate(instance, properties, duration, style, reducedMotion)
	if reducedMotion then
		for key, value in properties do
			instance[key] = value
		end
		return nil
	end
	local tween = TweenService:Create(instance, TweenInfo.new(
		duration or Motion.Base,
		style or Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), properties)
	tween:Play()
	return tween
end

-- Fade + rise a panel in. Used for toasts, cards and the lobby banner.
function Kit.enter(frame, options)
	local o = options or {}
	local target = frame.Position
	frame.Position = UDim2.new(
		target.X.Scale,
		target.X.Offset,
		target.Y.Scale,
		target.Y.Offset + (o.rise or 12)
	)
	frame.Visible = true
	if o.reducedMotion then
		frame.Position = target
		return
	end
	local info = TweenInfo.new(o.duration or Motion.Base, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(frame, info, { Position = target }):Play()
end

return Kit
