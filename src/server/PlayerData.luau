--!nonstrict
-- Atomic per-player leases; Studio data never touches published storage.
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local shared = game:GetService("ReplicatedStorage"):WaitForChild("MidnightGarage")
local economy = require(shared:WaitForChild("Economy")).new(require(shared:WaitForChild("Config")))
local PlayerData = {}
local sessions = {}
local LEASE_SECONDS = 180
local MAX_RETRIES = 3
local WAIT_SECONDS = 25
local serverToken = game.JobId ~= "" and game.JobId or HttpService:GenerateGUID(false)
local studioSession = RunService:IsStudio() or game.GameId == 0
local store = nil
local write

local function getStore()
	if not store then store = DataStoreService:GetDataStore("GarageTycoon_Player_v1") end
	return store
end

local function removeEntry(userId, entry)
	entry.released = true
	if sessions[userId] == entry then sessions[userId] = nil end
end

function PlayerData.Load(player)
	local userId = player.UserId
	local deadline = os.clock() + WAIT_SECONDS
	-- A reconnect is a different Player instance. It must acquire a fresh lease,
	-- never borrow a closing/loading entry owned by the previous connection.
	while sessions[userId] do
		local previous = sessions[userId]
		if previous.player == player and not previous.loading and not previous.closing and not previous.released then
			return economy.Sanitize(previous.profile), previous.status
		end
		if os.clock() >= deadline then return economy.NewProfile(), "unavailable" end
		task.wait(0.05)
	end
	local entry = {
		player = player, profile = economy.NewProfile(), status = studioSession and "session" or "unavailable",
		token = serverToken .. ":" .. tostring(userId) .. ":" .. HttpService:GenerateGUID(false),
		allowed = false, loading = true, saving = false, closing = false, released = false,
		pendingRelease = nil, releaseAfterLoad = false,
	}
	sessions[userId] = entry
	if studioSession then entry.loading = false; return entry.profile, entry.status end
	for attempt = 1, MAX_RETRIES do
		local locked = false
		local ok, record = pcall(function()
			return getStore():UpdateAsync("Player_" .. tostring(userId), function(current)
				local now = os.time()
				current = type(current) == "table" and current or {}
				local lease = current.session
				if type(lease) == "table" and lease.id ~= entry.token and type(lease.expires) == "number" and lease.expires > now then
					locked = true
					return nil
				end
				return { version = 1, profile = economy.Sanitize(current.profile), revision = tonumber(current.revision) or 0,
					session = { id = entry.token, expires = now + LEASE_SECONDS } }
			end)
		end)
		if ok and type(record) == "table" and record.session and record.session.id == entry.token then
			entry.profile, entry.allowed, entry.status = economy.Sanitize(record.profile), true, "saved"
			break
		end
		if locked then break end
		if attempt < MAX_RETRIES then task.wait(attempt * 0.5) end
	end
	entry.loading = false
	-- If a connection closed while its load yielded, release the data that was
	-- actually loaded, never the empty placeholder Main used during loading.
	if entry.releaseAfterLoad then write(player, entry.profile, true) end
	return economy.Sanitize(entry.profile), entry.status
end

local function persist(entry, snapshot, release)
	if not entry.allowed then return studioSession end
	for attempt = 1, MAX_RETRIES do
		local owned = true
		local ok, result = pcall(function()
			return getStore():UpdateAsync("Player_" .. tostring(entry.player.UserId), function(current)
				if type(current) ~= "table" or type(current.session) ~= "table" or current.session.id ~= entry.token then
					owned = false
					return nil
				end
				return { version = 1, profile = snapshot, revision = (tonumber(current.revision) or 0) + 1,
					updatedAt = os.time(), session = if release then nil else { id = entry.token, expires = os.time() + LEASE_SECONDS } }
			end)
		end)
		if ok and type(result) == "table" and owned then return true end
		if not owned then entry.allowed = false; return false end
		if attempt < MAX_RETRIES then task.wait(attempt * 0.5) end
	end
	return false
end

write = function(player, profile, release)
	local userId = player.UserId
	local entry = sessions[userId]
	if not entry or entry.player ~= player or entry.released then return false, "unavailable" end
	if entry.loading then
		if not release then return false, "unavailable" end
		entry.closing, entry.releaseAfterLoad = true, true
		local deadline = os.clock() + WAIT_SECONDS
		while entry.loading and os.clock() < deadline do task.wait(0.05) end
		if entry.released then return entry.status == "saved" or entry.status == "session", entry.status end
		if entry.loading then return false, "unavailable" end
		-- Load already queued its own release using the correct loaded snapshot.
		if entry.closing then
			while entry.saving and os.clock() < deadline do task.wait(0.05) end
			return entry.released and (entry.status == "saved" or entry.status == "session"), entry.status
		end
	end
	if entry.closing and not release then return false, entry.status end
	if release then
		entry.closing = true
		entry.pendingRelease = economy.Sanitize(profile)
	end
	if not entry.allowed then
		entry.profile = economy.Sanitize(profile)
		if release then removeEntry(userId, entry) end
		return studioSession, entry.status
	end
	if entry.saving then
		if not release then return false, entry.status end
		-- The active writer will drain pendingRelease even if this caller reaches
		-- its bounded wait. The final snapshot is not abandoned behind an autosave.
		local deadline = os.clock() + WAIT_SECONDS
		while entry.saving and not entry.released and os.clock() < deadline do task.wait(0.05) end
		return entry.released and entry.status == "saved", entry.status
	end
	entry.saving = true
	local isRelease = release
	local snapshot = if release then entry.pendingRelease else economy.Sanitize(profile)
	if release then entry.pendingRelease = nil end
	local success
	while true do
		success = persist(entry, snapshot, isRelease)
		entry.status = success and "saved" or "unavailable"
		if success then entry.profile = snapshot end
		if isRelease then
			removeEntry(userId, entry)
			break
		end
		if entry.pendingRelease then
			snapshot, entry.pendingRelease, isRelease = entry.pendingRelease, nil, true
		else
			break
		end
	end
	entry.saving = false
	return success, entry.status
end

function PlayerData.Save(player, profile) return write(player, profile, false) end
function PlayerData.Release(player, profile) return write(player, profile, true) end
return PlayerData
