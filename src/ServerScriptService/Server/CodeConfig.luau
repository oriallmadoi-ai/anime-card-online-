--!strict
-- Anime Card Online
-- Redeem codes. SERVER ONLY (lives in ServerScriptService) so players can't
-- read unreleased codes out of ReplicatedStorage.
--
-- Codes are CASE-SENSITIVE: "RELEASE" works, "release" does not.
-- Each code can be claimed once per player (saved in profile.redeemedCodes).
--
-- Adding a code: copy the RELEASE entry. Every reward line is optional.
--   coins    Elder Coins (paid exactly - the +35% pass and skill tree do NOT
--            boost code rewards)
--   cores    { { stage id, count } }  stage ids: "Basic1" .. "Cosmic5"
--   items    { { item id, count } }   "CoreEssenceBasic", "ElderWrench"
--   expires  optional os.time() after which the code stops working
--   disabled optional true to switch a code off without deleting it

local CodeConfig = {}

CodeConfig.Codes = {
	RELEASE = {
		coins = 500000,
		cores = { { "Basic1", 4 } },
		items = { { "ElderWrench", 1 } },
	},
}

return CodeConfig
