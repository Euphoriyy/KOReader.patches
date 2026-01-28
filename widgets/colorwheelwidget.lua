local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local MovableContainer = require("ui/widget/container/movablecontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Font = require("ui/font")
local Screen = Device.screen

------------------------------------------------------------

local ColorWheelWidget = FocusManager:extend {
    title_text = "Pick a color",
    width = nil,
    width_factor = 0.6,

    -- HSV values
    hue = 0, -- 0..360
    saturation = 1,
    value = 1,

    -- Whether to invert colors in night mode for accurate preview (default: true)
    invert_in_night_mode = true,

    cancel_text = "Cancel",
    ok_text = "Apply",

    callback = nil,
    cancel_callback = nil,
    close_callback = nil,
}

------------------------------------------------------------
-- HSV → RGB helper
------------------------------------------------------------
local function hsvToRgb(h, s, v)
    local c = v * s
    local x = c * (1 - math.abs((h / 60) % 2 - 1))
    local m = v - c

    local r, g, b
    if h < 60 then
        r, g, b = c, x, 0
    elseif h < 120 then
        r, g, b = x, c, 0
    elseif h < 180 then
        r, g, b = 0, c, x
    elseif h < 240 then
        r, g, b = 0, x, c
    elseif h < 300 then
        r, g, b = x, 0, c
    else
        r, g, b = c, 0, x
    end

    return
        math.floor((r + m) * 255 + 0.5),
        math.floor((g + m) * 255 + 0.5),
        math.floor((b + m) * 255 + 0.5)
end

------------------------------------------------------------
-- Color wheel widget (drawing + interaction)
------------------------------------------------------------
local ColorWheel = WidgetContainer:extend {
    radius = 0,
    hue = 0,
    saturation = 1,
    value = 1,
    invert_in_night_mode = true,
}

function ColorWheel:init()
    self.radius = math.floor(self.dimen.w / 2)
    self.dimen = Geom:new {
        x = 0,
        y = 0,
        w = self.dimen.w,
        h = self.dimen.h,
    }

    -- Detect night mode for accurate color preview (if enabled)
    self.night_mode = self.invert_in_night_mode and G_reader_settings:isTrue("night_mode")
end

function ColorWheel:paintTo(bb, x, y)
    -- Store the absolute position for gesture handling
    self.dimen.x = x
    self.dimen.y = y

    local cx = x + self.radius
    local cy = y + self.radius

    for py = -self.radius, self.radius do
        for px = -self.radius, self.radius do
            local dist = math.sqrt(px * px + py * py)
            if dist <= self.radius then
                local angle = (math.deg(math.atan2(py, px)) + 360) % 360
                local sat = dist / self.radius

                local r, g, b = hsvToRgb(angle, sat, self.value)

                -- Invert colors in night mode for accurate preview
                if self.night_mode then
                    r = 255 - r
                    g = 255 - g
                    b = 255 - b
                end

                -- Use ColorRGB24 or ColorRGB32 depending on bb type
                local color
                if bb:getType() == Blitbuffer.TYPE_BBRGB32 then
                    color = Blitbuffer.ColorRGB32(r, g, b, 0xFF)
                elseif bb:getType() == Blitbuffer.TYPE_BBRGB24 then
                    color = Blitbuffer.ColorRGB24(r, g, b)
                elseif bb:getType() == Blitbuffer.TYPE_BBRGB16 then
                    color = Blitbuffer.ColorRGB24(r, g, b)
                else
                    -- For grayscale buffers, convert to luminance
                    color = Blitbuffer.Color8(math.floor((r * 0.299 + g * 0.587 + b * 0.114) + 0.5))
                end
                bb:setPixel(cx + px, cy + py, color)
            end
        end
    end

    -- Draw current selection indicator
    local sel_angle = math.rad(self.hue)
    local sel_dist = self.saturation * self.radius
    local sel_x = cx + math.floor(math.cos(sel_angle) * sel_dist + 0.5)
    local sel_y = cy + math.floor(math.sin(sel_angle) * sel_dist + 0.5)

    -- Draw a small circle indicator (black with white outline for visibility)
    for py = -4, 4 do
        for px = -4, 4 do
            local d = px * px + py * py
            if d <= 16 then -- outer circle (radius 4)
                bb:setPixelClamped(sel_x + px, sel_y + py, Blitbuffer.COLOR_WHITE)
            end
            if d <= 9 then -- inner circle (radius 3)
                bb:setPixelClamped(sel_x + px, sel_y + py, Blitbuffer.COLOR_BLACK)
            end
        end
    end
end

function ColorWheel:updateColor(ges_pos)
    if not self.dimen then
        return false
    end

    local cx = self.dimen.x + self.radius
    local cy = self.dimen.y + self.radius
    local dx = ges_pos.x - cx
    local dy = ges_pos.y - cy

    local dist = math.sqrt(dx * dx + dy * dy)

    -- Only respond if tap is within the wheel
    if dist > self.radius then
        return false
    end

    self.hue = (math.deg(math.atan2(dy, dx)) + 360) % 360
    self.saturation = math.min(1, dist / self.radius)

    -- Notify parent widget to update
    if self.update_callback then
        self.update_callback()
    end

    return true
end

------------------------------------------------------------
-- Main dialog widget
------------------------------------------------------------
function ColorWheelWidget:init()
    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    self.medium_font_face = Font:getFace("ffont")

    if not self.width then
        self.width = math.floor(
            math.min(self.screen_width, self.screen_height) * self.width_factor
        )
    end

    self.inner_width = self.width - 2 * Size.padding.large
    self.button_width = math.floor(self.inner_width / 4)

    if Device:isTouchDevice() then
        self.ges_events = {
            TapColorWheel = {
                GestureRange:new {
                    ges = "tap",
                    range = Geom:new {
                        x = 0, y = 0,
                        w = self.screen_width,
                        h = self.screen_height,
                    }
                }
            },
            PanColorWheel = {
                GestureRange:new {
                    ges = "pan",
                    range = Geom:new {
                        x = 0, y = 0,
                        w = self.screen_width,
                        h = self.screen_height,
                    }
                }
            },
        }
    end

    self:update()
end

function ColorWheelWidget:update()
    local wheel_size = self.width - 2 * Size.padding.large

    self.color_wheel = ColorWheel:new {
        dimen = Geom:new {
            w = wheel_size,
            h = wheel_size,
        },
        hue = self.hue,
        saturation = self.saturation,
        value = self.value,
        invert_in_night_mode = self.invert_in_night_mode,
        update_callback = function()
            -- Sync values from color wheel
            self.hue = self.color_wheel.hue
            self.saturation = self.color_wheel.saturation
            -- Update the preview and rebuild
            self:update()
        end,
    }

    local title_bar = TitleBar:new {
        width = self.width,
        title = self.title_text,
        with_bottom_line = true,
        close_button = true,
        close_callback = function()
            self:onCancel()
        end,
        show_parent = self,
    }

    -- Value (brightness) slider
    local value_minus = Button:new {
        text = "−",
        enabled = self.value > 0,
        width = self.button_width,
        show_parent = self,
        callback = function()
            self.value = math.max(0, self.value - 0.1)
            self:update()
        end,
    }

    local value_plus = Button:new {
        text = "＋",
        enabled = self.value < 1,
        width = self.button_width,
        show_parent = self,
        callback = function()
            self.value = math.min(1, self.value + 0.1)
            self:update()
        end,
    }

    local value_label = TextWidget:new {
        text = string.format("Brightness: %d%%", math.floor(self.value * 100)),
        face = self.medium_font_face,
    }

    local value_group = HorizontalGroup:new {
        align = "center",
        value_minus,
        HorizontalSpan:new { width = Size.padding.default },
        value_label,
        HorizontalSpan:new { width = Size.padding.default },
        value_plus,
    }

    -- Color preview
    local r, g, b = hsvToRgb(self.hue, self.saturation, self.value)
    local hex_text = string.format("#%02X%02X%02X", r, g, b)

    local preview_size = math.floor(wheel_size / 4)

    -- Detect night mode for preview
    local night_mode = self.invert_in_night_mode and G_reader_settings:isTrue("night_mode")
    local preview_r, preview_g, preview_b = r, g, b

    -- Invert preview colors in night mode for accurate display
    if night_mode then
        preview_r = 255 - r
        preview_g = 255 - g
        preview_b = 255 - b
    end

    -- Create a simple widget for the color preview
    local ColorPreview = WidgetContainer:extend {
        dimen = Geom:new {
            w = preview_size,
            h = preview_size,
        },
    }

    function ColorPreview:paintTo(bb, x, y)
        bb:paintRectRGB32(x, y, self.dimen.w, self.dimen.h,
            Blitbuffer.ColorRGB32(preview_r, preview_g, preview_b, 0xFF))
    end

    self.color_preview = FrameContainer:new {
        bordersize = Size.border.thick,
        margin = 0,
        padding = 0,
        ColorPreview:new {},
    }

    local hex_label = TextWidget:new {
        text = hex_text,
        face = Font:getFace("infofont", 20),
    }

    local preview_group = HorizontalGroup:new {
        align = "center",
        self.color_preview,
        HorizontalSpan:new { width = Size.padding.large },
        hex_label,
    }

    -- Buttons
    local cancel_button = Button:new {
        text = self.cancel_text,
        width = math.floor(self.width / 2) - Size.padding.large * 2,
        show_parent = self,
        callback = function()
            self:onCancel()
        end,
    }

    local ok_button = Button:new {
        text = self.ok_text,
        width = math.floor(self.width / 2) - Size.padding.large * 2,
        show_parent = self,
        callback = function()
            self:onApply()
        end,
    }

    local button_row = HorizontalGroup:new {
        align = "center",
        cancel_button,
        HorizontalSpan:new { width = Size.padding.large },
        ok_button,
    }

    local vgroup = VerticalGroup:new {
        align = "center",
        title_bar,
        VerticalSpan:new { width = Size.padding.large },
        CenterContainer:new {
            dimen = Geom:new {
                w = self.width,
                h = value_label:getSize().h + Size.padding.default,
            },
            value_group,
        },
        VerticalSpan:new { width = Size.padding.large },
        CenterContainer:new {
            dimen = Geom:new {
                w = self.width,
                h = wheel_size + Size.padding.large * 2,
            },
            self.color_wheel,
        },
        VerticalSpan:new { width = Size.padding.large },
        CenterContainer:new {
            dimen = Geom:new {
                w = self.width,
                h = preview_size + Size.padding.default,
            },
            preview_group,
        },
        VerticalSpan:new { width = Size.padding.large },
        CenterContainer:new {
            dimen = Geom:new {
                w = self.width,
                h = Size.item.height_default,
            },
            button_row,
        },
        VerticalSpan:new { width = Size.padding.default },
    }

    self.frame = FrameContainer:new {
        radius = Size.radius.window,
        bordersize = Size.border.window,
        background = Blitbuffer.COLOR_WHITE,
        vgroup,
    }

    self.movable = MovableContainer:new {
        self.frame,
    }

    self[1] = CenterContainer:new {
        dimen = Geom:new {
            x = 0, y = 0,
            w = self.screen_width,
            h = self.screen_height,
        },
        self.movable,
    }

    UIManager:setDirty(self, "ui")
end

function ColorWheelWidget:onTapColorWheel(arg, ges_ev)
    -- Check if we have valid dimensions
    if not self.color_wheel.dimen or not self.frame.dimen then
        return true
    end

    -- Check if tap is on the color wheel
    if ges_ev.pos:intersectWith(self.color_wheel.dimen) then
        if self.color_wheel:updateColor(ges_ev.pos) then
            self:update()
        end
        return true
    elseif not ges_ev.pos:intersectWith(self.frame.dimen) and ges_ev.ges == "tap" then
        -- Close when tapping outside the dialog
        self:onCancel()
        return true
    end
    -- Let buttons handle their taps
    return false
end

function ColorWheelWidget:onPanColorWheel(arg, ges_ev)
    -- Only handle pan on the color wheel itself
    if not self.color_wheel.dimen then
        return false
    end

    if ges_ev.pos:intersectWith(self.color_wheel.dimen) then
        if self.color_wheel:updateColor(ges_ev.pos) then
            self:update()
        end
        return true
    end
    return false
end

function ColorWheelWidget:onApply()
    UIManager:close(self)
    if self.callback then
        local r, g, b = hsvToRgb(self.hue, self.saturation, self.value)
        local hex = string.format("#%02X%02X%02X", r, g, b)
        self.callback(hex)
    end
    if self.close_callback then
        self.close_callback()
    end
    return true
end

function ColorWheelWidget:onCancel()
    UIManager:close(self)
    if self.cancel_callback then
        self.cancel_callback()
    end
    if self.close_callback then
        self.close_callback()
    end
    return true
end

function ColorWheelWidget:onShow()
    UIManager:setDirty(self, "ui")
    return true
end

return ColorWheelWidget
