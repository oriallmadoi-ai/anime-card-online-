--!strict
local Controllers = script.Parent.Controllers

local loaded: { [string]: any } = {}
local ordered: { any } = {}

for _, module in ipairs(Controllers:GetChildren()) do
	if module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			result.Name = result.Name or module.Name
			loaded[module.Name] = result
			table.insert(ordered, result)
		else
			warn(("[Client] failed to require %s: %s"):format(module.Name, tostring(result)))
		end
	end
end

for _, c in ipairs(ordered) do c.Controllers = loaded end
for _, c in ipairs(ordered) do
	if type(c.Init) == "function" then
		local ok, err = pcall(c.Init, c)
		if not ok then warn(("[Client] %s:Init failed: %s"):format(c.Name, err)) end
	end
end
for _, c in ipairs(ordered) do
	if type(c.Start) == "function" then
		task.spawn(function()
			local ok, err = pcall(c.Start, c)
			if not ok then warn(("[Client] %s:Start failed: %s"):format(c.Name, err)) end
		end)
	end
end

print(("[Client] %d controllers online"):format(#ordered))
