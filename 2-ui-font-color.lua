--[[
    This user patch allows for changing the UI font color.
    It has menu options for the color and a toggle to invert it in night mode.
    Optionally, the color can be set with a color picker.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local RenderText = require("ui/rendertext")
local Screen = require("device").screen
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")

local function Setting(name, default)
    local self = {}
    self.get = function() return G_reader_settings:readSetting(name, default) end
    self.set = function(value) return G_reader_settings:saveSetting(name, value) end
    self.toggle = function() G_reader_settings:toggle(name) end
    return self
end

-- Settings
local HexFontColor = Setting("ui_font_color_hex", "#000000")    -- RGB hex for UI font color (default: #000000)
local InvertFontColor = Setting("ui_font_color_inverted", true) -- Whether the UI font color should be inverted in night mode (default: true)

-- Helper: invert a hex color string "#RRGGBB" → "#(FF-R)(FF-G)(FF-B)"
local function invertColor(hex)
    -- Remove the "#" and parse as R, G, B
    local r = tonumber(hex:sub(2, 3), 16)
    local g = tonumber(hex:sub(4, 5), 16)
    local b = tonumber(hex:sub(6, 7), 16)
    if not r or not g or not b then return hex end
    -- Invert
    return string.format("#%02X%02X%02X", 255 - r, 255 - g, 255 - b)
end

-- Helper: convert hex color string "#RRGGBB" → HSV values
local function hexToHSV(hex)
    -- Remove # if present
    hex = hex:gsub("#", "")

    -- Parse RGB values
    local r, g, b
    if #hex == 6 then
        -- Full form #RRGGBB
        r = tonumber(hex:sub(1, 2), 16) / 255
        g = tonumber(hex:sub(3, 4), 16) / 255
        b = tonumber(hex:sub(5, 6), 16) / 255
    elseif #hex == 3 then
        -- Short form #RGB -> #RRGGBB
        r = tonumber(hex:sub(1, 1), 16) / 15
        g = tonumber(hex:sub(2, 2), 16) / 15
        b = tonumber(hex:sub(3, 3), 16) / 15
    else
        -- Invalid format, return default (red)
        return 0, 1, 1
    end

    -- RGB to HSV conversion
    local max = math.max(r, g, b)
    local min = math.min(r, g, b)
    local delta = max - min

    -- Value (brightness)
    local v = max

    -- Saturation
    local s = 0
    if max > 0 then
        s = delta / max
    end

    -- Hue
    local h = 0
    if delta > 0 then
        if max == r then
            h = 60 * (((g - b) / delta) % 6)
        elseif max == g then
            h = 60 * (((b - r) / delta) + 2)
        else
            h = 60 * (((r - g) / delta) + 4)
        end
    end

    -- Normalize hue to 0-360
    if h < 0 then
        h = h + 360
    end

    return h, s, v
end

-- Cache
local cached = {
    night_mode = G_reader_settings:isTrue("night_mode"),
    invert_color = InvertFontColor.get(),
    hex = HexFontColor.get(),
    last_hex = nil,
    fgcolor = nil,
}

-- Recompute and cache the final fgcolor based on current settings
-- Applies night mode inversion if enabled, and updates cached.fgcolor only if it has changed
local function recomputeFGColor()
    local hex = cached.hex
    if cached.night_mode and not cached.invert_color then
        hex = invertColor(hex)
    end
    if hex ~= cached.last_hex then
        cached.fgcolor = Blitbuffer.colorFromString(hex)
        cached.last_hex = hex
    end
end

-- Compute and cache the initial fgcolor based on current settings
recomputeFGColor()

local function setFontColor(hex)
    HexFontColor.set(hex)
    cached.hex = hex
    recomputeFGColor()
end

-- Patch menus
local FileManagerMenu = require("apps/filemanager/filemanagermenu")
local ReaderMenu = require("apps/reader/modules/readermenu")
local _ = require("gettext")
local T = require("ffi/util").template

local function set_color_menu()
    InputDialog = require("ui/widget/inputdialog")
    return {
        text = _("Enter color code"),
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            local input_dialog
            input_dialog = InputDialog:new({
                title = "Enter custom color code",
                input = HexFontColor.get(),
                input_hint = "#000000",
                buttons = {
                    {
                        {
                            text = "Cancel",
                            callback = function()
                                UIManager:close(input_dialog)
                            end,
                        },
                        {
                            text = "Save",
                            callback = function()
                                local text = input_dialog:getInputText()

                                if text ~= "" then
                                    if not text:match("^#%x%x%x%x?%x?%x?$") then
                                        return
                                    end

                                    setFontColor(text)

                                    touchmenu_instance:updateItems()
                                    UIManager:close(input_dialog)
                                end
                            end,
                        },
                    },
                },
            })
            UIManager:show(input_dialog)
            input_dialog:onShowKeyboard()
        end,
    }
end

local has_ColorWheelWidget, ColorWheelWidget = pcall(require, "ui/widget/colorwheelwidget")

local function pick_color_menu()
    return {
        text = _("Pick color visually"),
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            local h, s, v = hexToHSV(HexFontColor.get())
            local wheel
            wheel = ColorWheelWidget:new({
                title_text = "Pick font color",
                hue = h,
                saturation = s,
                value = v,
                invert_in_night_mode = not InvertFontColor.get(),
                callback = function(hex)
                    setFontColor(hex)

                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                    UIManager:setDirty(nil, "ui")
                end,
                cancel_callback = function()
                    UIManager:setDirty(nil, "ui")
                end,
            })
            UIManager:show(wheel)
        end,
    }
end

local function font_color_menu()
    return {
        text_func = function()
            return T(_("UI font color: %1"), HexFontColor.get())
        end,
        sub_item_table_func = function()
            local items = {
                {
                    text_func = function()
                        return T(_("Current color: %1"), HexFontColor.get())
                    end,
                },
                set_color_menu(),
            }

            -- Add color picking menu if color wheel widget is present
            if has_ColorWheelWidget then
                table.insert(items, pick_color_menu())
            end

            table.insert(items, {
                text = _("Invert color in night mode"),
                checked_func = InvertFontColor.get,
                callback = function()
                    InvertFontColor.toggle()
                    cached.invert_color = InvertFontColor.get()
                    recomputeFGColor()
                end,
            })
            return items
        end,
    }
end

local function patch(menu, order)
    table.insert(order.setting, "----------------------------")
    table.insert(order.setting, "ui_font_color")
    menu.menu_items.ui_font_color = font_color_menu()
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

-- Hook into night mode state changes and update cache
function TextWidget:onToggleNightMode()
    cached.night_mode = not cached.night_mode
    recomputeFGColor()
end

function TextWidget:onSetNightMode(night_mode)
    if cached.night_mode ~= night_mode then
        cached.night_mode = night_mode
        recomputeFGColor()
    end
end

-- Hook into TextWidget painting
local original_TextWidget_paintTo = TextWidget.paintTo

function TextWidget:paintTo(bb, x, y)
    self.fgcolor = cached.fgcolor

    -- Use original B/W TextWidget painting method if color is not enabled
    if not Screen:isColorEnabled() then
        original_TextWidget_paintTo(self, bb, x, y)
    else
        self:updateSize()
        if self._is_empty then
            return
        end

        if not self.use_xtext then
            RenderText:renderUtf8Text(bb, x, y + self._baseline_h, self.face, self._text_to_draw,
                true, self.bold, self.fgcolor, self._length)
            return
        end

        -- Draw shaped glyphs with the help of xtext
        if not self._xshaping then
            self._xshaping = self._xtext:shapeLine(self._shape_start, self._shape_end,
                self._shape_idx_to_substitute_with_ellipsis)
        end

        -- Don't draw outside of BlitBuffer or max_width
        local text_width = bb:getWidth() - x
        if self.max_width and self.max_width < text_width then
            text_width = self.max_width
        end
        local pen_x = 0
        local baseline = self.forced_baseline or self._baseline_h
        for i, xglyph in ipairs(self._xshaping) do
            if pen_x >= text_width then
                break
            end
            local face = self.face.getFallbackFont(xglyph.font_num) -- callback (not a method)
            local glyph = RenderText:getGlyphByIndex(face, xglyph.glyph, self.bold)
            bb:colorblitFromRGB32(
                glyph.bb,
                x + pen_x + glyph.l + xglyph.x_offset,
                y + baseline - glyph.t - xglyph.y_offset,
                0, 0,
                glyph.bb:getWidth(), glyph.bb:getHeight(),
                self.fgcolor)
            pen_x = pen_x + xglyph.x_advance -- use Harfbuzz advance
        end
    end
end

-- Hook into TextBoxWidget text rendering
local original_TextBoxWidget_renderText = TextBoxWidget._renderText

function TextBoxWidget:_renderText(start_row_idx, end_row_idx)
    self.fgcolor = cached.fgcolor

    original_TextBoxWidget_renderText(self, start_row_idx, end_row_idx)
end
