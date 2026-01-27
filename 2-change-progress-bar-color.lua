--[[
    This user patch allows for changing the progress bar read & unread colors.
    It has menu options for the read and unread colors, and toggles to invert them in night mode.

    Source:
    -- Based on https://gist.github.com/IntrovertedMage/6ea38091292310241ba436f930ee0cb4

    Changes:
    -- Added night mode color correction
    -- Added reader settings persistence
--]]

local ReaderFooter = require("apps/reader/modules/readerfooter")
local ProgressWidget = require("ui/widget/progresswidget")
local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local Math = require("optmath")
local Screen = require("device").screen
local _ = require("gettext")
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template

-- Somewhat empirically chosen threshold to switch between the two designs ;o)
local INITIAL_MARKER_HEIGHT_THRESHOLD = Screen:scaleBySize(12)

-- Settings
local Settings = {}

local function colorAttrib(read)
    return read and "fillcolor" or "bgcolor"
end
local function getStyle(thin)
    return thin and "progress_style_thin_colors" or "progress_style_thick_colors"
end

function Settings:init(footer)
    local function defaultColor(thin)
        ProgressWidget:updateStyle(not thin, nil, false) -- no object needed, since height is nil, do no set colors
        local read, unread = colorAttrib(true), colorAttrib(false)
        return {
            [read] = "#808080",
            [unread] = "#c0c0c0",
        }
    end

    self.footer = footer
    self.default = {
        [getStyle(true)] = defaultColor(true),
        [getStyle(false)] = defaultColor(false),
    }
end

function Settings:getDefault(thin, color_attrib)
    local default = self.default[getStyle(thin)]
    return default[color_attrib]
end

function Settings:set(thin, color_attrib, color)
    local style = getStyle(thin)
    local settings = self.footer.settings[style] or {}
    settings[color_attrib] = color
    self.footer.settings[style] = settings
end

function Settings:getPersistent(thin, color_attrib)
    local key = getStyle(thin) .. "_" .. color_attrib
    local value = G_reader_settings:readSetting(key)
    if value then
        return value
    end
    return self:getDefault(thin, color_attrib)
end

function Settings:setPersistent(thin, color_attrib, color)
    local key = getStyle(thin) .. "_" .. color_attrib
    G_reader_settings:saveSetting(key, color)
    self:set(thin, color_attrib, color)
end

local function read_inverted_enabled()
    return G_reader_settings:isTrue("progress_bar_color_read_inverted", false)
end

local function unread_inverted_enabled()
    return G_reader_settings:isTrue("progress_bar_color_unread_inverted", true)
end

-- Helper: detect night mode
local function is_night_mode()
    return G_reader_settings:isTrue("night_mode")
end

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

local original_init = ReaderFooter.init

function ReaderFooter:init()
    Settings:init(self)
    original_init(self)
    self.progress_bar:_setColors(self.settings.progress_style_thin)
end

function ReaderFooter:onToggleNightMode()
    local read, unread = colorAttrib(true), colorAttrib(false)
    local thin = self.settings.progress_style_thin
    local readColor = Settings:getPersistent(thin, read)
    local unreadColor = Settings:getPersistent(thin, unread)

    if not is_night_mode() then
        if not keep_read_inverted_enabled() then
            readColor = invertColor(readColor)
        end
        if not keep_unread_inverted_enabled() then
            unreadColor = invertColor(unreadColor)
        end
    end

    self.progress_bar[read]   = Blitbuffer.colorFromString(readColor)
    self.progress_bar[unread] = Blitbuffer.colorFromString(unreadColor)

    self:refreshFooter(true)
end

function ReaderFooter:onSetNightMode(night_mode)
    local read, unread = colorAttrib(true), colorAttrib(false)
    local thin = self.settings.progress_style_thin
    local readColor = Settings:getPersistent(thin, read)
    local unreadColor = Settings:getPersistent(thin, unread)

    if night_mode then
        if not keep_read_inverted_enabled() then
            readColor = invertColor(readColor)
        end
        if not keep_unread_inverted_enabled() then
            unreadColor = invertColor(unreadColor)
        end
    end

    self.progress_bar[read]   = Blitbuffer.colorFromString(readColor)
    self.progress_bar[unread] = Blitbuffer.colorFromString(unreadColor)

    self:refreshFooter(true)
end

local original_loadPreset = ReaderFooter.loadPreset

function ReaderFooter:loadPreset(preset)
    original_loadPreset(self, preset)
    self.progress_bar:_setColors(self.settings.progress_style_thin)
end

function ProgressWidget:_setColors(thin)
    local read, unread = colorAttrib(true), colorAttrib(false)

    local readColor    = Settings:getPersistent(thin, read)
    local unreadColor  = Settings:getPersistent(thin, unread)

    if not readColor:match("^#%x%x%x%x?%x?%x?$") then
        readColor = "#808080"
        Settings:setPersistent(thin, read, readColor)
    end

    if not unreadColor:match("^#%x%x%x%x?%x?%x?$") then
        unreadColor = "#c0c0c0"
        Settings:setPersistent(thin, unread, unreadColor)
    end

    if is_night_mode() then
        if not keep_read_inverted_enabled() then
            readColor = invertColor(readColor)
        end
        if not keep_unread_inverted_enabled() then
            unreadColor = invertColor(unreadColor)
        end
    end

    self[read]   = Blitbuffer.colorFromString(readColor)
    self[unread] = Blitbuffer.colorFromString(unreadColor)
end

local orig_ProgressWidget_updateStyle = ProgressWidget.updateStyle

function ProgressWidget:updateStyle(thick, height, do_setcolors)
    do_setcolors = do_setcolors or do_setcolors == nil -- default: do_setcolors = trues
    orig_ProgressWidget_updateStyle(self, thick, height)
    if do_setcolors then self:_setColors(not thick) end
end

local function getMenuItem(menu, ...) -- path
    local function findItem(sub_items, texts)
        local find = {}
        local texts = type(texts) == "table" and texts or { texts }
        -- stylua: ignore
        for _, text in ipairs(texts) do find[text] = true end
        for _, item in ipairs(sub_items) do
            local text = item.text or (item.text_func and item.text_func())
            if text and find[text] then
                return item
            end
        end
    end

    local sub_items, item
    for _, texts in ipairs({ ... }) do -- walk path
        sub_items = (item or menu).sub_item_table
        if not sub_items then
            return
        end
        item = findItem(sub_items, texts)
        if not item then
            return
        end
    end
    return item
end

function ReaderFooter:_statusBarColorMenu(read)
    InputDialog = require("ui/widget/inputdialog")
    local color_attrib = colorAttrib(read)
    return {
        text_func = function()
            return T(read and "Read color: %1" or "Unread color: %1",
                Settings:getPersistent(self.settings.progress_style_thin, color_attrib))
        end,
        keep_menu_open = true,
        enabled_func = function()
            return not self.settings.disable_progress_bar
        end,
        callback = function(touchmenu_instance)
            local input_dialog
            input_dialog = InputDialog:new({
                title = "Enter color hex code for " .. (read and "read color" or "unread color"),
                input = Settings:getPersistent(self.settings.progress_style_thin, color_attrib),
                input_hint = "#ffffff",
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

                                    -- Process color depending on if the color should be inverted in night mode
                                    local displayText = text
                                    if is_night_mode() then
                                        if (read and not keep_read_inverted_enabled()) or
                                            (not read and not keep_unread_inverted_enabled()) then
                                            displayText = invertColor(text)
                                        end
                                    end
                                    local color = Blitbuffer.colorFromString(displayText)

                                    if not color then
                                        return
                                    end

                                    Settings:setPersistent(self.settings.progress_style_thin, color_attrib, text)
                                    self.progress_bar[color_attrib] = color
                                    touchmenu_instance:updateItems()
                                    self:refreshFooter(true)
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

function ReaderFooter:_invertColorMenu(read)
    local text = "Invert read color in night mode"
    if not read then
        text = "Invert unread color in night mode"
    end
    local setting = read and "progress_bar_color_read_inverted" or "progress_bar_color_unread_inverted"
    local is_enabled = read and read_inverted_enabled or unread_inverted_enabled

    return {
        text = _(text),
        checked_func = is_enabled,
        callback = function()
            G_reader_settings:saveSetting(setting, not is_enabled())
            self.progress_bar:_setColors(self.settings.progress_style_thin)
            self:refreshFooter(true)
        end,
    }
end

local original_ReaderFooter_addToMainMenu = ReaderFooter.addToMainMenu

function ReaderFooter:addToMainMenu(menu_items)
    original_ReaderFooter_addToMainMenu(self, menu_items)

    local item = getMenuItem(
        menu_items.status_bar,
        _("Progress bar"),
        { _("Thickness and height: thin"), _("Thickness and height: thick") }
    )
    if item then
        item.text_func = function()
            return self.settings.progress_style_thin and _("Thickness, height & colors: thin")
                or _("Thickness, height & colors: thick")
        end
        table.insert(item.sub_item_table, self:_statusBarColorMenu(true))
        table.insert(item.sub_item_table, self:_statusBarColorMenu(false))
        table.insert(item.sub_item_table, self:_invertColorMenu(true))
        table.insert(item.sub_item_table, self:_invertColorMenu(false))
    end
end

function ProgressWidget:paintTo(bb, x, y)
    local my_size = self:getSize()
    if not self.dimen then
        self.dimen = Geom:new({
            x = x,
            y = y,
            w = my_size.w,
            h = my_size.h,
        })
    else
        self.dimen.x = x
        self.dimen.y = y
    end
    if self.dimen.w == 0 or self.dimen.h == 0 then
        return
    end

    local _mirroredUI = BD.mirroredUILayout()
    -- We'll draw every bar element in order, bottom to top.
    local fill_width = my_size.w - 2 * (self.margin_h + self.bordersize)
    local fill_y = y + self.margin_v + self.bordersize
    local fill_height = my_size.h - 2 * (self.margin_v + self.bordersize)

    if self.radius == 0 then
        -- If we don't have rounded borders, we can start with a simple border colored rectangle.
        bb:paintRect(x, y, my_size.w, my_size.h, self.bordercolor)
        -- And a full background bar inside (i.e., on top) of that.
        bb:paintRectRGB32(
            x + self.margin_h + self.bordersize,
            fill_y,
            math.ceil(fill_width),
            math.ceil(fill_height),
            self.bgcolor
        )
    else
        -- Otherwise, we have to start with the background.
        -- Normally rounded but no rounded color support currently
        bb:paintRectRGB32(x, y, my_size.w, my_size.h, self.bgcolor)
        -- Then the border around that.
        bb:paintBorder(
            math.floor(x),
            math.floor(y),
            my_size.w,
            my_size.h,
            self.bordersize,
            self.bordercolor,
            self.radius
        )
    end

    -- Then we can just paint the fill rectangle(s) and tick(s) on top of that.
    -- First the fill bar(s)...
    -- Fill bar for alternate pages (e.g. non-linear flows).
    if self.alt and self.alt[1] ~= nil then
        for i = 1, #self.alt do
            local tick_x = fill_width * ((self.alt[i][1] - 1) / self.last)
            local width = fill_width * (self.alt[i][2] / self.last)
            if _mirroredUI then
                tick_x = fill_width - tick_x - width
            end
            tick_x = math.floor(tick_x)
            width = math.ceil(width)

            bb:paintRectRGB32(
                x + self.margin_h + self.bordersize + tick_x,
                fill_y,
                width,
                math.ceil(fill_height),
                self.altcolor
            )
        end
    end

    -- Main fill bar for the specified percentage.
    if self.percentage >= 0 and self.percentage <= 1 then
        local fill_x = x + self.margin_h + self.bordersize
        if self.fill_from_right or (_mirroredUI and not self.fill_from_right) then
            fill_x = fill_x + (fill_width * (1 - self.percentage))
            fill_x = math.floor(fill_x)
        end

        bb:paintRectRGB32(
            fill_x,
            fill_y,
            math.ceil(fill_width * self.percentage),
            math.ceil(fill_height),
            self.fillcolor
        )

        -- Overlay the initial position marker on top of that
        if self.initial_pos_marker and self.initial_percentage >= 0 then
            if self.height <= INITIAL_MARKER_HEIGHT_THRESHOLD then
                self.initial_pos_icon:paintTo(
                    bb,
                    Math.round(fill_x + math.ceil(fill_width * self.initial_percentage) - self.height / 4),
                    y - Math.round(self.height / 6)
                )
            else
                self.initial_pos_icon:paintTo(
                    bb,
                    Math.round(fill_x + math.ceil(fill_width * self.initial_percentage) - self.height / 2),
                    y
                )
            end
        end
    end

    -- ...then the tick(s).
    if self.ticks and self.last and self.last > 0 then
        for i, tick in ipairs(self.ticks) do
            local tick_x = fill_width * (tick / self.last)
            if _mirroredUI then
                tick_x = fill_width - tick_x
            end
            tick_x = math.floor(tick_x)

            bb:paintRect(
                x + self.margin_h + self.bordersize + tick_x,
                fill_y,
                self.tick_width,
                math.ceil(fill_height),
                self.bordercolor
            )
        end
    end
end
