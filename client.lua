local capturing = false
local lastCaptureTime = 0

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

-- Check if screenshot-basic is available
local screenshotAvailable = false
Citizen.CreateThread(function()
    Wait(5000) -- Wait for resources to load
    
    local success, result = pcall(function()
        return exports['screenshot-basic'] ~= nil
    end)
    
    screenshotAvailable = success and result
    
    if screenshotAvailable then
        print("[CLIENT] ✓ screenshot-basic resource detected")
    else
        print("[CLIENT] ✗ screenshot-basic resource NOT FOUND!")
        print("[CLIENT] Screenshots will not work. Please install screenshot-basic:")
        print("[CLIENT] https://github.com/citizenfx/screenshot-basic")
    end
end)

-- Periodic screenshot sender with proper error handling
Citizen.CreateThread(function()
    local interval = Config.ScreenshotInterval or 3000
    
    if Config.Debug then
        print("[CLIENT DEBUG] Screenshot thread started, interval: " .. tostring(interval) .. "ms")
    end
    
    while true do
        Wait(interval)
        
        -- Skip if screenshot-basic is not available
        if not screenshotAvailable then
            goto continue
        end
        
        local currentTime = GetGameTimer()
        
        -- Skip if already capturing
        if capturing then
            if Config.Debug then
                print("[CLIENT DEBUG] Already capturing, skipping")
            end
            goto continue
        end
        
        -- Rate limit check
        if currentTime - lastCaptureTime < (interval - 100) then
            goto continue
        end
        
        capturing = true
        lastCaptureTime = currentTime
        
        if Config.Debug then
            print("[CLIENT DEBUG] Attempting screenshot capture...")
        end
        
        -- Safety timeout
        local captureStartTime = currentTime
        SetTimeout(8000, function()
            if capturing and (GetGameTimer() - captureStartTime) >= 7500 then
                if Config.Debug then
                    print("[CLIENT DEBUG] Screenshot capture timed out, resetting")
                end
                capturing = false
            end
        end)
        
        -- Try to capture screenshot with better error handling
        local success, err = pcall(function()
            exports['screenshot-basic']:requestScreenshot(function(data)
                capturing = false
                
                if Config.Debug then
                    print("[CLIENT DEBUG] Screenshot callback fired!")
                end
                
                if not data or data == "" then 
                    if Config.Debug then
                        print("[CLIENT DEBUG] Screenshot data is empty")
                    end
                    return
                end
                
                -- Remove data URL prefix if present
                local base64 = data:gsub("^data:image/%w+;base64,", "")
                
                if Config.Debug then
                    print("[CLIENT DEBUG] Sending screenshot to server (size: " .. #base64 .. " bytes)")
                end
                
                TriggerServerEvent("anticheat:uploadScreenshot", base64)
            end, {
                encoding = "jpg",
                quality = math.floor(math.max(10, math.min(100, (Config.ScreenshotQuality or 0.7) * 100)))
            })
        end)
        
        if not success then
            capturing = false
            if Config.Debug then
                print("[CLIENT DEBUG] Screenshot capture error: " .. tostring(err))
            end
        end

        ::continue::
    end
end)

RegisterNetEvent("anticheat:requestScreenshot", function()
    if not screenshotAvailable then
        print("[anticheat] Cannot capture screenshot - screenshot-basic not available")
        return
    end
    
    if Config.Debug then
        print("[anticheat] Screenshot requested by server")
    end

    local success, err = pcall(function()
        exports['screenshot-basic']:requestScreenshot(function(data)
            if not data or data == "" then 
                if Config.Debug then
                    print("[anticheat] Failed to capture screenshot - no data")
                end
                return
            end
            
            local base64 = data:gsub("^data:image/%w+;base64,", "")
            
            if Config.Debug then
                print("[anticheat] Screenshot captured, sending to server (size: " .. #base64 .. " bytes)")
            end
            
            TriggerServerEvent("anticheat:uploadScreenshot", base64)
        end, {
            encoding = "jpg",
            quality = 70
        })
    end)
    
    if not success then
        print("[anticheat] Screenshot capture failed: " .. tostring(err))
    end
end)

-- Manual test command: /screenshot
RegisterCommand("screenshot", function()
    if not screenshotAvailable then
        print("[anticheat] screenshot-basic resource not available")
        return
    end
    
    print("[anticheat] Manual screenshot test started")
    
    local success, err = pcall(function()
        exports['screenshot-basic']:requestScreenshot(function(data)
            if data and data ~= "" then
                print("[anticheat] ✓ Screenshot test successful! Size: " .. #data .. " bytes")
            else
                print("[anticheat] ✗ Screenshot test failed - no data returned")
            end
        end, {
            encoding = "jpg",
            quality = 70
        })
    end)
    
    if not success then
        print("[anticheat] ✗ Screenshot test error: " .. tostring(err))
    end
end, false)

-- Debug command to check screenshot-basic status
RegisterCommand("checkscreenshot", function()
    print("=== Screenshot-Basic Status ===")
    print("Available: " .. tostring(screenshotAvailable))
    print("Capturing: " .. tostring(capturing))
    print("Last capture: " .. tostring(lastCaptureTime))
    
    local success, result = pcall(function()
        return exports['screenshot-basic'] ~= nil
    end)
    
    print("Export exists: " .. tostring(success and result))
    print("==============================")
end, false)
