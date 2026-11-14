-- Offline contract tests: leases, failed loads, stale writes and Studio isolation.
local Config = (function()
__CONFIG_SOURCE__
end)()
local Economy = (function()
__ECONOMY_SOURCE__
end)()
local records = {}
local calls = 0
local failing = false
local studio = false
local serial = 0
local clock = 0
local waitHook = nil
local pauseKey = nil
local fakeStore = {}
function fakeStore:UpdateAsync(key, callback)
	calls += 1
	if failing then error("Simulated connection failure") end
	if pauseKey == key then pauseKey = nil; coroutine.yield("datastore pending") end
	local result = callback(records[key])
	if result ~= nil then records[key] = result end
	return result
end
local function freshModule()
	serial += 1
	local shared = { WaitForChild = function(_, name) return name end }
	local services = {
		RunService = { IsStudio = function() return studio end },
		DataStoreService = { GetDataStore = function() return fakeStore end },
		HttpService = { GenerateGUID = function() serial += 1; return "guid-" .. serial end },
		ReplicatedStorage = { WaitForChild = function() return shared end },
	}
	local game = { JobId = "server-" .. serial, GameId = studio and 0 or 123, GetService = function(_, name) return services[name] end }
	local require = function(name) return name == "Config" and Config or Economy end
	local task = { wait = function(seconds)
		clock += seconds or 0
		if waitHook then waitHook() end
	end }
	local os = { clock = function() return clock end, time = function() return 100000 + math.floor(clock) end }
	return (function()
__DATA_SOURCE__
	end)()
end
local passed = 0
local function check(condition, name)
	assert(condition, name)
	passed += 1
	print("PASS data: " .. name)
end
local player = {UserId = 111}
local first = freshModule()
local profile, status = first.Load(player)
check(status == "saved" and profile.cash == 0, "fresh online profile acquires a lease")
profile.cash = 321
local saved = first.Save(player, profile)
check(saved and records.Player_111.profile.cash == 321 and records.Player_111.session ~= nil, "save writes a snapshot and renews lease")
local blocked = freshModule()
local blockedProfile, blockedStatus = blocked.Load(player)
check(blockedStatus == "unavailable" and blockedProfile.cash == 0, "second server cannot load an active session")
blockedProfile.cash = 999
check(not blocked.Save(player, blockedProfile) and records.Player_111.profile.cash == 321, "fallback profile cannot overwrite real progress")
check(first.Release(player, profile) and records.Player_111.session == nil, "release saves and removes session lease")
local resumed = freshModule()
local resumedProfile, resumedStatus = resumed.Load(player)
check(resumedStatus == "saved" and resumedProfile.cash == 321, "returning player recovers saved cash")
check(not first.Save(player, profile), "released session cannot write again")
failing = true
local offline = freshModule()
local offlineProfile, offlineStatus = offline.Load({UserId = 222})
check(offlineStatus == "unavailable", "load failure is reported")
failing = false
offlineProfile.cash = 800
local before = calls
check(not offline.Save({UserId = 222}, offlineProfile) and records.Player_222 == nil and calls == before, "failed initial load never writes an empty record")
records.Player_111.session.expires = 0
local replacement = freshModule()
local replacementProfile, replacementStatus = replacement.Load(player)
check(replacementStatus == "saved" and replacementProfile.cash == 321, "expired lease permits safe handoff")
resumedProfile.cash = 9999
check(not resumed.Save(player, resumedProfile) and records.Player_111.profile.cash == 321, "stale owner cannot overwrite replacement session")
failing = true
replacementProfile.cash = 500
check(not replacement.Save(player, replacementProfile) and records.Player_111.profile.cash == 321, "failed save preserves previous data")
failing = false
check(replacement.Save(player, replacementProfile) and records.Player_111.profile.cash == 500, "valid session can recover after temporary save failure")
replacement.Release(player, replacementProfile)
studio = true
local sandbox = freshModule()
before = calls
local studioProfile, studioStatus = sandbox.Load(player)
studioProfile.cash = 1500
local studioSaved, studioSaveStatus = sandbox.Save(player, studioProfile)
sandbox.Release(player, studioProfile)
check(studioStatus == "session" and studioSaved and studioSaveStatus == "session" and calls == before and records.Player_111.profile.cash == 500, "Studio never accesses or overwrites published data")

studio = false
local economy = Economy.new(Config)
waitHook = function() coroutine.yield("waiting for previous connection") end
local reconnectModule = freshModule()
local departing, arriving = {UserId = 333}, {UserId = 333}
local loaded = reconnectModule.Load(departing)
local runtime = economy.Sanitize(loaded)
runtime.cash = 777
pauseKey = "Player_333"
local oldRelease = coroutine.create(function() return reconnectModule.Release(departing, runtime) end)
assert(coroutine.resume(oldRelease))
local rejoined, rejoinedStatus
local newLoad = coroutine.create(function() rejoined, rejoinedStatus = reconnectModule.Load(arriving) end)
assert(coroutine.resume(newLoad))
check(coroutine.status(newLoad) == "suspended" and rejoined == nil, "same-server reconnect waits while the previous release is pending")
assert(coroutine.resume(oldRelease)); assert(coroutine.resume(newLoad))
check(rejoined and rejoined.cash == 777 and rejoinedStatus == "saved", "reconnect acquires the final saved snapshot after release")
rejoined.cash = 888
check(reconnectModule.Save(arriving, rejoined) and not reconnectModule.Save(departing, runtime)
	and not reconnectModule.Release(departing, runtime) and records.Player_333.profile.cash == 888,
	"old Player callbacks cannot write or delete the new connection's session")
reconnectModule.Release(arriving, rejoined)

local loadModule = freshModule()
local loadingPlayer, loadingRejoin = {UserId = 444}, {UserId = 444}
pauseKey = "Player_444"
local firstLoading = coroutine.create(function()
	local result = loadModule.Load(loadingPlayer)
	result.cash = 456
	loadModule.Release(loadingPlayer, result)
end)
assert(coroutine.resume(firstLoading))
local nextLoaded
local nextLoading = coroutine.create(function() nextLoaded = loadModule.Load(loadingRejoin) end)
assert(coroutine.resume(nextLoading))
check(nextLoaded == nil and coroutine.status(nextLoading) == "suspended", "reconnect never receives the empty in-flight load placeholder")
assert(coroutine.resume(firstLoading)); assert(coroutine.resume(nextLoading))
check(nextLoaded.cash == 456 and loadModule.Save(loadingRejoin, nextLoaded), "load cancellation safely hands the lease to the reconnect")
loadModule.Release(loadingRejoin, nextLoaded)

local queueModule = freshModule()
local queuedPlayer = {UserId = 555}
local queued = queueModule.Load(queuedPlayer)
queued.cash = 200
pauseKey = "Player_555"
local saving = coroutine.create(function() queueModule.Save(queuedPlayer, queued) end)
assert(coroutine.resume(saving))
queued.cash = 450
local finalRelease = coroutine.create(function() return queueModule.Release(queuedPlayer, queued) end)
assert(coroutine.resume(finalRelease))
clock += 9
assert(coroutine.resume(finalRelease))
check(coroutine.status(finalRelease) == "suspended", "final release is not abandoned after an autosave takes over eight seconds")
assert(coroutine.resume(saving)); assert(coroutine.resume(finalRelease))
check(records.Player_555.profile.cash == 450 and records.Player_555.session == nil,
	"active writer drains the latest release snapshot and clears its lease")
waitHook = nil

-- Run the real Main with a cooperative scheduler to prove shutdown awaits work
-- that PlayerRemoving already removed from its public profiles table.
local function startMain(options)
	local environment = { time = 0, releases = 0, released = false, pauseLoad = options.pauseLoad, pauseRelease = options.pauseRelease }
	local function event()
		local signal = {callbacks = {}}
		function signal:Connect(fn) table.insert(self.callbacks, fn); return {} end
		function signal:Fire(...) for _, callback in ipairs(self.callbacks) do callback(...) end end
		return signal
	end
	local players = {PlayerAdded = event(), PlayerRemoving = event()}
	local player = {UserId = 900, Name = "ShutdownTester", Parent = players, CharacterAdded = event()}
	function players:GetPlayers() return {player} end
	environment.player, environment.players = player, players
	local remoteItems = {}
	for _, name in ipairs({"State", "Notify", "Action"}) do
		remoteItems[name] = {OnServerEvent = event(), IsA = function() return true end, FireClient = function() end}
	end
	local remotes = {IsA = function() return true end, FindFirstChild = function(_, name) return remoteItems[name] end}
	local shared = {WaitForChild = function(_, name) return name end, FindFirstChild = function() return remotes end}
	local replicated = {WaitForChild = function() return shared end}
	local world = {}
	function world:AssignPlot() end
	function world:UpdatePlot() end
	function world:ReleasePlot() end
	function world:BindCollect(callback) self.collect = callback end
	function world:BindAction(callback) self.action = callback end
	local data = {}
	function data.Load()
		if environment.pauseLoad then environment.loadThread = coroutine.running(); coroutine.yield("load pending") end
		return economy.NewProfile(), "saved"
	end
	function data.Save() return true, "saved" end
	function data.Release()
		environment.releases += 1
		if environment.pauseRelease then coroutine.yield("release pending") end
		environment.released = true
		return true, "saved"
	end
	local game = {
		GetService = function(_, name) return name == "Players" and players or replicated end,
		BindToClose = function(_, callback) environment.close = callback end,
	}
	local script = {Parent = {WaitForChild = function(_, name) return name end}}
	local require = function(name)
		if name == "Config" then return Config end
		if name == "Economy" then return Economy end
		if name == "PlayerData" then return data end
		return {new = function() return world end}
	end
	local task = {}
	function task.spawn(fn, ...)
		local thread = coroutine.create(fn)
		local ok, reason = coroutine.resume(thread, ...)
		assert(ok, reason)
		return thread
	end
	function task.wait(seconds) environment.time += seconds or 0; coroutine.yield("timer") end
	function task.delay() end
	local os = {clock = function() return environment.time end}
	local warn = print
	local function runMain()
__SERVER_SOURCE__
	end
	runMain()
	return environment
end

local ending = startMain({pauseRelease = true})
local removing = coroutine.create(function()
	ending.player.Parent = nil
	ending.players.PlayerRemoving:Fire(ending.player)
end)
assert(coroutine.resume(removing))
local shutdown = coroutine.create(ending.close)
assert(coroutine.resume(shutdown))
check(coroutine.status(shutdown) == "suspended" and not ending.released,
	"BindToClose waits for a PlayerRemoving release that already cleared profiles")
assert(coroutine.resume(removing)); assert(coroutine.resume(shutdown))
check(ending.released and coroutine.status(shutdown) == "dead", "shutdown completes after the pending final save finishes")

local duringLoad = startMain({pauseLoad = true})
duringLoad.player.Parent = nil
duringLoad.players.PlayerRemoving:Fire(duringLoad.player)
local loadingShutdown = coroutine.create(duringLoad.close)
assert(coroutine.resume(loadingShutdown))
check(coroutine.status(loadingShutdown) == "suspended", "shutdown also waits for a load cancelled during player removal")
assert(coroutine.resume(duringLoad.loadThread)); assert(coroutine.resume(loadingShutdown))
check(duringLoad.released and coroutine.status(loadingShutdown) == "dead", "cancelled load releases its lease before shutdown returns")
print("PLAYER_DATA_TESTS_PASSED " .. passed)
