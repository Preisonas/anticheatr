Config = {}

-- API configuration
Config.ApiUrl = "https://ccbbxzlrbdxnhfduclpo.supabase.co/functions/v1/report-detection"
Config.ApiKey = "7df68eb35f5df148371686dbb6ff57e0807244f5c0298298bb0e65a7d2b6f37d"

-- Monitoring panel settings
Config.PanelApiUrl = "https://ccbbxzlrbdxnhfduclpo.supabase.co"
Config.ServerId = "5526414c-7c61-4e54-aada-4f3929d59014"  -- Get this from the Servers tab in your panel
Config.PlayerUpdateUrl = Config.PanelApiUrl .. "/functions/v1/player-update"
Config.ScreenshotUploadUrl = Config.PanelApiUrl .. "/functions/v1/upload-screenshot"
Config.ScreenshotInterval = 3000  -- 3 seconds (already good)
Config.ScreenshotQuality = 0.7    -- 70% quality (already good)


-- Detection sensitivity (higher = stricter; affects speed/teleport thresholds)
Config.Sensitivity = 2.0

-- Toggle noclip detection on/off (set to false to temporarily disable)
Config.EnableDetection = false

-- Sample interval in ms for position updates from the client
Config.SampleInterval = 500

-- Base thresholds before sensitivity is applied
Config.BaseMaxFootSpeed = 12.0      -- meters per second allowed on foot
Config.BaseMaxTeleportDistance = 80 -- meters between samples allowed
Config.BaseMaxVerticalGain = 14.0   -- meters gained up between samples allowed

-- If true, the 3rd offense will ban (DropPlayer) instead of kick
Config.EnableBanOnThird = true

-- Whitelisted identifiers (any match skips detection)
Config.Whitelist = {
    "steam:110000xxxxxxx",
    "license:xxxxxx"
}

-- Optional debug prints in server console
Config.Debug = true
