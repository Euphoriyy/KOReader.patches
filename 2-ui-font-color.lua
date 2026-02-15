--[[
    This user patch allows for changing the UI font color.
    It has the following menu options in addition to the color:
        - A toggle to use an alternative color in night mode.
        - A toggle to invert it in night mode.
        - A toggle for affecting TextBoxWidgets.
        - A toggle for affecting the dictionary text.
        - A toggle for changing the page font color (EPUB/HTML).
    Optionally, the color can be set with a color picker.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local DictQuickLookup = require("ui/widget/dictquicklookup")
local Event = require("ui/event")
local FileManager = require("apps/filemanager/filemanager")
local ReaderStyleTweak = require("apps/reader/modules/readerstyletweak")
local ReaderUI = require("apps/reader/readerui")
local RenderText = require("ui/rendertext")
local Screen = require("device").screen
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local util = require("util")

local function Setting(name, default)
    local self = {}
    self.get = function() return G_reader_settings:readSetting(name, default) end
    self.set = function(value) return G_reader_settings:saveSetting(name, value) end
    self.toggle = function() G_reader_settings:toggle(name) end
    return self
end

-- Settings
local HexFontColor = Setting("ui_font_color_hex", "#000000")            -- RGB hex for UI font color (default: #000000)
local InvertFontColor = Setting("ui_font_color_inverted", true)         -- Whether the UI font color should be inverted in night mode (default: true)
local AltNightFontColor = Setting("ui_font_color_alt_night", false)     -- Whether the UI font color should be changed to an alternative color in night mode (default: false)
local NightHexFontColor = Setting("ui_font_color_night_hex", "#ffffff") -- RGB hex for the alternative UI font color in night mode (default: #ffffff)
local TextBoxFontColor = Setting("ui_font_color_textbox", true)         -- Whether the font color of TextBoxWidgets should be changed (default: true)
local DictionaryFontColor = Setting("ui_font_color_dict", true)         -- Whether the font color of the dictionary should be changed (default: true)
local PageFontColor = Setting("ui_font_color_reader_page", false)       -- Whether the font color of the page should be changed (default: false)

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

-- Helper: check if two colors are equal
local function colorEquals(c1, c2)
    if not c1 or not c2 then return false end
    return c1:getColorRGB32() == c2:getColorRGB32()
end

-- Helper: compute luminance of a color (0 = black, 1 = white)
local function luminance(color)
    return 0.299 * color:getR() + 0.587 * color:getG() + 0.114 * color:getB()
end

-- Helper: compute contrast between two colors
local function contrast(c1, c2)
    return math.abs(luminance(c1) - luminance(c2))
end

-- Helper: check if we have a document open
local function has_document_open()
    return ReaderUI.instance ~= nil and ReaderUI.instance.document ~= nil
end

-- Helper: lighten a color by a percentage
local function lightenColor(c, amount)
    local r = c:getR()
    local g = c:getG()
    local b = c:getB()

    return Blitbuffer.ColorRGB32(
        math.floor(r + (255 - r) * amount),
        math.floor(g + (255 - g) * amount),
        math.floor(b + (255 - b) * amount)
    )
end

-- Cache
local cached = {
    night_mode = G_reader_settings:isTrue("night_mode"),
    alt_night_color = AltNightFontColor.get(),
    invert_in_night_mode = InvertFontColor.get(),
    set_textbox_color = TextBoxFontColor.get(),
    set_dictionary_color = DictionaryFontColor.get(),
    set_page_color = PageFontColor.get(),
    hex = HexFontColor.get(),
    night_hex = NightHexFontColor.get(),
    last_hex = nil,
    fgcolor = nil,
}

-- Recompute and cache the final fgcolor based on current settings
-- Applies night mode inversion if enabled, and updates cached.fgcolor only if it has changed
local function recomputeFGColor()
    local hex = (cached.night_mode and cached.alt_night_color) and cached.night_hex or cached.hex
    if cached.night_mode then
        if cached.alt_night_color or not cached.invert_in_night_mode then
            hex = invertColor(hex)
        end
    end
    if hex ~= cached.last_hex then
        cached.fgcolor = Blitbuffer.colorFromString(hex)
        cached.last_hex = hex
    end
end

-- Compute and cache the initial fgcolor based on current settings
recomputeFGColor()

local function refreshFileManager()
    if FileManager.instance then
        FileManager.instance.file_chooser:updateItems(1, true)
    end
end

local function getFontColor()
    if cached.night_mode and cached.alt_night_color then
        return NightHexFontColor.get()
    else
        return HexFontColor.get()
    end
end

local function setFontColor(hex)
    if cached.night_mode and cached.alt_night_color then
        NightHexFontColor.set(hex)
        cached.night_hex = hex
    else
        HexFontColor.set(hex)
        cached.hex = hex
    end

    recomputeFGColor()

    -- If TextBoxWidget colors are enabled, then update the file list
    if cached.set_textbox_color then
        refreshFileManager()
    end

    -- Reapply page CSS
    if cached.set_page_color and has_document_open() then
        UIManager:broadcastEvent(Event:new("ApplyStyleSheet"))
    end
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
                input = getFontColor(),
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
                                    if not text:match("^#%x%x%x%x%x%x$") then
                                        return
                                    end

                                    setFontColor(string.upper(text))

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
            local h, s, v = hexToHSV(getFontColor())
            local wheel
            local should_invert_wheel = AltNightFontColor.get() or not InvertFontColor.get()
            wheel = ColorWheelWidget:new({
                title_text = "Pick font color",
                hue = h,
                saturation = s,
                value = v,
                invert_in_night_mode = should_invert_wheel,
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
            return T(_("UI font color: %1"), getFontColor())
        end,
        sub_item_table_func = function()
            local items = {
                {
                    text_func = function()
                        return T(_("Current color: %1"), getFontColor())
                    end,
                },
                set_color_menu(),
            }

            -- Add color picking menu if color wheel widget is present
            if has_ColorWheelWidget then
                table.insert(items, pick_color_menu())
            end

            table.insert(items, {
                text = _("Alternative night mode color"),
                checked_func = AltNightFontColor.get,
                callback = function()
                    AltNightFontColor.toggle()
                    cached.alt_night_color = AltNightFontColor.get()

                    if cached.night_mode then
                        recomputeFGColor()

                        if cached.set_textbox_color then
                            refreshFileManager()
                        end

                        if cached.set_page_color and has_document_open() then
                            UIManager:broadcastEvent(Event:new("ApplyStyleSheet"))
                        end
                    end
                end,
            })

            table.insert(items, {
                text = _("Invert color in night mode"),
                enabled_func = function() return not AltNightFontColor.get() end,
                checked_func = InvertFontColor.get,
                callback = function()
                    InvertFontColor.toggle()
                    cached.invert_in_night_mode = InvertFontColor.get()
                    recomputeFGColor()

                    if cached.night_mode then
                        if cached.set_textbox_color then
                            refreshFileManager()
                        end

                        if cached.set_page_color and has_document_open() then
                            UIManager:broadcastEvent(Event:new("ApplyStyleSheet"))
                        end
                    end
                end,
            })

            table.insert(items, {
                text = _("Apply to text boxes (CoverBrowser)"),
                checked_func = TextBoxFontColor.get,
                callback = function()
                    TextBoxFontColor.toggle()
                    cached.set_textbox_color = TextBoxFontColor.get()

                    -- Update the file list
                    refreshFileManager()
                end,
            })

            table.insert(items, {
                text = _("Apply to dictionary text"),
                checked_func = DictionaryFontColor.get,
                callback = function()
                    DictionaryFontColor.toggle()
                    cached.set_dictionary_color = DictionaryFontColor.get()
                end,
            })

            table.insert(items, {
                text = _("Apply to reader pages (EPUB/HTML)"),
                checked_func = PageFontColor.get,
                callback = function()
                    PageFontColor.toggle()
                    cached.set_page_color = PageFontColor.get()

                    if has_document_open() then
                        UIManager:broadcastEvent(Event:new("ApplyStyleSheet"))
                    end
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
local original_UIManager_ToggleNightMode = UIManager.ToggleNightMode

function UIManager:ToggleNightMode()
    original_UIManager_ToggleNightMode(self)

    cached.night_mode = not cached.night_mode
    recomputeFGColor()

    if cached.alt_night_color or not cached.invert_in_night_mode then
        -- Refresh files if CoverBrowser is affected and night mode inversion is not enabled
        if cached.set_textbox_color then
            refreshFileManager()
        end

        if cached.set_page_color and has_document_open() then
            UIManager:broadcastEvent(Event:new("ApplyStyleSheet"))
        end
    end
end

local original_UIManager_SetNightMode = UIManager.SetNightMode

function UIManager:SetNightMode(night_mode)
    original_UIManager_SetNightMode(self)

    if cached.night_mode ~= night_mode then
        cached.night_mode = night_mode
        recomputeFGColor()

        if cached.alt_night_color or not cached.invert_in_night_mode then
            if cached.set_textbox_color then
                refreshFileManager()
            end

            if cached.set_page_color and has_document_open() then
                UIManager:broadcastEvent(Event:new("ApplyStyleSheet"))
            end
        end
    end
end

-- Hook into TextWidget painting
local original_TextWidget_paintTo = TextWidget.paintTo

function TextWidget:paintTo(bb, x, y)
    local original_fgcolor = self.fgcolor

    -- If the original color was dark gray, then place a lighter color
    if colorEquals(original_fgcolor, Blitbuffer.COLOR_DARK_GRAY) then
        self.fgcolor = lightenColor(cached.fgcolor, 0.5)

        -- Set font color to dark gray when more contrast is needed
        if contrast(self.fgcolor, cached.fgcolor) < 10 then
            self.fgcolor = Blitbuffer.COLOR_DARK_GRAY
        end
    else
        self.fgcolor = cached.fgcolor
    end

    -- Use original B/W TextWidget painting method if color is not enabled
    if not Screen:isColorEnabled() then
        original_TextWidget_paintTo(self, bb, x, y)
        self.fgcolor = original_fgcolor
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

    self.fgcolor = original_fgcolor
end

-- Hook into TextBoxWidget text rendering
local original_TextBoxWidget_renderText = TextBoxWidget._renderText

function TextBoxWidget:_renderText(start_row_idx, end_row_idx)
    local original_fgcolor = self.fgcolor

    if cached.set_textbox_color then
        self.fgcolor = cached.fgcolor
    end

    original_TextBoxWidget_renderText(self, start_row_idx, end_row_idx)

    self.fgcolor = original_fgcolor
end

-- Add font color CSS to HTML dictionary
local original_DictQuickLookup_getHtmlDictionaryCss = DictQuickLookup.getHtmlDictionaryCss

function DictQuickLookup:getHtmlDictionaryCss()
    local original_css = original_DictQuickLookup_getHtmlDictionaryCss(self)

    if cached.set_dictionary_color then
        local fg_hex = (cached.night_mode and cached.alt_night_color) and cached.night_hex or cached.hex
        if cached.night_mode then
            if cached.alt_night_color or not cached.invert_in_night_mode then
                fg_hex = invertColor(fg_hex)
            end
        end
        local custom_css = [[
            body {
                color: ]] .. fg_hex .. [[;
            }
        ]]

        return original_css .. custom_css
    else
        return original_css
    end
end

-- Add font color to reader style tweak CSS if enabled
local original_ReaderStyleTweak_getCssText = ReaderStyleTweak.getCssText

function ReaderStyleTweak:getCssText()
    local original_css = original_ReaderStyleTweak_getCssText(self)

    if cached.set_page_color then
        local fg_hex = (cached.night_mode and cached.alt_night_color) and cached.night_hex or cached.hex
        if cached.night_mode then
            if cached.alt_night_color or not cached.invert_in_night_mode then
                fg_hex = invertColor(fg_hex)
            end
        end

        local fg_css = [[
            body {
                color: ]] .. fg_hex .. [[;
            }
        ]]
        return util.trim(fg_css .. original_css)
    else
        return original_css
    end
end
