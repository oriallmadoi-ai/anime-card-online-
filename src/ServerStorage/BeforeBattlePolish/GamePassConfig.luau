--!strict
-- Anime Card Online
-- The three game passes: ids, store copy, and the numbers their perks use.
--
-- OWNERSHIP TRAVELS AS A PLAYER ATTRIBUTE ("Pass_<key>"), set only by the
-- server (GamePassService). Attributes replicate, so the store, the battle
-- speed button and anything else on the client can read ownership without a
-- remote of its own - and nothing the client writes to its own copy counts,
-- because every perk is applied on the server.

local GamePassConfig = {}

GamePassConfig.Passes = {
	VIP = {
		key = "VIP",
		id = 1998717118,
		name = "VIP",
		icon = "rbxassetid://122149546048511",
		description = "+25% luck, 2x rolling speed and a 2x battle speed button!",
		accent = Color3.fromRGB(255, 61, 90),
		accent2 = Color3.fromRGB(255, 197, 61),
		tag = "MOST POPULAR",
		-- The tag's colours travel around it like the Divine/Secret borders.
		tagColours = {
			Color3.fromRGB(255, 197, 61),
			Color3.fromRGB(255, 92, 120),
			Color3.fromRGB(255, 236, 150),
			Color3.fromRGB(255, 61, 90),
			Color3.fromRGB(255, 197, 61),
		},
	},
	DoubleCore = {
		key = "DoubleCore",
		id = 1998297024,
		name = "2x Summon Core",
		icon = "rbxassetid://124664731309634",
		description = "Every Summon Core you open summons TWICE. Two cards, one core!",
		accent = Color3.fromRGB(180, 92, 255),
		accent2 = Color3.fromRGB(255, 197, 61),
		tag = "HOT",
		tagColours = {
			Color3.fromRGB(255, 140, 40),
			Color3.fromRGB(255, 226, 90),
			Color3.fromRGB(255, 70, 70),
			Color3.fromRGB(255, 170, 60),
			Color3.fromRGB(255, 140, 40),
		},
	},
	MoreItems = {
		key = "MoreItems",
		id = 1999641020,
		name = "+35% Items",
		icon = "rbxassetid://81702044714575",
		description = "35% more Elder Coins, essence and items from everything!",
		accent = Color3.fromRGB(34, 200, 255),
		accent2 = Color3.fromRGB(127, 233, 255),
	},
}

GamePassConfig.Order = { "VIP", "DoubleCore", "MoreItems" }

-- VIP
GamePassConfig.VipLuckMultiplier = 1.25   -- multiplies the whole luck total
GamePassConfig.VipRollSpeedMultiplier = 2 -- roll cooldown divided by this
GamePassConfig.VipBattleSpeed = 2         -- the fast setting of the battle toggle

-- +35% Items
GamePassConfig.ItemBonus = 0.35

-- STUDIO TESTING. You own your own passes, so Roblox would report all three as
-- owned and the store would only ever say OWNED. With this on, a Studio
-- playtest starts with NO passes, so you can press BUY and go through the real
-- purchase prompt (Studio purchases are free test purchases) and watch each
-- perk switch on. Live servers are never affected: this is only read when
-- RunService:IsStudio() is true. Set it to false to test as the owner.
GamePassConfig.StudioStartUnowned = true

function GamePassConfig.attribute(key: string): string
	return "Pass_" .. key
end

function GamePassConfig.owns(player: Player?, key: string): boolean
	return player ~= nil and player:GetAttribute(GamePassConfig.attribute(key)) == true
end

function GamePassConfig.byId(id: number)
	for _, key in ipairs(GamePassConfig.Order) do
		local pass = GamePassConfig.Passes[key]
		if pass.id == id then
			return pass
		end
	end
	return nil
end

return GamePassConfig
