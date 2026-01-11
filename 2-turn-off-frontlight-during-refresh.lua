--[[
    This user patch turns off the frontlight during refreshes in night mode to prevent bright flashes.
--]]

local Device = require("device")
local logger = require("logger")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")

local patch_active = false
local saved_frontlight = nil
local restoring = false
local restore_task = nil

-- Helper: detect night mode
local function is_night_mode()
    return G_reader_settings:isTrue("night_mode")
end

-- Helper: check if we have a document open
local function has_document_open()
    return ReaderUI.instance ~= nil and ReaderUI.instance.document ~= nil
end

-- Helper: check if this is a full refresh
local function is_full_refresh(refresh_mode)
    return refresh_mode == "full" or refresh_mode == "flashpartial"
end

-- Hook into ReaderUI to delay patch activation
local original_init = ReaderUI.init

ReaderUI.init = function(self)
    original_init(self)

    -- Activate patch after document is fully loaded
    UIManager:scheduleIn(0.5, function()
        if self.document then
            patch_active = true
            logger.info("Frontlight refresh patch now active...")
        end
    end)
end

-- Hook into ReaderUI close to deactivate the patch
local original_onClose = ReaderUI.onClose

ReaderUI.onClose = function(self)
    patch_active = false
    if restore_task then
        UIManager:unschedule(restore_task)
        restore_task = nil
    end
    logger.info("Frontlight refresh patch deactivated...")
    return original_onClose(self)
end

-- Hook into the refresh function
local original_refresh = UIManager._refresh

UIManager._refresh = function(self, refresh_mode, ...)
    -- Only act if not currently restoring, the patch is active, in night mode, a document is open, and it's a full refresh
    if restoring or not patch_active or not is_night_mode() or
        not has_document_open() or not is_full_refresh(refresh_mode) then
        return original_refresh(self, refresh_mode, ...)
    end

    -- Save & disable frontlight before refresh
    local level = Device.powerd:frontlightIntensity()
    if level > 0 then
        saved_frontlight = level
        Device.powerd:setIntensity(Device.powerd.fl_min)
    else
        saved_frontlight = nil
    end

    -- Perform actual refresh
    local result = original_refresh(self, refresh_mode, ...)

    -- Restore frontlight after refresh
    if saved_frontlight then
        restoring = true
        restore_task = UIManager:scheduleIn(0.02, function()
            Device.powerd:setIntensity(saved_frontlight)
            saved_frontlight = nil
            -- Clear flag after a longer delay to catch all triggered refreshes
            UIManager:scheduleIn(0.15, function()
                restoring = false
            end)
        end)
    end

    return result
end
