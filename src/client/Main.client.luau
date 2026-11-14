--!nonstrict
-- Personal tycoon HUD. Purchases, prices and progress are server-authoritative.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContentProvider = game:GetService("ContentProvider")
pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false) end)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local packageRoot = ReplicatedStorage:WaitForChild("MidnightGarage")
local remotes = packageRoot:WaitForChild("Remotes")
local stateRemote, actionRemote, notifyRemote = remotes:WaitForChild("State"), remotes:WaitForChild("Action"), remotes:WaitForChild("Notify")
local oldGui = playerGui:FindFirstChild("MidnightGarageHUD")
if oldGui then oldGui:Destroy() end

local C = {
	ink = Color3.fromRGB(15, 30, 57), panel = Color3.fromRGB(34, 65, 108), raised = Color3.fromRGB(52, 91, 140),
	line = Color3.fromRGB(6, 15, 32), text = Color3.new(1, 1, 1), muted = Color3.fromRGB(206, 225, 247),
	blue = Color3.fromRGB(43, 158, 255), green = Color3.fromRGB(100, 222, 57), gold = Color3.fromRGB(255, 194, 57),
	orange = Color3.fromRGB(255, 155, 39), red = Color3.fromRGB(241, 76, 84), violet = Color3.fromRGB(167, 108, 255),
}
local currentState, currentPanel, panelSignature = nil, nil, nil
local rowReferences, panelParts = {}, nil
local portrait, smallHeight, introOpen = false, false, true
local confirmArmed, confirmSnapshot = false, nil
local requestTimes, toastGeneration = {}, 0
local updatePanel, layout, openPanel, closePanels

local function make(className, properties, parent)
	local object = Instance.new(className)
	for key, value in pairs(properties or {}) do object[key] = value end
	object.Parent = parent
	return object
end
local function round(parent, radius)
	make("UICorner", { CornerRadius = UDim.new(0, radius or 12) }, parent)
end
local function stroke(parent, color, thickness)
	return make("UIStroke", { Color = color or C.line, Thickness = thickness or 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end
local function gradient(parent)
	make("UIGradient", { Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 220, 240)) }, parent)
end
local function skin(parent, color)
	parent.BackgroundColor3, parent.BorderSizePixel = color or C.panel, 0
	round(parent, 14)
	stroke(parent)
	gradient(parent)
end
local function text(parent, value, size, color, title)
	return make("TextLabel", {
		BackgroundTransparency = 1, BorderSizePixel = 0, Text = value or "",
		TextSize = size or 14, TextColor3 = color or C.text,
		Font = if title then Enum.Font.FredokaOne else Enum.Font.GothamMedium,
		TextStrokeColor3 = C.line, TextStrokeTransparency = if title then 0.35 else 1,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = true, ZIndex = parent.ZIndex + 1,
	}, parent)
end
local function button(parent, value, color)
	-- Separate sibling bases never cover a TextButton's lettering.
	local base = make("Frame", { Name = "ButtonBase", BackgroundColor3 = C.line,
		BorderSizePixel = 0, ZIndex = parent.ZIndex + 1 }, parent)
	round(base, 12)
	local result = make("TextButton", {
		AutoButtonColor = false, BackgroundColor3 = color or C.green, BorderSizePixel = 0,
		Text = value, TextColor3 = C.text, Font = Enum.Font.FredokaOne, TextSize = 19,
		TextStrokeColor3 = C.line, TextStrokeTransparency = 0.35, ZIndex = parent.ZIndex + 2,
	}, parent)
	round(result, 12)
	stroke(result)
	gradient(result)
	local scale = make("UIScale", { Scale = 1 }, result)
	local function align()
		base.Position = result.Position + UDim2.fromOffset(0, 5)
		base.Size, base.AnchorPoint, base.Visible = result.Size, result.AnchorPoint, result.Visible
	end
	for _, property in ipairs({ "Position", "Size", "AnchorPoint", "Visible" }) do
		result:GetPropertyChangedSignal(property):Connect(align)
	end
	align()
	result.MouseButton1Down:Connect(function()
		if result.Active then TweenService:Create(scale, TweenInfo.new(0.07), { Scale = 0.96 }):Play() end
	end)
	local function release()
		TweenService:Create(scale, TweenInfo.new(0.17, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	result.MouseButton1Up:Connect(release)
	result.MouseLeave:Connect(release)
	return result
end
local function setButton(object, value, color, enabled)
	object.Text, object.BackgroundColor3, object.Active = value, color, enabled
	object.TextTransparency = if enabled then 0 else 0.13
end
local function number(value) return math.max(0, tonumber(value) or 0) end
local function shortNumber(value)
	local amount = number(value)
	for _, unit in ipairs({ { 1e12, "B" }, { 1e9, "MM" }, { 1e6, "M" }, { 1e3, "K" } }) do
		if amount >= unit[1] then return string.format("%.1f", amount / unit[1]):gsub("%.0$", "") .. unit[2] end
	end
	if amount > 0 and amount < 1 then return string.format("%.2f", amount) end
	return tostring(math.floor(amount))
end
local function money(value) return "$" .. shortNumber(value) end
local function rateMoney(value)
	local amount = number(value)
	if amount >= 1000 then return money(amount) end
	return "$" .. string.format("%.2f", amount):gsub("0+$", ""):gsub("%.$", "")
end
local function exactMoney(value)
	local integer = tostring(math.floor(number(value)))
	local formatted = integer:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "")
	return "$" .. formatted
end
local function multiplier(value)
	return "x" .. string.format("%.2f", number(value)):gsub("0+$", ""):gsub("%.$", "")
end
local function sendAction(actionType, id)
	local key, now = actionType .. ":" .. tostring(id or ""), os.clock()
	if now - (requestTimes[key] or -math.huge) < 0.55 then return false end
	requestTimes[key] = now
	local payload = { type = actionType }
	if id ~= nil then payload.id = id end
	actionRemote:FireServer(payload)
	return true
end

local gui = make("ScreenGui", { Name = "MidnightGarageHUD", ResetOnSpawn = false, IgnoreGuiInset = false,
	DisplayOrder = 20, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
local canvas = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)
local cashCard = make("Frame", { ZIndex = 5 }, canvas)
skin(cashCard, C.green)
local gameName = text(cashCard, "TALLER TYCOON", 12, C.text, true)
gameName.Position, gameName.Size = UDim2.fromOffset(14, 6), UDim2.new(1, -28, 0, 19)
local cashLabel = text(cashCard, "$0", 36, C.text, true)
cashLabel.Position, cashLabel.Size = UDim2.fromOffset(14, 25), UDim2.new(1, -28, 0, 43)
local incomeLabel = text(cashCard, "+$0 / SEGUNDO", 13, C.text, true)
incomeLabel.Position, incomeLabel.Size = UDim2.fromOffset(14, 70), UDim2.new(1, -28, 0, 20)
local statsCard = make("Frame", { ZIndex = 5 }, canvas)
skin(statsCard, C.panel)
local rebirthLabel = text(statsCard, "RENACIMIENTOS  0", 17, C.gold, true)
rebirthLabel.Position, rebirthLabel.Size = UDim2.fromOffset(13, 8), UDim2.new(1, -26, 0, 25)
local multiplierLabel = text(statsCard, "INGRESOS x1", 15, C.text, true)
multiplierLabel.Position, multiplierLabel.Size = UDim2.fromOffset(13, 35), UDim2.new(1, -26, 0, 24)
local saveLabel = text(statsCard, "Cargando progreso...", 10, C.muted, false)
saveLabel.Position, saveLabel.Size = UDim2.fromOffset(13, 64), UDim2.new(1, -26, 0, 27)
local objectiveCard = make("Frame", { ZIndex = 5 }, canvas)
skin(objectiveCard, C.orange)
local objectiveCaption = text(objectiveCard, "TU SIGUIENTE META", 11, C.text, true)
objectiveCaption.Position, objectiveCaption.Size = UDim2.fromOffset(13, 6), UDim2.new(1, -26, 0, 18)
local objectiveText = text(objectiveCard, "Recoge las monedas doradas de tu parcela.", 14, C.text, false)
objectiveText.TextStrokeTransparency = 0.5
objectiveText.Position, objectiveText.Size = UDim2.fromOffset(13, 25), UDim2.new(1, -26, 1, -31)
local navigation = make("Frame", { BackgroundTransparency = 1, ZIndex = 6 }, canvas)
local navButtons = { cars = button(navigation, "AUTOS", C.blue), upgrades = button(navigation, "MEJORAS", C.green),
	rebirth = button(navigation, "RENACER", C.orange) }
local navKeys = { "cars", "upgrades", "rebirth" }
local footer = text(canvas, "1 · Autos    2 · Mejoras    3 · Renacer    E · Interactuar", 11, C.text, false)
footer.TextXAlignment, footer.TextStrokeTransparency = Enum.TextXAlignment.Center, 0.4
local helpButton = button(canvas, "?", C.blue)
local coinPopup = text(canvas, "", 27, C.gold, true)
coinPopup.AnchorPoint = Vector2.new(0.5, 0.5)
coinPopup.Size, coinPopup.Visible, coinPopup.ZIndex = UDim2.fromOffset(190, 40), false, 18
coinPopup.TextXAlignment = Enum.TextXAlignment.Center
local coinGeneration, accumulatedCoins = 0, 0
local coinTween = nil
local function showCoin(amount)
	coinGeneration += 1
	local generation = coinGeneration
	accumulatedCoins += number(amount)
	if coinTween then coinTween:Cancel() end
	coinPopup.Text = "+" .. rateMoney(accumulatedCoins)
	coinPopup.Position, coinPopup.TextTransparency, coinPopup.Visible = UDim2.fromScale(0.5, 0.43), 0, true
	coinTween = TweenService:Create(coinPopup, TweenInfo.new(0.85, Enum.EasingStyle.Quad), {
		Position = UDim2.new(0.5, 0, 0.43, -40), TextTransparency = 1,
	})
	coinTween:Play()
	task.delay(0.9, function()
		if generation == coinGeneration then coinPopup.Visible, accumulatedCoins = false, 0 end
	end)
end

local toast = make("Frame", { ZIndex = 70, Visible = false }, canvas)
skin(toast, C.green)
local toastText = text(toast, "", 15, C.text, true)
toastText.Position, toastText.Size = UDim2.fromOffset(14, 8), UDim2.new(1, -28, 1, -16)
local function showToast(payload)
	if type(payload) ~= "table" or type(payload.text) ~= "string" then return end
	toastGeneration += 1
	local generation = toastGeneration
	toast.BackgroundColor3 = ({ danger = C.red, warning = C.orange, info = C.blue })[payload.tone] or C.green
	toastText.Text, toast.Visible = payload.text, true
	toast.BackgroundTransparency, toastText.TextTransparency = 0, 0
	task.delay(3.5, function()
		if generation ~= toastGeneration then return end
		TweenService:Create(toast, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(toastText, TweenInfo.new(0.2), { TextTransparency = 1 }):Play()
		task.wait(0.2)
		if generation == toastGeneration then toast.Visible = false end
	end)
end

local modalShade = make("TextButton", { Name = "ShopShade", Text = "", AutoButtonColor = false, Modal = true,
	BackgroundColor3 = C.line, BackgroundTransparency = 0.27, BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1), ZIndex = 30, Visible = false }, canvas)
local modal = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 31 }, modalShade)
skin(modal, C.panel)
local modalTitle = text(modal, "TUS AUTOS", 28, C.text, true)
modalTitle.Position, modalTitle.Size = UDim2.fromOffset(20, 10), UDim2.new(1, -88, 0, 36)
modalTitle.TextScaled, modalTitle.TextWrapped = true, false
make("UITextSizeConstraint", { MinTextSize = 13, MaxTextSize = 28 }, modalTitle)
local modalSubtitle = text(modal, "Compra autos y genera dinero por segundo.", 12, C.muted, false)
modalSubtitle.Position, modalSubtitle.Size = UDim2.fromOffset(20, 46), UDim2.new(1, -88, 0, 30)
local closeButton = button(modal, "X", C.red)
closeButton.Size, closeButton.Position = UDim2.fromOffset(43, 42), UDim2.new(1, -56, 0, 14)
local body = make("ScrollingFrame", { Name = "Cards", BackgroundTransparency = 1, BorderSizePixel = 0,
	Position = UDim2.fromOffset(0, 84), Size = UDim2.new(1, -8, 1, -100), CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 5, ScrollBarImageColor3 = C.blue, ZIndex = 32 }, modal)
make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 12),
	PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, body)
make("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, body)

local introShade = make("TextButton", { Text = "", AutoButtonColor = false, Modal = true, BackgroundColor3 = C.line,
	BackgroundTransparency = 0.2, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 80 }, canvas)
local introCard = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 81 }, introShade)
skin(introCard, C.panel)
local introScroll = make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0,
	Position = UDim2.fromOffset(22, 18), Size = UDim2.new(1, -44, 1, -96), CanvasSize = UDim2.fromOffset(0, 343),
	ScrollBarThickness = 3, ScrollBarImageColor3 = C.blue, ZIndex = 82 }, introCard)
local introTitle = text(introScroll, "DE LA MONEDA\nAL SUPERAUTO", 32, C.gold, true)
introTitle.Position, introTitle.Size = UDim2.fromOffset(0, 0), UDim2.new(1, -4, 0, 82)
local introSubtitle = text(introScroll, "Tu parcela. Tu colección. Cada renacimiento te hace más fuerte.", 14, C.muted, false)
introSubtitle.Position, introSubtitle.Size = UDim2.fromOffset(0, 88), UDim2.new(1, -4, 0, 44)
for index, step in ipairs({
	{ "MONEDAS", "Recoge monedas doradas caminando sobre ellas." },
	{ "TU PRIMER AUTO", "Compra un auto: empieza a generar dinero por segundo." },
	{ "CRECE", "Mejora ingresos, velocidad e imán. Desbloquea mejores autos." },
	{ "RENACE", "Reinicia tu negocio a cambio de un multiplicador permanente." },
}) do
	local y = 145 + (index - 1) * 49
	local badge = text(introScroll, string.format("%02d", index), 21, C.gold, true)
	badge.Position, badge.Size = UDim2.fromOffset(0, y), UDim2.fromOffset(36, 26)
	local title = text(introScroll, step[1], 12, C.text, true)
	title.Position, title.Size = UDim2.fromOffset(44, y), UDim2.new(1, -44, 0, 18)
	local detail = text(introScroll, step[2], 11, C.muted, false)
	detail.Position, detail.Size = UDim2.fromOffset(44, y + 18), UDim2.new(1, -48, 0, 31)
end
local introStart = button(introCard, "¡A POR MI PRIMER AUTO!", C.green)
introStart.Position, introStart.Size = UDim2.new(0, 22, 1, -66), UDim2.new(1, -44, 0, 43)
local introNote = text(introCard, "Compras con dinero del juego.", 9, C.muted, false)
introNote.Position, introNote.Size = UDim2.new(0, 16, 1, -20), UDim2.new(1, -32, 0, 13)
introNote.TextXAlignment = Enum.TextXAlignment.Center

local controls = nil
pcall(function() controls = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 5)):GetControls() end)
local function updateControls()
	if controls then
		if introOpen or currentPanel ~= nil then controls:Disable() else controls:Enable() end
	end
	navigation.Visible = currentPanel == nil and not introOpen
	footer.Visible = currentPanel == nil and not introOpen and not UserInputService.TouchEnabled
	helpButton.Visible = currentPanel == nil and not introOpen
end
local function clearBody()
	for _, child in ipairs(body:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
	rowReferences, panelParts = {}, nil
	body.CanvasPosition = Vector2.zero
end
local function newCard(order, height)
	local card = make("Frame", { Name = "Card", Size = UDim2.new(1, -28, 0, height), LayoutOrder = order, ZIndex = 33 }, body)
	skin(card, C.ink)
	return card
end
local carColors = { C.blue, C.green, C.orange, C.red, C.violet, C.gold }
local function drawCarIcon(parent, color)
	local holder = make("Frame", { BackgroundColor3 = C.raised, BorderSizePixel = 0, ZIndex = 34 }, parent)
	round(holder, 9)
	local carBody = make("Frame", { BackgroundColor3 = color, BorderSizePixel = 0,
		Position = UDim2.fromScale(0.1, 0.42), Size = UDim2.fromScale(0.8, 0.29), ZIndex = 35 }, holder)
	round(carBody, 5)
	stroke(carBody, C.line, 2)
	local roof = make("Frame", { BackgroundColor3 = color, BorderSizePixel = 0,
		Position = UDim2.fromScale(0.28, 0.24), Size = UDim2.fromScale(0.42, 0.25), ZIndex = 35 }, holder)
	round(roof, 5)
	local window = make("Frame", { BackgroundColor3 = Color3.fromRGB(159, 225, 255), BorderSizePixel = 0,
		Position = UDim2.fromScale(0.32, 0.28), Size = UDim2.fromScale(0.33, 0.14), ZIndex = 36 }, holder)
	round(window, 3)
	for _, x in ipairs({ 0.2, 0.65 }) do
		local wheel = make("Frame", { BackgroundColor3 = C.line, BorderSizePixel = 0,
			Position = UDim2.fromScale(x, 0.6), Size = UDim2.fromScale(0.18, 0.25), ZIndex = 36 }, holder)
		round(wheel, 100)
	end
	return holder
end
local previewLoads = {}
local previewWaiters = {}
local function startPreviewLoad(template)
	if previewLoads[template] then return end
	previewLoads[template] = "loading"
	task.spawn(function()
		local ok = pcall(function() ContentProvider:PreloadAsync({ template }) end)
		previewLoads[template] = if ok then "ready" else "failed"
		for _, record in ipairs(previewWaiters[template] or {}) do
			if record.viewport.Parent then
				record.viewport.Visible = ok
				record.label.Visible = not ok
				record.label.Text = "Vista previa"
			end
		end
		previewWaiters[template] = nil
	end)
end
-- Download visual assets in the background while the player reads the introduction.
local previewTemplates = packageRoot:FindFirstChild("CarTemplates")
if previewTemplates then
	for _, template in ipairs(previewTemplates:GetChildren()) do
		if template:IsA("Model") then startPreviewLoad(template) end
	end
end
local function addViewport(row, tier)
	local templates = packageRoot:FindFirstChild("CarTemplates")
	local template = templates and templates:FindFirstChild(tostring(tier.template or ""))
	if not template or not template:IsA("Model") then return end
	local viewport = make("ViewportFrame", { BackgroundColor3 = C.raised, BorderSizePixel = 0, Visible = false,
		Ambient = Color3.fromRGB(200, 210, 235), LightColor = Color3.new(1, 1, 1), LightDirection = Vector3.new(-1, -2, -1),
		Size = UDim2.fromScale(1, 1), ZIndex = 37 }, row.icon)
	round(viewport, 9)
	local world = make("WorldModel", {}, viewport)
	local visual = make("Model", { Name = "Preview" }, world)
	for _, descendant in ipairs(template:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local part = descendant:Clone()
			for _, child in ipairs(part:GetChildren()) do
				if not child:IsA("DataModelMesh") and not child:IsA("Decal") and not child:IsA("Texture") and not child:IsA("SurfaceAppearance") then child:Destroy() end
			end
			part.Anchored, part.CanCollide, part.Parent = true, false, visual
		end
	end
	if #visual:GetChildren() == 0 then viewport:Destroy() return end
	local bounds, size = visual:GetBoundingBox()
	local radius = math.max(size.X, size.Y, size.Z)
	local camera = make("Camera", { FieldOfView = 42 }, viewport)
	camera.CFrame = CFrame.lookAt(bounds.Position + Vector3.new(radius * 0.86, radius * 0.58, radius * 0.94), bounds.Position)
	viewport.CurrentCamera = camera
	if previewLoads[template] == "ready" then
		viewport.Visible = true
	else
		local loading = text(row.icon, "Cargando modelo...", 9, C.text, false)
		loading.Position, loading.Size = UDim2.new(0, 2, 1, -15), UDim2.new(1, -4, 0, 14)
		loading.TextXAlignment, loading.ZIndex = Enum.TextXAlignment.Center, 38
		if previewLoads[template] == "failed" then
			loading.Text = "Vista previa"
		else
			previewWaiters[template] = previewWaiters[template] or {}
			table.insert(previewWaiters[template], { viewport = viewport, label = loading })
			startPreviewLoad(template)
		end
	end
end
local function createCarRows(tiers)
	for order, tier in ipairs(tiers) do
		local card = newCard(order, if portrait then 189 else 146)
		local row = { card = card, id = tier.id }
		row.icon = drawCarIcon(card, carColors[((order - 1) % #carColors) + 1])
		row.name = text(card, tostring(tier.name or "Auto"), 22, C.text, true)
		row.name.TextScaled, row.name.TextWrapped = true, false
		make("UITextSizeConstraint", { MinTextSize = 12, MaxTextSize = 22 }, row.name)
		row.description = text(card, tostring(tier.description or ""), 11, C.muted, false)
		row.income = text(card, "", 16, C.green, true)
		row.lock = text(card, "", 10, C.gold, false)
		row.buy = button(card, "COMPRAR", C.green)
		row.buy.TextSize = 17
		row.buy.Activated:Connect(function() if row.buy.Active then sendAction("buyCar", row.id) end end)
		addViewport(row, tier)
		rowReferences[tostring(tier.id)] = row
	end
end
local function createUpgradeRows(upgrades)
	local glyphs = { income = "x$", speed = ">>", magnet = "U", coinValue = "$+" }
	for order, upgrade in ipairs(upgrades) do
		local card = newCard(order, if portrait then 172 else 132)
		local row = { card = card, id = upgrade.id }
		row.icon = text(card, glyphs[upgrade.id] or "+", 30, C.gold, true)
		row.icon.TextXAlignment = Enum.TextXAlignment.Center
		row.name = text(card, tostring(upgrade.name or "Mejora"), 21, C.text, true)
		row.name.TextScaled, row.name.TextWrapped = true, false
		make("UITextSizeConstraint", { MinTextSize = 11, MaxTextSize = 21 }, row.name)
		row.level = text(card, "", 12, C.blue, true)
		row.description = text(card, "", 12, C.muted, false)
		row.buy = button(card, "MEJORAR", C.green)
		row.buy.TextSize = 17
		row.buy.Activated:Connect(function() if row.buy.Active then sendAction("buyUpgrade", row.id) end end)
		rowReferences[tostring(upgrade.id)] = row
	end
end
local function createRebirthPanel()
	local card = newCard(1, 482)
	local title = text(card, "UN NUEVO COMIENZO", 25, C.gold, true)
	local benefit = text(card, "", 18, C.green, true)
	local requirements = text(card, "", 13, C.text, false)
	local resetBox = make("Frame", { BackgroundColor3 = C.raised, BorderSizePixel = 0, ZIndex = 34 }, card)
	round(resetBox, 10)
	local resetTitle = text(resetBox, "SE REINICIAN", 13, C.orange, true)
	resetTitle.Position, resetTitle.Size = UDim2.fromOffset(12, 6), UDim2.new(1, -24, 0, 22)
	local resetText = text(resetBox, "Dinero, autos activos y todas las mejoras.", 13, C.text, false)
	resetText.Position, resetText.Size = UDim2.fromOffset(12, 31), UDim2.new(1, -24, 0, 34)
	local keepBox = make("Frame", { BackgroundColor3 = C.raised, BorderSizePixel = 0, ZIndex = 34 }, card)
	round(keepBox, 10)
	local keepTitle = text(keepBox, "CONSERVAS", 13, C.green, true)
	keepTitle.Position, keepTitle.Size = UDim2.fromOffset(12, 6), UDim2.new(1, -24, 0, 22)
	local keepText = text(keepBox, "Renacimientos y colección de autos descubiertos.", 13, C.text, false)
	keepText.Position, keepText.Size = UDim2.fromOffset(12, 31), UDim2.new(1, -24, 0, 34)
	local warning = text(card, "", 12, C.gold, false)
	local confirm = button(card, "PREPARAR RENACIMIENTO", C.orange)
	local cancel = button(card, "VOLVER", C.blue)
	cancel.Visible = false
	panelParts = { card = card, title = title, benefit = benefit, requirements = requirements,
		resetBox = resetBox, keepBox = keepBox, warning = warning, confirm = confirm, cancel = cancel }
	confirm.Activated:Connect(function()
		local rebirth = currentState and currentState.rebirth
		if not confirm.Active or type(rebirth) ~= "table" or rebirth.canRebirth ~= true then return end
		if not confirmArmed then
			confirmArmed = true
			confirmSnapshot = { count = currentState.rebirths, cost = rebirth.cost, tier = rebirth.requiredTier }
			updatePanel()
			layout()
			return
		end
		if confirmSnapshot and confirmSnapshot.count == currentState.rebirths and confirmSnapshot.cost == rebirth.cost and confirmSnapshot.tier == rebirth.requiredTier then
			if sendAction("rebirth") then
				confirmArmed, confirmSnapshot = false, nil
				setButton(confirm, "ENVIANDO...", C.raised, false)
			end
		end
	end)
	cancel.Activated:Connect(function() confirmArmed, confirmSnapshot = false, nil updatePanel() layout() end)
end
local function rowsSignature(items)
	local ids = {}
	for _, item in ipairs(items) do table.insert(ids, tostring(item.id)) end
	return table.concat(ids, ",")
end
updatePanel = function()
	if not currentPanel then return end
	local state = currentState or {}
	if currentPanel == "cars" then
		local tiers = if type(state.carTiers) == "table" then state.carTiers else {}
		local signature = "cars:" .. rowsSignature(tiers)
		if panelSignature ~= signature then clearBody() createCarRows(tiers) panelSignature = signature end
		modalTitle.Text = "TUS AUTOS"
		modalSubtitle.Text = "Caja: " .. exactMoney(state.cash) .. "  ·  Los autos suman sus ingresos."
		for _, tier in ipairs(tiers) do
			local row = rowReferences[tostring(tier.id)]
			row.income.Text = "+" .. rateMoney(tier.income) .. "/s"
			local status = if tier.owned then "EN TU GARAJE" else (if number(tier.minRebirth) > 0 then "Requiere " .. shortNumber(tier.minRebirth) .. " renacimientos" else "Disponible desde el inicio")
			row.lock.Text = "PRECIO " .. money(tier.cost) .. " · " .. status
			row.description.Text = tostring(tier.description or "")
			if tier.discovered and not tier.owned then row.description.Text = "DESCUBIERTO · " .. tostring(tier.description or "") end
			if tier.owned then setButton(row.buy, "COMPRADO", C.blue, false)
			elseif tier.locked then setButton(row.buy, "BLOQUEADO", C.raised, false)
			elseif tier.canBuy then setButton(row.buy, "COMPRAR  " .. money(tier.cost), C.green, true)
			else setButton(row.buy, "FALTAN  " .. money(number(tier.cost) - number(state.cash)), C.orange, false) end
		end
	elseif currentPanel == "upgrades" then
		local upgrades = if type(state.upgrades) == "table" then state.upgrades else {}
		local signature = "upgrades:" .. rowsSignature(upgrades)
		if panelSignature ~= signature then clearBody() createUpgradeRows(upgrades) panelSignature = signature end
		modalTitle.Text = "MEJORA TU NEGOCIO"
		modalSubtitle.Text = "Caja: " .. exactMoney(state.cash) .. "  ·  Las mejoras se reinician al renacer."
		for _, upgrade in ipairs(upgrades) do
			local row = rowReferences[tostring(upgrade.id)]
			row.level.Text = "NIVEL " .. shortNumber(upgrade.level) .. " / " .. shortNumber(upgrade.maxLevel)
			if number(upgrade.level) < number(upgrade.maxLevel) then row.level.Text ..= " · " .. money(upgrade.cost) end
			row.description.Text = tostring(upgrade.description or "")
			if number(upgrade.level) >= number(upgrade.maxLevel) then setButton(row.buy, "AL MÁXIMO", C.blue, false)
			elseif upgrade.canBuy then setButton(row.buy, "MEJORAR  " .. money(upgrade.cost), C.green, true)
			else setButton(row.buy, "FALTAN  " .. money(number(upgrade.cost) - number(state.cash)), C.orange, false) end
		end
	else
		if panelSignature ~= "rebirth" then clearBody() createRebirthPanel() panelSignature = "rebirth" end
		local rebirth = if type(state.rebirth) == "table" then state.rebirth else {}
		if confirmArmed and (not confirmSnapshot or confirmSnapshot.count ~= state.rebirths or confirmSnapshot.cost ~= rebirth.cost or confirmSnapshot.tier ~= rebirth.requiredTier) then
			confirmArmed, confirmSnapshot = false, nil
		end
		modalTitle.Text = if confirmArmed then "CONFIRMA TU DECISIÓN" else "RENACIMIENTO"
		modalSubtitle.Text = "Renacimiento siguiente: " .. shortNumber(number(state.rebirths) + 1)
		panelParts.title.Text = if confirmArmed then "¿RENACER AHORA?" else "UN NUEVO COMIENZO"
		panelParts.benefit.Text = "BONIFICACIÓN PERMANENTE: " .. multiplier(rebirth.nextPermanentMultiplier or rebirth.nextMultiplier or 1)
		panelParts.requirements.Text = "Necesitas " .. exactMoney(rebirth.cost) .. " y el auto " .. tostring(rebirth.requiredTierName or "indicado") .. ".\nTu caja actual: " .. exactMoney(state.cash)
		panelParts.warning.Text = if confirmArmed then "Este reinicio no se puede deshacer. Confirma solo si quieres comenzar otra vez."
			else tostring(rebirth.reason or "Consigue el dinero y el auto requeridos para renacer.")
		panelParts.cancel.Visible = confirmArmed
		setButton(panelParts.confirm, if confirmArmed then "SÍ, RENACER Y REINICIAR" else "PREPARAR RENACIMIENTO",
			if confirmArmed then C.red else C.orange, rebirth.canRebirth == true)
	end
end
closePanels = function()
	currentPanel, panelSignature, confirmArmed, confirmSnapshot = nil, nil, false, nil
	modalShade.Visible = false
	updateControls()
end
openPanel = function(kind)
	if kind ~= "cars" and kind ~= "upgrades" and kind ~= "rebirth" then return end
	if introOpen then return end
	if currentPanel == kind then closePanels() return end
	currentPanel, panelSignature, confirmArmed, confirmSnapshot = kind, nil, false, nil
	modalShade.Visible = true
	updatePanel()
	layout()
	updateControls()
end

layout = function()
	local width, height = canvas.AbsoluteSize.X, canvas.AbsoluteSize.Y
	if width <= 0 or height <= 0 then return end
	portrait, smallHeight = width < 580, height < 520
	local margin = if width < 840 then 12 else 20
	local cashWidth = if portrait then math.floor((width - margin * 3) * 0.59) else 245
	local statsWidth = if portrait then width - margin * 3 - cashWidth else 235
	cashCard.Position, cashCard.Size = UDim2.fromOffset(margin, 8), UDim2.fromOffset(cashWidth, 98)
	statsCard.Position, statsCard.Size = UDim2.new(1, -statsWidth - margin, 0, 8), UDim2.fromOffset(statsWidth, 98)
	cashLabel.TextSize = if portrait then (if width < 350 then 27 else 31) else 36
	incomeLabel.TextSize, gameName.TextSize = if portrait then 11 else 13, if portrait then 10 else 12
	rebirthLabel.TextSize, multiplierLabel.TextSize, saveLabel.TextSize = if portrait then 12 else 17, if portrait then 12 else 15, if portrait then 9 else 10
	local touch = UserInputService.TouchEnabled
	local objectiveWidth = math.min(width - margin * 2, 520)
	if touch and smallHeight and not portrait then objectiveWidth = math.min(width - 106 - margin * 3, 520) end
	objectiveCard.Position = if touch and smallHeight and not portrait then UDim2.fromOffset(margin, 117) else UDim2.new(0.5, -objectiveWidth / 2, 0, 117)
	objectiveCard.Size = UDim2.fromOffset(objectiveWidth, if portrait then 72 else 64)
	objectiveText.TextSize = if portrait then 12 else 14
	if touch then
		navigation.Position = if smallHeight and not portrait then UDim2.new(1, -margin - 106, 0, 118) else UDim2.new(1, -margin - 106, 0.5, -36)
		navigation.Size = UDim2.fromOffset(106, 162)
		for index, key in ipairs(navKeys) do
			navButtons[key].Position, navButtons[key].Size = UDim2.fromOffset(0, (index - 1) * 55), UDim2.fromOffset(106, 44)
			navButtons[key].TextSize = 17
		end
	else
		local navWidth = math.min(width - margin * 2 - 12, 444)
		local buttonWidth = (navWidth - 24) / 3
		navigation.Position, navigation.Size = UDim2.new(0.5, -navWidth / 2, 1, -83), UDim2.fromOffset(navWidth, 51)
		for index, key in ipairs(navKeys) do
			navButtons[key].Position, navButtons[key].Size = UDim2.fromOffset((index - 1) * (buttonWidth + 12), 0), UDim2.fromOffset(buttonWidth, 46)
			navButtons[key].TextSize = if portrait then 16 else 20
		end
	end
	local footerWidth = math.min(width - margin * 2, 520)
	footer.Position, footer.Size = UDim2.new(0.5, -footerWidth / 2, 1, -21), UDim2.fromOffset(footerWidth, 15)
	footer.Text = if portrait then "1 · Autos    2 · Mejoras    3 · Renacer" else "1 · Autos    2 · Mejoras    3 · Renacer    E · Interactuar"
	footer.TextSize = if portrait then 10 else 11
	helpButton.Position = if touch then UDim2.fromOffset(margin, 204) else UDim2.new(0, margin, 1, -63)
	helpButton.Size = UDim2.fromOffset(37, 37)
	local toastWidth = math.min(width - margin * 2, 450)
	toast.Position, toast.Size = UDim2.new(0.5, -toastWidth / 2, 0, if portrait then 201 else 192), UDim2.fromOffset(toastWidth, 58)
	modal.Size = UDim2.fromOffset(math.min(width - 24, 760), math.min(height - 24, 592))
	modalTitle.TextSize, modalSubtitle.TextSize = if portrait then 22 else 28, if portrait then 10 else 12
	introCard.Size = UDim2.fromOffset(math.min(width - 24, 530), math.min(height - 24, 464))
	introTitle.TextSize, introStart.TextSize = if portrait then 27 else 32, if portrait then 17 else 20
	for _, row in pairs(rowReferences) do
		if currentPanel == "cars" then
			row.card.Size = UDim2.new(1, -28, 0, if portrait then 189 else 146)
			row.icon.Position, row.icon.Size = UDim2.fromOffset(12, 12), UDim2.fromOffset(if portrait then 71 else 105, if portrait then 62 else 91)
			local x = if portrait then 94 else 131
			row.name.Position, row.name.Size = UDim2.fromOffset(x, 10), UDim2.new(1, -x - 12, 0, 31)
			row.name.TextSize = if portrait then 18 else 22
			row.income.Position, row.income.Size = UDim2.fromOffset(x, 45), UDim2.new(1, -x - 12, 0, 25)
			row.income.TextSize = if portrait then 14 else 16
			row.description.Position, row.description.Size = UDim2.fromOffset(if portrait then 12 else 131, if portrait then 83 else 76), UDim2.new(1, if portrait then -24 else -350, 0, 31)
			row.lock.Position, row.lock.Size = UDim2.fromOffset(12, if portrait then 119 else 112), UDim2.new(1, if portrait then -24 else -220, 0, 21)
			row.buy.Position = if portrait then UDim2.fromOffset(12, 145) else UDim2.new(1, -205, 0, 91)
			row.buy.Size = if portrait then UDim2.new(1, -24, 0, 39) else UDim2.fromOffset(191, 39)
		else
			row.card.Size = UDim2.new(1, -28, 0, if portrait then 172 else 132)
			row.icon.Position, row.icon.Size = UDim2.fromOffset(12, 14), UDim2.fromOffset(48, 44)
			row.name.Position, row.name.Size = UDim2.fromOffset(72, 10), UDim2.new(1, -84, 0, 29)
			row.name.TextSize = if portrait then 18 else 21
			row.level.Position, row.level.Size = UDim2.fromOffset(72, 40), UDim2.new(1, -84, 0, 23)
			row.description.Position, row.description.Size = UDim2.fromOffset(14, 73), UDim2.new(1, if portrait then -28 else -228, 0, 37)
			row.buy.Position = if portrait then UDim2.fromOffset(14, 123) else UDim2.new(1, -205, 0, 72)
			row.buy.Size = if portrait then UDim2.new(1, -28, 0, 38) else UDim2.fromOffset(191, 38)
		end
	end
	if panelParts then
		local p, offset = panelParts, if portrait then 32 else 0
		p.title.Position, p.title.Size = UDim2.fromOffset(16, 12), UDim2.new(1, -32, 0, if portrait then 63 else 37)
		p.title.TextSize = if portrait then 23 else 25
		p.benefit.Position, p.benefit.Size = UDim2.fromOffset(16, 53 + offset), UDim2.new(1, -32, 0, 52)
		p.benefit.TextSize = if portrait then 16 else 18
		p.requirements.Position, p.requirements.Size = UDim2.fromOffset(16, 112 + offset), UDim2.new(1, -32, 0, if portrait then 74 else 51)
		local boxY = if portrait then 231 else 174
		p.resetBox.Position, p.resetBox.Size = UDim2.fromOffset(16, boxY), UDim2.new(1, -32, 0, 73)
		p.keepBox.Position, p.keepBox.Size = UDim2.fromOffset(16, boxY + 84), UDim2.new(1, -32, 0, 73)
		p.warning.Position, p.warning.Size = UDim2.fromOffset(16, boxY + 169), UDim2.new(1, -32, 0, 57)
		p.confirm.Position, p.confirm.Size = UDim2.fromOffset(16, boxY + 236), UDim2.new(1, -32, 0, 43)
		p.confirm.TextSize = if portrait then 15 else 18
		p.cancel.Position, p.cancel.Size = UDim2.fromOffset(16, boxY + 294), UDim2.new(1, -32, 0, 38)
		p.cancel.TextSize = 17
		p.card.Size = UDim2.new(1, -28, 0, boxY + (if confirmArmed then 345 else 292))
	end
end

for key, navButton in pairs(navButtons) do navButton.Activated:Connect(function() openPanel(key) end) end
closeButton.Activated:Connect(closePanels)
introStart.Activated:Connect(function()
	introOpen, introShade.Visible = false, false
	updateControls()
	showToast({ text = "Recoge las monedas doradas de tu parcela para comprar tu primer auto.", tone = "info" })
end)
helpButton.Activated:Connect(function()
	closePanels()
	introOpen, introShade.Visible = true, true
	updateControls()
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.Escape and currentPanel then closePanels() return end
	if introOpen then return end
	local keys = { [Enum.KeyCode.One] = "cars", [Enum.KeyCode.Two] = "upgrades", [Enum.KeyCode.Three] = "rebirth" }
	if keys[input.KeyCode] then openPanel(keys[input.KeyCode]) end
end)
local function renderState(state)
	if type(state) ~= "table" or state.mode ~= "tycoon" then return end
	local previousRebirths = currentState and number(currentState.rebirths)
	currentState = state
	if previousRebirths and number(state.rebirths) > previousRebirths and currentPanel == "rebirth" then closePanels() end
	cashLabel.Text, incomeLabel.Text = money(state.cash), "+" .. rateMoney(state.incomePerSecond) .. " / SEGUNDO"
	rebirthLabel.Text = if portrait then "RENACER  " .. shortNumber(state.rebirths) else "RENACIMIENTOS  " .. shortNumber(state.rebirths)
	multiplierLabel.Text = "INGRESOS " .. multiplier(state.multiplier or 1)
	objectiveText.Text = tostring(state.objective or "Recoge monedas y compra tu primer auto.")
	local labels = { session = "Sesión de prueba", saved = "Progreso guardado", loading = "Cargando progreso...", unavailable = "Sin guardado" }
	saveLabel.Text, saveLabel.TextColor3 = labels[state.saveStatus] or "Guardado pendiente", if state.saveStatus == "unavailable" then C.gold else C.muted
	updatePanel()
	layout()
end
stateRemote.OnClientEvent:Connect(renderState)
notifyRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	if payload.tone == "coin" or payload.kind == "coin" then showCoin(payload.amount) return end
	if payload.openPanel then openPanel(payload.openPanel) end
	if payload.kind == "rebirth" then closePanels() end
	showToast(payload)
end)
canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
layout()
updateControls()
actionRemote:FireServer({ type = "sync" })
