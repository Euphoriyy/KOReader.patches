--[[
    This user patch adds rounded corners to book covers.
    Its main distinguishing feature is that it is background-agnostic,
    so it supports my background color patch.
    It also does not require the use of icon files.

    Source:
    -- Based on https://github.com/SeriousHornet/KOReader.patches/blob/main/2-rounded-folder-covers.lua
--]]

local AlphaContainer = require("ui/widget/container/alphacontainer")
local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FileChooser = require("ui/widget/filechooser")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local ImageWidget = require("ui/widget/imagewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TopContainer = require("ui/widget/container/topcontainer")
local VerticalSpan = require("ui/widget/verticalspan")
local userpatch = require("userpatch")
local util = require("util")

local _ = require("gettext")
local Screen = Device.screen
local logger = require("logger")

--========================== Edit your preferences here ================================
local aspect_ratio = 2 / 3  -- adjust aspect ratio of folder cover
local stretch_limit = 50    -- adjust the stretching limit
local fill = false          -- set true to fill the entire cell ignoring aspect ratio
local file_count_size = 14  -- font size of the file count badge
local folder_font_size = 20 -- font size of the folder name
local folder_border = 0.5   -- thickness of folder border
local folder_name = true    -- set to false to remove folder title from the center
--======================================================================================

local FolderCover = {
    name = ".cover",
    exts = { ".jpg", ".jpeg", ".png", ".webp", ".gif" },
}

local function findCover(dir_path)
    local path = dir_path .. "/" .. FolderCover.name
    for _, ext in ipairs(FolderCover.exts) do
        local fname = path .. ext
        if util.fileExists(fname) then return fname end
    end
end

local function getMenuItem(menu, ...)
    local function findItem(sub_items, texts)
        local find = {}
        for _, text in ipairs(type(texts) == "table" and texts or { texts }) do
            find[text] = true
        end
        for _, item in ipairs(sub_items) do
            local text = item.text or (item.text_func and item.text_func())
            if text and find[text] then return item end
        end
    end

    local sub_items, item
    for _, texts in ipairs { ... } do
        sub_items = (item or menu).sub_item_table
        if not sub_items then return end
        item = findItem(sub_items, texts)
        if not item then return end
    end
    return item
end

local function toKey(...)
    local keys = {}
    for _, key in pairs { ... } do
        if type(key) == "table" then
            table.insert(keys, "table")
            for k, v in pairs(key) do
                table.insert(keys, tostring(k))
                table.insert(keys, tostring(v))
            end
        else
            table.insert(keys, tostring(key))
        end
    end
    return table.concat(keys, "")
end

local orig_FileChooser_getListItem = FileChooser.getListItem
local cached_list = {}
function FileChooser:getListItem(dirpath, f, fullpath, attributes, collate)
    local key = toKey(dirpath, f, fullpath, attributes, collate, self.show_filter.status)
    cached_list[key] = cached_list[key] or orig_FileChooser_getListItem(self, dirpath, f, fullpath, attributes, collate)
    return cached_list[key]
end

local function capitalize(sentence)
    local words = {}
    for word in sentence:gmatch("%S+") do
        table.insert(words, word:sub(1, 1):upper() .. word:sub(2):lower())
    end
    return table.concat(words, " ")
end

local Folder = {
    face = {
        border_size = 1,
        alpha = 0.75,
        nb_items_font_size = file_count_size,
        nb_items_margin = Screen:scaleBySize(5),
        dir_max_font_size = folder_font_size,
    },
}

local clipCorner

local function clipRoundedRect(bb, x, y, w, h, r, color)
    if r <= 0 then return end
    if 2 * r > w then r = math.floor(w / 2) end
    if 2 * r > h then r = math.floor(h / 2) end

    local r2 = r * r

    -- Helper: clip one corner
    clipCorner = clipCorner or function(cx, cy, start_x, end_x, start_y, end_y)
        for px = start_x, end_x do
            for py = start_y, end_y do
                local dx = px - cx
                local dy = py - cy
                if dx * dx + dy * dy > r2 then
                    bb:setPixelClamped(px, py, color)
                end
            end
        end
    end

    -- Top-left
    clipCorner(
        x + r - 1, y + r - 1,
        x, x + r - 1,
        y, y + r - 1
    )

    -- Top-right
    clipCorner(
        x + w - r, y + r - 1,
        x + w - r, x + w - 1,
        y, y + r - 1
    )

    -- Bottom-left
    clipCorner(
        x + r - 1, y + h - r,
        x, x + r - 1,
        y + h - r, y + h - 1
    )

    -- Bottom-right
    clipCorner(
        x + w - r, y + h - r,
        x + w - r, x + w - 1,
        y + h - r, y + h - 1
    )
end

local drawCorner

local function strokeRoundedRect(bb, x, y, w, h, r, color, thickness)
    thickness = thickness or 1
    if r <= 0 then
        -- Fallback to normal rectangle border
        bb:paintBorder(x, y, w, h, thickness, color, 0, false)
        return
    end
    if 2 * r > w then r = math.floor(w / 2) end
    if 2 * r > h then r = math.floor(h / 2) end

    -- Draw straight edges (top, bottom, left, right) leaving corners
    bb:paintRect(x + r, y, w - 2 * r, thickness, color)                 -- top
    bb:paintRect(x + r, y + h - thickness, w - 2 * r, thickness, color) -- bottom
    bb:paintRect(x, y + r, thickness, h - 2 * r, color)                 -- left
    bb:paintRect(x + w - thickness, y + r, thickness, h - 2 * r, color) -- right

    local r2 = r * r

    -- Helper: draw one quarter circle
    drawCorner = drawCorner or function(cx, cy, start_x, end_x, start_y, end_y)
        for px = start_x, end_x do
            for py = start_y, end_y do
                local dx = px - cx
                local dy = py - cy
                local dist2 = dx * dx + dy * dy
                if dist2 >= (r - thickness) ^ 2 and dist2 <= r2 then
                    bb:setPixelClamped(px, py, color)
                end
            end
        end
    end

    -- Top-left
    drawCorner(x + r - 1, y + r - 1, x, x + r - 1, y, y + r - 1)
    -- Top-right
    drawCorner(x + w - r, y + r - 1, x + w - r, x + w - 1, y, y + r - 1)
    -- Bottom-left
    drawCorner(x + r - 1, y + h - r, x, x + r - 1, y + h - r, y + h - 1)
    -- Bottom-right
    drawCorner(x + w - r, y + h - r, x + w - r, x + w - 1, y + h - r, y + h - 1)
end

local function patchCoverBrowser(plugin)
    local MosaicMenu = require("mosaicmenu")
    local MosaicMenuItem = userpatch.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
    if not MosaicMenuItem or MosaicMenuItem.rounded_folder_covers then return end
    MosaicMenuItem.rounded_folder_covers = true

    local BookInfoManager = userpatch.getUpValue(MosaicMenuItem.update, "BookInfoManager")
    local original_update = MosaicMenuItem.update

    local max_img_w, max_img_h
    -- used by StretchingImageWidget and _setFolderCover, they will hold dimensions after aspect ratio is applied
    local adjusted_w, adjusted_h

    if not MosaicMenuItem.patched_aspect_ratio then
        MosaicMenuItem.patched_aspect_ratio = true

        local local_ImageWidget
        local n = 1
        while true do
            local name, value = debug.getupvalue(MosaicMenuItem.update, n)
            if not name then break end
            if name == "ImageWidget" then
                local_ImageWidget = value
                break
            end
            n = n + 1
        end

        if not local_ImageWidget then
            logger.warn("Could not find ImageWidget in MosaicMenuItem.update closure")
        else
            local setupvalue_n = n
            local orig_MosaicMenuItem_init = MosaicMenuItem.init

            function MosaicMenuItem:init()
                if orig_MosaicMenuItem_init then orig_MosaicMenuItem_init(self) end
                if self.width and self.height then
                    local border_size = Size.border.thin
                    max_img_w = self.width - 2 * border_size
                    max_img_h = self.height - 2 * border_size

                    -- math.floor is applied when messing with the ratio
                    if fill then
                        adjusted_w = max_img_w
                        adjusted_h = max_img_h
                    else
                        local ratio = aspect_ratio
                        if max_img_w / max_img_h > ratio then
                            adjusted_h = max_img_h
                            adjusted_w = math.floor(max_img_h * ratio)
                        else
                            adjusted_w = max_img_w
                            adjusted_h = math.floor(max_img_w / ratio)
                        end
                    end
                end
            end

            local StretchingImageWidget = local_ImageWidget:extend({})
            StretchingImageWidget.init = function(self)
                if local_ImageWidget.init then local_ImageWidget.init(self) end
                if not adjusted_w or not adjusted_h then return end

                self.scale_factor = nil
                self.stretch_limit_percentage = stretch_limit
                -- no need to recalculate ratio, we use  adjusted_w/adjusted_h
                self.width = adjusted_w
                self.height = adjusted_h
            end

            debug.setupvalue(MosaicMenuItem.update, setupvalue_n, StretchingImageWidget)
            logger.info("Aspect ratio control applied successfully")
        end
    end

    local function getAspectRatioAdjustedDimensions(width, height, border_size)
        if adjusted_w and adjusted_h then
            return { w = adjusted_w + 2 * border_size, h = adjusted_h + 2 * border_size }
        end
        -- fallback
        local available_w = width - 2 * border_size
        local available_h = height - 2 * border_size
        local ratio = fill and (available_w / available_h) or aspect_ratio

        local frame_w, frame_h
        if available_w / available_h > ratio then
            frame_h = available_h
            frame_w = available_h * ratio
        else
            frame_w = available_w
            frame_h = available_w / ratio
        end

        return { w = frame_w + 2 * border_size, h = frame_h + 2 * border_size }
    end

    function BooleanSetting(text, name, default)
        self = { text = text }
        self.get = function()
            local setting = BookInfoManager:getSetting(name)
            return setting or default
        end
        self.toggle = function() return BookInfoManager:toggleSetting(name) end
        return self
    end

    local settings = {
        name_centered = BooleanSetting(_("Folder name centered"), "folder_name_centered", false),
        show_folder_name = BooleanSetting(_("Show folder name"), "folder_name_show", folder_name),
    }

    function MosaicMenuItem:update(...)
        original_update(self, ...)
        if self._foldercover_processed or self.menu.no_refresh_covers or not self.do_cover_image then return end
        if self.entry.is_file or self.entry.file or not self.mandatory then return end

        local dir_path = self.entry and self.entry.path
        if not dir_path then return end

        self._foldercover_processed = true

        local cover_file = findCover(dir_path)
        if cover_file then
            local success, w, h = pcall(function()
                local tmp_img = ImageWidget:new { file = cover_file, scale_factor = 1 }
                tmp_img:_render()
                local orig_w = tmp_img:getOriginalWidth()
                local orig_h = tmp_img:getOriginalHeight()
                tmp_img:free()
                return orig_w, orig_h
            end)
            if success then
                self:_setFolderCover { file = cover_file, w = w, h = h }
                return
            end
        end

        self.menu._dummy = true
        local entries = self.menu:genItemTableFromPath(dir_path)
        self.menu._dummy = false
        if not entries then return end

        for _, entry in ipairs(entries) do
            if entry.is_file or entry.file then
                local bookinfo = BookInfoManager:getBookInfo(entry.path, true)
                if bookinfo and bookinfo.cover_bb and bookinfo.has_cover and bookinfo.cover_fetched
                    and not bookinfo.ignore_cover and not BookInfoManager.isCachedCoverInvalid(bookinfo, self.menu.cover_specs) then
                    self:_setFolderCover { data = bookinfo.cover_bb, w = bookinfo.cover_w, h = bookinfo.cover_h }
                    break
                end
            end
        end
    end

    function MosaicMenuItem:_setFolderCover(img)
        local border_size = 0
        local frame_dimen = getAspectRatioAdjustedDimensions(self.width, self.height, border_size)
        local image_width = frame_dimen.w - 2 * border_size
        local image_height = frame_dimen.h - 2 * border_size

        local image = img.file and
            ImageWidget:new { file = img.file, width = image_width, height = image_height, stretch_limit_percentage = stretch_limit } or
            ImageWidget:new { image = img.data, width = image_width, height = image_height, stretch_limit_percentage = stretch_limit }

        local image_widget = FrameContainer:new {
            padding = 0, bordersize = border_size, image, overlap_align = "center",
        }

        local image_size = image:getSize()
        local directory = self:_getTextBox { w = image_size.w, h = image_size.h }

        local folder_name_widget
        if settings.show_folder_name.get() then
            folder_name_widget = (settings.name_centered.get() and CenterContainer or TopContainer):new {
                dimen = frame_dimen,
                FrameContainer:new {
                    padding = -1, bordersize = 1,
                    AlphaContainer:new { alpha = Folder.face.alpha, directory },
                },
                overlap_align = "center",
            }
        else
            folder_name_widget = VerticalSpan:new { width = 0 }
        end

        local nbitems_widget
        local item_count = 0
        if self.mandatory then
            local count_str = self.mandatory:match("(%d+)")
            if count_str then item_count = tonumber(count_str) end
        end

        if item_count > 0 then
            local nbitems = TextWidget:new {
                text = tostring(item_count),
                face = Font:getFace("cfont", Folder.face.nb_items_font_size),
                bold = true, padding = 0
            }

            local nb_size = math.max(nbitems:getSize().w, nbitems:getSize().h)
            nbitems_widget = BottomContainer:new {
                dimen = frame_dimen,
                RightContainer:new {
                    dimen = {
                        w = frame_dimen.w - Folder.face.nb_items_margin,
                        h = nb_size + Folder.face.nb_items_margin * 2,
                    },
                    FrameContainer:new {
                        padding = 2, bordersize = Folder.face.border_size,
                        radius = math.ceil(nb_size), background = Blitbuffer.COLOR_GRAY_E,
                        CenterContainer:new { dimen = { w = nb_size, h = nb_size }, nbitems },
                    },
                },
                overlap_align = "center",
            }
        else
            nbitems_widget = VerticalSpan:new { width = 0 }
        end

        self._folder_frame_dimen = frame_dimen
        self._folder_image_size = image_size

        local widget = CenterContainer:new {
            dimen = { w = self.width, h = self.height },
            CenterContainer:new {
                dimen = { w = self.width, h = self.height },
                OverlapGroup:new {
                    dimen = frame_dimen,
                    image_widget,
                    folder_name_widget,
                    nbitems_widget,
                },
            },
        }

        if self._underline_container[1] then
            self._underline_container[1]:free()
        end
        self._underline_container[1] = widget
    end

    function MosaicMenuItem:_getTextBox(dimen)
        local text = self.text
        if text:match("/$") then text = text:sub(1, -2) end
        text = BD.directory(capitalize(text))

        local available_height = dimen.h
        local dir_font_size = Folder.face.dir_max_font_size
        local directory

        while true do
            if directory then directory:free(true) end
            directory = TextBoxWidget:new {
                text = text,
                face = Font:getFace("cfont", dir_font_size),
                width = dimen.w,
                alignment = "center",
                bold = true,
            }
            if directory:getSize().h <= available_height then break end
            dir_font_size = dir_font_size - 1
            if dir_font_size < 10 then
                directory:free()
                directory.height = available_height
                directory.height_adjust = true
                directory.height_overflow_show_ellipsis = true
                directory:init()
                break
            end
        end
        return directory
    end

    local orig_MosaicMenuItem_paintTo = MosaicMenuItem.paintTo
    function MosaicMenuItem:paintTo(bb, x, y)
        orig_MosaicMenuItem_paintTo(self, bb, x, y)

        if not self._folder_frame_dimen or not self._folder_image_size then return end
        if self.entry.is_file or self.entry.file then return end

        local frame_dimen = self._folder_frame_dimen
        local image_size = self._folder_image_size

        local fx = x + math.floor((self.width - frame_dimen.w) / 2)
        local fy = y + math.floor((self.height - frame_dimen.h) / 2)
        local image_x = fx + math.floor((frame_dimen.w - image_size.w) / 2)
        local image_y = fy + math.floor((frame_dimen.h - image_size.h) / 2)
        local bgcolor = bb:getPixel(fx - 1, fy - 1)

        local cover_border = Screen:scaleBySize(folder_border)
        bb:paintBorder(image_x, image_y, image_size.w, image_size.h, cover_border, Blitbuffer.COLOR_BLACK, 0, false)

        local border_color = Blitbuffer.COLOR_BLACK
        local radius = Screen:scaleBySize(24)

        clipRoundedRect(bb, fx, fy, image_size.w, image_size.h, radius, bgcolor)
        strokeRoundedRect(bb, fx, fy, image_size.w, image_size.h, radius, border_color, cover_border)
    end

    local orig_CoverBrowser_addToMainMenu = plugin.addToMainMenu
    function plugin:addToMainMenu(menu_items)
        orig_CoverBrowser_addToMainMenu(self, menu_items)
        if menu_items.filebrowser_settings == nil then return end

        local item = getMenuItem(menu_items.filebrowser_settings, _("Mosaic and detailed list settings"))
        if item then
            item.sub_item_table[#item.sub_item_table].separator = true
            for i, setting in pairs(settings) do
                if not getMenuItem(menu_items.filebrowser_settings, _("Mosaic and detailed list settings"), setting.text) then
                    table.insert(item.sub_item_table, {
                        text = setting.text,
                        checked_func = function() return setting.get() end,
                        callback = function()
                            setting.toggle()
                            self.ui.file_chooser:updateItems()
                        end,
                    })
                end
            end
        end
    end
end

userpatch.registerPatchPluginFunc("coverbrowser", patchCoverBrowser)
