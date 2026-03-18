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

local _corner_cache = {}

local function getCornerCache(r, thickness)
    local dr  = math.max(1, math.floor(r))
    local dt  = math.max(1, math.floor(math.max(1, thickness)))
    local key = dr .. "," .. dt
    if _corner_cache[key] then return _corner_cache[key] end

    local r2     = dr * dr
    local inner2 = (dr - dt) * (dr - dt)
    local clip   = {}
    local border = {}

    for dy = 0, dr - 1 do
        for dx = 0, dr - 1 do
            local idx   = dy * dr + dx + 1
            local dist2 = dx * dx + dy * dy
            clip[idx]   = dist2 > r2
            border[idx] = dist2 >= inner2 and dist2 <= r2
        end
    end

    _corner_cache[key] = { clip = clip, border = border, dr = dr }
    return _corner_cache[key]
end

local function applyMask(bb, mask, sx, sy, r, dr, color, flip_x, flip_y)
    local step = r / dr
    local idx  = 0
    for dy = 0, dr - 1 do
        local fy = flip_y and (dr - 1 - dy) or dy
        for dx = 0, dr - 1 do
            idx = idx + 1
            if mask[idx] then
                local fx = flip_x and (dr - 1 - dx) or dx
                -- block fill for scale < 1, single pixel for scale = 1
                if step <= 1.0 then
                    bb:setPixelClamped(sx + fx, sy + fy, color)
                else
                    local fx0 = math.floor(fx * step)
                    local fx1 = math.floor((fx + 1) * step) - 1
                    local fy0 = math.floor(fy * step)
                    local fy1 = math.floor((fy + 1) * step) - 1
                    for bfy = fy0, fy1 do
                        for bfx = fx0, fx1 do
                            bb:setPixelClamped(sx + bfx, sy + bfy, color)
                        end
                    end
                end
            end
        end
    end
end

local function clipRoundedRect(bb, x, y, w, h, r, color)
    if r <= 0 then return end
    if 2 * r > w then r = math.floor(w / 2) end
    if 2 * r > h then r = math.floor(h / 2) end

    local cache = getCornerCache(r, r)
    local dr    = cache.dr

    applyMask(bb, cache.clip, x, y, r, dr, color, true, true)
    applyMask(bb, cache.clip, x + w - r, y, r, dr, color, false, true)
    applyMask(bb, cache.clip, x, y + h - r, r, dr, color, true, false)
    applyMask(bb, cache.clip, x + w - r, y + h - r, r, dr, color, false, false)
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

            -- Paint rounded corners on the outer frame rect
            local cover_border = Screen:scaleBySize(0.5) -- tweak for thicker line
            if not self.is_directory then
                fx = x + math.floor((self.width - target.dimen.w) / 2)
                fy = y + math.floor((self.height - target.dimen.h) / 2)
                fw, fh = target.dimen.w, target.dimen.h

                local bgcolor = bb:getPixel(fx - 1, fy - 1)
                local border_color = Blitbuffer.COLOR_BLACK
                local corner_radius = Screen:scaleBySize(24)
                local border_radius = Screen:scaleBySize(22)

                clipRoundedRect(bb, fx, fy, fw, fh, corner_radius, bgcolor)
                bb:paintBorder(ix, iy, iw, ih, cover_border, border_color, border_radius, false)
            end
        end
    end
end
userpatch.registerPatchPluginFunc("coverbrowser", patchBookCoverRoundedCorners)
