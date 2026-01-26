--[[
    This user patch turns off the frontlight during refreshes in night mode to prevent bright flashes.
--]]

local Device = require("device")
local Dispatcher = require("dispatcher")
local ReaderUI = require("apps/reader/readerui")
local Screensaver = require("ui/screensaver")
local ScreenSaverWidget = require("ui/widget/screensaverwidget")
local UIManager = require("ui/uimanager")

local function Setting(name, default)
    local self = {}
    self.get = function() return G_reader_settings:readSetting(name, default) end
    self.set = function(value) return G_reader_settings:saveSetting(name, value) end
    self.toggle = function() G_reader_settings:toggle(name) end
    return self
end

-- Settings
local EnableFrontlightRefresh = Setting("frontlight_refresh_enable", true)           -- Enable turning off the frontlight on refreshes (default: true)
local ForceFrontlightRefresh = Setting("frontlight_refresh_force", false)            -- Turn off frontlight on every page turn (default: false)
local UIFrontlightRefresh = Setting("frontlight_refresh_ui", true)                   -- Enable turning off the frontlight on refreshes in UI menus (default: true)
local ReaderOnlyFrontlightRefresh = Setting("frontlight_refresh_reader_only", false) -- Turn off frontlight in reader only (default: false)
local DimLevel = Setting("frontlight_refresh_dim_level", 0)                          -- Variable frontlight dim level (default: 0)

-- Script Variables
local patch_active = false
local restoring = false

-- Helper: detect night mode
local function is_night_mode()
    return G_reader_settings:isTrue("night_mode")
end

-- Helper: check if we have a document open
local function has_document_open()
    return ReaderUI.instance ~= nil and ReaderUI.instance.document ~= nil
end

-- Helper: check if this is a flashing refresh
local function is_flashing_refresh(refresh_mode, region, FULL_REFRESH_COUNT, refresh_count, refresh_counted,
                                   currently_scrolling)
    if not refresh_mode or currently_scrolling then
        return false
    end

    if refresh_mode == "full" or refresh_mode == "flashpartial" then
        return true
    end

    -- Simulate promotion of partial refresh mode to full & flashui
    if refresh_mode == "partial" and FULL_REFRESH_COUNT > 0 and not refresh_counted then
        refresh_count = (refresh_count + 1) % FULL_REFRESH_COUNT
        if refresh_count == FULL_REFRESH_COUNT - 1 then
            -- NOTE: Promote to "full" (true) if no region (reader), to "flashui" otherwise (UI)
            if region then
                refresh_mode = "flashui"
            else
                return true
            end
        end
    end

    return (ForceFrontlightRefresh.get() and refresh_mode == "partial") or
        (UIFrontlightRefresh.get() and ((refresh_mode == "ui" and not region) or refresh_mode == "flashui"))
end

-- Hook into UIManager quit to prevent frontlight dimming on quit
local original_uimanager_quit = UIManager.quit

function UIManager.quit(self, exit_code, implicit)
    patch_active = false

    UIManager:scheduleIn(0.02, function()
        return original_uimanager_quit(self, exit_code, implicit)
    end)
end

-- Hook into Screensaver & ScreenSaverWidget to prevent the patch from dimming the screensaver when screensaver_delay is set
local original_screensaver_show = Screensaver.show

function Screensaver.show(self)
    patch_active = false

    original_screensaver_show(self)
end

local original_screensaverwidget_onCloseWidget = ScreenSaverWidget.onCloseWidget

function ScreenSaverWidget.onCloseWidget()
    original_screensaverwidget_onCloseWidget()

    patch_active = true
end

-- Hook into the refresh function
local original_refresh = UIManager._refresh

function UIManager._refresh(self, refresh_mode, region, dither)
    -- Only act if not currently restoring, the patch is active, in night mode, a document is open, and it's a full refresh
    if not EnableFrontlightRefresh.get() or restoring or not patch_active or not is_night_mode() or
        (ReaderOnlyFrontlightRefresh.get() and not has_document_open()) or
        not is_flashing_refresh(refresh_mode, region, self.FULL_REFRESH_COUNT, self.refresh_count, self.refresh_counted, self.currently_scrolling)
    then
        return original_refresh(self, refresh_mode, region, dither)
    end

    -- Save & disable frontlight before refresh
    local intensity = Device.powerd.fl_intensity
    local dimmed = false

    if intensity > DimLevel.get() then
        Device.powerd:setIntensity(Device.powerd.fl_min + DimLevel.get())
        dimmed = true
    end

    -- Perform actual refresh
    local result = original_refresh(self, refresh_mode, region, dither)

    -- Restore frontlight after refresh
    if dimmed then
        restoring = true
        UIManager:scheduleIn(0.02, function()
            Device.powerd:setIntensity(intensity)

            -- Clear flag after a longer delay to catch all triggered refreshes
            UIManager:scheduleIn(0.15, function()
                restoring = false
            end)
        end)
    end

    return result
end

-- Patch reader & filemanager menus
local ReaderMenu = require("apps/reader/modules/readermenu")
local ReaderMenuOrder = require("ui/elements/reader_menu_order")
local FileManagerMenu = require("apps/filemanager/filemanagermenu")
local FileManagerMenuOrder = require("ui/elements/filemanager_menu_order")
local SpinWidget = require("ui/widget/spinwidget")
local _ = require("gettext")
local T = require("ffi/util").template

local original_readermenu_setUpdateItemTable = ReaderMenu.setUpdateItemTable
local original_filemanagermenu_setUpdateItemTable = FileManagerMenu.setUpdateItemTable

local function set_menu(self, menu_items)
    menu_items.frontlight_refresh = {
        text = _("Frontlight refresh"),
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
            {
                text = _("Turn off frontlight on UI refreshes"),
                checked_func = UIFrontlightRefresh.get,
                enabled_func = EnableFrontlightRefresh.get,
                callback = function()
                    UIFrontlightRefresh.toggle()
                    self.ui:handleEvent("Refresh")
                end,
            },
            {
                text = _("Turn off frontlight in reader only"),
                checked_func = ReaderOnlyFrontlightRefresh.get,
                enabled_func = EnableFrontlightRefresh.get,
                callback = function()
                    ReaderOnlyFrontlightRefresh.toggle()
                    self.ui:handleEvent("Refresh")
                end,
            },
            {
                text_func = function()
                    return T(_("Dim level: %1%"), DimLevel.get())
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local spin = SpinWidget:new {
                        title_text = _("Dim level"),
                        info_text = _("Frontlight brightness on refresh. (Lower ⇛ Darker)"),
                        value = DimLevel.get(),
                        default_value = 0,
                        value_min = 0,
                        value_max = 10,
                        value_step = 1,
                        value_hold_step = 2,
                        precision = "%1d",
                        unit = "%",
                        callback = function(widget)
                            DimLevel.set(widget.value)
                            if self.overlay_rect then
                                UIManager:setDirty(self.ui.dialog, "partial")
                            end
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    }
                    UIManager:show(spin)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            },
        },
    }
end

function ReaderMenu:setUpdateItemTable()
    -- Add main menu entry with submenu
    local order = ReaderMenuOrder.screen
    table.insert(order, #order - 6, "frontlight_refresh")

    set_menu(self, self.menu_items)
    original_readermenu_setUpdateItemTable(self)
end

function FileManagerMenu:setUpdateItemTable()
    -- Add main menu entry with submenu
    local order = FileManagerMenuOrder.screen
    table.insert(order, #order - 6, "frontlight_refresh")

    set_menu(self, self.menu_items)
    original_filemanagermenu_setUpdateItemTable(self)
end

-- Toggle action events
ReaderUI.onToggleFrontlightRefreshEnabled = function()
    EnableFrontlightRefresh.toggle()
end

ReaderUI.onToggleFrontlightRefreshForceful = function()
    ForceFrontlightRefresh.toggle()
end

ReaderUI.onToggleFrontlightRefreshUI = function()
    UIFrontlightRefresh.toggle()
end

ReaderUI.onToggleFrontlightRefreshReaderOnly = function()
    ReaderOnlyFrontlightRefresh.toggle()
end

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

Dispatcher:registerAction("frontlight_refresh_toggle_ui", {
    category = "none",
    event = "ToggleFrontlightRefreshUI",
    title = _("Toggle turning off frontlight in UI refreshes"),
    screen = true,
})

Dispatcher:registerAction("frontlight_refresh_toggle_reader_only", {
    category = "none",
    event = "ToggleFrontlightRefreshReaderOnly",
    title = _("Toggle turning off frontlight in reader only"),
    screen = true,
})
