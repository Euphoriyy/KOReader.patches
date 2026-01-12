--[[
    This user patch turns off the frontlight during refreshes in night mode to prevent bright flashes.
--]]

local Device = require("device")
local Dispatcher = require("dispatcher")
local logger = require("logger")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")

local function Setting(name, default)
    local self = {}
    self.get = function() return G_reader_settings:readSetting(name, default) end
    self.toggle = function() G_reader_settings:toggle(name) end
    return self
end

-- Settings
local EnableFrontlightRefresh = Setting("frontlight_refresh_enable", true) -- Enable turning off the frontlight on refreshes (default: true)
local ForceFrontlightRefresh = Setting("frontlight_refresh_force", false)  -- Turns off frontlight on every page turn (default: false)

-- Script Variables
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
    return refresh_mode == "full" or refresh_mode == "flashpartial" or
    (ForceFrontlightRefresh.get() and refresh_mode == "partial")
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

UIManager._refresh = function(self, refresh_mode, region, dither, ...)
    -- Only act if not currently restoring, the patch is active, in night mode, a document is open, and it's a full refresh
    if not EnableFrontlightRefresh.get() or restoring or not patch_active or not is_night_mode() or
        not has_document_open() or not is_full_refresh(refresh_mode) then
        return original_refresh(self, refresh_mode, region, dither, ...)
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
    local result = original_refresh(self, refresh_mode, region, dither, ...)

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

-- Patch reader menu
local ReaderMenu = require("apps/reader/modules/readermenu")
local ReaderMenuOrder = require("ui/elements/reader_menu_order")
local _ = require("gettext")

local original_setUpdateItemTable = ReaderMenu.setUpdateItemTable

function ReaderMenu:setUpdateItemTable()
    -- Add main menu entry with submenu
    local order = ReaderMenuOrder.typeset
    table.insert(order, #order + 1, "frontlight_refresh_menu")

    self.menu_items.frontlight_refresh_menu = {
        text = _("Frontlight Refresh"),
        sub_item_table = {
            {
                text = _("Enable turning off frontlight on refresh"),
                checked_func = EnableFrontlightRefresh.get,
                callback = function()
                    EnableFrontlightRefresh.toggle()
                    self.ui:handleEvent("Refresh")
                end,
            },
            {
                text = _("Force frontlight off every page turn"),
                checked_func = ForceFrontlightRefresh.get,
                enabled_func = EnableFrontlightRefresh.get,
                callback = function()
                    ForceFrontlightRefresh.toggle()
                    self.ui:handleEvent("Refresh")
                end,
            },
        },
    }

    original_setUpdateItemTable(self)
end

-- Toggle action events
local function onToggleFrontlightRefreshEnabled()
    EnableFrontlightRefresh.toggle()
end

ReaderUI.onToggleFrontlightRefreshEnabled = onToggleFrontlightRefreshEnabled

local function onToggleFrontlightRefreshForceful()
    ForceFrontlightRefresh.toggle()
end

ReaderUI.onToggleFrontlightRefreshForceful = onToggleFrontlightRefreshForceful

-- Register the dispatcher actions
Dispatcher:registerAction("frontlight_refresh_toggle", {
    category = "none",
    event = "ToggleFrontlightRefreshEnabled",
    title = _("Toggle turning off frontlight on refresh"),
    screen = true,
})

Dispatcher:registerAction("frontlight_refresh_toggle_forceful", {
    category = "none",
    event = "ToggleFrontlightRefreshForceful",
    title = _("Toggle force frontlight off every page turn"),
    screen = true,
})
