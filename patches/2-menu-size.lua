--[[
menu-size - scale menu item counts to the screen's real DPI.

Compares the configured DPI against the device default and shrinks
TouchMenu.max_per_page_default and Menu.items_per_page_default by that ratio,
so menus keep comfortable touch targets when a custom (higher) DPI is set.

Targets:
  - KOReader 2026.07.1 (safe_version 202607010000)
  - KOReader core (ui/widget/menu, ui/widget/touchmenu)
--]]

local Device = require("device")
local Screen = Device.screen
local Menu = require("ui/widget/menu")
local TouchMenu = require("ui/widget/touchmenu")

local dpi = Screen:getDPI()
Screen:clearDPI()
local dpi_default = Screen:getDPI()
Screen:setDPI(dpi)
local size_ratio = math.min(dpi / dpi_default, 1)

TouchMenu.max_per_page_default = math.floor(TouchMenu.max_per_page_default / size_ratio)
Menu.items_per_page_default = math.floor(Menu.items_per_page_default / size_ratio)
