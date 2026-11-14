--!strict
-- Prefer the bundled, sanitized Roblox Creator Store vehicles. The part-built
-- fallback keeps development checkouts playable when templates are unavailable.
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")

local World = {}
World.__index = World

local COLORS = {
	Dark = Color3.fromRGB(17, 24, 31),
	Metal = Color3.fromRGB(136, 159, 166),
	Glass = Color3.fromRGB(105, 165, 181),
	Teal = Color3.fromRGB(55, 225, 190),
	Amber = Color3.fromRGB(255, 190, 79),
	Warm = Color3.fromRGB(255, 239, 184),
}

local function makePart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Shape = shape or Enum.PartType.Block
	part.Anchored = true
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function textFace(part: BasePart, text: string, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(800, 220)
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui
end

local function normalizeAnomaly(anomaly: any): string?
	if type(anomaly) == "table" then
		anomaly = anomaly.id or anomaly.kind or anomaly.type
	end
	if type(anomaly) ~= "string" or anomaly == "" or anomaly == "none" or anomaly == "normal" then
		return nil
	end
	local key = string.lower(string.gsub(anomaly, "[%s_%-]", ""))
	local aliases = {
		missingwheel = "missingWheel", nowheel = "missingWheel", wheel = "missingWheel",
		redlights = "redLights", redheadlights = "redLights", lights = "redLights",
		floating = "floating", hovering = "floating", float = "floating",
		ghost = "ghost", ghostcar = "ghost", transparent = "ghost",
	}
	return aliases[key] or anomaly
end

local WHEEL_ALIASES = {
	fl = "FL", frontleft = "FL", frontleftwheel = "FL", frontleftrim = "FL", frontlefthub = "FL",
	fr = "FR", frontright = "FR", frontrightwheel = "FR", frontrightrim = "FR", frontrighthub = "FR",
	rl = "RL", rearleft = "RL", rearleftwheel = "RL", rearleftrim = "RL", rearlefthub = "RL",
	rr = "RR", rearright = "RR", rearrightwheel = "RR", rearrightrim = "RR", rearrighthub = "RR",
}

local function cleanName(name: string): string
	return string.lower(string.gsub(name, "[%s_%-]", ""))
end

local function wheelGroup(object: BasePart, model: Model): string?
	local current: Instance? = object
	while current and current ~= model do
		local role = current:GetAttribute("VehicleRole")
		local key = cleanName(if type(role) == "string" then role else current.Name)
		if WHEEL_ALIASES[key] then return WHEEL_ALIASES[key] end
		current = current.Parent
	end
	-- Some imported vehicles have individually named tires rather than groups.
	local name = cleanName(object.Name)
	if string.find(name, "wheel", 1, true) or string.find(name, "tire", 1, true) or string.find(name, "tyre", 1, true) then
		local position = model:GetPivot():PointToObjectSpace(object.Position)
		return if position.Z < 0 then (if position.X < 0 then "FL" else "FR") else (if position.X < 0 then "RL" else "RR")
	end
	return nil
end

local function isHeadlight(object: BasePart): boolean
	local role = object:GetAttribute("VehicleRole")
	local key = cleanName(if type(role) == "string" then role else object.Name)
	return string.find(key, "headlight", 1, true) ~= nil or key == "lightwhite"
end

local function isPaintable(object: BasePart): boolean
	local marker = object:FindFirstChild("Paintable")
	if object:GetAttribute("Paintable") == true or (marker and marker:IsA("BoolValue") and marker.Value) then
		return true
	end
	local key = cleanName(object.Name)
	return key == "body" or key == "bodymesh" or key == "paint"
end

local function spawnTemplate(customer: any, base: CFrame, bodyColor: Color3): Model?
	local templates = ServerStorage:FindFirstChild("VehicleTemplates")
	if not templates then return nil end
	local templateName = if type(customer.template) == "string" then customer.template else "Sedan"
	local template = templates:FindFirstChild(templateName) or templates:FindFirstChild("Sedan")
	if not template or not template:IsA("Model") then return nil end
	local model = template:Clone()
	model.Name = "CustomerCar"
	model:SetAttribute("VehicleTemplate", template.Name)
	local root = model:FindFirstChild("VehicleRoot")
	if root and root:IsA("BasePart") then model.PrimaryPart = root end
	for _, object in model:GetDescendants() do
		if object:IsA("BasePart") then
			object.Anchored = true
			object.CanCollide = false
			object.CanTouch = false
			if isPaintable(object) then object.Color = bodyColor end
		elseif object:IsA("Light") then
			object.Brightness = math.min(object.Brightness, .25)
		end
	end
	-- Template origin is normalized to its ground plane by the asset importer.
	model:PivotTo(CFrame.new(base.X, .55, base.Z))
	local bounds, size = model:GetBoundingBox()
	local plate = makePart(model, "LicensePlate", Vector3.new(1.75, .44, .07),
		CFrame.new(base.X, .55 + math.min(1.1, size.Y * .28), bounds.Z - size.Z / 2 - .075),
		Color3.fromRGB(211, 216, 197))
	textFace(plate, tostring(customer.plate or ("MN-" .. tostring(customer.id or "024"))), COLORS.Dark)
	makePart(model, "OilLeak", Vector3.new(2, .025, 1.3), CFrame.new(base.X + .9, .57, base.Z + 2.2), Color3.fromRGB(30, 35, 30))
	model.Parent = workspace
	return model
end

local function registerCar(self: any, model: Model, anomaly: any): Model
	self.Car = model
	self.car = model
	self.CarParts = {}
	self.WheelGroups = { FL = {}, FR = {}, RL = {}, RR = {} }
	self.Headlights = {}
	for _, object in model:GetDescendants() do
		if object:IsA("BasePart") then
			self.CarParts[object] = {
				Transparency = object.Transparency, Color = object.Color,
				CFrame = object.CFrame, Material = object.Material,
			}
			if object.Name ~= "VehicleRoot" then
				local group = wheelGroup(object, model)
				if group then table.insert(self.WheelGroups[group], object) end
				if isHeadlight(object) then table.insert(self.Headlights, object) end
			end
		end
	end
	self:SetCarState(anomaly)
	return model
end

function World.new()
	local self: any = setmetatable({}, World)
	local map = workspace:FindFirstChild("MidnightGarage")
	if not map then
		map = Instance.new("Model")
		map.Name = "MidnightGarage"
		map.Parent = workspace
		local floor = makePart(map, "GarageFloor", Vector3.new(40, 1, 36), CFrame.new(0, 0, 2), Color3.fromRGB(80, 95, 99), Enum.Material.Concrete)
		floor.CanCollide = true
		local anchors = {
			BayPosition = Vector3.new(0, 2, 0), RepairWheel = Vector3.new(-4.6, 2, 0),
			RepairOil = Vector3.new(4.4, 2, 3), RepairLights = Vector3.new(0, 2, -6.5),
			InspectionPoint = Vector3.new(12, 2.8, -7), UpgradePoint = Vector3.new(12, 3.8, 9),
			RejectPoint = Vector3.new(8, 3, -11), DispatchPoint = Vector3.new(12, 3, -11),
			DriveExit = Vector3.new(0, 2, -48),
		}
		for name, pos in anchors do
			local marker = makePart(map, name, Vector3.one * .2, CFrame.new(pos), COLORS.Teal)
			marker.Transparency = 1
		end
	end
	self.Map = map
	self.map = map
	self.refs = {}
	for _, name in { "BayPosition", "RepairWheel", "RepairOil", "RepairLights", "InspectionPoint", "UpgradePoint", "RejectPoint", "DispatchPoint", "DriveExit", "Shutter" } do
		self.refs[name] = map:FindFirstChild(name)
		self[name] = self.refs[name]
	end
	self.Car = nil
	self.car = nil
	self.CarParts = {}
	self.WheelGroups = { FL = {}, FR = {}, RL = {}, RR = {} }
	self.Headlights = {}
	self.Anomaly = nil
	self.CarBase = CFrame.new(0, 2, 0)
	self.DoorClosed = false
	self:SetupAtmosphere()
	return self
end

function World.SetupAtmosphere(self: any)
	Lighting.ClockTime = .5
	Lighting.Brightness = 1.5
	Lighting.Ambient = Color3.fromRGB(36, 53, 67)
	Lighting.OutdoorAmbient = Color3.fromRGB(46, 65, 81)
	Lighting.FogColor = Color3.fromRGB(22, 42, 55)
	Lighting.FogStart = 80
	Lighting.FogEnd = 230
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if not bloom then
		bloom = Instance.new("BloomEffect")
		bloom.Name = "MidnightBloom"
		bloom.Intensity = .2
		bloom.Size = 24
		bloom.Threshold = 1.7
		bloom.Parent = Lighting
	end
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if not sky then
		sky = Instance.new("Sky")
		sky.StarCount = 1600
		sky.Parent = Lighting
	end
end

function World.SpawnCar(self: any, customer: any): Model
	self:RemoveCar()
	self:SetDoor(false)
	local base = if self.refs.BayPosition then self.refs.BayPosition.CFrame else CFrame.new(0, 2, 0)
	self.CarBase = base
	local bodyColor = customer.color
	if typeof(bodyColor) ~= "Color3" then
		if type(bodyColor) == "table" then
			bodyColor = Color3.fromRGB(bodyColor[1] or 71, bodyColor[2] or 148, bodyColor[3] or 151)
		else
			bodyColor = Color3.fromRGB(75, 141, 157)
		end
	end
	local imported = spawnTemplate(customer, base, bodyColor)
	if imported then return registerCar(self, imported, customer.anomaly) end
	local model = Instance.new("Model")
	model.Name = "CustomerCar"
	local function part(name: string, pos: Vector3, size: Vector3, color: Color3, material: Enum.Material?, rotation: CFrame?, shape: Enum.PartType?): Part
		return makePart(model, name, size, base * CFrame.new(pos) * (rotation or CFrame.identity), color, material, shape)
	end
	local chassis = part("Chassis", Vector3.new(0, -.1, 0), Vector3.new(6.5, 1.1, 11.6), COLORS.Dark, Enum.Material.Metal)
	model.PrimaryPart = chassis
	part("Body", Vector3.new(0, .5, 0), Vector3.new(6.7, 1.25, 11.6), bodyColor)
	part("Hood", Vector3.new(0, 1.23, -3.45), Vector3.new(6.3, .33, 4.1), bodyColor)
	part("Trunk", Vector3.new(0, 1.22, 4.2), Vector3.new(6.3, .3, 2.5), bodyColor)
	part("Roof", Vector3.new(0, 3.15, .25), Vector3.new(5.8, .3, 4.6), bodyColor)
	part("Cabin", Vector3.new(0, 2.15, .3), Vector3.new(5.5, 1.8, 4.7), COLORS.Dark)
	local windshield = part("Windshield", Vector3.new(0, 2.15, -2.17), Vector3.new(5.3, 1.65, .17), COLORS.Glass, Enum.Material.Glass, CFrame.Angles(math.rad(-14), 0, 0))
	windshield.Transparency = .28
	local rear = part("RearWindow", Vector3.new(0, 2.15, 2.7), Vector3.new(5.2, 1.55, .16), COLORS.Glass, Enum.Material.Glass, CFrame.Angles(math.rad(12), 0, 0))
	rear.Transparency = .3
	for _, side in { -1, 1 } do
		local x = side * 2.83
		for _, z in { -1.1, 1.2 } do
			local window = part("SideWindow", Vector3.new(x, 2.18, z), Vector3.new(.15, 1.5, 1.9), COLORS.Glass, Enum.Material.Glass)
			window.Transparency = .3
		end
		part("DoorPillar", Vector3.new(x, 2.15, .08), Vector3.new(.21, 1.65, .17), bodyColor)
		part("DoorHandle", Vector3.new(side * 3.43, 1.1, .7), Vector3.new(.12, .16, .7), COLORS.Metal, Enum.Material.Metal)
		part("SideMirror", Vector3.new(side * 3.7, 1.8, -1.85), Vector3.new(.7, .5, .7), bodyColor)
		part("SideSill", Vector3.new(side * 3.4, -.1, 0), Vector3.new(.18, .24, 8.3), COLORS.Metal, Enum.Material.Metal)
		for _, z in { -3.65, 3.65 } do
			local prefix = if side == -1 and z < 0 then "FrontLeft" elseif side == 1 and z < 0 then "FrontRight" elseif side == -1 then "RearLeft" else "RearRight"
			part(prefix .. "Wheel", Vector3.new(side * 3.18, -.35, z), Vector3.new(.95, 2.5, 2.5), COLORS.Dark, Enum.Material.SmoothPlastic, nil, Enum.PartType.Cylinder)
			part(prefix .. "Rim", Vector3.new(side * 3.69, -.35, z), Vector3.new(.08, 1.5, 1.5), COLORS.Metal, Enum.Material.Metal, nil, Enum.PartType.Cylinder)
			part(prefix .. "Hub", Vector3.new(side * 3.75, -.35, z), Vector3.new(.1, .45, .45), bodyColor, Enum.Material.Metal, nil, Enum.PartType.Cylinder)
		end
	end
	part("FrontBumper", Vector3.new(0, .15, -5.94), Vector3.new(6.8, .42, .38), COLORS.Metal, Enum.Material.Metal)
	part("BackBumper", Vector3.new(0, .15, 5.94), Vector3.new(6.8, .42, .38), COLORS.Metal, Enum.Material.Metal)
	part("Grille", Vector3.new(0, .65, -5.88), Vector3.new(2.2, .6, .1), COLORS.Dark)
	local plate = part("LicensePlate", Vector3.new(0, .1, -6.15), Vector3.new(1.75, .48, .07), Color3.fromRGB(211, 216, 197))
	textFace(plate, tostring(customer.plate or ("MN-" .. tostring(customer.id or "024"))), COLORS.Dark)
	for _, x in { -2.25, 2.25 } do
		local lamp = part("Headlight", Vector3.new(x, .7, -5.88), Vector3.new(1.45, .6, .15), COLORS.Warm, Enum.Material.Neon)
		local glow = Instance.new("PointLight")
		glow.Color = COLORS.Warm
		glow.Range = 13
		glow.Brightness = .25
		glow.Parent = lamp
		part("TailLight", Vector3.new(x, .7, 5.88), Vector3.new(1.35, .5, .15), Color3.fromRGB(190, 53, 49), Enum.Material.Neon)
	end
	part("OilLeak", Vector3.new(.9, -1.43, 2.2), Vector3.new(2, .025, 1.3), Color3.fromRGB(30, 35, 30))
	model.Parent = workspace
	return registerCar(self, model, customer.anomaly)
end

function World.SetCarState(self: any, rawAnomaly: any)
	if not self.Car then return end
	for object, original in self.CarParts do
		if object.Parent then
			object.Transparency = original.Transparency
			object.Color = original.Color
			object.CFrame = original.CFrame
			object.Material = original.Material
			local glow = object:FindFirstChildOfClass("PointLight")
			if glow then glow.Color = original.Color end
		end
	end
	local anomaly = normalizeAnomaly(rawAnomaly)
	self.Anomaly = anomaly
	if anomaly == "missingWheel" then
		for _, wheel in self.WheelGroups.FL do
			wheel.Transparency = 1
		end
	elseif anomaly == "redLights" then
		for _, object in self.Headlights do
			object.Color = Color3.fromRGB(255, 35, 58)
			object.Material = Enum.Material.Neon
			for _, glow in object:GetDescendants() do
				if glow:IsA("Light") then glow.Color = object.Color end
			end
		end
	elseif anomaly == "floating" then
		for object, original in self.CarParts do
			if object.Parent then object.CFrame = original.CFrame + Vector3.new(0, 2.2, 0) end
		end
	elseif anomaly == "ghost" then
		for object, _ in self.CarParts do
			if object.Parent and object.Name ~= "VehicleRoot" then
				object.Transparency = math.max(.68, object.Transparency)
				object.Color = Color3.fromRGB(156, 244, 226)
			end
		end
	end
end

function World.Repair(self: any, kind: string)
	if not self.Car then return end
	local key = string.lower(kind)
	if key == "oil" or key == "aceite" then
		local leak = self.Car:FindFirstChild("OilLeak")
		if leak and leak:IsA("BasePart") then leak.Transparency = 1 end
	elseif key == "wheel" or key == "rueda" or key == "neumatico" or key == "tire" then
		for _, object in self.WheelGroups.FR do
			local name = cleanName(object.Name)
			if string.find(name, "rim", 1, true) or string.find(name, "trim", 1, true) then object.Color = COLORS.Teal end
		end
	elseif key == "lights" or key == "luces" then
		for _, object in self.Headlights do
			if self.Anomaly ~= "redLights" then
				object.Color = COLORS.Warm
			end
		end
	end
	self:Flash(COLORS.Teal)
end

function World.RemoveCar(self: any)
	if self.Car then self.Car:Destroy() end
	self.Car = nil
	self.car = nil
	self.CarParts = {}
	self.WheelGroups = { FL = {}, FR = {}, RL = {}, RR = {} }
	self.Headlights = {}
	self.Anomaly = nil
end

function World.SetDoor(self: any, closed: boolean)
	self.DoorClosed = closed
	local door = self.refs.Shutter
	if door and door:IsA("BasePart") then
		door.Transparency = if closed then 0 else 1
		door.CanCollide = closed
		door.CFrame = CFrame.new(-.5, if closed then 5.25 else 15.3, -13.2)
	end
	local button = self.Map:FindFirstChild("ShutterButton")
	if button and button:IsA("BasePart") then
		button.Color = if closed then COLORS.Amber else Color3.fromRGB(226, 77, 74)
	end
end

function World.Flash(self: any, color: Color3?)
	local panel = self.Map:FindFirstChild("DispatchLED")
	if panel and panel:IsA("BasePart") then
		panel.Color = color or COLORS.Teal
		local light = panel:FindFirstChildOfClass("PointLight")
		if not light then
			light = Instance.new("PointLight")
			light.Range = 12
			light.Parent = panel
		end
		light.Color = panel.Color
		light.Brightness = 2
		TweenService:Create(light, TweenInfo.new(.8), { Brightness = 0 }):Play()
	end
end

return World
