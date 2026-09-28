--!strict
-- Global typography.
--
-- Every text object in the game gets its FontFace from here. Rather than
-- editing the Font property on a few hundred labels scattered across modules,
-- bind() walks a container and also listens for DescendantAdded - so anything
-- created later (backpack rows, card reveals, notifications) is styled the
-- moment it appears. Changing the game's font is now a one-line edit.

local Theme = {}

-- Fredoka One: round, bold and friendly - Roblox's built-in cut of the Fredoka
-- family the UI mockups in Figma are drawn with. (Was Creepster.)
Theme.FontId = "rbxasset://fonts/families/FredokaOne.json"

-- ALWAYS Regular. Fredoka One ships a single weight that is already heavy;
-- asking it for Bold makes Roblox SYNTHESISE one by smearing the outlines.
-- Hierarchy comes from size and colour, never from weight.
Theme.Weight = Enum.FontWeight.Regular

-- Roblox does not error when a font id is the wrong asset type; it warns once
-- and falls back. Checking here means a bad id is obvious immediately instead
-- of being mistaken for "the font just looks like that".
function Theme.verifyFont(): boolean
	local ok = pcall(function()
		local probe = Instance.new("TextLabel")
		probe.FontFace = Theme.font()
		probe:Destroy()
	end)
	if not ok then
		warn("[Theme] font id rejected: " .. Theme.FontId)
	end
	return ok
end

function Theme.font(): Font
	return Font.new(Theme.FontId, Theme.Weight, Enum.FontStyle.Normal)
end

local TEXT_CLASSES = {
	TextLabel = true, TextButton = true, TextBox = true,
}

local function isThemed(face: Font): boolean
	return face.Family == Theme.FontId and face.Weight == Theme.Weight
end

-- Objects already being watched, so a label that is re-parented (and so
-- "added" again) does not collect a second listener.
local watched: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function apply(inst: Instance)
	local ok = pcall(function()
		local label = inst :: any
		if not isThemed(label.FontFace) then
			label.FontFace = Theme.font()
		end
	end)
	if not ok then
		warn("[Theme] could not set FontFace on " .. inst:GetFullName())
	end
end

local function styleOne(inst: Instance)
	if not TEXT_CLASSES[inst.ClassName] then
		return
	end
	apply(inst)
	if watched[inst] then
		return
	end
	watched[inst] = true
	-- A lot of older UI code sets `Font = Enum.Font.GothamBold` AFTER the label
	-- is already in the tree, which used to win over the sweep. Watching the
	-- property puts the game font straight back, so every piece of text ends up
	-- in it no matter when or how it was styled.
	inst:GetPropertyChangedSignal("FontFace"):Connect(function()
		apply(inst)
	end)
end

-- Applies to everything currently inside `container`, and to anything added to
-- it afterwards. Returns the connection so a caller can stop watching.
function Theme.bind(container: Instance): RBXScriptConnection
	for _, d in ipairs(container:GetDescendants()) do
		styleOne(d)
	end
	styleOne(container)
	return container.DescendantAdded:Connect(styleOne)
end

return Theme
