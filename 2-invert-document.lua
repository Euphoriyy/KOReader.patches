--[[
    This user patch adds a document option to invert the document in night mode.
--]]

local Document = require("document/document")
local KoptInterface = require("document/koptinterface")
local KoptOptions = require("ui/data/koptoptions")
local ReaderConfig = require("apps/reader/modules/readerconfig")
local Screen = require("device").screen
local optionsutil = require("ui/data/optionsutil")
local _ = require("gettext")

for __, section in ipairs(KoptOptions) do
    if section.icon == "appbar.contrast" then
        table.insert(section.options, {
            name = "nightmode_document",
            name_text = _("Invert Document"),
            toggle = { _("off"), _("on") },
            values = { 0, 1 },
            default_value = 0,
            show_func = function() return Screen.night_mode end,
            name_text_hold_callback = optionsutil.showValues,
            help_text = _([[Invert document in night mode. Useful for image heavy documents such as comics and manga.]]),
        })
        break
    end
end

local original_ReaderConfig_init = ReaderConfig.init

-- Load new option
function ReaderConfig:init()
    original_ReaderConfig_init(self)

    if self.document.koptinterface ~= nil then
        self.options = KoptOptions
        self.configurable:loadDefaults(self.options)
    end
end

-- Invert page
function Document:drawPageInverted(target, x, y, rect, pageno, zoom, rotation, gamma)
    local tile = self:renderPage(pageno, rect, zoom, rotation, gamma)
    target:invertblitFrom(tile.bb,
        x, y,
        rect.x - tile.excerpt.x,
        rect.y - tile.excerpt.y,
        rect.w, rect.h)
end

function KoptInterface:drawContextPage(doc, target, x, y, rect, pageno, zoom, rotation)
    local tile = self:renderPage(doc, pageno, rect, zoom, rotation, 1.0)
    if doc.configurable.nightmode_document == 1 and Screen.night_mode then
        if doc.configurable.page_opt then
            -- Dewatermark enabled: blit from tile first, then invert the drawn target region
            target:blitFrom(tile.bb,
                x, y,
                rect.x - tile.excerpt.x,
                rect.y - tile.excerpt.y,
                rect.w, rect.h)
            target:invertblitFrom(target,
                x, y,
                x, y,
                rect.w, rect.h)
        else
            -- Dewatermark disabled: invert blit from tile
            target:invertblitFrom(tile.bb,
                x, y,
                rect.x - tile.excerpt.x,
                rect.y - tile.excerpt.y,
                rect.w, rect.h)
        end
    else
        target:blitFrom(tile.bb,
            x, y,
            rect.x - tile.excerpt.x,
            rect.y - tile.excerpt.y,
            rect.w, rect.h)
    end
end

function KoptInterface:drawPage(doc, target, x, y, rect, pageno, zoom, rotation, gamma)
    if doc.configurable.text_wrap == 1 then
        self:drawContextPage(doc, target, x, y, rect, pageno, zoom, rotation)
    elseif doc.configurable.page_opt == 1 or doc.configurable.auto_straighten > 0 then
        self:drawContextPage(doc, target, x, y, rect, pageno, zoom, rotation)
    elseif doc.configurable.nightmode_document == 1 and Screen.night_mode then
        Document.drawPageInverted(doc, target, x, y, rect, pageno, zoom, rotation, gamma)
    else
        Document.drawPage(doc, target, x, y, rect, pageno, zoom, rotation, gamma)
    end
end
