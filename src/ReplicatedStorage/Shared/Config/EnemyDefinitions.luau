--!strict
-- Enemies use the same stat model as cards but live in their own table: an
-- enemy may have stats no card can reach, and enemies must never leak into the
-- rolling pool.
--
-- Passive-free while the card roster is being rebuilt; add `passive = "..."`
-- to any entry and it works immediately.

local EnemyDefinitions = {}

EnemyDefinitions.Data = {
	TrainingDummy = { id = "TrainingDummy", name = "Training Dummy", baseDMG = 1,  baseHP = 40,  tags = {} },
	Slimeling     = { id = "Slimeling",     name = "Slimeling",      baseDMG = 3,  baseHP = 60,  tags = {} },
	BanditScout   = { id = "BanditScout",   name = "Bandit Scout",   baseDMG = 6,  baseHP = 110, tags = {} },
}

function EnemyDefinitions.get(id: string) return EnemyDefinitions.Data[id] end

return EnemyDefinitions
