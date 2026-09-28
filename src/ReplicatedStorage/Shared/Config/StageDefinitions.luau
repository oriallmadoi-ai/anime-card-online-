--!strict
-- Story content. A stage is a list of waves; a wave is a list of enemies.
-- Placeholder while the roster is rebuilt.

local StageDefinitions = {}

StageDefinitions.Worlds = {
	[1] = {
		id = 1, name = "Training Grounds",
		stages = {
			{
				id = "1-1", name = "First Steps",
				waves = {
					{ { id = "TrainingDummy", level = 1 } },
					{ { id = "Slimeling", level = 1 }, { id = "Slimeling", level = 2 } },
				},
				rewards = { books = { MinorTome = 2 } },
			},
		},
	},
}

function StageDefinitions.get(worldId: number, stageIndex: number)
	local world = StageDefinitions.Worlds[worldId]
	return world and world.stages[stageIndex] or nil
end

return StageDefinitions
