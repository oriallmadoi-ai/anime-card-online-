# Anime Card Online — Rojo script project

This project contains all 198 scripts exported from your saved `animecardonline rojo.rbxl` copy. It syncs code into that existing place. It is **not a complete replacement place**: maps, models, UI objects, assets, terrain, and other non-script properties remain in Studio.

## Open and sync

1. Open this whole folder in VS Code (File > Open Folder).
2. Install the **Rojo – Roblox Studio Sync** extension.
3. Press Ctrl+Shift+P and select **Rojo: Open menu**. Follow the prompts to install Rojo, and choose **Install Roblox Studio plugin**.
4. Start the Rojo server for `default.project.json` from the extension menu.
5. Open a backup copy of the original game in Roblox Studio, with play mode stopped.
6. Open the Rojo plugin and connect to the local server. Review its initial sync changes. Stop if it proposes unexpected removals or replacing existing objects.
7. Playtest. Keep your original backup until you have verified the synced game.

If Rojo CLI is installed separately, the server command from this folder is `rojo serve default.project.json`.

All mapped nodes explicitly preserve unknown instances. Existing script paths, classes, Disabled flags, and RunContext settings were checked against the saved copy. This does not verify a live Studio sync; review that first connection before applying it. If your Studio place has changed since you saved the copy, reconcile those newer changes before syncing.

## GitHub and Claude cloud

1. Put the contents of this folder at the root of your local GitHub repository. Keep `src` and `default.project.json` together.
2. Commit the files in GitHub Desktop, then publish the repository as private.
3. In Claude's Code tab, start a **Cloud** session, connect GitHub, and choose that repository.
4. Give Claude a small coding task and check the cloud-credit balance in Claude's usage settings.
5. Review and merge its pull request, then use **Fetch origin / Pull origin** in GitHub Desktop on your main branch.
6. Rojo syncs those updated local code files into the connected Studio place. Playtest before publishing.

Do not upload the scratch `scripts-check.rbxlx` build as your game; it contains only the mapped scripts and their ancestors. Your original game remains the source for the scene and assets.

## Editing

Edit managed scripts in `src` and commit them before sending another cloud task. Direct Studio source edits do not automatically flow back into these files. Adding or moving scripts also requires updating their mappings in `default.project.json`; paths are explicit to preserve the existing game hierarchy. `script-manifest.json` records the initial export, not future edits.

Cloud editing of this repository does not automatically provide access to the Studio window or its playtests.
