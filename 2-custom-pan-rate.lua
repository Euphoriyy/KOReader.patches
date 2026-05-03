local Event = require("ui/event")
local ReaderUI = require("apps/reader/readerui")
local Screen = require("device").screen
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local time = require("ui/time")
local userpatch = require("userpatch")
local util = require("ffi/util")
local _ = require("gettext")
local C_ = _.pgettext

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
local PanRate = Setting("pan_rate", get_refresh_rate() or 30.0)

function ReaderUI:onUpdatePanRate()
    local pan_rate = Screen.low_pan_rate and 2.0 or PanRate.get()
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
    self:handleEvent(Event:new("UpdatePanRate"))
end

-- Add menu to Gestures plugin
local patched = false

userpatch.registerPatchPluginFunc("gestures", function(Gestures)
    if patched then return end

    local original_Gestures_addIntervals = Gestures.addIntervals
    function Gestures:addIntervals(menu_items)
        original_Gestures_addIntervals(self, menu_items)

        table.insert(menu_items.gesture_intervals.sub_item_table, 1, {
            text = _("Pan rate"),
            enabled_func = function() return not Screen.low_pan_rate end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local spin = SpinWidget:new {
                    title_text = _("Pan rate"),
                    info_text = _([[
The rate is how often the screen will be refreshed per second while panning.
Higher values mean faster screen updates but also use more CPU.

The rate value can range from 1 Hz to 360 Hz.
]]),
                    width = math.floor(Screen:getWidth() * 0.75),
                    value = PanRate.get(),
                    value_min = 1.0,
                    value_max = 360.0,
                    value_step = 1,
                    value_hold_step = 15,
                    unit = C_("Frequency", "Hz"),
                    ok_text = _("Set rate"),
                    default_value = PanRate.default,
                    callback = function(widget)
                        PanRate.set(widget.value)
                        UIManager:broadcastEvent(Event:new("UpdatePanRate"))
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                }
                UIManager:show(spin)
            end,
        })
    end

    patched = true
end)
