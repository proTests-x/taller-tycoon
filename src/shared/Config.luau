--!nonstrict
-- Pure configuration: no Roblox instances or services.
local Config = {
	GameTitle = "TALLER TYCOON",
	Subtitle = "De la primera moneda a tu colección de superautos.",
	Version = "0.3.0", ProfileVersion = 2,
	MaxPlayers = 4, MaxPlots = 4, StartingCash = 0, MaxCash = 1e15,
	BaseCoinValue = 10, CoinsPerPlot = 12, CoinSpawnCount = 12, CoinCooldown = 10,
	BaseWalkSpeed = 16, BasePickupRadius = 8, BaseMagnetRadius = 0, AutosaveInterval = 45,
	RebirthBaseCost = 12000, RebirthCostPower = 1.35, RebirthMultiplierBonus = 0.75,
	CarPriceGrowthPerRebirth = 0.20,
	CarTiers = {
		{ id = 1, name = "Sedán usado", cost = 120, income = 1, minRebirth = 0, template = "Sedan", description = "Tu primer auto. Produce dinero cada segundo.", color = { 147, 161, 174 } },
		{ id = 2, name = "Sedán restaurado", cost = 700, income = 6, minRebirth = 0, template = "Sedan", description = "Una restauración completa para aumentar tus ingresos.", color = { 66, 186, 197 } },
		{ id = 3, name = "Pickup de trabajo", cost = 3500, income = 24, minRebirth = 0, template = "Pickup", description = "Completa tu primer garaje y prepara el primer renacimiento.", color = { 238, 159, 72 } },
		{ id = 4, name = "Deportivo GT", cost = 14000, income = 65, minRebirth = 1, template = "SportsCar", description = "Se desbloquea después de tu primer renacimiento.", color = { 233, 82, 116 } },
		{ id = 5, name = "Deportivo neón", cost = 42000, income = 180, minRebirth = 1, template = "SportsCar", description = "Una edición especial para tu segundo ciclo.", color = { 130, 86, 255 }, neon = true },
		{ id = 6, name = "Superauto Eclipse", cost = 140000, income = 550, minRebirth = 2, template = "Supercar", description = "La joya de la colección. Requiere dos renacimientos.", color = { 55, 221, 175 } },
	},
	Upgrades = {
		{ id = "income", name = "Multiplicador de dinero", baseCost = 200, costGrowth = 1.75, maxLevel = 8, amount = 0.25, description = "+25% al multiplicador de monedas y autos por nivel." },
		{ id = "speed", name = "Zapatillas turbo", baseCost = 75, costGrowth = 1.85, maxLevel = 5, amount = 2, description = "+2 de velocidad al caminar por nivel." },
		{ id = "magnet", name = "Imán de monedas", baseCost = 100, costGrowth = 2, maxLevel = 4, amount = 3, description = "Recoge monedas automáticamente a 3 studs extra por nivel." },
		{ id = "coinValue", name = "Monedas premium", baseCost = 150, costGrowth = 2, maxLevel = 4, amount = 0.25, description = "+25% al valor base de cada moneda por nivel." },
	},
	Colors = {
		Background = { 12, 20, 29 }, Panel = { 20, 31, 42 }, Text = { 239, 242, 235 },
		Muted = { 158, 176, 186 }, Accent = { 72, 220, 192 }, Warning = { 255, 191, 96 }, Danger = { 255, 107, 109 },
	},
	Controls = "WASD: moverte · camina sobre monedas · E: interactuar · móvil: toca los avisos",
}
return Config
