--!strict
-- ReplicatedStorage > Shared > UI > MenuAnimator
--
-- Open / close choreography, and the shared focus dim behind whichever menu is
-- open.
--
-- Opening is two tweens, not one. A single Back-eased tween overshoots on the
-- way in AND undershoots on the way out, which reads as a wobble. Rising to
-- 1.015 and then settling to 1.000 gives the weight without the bounce.
--
--   0.00s  scale 0.940, panel transparent
--   0.13s  scale 1.015
--   0.26s  scale 1.000, settled
--
-- The header leads the content by a few frames so the menu assembles itself
-- rather than appearing all at once.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UITheme = require(ReplicatedStorage.Shared.UI.UITheme)

local MenuAnimator = {}

local M = UITheme.Motion

local RISE   = TweenInfo.new(M.OpenRise, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local SETTLE = TweenInfo.new(M.OpenSettle, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SHUT   = TweenInfo.new(M.Close, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

-- ── FOCUS DIM ─────────────────────────────────────────────
local dimFrame: Frame? = nil

-- The dim is created once and reused. It sits UNDER the menu windows but over
-- the HUD, and it is not a button - clicks pass through to whatever is beneath,
-- so it can never swallow input meant for the world or the sidebar.
function MenuAnimator.EnsureDim(parent: Instance, zIndex: number): Frame
	if dimFrame and dimFrame.Parent then
		return dimFrame
	end

	local frame = Instance.new("Frame")
	frame.Name = "MenuFocusDim"
	frame.Size = UDim2.fromScale(1, 1)
	frame.Position = UDim2.fromScale(0, 0)
	frame.BackgroundColor3 = UITheme.DimColor
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Active = false
	frame.ZIndex = zIndex
	frame.Parent = parent

	dimFrame = frame
	return frame
end

function MenuAnimator.ShowDim()
	local frame = dimFrame
	if not frame then return end
	frame.Visible = true
	TweenService:Create(
		frame,
		TweenInfo.new(UITheme.DimTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = UITheme.DimTransparency }
	):Play()
end

function MenuAnimator.HideDim()
	local frame = dimFrame
	if not frame then return end
	local tween = TweenService:Create(
		frame,
		TweenInfo.new(UITheme.DimTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1 }
	)
	tween:Play()
	tween.Completed:Once(function()
		if frame.BackgroundTransparency >= 0.99 then
			frame.Visible = false
		end
	end)
end

-- ── WINDOW ───────────────────────────────────────────────
-- refs must carry: Anchor, Window, Scale, HeaderHolder, HeaderAura, Header,
-- Title, Content. HeaderHome is the header's resting Position, captured by the
-- caller at build time so the slide-in always starts from the same offset.

function MenuAnimator.Reset(refs)
	refs.Anchor.Visible = false
	refs.Window.GroupTransparency = 1
	refs.Scale.Scale = M.OpenStart
	refs.HeaderAura.GroupTransparency = 1
	refs.Header.ImageTransparency = 1
	refs.Title.TextTransparency = 1
	refs.Title.TextStrokeTransparency = 1
	if refs.Content then
		refs.Content.GroupTransparency = 1
	end
	if refs.HeaderHome then
		refs.HeaderHolder.Position = refs.HeaderHome
	end
end

function MenuAnimator.Open(refs)
	MenuAnimator.Reset(refs)
	refs.Anchor.Visible = true

	-- Header starts slightly left of home and slides in.
	local home = refs.HeaderHome or refs.HeaderHolder.Position
	refs.HeaderHolder.Position = home - UDim2.fromOffset(M.HeaderSlide, 0)

	TweenService:Create(refs.Window, RISE, { GroupTransparency = 0 }):Play()

	-- Rise past the resting size, then settle back onto it.
	local rise = TweenService:Create(refs.Scale, RISE, { Scale = M.OpenPeak })
	rise:Play()
	rise.Completed:Once(function()
		TweenService:Create(refs.Scale, SETTLE, { Scale = 1 }):Play()
	end)

	task.delay(M.HeaderDelay, function()
		if not refs.Anchor.Visible then return end
		TweenService:Create(
			refs.HeaderHolder,
			TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Position = home }
		):Play()
		TweenService:Create(refs.HeaderAura, RISE, { GroupTransparency = 0 }):Play()
		TweenService:Create(refs.Header, RISE, { ImageTransparency = 0 }):Play()
		TweenService:Create(refs.Title, RISE, {
			TextTransparency = 0,
			TextStrokeTransparency = 0.10,
		}):Play()
	end)

	if refs.Content then
		task.delay(M.ContentDelay, function()
			if not refs.Anchor.Visible then return end
			TweenService:Create(
				refs.Content,
				TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ GroupTransparency = 0 }
			):Play()
		end)
	end
end

-- Returns the delay after which the caller should hide the anchor. The caller
-- owns that so it can guard with its own token and avoid hiding a window that
-- was reopened during the fade.
function MenuAnimator.Close(refs): number
	TweenService:Create(refs.Window, SHUT, { GroupTransparency = 1 }):Play()
	TweenService:Create(refs.Scale, SHUT, { Scale = M.CloseEnd }):Play()
	TweenService:Create(refs.HeaderAura, SHUT, { GroupTransparency = 1 }):Play()
	TweenService:Create(refs.Header, SHUT, { ImageTransparency = 1 }):Play()
	TweenService:Create(refs.Title, SHUT, {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	if refs.Content then
		TweenService:Create(refs.Content, SHUT, { GroupTransparency = 1 }):Play()
	end
	return M.Close + 0.03
end

return MenuAnimator
