--!strict
-- The travelling highlight - light catching glass.
--
-- The HUD nav buttons and the roll bar have swept since they were built, using
-- a tween per button. This module is that same effect extracted so cards and
-- items can wear it too, and it is a MODULE rather than a copied block for one
-- reason: every sweep in the game has to be on the same clock.
--
-- A tween starts when it is created. Nav buttons are built at login, a card
-- grid is built when the player opens the Deck, and a Backpack tile when they
-- open the bag - so three sets of identical tweens would run at three
-- different phases and the screen would read as separate things blinking
-- rather than one surface being lit. Driving every highlight from one shared
-- clock instead means a sweep that appears mid-session arrives already in step
-- with everything else on screen.
--
-- WHY NOT ROTATED
-- A rotated GuiObject ignores its parent's ClipsDescendants, so a tilted sweep
-- escapes its tile and streaks across the whole screen. The slant lives in the
-- source image; nothing here is ever rotated.

local RunService = game:GetService("RunService")

local Sweep = {}

Sweep.Image = "rbxassetid://135060446578504"

-- Verbatim from the nav column's TweenInfo(1.9, Sine, InOut, -1, false, 4.2).
-- Anything that sweeps on a different cadence reads as a second, competing
-- animation instead of the same light.
local TRAVEL = 1.9    -- seconds crossing the face
local REST = 4.2      -- seconds dark between passes
local PERIOD = TRAVEL + REST

-- Off the left edge to off the right edge. The parent crops both ends, so the
-- highlight fades in and out at the borders instead of popping.
local START_X = -0.4
local PARK_X = 1.4

local labels: { ImageLabel } = {}
local connection: RBXScriptConnection? = nil
local epoch = os.clock()
local parked = false

-- One pass over every highlight in the game. Cheap enough that a grid of a
-- hundred card tiles costs a hundred Position writes on the frames it is
-- actually moving, and nothing at all for the ~4 seconds it is resting.
local function step()
	local t = (os.clock() - epoch) % PERIOD
	local resting = t > TRAVEL

	-- Nothing to do while the light is off-screen, but the list still has to be
	-- swept for destroyed tiles or it would grow for the whole session.
	if resting and parked then
		for i = #labels, 1, -1 do
			if not labels[i].Parent then table.remove(labels, i) end
		end
	else
		local x
		if resting then
			x = PARK_X
		else
			-- Sine InOut by hand: the same ease TweenService gives the buttons.
			local alpha = (1 - math.cos(math.pi * (t / TRAVEL))) / 2
			x = START_X + (PARK_X - START_X) * alpha
		end
		local position = UDim2.new(x, 0, 0.5, 0)
		for i = #labels, 1, -1 do
			local label = labels[i]
			if label.Parent then
				label.Position = position
			else
				table.remove(labels, i)
			end
		end
		parked = resting
	end

	if #labels == 0 and connection then
		connection:Disconnect()
		connection = nil
	end
end

-- Adds the highlight to `frame` and returns the labels it made.
--
-- opts:
--   layers        how many stacked copies. Blur is faked by stacking: one copy
--                 is a hard-edged band, three at increasing width and
--                 transparency read as a soft one. Default 1.
--   width         band width as a fraction of the face. Default 0.5.
--   transparency  0.78 is the HUD's. Higher is fainter.
--   tint          ImageColor3, for a sweep that should carry a rarity's colour.
--   zIndex        defaults to just above the frame.
function Sweep.attach(frame: GuiObject, opts: any?): { ImageLabel }
	local made: { ImageLabel } = {}
	if not frame then return made end
	opts = opts or {}

	-- The highlight is a child that slides right across the face, so the face
	-- has to crop it. Strokes render outside the element and ignore clipping,
	-- so a rarity border is unaffected by this.
	frame.ClipsDescendants = true

	local layers = opts.layers or 1
	local width = opts.width or 0.5
	local transparency = opts.transparency or 0.78
	local zIndex = opts.zIndex or (frame.ZIndex + 1)

	for i = 1, layers do
		local label = Instance.new("ImageLabel")
		label.Name = "Sweep" .. i
		label.BackgroundTransparency = 1
		label.Image = Sweep.Image
		label.ImageTransparency = math.min(0.985, transparency + (i - 1) * 0.03)
		if opts.tint then label.ImageColor3 = opts.tint end
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		-- Starts parked, so a tile built mid-cycle does not flash at its own
		-- centre for one frame before the loop places it.
		label.Position = UDim2.new(PARK_X, 0, 0.5, 0)
		label.Size = UDim2.new(width * (1 + (i - 1) * 0.55), 0, opts.height or 1, 0)
		label.ScaleType = Enum.ScaleType.Stretch
		label.ZIndex = zIndex
		-- Never Active: an input-consuming child would eat the hover and click
		-- of whatever it is sweeping across.
		label.Active = false
		label.Parent = frame

		labels[#labels + 1] = label
		made[i] = label
	end

	if not connection then
		parked = false
		connection = RunService.RenderStepped:Connect(step)
	end

	return made
end

-- Removes every highlight this module put on `frame`.
--
-- Used by anything that builds a card but does not want it lit - the battle
-- board strips it here, because cards there overlap constantly and stacked
-- highlights composite into stripes rather than lighting one card. Also for a
-- frame restyled in place, which should not end up with two.
--
-- The destroyed labels prune themselves from the loop on its next pass.
function Sweep.remove(frame: GuiObject)
	if not frame then return end
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("ImageLabel") and child.Name:sub(1, 5) == "Sweep" then
			child:Destroy()
		end
	end
end

return Sweep
