-- Pure economy tests. tools/check.py injects the current source files.
local Config = (function()
__CONFIG_SOURCE__
end)()
local Economy = (function()
__ECONOMY_SOURCE__
end)()
local economy = Economy.new(Config)
local checks = 0
local function check(condition, message)
	assert(condition, message)
	checks += 1
	print("PASS " .. message)
end
local function close(a, b)
	return math.abs(a - b) < 0.001
end

local profile = economy.NewProfile()
local other = economy.NewProfile()
check(profile.cash == 0 and #profile.ownedCars == 0 and economy.CarIncome(profile) == 0, "start with coins and no passive income")
profile.upgrades.speed = 1
check(other.upgrades.speed == 0, "profiles never share mutable upgrade tables")
profile.upgrades.speed = 0
for _ = 1, 12 do economy.CollectCoin(profile) end
check(profile.cash == 120 and profile.coinsCollected == 12 and profile.totalCoinsCollected == 12, "twelve base coins pay the starter car")
check(economy.BuyCar(profile, 1) and profile.cash == 0 and #profile.ownedCars == 1, "starter purchase debits the exact price")
check(profile.discoveredCars[1] == 1 and economy.CarIncome(profile) == 1, "owned car enters the permanent book and produces income")
check(economy.Tick(profile, 10) == 10 and profile.cash == 10, "passive income accrues directly into the wallet")
local prior = profile.cash
check(not economy.BuyCar(profile, 1) and profile.cash == prior, "duplicate car cannot charge the wallet")
check(not economy.BuyCar(profile, 2) and profile.cash == prior, "insufficient funds cannot charge the wallet")
profile.cash = 1e9
check(not economy.BuyCar(profile, 3) and not economy.BuyCar(profile, 4), "car order and rebirth locks are enforced")
check(not economy.BuyCar(profile, -1) and not economy.BuyCar(profile, 0/0) and not economy.BuyCar(profile, {})
	and not economy.BuyCar(profile, "1"), "malformed car IDs are rejected")
check(not economy.BuyUpgrade(profile, {}) and not economy.BuyUpgrade(profile, string.rep("x", 1000)), "malformed upgrade IDs are rejected")

local beforeUpgrade = profile.cash
check(economy.UpgradePrice(profile, "income") == 200 and economy.BuyUpgrade(profile, "income")
	and profile.cash == beforeUpgrade - 200, "income upgrade has a server-owned price")
check(close(economy.Multiplier(profile), 1.25) and close(economy.CarIncome(profile), 1.25)
	and economy.CoinValue(profile) == 12, "money multiplier improves both cars and coins")
for _, definition in ipairs(Config.Upgrades) do
	while profile.upgrades[definition.id] < definition.maxLevel do
		assert(economy.BuyUpgrade(profile, definition.id))
	end
	prior = profile.cash
	check(economy.UpgradePrice(profile, definition.id) == 0 and not economy.BuyUpgrade(profile, definition.id)
		and profile.cash == prior, definition.id .. " upgrade caps without charging again")
end
check(economy.Multiplier(profile) == 3 and economy.WalkSpeed(profile) == 26
	and economy.MagnetRadius(profile) == 12 and economy.CoinValue(profile) == 60, "all upgrade categories change their intended effect")
prior = profile.cash
economy.Tick(profile, -1); economy.Tick(profile, 0/0); economy.Tick(profile, math.huge)
check(profile.cash == prior, "invalid tick durations never create or remove currency")

local clean = economy.Sanitize({ cash = 0/0, rebirths = -3, ownedCars = {1, 2, 6, 6}, discoveredCars = {1, 1, 3, 999},
	upgrades = {income = math.huge, speed = 99, magnet = -10, coinValue = "invalid"}, totalCoinsCollected = math.huge })
check(clean.cash == 0 and clean.rebirths == 0 and #clean.ownedCars == 2, "loaded data rejects NaN and inaccessible car tiers")
check(#clean.discoveredCars == 3 and clean.discoveredCars[2] == 2 and clean.discoveredCars[3] == 3,
	"collection sanitization deduplicates and includes owned cars")
check(clean.upgrades.income == 0 and clean.upgrades.speed == 5 and clean.upgrades.magnet == 0
	and clean.upgrades.coinValue == 0, "loaded upgrade levels are finite and bounded")
check(economy.Sanitize(nil).cash == 0 and economy.Sanitize({rebirths = math.huge}).rebirths == 0, "missing or corrupt profiles receive safe defaults")

local run = economy.NewProfile()
run.cash = 1e9
check(not economy.CanRebirth(run), "money alone cannot bypass the rebirth car requirement")
for id = 1, 3 do assert(economy.BuyCar(run, id)) end
local requirement = economy.RebirthRequirements(run)
run.cash = requirement.cost - 1
check(not economy.CanRebirth(run), "rebirth requires the full wallet threshold")
run.cash = requirement.cost
run.upgrades.income = 2; run.upgrades.speed = 3
run.coinsCollected = 42; run.totalCoinsCollected = 99; run.lifetimeCash = 50000
check(economy.CanRebirth(run) and economy.Rebirth(run), "first rebirth succeeds when both gates are satisfied")
check(run.rebirths == 1 and run.cash == 0 and #run.ownedCars == 0 and run.upgrades.income == 0
	and run.upgrades.speed == 0 and run.coinsCollected == 0, "rebirth resets run currency, cars and temporary upgrades")
check(#run.discoveredCars == 3 and run.totalCoinsCollected == 99 and run.lifetimeCash == 50000,
	"rebirth preserves permanent collection and lifetime counters")
check(economy.Multiplier(run) == 1.75 and economy.PublicState(run).carTiers[4].locked == false
	and economy.PublicState(run).carTiers[6].locked, "first rebirth adds a permanent bonus and unlocks the next class")
check(economy.Price(run, 1) == 144 and economy.RebirthRequirements(run).requiredTier == 5
	and economy.RebirthRequirements(run).cost > requirement.cost, "later cycles increase prices and require the new highest tier")
local previousCost = requirement.cost
for cycle = 2, 5 do
	run.cash = 1e12
	local gate = economy.RebirthRequirements(run)
	for id = 1, gate.requiredTier do assert(economy.BuyCar(run, id)) end
	check(gate.cost > previousCost and economy.CanRebirth(run), "consecutive rebirth " .. cycle .. " has an increasing requirement")
	previousCost = gate.cost
	assert(economy.Rebirth(run))
end
check(run.rebirths == 5 and #run.discoveredCars == 6 and economy.Multiplier(run) == 4.75,
	"repeated cycles preserve all discovered cars and increase the permanent factor")

local cap = economy.NewProfile()
cap.ownedCars = {1, 2, 3}; cap.cash = Config.MaxCash - 1
check(economy.Tick(cap, 60) == 1 and cap.cash == Config.MaxCash, "income cannot overflow the wallet cap")
local view = economy.PublicState(run)
table.insert(view.ownedCars, 999); table.insert(view.discoveredCars, 999)
check(#run.ownedCars == 0 and #run.discoveredCars == 6, "public collection arrays do not expose mutable profile arrays")

local function simulate(coinsPerMinute, buyIncome)
	local simulated = economy.NewProfile()
	local coinAccumulator = 0
	local firstCarTime = nil
	for second = 1, 3600 do
		economy.Tick(simulated, 1)
		coinAccumulator += coinsPerMinute / 60
		while coinAccumulator >= 1 do
			coinAccumulator -= 1
			economy.CollectCoin(simulated)
		end
		for id = 1, 3 do
			if economy.CanBuyCar(simulated, id) then
				assert(economy.BuyCar(simulated, id))
				if id == 1 then firstCarTime = second end
			end
		end
		if buyIncome and #simulated.ownedCars > 0 and simulated.upgrades.income < #simulated.ownedCars
			and simulated.cash >= economy.UpgradePrice(simulated, "income") then
			assert(economy.BuyUpgrade(simulated, "income"))
		end
		if economy.CanRebirth(simulated) then return second, firstCarTime end
	end
	error("Simulation never reached rebirth")
end
for _, rate in ipairs({25, 30, 35}) do
	local time, firstCar = simulate(rate, false)
	check(firstCar >= 20 and firstCar <= 45 and time >= 600 and time <= 900,
		string.format("balance at %d coins/min: starter %ds, first rebirth %.2f min (no upgrades)", rate, firstCar, time / 60))
end
local optimized = simulate(30, true)
check(optimized < simulate(30, false) and optimized >= 420,
	string.format("planned income upgrades reward choices: first rebirth %.2f min at 30 coins/min", optimized / 60))
print(string.format("ECONOMY TESTS PASSED: %d checks. Simulations assume continuous coin gathering, not measured player behavior.", checks))
