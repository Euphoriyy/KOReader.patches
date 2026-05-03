local ReaderScrolling = require("apps/reader/modules/readerscrolling")
local ReaderUI = require("apps/reader/readerui")
local Screen = require("device").screen
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local time = require("ui/time")
local util = require("ffi/util")
local _ = require("gettext")
local C_ = _.pgettext
local T = require("ffi/util").template

function Setting(name, default)
    local self = {}
    self.default = default
    self.get = function() return G_reader_settings:readSetting(name, default) end
    self.set = function(value) return G_reader_settings:saveSetting(name, value) end
    self.toggle = function() G_reader_settings:toggle(name) end
    return self
end

-- Helper: attempt to get the screen's refresh rate from SDL
local function get_refresh_rate()
    local SDL = util.loadSDL3()
    if SDL then
        local mode = SDL.SDL_GetCurrentDisplayMode(SDL.SDL_GetPrimaryDisplay())
        if mode then
            return mode.refresh_rate
        end
    end
end

-- Setting
local CustomPanRate = Setting("custom_pan_rate", get_refresh_rate() or 30.0)

local function update_pan_rate(self)
    local pan_rate = Screen.low_pan_rate and 2.0 or CustomPanRate.get()
    self.pan_rate = pan_rate

    if self.document.info.has_pages then
        self.paging.pan_rate = pan_rate
        self.paging.pan_interval = time.s(1 / self.paging.pan_rate)
    else
        self.rolling.pan_rate = pan_rate
        self.rolling.pan_interval = time.s(1 / self.rolling.pan_rate)
    end
    self.scrolling.pan_rate = pan_rate
    self.scrolling.pan_interval = time.s(1 / self.scrolling.pan_rate)
end

local original_ReaderUI_init = ReaderUI.init
function ReaderUI:init()
    original_ReaderUI_init(self)
    update_pan_rate(self)
end

local original_ReaderScrolling_addToMainMenu = ReaderScrolling.addToMainMenu
function ReaderScrolling:addToMainMenu(menu_items)
    original_ReaderScrolling_addToMainMenu(self, menu_items)

    -- Add separator to previous submenu item
    menu_items.scrolling.sub_item_table[#menu_items.scrolling.sub_item_table].separator = true

    table.insert(menu_items.scrolling.sub_item_table, #menu_items.scrolling.sub_item_table + 1, {
        text_func = function() return T(_("Pan rate: %1 Hz"), CustomPanRate.get()) end,
        enabled_func = function() return not Screen.low_pan_rate end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            local spin = SpinWidget:new {
                title_text = _("Scroll pan rate"),
                info_text = _([[
The rate is how often the screen will be refreshed per second while panning.
Higher values mean faster screen updates but also use more CPU.

The rate value can range from 1 Hz to 360 Hz.
]]),
                width = math.floor(Screen:getWidth() * 0.75),
                value = CustomPanRate.get(),
                value_min = 1.0,
                value_max = 360.0,
                value_step = 1,
                value_hold_step = 15,
                unit = C_("Frequency", "Hz"),
                ok_text = _("Set rate"),
                default_value = CustomPanRate.default,
                callback = function(widget)
                    CustomPanRate.set(widget.value)
                    update_pan_rate(self.ui)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            }
            UIManager:show(spin)
        end,
    })
end
