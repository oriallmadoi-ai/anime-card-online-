--!strict
-- Loads every ModuleScript in Services, then calls :Init() and :Start() in
-- two passes. Two passes matter: Init sets up state, Start is where services
-- are allowed to talk to each other. Skip this and you get load-order bugs
-- that only show up in production.

local Services = script.Parent.Services

local loaded: { [string]: any } = {}
local ordered: { any } = {}

for _, module in ipairs(Services:GetChildren()) do
	if module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			result.Name = result.Name or module.Name
			loaded[module.Name] = result
			table.insert(ordered, result)
		else
			warn(("[Bootstrap] failed to require %s: %s"):format(module.Name, tostring(result)))
		end
	end
end

-- Let services find each other without circular require()
for _, service in ipairs(ordered) do
	service.Services = loaded
end

for _, service in ipairs(ordered) do
	if type(service.Init) == "function" then
		local ok, err = pcall(service.Init, service)
		if not ok then warn(("[Bootstrap] %s:Init failed: %s"):format(service.Name, err)) end
	end
end

for _, service in ipairs(ordered) do
	if type(service.Start) == "function" then
		task.spawn(function()
			local ok, err = pcall(service.Start, service)
			if not ok then warn(("[Bootstrap] %s:Start failed: %s"):format(service.Name, err)) end
		end)
	end
end

-- Debug handle. Lets the command bar and MCP tooling reach the *live* service
-- instances; a plain require() from there gets a separate module cache and a
-- second, empty copy of every service. Server-side only, so this is not an
-- exploit surface.
_G.CardClash = { Services = loaded }

print(("[Bootstrap] %d services online"):format(#ordered))
