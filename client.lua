local capturing = false

Citizen.CreateThread(function()
    while true do
        Wait(Config.SampleInterval or 500)

        local ped = PlayerPedId()
        if not DoesEntityExist(ped) then goto continue end

        local coords = GetEntityCoords(ped)
        local flags = {
            isInVehicle = IsPedInAnyVehicle(ped, false),
            isFalling = IsPedFalling(ped),
            isRagdoll = IsPedRagdoll(ped),
            isParachuteOpen = GetPedParachuteState(ped) > 0
        }

        TriggerServerEvent("anticheat:noclipSample", coords.x, coords.y, coords.z, GetGameTimer(), flags)

        ::continue::
    end
end)

-- Periodic screenshot sender
Citizen.CreateThread(function()
    local interval = Config.ScreenshotInterval or 3000
    print("[CLIENT DEBUG] Screenshot thread started, interval: " .. tostring(interval) .. "ms")
    while true do
        Wait(interval)
        print("[CLIENT DEBUG] Screenshot loop iteration, capturing=" .. tostring(capturing))
        if capturing then goto continue end
        capturing = true

        print("[CLIENT DEBUG] Requesting screenshot...")
        exports['screenshot-basic']:requestScreenshot(function(data)
            capturing = false
            print("[CLIENT DEBUG] Screenshot callback received, data length: " .. (data and #data or 0))
            if not data or data == "" then 
                print("[CLIENT DEBUG] Screenshot data is empty!")
                return end
            local base64 = data:gsub("^data:image/%w+;base64,", "")
            print("[CLIENT DEBUG] Sending screenshot to server, base64 length: " .. #base64)
            TriggerServerEvent("monitoring:screenshot", base64)
        end, {
            encoding = "jpg",
            quality = math.floor(math.max(10, math.min(100, (Config.ScreenshotQuality or 0.7) * 100)))
        })

        ::continue::
    end
end)

RegisterNetEvent("anticheat:requestScreenshot", function()
    if Config.Debug then
        print("[anticheat] Screenshot requested by server")
    end

    exports['screenshot-basic']:requestScreenshotUpload(
        Config.PanelApiUrl .. "/functions/v1/upload-screenshot",
        "files[]",
        {
            encoding = "jpg",
            quality = 0.7
        },
        function(data)
            local resp = json.decode(data)
            if resp and resp.files and resp.files[1] then
                local base64 = resp.files[1]
                if Config.Debug then
                    print("[anticheat] Screenshot captured, sending to server...")
                end
                TriggerServerEvent("monitoring:screenshot", base64)
            else
                if Config.Debug then
                    print("[anticheat] Failed to capture screenshot")
                end
            end
        end
    )
end)

-- Manual test command: /screenshot
RegisterCommand("screenshot", function()
    print("[anticheat] Manual screenshot test started")
    exports['screenshot-basic']:requestScreenshot(function(data)
        print("TEST: " .. tostring(data ~= nil))
    end, {
        encoding = "jpg"
    })
end, false)
