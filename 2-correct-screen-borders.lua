--[[
    This user patch adds border lines to the sides of the screen to correct for e-ink issues.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local logger = require("logger")

local function Setting(name, default)
    local self = {}
    self.get = function() return G_reader_settings:readSetting(name, default) end
    self.set = function(value) return G_reader_settings:saveSetting(name, value) end
    self.toggle = function() G_reader_settings:toggle(name) end
    return self
end

-- Settings
local EnableTopCorrection = Setting("correct_border_top", true)       -- Enable drawing a black line on the top border (default: true)
local EnableBottomCorrection = Setting("correct_border_bottom", true) -- Enable drawing a black line on the bottom border (default: true)
local EnableLeftCorrection = Setting("correct_border_left", true)     -- Enable drawing a black line on the left border (default: true)
local EnableRightCorrection = Setting("correct_border_right", true)   -- Enable drawing a black line on the right border (default: true)
local CorrectionWidth = Setting("correct_border_width", 1)            -- The width to draw the line at (default: 1)
local InvertCorrection = Setting("correct_border_invert", false)      -- Invert line (default: false)

local show_delay = 0.2

local enable_top = EnableTopCorrection.get()
local enable_bottom = EnableBottomCorrection.get()
local enable_left = EnableLeftCorrection.get()
local enable_right = EnableRightCorrection.get()
local correction_width = CorrectionWidth.get()
local invert_correction = InvertCorrection.get()

local border_draw_scheduled = false

local function draw_borders()
    if not (enable_top or enable_bottom or enable_left or enable_right) then
        return
    end

    local c = invert_correction and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
    local screen_width, screen_height = Screen:getWidth(), Screen:getHeight()

    -- Top
    if enable_top then
        Screen.bb:paintRect(0, 0, screen_width, correction_width, c)
    end
    -- Bottom
    if enable_bottom then
        Screen.bb:paintRect(0, screen_height - correction_width, screen_width, correction_width, c)
    end
    -- Left
    if enable_left then
        Screen.bb:paintRect(0, 0, correction_width, screen_height, c)
    end
    -- Right
    if enable_right then
        Screen.bb:paintRect(screen_width - correction_width, 0, correction_width, screen_height, c)
    end

    UIManager:setDirty(nil, "ui")

    -- logger.info("[CSB] Corrected screen border(s)!")
end

-- Debounce draws
local function schedule_draw(delay)
    if border_draw_scheduled then return end
    border_draw_scheduled = true
    UIManager:scheduleIn(delay, function()
        border_draw_scheduled = false
        draw_borders()
    end)
end

-- Helper: check if this is a relevant refresh
local function is_relevant_refresh(refresh_mode, region, currently_scrolling)
    if not refresh_mode or currently_scrolling then
        return false
    end

    if refresh_mode == "full" or refresh_mode == "flashpartial" or
        refresh_mode == "partial" or refresh_mode == "flashui" or
        (refresh_mode == "ui" and region)
    then
        return true
    end
end

-- Schedule border drawing on refreshes
local original_UIManager_refresh = UIManager._refresh

function UIManager:_refresh(refresh_mode, region, dither)
    original_UIManager_refresh(self, refresh_mode, region, dither)

    if is_relevant_refresh(refresh_mode, region, self.currently_scrolling) then
        schedule_draw(0.01)
    end
end

-- Draw once on start
UIManager:scheduleIn(show_delay, draw_borders)

-- Resets border (for setting changes)
local function refresh_borders()
    UIManager:setDirty("all", "full")
    UIManager:forceRePaint()
    schedule_draw(show_delay)
end

-- Patch menus
local FileManagerMenu = require("apps/filemanager/filemanagermenu")
local ReaderMenu = require("apps/reader/modules/readermenu")
local SpinWidget = require("ui/widget/spinwidget")
local _ = require("gettext")
local T = require("ffi/util").template

local function border_correction_menu()
    return {
        text = _("Border correction"),
        sub_item_table_func = function()
            local items = {
                {
                    text_func = function()
                        return T(_("Border width: %1"), CorrectionWidth.get())
                    end,
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        local spin = SpinWidget:new {
                            title_text = _("Border width"),
                            info_text = _("Width of correction border."),
                            value = CorrectionWidth.get(),
                            value_min = 1,
                            value_max = 25,
                            value_hold_step = 2,
                            default_value = 1,
                            callback = function(widget)
                                CorrectionWidth.set(widget.value)
                                correction_width = widget.value

                                refresh_borders()
                                if touchmenu_instance then touchmenu_instance:updateItems() end
                            end,
                        }
                        UIManager:show(spin)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                },
                {
                    text = _("Correct top border"),
                    checked_func = EnableTopCorrection.get,
                    callback = function()
                        EnableTopCorrection.toggle()
                        enable_top = EnableTopCorrection.get()

                        refresh_borders()
                    end,
                },
                {
                    text = _("Correct bottom border"),
                    checked_func = EnableBottomCorrection.get,
                    callback = function()
                        EnableBottomCorrection.toggle()
                        enable_bottom = EnableBottomCorrection.get()

                        refresh_borders()
                    end,
                },
                {
                    text = _("Correct left border"),
                    checked_func = EnableLeftCorrection.get,
                    callback = function()
                        EnableLeftCorrection.toggle()
                        enable_left = EnableLeftCorrection.get()

                        refresh_borders()
                    end,
                },
                {
                    text = _("Correct right border"),
                    checked_func = EnableRightCorrection.get,
                    callback = function()
                        EnableRightCorrection.toggle()
                        enable_right = EnableRightCorrection.get()

                        refresh_borders()
                    end,
                },
                {
                    text = _("Invert correction border (for visibility)"),
                    checked_func = InvertCorrection.get,
                    callback = function()
                        InvertCorrection.toggle()
                        invert_correction = InvertCorrection.get()

                        refresh_borders()
                    end,
                },
            }
            return items
        end,
    }
end

local function patch(menu, order)
    table.insert(order.screen, "border_correction")
    menu.menu_items.border_correction = border_correction_menu()
end

local original_FileManagerMenu_setUpdateItemTable = FileManagerMenu.setUpdateItemTable
function FileManagerMenu:setUpdateItemTable()
    patch(self, require("ui/elements/filemanager_menu_order"))
    original_FileManagerMenu_setUpdateItemTable(self)
end

local original_ReaderMenu_setUpdateItemTable = ReaderMenu.setUpdateItemTable
function ReaderMenu:setUpdateItemTable()
    patch(self, require("ui/elements/reader_menu_order"))
    original_ReaderMenu_setUpdateItemTable(self)
end
