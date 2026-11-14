--!nonstrict
-- Personal tycoon progression. Currency, prices, collection and rebirths are authoritative.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local shared = ReplicatedStorage:WaitForChild("MidnightGarage")
local Config = require(shared:WaitForChild("Config"))
local Economy = require(shared:WaitForChild("Economy"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local TycoonWorld = require(script.Parent:WaitForChild("TycoonWorld"))
local economy = Economy.new(Config)
local world = TycoonWorld.new()

local function ensure(parent, className, name)
	local existing = parent:FindFirstChild(name)
	if existing then
		assert(existing:IsA(className), "Unexpected class for " .. name)
		return existing
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = parent
	return created
end

local remotes = ensure(shared, "Folder", "Remotes")
local stateRemote = ensure(remotes, "RemoteEvent", "State")
local notifyRemote = ensure(remotes, "RemoteEvent", "Notify")
local actionRemote = ensure(remotes, "RemoteEvent", "Action")
local profiles, saveStatuses, plots, slots = {}, {}, {}, {}
local nextCoinAt, lastActionAt, lastSyncAt, releasing, revisions = {}, {}, {}, {}, {}
local pendingReleases, pendingLoads = {}, {}
local closing = false

local function notify(player, text, tone, extras)
	local payload = { text = text, tone = tone or "info" }
	if extras then
		for key, value in pairs(extras) do payload[key] = value end
	end
	notifyRemote:FireClient(player, payload)
end

local function sendState(player)
	local profile = profiles[player]
	if not profile or player.Parent ~= Players then return end
	local payload = economy.PublicState(profile)
	revisions[player] = (revisions[player] or 0) + 1
	payload.revision = revisions[player]
	payload.plotIndex = plots[player]
	payload.saveStatus = saveStatuses[player] or "loading"
	payload.objective = payload.saveStatus == "loading" and "Preparando tu garaje…" or payload.objective
	stateRemote:FireClient(player, payload)
	if payload.saveStatus ~= "loading" then world:UpdatePlot(player, profile, payload) end
end

local function applySpeed(player)
	local profile = profiles[player]
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if profile and humanoid then humanoid.WalkSpeed = economy.WalkSpeed(profile) end
end

local function ready(player)
	return not closing and profiles[player] ~= nil and saveStatuses[player] ~= "loading" and player.Parent == Players
end

local function aliveRoot(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return humanoid and root and humanoid.Health > 0 and root or nil
end

local function collect(player, coinId, automatic)
	if not ready(player) or type(coinId) ~= "number" or coinId % 1 ~= 0 or coinId < 1 or coinId > Config.CoinsPerPlot then return false end
	local root = aliveRoot(player)
	local position = world:GetCoinPosition(player, coinId)
	if not root or not position then return false end
	local radius = automatic and economy.MagnetRadius(profiles[player]) or Config.BasePickupRadius
	local distance = (root.Position - position).Magnitude
	if radius <= 0 or distance ~= distance or distance == math.huge or distance > radius then return false end
	local ledger = nextCoinAt[player]
	local now = os.clock()
	if not ledger or now < (ledger[coinId] or 0) then return false end
	-- Touched and Prompt can fire in the same frame: reserve before crediting.
	ledger[coinId] = now + Config.CoinCooldown
	local amount = economy.CollectCoin(profiles[player])
	world:SetCoinAvailable(player, coinId, false)
	notify(player, "+$" .. amount, "coin", { amount = amount, coinId = coinId })
	sendState(player)
	task.delay(Config.CoinCooldown, function()
		if nextCoinAt[player] == ledger and player.Parent == Players then world:SetCoinAvailable(player, coinId, true) end
	end)
	return true
end

local function buyCar(player, id)
	if not ready(player) then return end
	local success, message = economy.BuyCar(profiles[player], id)
	notify(player, message, success and "success" or "warning")
	sendState(player)
end

local function buyUpgrade(player, id)
	if not ready(player) then return end
	local success, message = economy.BuyUpgrade(profiles[player], id)
	if success then applySpeed(player) end
	notify(player, message, success and "success" or "warning")
	sendState(player)
end

local function rebirth(player)
	if not ready(player) then return end
	local success, message = economy.Rebirth(profiles[player])
	if success then applySpeed(player) end
	notify(player, message, success and "success" or "warning")
	sendState(player)
end

local function allowedAction(player)
	local now = os.clock()
	if now - (lastActionAt[player] or -math.huge) < 0.18 then return false end
	lastActionAt[player] = now
	return true
end

actionRemote.OnServerEvent:Connect(function(player, payload)
	if type(payload) ~= "table" or type(payload.type) ~= "string" or #payload.type > 24 then return end
	if payload.type == "sync" then
		local now = os.clock()
		if now - (lastSyncAt[player] or -math.huge) >= 1 then lastSyncAt[player] = now; sendState(player) end
		return
	end
	if not allowedAction(player) or not ready(player) then return end
	if payload.type == "collect" then collect(player, payload.coinId, false)
	elseif payload.type == "buyCar" then buyCar(player, payload.id)
	elseif payload.type == "buyUpgrade" then buyUpgrade(player, payload.id)
	elseif payload.type == "rebirth" then rebirth(player) end
end)

world:BindCollect(function(player, coinId) collect(player, coinId, false) end)
world:BindAction(function(player, action, id)
	if not ready(player) or not allowedAction(player) then return end
	if action == "buyCar" then buyCar(player, id)
	elseif action == "buyUpgrade" then buyUpgrade(player, id)
	elseif action == "openRebirth" or action == "rebirth" then
		notify(player, "Revisa lo que conservarás y confirma para renacer.", "info", { openPanel = "rebirth" })
	elseif action == "openCars" then notify(player, "Elige tu próximo auto.", "info", { openPanel = "cars" })
	elseif action == "openUpgrades" then notify(player, "Mejora la producción y la recogida de monedas.", "info", { openPanel = "upgrades" }) end
end)

local function save(player)
	if not ready(player) or releasing[player] then return end
	local ok, success, status = pcall(PlayerData.Save, player, profiles[player])
	if player.Parent == Players and profiles[player] then
		if ok and success then saveStatuses[player] = status or saveStatuses[player]
		elseif saveStatuses[player] ~= "session" then saveStatuses[player] = "unavailable" end
		sendState(player)
	end
end

local function playerAdded(player)
	if profiles[player] or closing then return end
	local index
	for candidate = 1, Config.MaxPlots do
		if not slots[candidate] then index = candidate; break end
	end
	if not index then player:Kick("Este servidor tiene cuatro garajes ocupados. Prueba otro servidor."); return end
	slots[index], plots[player] = player, index
	profiles[player], saveStatuses[player], nextCoinAt[player] = economy.NewProfile(), "loading", {}
	world:AssignPlot(player, index)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and profiles[player] then applySpeed(player); sendState(player) end
	end)
	sendState(player)
	pendingLoads[player] = true
	task.spawn(function()
		local ok, loaded, status = pcall(PlayerData.Load, player)
		if player.Parent ~= Players or not profiles[player] then
			if ok and type(loaded) == "table" then pcall(PlayerData.Release, player, loaded) end
			pendingLoads[player] = nil
			return
		end
		profiles[player] = economy.Sanitize(ok and loaded or nil)
		saveStatuses[player] = ok and (status or "unavailable") or "unavailable"
		applySpeed(player)
		sendState(player)
		if saveStatuses[player] == "unavailable" then
			notify(player, "El guardado no está disponible. Puedes jugar, pero esta sesión podría no guardarse.", "warning")
		end
		pendingLoads[player] = nil
	end)
end

local function release(player)
	if releasing[player] then return end
	releasing[player] = true
	pendingReleases[player] = true
	local profile = profiles[player]
	profiles[player], nextCoinAt[player] = nil, nil
	local index = plots[player]
	if index then slots[index] = nil end
	plots[player] = nil
	local cleaned, cleanupError = pcall(world.ReleasePlot, world, player)
	if not cleaned then warn("[Taller Tycoon] Plot cleanup: " .. tostring(cleanupError)) end
	lastActionAt[player], lastSyncAt[player], revisions[player] = nil, nil, nil
	if profile and saveStatuses[player] ~= "loading" then pcall(PlayerData.Release, player, profile) end
	saveStatuses[player] = nil
	pendingReleases[player] = nil
end

Players.PlayerAdded:Connect(playerAdded)
Players.PlayerRemoving:Connect(release)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(playerAdded, player) end

task.spawn(function()
	while not closing do
		task.wait(1)
		for player, profile in pairs(profiles) do
			if ready(player) then
				economy.Tick(profile, 1)
				if economy.MagnetRadius(profile) > 0 then
					for coinId = 1, Config.CoinsPerPlot do collect(player, coinId, true) end
				end
				sendState(player)
			end
		end
	end
end)

task.spawn(function()
	while not closing do
		task.wait(Config.AutosaveInterval)
		for player in pairs(profiles) do task.spawn(save, player) end
	end
end)

game:BindToClose(function()
	closing = true
	local leaving = {}
	for player in pairs(profiles) do
		table.insert(leaving, player)
	end
	for _, player in ipairs(leaving) do task.spawn(release, player) end
	local deadline = os.clock() + 25
	-- PlayerRemoving may already have cleared profiles while its datastore write
	-- is suspended. Also await those releases and loads cancelled during shutdown.
	while (next(pendingReleases) ~= nil or next(pendingLoads) ~= nil) and os.clock() < deadline do task.wait(0.1) end
end)

print("[Taller Tycoon] Tycoon personal listo: monedas, autos, mejoras y renacimientos.")
