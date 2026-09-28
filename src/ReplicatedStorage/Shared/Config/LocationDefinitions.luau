--!strict
-- Anime Card Online - Location Definitions
-- Full replacement version for the Pirate Shark Park location.
--
-- IMPORTANT:
-- The internal key stays "GreenPlanet" for now so the existing BattleService
-- continues working without needing another server-side replacement. Players
-- will only ever see "Pirate Shark Park".

local LocationDefinitions = {}

LocationDefinitions.Data = {
	GreenPlanet = {
		id = "GreenPlanet",

		-- Player-facing location name.
		Name = "Pirate Shark Park",

		Description = "Round 6: All remaining cards lose HP equal to 15% of their Max HP.",
		Trigger = "RoundStart",
		TriggerRound = 6,
		Once = true,

		-- Kept independent from the internal ID so future location-border systems
		-- can recognize this as Arlong Park.
		BorderTheme = "ArlongPark",

		-- Pirate Shark Park location artwork supplied by you.
		Artwork = "rbxassetid://138229980884501",

		Effect = {
			Kind = "PercentMaxHPLoss",
			Percent = 0.15,
			Targets = "BothActive",
		},

		-- Blue location / hover theme.
		Colors = {
			Outer = Color3.fromRGB(5, 20, 42),
			Base = Color3.fromRGB(12, 55, 100),
			Highlight = Color3.fromRGB(65, 172, 255),
			Teal = Color3.fromRGB(76, 205, 255),
			Text = Color3.fromRGB(230, 246, 255),
		},
	},
}

function LocationDefinitions.get(id: string)
	return LocationDefinitions.Data[id]
end

return LocationDefinitions
