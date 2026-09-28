--!strict
-- The overworld's encounter cards: spawning them, keeping them alive, and the
-- run-up into a battle.
--
-- WHY THIS IS CLIENT-SIDE.
-- The card face is CardRenderer, which is UI code, and a SurfaceGui's contents
-- are drawn per-client anyway. Building these on the server would mean running
-- the whole card renderer there and then replicating several hundred GUI
-- instances per encounter to everybody. Built here it costs the network
-- nothing, and the security story is unchanged: the prompt only carries a card
-- id, and BattleService validates that id against its own ENCOUNTER_CARDS
-- before a fight starts. A tampered client can fake a prompt, not a battle.
--
-- ONE LOOP, NOT ONE PER CARD.
-- Every card is animated from a single Heartbeat below. Cards far from the
-- camera are updated at a third of the rate, and very distant ones are put to
-- sleep entirely - their emitters and light switch off and their CFrame stops
-- being written. Adding encounters therefore costs a table entry, not a
-- connection.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ED = require(ReplicatedStorage.Shared.Config.EncounterDefinitions)
local EncounterCard = require(ReplicatedStorage.Shared.World.EncounterCard)

local EncounterWorldController = {}
EncounterWorldController.Name = "EncounterWorldController"

local player = Players.LocalPlayer

----------------------------------------------------------------
-- TUNING
----------------------------------------------------------------

local TUNE = {
	-- Idle motion. All of this is deliberately slow: the brief was premium and
	-- calm, so nothing here should be noticeable as ANIMATION, only as life.
	BobAmplitude = 0.17,   -- studs above and below the rest height
	BobSpeed     = 1.05,   -- radians/sec (~6s for a full breath)
	SwayAngle    = math.rad(2.4),
	SwaySpeed    = 0.55,
	RollAngle    = math.rad(1.3),
	RollSpeed    = 0.37,
	PulseSpeed   = 0.85,

	-- Facing. The card turns toward you, but softly - this is a rate, not a snap.
	FaceRadius   = 34,     -- start turning to the player inside this
	FaceRate     = 3.2,    -- higher = turns faster

	-- Proximity ramp. Full brightness inside NearDistance, nothing past FarDistance.
	NearDistance = 13,
	FarDistance  = 46,

	-- Level of detail.
	LodDistance   = 70,    -- beyond this, update every third frame
	SleepDistance = 145,   -- beyond this, stop updating and switch effects off
	SleepPoll     = 15,    -- frames between re-checks while asleep

	-- Challenge run-up.
	ChallengeTime = 0.42,
	ChallengeLift = 2.4,   -- studs travelled toward the camera
	ChallengeTilt = math.rad(9),
}

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------

local cards: { any } = {}
local byCardId: { [string]: any } = {}
local folder: Folder
local frame = 0
local running = false

----------------------------------------------------------------
-- ANCHORS
----------------------------------------------------------------

-- An anchor is any BasePart carrying a CardId attribute. Two places are
-- searched, in order:
--
--   1. EncounterAnchors - the intended home. Drag the part, the card moves.
--      This is what you edit to place a new encounter.
--   2. The old EncounterNPCs models, so this system still works if it is ever
--      dropped into a place where the NPCs have not been retired.
--
-- The anchor's Y is the GROUND; the card floats above it.
--
-- THIS PLACE HAS StreamingEnabled ON, WHICH MATTERS HERE.
-- Under streaming a client is only sent parts near itself, so a plain folder of
-- anchors would arrive piecemeal - and the far ones never at all - meaning half
-- the encounters would silently fail to build. EncounterAnchors is therefore a
-- MODEL with ModelStreamingMode = Persistent, which is always replicated whole.
-- If you add an anchor, add it inside that model; a part dropped loose in the
-- workspace will work near spawn and mysteriously not work far from it.
local function collectAnchors(): { { cardId: string, cframe: CFrame } }
	local found: { { cardId: string, cframe: CFrame } } = {}
	local seen: { [string]: boolean } = {}

	local function take(cardId: any, cf: CFrame)
		if type(cardId) ~= "string" or seen[cardId] then return end
		seen[cardId] = true
		table.insert(found, { cardId = cardId, cframe = cf })
	end

	for _, d in ipairs(Workspace:GetDescendants()) do
		if (d:IsA("Model") or d:IsA("Folder")) and d.Name == "EncounterAnchors" then
			for _, a in ipairs(d:GetChildren()) do
				if a:IsA("BasePart") then
					-- Name is accepted as a fallback so an anchor is still usable if
					-- someone forgets the attribute.
					take(a:GetAttribute("CardId") or a.Name, a.CFrame)
				end
			end
		end
	end

	if #found == 0 then
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("Model") and d:GetAttribute("CardId") then
				local root = d.PrimaryPart or d:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					-- The NPC's root sits at torso height; drop to its feet so the
					-- card's float height is measured from the ground either way.
					local cf = root.CFrame * CFrame.new(0, -root.Size.Y * 0.5 - 1.0, 0)
					take(d:GetAttribute("CardId"), CFrame.new(cf.Position)
						* CFrame.Angles(0, select(2, root.CFrame:ToEulerAnglesYXZ()), 0))
				end
			end
		end
	end

	return found
end

----------------------------------------------------------------
-- SPAWNING
----------------------------------------------------------------

local function spawnAll()
	-- Controllers start before the workspace has finished arriving, so a single
	-- look can legitimately come up empty on a slow join. Retry briefly rather
	-- than deciding there are no encounters in the game.
	local anchors = collectAnchors()
	local waited = 0
	while #anchors == 0 and waited < 10 do
		task.wait(0.5)
		waited += 1
		anchors = collectAnchors()
	end

	if #anchors == 0 then
		warn("[EncounterWorld] no anchors found after 5s; no encounter cards spawned")
		return
	end

	for _, anchor in ipairs(anchors) do
		local entry = ED.get(anchor.cardId)
		if not entry then
			-- An anchor for a card that is not an encounter is a placement mistake,
			-- not a crash. Say so and carry on with the rest.
			warn(("[EncounterWorld] anchor %q has no EncounterDefinitions entry; skipped")
				:format(anchor.cardId))
			continue
		end

		local handle = EncounterCard.build(entry, folder)
		if handle then
			local _, yaw = anchor.cframe:ToEulerAnglesYXZ()
			local ground = anchor.cframe.Position

			handle.groundPosition = ground
			handle.restPosition = ground + Vector3.new(0, ED.Card.Float * handle.scale, 0)
			handle.homeYaw = yaw
			handle.yaw = yaw
			-- Every card gets its own phase so six of them never breathe in unison,
			-- which is what makes a row of them look mechanical.
			handle.phase = (handle.entry.Order or #cards) * 1.37

			handle.ring.CFrame = CFrame.new(ground + Vector3.new(0, 0.06, 0))
				* CFrame.Angles(0, yaw, 0)

			table.insert(cards, handle)
			byCardId[entry.CardId] = handle
		end
	end

	print(("[EncounterWorld] %d encounter cards built (%s)")
		:format(#cards, ED.CardMeshId ~= "" and "mesh" or "part fallback"))
end

----------------------------------------------------------------
-- THE LOOP
----------------------------------------------------------------

local function shortestAngle(from: number, to: number): number
	return (to - from + math.pi) % (math.pi * 2) - math.pi
end

local function playerPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function step(dt: number)
	frame += 1
	local now = os.clock()
	local camera = Workspace.CurrentCamera
	local cameraPos = camera and camera.CFrame.Position or Vector3.zero
	local target = playerPosition() or cameraPos

	for i, h in ipairs(cards) do
		local dist = (target - h.restPosition).Magnitude

		----------------------------------------------------------------
		-- level of detail
		----------------------------------------------------------------
		if dist > TUNE.SleepDistance then
			EncounterCard.setAsleep(h, true)
			-- Still poll occasionally so walking back into range wakes it.
			if (frame + i) % TUNE.SleepPoll ~= 0 then continue end
		else
			EncounterCard.setAsleep(h, false)
			if dist > TUNE.LodDistance and (frame + i) % 3 ~= 0 then continue end
		end

		----------------------------------------------------------------
		-- idle motion
		----------------------------------------------------------------
		local bob = math.sin(now * TUNE.BobSpeed + h.phase) * TUNE.BobAmplitude * h.scale
		local sway = math.sin(now * TUNE.SwaySpeed + h.phase * 1.7) * TUNE.SwayAngle
		local roll = math.sin(now * TUNE.RollSpeed + h.phase * 0.9) * TUNE.RollAngle

		----------------------------------------------------------------
		-- facing
		----------------------------------------------------------------
		-- Inside FaceRadius the card turns to the player; outside it drifts back
		-- to the yaw it was placed at. Both are the same exponential approach, so
		-- there is no moment where it visibly changes behaviour.
		local wantYaw = h.homeYaw
		if dist < TUNE.FaceRadius then
			local d = target - h.restPosition
			if d.Magnitude > 0.05 then
				-- A part's Front face is -Z, so this points the printed side at the
				-- player rather than the back of the card.
				wantYaw = math.atan2(-d.X, -d.Z)
			end
		end
		local blend = 1 - math.exp(-TUNE.FaceRate * dt)
		h.yaw += shortestAngle(h.yaw, wantYaw) * blend

		----------------------------------------------------------------
		-- challenge run-up
		----------------------------------------------------------------
		local lift, tilt = 0, 0
		local charge = 0
		if h.challengeAt then
			local p = math.clamp((now - h.challengeAt) / TUNE.ChallengeTime, 0, 1)
			-- ease-out cubic: fast off the mark, settles rather than arrives
			local e = 1 - (1 - p) ^ 3
			charge = e
			lift = e * TUNE.ChallengeLift * h.scale
			tilt = e * TUNE.ChallengeTilt
			if now - h.challengeAt > TUNE.ChallengeTime + 1.4 then
				h.challengeAt = nil
			end
		end

		----------------------------------------------------------------
		-- write
		----------------------------------------------------------------
		local pos = h.restPosition + Vector3.new(0, bob, 0)
		if lift > 0 then
			-- Travel toward the CAMERA, not the character: the transition is a
			-- framing move, and the player's eye is at the camera.
			local toCam = cameraPos - pos
			if toCam.Magnitude > 0.1 then
				pos += toCam.Unit * lift
			end
		end

		local cf = CFrame.new(pos)
			* CFrame.Angles(0, h.yaw + sway, 0)
			* CFrame.Angles(tilt, 0, roll)

		h.body.CFrame = cf
		-- The edge light rides just behind the card so only its rim shows.
		h.glow.CFrame = cf * CFrame.new(0, 0, h.thickness * 0.5 + 0.012)

		----------------------------------------------------------------
		-- proximity + pulse
		----------------------------------------------------------------
		local t = 1 - math.clamp(
			(dist - TUNE.NearDistance) / (TUNE.FarDistance - TUNE.NearDistance), 0, 1)
		t = math.max(t, charge)
		local pulse = 0.5 + 0.5 * math.sin(now * TUNE.PulseSpeed + h.phase)
		EncounterCard.setNearness(h, t, pulse)
	end
end

----------------------------------------------------------------
-- PUBLIC
----------------------------------------------------------------

-- Called by NPCEncounterController the instant the player commits to the fight,
-- so the world reacts before the battle UI takes over the screen.
function EncounterWorldController:PlayChallenge(cardId: string)
	local h = byCardId[cardId]
	if not h then return end
	h.challengeAt = os.clock()
end

function EncounterWorldController:GetCard(cardId: string)
	return byCardId[cardId]
end

function EncounterWorldController:Init()
	folder = Instance.new("Folder")
	folder.Name = "EncounterCards"
	folder.Parent = Workspace

	-- EncounterCard.build yields on CreateMeshPartAsync, so spawning cannot run
	-- inline in Init without stalling every controller behind it.
	task.spawn(function()
		local ok, err = pcall(spawnAll)
		if not ok then
			warn("[EncounterWorld] spawn failed: " .. tostring(err))
			return
		end
		if #cards == 0 or running then return end
		running = true
		RunService.Heartbeat:Connect(step)
	end)

	-- Opening the panel clears any run-up still playing on that card. Without
	-- this, backing out of a fight and immediately re-opening the same encounter
	-- would show the card still hanging in mid-flight toward the camera from the
	-- previous attempt.
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local id = prompt:GetAttribute("EncounterCardId")
		if type(id) == "string" then
			local h = byCardId[id]
			if h then h.challengeAt = nil end
		end
	end)
end

function EncounterWorldController:Start()
end

return EncounterWorldController
