--!strict
-- Anime Card Online
-- Shared configuration for the standard sidebar windows.
--
-- IMPORTANT:
-- Deck and Skill Tree intentionally stay OUT of this config because both have
-- specialised full-screen controllers that should not be redesigned here.

local MenuConfig = {}

-- THE MOUNT ICON LIVES HERE AND NOWHERE ELSE.
-- The navigation button in UIController reads this same value, so the cloud
-- art is set in one place. Paste the uploaded asset id in below.
MenuConfig.MountIcon = "rbxassetid://134611162201385"

MenuConfig.Order = {
	"Backpack",
	"Quests",
	"BattlePass",
	"Teleport",
	"Shop",
	"Mounts",
	"Settings",
	"Codes",
}

MenuConfig.Menus = {
	Backpack = {
		Title = "BACKPACK",
		IconImage = "rbxassetid://97534595040988",
		Color1 = Color3.fromRGB(22, 144, 255),
		Color2 = Color3.fromRGB(105, 228, 255),
		Color3 = Color3.fromRGB(30, 93, 229),
		ButtonAliases = { "backpack", "backpackbutton", "backpackbtn" },
	},

	Quests = {
		Title = "QUESTS",
		IconImage = "rbxassetid://77987610643269",
		Color1 = Color3.fromRGB(36, 193, 85),
		Color2 = Color3.fromRGB(191, 246, 51),
		Color3 = Color3.fromRGB(17, 145, 69),
		ButtonAliases = { "quest", "quests", "questbutton", "questsbutton", "questbtn", "questsbtn" },
	},

	BattlePass = {
		Title = "BATTLE PASS",
		IconImage = "rbxassetid://107867939390433",
		Color1 = Color3.fromRGB(53, 187, 94),
		Color2 = Color3.fromRGB(210, 231, 54),
		Color3 = Color3.fromRGB(27, 135, 74),
		ButtonAliases = { "battlepass", "battlepassbutton", "battlepassbtn" },
	},

	-- A tall, narrow panel: three destination cards stacked, nothing else.
	-- See the Width/Height note on Mounts below for why these two opt out of
	-- the responsive full-screen layout.
	Teleport = {
		Title = "TELEPORT",
		IconImage = "rbxassetid://116662081402516",
		Width = 420,
		Height = 640,
		Color1 = Color3.fromRGB(255, 132, 18),
		Color2 = Color3.fromRGB(255, 222, 53),
		Color3 = Color3.fromRGB(235, 79, 17),
		ButtonAliases = { "teleport", "portal", "teleportbutton", "teleportbtn", "portalbutton", "portalbtn" },
	},

	Shop = {
		Title = "SHOP",
		IconImage = "rbxassetid://81589496518912",
		Color1 = Color3.fromRGB(108, 56, 230),
		Color2 = Color3.fromRGB(203, 111, 255),
		Color3 = Color3.fromRGB(78, 36, 186),
		ButtonAliases = { "shop", "store", "shopbutton", "storebutton", "shopbtn", "storebtn" },
	},

	-- Width/Height are optional, and only Teleport and Mounts set them. A menu
	-- that declares them gets a fixed panel at exactly that size, which only
	-- ever shrinks to fit a small viewport; every other menu keeps the
	-- responsive behaviour of stretching toward the edges of the screen. Both
	-- of these are short lists, and a short list in a 1200x680 frame is mostly
	-- empty space.
	--
	-- White, because the cloud is white. Color2 is the border and the accents.
	Mounts = {
		Title = "MOUNTS",
		IconImage = MenuConfig.MountIcon,
		Width = 420,
		Height = 396,
		Color1 = Color3.fromRGB(226, 232, 244),
		Color2 = Color3.fromRGB(255, 255, 255),
		Color3 = Color3.fromRGB(150, 160, 180),
		ButtonAliases = { "mount", "mounts", "mountbutton", "mountsbutton", "mountbtn", "mountsbtn" },
	},

	Settings = {
		Title = "SETTINGS",
		IconImage = "rbxassetid://86261752940686",
		Color1 = Color3.fromRGB(255, 111, 18),
		Color2 = Color3.fromRGB(255, 207, 50),
		Color3 = Color3.fromRGB(226, 68, 13),
		ButtonAliases = { "setting", "settings", "settingbutton", "settingsbutton", "settingbtn", "settingsbtn" },
	},

	Codes = {
		Title = "CODES",
		IconImage = "rbxassetid://123936473099980",
		Color1 = Color3.fromRGB(241, 54, 151),
		Color2 = Color3.fromRGB(206, 76, 255),
		Color3 = Color3.fromRGB(131, 48, 220),
		ButtonAliases = { "code", "codes", "codebutton", "codesbutton", "codebtn", "codesbtn" },
	},
}

return MenuConfig
