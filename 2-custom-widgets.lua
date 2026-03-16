--[[
    This user patch provides a custom widget registry.
    Other patches can register and retrieve custom widgets by name.

    Widgets are auto-loaded from:
        <koreader_dir>/widgets/

    Each .lua file in that directory is loaded and registered under its
    filename (without the .lua extension). For example:
        widgets/colorwheelwidget.lua  →  "colorwheelwidget"

    Usage from another patch:
        local CustomWidgets = require("custom_widgets")

        local MyWidget = CustomWidgets.get("mywidget")
        if MyWidget then
            UIManager:show(MyWidget:new({ ... }))
        end

    Manual registration (for widgets defined inline in a patch):
        CustomWidgets.register("MyWidget", MyWidgetClass)
--]]

local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local WIDGETS_DIR = require("datastorage"):getDataDir() .. "/widgets/"

-- The registry: name -> widget class
local registry = {}

local CustomWidgets = {}

-- Register a widget class under a given name.
-- Overwrites any existing entry with a warning.
function CustomWidgets.register(name, widget)
    if type(name) ~= "string" or name == "" then
        logger.warn("CustomWidgets.register: name must be a non-empty string")
        return false
    end
    if widget == nil then
        logger.warn("CustomWidgets.register: widget is nil for name:", name)
        return false
    end
    if registry[name] then
        logger.warn("CustomWidgets.register: overwriting existing widget:", name)
    else
        logger.dbg("CustomWidgets.register:", name)
    end
    registry[name] = widget
    return true
end

-- Retrieve a widget class by name. Returns nil if not found.
function CustomWidgets.get(name)
    local widget = registry[name]
    if not widget then
        logger.warn("CustomWidgets.get: no widget registered under name:", name)
    end
    return widget
end

-- Silent existence check, useful for optional dependencies.
function CustomWidgets.has(name)
    return registry[name] ~= nil
end

-- Unregister a widget by name.
function CustomWidgets.unregister(name)
    if not registry[name] then
        logger.warn("CustomWidgets.unregister: no widget not registered:", name)
        return false
    end
    logger.dbg("CustomWidgets.unregister:", name)
    registry[name] = nil
    return true
end

-- Return a sorted list of all registered widget names.
function CustomWidgets.list()
    local names = {}
    for name in pairs(registry) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

-- Auto-load all .lua files from WIDGETS_DIR
local function loadWidgetsDir()
    local attr = lfs.attributes(WIDGETS_DIR)
    if not attr or attr.mode ~= "directory" then
        logger.dbg("CustomWidgets: widgets dir not found, skipping auto-load:", WIDGETS_DIR)
        return
    end

    package.path = WIDGETS_DIR .. "?.lua;" .. package.path

    local files = {}
    for entry in lfs.dir(WIDGETS_DIR) do
        if entry:match("%.lua$") then
            table.insert(files, entry)
        end
    end
    table.sort(files)
    for _, filename in ipairs(files) do
        local name = filename:gsub("%.lua$", "")
        local ok, widget = pcall(require, name)
        if ok then
            CustomWidgets.register(name, widget)
        else
            logger.warn("CustomWidgets: failed to load", filename, ":", widget)
        end
    end
end

loadWidgetsDir()

-- Expose as a requireable module so other patches can do:
--   local CustomWidgets = require("custom_widgets")
package.loaded["custom_widgets"] = CustomWidgets

return CustomWidgets
