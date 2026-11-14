--!nonstrict
-- Pure economy: no Roblox globals, clock, randomness, network or persistence.
-- local econ = Economy.new(Config); local profile = econ.NewProfile()
-- Mutating purchases return success, message. Failures leave the profile intact.
local Economy = {}
local function finite(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function number(value, minimum, maximum, fallback)
	return finite(value) and math.clamp(value, minimum, maximum) or fallback
end
local function integer(value, minimum, maximum, fallback)
	return math.floor(number(value, minimum, maximum, fallback))
end
local function includes(values, value)
	for _, existing in ipairs(values) do
		if existing == value then return true end
	end
	return false
end
local function rounded(value)
	return math.floor(value * 100 + 0.5) / 100
end

function Economy.new(config)
	assert(type(config) == "table" and #config.CarTiers > 0, "Economy requires a valid Config")
	local api, tiers, upgrades = {}, {}, {}
	for _, tier in ipairs(config.CarTiers) do tiers[tier.id] = tier end
	for _, upgrade in ipairs(config.Upgrades) do upgrades[upgrade.id] = upgrade end
	local maxCash = config.MaxCash or 1e15

	function api.NewProfile()
		local levels = {}
		for _, upgrade in ipairs(config.Upgrades) do levels[upgrade.id] = 0 end
		return { version = config.ProfileVersion, cash = config.StartingCash, rebirths = 0, ownedCars = {},
			discoveredCars = {}, upgrades = levels, coinsCollected = 0, totalCoinsCollected = 0, lifetimeCash = 0 }
	end

	function api.Sanitize(raw)
		local profile = api.NewProfile()
		if type(raw) ~= "table" then return profile end
		profile.cash = number(raw.cash, 0, maxCash, config.StartingCash)
		profile.rebirths = integer(raw.rebirths, 0, 1000000, 0)
		profile.coinsCollected = integer(raw.coinsCollected, 0, maxCash, 0)
		profile.totalCoinsCollected = integer(raw.totalCoinsCollected, profile.coinsCollected, maxCash, profile.coinsCollected)
		profile.lifetimeCash = number(raw.lifetimeCash, profile.cash, maxCash, profile.cash)
		local rawOwned = type(raw.ownedCars) == "table" and raw.ownedCars or {}
		for _, tier in ipairs(config.CarTiers) do
			if tier.minRebirth > profile.rebirths or not includes(rawOwned, tier.id) then break end
			table.insert(profile.ownedCars, tier.id)
		end
		local rawBook = type(raw.discoveredCars) == "table" and raw.discoveredCars or {}
		for _, tier in ipairs(config.CarTiers) do
			if includes(rawBook, tier.id) or includes(profile.ownedCars, tier.id) then
				table.insert(profile.discoveredCars, tier.id)
			end
		end
		if type(raw.upgrades) == "table" then
			for _, upgrade in ipairs(config.Upgrades) do
				profile.upgrades[upgrade.id] = integer(raw.upgrades[upgrade.id], 0, upgrade.maxLevel, 0)
			end
		end
		return profile
	end

	function api.PermanentMultiplier(profile)
		return 1 + profile.rebirths * config.RebirthMultiplierBonus
	end
	function api.Multiplier(profile)
		return api.PermanentMultiplier(profile) * (1 + (profile.upgrades.income or 0) * upgrades.income.amount)
	end
	function api.CarIncome(profile)
		local base = 0
		for _, id in ipairs(profile.ownedCars) do
			if tiers[id] then base += tiers[id].income end
		end
		return base * api.Multiplier(profile)
	end
	function api.CoinValue(profile)
		return math.max(1, math.floor(config.BaseCoinValue * api.Multiplier(profile)
			* (1 + (profile.upgrades.coinValue or 0) * upgrades.coinValue.amount)))
	end
	function api.WalkSpeed(profile)
		return config.BaseWalkSpeed + (profile.upgrades.speed or 0) * upgrades.speed.amount
	end
	function api.MagnetRadius(profile)
		return config.BaseMagnetRadius + (profile.upgrades.magnet or 0) * upgrades.magnet.amount
	end
	function api.Price(profile, id)
		local tier = tiers[id]
		if not tier then return nil end
		return math.min(maxCash, math.floor(tier.cost * (1 + profile.rebirths * config.CarPriceGrowthPerRebirth) + 0.5))
	end
	api.CarPrice = api.Price
	function api.UpgradePrice(profile, id)
		local upgrade = upgrades[id]
		if not upgrade then return nil end
		local level = profile.upgrades[id] or 0
		if level >= upgrade.maxLevel then return 0 end
		return math.min(maxCash, math.floor(upgrade.baseCost * upgrade.costGrowth ^ level + 0.5))
	end

	local function canBuyCar(profile, id)
		if not finite(id) or id % 1 ~= 0 or not tiers[id] then return false, "Ese auto no existe." end
		local tier = tiers[id]
		if includes(profile.ownedCars, id) then return false, "Ya tienes este auto." end
		if tier.minRebirth > profile.rebirths then return false, "Necesitas " .. tier.minRebirth .. " renacimientos para este auto." end
		if id > 1 and not includes(profile.ownedCars, id - 1) then return false, "Compra primero el auto anterior." end
		if profile.cash < api.Price(profile, id) then return false, "Te falta dinero para este auto." end
		return true, ""
	end
	api.CanBuyCar = canBuyCar
	function api.BuyCar(profile, id)
		local allowed, reason = canBuyCar(profile, id)
		if not allowed then return false, reason end
		profile.cash -= api.Price(profile, id)
		table.insert(profile.ownedCars, id)
		if not includes(profile.discoveredCars, id) then table.insert(profile.discoveredCars, id) end
		return true, tiers[id].name .. " añadido a tu garaje."
	end
	function api.BuyUpgrade(profile, id)
		if type(id) ~= "string" or #id > 24 or not upgrades[id] then return false, "Esa mejora no existe." end
		local cost = api.UpgradePrice(profile, id)
		if cost == 0 then return false, "Esta mejora ya está al máximo." end
		if profile.cash < cost then return false, "Te falta dinero para esta mejora." end
		profile.cash -= cost
		profile.upgrades[id] += 1
		return true, upgrades[id].name .. " · nivel " .. profile.upgrades[id] .. "."
	end

	local function credit(profile, amount)
		amount = math.min(amount, maxCash - profile.cash)
		profile.cash += amount
		profile.lifetimeCash = math.min(maxCash, profile.lifetimeCash + amount)
		return amount
	end
	function api.CollectCoin(profile)
		profile.coinsCollected = math.min(maxCash, profile.coinsCollected + 1)
		profile.totalCoinsCollected = math.min(maxCash, profile.totalCoinsCollected + 1)
		return credit(profile, api.CoinValue(profile))
	end
	function api.Tick(profile, seconds)
		return credit(profile, api.CarIncome(profile) * number(seconds, 0, 60, 0))
	end

	function api.RebirthRequirements(profile)
		local required = config.CarTiers[1]
		for _, tier in ipairs(config.CarTiers) do
			if tier.minRebirth <= profile.rebirths then required = tier end
		end
		return {
			cost = math.min(maxCash, math.floor(config.RebirthBaseCost * (1 + profile.rebirths) ^ config.RebirthCostPower + 0.5)),
			requiredTier = required.id, requiredTierName = required.name,
			nextMultiplier = 1 + (profile.rebirths + 1) * config.RebirthMultiplierBonus,
			nextPermanentMultiplier = 1 + (profile.rebirths + 1) * config.RebirthMultiplierBonus,
		}
	end
	function api.CanRebirth(profile)
		local requirement = api.RebirthRequirements(profile)
		if not includes(profile.ownedCars, requirement.requiredTier) then
			return false, "Consigue " .. requirement.requiredTierName .. " para renacer.", requirement
		end
		if profile.cash < requirement.cost then
			return false, "Ahorra $" .. requirement.cost .. " en tu cartera para renacer.", requirement
		end
		return true, "Todo listo para renacer.", requirement
	end
	function api.Rebirth(profile)
		local allowed, reason = api.CanRebirth(profile)
		if not allowed then return false, reason end
		profile.rebirths += 1
		profile.cash, profile.ownedCars, profile.coinsCollected = 0, {}, 0
		for _, upgrade in ipairs(config.Upgrades) do profile.upgrades[upgrade.id] = 0 end
		return true, "Renacimiento " .. profile.rebirths .. ": multiplicador permanente ×" .. api.PermanentMultiplier(profile) .. "."
	end

	function api.PublicState(profile)
		local cars = {}
		for _, tier in ipairs(config.CarTiers) do
			local canBuy, reason = canBuyCar(profile, tier.id)
			table.insert(cars, {
				id = tier.id, name = tier.name, cost = api.Price(profile, tier.id), income = rounded(tier.income * api.Multiplier(profile)),
				baseIncome = tier.income, minRebirth = tier.minRebirth, owned = includes(profile.ownedCars, tier.id),
				locked = tier.minRebirth > profile.rebirths, canBuy = canBuy, reason = reason, template = tier.template,
				description = tier.description, discovered = includes(profile.discoveredCars, tier.id), color = tier.color, neon = tier.neon or false,
			})
		end
		local publicUpgrades = {}
		for _, upgrade in ipairs(config.Upgrades) do
			local cost = api.UpgradePrice(profile, upgrade.id)
			table.insert(publicUpgrades, { id = upgrade.id, name = upgrade.name, level = profile.upgrades[upgrade.id], maxLevel = upgrade.maxLevel,
				cost = cost, description = upgrade.description, canBuy = cost > 0 and profile.cash >= cost })
		end
		local canRebirth, reason, requirement = api.CanRebirth(profile)
		requirement.canRebirth, requirement.reason = canRebirth, reason
		local objective = reason
		if #profile.ownedCars == 0 then
			objective = "Recoge monedas y compra tu primer Sedán usado por $" .. api.Price(profile, 1) .. "."
		elseif not canRebirth then
			for _, car in ipairs(cars) do
				if not car.owned and not car.locked then
					objective = "Ahorra $" .. car.cost .. " para " .. car.name .. ". Tus autos producen dinero solos."
					break
				end
			end
		end
		return {
			mode = "tycoon", cash = rounded(profile.cash), rebirths = profile.rebirths, multiplier = rounded(api.Multiplier(profile)),
			permanentMultiplier = rounded(api.PermanentMultiplier(profile)), incomePerSecond = rounded(api.CarIncome(profile)),
			ownedCars = table.clone(profile.ownedCars), discoveredCars = table.clone(profile.discoveredCars),
			carTiers = cars, upgrades = publicUpgrades, rebirth = requirement, coinValue = api.CoinValue(profile),
			coinsCollected = profile.coinsCollected, totalCoinsCollected = profile.totalCoinsCollected,
			lifetimeCash = rounded(profile.lifetimeCash), walkSpeed = api.WalkSpeed(profile), magnetRadius = api.MagnetRadius(profile), objective = objective,
		}
	end
	return api
end
return Economy
