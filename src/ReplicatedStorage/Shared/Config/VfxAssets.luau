--!strict
-- Authored VFX sprites for the roll reveal.
--
-- WHY THESE EXIST AT ALL.
-- The reveal used to draw its "light" out of plain Frames: twelve white
-- rectangles for rays, a rounded rectangle for the glow, a UIStroke circle for
-- the shockwave. A Frame has a hard edge and no falloff, so none of it read as
-- light - it read as cardboard. Every one of those is now a real sprite with a
-- proper alpha ramp, which is the single biggest reason the reveal stopped
-- looking flat.
--
-- ALL OF THESE ARE WHITE WITH ALPHA, deliberately. RGB is 255 across the whole
-- image INCLUDING the fully transparent pixels, so bilinear filtering can never
-- pull a dark fringe in from the empty area. Tint at the call site with
-- ImageColor3 and the sprite takes the rarity's colour for free. Vignette is
-- the one exception: it is black with alpha, because it darkens rather than
-- lights.
--
-- Source PNGs live in the repo folder under rollvfx/ - regenerate and re-upload
-- there rather than editing ids by hand.

local VfxAssets = {}

-- Soft radial bloom. 512x512. Wide gaussian body with a hotter core.
VfxAssets.Glow = "rbxassetid://107970376598883"

-- 30-ray starburst, varied width and length, soft hub. 1024x1024.
VfxAssets.Burst = "rbxassetid://100866883960898"

-- One cone of light: narrow bright BASE AT THE BOTTOM of the image, flaring
-- soft toward the top. Anchor it at (0.5, 1) and rotate to fan shafts outward.
VfxAssets.Shaft = "rbxassetid://139789126199300"

-- Expanding shockwave: thin bright leading edge, softer trailing bleed, faint
-- wash inside. 512x512, ring sits at 0.60 of the half-width.
VfxAssets.Shock = "rbxassetid://130434325998705"

-- Summon circle: two tick bands, a glyph band, inscribed hexagram, spokes.
-- 1024x1024. Reads as light, not as line art, because every stroke is blurred.
VfxAssets.Rune = "rbxassetid://83007697141560"

-- Four-point lens sparkle with a secondary 45 degree cross. 128x128.
VfxAssets.Spark = "rbxassetid://95098361874999"

-- Plain soft dot for drifting particles. 64x64.
VfxAssets.Mote = "rbxassetid://103427829662023"

-- Anamorphic horizontal lens streak. 512x128.
VfxAssets.Streak = "rbxassetid://80281916054168"

-- Converging manga focus lines, clear through the middle. 1024x1024.
VfxAssets.SpeedLines = "rbxassetid://76780151618828"

-- BLACK with alpha. Clear centre, dark edges.
VfxAssets.Vignette = "rbxassetid://99996847693980"

-- Halo shaped like a card: bright rim tracing a rounded rectangle, broad soft
-- falloff outward. 512x660, matches a 0.76 aspect card.
VfxAssets.CardGlow = "rbxassetid://78277232420194"

-- ── ABILITY SPRITES ────────────────────────────────────────────────
-- Modelled in Blender rather than drawn: nested additive emitters rendered to
-- float EXR, then collapsed to a white alpha mask here. Same white-with-alpha
-- rule as everything above, so one beam sprite serves both "Son" cards in
-- blue-white and Number One's rounds in deep blue off a single upload.

-- The beam SHAFT. 1024x256, horizontal, uniform along its length so it can be
-- stretched to any distance between two cards. Surging thickness, three winds
-- spiralling inside it and four flow filaments. Cap the ends with Flare and
-- Impact rather than baking them in, or the caps stretch too.
VfxAssets.BeamCore = "rbxassetid://106598402563013"

-- Muzzle. 512x512, ASYMMETRIC: long lance toward +X where the beam leaves, a
-- short recoil stub behind, containment rings at the mouth. Rotate it to the
-- firing angle, do not mirror it.
VfxAssets.BeamFlare = "rbxassetid://140399992562218"

-- Where the beam is stopped. 512x512, twelve shards of uneven length plus two
-- shock rings - the energy has to visibly go sideways or the beam reads as
-- passing through the target.
VfxAssets.BeamImpact = "rbxassetid://106504522016077"

-- The wind-up. 512x512 pearl with three tilted containment rings and nine
-- wisps spiralling INWARD, which is the only thing separating a charge from an
-- explosion at a glance.
VfxAssets.BeamCharge = "rbxassetid://137078921866301"

-- One round. 512x128, hard nose at the RIGHT, tail dissolving left. Built
-- separately from BeamCore because shrinking a beam down to bullet size just
-- gives a soft dash with no leading edge.
VfxAssets.ShotTracer = "rbxassetid://126927167740477"

return VfxAssets
