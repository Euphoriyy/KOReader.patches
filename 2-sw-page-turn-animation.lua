--[[--
Software-based page turn "erase/wipe" animation for e-ink devices.

A new submenu "Page turn animation (patch)" appears under:
Settings (gear) -> Gestures & Actions -> Page turning
with two options:
  - Enable animation (mirrors the native toggle)
  - Number of steps (free spinner, 2 to 24)
--]] --

local Device = require("device")
local Event = require("ui/event")
local ReaderPaging = require("apps/reader/modules/readerpaging")
local Screen = Device.screen
local UIManager = require("ui/uimanager")
local logger = require("logger")
local dbg = require("dbg")
local userpatch = require("userpatch")
local _ = require("gettext")

-- ============ TUNABLE (default, overridden by the menu option below) =====
local DEFAULT_STEPS = 8
local SETTING_KEY = "page_turn_animation_steps"
local function getSteps()
    return G_reader_settings:readSetting(SETTING_KEY, DEFAULT_STEPS)
end
-- ===========================================================================

-- 1) Framebuffer: implement saved_bb snapshot + real setSwipeAnimations/setSwipeDirection
Screen.beforePaint = function(self)
    if not self.painting then
        self.painting = true
        if self.swipe_animations then
            if self.saved_bb then self.saved_bb:free() end
            self.saved_bb = self.bb:copy()
        end
    end
end

Screen.afterPaint = function(self)
    self.painting = false
end

Screen.setSwipeAnimations = function(self, enabled)
    self.swipe_animations = enabled
end

Screen.setSwipeDirection = function(self, direction)
    self.swipe_forward = direction
end

local hardware_animate = Device.canDoSwipeAnimation()

-- 2) Make sure the device reports it can do the (software) swipe animation,
--    even if this specific device model has it hardcoded to false.
Device.canDoSwipeAnimation = function() return true end

-- 3) UIManager:_repaint -- inject the software swipe animation right before
--    the queued refreshes are executed. We need the module's private
--    upvalues (refresh_methods, update_dither), which we grab via KOReader's
--    own userpatch.getUpValue() helper instead of reimplementing them.
local orig_repaint = UIManager._repaint
local refresh_methods = userpatch.getUpValue(orig_repaint, "refresh_methods")
local update_dither = userpatch.getUpValue(orig_repaint, "update_dither")

UIManager._repaint = function(self)
    local dirty = false
    local dithered = false

    local start_idx = 1
    for i = #self._window_stack, 1, -1 do
        if self._window_stack[i].widget.covers_fullscreen then
            start_idx = i
            break
        end
    end

    for i = start_idx, #self._window_stack do
        local window = self._window_stack[i]
        local widget = window.widget
        if dirty or self._dirty[widget] then
            Screen:beforePaint()
            widget:paintTo(Screen.bb, window.x, window.y, self._dirty[widget])
            self._dirty[widget] = nil
            dirty = true
            if widget.dithered then
                dithered = true
            end
        end
    end

    for _, refreshfunc in ipairs(self._refresh_func_stack) do
        local refreshtype, region, dither = refreshfunc()
        dither = update_dither(dither, dithered)
        if refreshtype then
            self:_refresh(refreshtype, region, dither)
        end
    end
    self._refresh_func_stack = {}

    if dirty and not self._refresh_stack[1] then
        logger.dbg("no refresh got enqueued. Will do a partial full screen refresh, which might be inefficient")
        self:_refresh("partial")
    end

    local software_animate = not hardware_animate

    if software_animate then
        Screen.swipe_animations = false
        local saved_bb = Screen.saved_bb
        Screen.saved_bb = nil
        if saved_bb then
            local new_bb = Screen.bb:copy()
            local steps = getSteps()
            local screen_w = Screen.bb:getWidth()
            local screen_h = Screen.bb:getHeight()
            local swipe_forward = Screen.swipe_forward
            local prev_dx = 0

            for i = 1, steps do
                local progress = i / steps
                local dx = math.floor(screen_w * progress)
                local strip_w = dx - prev_dx

                if swipe_forward then
                    -- Right-to-left: new page reveals from the right
                    Screen.bb:blitFrom(saved_bb, 0, 0, 0, 0, screen_w - dx, screen_h)
                    Screen.bb:blitFrom(new_bb, screen_w - dx, 0, screen_w - dx, 0, dx, screen_h)

                    if i < steps then
                        -- Intermediate frame: grayscale refresh (not A2) on just the
                        -- newly revealed strip. Slower than A2, but avoids the harsh
                        -- black/white flash, giving a subtler, more "blended" look
                        -- closer to Amazon's native page turn animation.
                        if strip_w > 0 then
                            Screen:refreshUI(screen_w - dx, 0, strip_w, screen_h)
                            self:yieldToEPDC(20000)
                        end
                    else
                        -- Final frame: same grayscale mode as the intermediate
                        -- steps (not refreshPartial), so there's no visible
                        -- mode-switch jump right as the animation ends.
                        Screen:refreshUI(0, 0, screen_w, screen_h)
                    end
                else
                    -- Left-to-right: new page reveals from the left
                    Screen.bb:blitFrom(new_bb, 0, 0, 0, 0, dx, screen_h)
                    Screen.bb:blitFrom(saved_bb, dx, 0, dx, 0, screen_w - dx, screen_h)

                    if i < steps then
                        if strip_w > 0 then
                            Screen:refreshUI(prev_dx, 0, strip_w, screen_h)
                            self:yieldToEPDC(20000)
                        end
                    else
                        Screen:refreshUI(0, 0, screen_w, screen_h)
                    end
                end

                prev_dx = dx
            end

            -- The animation already painted+refreshed the new page in full.
            -- The regular "page turn" refresh queued earlier this repaint is
            -- now redundant (it would cause a jarring extra refresh right
            -- after the animation). But keep any "full" mode refresh in the
            -- queue: that's KOReader's periodic ghosting-clear refresh
            -- (every FULL_REFRESH_COUNT page turns), which we still want.
            local kept_refreshes = {}
            for _, refresh in ipairs(self._refresh_stack) do
                if refresh.mode == "full" then
                    table.insert(kept_refreshes, refresh)
                end
            end
            self._refresh_stack = kept_refreshes

            new_bb:free()
            saved_bb:free()
        end
    end

    -- End software page animation
    for _, refresh in ipairs(self._refresh_stack) do
        refresh.dither = update_dither(refresh.dither, dithered)
        if not Screen.hw_dithering then
            refresh.dither = nil
        end
        dbg:v("triggering refresh", refresh)
        refresh_methods[refresh.mode](Screen,
            refresh.region.x, refresh.region.y,
            refresh.region.w, refresh.region.h,
            refresh.dither)
    end

    if dirty then
        Screen:afterPaint()
    end

    self._refresh_stack = {}
    self.refresh_counted = false
end

logger.info("page-turn-animation patch: applied (steps = " .. getSteps() .. ")")

-- Override page changes for fixed-layout documents to show the animation
function ReaderPaging:_gotoPage(number, orig_mode)
    if number == self.current_page or not number then
        -- update footer even if we stay on the same page (like when
        -- viewing the bottom part of a page from a top part view)
        self.view.footer:onUpdateFooter(self.view.footer_visible)
        return true
    end
    if number > self.number_of_pages then
        logger.warn("page number too high: " .. number .. "!")
        number = self.number_of_pages
    elseif number < 1 then
        logger.warn("page number too low: " .. number .. "!")
        number = 1
    end
    if self.current_page then
        self.ui:handleEvent(Event:new("PageChangeAnimation", number > self.current_page))
    end
    -- this is an event to allow other controllers to be aware of this change
    self.ui:handleEvent(Event:new("PageUpdate", number, orig_mode))
    return true
end

-- Add a config menu entry under Settings -> Page turning
local PageTurns = require("ui/elements/page_turns")

table.insert(PageTurns.sub_item_table, {
    text = _("Software page turn animation"),
    sub_item_table = {
        {
            text = _("Enable animation"),
            checked_func = function()
                return G_reader_settings:isTrue("swipe_animations")
            end,
            callback = function()
                G_reader_settings:flipNilOrFalse("swipe_animations")
            end,
        },
        {
            keep_menu_open = true,
            text_func = function()
                local T = require("ffi/util").template
                return T(_("Number of steps: %1"), getSteps())
            end,
            callback = function(touchmenu_instance)
                local SpinWidget = require("ui/widget/spinwidget")
                UIManager:show(SpinWidget:new {
                    title_text = _("Animation steps"),
                    info_text = _([[
How many frames the page-turn wipe animation is split into.
More steps = smoother animation but slower.
Fewer steps = faster but choppier.]]),
                    value = getSteps(),
                    value_min = 2,
                    value_max = 24,
                    value_step = 1,
                    default_value = DEFAULT_STEPS,
                    precision = "%d",
                    callback = function(spin)
                        G_reader_settings:saveSetting(SETTING_KEY, spin.value)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                })
            end,
        },
    },
})
