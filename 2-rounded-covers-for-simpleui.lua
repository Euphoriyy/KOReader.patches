--[[
    This user patch adds rounded corners to the covers used in SimpleUI.
    It is background-agnostic, so it supports the Appearance plugin.
    It also does not require the use of icon files.
--]]

local Screen = require("device").screen
local userpatch = require("userpatch")

-- Adjust this for more/less rounded corners (high -> rounder, less -> squarer)
local RADIUS_SIZE = 20

-- Adjust this for a thicker outline
local BORDER_SIZE = 1

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

    local cache  = getCornerCache(r, r)
    local dr     = cache.dr

    local colors = color and { color, color, color, color } or {
        bb:getPixel(x - 1, y - 1),
        bb:getPixel(x + w + 1, y - 1),
        bb:getPixel(x - 1, y + h + 1),
        bb:getPixel(x + w + 1, y + h + 1),
    }

    applyMask(bb, cache.clip, x, y, r, dr, colors[1], true, true)
    applyMask(bb, cache.clip, x + w - r, y, r, dr, colors[2], false, true)
    applyMask(bb, cache.clip, x, y + h - r, r, dr, colors[3], true, false)
    applyMask(bb, cache.clip, x + w - r, y + h - r, r, dr, colors[4], false, false)
end

-- Add rounded corners to SimpleUI (plugin)
userpatch.registerPatchPluginFunc("simpleui", function()
    local SH = require("desktop_modules/module_books_shared")
    if not SH then return end

    local original_getBookCover = SH.getBookCover
    function SH.getBookCover(...)
        local fc = original_getBookCover(...)
        if not fc then return nil end
        local img = fc and fc[1]
        if not img then return fc end

        -- Prevent repatching
        if img._rounded_corners_patched then return fc end
        img._rounded_corners_patched = true

        -- Hook onto the cover's paint function
        local original_img_paintTo = img.paintTo
        function img:paintTo(bb, x, y)
            original_img_paintTo(self, bb, x, y)

            -- Outer frame rect (already centered)
            local fw, fh = fc.dimen.w, fc.dimen.h
            local fx = x + math.floor((self.width - fw) / 2)
            local fy = y + math.floor((self.height - fh) / 2)

            -- Inner content rect = cover area inside padding
            local pad = fc.padding or 0
            local inset = 0 --Screen:scaleBySize(1)
            local ix = math.floor(fx + pad + inset)
            local iy = math.floor(fy + pad + inset)
            local iw = math.max(1, fw - 2 * (pad + inset))
            local ih = math.max(1, fh - 2 * (pad + inset))

            -- Paint rounded corners on the outer frame rect
            local cover_border = BORDER_SIZE
            local border_color = fc.color
            local corner_radius = Screen:scaleBySize(RADIUS_SIZE)
            local border_radius = Screen:scaleBySize(RADIUS_SIZE - 2)

            clipRoundedRect(bb, fx, fy, fw, fh, corner_radius)
            bb:paintBorder(ix, iy, iw, ih, cover_border, border_color, border_radius, false)
        end

        -- Don't draw the border of the original container
        fc.bordersize = 0

        return fc
    end
end)
