local playerStates = {}
local bannedIdentifiers = {}
local monitoredPlayers = {}

local function startupLog(msg)
    print(msg)
end

local function isWhitelisted(source)
    local ids = GetPlayerIdentifiers(source)
    local whitelist = Config.Whitelist or {}
    for _, identifier in ipairs(ids) do
        for _, white in ipairs(whitelist) do
            if white ~= nil and identifier:lower() == tostring(white):lower() then
                return true
            end
        end
    end
    return false
end

local function collectIdentifiers(source)
    local identifiers = {
        steam = nil,
        license = nil,
        discord = nil,
        fivem = nil,
        ip = nil
    }

    for _, id in ipairs(GetPlayerIdentifiers(source)) do
        if id:find("steam:") == 1 then
            identifiers.steam = id
        elseif id:find("license:") == 1 then
            identifiers.license = id
        elseif id:find("discord:") == 1 then
            identifiers.discord = id
        elseif id:find("fivem:") == 1 then
            identifiers.fivem = id
        elseif id:find("ip:") == 1 then
            identifiers.ip = id
        end
    end

    return identifiers
end

local function rememberBan(source)
    for _, id in ipairs(GetPlayerIdentifiers(source)) do
        bannedIdentifiers[id:lower()] = true
    end
end

local function actionForOffense(count)
    if count >= 3 then
        return Config.EnableBanOnThird and "ban" or "kick"
    elseif count == 2 then
        return "kick"
    else
        return "warn"
    end
end

local function parseServerName(body)
    if not body or body == "" then return nil end
    local ok, decoded = pcall(json.decode, body)
    if not ok or type(decoded) ~= "table" then return nil end
    return decoded.server_name or decoded.server or decoded.name
end

local function sendDetectionToApi(source, coords, action)
    if not Config.ApiUrl or Config.ApiUrl == "" then return end
    if not Config.ApiKey or Config.ApiKey == "" then return end

    local payload = {
        api_key = Config.ApiKey,
        player_name = GetPlayerName(source) or ("player_" .. tostring(source)),
        player_identifiers = collectIdentifiers(source),
        location = {
            x = coords.x,
            y = coords.y,
            z = coords.z
        },
        action_taken = action
    }

    PerformHttpRequest(Config.ApiUrl, function(code, body, _headers)
        if Config.Debug then
            print(("[anticheat] API response: %s %s"):format(tostring(code), tostring(body)))
        end
    end, "POST", json.encode(payload), { ["Content-Type"] = "application/json" })

    local tracked = monitoredPlayers[source]
    if tracked and tracked.player_id then
        if Config.Debug then
            print(("[anticheat] Requesting screenshot for player %s (id: %s)"):format(GetPlayerName(source), tracked.player_id))
        end
        TriggerClientEvent("anticheat:requestScreenshot", source)
    end
end

local function postWithRetries(url, payload, description, attempt, cb)
    attempt = attempt or 1
    local maxAttempts = 3
    PerformHttpRequest(url, function(code, body, _headers)
        local ok = code == 200
        if Config.Debug then
            print(("[monitoring] %s attempt %d => HTTP %s body: %s"):format(description or "request", attempt, tostring(code), tostring(body)))
        end

        if ok or attempt >= maxAttempts then
            if cb then cb(ok, code, body) end
            return
        end

        SetTimeout(1000, function()
            postWithRetries(url, payload, description, attempt + 1, cb)
        end)
    end, "POST", json.encode(payload), { ["Content-Type"] = "application/json" })
end

local function parseJson(body)
    if not body or body == "" then return nil end
    local ok, decoded = pcall(json.decode, body)
    if not ok then return nil end
    return decoded
end

local function registerOrUpdatePlayer(source, online)
    if not Config.PlayerUpdateUrl or Config.PlayerUpdateUrl == "" or not Config.ApiKey or Config.ApiKey == "" or not Config.ServerId or Config.ServerId == "" then
        return
    end

    local identifiers = collectIdentifiers(source)
    local payload = {
        api_key = Config.ApiKey,
        server_id = Config.ServerId,
        player_name = GetPlayerName(source) or ("player_" .. tostring(source)),
        player_identifiers = {
            steam = identifiers.steam,
            license = identifiers.license,
            discord = identifiers.discord
        },
        online = online
    }

    local url = Config.PlayerUpdateUrl
    postWithRetries(url, payload, "player-update", 1, function(success, code, body)
        if success then
            local decoded = parseJson(body) or {}
            local playerId = decoded.player_id or decoded.id
            monitoredPlayers[source] = monitoredPlayers[source] or {}
            monitoredPlayers[source].player_id = playerId
            monitoredPlayers[source].name = payload.player_name
            monitoredPlayers[source].identifiers = payload.player_identifiers
            if Config.Debug then
                print(("[monitoring] player %s registered, id: %s"):format(payload.player_name, tostring(playerId)))
            end
        else
            if Config.Debug then
                print(("[monitoring] player-update failed HTTP %s body: %s"):format(tostring(code), tostring(body)))
            end
        end
    end)
end

local function uploadScreenshot(playerId, base64Data)
    if not playerId or not base64Data or base64Data == "" then return end
    if not Config.ScreenshotUploadUrl or Config.ScreenshotUploadUrl == "" or not Config.ApiKey or Config.ApiKey == "" then return end

    local payload = {
        api_key = Config.ApiKey,
        player_id = playerId,
        screenshot_base64 = base64Data
    }

    local url = Config.ScreenshotUploadUrl
    postWithRetries(url, payload, "upload-screenshot")
end

RegisterNetEvent("monitoring:screenshot", function(base64Data)
    local src = source
    if not src then return end
    
    if Config.Debug then
        print(("[monitoring] Received screenshot from player %s, size: %d bytes"):format(GetPlayerName(src), #(base64Data or "")))
    end

    local tracked = monitoredPlayers[src]
    if not tracked or not tracked.player_id then
        if Config.Debug then
            print(("[monitoring] Player not tracked yet, registering now..."))
        end
        registerOrUpdatePlayer(src, true)
        tracked = monitoredPlayers[src]
    end
    if tracked and tracked.player_id then
        uploadScreenshot(tracked.player_id, base64Data)
    end
end)

RegisterNetEvent("anticheat:uploadScreenshot", function(base64Data)
    local src = source
    if not src then return end
    if Config.Debug then
        print(("[monitoring] Upload screenshot event from %s, size: %d bytes"):format(GetPlayerName(src), #(base64Data or "")))
    end
    local tracked = monitoredPlayers[src]
    if not tracked or not tracked.player_id then
        registerOrUpdatePlayer(src, true)
        tracked = monitoredPlayers[src]
    end
    if tracked and tracked.player_id then
        uploadScreenshot(tracked.player_id, base64Data)
    end
end)

local function testConnectionOnStart()
    -- Panel monitoring startup test
    startupLog("^2[Monitoring]^0 Starting player monitoring...")
    if Config.PlayerUpdateUrl ~= "" and Config.ApiKey ~= "" and Config.ServerId ~= "" then
        startupLog("^2[Monitoring]^0 Testing connection to panel...")
        local payload = {
            api_key = Config.ApiKey,
            server_id = Config.ServerId,
            player_name = "StartupMonitor",
            player_identifiers = {
                steam = "startup:0000",
                license = "startup:0000",
                discord = "startup:0000"
            },
            online = false
        }
        local url = Config.PlayerUpdateUrl
        postWithRetries(url, payload, "panel-startup", 1, function(success, code, body)
            if success then
                startupLog("^2[Monitoring]^0 ✓ Connected to panel!")
            else
                startupLog("^1[Monitoring]^0 ✗ Panel connection failed!")
                startupLog(("^1[Monitoring]^0 Error: HTTP %s - Check panel config"):format(tostring(code)))
                if Config.Debug then
                    startupLog(("[Monitoring] Debug: HTTP %s Body: %s"):format(tostring(code), tostring(body)))
                end
            end
        end)
    else
        startupLog("^1[Monitoring]^0 Panel config missing (PanelApiUrl/ApiKey/ServerId)")
    end

    -- Original anti-cheat backend test
    if not Config.ApiUrl or Config.ApiUrl == "" or not Config.ApiKey or Config.ApiKey == "" then
        startupLog("^1[Anti-Cheat]^0 ✗ Connection Failed!")
        startupLog("^1[Anti-Cheat]^0 Error: Check your API key in config.lua")
        return
    end

    startupLog("^2[Anti-Cheat]^0 Starting up...")
    startupLog("^2[Anti-Cheat]^0 Testing connection to panel...")

    local payload = {
        api_key = Config.ApiKey,
        player_name = "StartupTest",
        player_identifiers = {
            steam = "startup:0000",
            license = "startup:0000",
            discord = "startup:0000"
        },
        location = { x = 0.0, y = 0.0, z = 0.0 },
        action_taken = "warn"
    }

    PerformHttpRequest(Config.ApiUrl, function(code, body, _headers)
        if code == 200 then
            startupLog("^2[Anti-Cheat]^0 ✓ Connected Successfully!")
            local serverName = parseServerName(body) or "Unknown"
            startupLog(("^2[Anti-Cheat]^0 Server: %s"):format(serverName))
            startupLog("^2[Anti-Cheat]^0 Status: ^2Active and Monitoring^0")
        else
            startupLog("^1[Anti-Cheat]^0 ✗ Connection Failed!")
            startupLog(("^1[Anti-Cheat]^0 Error: HTTP %s - Check your API key"):format(tostring(code)))
            if Config.Debug then
                startupLog(("[Anti-Cheat] Debug: HTTP %s Body: %s"):format(tostring(code), tostring(body)))
            end
        end
    end, "POST", json.encode(payload), { ["Content-Type"] = "application/json" })
end

local function notifyPlayer(source, message)
    TriggerClientEvent("chat:addMessage", source, {
        color = { 255, 80, 80 },
        multiline = false,
        args = { "AntiCheat", message }
    })
end

RegisterNetEvent("anticheat:noclipSample", function(x, y, z, clientTime, flags)
    local src = source
    if not src then return end
    if Config.EnableDetection == false then return end
    if isWhitelisted(src) then return end

    local coords = vector3(tonumber(x) or 0.0, tonumber(y) or 0.0, tonumber(z) or 0.0)
    local state = playerStates[src] or {}
    local now = GetGameTimer()

    if not state.lastPos then
        playerStates[src] = { lastPos = coords, lastTime = now, offenses = 0 }
        return
    end

    local dt = (now - (state.lastTime or now)) / 1000.0
    if dt <= 0.0 then
        dt = (Config.SampleInterval or 500) / 1000.0
    end

    local distance = #(coords - state.lastPos)
    local speed = distance / dt
    local verticalGain = coords.z - state.lastPos.z

    local sensitivity = math.max(Config.Sensitivity or 1.0, 0.1)
    local maxSpeed = (Config.BaseMaxFootSpeed or 12.0) / sensitivity
    local maxTeleport = (Config.BaseMaxTeleportDistance or 80.0) / sensitivity
    local maxVertical = (Config.BaseMaxVerticalGain or 14.0) / sensitivity

    local isInVehicle = flags and flags.isInVehicle
    local isFalling = flags and flags.isFalling
    local isRagdoll = flags and flags.isRagdoll
    local isParachuteOpen = flags and flags.isParachuteOpen

    local detectionReason

    if distance > maxTeleport and not isInVehicle and not isFalling and not isParachuteOpen then
        detectionReason = ("Teleport distance %.2f > %.2f"):format(distance, maxTeleport)
    elseif verticalGain > maxVertical and not isInVehicle and not isFalling and not isParachuteOpen then
        detectionReason = ("Vertical gain %.2f > %.2f"):format(verticalGain, maxVertical)
    elseif speed > maxSpeed and not isInVehicle and not isFalling and not isRagdoll then
        detectionReason = ("Speed %.2f > %.2f"):format(speed, maxSpeed)
    end

    state.lastPos = coords
    state.lastTime = now
    playerStates[src] = state

    if not detectionReason then
        return
    end

    state.offenses = (state.offenses or 0) + 1
    local action = actionForOffense(state.offenses)

    if Config.Debug then
        print(("[anticheat] %s triggered detection (%s), offense %d, action %s"):format(GetPlayerName(src) or "unknown", detectionReason, state.offenses, action))
    end

    sendDetectionToApi(src, coords, action)

    if action == "warn" then
        notifyPlayer(src, "Possible noclip detected. This is a warning.")
    elseif action == "kick" then
        DropPlayer(src, "[AntiCheat] Noclip detected. (Kick)")
    elseif action == "ban" then
        rememberBan(src)
        DropPlayer(src, "[AntiCheat] Noclip detected. (Ban)")
    end
end)

AddEventHandler("playerConnecting", function(_name, setKickReason, deferrals)
    local src = source
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if bannedIdentifiers[id:lower()] then
            setKickReason("[AntiCheat] You are banned for noclip detections.")
            if deferrals then
                deferrals.done("[AntiCheat] You are banned for noclip detections.")
            end
            CancelEvent()
            return
        end
    end
    registerOrUpdatePlayer(src, true)
end)

AddEventHandler("playerDropped", function(_reason)
    local src = source
    playerStates[src] = nil
    if monitoredPlayers[src] then
        registerOrUpdatePlayer(src, false)
        monitoredPlayers[src] = nil
    end
end)

AddEventHandler("onResourceStart", function(resName)
    if resName ~= GetCurrentResourceName() then return end
    testConnectionOnStart()
end)
