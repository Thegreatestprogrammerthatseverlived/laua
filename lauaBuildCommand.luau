local url = "https://raw.githubusercontent.com/Thegreatestprogrammerthatseverlived/laua/main/transpiler/transpiler.luau"

local success, source = pcall(function()
    return game:GetService("HttpService"):GetAsync(url, true)
end)
if not success then error("Failed to download Laua: " .. tostring(source)) end

if not source:find("local Transpiler =", 1, true) or not source:find("return Transpiler", 1, true) then
    error("Invalid Laua transpiler source received from GitHub")
end

local parent = game:GetService("ServerScriptService")
local transpiler = parent:FindFirstChild("transpiler")

if transpiler and not transpiler:IsA("ModuleScript") then
    error("An object named 'transpiler' already exists and is not a ModuleScript")
end

if not transpiler then
    transpiler = Instance.new("ModuleScript")
    transpiler.Name = "transpiler"
end

transpiler.Source = source
transpiler.Parent = parent

local version = source:match('Version%s*=%s*"([^"]+)"') or "Unknown"
print("Laua v" .. version .. " installed successfully!")
