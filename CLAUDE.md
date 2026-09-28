# Project instructions

This is an existing Roblox game's script-only Rojo project, exported from a saved place. Read README.md before making changes.

- Edit Luau files in src. Preserve exact instance names, classes, and hierarchy unless the task requires a migration.
- default.project.json explicitly maps each source file. Update it when adding or moving a script.
- Keep $ignoreUnknownInstances true on mapped nodes. The map, models, GUI instances, and assets are maintained in the existing Studio place and must be preserved.
- Preserve Disabled and RunContext settings. Script / LocalScript / ModuleScript are distinct.
- Do not claim the built script-only place is a complete game. Do not publish it as one.
- Do not reset player data or change datastore names as a workaround for bugs.
- Validate with Rojo 7.7 or newer when available. Explain which checks were run and which require a Studio playtest.
- Cloud sessions do not have an automatically configured live Studio connection. Do not claim to have observed Studio or tested gameplay unless tools actually provided that access.
- script-manifest.json is the original export inventory and checksum baseline.
