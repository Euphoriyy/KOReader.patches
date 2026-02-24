--[[
    This user patch adds rounded corners to book covers.
    Its main distinguishing feature is that it is background-agnostic,
    so it supports my background color patch.
    It also does not require the use of icon files.

    Source:
    -- Based on https://github.com/SeriousHornet/KOReader.patches/blob/main/2--rounded-covers.lua
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Screen = require("device").screen
local userpatch = require("userpatch")

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
    if 2*r > w then r = math.floor(w/2) end
    if 2*r > h then r = math.floor(h/2) end

    -- Draw straight edges (top, bottom, left, right) leaving corners
    bb:paintRect(x+r, y, w-2*r, thickness, color)            -- top
    bb:paintRect(x+r, y+h-thickness, w-2*r, thickness, color) -- bottom
    bb:paintRect(x, y+r, thickness, h-2*r, color)            -- left
    bb:paintRect(x+w-thickness, y+r, thickness, h-2*r, color) -- right

    local r2 = r*r

    -- Helper: draw one quarter circle
    drawCorner = drawCorner or function(cx, cy, start_x, end_x, start_y, end_y)
        for px = start_x, end_x do
            for py = start_y, end_y do
                local dx = px - cx
                local dy = py - cy
                local dist2 = dx*dx + dy*dy
                if dist2 >= (r-thickness)^2 and dist2 <= r2 then
                    bb:setPixelClamped(px, py, color)
                end
            end
        end
    end

    -- Top-left
    drawCorner(x+r-1, y+r-1, x, x+r-1, y, y+r-1)
    -- Top-right
    drawCorner(x+w-r, y+r-1, x+w-r, x+w-1, y, y+r-1)
    -- Bottom-left
    drawCorner(x+r-1, y+h-r, x, x+r-1, y+h-r, y+h-1)
    -- Bottom-right
    drawCorner(x+w-r, y+h-r, x+w-r, x+w-1, y+h-r, y+h-1)
end

local function patchBookCoverRoundedCorners(plugin)
    local MosaicMenu = require("mosaicmenu")
    local MosaicMenuItem = userpatch.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")

    if MosaicMenuItem.patched_rounded_corners then
        return
    end
    MosaicMenuItem.patched_rounded_corners = true

    local orig_MosaicMenuItem_paint = MosaicMenuItem.paintTo

    function MosaicMenuItem:paintTo(bb, x, y)
        -- First, call the original paintTo method to draw the cover normally
        orig_MosaicMenuItem_paint(self, bb, x, y)

        -- Locate the cover frame widget as the base code does
        local target = self[1][1][1]

        if target and target.dimen then
            -- Outer frame rect (already centered)
            local fx = x + math.floor((self.width - target.dimen.w) / 2)
            local fy = y + math.floor((self.height - target.dimen.h) / 2)
            local fw, fh = target.dimen.w, target.dimen.h

            -- Inner content rect = cover area inside padding
            local pad = target.padding or 0
            local inset = 0 --Screen:scaleBySize(1)
            local ix = math.floor(fx + pad + inset)
            local iy = math.floor(fy + pad + inset)
            local iw = math.max(1, fw - 2 * (pad + inset))
            local ih = math.max(1, fh - 2 * (pad + inset))

            local cover_border = Screen:scaleBySize(0.5) -- tweak for thicker line
            if not self.is_directory then
                bb:paintBorder(ix, iy, iw, ih, cover_border, Blitbuffer.COLOR_BLACK, 0, false)
            end
        end

        -- Paint rounded corners on the outer frame rect
        if target and target.dimen and not self.is_directory then
            local fx = x + math.floor((self.width - target.dimen.w) / 2)
            local fy = y + math.floor((self.height - target.dimen.h) / 2)
            local fw, fh = target.dimen.w, target.dimen.h

            local bgcolor = bb:getPixel(fx - 1, fy - 1)
            local cover_border = Screen:scaleBySize(0.5)
            local border_color = Blitbuffer.COLOR_BLACK
            local radius = Screen:scaleBySize(24)

            clipRoundedRect(bb, fx, fy, fw, fh, radius, bgcolor)
            strokeRoundedRect(bb, fx, fy, fw, fh, radius, border_color, cover_border)
        end
    end
end
userpatch.registerPatchPluginFunc("coverbrowser", patchBookCoverRoundedCorners)
