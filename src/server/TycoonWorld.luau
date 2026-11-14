--!nonstrict
-- Plots, owner-only interactions and cached vehicle displays; Main owns economy.
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local TycoonWorld = {}
TycoonWorld.__index = TycoonWorld

local ORIGINS = { Vector3.new(-55, .5, -55), Vector3.new(55, .5, -55), Vector3.new(-55, .5, 55), Vector3.new(55, .5, 55) }
local BAY_X = { -20, 0, 20 }
local UPGRADE_IDS = { "income", "speed", "magnet", "coinValue" }
local UPGRADE_NAMES = { income = "INGRESOS", speed = "VELOCIDAD", magnet = "IMÁN", coinValue = "MONEDAS" }
local RANK_COLORS = { Color3.fromRGB(130, 88, 62), Color3.fromRGB(50, 151, 204), Color3.fromRGB(42, 176, 144), Color3.fromRGB(241, 166, 51), Color3.fromRGB(218, 67, 83), Color3.fromRGB(156, 96, 242) }
local TEAL, GOLD = Color3.fromRGB(47, 210, 180), Color3.fromRGB(255, 198, 62)
local NAVY, PURPLE, WHITE = Color3.fromRGB(30, 48, 72), Color3.fromRGB(166, 103, 255), Color3.fromRGB(240, 247, 245)

local function money(amount)
	amount = tonumber(amount) or 0
	if amount >= 1e9 then return string.format("%.1fB", amount / 1e9) end
	if amount >= 1e6 then return string.format("%.1fM", amount / 1e6) end
	if amount >= 1e3 then return string.format("%.1fK", amount / 1e3) end
	return tostring(math.floor(amount))
end

local function part(parent, name, size, position, color, material)
	local result = Instance.new("Part")
	result.Name, result.Size, result.Position = name, size, position
	result.Color, result.Material = color, material or Enum.Material.SmoothPlastic
	result.Anchored, result.CanCollide, result.CanTouch = true, false, false
	result.TopSurface, result.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	result.Parent = parent
	return result
end

local function billboard(parent, text, color, offset, size, distance)
	local gui = Instance.new("BillboardGui")
	gui.Name, gui.Size = "DisplayLabel", size or UDim2.fromOffset(205, 55)
	gui.StudsOffsetWorldSpace, gui.AlwaysOnTop, gui.MaxDistance = offset or Vector3.new(0, 2.3, 0), false, distance or 90
	gui.Parent = parent
	local label = Instance.new("TextLabel")
	label.Name, label.Size = "Label", UDim2.fromScale(1, 1)
	label.BackgroundColor3, label.BackgroundTransparency = NAVY, .12
	label.TextColor3, label.Text, label.Font, label.TextSize, label.TextWrapped = color or WHITE, text, Enum.Font.GothamBold, 16, true
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius, corner.Parent = UDim.new(0, 9), label
	local stroke = Instance.new("UIStroke")
	stroke.Color, stroke.Transparency, stroke.Thickness, stroke.Parent = color or TEAL, .3, 1, label
	return label
end

local function prompt(parent, action, object)
	local result = Instance.new("ProximityPrompt")
	result.Name, result.ActionText, result.ObjectText = "Interact", action, object
	result.KeyboardKeyCode, result.GamepadKeyCode = Enum.KeyCode.E, Enum.KeyCode.ButtonX
	result.HoldDuration, result.MaxActivationDistance, result.RequiresLineOfSight = .3, 8, false
	result.Exclusivity, result.Parent = Enum.ProximityPromptExclusivity.OnePerButton, parent
	return result
end

local function validOwner(plot, player, position, distance)
	if plot.owner ~= player then return false end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return root and humanoid and humanoid.Health > 0 and (root.Position - position).Magnitude <= (distance or 10)
end

local function ownedSet(profile, state)
	local owned = {}
	for _, id in (profile and profile.ownedCars) or {} do owned[tonumber(id) or id] = true end
	for _, tier in (state and state.carTiers) or {} do if tier.owned then owned[tier.id] = true end end
	return owned
end

local function paintable(object)
	local marker = object:FindFirstChild("Paintable")
	return object:GetAttribute("Paintable") == true or (marker and marker:IsA("BoolValue") and marker.Value)
end

function TycoonWorld.new()
	local self = setmetatable({ Plots = {}, PlayerPlots = {} }, TycoonWorld)
	self.Root = workspace:FindFirstChild("TycoonPlots") or Instance.new("Folder")
	self.Root.Name, self.Root.Parent = "TycoonPlots", workspace
	Lighting.ClockTime, Lighting.Brightness = 16.6, 2
	Lighting.Ambient, Lighting.OutdoorAmbient = Color3.fromRGB(110, 120, 138), Color3.fromRGB(143, 146, 160)
	Lighting.FogColor, Lighting.FogStart, Lighting.FogEnd = Color3.fromRGB(179, 205, 229), 280, 750
	return self
end

function TycoonWorld.BindCollect(self, callback) self.CollectCallback = callback end
function TycoonWorld.BindAction(self, callback) self.ActionCallback = callback end

function TycoonWorld._EmitAction(self, plot, player, action, id, pad)
	if validOwner(plot, player, pad.Position, 11) and self.ActionCallback then self.ActionCallback(player, action, id) end
end

function TycoonWorld._EmitCollect(self, plot, player, coin)
	if not coin.available or os.clock() < coin.debounceUntil or not validOwner(plot, player, coin.part.Position, 8) then return end
	coin.debounceUntil = os.clock() + .2
	if self.CollectCallback then self.CollectCallback(player, coin.id) end
end

function TycoonWorld._CreateCoins(self, plot)
	for id = 1, 12 do
		local position = plot.origin + Vector3.new(-21 + ((id - 1) % 4) * 14, 2, -24 + math.floor((id - 1) / 4) * 6)
		local disc = part(plot.folder, "Coin" .. id, Vector3.new(.3, 1.9, 1.9), position, GOLD, Enum.Material.Metal)
		disc.Shape, disc.CFrame, disc.CanTouch = Enum.PartType.Cylinder, CFrame.new(position) * CFrame.Angles(0, math.pi / 2, 0), true
		disc:SetAttribute("OwnerUserId", plot.owner.UserId)
		disc:SetAttribute("CoinId", id)
		local label = billboard(disc, "$", GOLD, Vector3.new(0, 1.6, 0), UDim2.fromOffset(30, 30), 55)
		label.BackgroundTransparency, label.TextSize = 1, 25
		label:FindFirstChildOfClass("UIStroke").Enabled = false
		local interact = prompt(disc, "Recoger", "Moneda de tu taller")
		interact.HoldDuration, interact.MaxActivationDistance = 0, 5
		local coin = { id = id, part = disc, label = label, prompt = interact, available = true, debounceUntil = 0 }
		plot.coins[id] = coin
		interact.Triggered:Connect(function(player) self:_EmitCollect(plot, player, coin) end)
		disc.Touched:Connect(function(hit)
			local character = hit:FindFirstAncestorOfClass("Model")
			local player = character and Players:GetPlayerFromCharacter(character)
			if player then self:_EmitCollect(plot, player, coin) end
		end)
	end
end

function TycoonWorld._CreateActions(self, plot)
	for id = 1, 6 do
		local position = plot.origin + Vector3.new(BAY_X[(id - 1) % 3 + 1], .45, math.floor((id - 1) / 3) * 19 - 7)
		local pad = part(plot.folder, "BuyCar" .. id, Vector3.new(7.5, .35, 2.6), position, GOLD, Enum.Material.Neon)
		local label = billboard(pad, "AUTO " .. id .. "\nCARGANDO…", GOLD, Vector3.new(0, 1.7, 0), UDim2.fromOffset(160, 46), 36)
		label.TextSize = 14
		local interact = prompt(pad, "Comprar auto", "Auto " .. id)
		plot.carPads[id] = { part = pad, label = label, prompt = interact }
		interact.Triggered:Connect(function(player) self:_EmitAction(plot, player, "buyCar", id, pad) end)
	end
	for index, id in UPGRADE_IDS do
		local pad = part(plot.folder, "Upgrade_" .. id, Vector3.new(4, .35, 5.5), plot.origin + Vector3.new(28.7, .45, -21 + (index - 1) * 10), Color3.fromRGB(65, 152, 232), Enum.Material.Neon)
		local label = billboard(pad, UPGRADE_NAMES[id], Color3.fromRGB(138, 200, 255), Vector3.new(0, 1.7, 0), UDim2.fromOffset(135, 46), 23)
		label.TextSize = 14
		local interact = prompt(pad, "Mejorar", UPGRADE_NAMES[id])
		plot.upgradePads[id] = { part = pad, label = label, prompt = interact }
		interact.Triggered:Connect(function(player) self:_EmitAction(plot, player, "buyUpgrade", id, pad) end)
	end
	local rebirth = part(plot.folder, "RebirthPrompt", Vector3.one * .3, plot.origin + Vector3.new(-28.7, 2.2, -17), PURPLE)
	rebirth.Transparency = 1
	prompt(rebirth, "Ver renacimiento", "Conserva tus multiplicadores").Triggered:Connect(function(player) self:_EmitAction(plot, player, "openRebirth", nil, rebirth) end)
	plot.rebirthPad = rebirth
end

function TycoonWorld.AssignPlot(self, player, index)
	index = tonumber(index)
	if not index or not ORIGINS[index] then return nil end
	if self.PlayerPlots[player] then self:ReleasePlot(player) end
	if self.Plots[index] and self.Plots[index].owner ~= player then return nil end
	local folder = Instance.new("Folder")
	folder.Name, folder.Parent = "Plot" .. index, self.Root
	folder:SetAttribute("OwnerUserId", player.UserId)
	local cars, decor = Instance.new("Folder"), Instance.new("Folder")
	cars.Name, cars.Parent, decor.Name, decor.Parent = "Cars", folder, "Milestones", folder
	local origin = ORIGINS[index]
	local map = workspace:FindFirstChild("MidnightGarage")
	local marker = map and map:FindFirstChild("Plot" .. index .. "Origin")
	if marker and marker:IsA("BasePart") then origin = marker.Position end
	local plot = { index = index, origin = origin, owner = player, folder = folder, cars = cars, decor = decor, coins = {}, carPads = {}, upgradePads = {}, signature = nil }
	self.Plots[index], self.PlayerPlots[player] = plot, plot
	local ownerAnchor = part(folder, "OwnerSign", Vector3.one * .2, origin + Vector3.new(0, 7.6, -31), TEAL)
	ownerAnchor.Transparency = 1
	plot.ownerLabel = billboard(ownerAnchor, string.upper(player.DisplayName) .. "\nTALLER 0" .. index, WHITE, Vector3.zero, UDim2.fromOffset(280, 65), 145)
	self:_CreateCoins(plot)
	self:_CreateActions(plot)
	-- RespawnLocation lets the engine place every new character in the assigned
	-- plot. A delayed correction handles a character already spawning when the
	-- plot was claimed; an immediate CharacterAdded PivotTo races engine spawn.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name, spawn.Size = "OwnerSpawn", Vector3.new(6, .3, 4)
	spawn.Position = origin + Vector3.new(0, .15, -28)
	spawn.CFrame = CFrame.lookAt(spawn.Position, spawn.Position + Vector3.new(0, 0, 10))
	spawn.Anchored, spawn.CanCollide, spawn.CanTouch, spawn.Transparency = true, false, false, 1
	spawn.Neutral, spawn.Duration, spawn.Enabled, spawn.AllowTeamChangeOnTouch = true, 0, true, false
	spawn.Parent = folder
	plot.spawn = spawn
	player.RespawnLocation = spawn
	local function teleportAfterSpawn(character, delaySeconds)
		task.spawn(function()
			local root = character:WaitForChild("HumanoidRootPart", 8)
			local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 8)
			task.wait(delaySeconds)
			if not root or not humanoid or humanoid.Health <= 0 or not character.Parent then return end
			if self.PlayerPlots[player] ~= plot or player.Character ~= character or plot.placedCharacter == character then return end
			-- Once the player is in their plot, later appearance events must never
			-- pull them back to the entrance after they begin walking around.
			local offset = root.Position - origin
			if math.abs(offset.X) <= 32 and math.abs(offset.Z) <= 31 then
				plot.placedCharacter = character
				return
			end
			local destination = origin + Vector3.new(0, 3, -28)
			character:PivotTo(CFrame.lookAt(destination, destination + Vector3.new(0, 0, 10)))
			plot.placedCharacter = character
		end)
	end
	plot.characterConnection = player.CharacterAdded:Connect(function(character)
		teleportAfterSpawn(character, .65)
	end)
	if player.CharacterAppearanceLoaded then
		plot.appearanceConnection = player.CharacterAppearanceLoaded:Connect(function(character)
			teleportAfterSpawn(character, .2)
		end)
	end
	if player.Character then teleportAfterSpawn(player.Character, .65) end
	return index
end

function TycoonWorld._DisplayCar(self, plot, tier, owned)
	local templates = ServerStorage:FindFirstChild("VehicleTemplates")
	local template = templates and (templates:FindFirstChild(tier.template or "Sedan") or templates:FindFirstChild("Sedan"))
	local id = tonumber(tier.id) or 1
	local position = plot.origin + Vector3.new(BAY_X[(id - 1) % 3 + 1], .2, math.floor((id - 1) / 3) * 19)
	if not template or not template:IsA("Model") then return end
	local model = template:Clone()
	model.Name = "Tier" .. id
	model:SetAttribute("TierId", id)
	model:SetAttribute("Owned", owned == true)
	model:SetAttribute("OwnerUserId", plot.owner.UserId)
	local root = model:FindFirstChild("VehicleRoot")
	if root and root:IsA("BasePart") then model.PrimaryPart = root end
	local paintColor = RANK_COLORS[id] or TEAL
	if type(tier.color) == "table" then paintColor = Color3.fromRGB(tier.color[1] or 47, tier.color[2] or 210, tier.color[3] or 180) end
	for _, object in model:GetDescendants() do
		if object:IsA("BasePart") then
			object.Anchored, object.CanCollide, object.CanTouch = true, false, false
			if object.Name ~= "VehicleRoot" then
				if not owned then
					object.Transparency, object.Color = math.max(object.Transparency, .86), Color3.fromRGB(89, 110, 134)
					object.Material, object.CastShadow = Enum.Material.SmoothPlastic, false
				elseif paintable(object) then
					object.Color = paintColor
					if id == 1 then object.Material = Enum.Material.CorrodedMetal end
				end
			end
		elseif object:IsA("Light") then object.Enabled, object.Brightness = owned == true, .15 end
	end
	model:PivotTo(CFrame.new(position))
	model.Parent = plot.cars
	if owned and tier.neon then
		part(model, "NeonUnderGlow", Vector3.new(4.7, .05, 8), position + Vector3.new(0, .08, 0), paintColor, Enum.Material.Neon).Transparency = .35
	end
	local labelAnchor = part(model, "NameAnchor", Vector3.one * .2, position + Vector3.new(0, 4.5, 0), TEAL)
	labelAnchor.Transparency = 1
	billboard(labelAnchor, (owned and "✓  " or "◇  ") .. tostring(tier.name or ("Auto " .. id)), owned and WHITE or Color3.fromRGB(143, 168, 190), Vector3.zero, UDim2.fromOffset(190, 30), 28)
end

function TycoonWorld._BuildMilestones(self, plot, count)
	plot.decor:ClearAllChildren()
	if count >= 1 then
		for _, x in { -7, 7 } do part(plot.decor, "EntranceGlow", Vector3.new(.22, .1, 12), plot.origin + Vector3.new(x, .12, -18), TEAL, Enum.Material.Neon) end
	end
	if count >= 2 then
		for _, x in { -28, 28 } do
			local banner = part(plot.decor, "CollectionBanner", Vector3.new(1.2, 4.2, .35), plot.origin + Vector3.new(x, 6, 28), GOLD, Enum.Material.Metal)
			billboard(banner, "★", GOLD, Vector3.zero, UDim2.fromOffset(35, 35), 70)
		end
	end
	if count >= 3 then
		local desk = part(plot.decor, "OfficeDesk", Vector3.new(4, 2.8, 2), plot.origin + Vector3.new(-28, 1.8, 8), NAVY, Enum.Material.Metal)
		part(plot.decor, "OfficeMonitor", Vector3.new(2, 1.2, .15), desk.Position + Vector3.new(0, 2, 0), TEAL, Enum.Material.Neon)
	end
	if count >= 4 then
		for _, x in { -10, 10 } do part(plot.decor, "PremiumBeam", Vector3.new(.25, .25, 38), plot.origin + Vector3.new(x, 9.3, 9), GOLD, Enum.Material.Neon) end
	end
	if count >= 5 then
		local pedestal = part(plot.decor, "TrophyBase", Vector3.new(2, 1, 2), plot.origin + Vector3.new(28, 1, 21), NAVY, Enum.Material.Metal)
		part(plot.decor, "Trophy", Vector3.new(1.8, 2.3, 1.8), pedestal.Position + Vector3.new(0, 1.6, 0), GOLD, Enum.Material.Metal).Shape = Enum.PartType.Ball
	end
	if count >= 6 then
		local champion = part(plot.decor, "ChampionSign", Vector3.one * .2, plot.origin + Vector3.new(0, 9, 20), PURPLE)
		champion.Transparency = 1
		billboard(champion, "★  COLECCIÓN COMPLETA  ★", GOLD, Vector3.zero, UDim2.fromOffset(330, 45), 110)
	end
end

function TycoonWorld.UpdatePlot(self, player, profile, state)
	local plot = self.PlayerPlots[player]
	if not plot then return end
	state = state or {}
	local owned, tiers = ownedSet(profile, state), state.carTiers or {}
	local signatureParts, ownedCount = {}, 0
	for _, tier in tiers do
		table.insert(signatureParts, tostring(tier.id) .. ":" .. tostring(owned[tier.id] == true) .. ":" .. tostring(tier.template))
		if owned[tier.id] then ownedCount += 1 end
		local pad = plot.carPads[tier.id]
		if pad then
			pad.part.Color = if owned[tier.id] then TEAL elseif tier.locked then PURPLE elseif tier.canBuy then GOLD else Color3.fromRGB(151, 134, 91)
			pad.part.Transparency = if owned[tier.id] then .55 else 0
			pad.label.Text = if owned[tier.id] then "EN TU COLECCIÓN\n+$" .. money(tier.income) .. "/s" elseif tier.locked then tostring(tier.name) .. "\nRENACIMIENTOS: " .. tostring(tier.minRebirth or 0) else tostring(tier.name) .. "\n$" .. money(tier.cost) .. "  •  +$" .. money(tier.income) .. "/s"
			pad.label.TextColor3 = if tier.locked then Color3.fromRGB(214, 188, 255) else WHITE
			pad.prompt.Enabled, pad.prompt.ActionText, pad.prompt.ObjectText = not owned[tier.id] and not tier.locked, "Comprar • $" .. money(tier.cost), tostring(tier.name)
		end
	end
	local signature = table.concat(signatureParts, "|")
	if plot.signature ~= signature then
		plot.cars:ClearAllChildren()
		for _, tier in tiers do self:_DisplayCar(plot, tier, owned[tier.id]) end
		self:_BuildMilestones(plot, ownedCount)
		plot.signature = signature
	end
	for _, upgrade in state.upgrades or {} do
		local pad = plot.upgradePads[upgrade.id]
		if pad then
			local atMax = (upgrade.level or 0) >= (upgrade.maxLevel or 999)
			pad.label.Text = string.upper(upgrade.name or UPGRADE_NAMES[upgrade.id] or upgrade.id) .. "  " .. tostring(upgrade.level or 0) .. "/" .. tostring(upgrade.maxLevel or "∞") .. "\n" .. (atMax and "NIVEL MÁXIMO" or ("$" .. money(upgrade.cost)))
			pad.prompt.Enabled, pad.prompt.ActionText = not atMax, "Mejorar • $" .. money(upgrade.cost)
			pad.prompt.ObjectText = upgrade.name or UPGRADE_NAMES[upgrade.id] or upgrade.id
			pad.part.Color = if atMax then TEAL elseif upgrade.canBuy then Color3.fromRGB(65, 152, 232) else Color3.fromRGB(86, 107, 136)
		end
	end
	local rebirths = (profile and profile.rebirths) or state.rebirths or 0
	plot.ownerLabel.Text = string.upper(player.DisplayName) .. "  /  TALLER 0" .. plot.index .. "\n" .. ownedCount .. "/6 AUTOS  •  " .. tostring(rebirths) .. " RENACIMIENTOS"
	for _, coin in plot.coins do coin.prompt.ActionText = "Recoger +$" .. money(state.coinValue or 10) end
end

function TycoonWorld.GetCoinPosition(self, player, id)
	local plot = self.PlayerPlots[player]
	local coin = plot and plot.coins[tonumber(id)]
	return coin and coin.part.Position or nil
end

function TycoonWorld.SetCoinAvailable(self, player, id, available)
	local plot = self.PlayerPlots[player]
	local coin = plot and plot.coins[tonumber(id)]
	if not coin then return end
	coin.available, coin.part.CanTouch, coin.prompt.Enabled, coin.label.Parent.Enabled = available == true, available == true, available == true, available == true
	coin.part.Transparency = if coin.available then 0 else 1
	if coin.available then
		coin.part.Size = Vector3.new(.3, .1, .1)
		TweenService:Create(coin.part, TweenInfo.new(.25, Enum.EasingStyle.Back), { Size = Vector3.new(.3, 1.9, 1.9) }):Play()
	end
end

function TycoonWorld.GetActionPosition(self, player, action, id)
	local plot = self.PlayerPlots[player]
	if not plot then return nil end
	if action == "buyCar" then local pad = plot.carPads[tonumber(id)]; return pad and pad.part.Position or nil end
	if action == "buyUpgrade" then local pad = plot.upgradePads[id]; return pad and pad.part.Position or nil end
	if action == "openRebirth" or action == "rebirth" then return plot.rebirthPad.Position end
	return nil
end

function TycoonWorld.ReleasePlot(self, player)
	local plot = self.PlayerPlots[player]
	if not plot then return end
	if plot.characterConnection then plot.characterConnection:Disconnect() end
	if plot.appearanceConnection then plot.appearanceConnection:Disconnect() end
	if player.RespawnLocation == plot.spawn then player.RespawnLocation = nil end
	plot.folder:Destroy()
	self.Plots[plot.index], self.PlayerPlots[player] = nil, nil
end

return TycoonWorld
