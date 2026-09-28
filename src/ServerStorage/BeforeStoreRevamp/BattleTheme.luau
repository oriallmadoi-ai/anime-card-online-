--!strict
-- Visual language for the battle screen.
--
-- The old battle UI was a dozen translucent rectangles stacked on gameplay.
-- Everything here exists to build the opposite: solid, angled, lit panels that
-- read as one battlefield. The controller composes these; it does not draw
-- primitives itself, so the look can be retuned in one file.
--
-- Roblox has no polygon primitive and no arbitrary masking, so "angled" is
-- built from rotated Frames layered over a base rect. Note that a rotated
-- GuiObject ESCAPES ClipsDescendants - that is exactly why the corner cuts are
-- drawn as opaque wedges in the backdrop colour ON TOP of a panel, rather than
-- trying to clip the panel into shape.

local TweenService = game:GetService("TweenService")

local BattleTheme = {}

-- ── Palette ─────────────────────────────────────────────────────────────
BattleTheme.Colors = {
	Void        = Color3.fromRGB(6, 4, 14),      -- deepest backdrop
	Panel       = Color3.fromRGB(16, 12, 32),    -- panel body
	PanelHi     = Color3.fromRGB(31, 23, 58),    -- panel body, lit edge
	Navy        = Color3.fromRGB(11, 15, 40),

	Player      = Color3.fromRGB(150, 110, 255), -- player side accent
	PlayerDim   = Color3.fromRGB(78, 54, 148),
	Enemy       = Color3.fromRGB(255, 74, 122),  -- enemy side accent
	EnemyDim    = Color3.fromRGB(150, 34, 68),

	Gold        = Color3.fromRGB(255, 205, 90),
	Text        = Color3.fromRGB(238, 234, 255),
	TextDim     = Color3.fromRGB(168, 160, 200),
	Good        = Color3.fromRGB(120, 235, 150),
	Bad         = Color3.fromRGB(255, 96, 96),
}

-- ── Motion ──────────────────────────────────────────────────────────────
-- Named curves rather than ad-hoc TweenInfos, so hover/drag/impact feel like
-- one system instead of six people's guesses.
BattleTheme.Ease = {
	Hover   = TweenInfo.new(0.16, Enum.EasingStyle.Quad,  Enum.EasingDirection.Out),
	Snap    = TweenInfo.new(0.22, Enum.EasingStyle.Back,  Enum.EasingDirection.Out),
	Return  = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Drift   = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Pop     = TweenInfo.new(0.13, Enum.EasingStyle.Back,  Enum.EasingDirection.Out),
	Fade    = TweenInfo.new(0.20, Enum.EasingStyle.Quad,  Enum.EasingDirection.Out),
	Lunge   = TweenInfo.new(0.13, Enum.EasingStyle.Quad,  Enum.EasingDirection.In),
	Recover = TweenInfo.new(0.20, Enum.EasingStyle.Quad,  Enum.EasingDirection.Out),
}

function BattleTheme.tween(obj: Instance, info: TweenInfo, props: { [string]: any })
	local t = TweenService:Create(obj, info, props)
	t:Play()
	return t
end

-- ── Construction helper ─────────────────────────────────────────────────
function BattleTheme.new(class: string, props: { [string]: any }?, children: { Instance }?): any
	local o = Instance.new(class)
	local parent = nil
	for k, v in pairs(props or {}) do
		if k == "Parent" then
			parent = v            -- assigned LAST, so the object is fully built first
		else
			(o :: any)[k] = v
		end
	end
	for _, c in ipairs(children or {}) do
		c.Parent = o
	end
	if parent then o.Parent = parent end
	return o
end
local new = BattleTheme.new

-- ── Glow ────────────────────────────────────────────────────────────────
-- A soft outer halo. Built from nested strokes rather than a blurred image so
-- it needs no uploaded asset and can be recoloured live.
function BattleTheme.glow(frame: GuiObject, color: Color3, strength: number?)
	local s = strength or 1
	for i = 1, 3 do
		new("UIStroke", {
			Name = "Glow" .. i,
			Parent = frame,
			Color = color,
			Thickness = i * 2.2 * s,
			Transparency = 1 - (0.20 / i) * s,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		})
	end
end

function BattleTheme.setGlow(frame: GuiObject, alpha: number)
	for i = 1, 3 do
		local s = frame:FindFirstChild("Glow" .. i)
		if s and s:IsA("UIStroke") then
			BattleTheme.tween(s, BattleTheme.Ease.Hover,
				{ Transparency = 1 - (0.20 / i) * alpha })
		end
	end
end

-- ── Angled panel ────────────────────────────────────────────────────────
-- A rectangle whose corners are cut away by rotated wedges painted in the
-- backdrop colour. `cuts` names which corners to bevel: "tl","tr","bl","br".
function BattleTheme.bevel(parent: Instance, props: { [string]: any }, opts: { [string]: any }?)
	opts = opts or {}
	local size = opts.cut or 16
	local accent = opts.accent or BattleTheme.Colors.Player
	local backdrop = opts.backdrop or BattleTheme.Colors.Void
	local cuts = opts.cuts or { "tl", "br" }

	local body = new("Frame", (function()
		local p = table.clone(props)
		p.Parent = parent
		p.BackgroundColor3 = p.BackgroundColor3 or BattleTheme.Colors.Panel
		p.BorderSizePixel = 0
		return p
	end)())

	new("UIGradient", {
		Parent = body,
		Rotation = 90,
		Color = ColorSequence.new(
			opts.top or BattleTheme.Colors.PanelHi,
			opts.bottom or BattleTheme.Colors.Panel
		),
	})

	local stroke = new("UIStroke", {
		Name = "Edge",
		Parent = body,
		Color = accent,
		Thickness = opts.thickness or 1.8,
		Transparency = 0.15,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})

	-- The wedges. Each is a square rotated 45 degrees, parked so that exactly
	-- one of its corners overlaps the panel corner it is erasing.
	local anchors = {
		tl = { UDim2.fromScale(0, 0), Vector2.new(0.5, 0.5) },
		tr = { UDim2.fromScale(1, 0), Vector2.new(0.5, 0.5) },
		bl = { UDim2.fromScale(0, 1), Vector2.new(0.5, 0.5) },
		br = { UDim2.fromScale(1, 1), Vector2.new(0.5, 0.5) },
	}
	for _, corner in ipairs(cuts) do
		local a = anchors[corner]
		if a then
			new("Frame", {
				Name = "Cut_" .. corner,
				Parent = body,
				AnchorPoint = a[2],
				Position = a[1],
				Size = UDim2.fromOffset(size, size),
				Rotation = 45,
				BackgroundColor3 = backdrop,
				BorderSizePixel = 0,
				ZIndex = (props.ZIndex or 1) + 6,
			}, {
				new("UIStroke", { Color = accent, Thickness = 1.4, Transparency = 0.25 }),
			})
		end
	end

	return body, stroke
end

-- ── Hex portrait ────────────────────────────────────────────────────────
-- Three overlapping rotated bars make a hexagon outline; the image sits in a
-- plain frame behind them. Not a true mask - the art is inset far enough that
-- the illusion holds, which is all a 96px portrait needs.
function BattleTheme.hexPortrait(parent: Instance, opts: { [string]: any })
	local size = opts.size or 92
	local accent = opts.accent or BattleTheme.Colors.Player
	local z = opts.zIndex or 10

	local root = new("Frame", {
		Name = opts.name or "Portrait",
		Parent = parent,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Position = opts.position or UDim2.fromOffset(0, 0),
		AnchorPoint = opts.anchorPoint or Vector2.new(0, 0),
		ZIndex = z,
	})

	-- rotated square backing reads as a gem/hex facet
	local plate = new("Frame", {
		Name = "Plate",
		Parent = root,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size * 0.76, size * 0.76),
		Rotation = 45,
		BackgroundColor3 = BattleTheme.Colors.Panel,
		BorderSizePixel = 0,
		ZIndex = z,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, 8) }),
		new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(BattleTheme.Colors.PanelHi, BattleTheme.Colors.Void),
		}),
		new("UIStroke", { Color = accent, Thickness = 2.4, Transparency = 0.05 }),
	})
	BattleTheme.glow(plate, accent, 1)

	-- Counter-rotated so the artwork sits upright inside the tilted facet.
	local holder = new("Frame", {
		Name = "Holder",
		Parent = plate,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.98, 0.98),
		Rotation = -45,
		BackgroundTransparency = 1,
		ZIndex = z + 1,
	})

	local image = new("ImageLabel", {
		Name = "Art",
		Parent = holder,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.35, 1.35),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Crop,
		Image = opts.image or "",
		ZIndex = z + 1,
	})

	return root, image, plate
end

-- ── Floating combat number ──────────────────────────────────────────────
function BattleTheme.floatNumber(parent: GuiObject, text: string, color: Color3, z: number?)
	local label = new("TextLabel", {
		Parent = parent,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(1, 0.3),
		Text = text,
		TextColor3 = color,
		TextScaled = true,
		ZIndex = (z or 50) + 20,
	}, {
		new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 3, Transparency = 0.15 }),
		new("UITextSizeConstraint", { MaxTextSize = 34 }),
	})

	BattleTheme.tween(label, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.5, -0.15),
		TextTransparency = 1,
	})
	local s = label:FindFirstChildOfClass("UIStroke")
	if s then
		BattleTheme.tween(s, TweenInfo.new(0.75), { Transparency = 1 })
	end
	game:GetService("Debris"):AddItem(label, 0.9)
	return label
end

-- ── Shake ───────────────────────────────────────────────────────────────
-- Repeated hits share a stable origin. Superseded shake tasks never restore
-- their own offset over a newer animation.
local activeShakes = setmetatable({}, { __mode = "k" })
function BattleTheme.shake(frame: GuiObject, magnitude: number?, duration: number?)
	local mag, dur = magnitude or 6, duration or 0.24
	local previous = activeShakes[frame]
	local state = { home = previous and previous.home or frame.Position }
	activeShakes[frame] = state
	local started = os.clock()
	task.spawn(function()
		while frame.Parent and activeShakes[frame] == state do
			local elapsed = os.clock() - started
			if elapsed >= dur then break end
			local falloff = 1 - elapsed / dur
			frame.Position = state.home + UDim2.fromOffset(
				math.random(-100, 100) / 100 * mag * falloff,
				math.random(-100, 100) / 100 * mag * falloff
			)
			task.wait()
		end
		if activeShakes[frame] == state then
			activeShakes[frame] = nil
			if frame.Parent then frame.Position = state.home end
		end
	end)
end

return BattleTheme
