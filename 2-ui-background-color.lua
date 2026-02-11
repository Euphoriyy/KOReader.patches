--[[
    This user patch allows for changing the UI background color.
    It has the following menu options in addition to the color:
        - A toggle to invert it in night mode.
        - A toggle for affecting TextBoxWidgets.
        - A toggle for affecting the ReaderFooter.
    Optionally, the color can be set with a color picker.
--]]

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Cache = require("cache")
local DictQuickLookup = require("ui/widget/dictquicklookup")
local FileManager = require("apps/filemanager/filemanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HtmlBoxWidget = require("ui/widget/htmlboxwidget")
local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget")
local InputText = require("ui/widget/inputtext")
local LineWidget = require("ui/widget/linewidget")
local ReaderFooter = require("apps/reader/modules/readerfooter")
local RenderImage = require("ui/renderimage")
local Screen = require("device").screen
local ScreenSaverWidget = require("ui/widget/screensaverwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")
local ffi = require("ffi")
local logger = require("logger")
local util = require("util")

local function Setting(name, default)
    local self = {}
    self.get = function() return G_reader_settings:readSetting(name, default) end
    self.set = function(value) return G_reader_settings:saveSetting(name, value) end
    self.toggle = function() G_reader_settings:toggle(name) end
    return self
end

-- Settings
local HexBackgroundColor = Setting("ui_background_color_hex", "#ffffff")          -- RGB hex for UI background color (default: #ffffff)
local InvertBackgroundColor = Setting("ui_background_color_inverted", true)       -- Whether the UI background color should be inverted in night mode (default: true)
local TextBoxBackgroundColor = Setting("ui_background_color_textbox", true)       -- Whether the background color of TextBoxWidgets should be changed (default: true)
local FooterBackgroundColor = Setting("ui_background_color_reader_footer", false) -- Whether the background color of the ReaderFooter should be changed (default: false)

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

------------------------------------------------------------
-- ImageWidget specific code
------------------------------------------------------------

-- DPI_SCALE can't change without a restart, so let's compute it now
local function get_dpi_scale()
    local size_scale = math.min(Screen:getWidth(), Screen:getHeight()) * (1 / 600)
    local dpi_scale = Screen:scaleByDPI(1)
    return math.max(0, (math.log((size_scale + dpi_scale) / 2) / 0.69) ^ 2)
end
local DPI_SCALE = get_dpi_scale()

local ImageCache = Cache:new {
    -- 8 MiB of image cache, with 128 slots
    -- Overwhelmingly used for our icons, which are tiny in size, and not very numerous (< 100),
    -- but also by ImageViewer (on files, which we never do), and ScreenSaver (again, on image files, but not covers),
    -- hence the leeway.
    size = 8 * 1024 * 1024,
    avg_itemsize = 64 * 1024,
    -- Rely on our FFI finalizer to free the BBs on GC
    enable_eviction_cb = false,
}

local uint8pt = ffi.typeof("uint8_t*")

-- color value pointer types
local P_Color8A = ffi.typeof("Color8A*")
local P_ColorRGB16 = ffi.typeof("ColorRGB16*")
local P_ColorRGB32 = ffi.typeof("ColorRGB32*")

--------------------------------------------
-- Background Color
--------------------------------------------

-- Cache
local bg_cached = {
    night_mode = G_reader_settings:isTrue("night_mode"),
    invert_in_night_mode = InvertBackgroundColor.get(),
    set_textbox_colors = TextBoxBackgroundColor.get(),
    set_footer_color = FooterBackgroundColor.get(),
    hex = HexBackgroundColor.get(),
    last_hex = nil,
    bgcolor = nil,
}

-- Recompute and cache the final bgcolor based on current settings
-- Applies night mode inversion if enabled, and updates bg_cached.bgcolor only if it has changed
local function recomputeBGColor()
    local hex = bg_cached.hex
    if bg_cached.night_mode and not bg_cached.invert_in_night_mode then
        hex = invertColor(hex)
    end
    if hex ~= bg_cached.last_hex then
        bg_cached.bgcolor = Blitbuffer.colorFromString(hex)
        bg_cached.last_hex = hex
    end
end

-- Compute and cache the initial bgcolor based on current settings
recomputeBGColor()

local function refreshFileManager()
    if FileManager.instance then
        FileManager.instance.file_chooser:updateItems(1, true)
    end
end

local function setBackgroundColor(hex)
    HexBackgroundColor.set(hex)
    bg_cached.hex = hex
    recomputeBGColor()

    -- If TextBoxWidget colors are enabled, then update the file list
    if bg_cached.set_textbox_colors then
        refreshFileManager()
    end

    ImageCache:clear()

    -- Ask for restart, otherwise icon backgrounds may fail to be filled
    UIManager:askForRestart()
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
                input = HexBackgroundColor.get(),
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

                                    setBackgroundColor(text)

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
            local h, s, v = hexToHSV(HexBackgroundColor.get())
            local wheel
            wheel = ColorWheelWidget:new({
                title_text = "Pick background color",
                hue = h,
                saturation = s,
                value = v,
                invert_in_night_mode = not InvertBackgroundColor.get(),
                callback = function(hex)
                    setBackgroundColor(hex)

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

local function background_color_menu()
    return {
        text_func = function()
            return T(_("UI background color: %1"), HexBackgroundColor.get())
        end,
        sub_item_table_func = function()
            local items = {
                {
                    text_func = function()
                        return T(_("Current color: %1"), HexBackgroundColor.get())
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
                checked_func = InvertBackgroundColor.get,
                callback = function()
                    InvertBackgroundColor.toggle()
                    bg_cached.invert_in_night_mode = InvertBackgroundColor.get()
                    recomputeBGColor()

                    if bg_cached.set_textbox_colors then
                        refreshFileManager()
                    end

                    ImageCache:clear()

                    -- Ask for restart, otherwise icon backgrounds may fail to be filled
                    UIManager:askForRestart()
                end,
            })

            table.insert(items, {
                text = _("Apply to text boxes (CoverBrowser)"),
                checked_func = TextBoxBackgroundColor.get,
                callback = function()
                    TextBoxBackgroundColor.toggle()
                    bg_cached.set_textbox_colors = TextBoxBackgroundColor.get()

                    -- Update the file list
                    refreshFileManager()
                end,
            })

            table.insert(items, {
                text = _("Apply to the reader footer"),
                checked_func = FooterBackgroundColor.get,
                callback = function()
                    FooterBackgroundColor.toggle()
                    bg_cached.set_footer_color = FooterBackgroundColor.get()
                end,
            })
            return items
        end,
    }
end

local function patch(menu, order)
    table.insert(order.setting, "----------------------------")
    table.insert(order.setting, "ui_background_color")
    menu.menu_items.ui_background_color = background_color_menu()
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

-- Special color which indicates that the color should either stay white or be set to the original bgcolor
-- Used for ReaderFooter option and ScreenSaverWidget
local EXCLUSION_COLOR = Blitbuffer.colorFromString("#DAAAAD")

-- Hook into FrameContainer painting (responsible for 80% of background)
local original_FrameContainer_paintTo = FrameContainer.paintTo

function FrameContainer:paintTo(bb, x, y)
    local original_background = self.background
    local original_color = self.color

    -- Change background color if it isn't transparent (nil)
    if original_background then
        if not colorEquals(original_background, EXCLUSION_COLOR) then
            self.background = bg_cached.bgcolor
            self.color = bg_cached.bgcolor:invert()
        else
            self.background = self.original_background or Blitbuffer.COLOR_WHITE
        end
    end

    original_FrameContainer_paintTo(self, bb, x, y)

    self.background = original_background
    self.color = original_color
end

-- Exclude footer background color changes if option is not set
local original_ReaderFooter_updateFooterContainer = ReaderFooter.updateFooterContainer

function ReaderFooter:updateFooterContainer()
    original_ReaderFooter_updateFooterContainer(self)

    if not bg_cached.set_footer_color then
        self.footer_content.background = EXCLUSION_COLOR
    end
end

-- Exclude ScreenSaverWidget from background color changes
local original_ScreenSaverWidget_init = ScreenSaverWidget.init

function ScreenSaverWidget:init()
    original_ScreenSaverWidget_init(self)

    self[1].original_background = self.background
    self[1].background = EXCLUSION_COLOR
end

-- Method to fill icon backgrounds
-- RGB version of Blitbuffer:fill
local function fillRGB(bb, bbtype, v)
    -- While we could use a plain ffi.fill, there are a few BB types where we do not want to stomp on the alpha byte...

    -- Handle invert...
    if bb:getInverse() == 1 then v = v:invert() end

    --print("fill")
    if bbtype == Blitbuffer.TYPE_BBRGB32 then
        local src = v:getColorRGB32()
        local p = ffi.cast(P_ColorRGB32, bb.data)
        for i = 1, bb.pixel_stride * bb.h do
            p[0] = src
            -- Pointer arithmetics magic: +1 on an uint32_t* means +4 bytes (i.e., next pixel) ;).
            p = p + 1
        end
    elseif bbtype == Blitbuffer.TYPE_BBRGB16 then
        local src = v:getColorRGB16()
        local p = ffi.cast(P_ColorRGB16, bb.data)
        for i = 1, bb.pixel_stride * bb.h do
            p[0] = src
            p = p + 1
        end
    elseif bbtype == Blitbuffer.TYPE_BB8A then
        local src = v:getColor8A()
        local p = ffi.cast(P_Color8A, bb.data)
        for i = 1, bb.pixel_stride * bb.h do
            p[0] = src
            p = p + 1
        end
    else
        -- Should only be BBRGB24 & BB8 left, where we can use ffi.fill ;)
        local p = ffi.cast(uint8pt, bb.data)
        ffi.fill(p, bb.stride * bb.h, v.alpha)
    end
end

-- Replace ImageWidget loading method
-- Responsible for icons matching the background
function ImageWidget:_loadfile()
    local DocumentRegistry = require("document/documentregistry")
    if DocumentRegistry:isImageFile(self.file) then
        -- In our use cases for files (icons), we either provide width and height,
        -- or just scale_for_dpi, and scale_factor should stay nil.
        -- Other combinations will result in double scaling, and unexpected results.
        -- We should anyway only give self.width and self.height to renderImageFile(),
        -- and use them in cache hash, when self.scale_factor is nil, when we are sure
        -- we don't need to keep aspect ratio.
        local width, height
        if self.scale_factor == nil and self.stretch_limit_percentage == nil then
            width = self.width
            height = self.height
        end
        local hash = "image|" ..
            self.file .. "|" .. tostring(width) .. "|" .. tostring(height) .. "|" .. (self.alpha and "alpha" or "flat")
        -- Do the scaling for DPI here, so it can be cached and not re-done
        -- each time in _render() (but not if scale_factor, to avoid double scaling)
        local scale_for_dpi_here = false
        if self.scale_for_dpi and DPI_SCALE ~= 1 and not self.scale_factor then
            scale_for_dpi_here = true          -- we'll do it before caching
            hash = hash .. "|d"
            self.already_scaled_for_dpi = true -- so we don't do it again in _render()
        end
        local cached = ImageCache:check(hash)
        if cached then
            -- hit cache
            self._bb = cached.bb
            self._bb_disposable = false -- don't touch or free a cached _bb
            self._is_straight_alpha = cached.is_straight_alpha
        else
            if util.getFileNameSuffix(self.file) == "svg" then
                local zoom
                if scale_for_dpi_here then
                    zoom = DPI_SCALE
                elseif self.scale_factor == 0 then
                    -- renderSVGImageFile() keeps aspect ratio by default
                    width = self.width
                    height = self.height
                end
                -- If NanoSVG is used by renderSVGImageFile, we'll get self._is_straight_alpha=true,
                -- and paintTo() must use alphablitFrom() instead of pmulalphablitFrom() (which is
                -- fine for everything MuPDF renders out)
                self._bb, self._is_straight_alpha = RenderImage:renderSVGImageFile(self.file, width, height, zoom)

                -- Ensure we always return a BB, even on failure
                if not self._bb then
                    logger.warn("ImageWidget: Failed to render SVG image file:", self.file)
                    self._bb = RenderImage:renderCheckerboard(width, height, Screen.bb:getType())
                    self._is_straight_alpha = false
                end
            else
                self._bb = RenderImage:renderImageFile(self.file, false, width, height)

                if not self._bb then
                    logger.warn("ImageWidget: Failed to render image file:", self.file)
                    self._bb = RenderImage:renderCheckerboard(width, height, Screen.bb:getType())
                    self._is_straight_alpha = false
                end

                if scale_for_dpi_here then
                    local bb_w, bb_h = self._bb:getWidth(), self._bb:getHeight()
                    self._bb = RenderImage:scaleBlitBuffer(self._bb, math.floor(bb_w * DPI_SCALE),
                        math.floor(bb_h * DPI_SCALE))
                end
            end

            -- Now, if that was *also* one of our icons, we haven't explicitly requested to keep the alpha channel intact,
            -- and it actually has an alpha channel, compose it against a background-colored BB now, and cache *that*.
            -- This helps us avoid repeating alpha-blending steps down the line,
            -- and also ensures icon highlights/unhighlights behave sensibly.
            if self.is_icon and not self.alpha then
                local bbtype = self._bb:getType()
                if bbtype == Blitbuffer.TYPE_BB8A or bbtype == Blitbuffer.TYPE_BBRGB32 then
                    -- Invert so that icons stay the same
                    if Screen.night_mode and not bg_cached.invert_in_night_mode then
                        self._bb:invert()
                    end

                    local icon_bb = Blitbuffer.new(self._bb.w, self._bb.h, Screen.bb:getType())

                    -- Fill icon's background with custom background color
                    if bg_cached.bgcolor then
                        fillRGB(icon_bb, Screen.bb:getType(), bg_cached.bgcolor)
                    end

                    -- And now simply compose the icon on top of that, with dithering if necessary
                    -- Remembering that NanoSVG feeds us straight alpha, unlike MµPDF
                    if self._is_straight_alpha then
                        if Screen.sw_dithering then
                            icon_bb:ditheralphablitFrom(self._bb, 0, 0, 0, 0, icon_bb.w, icon_bb.h)
                        else
                            icon_bb:alphablitFrom(self._bb, 0, 0, 0, 0, icon_bb.w, icon_bb.h)
                        end
                    else
                        if Screen.sw_dithering then
                            icon_bb:ditherpmulalphablitFrom(self._bb, 0, 0, 0, 0, icon_bb.w, icon_bb.h)
                        else
                            icon_bb:pmulalphablitFrom(self._bb, 0, 0, 0, 0, icon_bb.w, icon_bb.h)
                        end
                    end

                    -- Reinvert back to original
                    if Screen.night_mode and not bg_cached.invert_in_night_mode then
                        self._bb:invert()
                    end

                    -- Save the original alpha-channel icon for alpha masks and the flattened one
                    self._unflattened = self._bb
                    self._bb = icon_bb

                    -- There's no longer an alpha channel ;)
                    self._is_straight_alpha = nil
                end
            end

            if not self.file_do_cache then
                self._bb_disposable = true  -- we made it, we can modify and free it
            else
                self._bb_disposable = false -- don't touch or free a cached _bb
                -- cache this image
                logger.dbg("cache", hash)
                cached = {
                    bb = self._bb,
                    is_straight_alpha = self._is_straight_alpha,
                }
                ImageCache:insert(hash, cached, tonumber(cached.bb.stride) * cached.bb.h)
            end
        end
    else
        error("Image file type not supported.")
    end
end

-- Replace ImageWidget painting to fix RGB dimming
function ImageWidget:paintTo(bb, x, y)
    if self.hide then return end
    -- self:_render is called in getSize method
    local size = self:getSize()
    if not self.dimen then
        self.dimen = Geom:new {
            x = x, y = y,
            w = size.w,
            h = size.h
        }
    else
        self.dimen.x = x
        self.dimen.y = y
    end
    logger.dbg("blitFrom", x, y, self._offset_x, self._offset_y, size.w, size.h)
    local do_alpha = false
    if self.alpha == true then
        -- Only actually try to alpha-blend if the image really has an alpha channel...
        local bbtype = self._bb:getType()
        if bbtype == Blitbuffer.TYPE_BB8A or bbtype == Blitbuffer.TYPE_BBRGB32 then
            do_alpha = true
        end
    end
    if do_alpha then
        --- @note: MuPDF feeds us premultiplied alpha (and we don't care w/ GifLib, as alpha is all or nothing),
        ---        while NanoSVG feeds us straight alpha.
        ---        SVG icons are currently flattened at caching time, so we'll only go through the straight alpha
        ---        codepath for non-icons SVGs.
        if self._is_straight_alpha then
            --- @note: Our icons are already dithered properly, either at encoding time, or at caching time.
            if Screen.sw_dithering and not self.is_icon then
                bb:ditheralphablitFrom(self._bb, x, y, self._offset_x, self._offset_y, size.w, size.h)
            else
                bb:alphablitFrom(self._bb, x, y, self._offset_x, self._offset_y, size.w, size.h)
            end
        else
            if Screen.sw_dithering and not self.is_icon then
                bb:ditherpmulalphablitFrom(self._bb, x, y, self._offset_x, self._offset_y, size.w, size.h)
            else
                bb:pmulalphablitFrom(self._bb, x, y, self._offset_x, self._offset_y, size.w, size.h)
            end
        end
    else
        if Screen.sw_dithering and not self.is_icon then
            bb:ditherblitFrom(self._bb, x, y, self._offset_x, self._offset_y, size.w, size.h)
        else
            bb:blitFrom(self._bb, x, y, self._offset_x, self._offset_y, size.w, size.h)
        end
    end
    if self.invert then
        bb:invertRect(x, y, size.w, size.h)
    end
    --- @note: This is mainly geared at black icons/text on a *white* background,
    ---        otherwise the background color itself will shift.
    ---        i.e., this actually *lightens* the rectangle, but since it's aimed at black,
    ---        it makes it gray, dimmer; hence the name.
    ---        TL;DR: If we one day want that to work for icons on a non-white background,
    ---        a better solution would probably be to take the icon pixmap as an alpha-mask,
    ---        (which simply involves blending it onto a white background, then inverting the result),
    ---        and colorBlit it a dim gray onto the target bb.
    ---        This would require the *original* transparent icon, not the flattened one in the cache.
    ---        c.f., https://github.com/koreader/koreader/pull/6937#issuecomment-748372429 for a PoC
    if self.dim and self._unflattened then
        -- bb:lightenRect(x, y, size.w, size.h)
        -- First, convert that black-on-transparent icon into an alpha mask (i.e., flat white on black)
        local icon_bb = Blitbuffer.new(self._unflattened.w, self._unflattened.h, Blitbuffer.TYPE_BB8)
        icon_bb:fill(Blitbuffer.Color8(0xFF)) -- We need *actual* white ^^
        icon_bb:alphablitFrom(self._unflattened, 0, 0, 0, 0, icon_bb.w, icon_bb.h)
        icon_bb:invertRect(0, 0, icon_bb.w, icon_bb.h)
        -- Then, use it as an alpha mask with a fg color set at the middle point of the eInk palette
        -- (much like black after the default dim)
        local fgcolor = Blitbuffer.COLOR_DARK_GRAY
        if Screen.night_mode and not bg_cached.invert_in_night_mode then
            fgcolor = fgcolor:invert()
        end
        bb:colorblitFromRGB32(icon_bb, x, y, self._offset_x, self._offset_y, size.w, size.h, fgcolor)
        icon_bb:free()
    end
    -- In night mode, invert all rendered images, so the original is
    -- displayed when the whole screen is inverted by night mode.
    -- Except for our *black & white* icons: we do *NOT* want to invert them again:
    -- they should match the UI's text/background.
    --- @note: As for *color* icons, we really *ought* to invert them here,
    ---        but we currently don't, as we don't really trickle down
    ---        a way to discriminate them from the B&W ones.
    ---        Currently, this is *only* the KOReader icon in Help, AFAIK.
    if Screen.night_mode and self.original_in_nightmode and not self.is_icon then
        bb:invertRect(x, y, size.w, size.h)
    end
end

-- Reload icon images on night mode state changes
IconWidget.onToggleNightMode = function(self)
    self:free()
    self:init()
end

IconWidget.onSetNightMode = function(self, night_mode)
    if bg_cached.night_mode ~= night_mode then
        self:free()
        self:init()
    end
end

-- Hook into night mode state changes and update cache
local original_UIManager_ToggleNightMode = UIManager.ToggleNightMode

function UIManager:ToggleNightMode()
    original_UIManager_ToggleNightMode(self)

    bg_cached.night_mode = not bg_cached.night_mode
    recomputeBGColor()

    if not bg_cached.invert_in_night_mode then
        -- Refresh files if CoverBrowser is affected and night mode inversion is not enabled
        if bg_cached.set_textbox_colors then
            refreshFileManager()
        end
        ImageCache:clear()
    end
end

local original_UIManager_SetNightMode = UIManager.SetNightMode

function UIManager:SetNightMode(night_mode)
    original_UIManager_SetNightMode(self)

    if bg_cached.night_mode ~= night_mode then
        bg_cached.night_mode = night_mode
        recomputeBGColor()

        if not bg_cached.invert_in_night_mode then
            if bg_cached.set_textbox_colors then
                refreshFileManager()
            end
            ImageCache:clear()
        end
    end
end

-- Replace UnderlineContainer painting
function UnderlineContainer:paintTo(bb, x, y)
    local container_size = self:getSize()
    if not self.dimen then
        self.dimen = Geom:new {
            x = x, y = y,
            w = container_size.w,
            h = container_size.h
        }
    else
        self.dimen.x = x
        self.dimen.y = y
    end

    local line_width = self.line_width or self.dimen.w
    local line_x = x
    if BD.mirroredUILayout() then
        line_x = line_x + self.dimen.w - line_width
    end

    local content_size = self[1]:getSize()
    local p_y = y
    if self.vertical_align == "center" then
        p_y = math.floor((container_size.h - content_size.h) / 2) + y
    elseif self.vertical_align == "bottom" then
        p_y = (container_size.h - content_size.h) + y
    end
    self[1]:paintTo(bb, x, p_y)

    -- Only paint underline if its color is NOT white
    if not colorEquals(self.color, Blitbuffer.COLOR_WHITE) then
        bb:paintRect(line_x, y + container_size.h - self.linesize,
            line_width, self.linesize, self.color)
    end
end

-- Hook into TextBoxWidget text rendering
local original_TextBoxWidget_renderText = TextBoxWidget._renderText

function TextBoxWidget:_renderText(start_row_idx, end_row_idx)
    local original_bgcolor = self.bgcolor

    if bg_cached.set_textbox_colors then
        self.bgcolor = bg_cached.bgcolor
    end

    original_TextBoxWidget_renderText(self, start_row_idx, end_row_idx)

    self.bgcolor = original_bgcolor
end

-- Hook into LineWidget painting
-- Responsible for separators between icons and document option tabs
local original_LineWidget_paintTo = LineWidget.paintTo

function LineWidget:paintTo(bb, x, y)
    local original_background = self.background

    if self.background == Blitbuffer.COLOR_WHITE then
        self.background = bg_cached.bgcolor
    else
        self.background = bg_cached.bgcolor:invert()
    end

    original_LineWidget_paintTo(self, bb, x, y)

    self.background = original_background
end

-- Adjust InputText frame color to match background
local original_InputText_initTextBox = InputText.initTextBox

function InputText:initTextBox(text, char_added)
    original_InputText_initTextBox(self, text, char_added)

    self.focused_color = bg_cached.bgcolor:invert()
    self.unfocused_color = Blitbuffer.ColorRGB32(
        self.focused_color:getR() * 0.5,
        self.focused_color:getG() * 0.5,
        self.focused_color:getB() * 0.5
    )

    self._frame_textwidget.color = self.focused and self.focused_color or self.unfocused_color
end

function InputText:unfocus()
    self.focused = false
    self.text_widget:unfocus()
    self._frame_textwidget.color = self.unfocused_color
end

function InputText:focus()
    self.focused = true
    self.text_widget:focus()
    self._frame_textwidget.color = self.focused_color
end

-- Hook into HTMLBoxWidget rendering (DictQuickLookup) to add "flashui" refreshes to prevent ghosting
local original_HtmlBoxWidget_render = HtmlBoxWidget._render

function HtmlBoxWidget:_render()
    original_HtmlBoxWidget_render(self)

    -- Check for non-white background color
    if string.lower(bg_cached.hex) ~= "#ffffff" then
        UIManager:setDirty(self.dialog or "all", function()
            return "flashui", self.dimen
        end)
    end
end

-- Add background color CSS to HTML dictionary
local original_DictQuickLookup_getHtmlDictionaryCss = DictQuickLookup.getHtmlDictionaryCss

function DictQuickLookup:getHtmlDictionaryCss()
    local original_css = original_DictQuickLookup_getHtmlDictionaryCss(self)

    local bg_hex = bg_cached.hex
    if bg_cached.night_mode and not bg_cached.invert_in_night_mode then
        bg_hex = invertColor(bg_hex)
    end
    local custom_css = [[
        body {
            background-color: ]] .. bg_hex .. [[;
        }
    ]]

    return original_css .. custom_css
end
