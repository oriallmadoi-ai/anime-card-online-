--!strict
-- ReplicatedStorage > Shared > UI > UITheme
--
-- Every number that decides how a menu LOOKS lives here, and nowhere else. If a
-- panel corner, a stroke weight or a hover scale is written as a literal inside
-- a menu, the menus will drift apart again the first time one of them is edited
-- in isolation - which is exactly how the old UI ended up inconsistent.
--
-- Deck and Battle deliberately do NOT read from this module. They are excluded
-- from the design system on purpose; leaving them alone is a requirement, not an
-- oversight.

local UITheme = {}

-- ── SURFACES ───────────────────────────────────────────────────
-- A charcoal-navy rather than black. Pure black reads as a hole punched in the
-- screen; a blue-leaning dark still feels like a lit surface.
-- These sit deliberately HIGHER than the first pass. At (22,25,41) the panel
-- rendered as a black hole on screen - technically navy, visually black - which
-- was the single biggest complaint about the old menu. A mid-charcoal reads as
-- a lit surface while still giving white text plenty of contrast.
UITheme.Panel        = Color3.fromRGB(34, 39, 60)
UITheme.PanelTop     = Color3.fromRGB(48, 55, 82)   -- top of the panel gradient
UITheme.PanelBottom  = Color3.fromRGB(24, 28, 45)   -- bottom of the panel gradient
UITheme.Section      = Color3.fromRGB(52, 59, 84)   -- inner container fill
UITheme.SectionHover = Color3.fromRGB(68, 77, 108)
UITheme.Shadow       = Color3.fromRGB(0, 0, 0)

-- Translucent enough that the lobby still lives behind the menu, opaque enough
-- that card art and body text keep their contrast.
--
-- Sections are MORE opaque than the panel, not less. They are supposed to read
-- as raised surfaces sitting on it; leaving them translucent let the dark panel
-- show through and inverted the hierarchy - the inner container ended up darker
-- than the thing it sat on.
UITheme.PanelTransparency   = 0.14
UITheme.SectionTransparency = 0.10

-- How much of the menu's accent colour bleeds into the panel. Small on purpose:
-- at 0.10 the Battle Pass panel came out lavender rather than charcoal, which
-- crossed from "tinted" into "coloured".
UITheme.AccentTint = 0.06

-- ── TEXT ──────────────────────────────────────────────────────
UITheme.Text      = Color3.fromRGB(240, 242, 252)
UITheme.TextMuted = Color3.fromRGB(158, 165, 192)
UITheme.TextDim   = Color3.fromRGB(132, 140, 168)
UITheme.Ink       = Color3.fromRGB(8, 9, 15)        -- text stroke / shadow

-- Four steps, no more. Every label in every menu picks one of these; that single
-- rule is what stops "random text sizes in different menus".
UITheme.Type = {
	Header  = { Min = 18, Max = 34 },
	Section = { Min = 14, Max = 22 },
	Body    = { Min = 12, Max = 18 },
	Small   = { Min = 10, Max = 15 },
}

-- ── GEOMETRY ───────────────────────────────────────────────
UITheme.Radius = {
	Panel   = 18,
	Section = 12,
	Button  = 10,
	Pill    = 999,
}

UITheme.Stroke = {
	Panel       = 3.4,   -- the main accent border, hugging the panel itself
	PanelInner  = 1.2,   -- inner highlight, sits just inside the accent border
	Section     = 1.4,
	Button      = 1.4,
	ButtonHover = 2.2,
}

UITheme.Spacing = {
	Panel   = 18,
	Section = 14,
	Item    = 10,
	Tight   = 6,
}

-- ── MOTION ────────────────────────────────────────────────
UITheme.Motion = {
	-- Open overshoots slightly then settles, so the panel feels like it has
	-- weight. Close is quicker than open: waiting to dismiss feels sluggish in a
	-- way that waiting to open does not.
	OpenRise   = 0.13,
	OpenSettle = 0.13,
	OpenPeak   = 1.015,
	OpenStart  = 0.94,
	Close      = 0.16,
	CloseEnd   = 0.96,

	HeaderDelay  = 0.03,   -- header leads the content in
	ContentDelay = 0.09,
	HeaderSlide  = 12,     -- pixels the header travels on entry

	Hover = 0.12,
	Click = 0.08,
}

UITheme.Scale = {
	Rest  = 1.00,
	Hover = 1.025,
	Click = 0.97,
}

-- ── FOCUS DIM ─────────────────────────────────────────────
-- 0.62 transparency = ~38% dim. Enough to push the world back and make the menu
-- the focus, low enough that the lobby is still clearly readable behind it.
UITheme.DimTransparency = 0.62
UITheme.DimColor = Color3.fromRGB(6, 7, 14)
UITheme.DimTime = 0.18

-- ── HELPERS ───────────────────────────────────────────────
local WHITE = Color3.new(1, 1, 1)

-- The panel body for a given accent, i.e. the neutral dark nudged a few percent
-- toward the menu's colour so Backpack reads faintly warm and Quests faintly
-- cold without either becoming a coloured box.
function UITheme.tint(base: Color3, accent: Color3, amount: number?): Color3
	return base:Lerp(accent, amount or UITheme.AccentTint)
end

function UITheme.lighten(color: Color3, amount: number): Color3
	return color:Lerp(WHITE, amount)
end

function UITheme.darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

return UITheme
