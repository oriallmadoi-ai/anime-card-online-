--!strict
-- Every balance number lives here. Nothing else should hardcode a constant.

local GameConfig = {}

-- ── Rolling ────────────────────────────────────────────────
GameConfig.BaseRollCooldown = 2.0
GameConfig.MinRollCooldown  = 0.10

-- Luck multiplies a card's 1/N chance. Luck 0 = 1x.
GameConfig.LuckPerLevel = 0.25          -- +0.25 luck per upgrade level
GameConfig.MaxLuckLevel = 3000
GameConfig.RollSpeedPerLevel = 0.03     -- -3% roll interval per level
GameConfig.MaxRollSpeedLevel = 50

-- Every Nth roll is a "lucky" roll at multiplied luck. A guaranteed rhythm like
-- this gives the player something to count toward between rare pulls, which
-- matters most in the long stretches where nothing good is landing.
GameConfig.LuckyRollEvery = 10
GameConfig.LuckyRollMultiplier = 2

-- ── Variants ───────────────────────────────────────────────
-- Merging copies into a higher tier is NOT built. The two constants that used
-- to sit here (MergeRequirement, AllowDeconstruct) were read by nothing, and a
-- balance number nothing reads is worse than no number at all - it reads as a
-- tuned system. Add them back in the same breath as the code that uses them.

-- ── Deck ───────────────────────────────────────────────────
GameConfig.AttackSlots  = 5
GameConfig.SupportSlots = 5
GameConfig.DeckPresets  = 8

-- ── Cards / levelling ──────────────────────────────────────
-- Levels run 0..100 (boss cards to BossCardLevel). A fresh copy sits at 0 and
-- Elder Essence raises it; level 0
-- therefore means "base stats, no bonus".
GameConfig.MinCardLevel = 0
GameConfig.MaxCardLevel = 100

-- Boss cards go further than everything else. This is the CEILING, not a cap
-- every boss shares: a card opts in by setting its own `maxLevel`, and
-- CardDefinitions.maxLevel falls back to MaxCardLevel for everyone else. So
-- promoting a card to boss levelling is one field on that card, and nothing
-- can quietly outgrow this number.
GameConfig.BossCardLevel = 120
GameConfig.StatBonusPerLevel = 0.0125   -- +1.25% per level, +125% at max

-- ── Combat ─────────────────────────────────────────────────
GameConfig.BaseCritChance = 0.05
GameConfig.CritMultiplier = 2.0
GameConfig.MaxDamageReduction = 0.75
GameConfig.MaxBattleTurns = 200

-- ── Skill tree ─────────────────────────────────────────────
-- Elder Coins are awarded for WINNING a battle, not per enemy defeated, so a
-- loss pays nothing however far it got.
--
-- Battle wins now pay a large, satisfying amount because every skill-tree cost
-- is expressed in the same larger economy. The important thing is the ratio:
-- early ranks still move quickly, while the deep prerequisite ranks plus Elder
-- Ascension remain a long-term goal.
GameConfig.ElderCoinsPerVictory = 20000

-- A hard ceiling on the derived roll-speed reduction, whatever the tree totals
-- to. RollService already floors the cooldown at MinRollCooldown, so this is a
-- second guard rather than the only one - but a reduction of 1.0 or more would
-- make the cooldown zero or negative before that floor is ever consulted.
GameConfig.MaxSkillRollSpeedReduction = 0.80

-- ── Data ───────────────────────────────────────────────────
GameConfig.SaveSchemaVersion = 13

return GameConfig
