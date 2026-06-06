--[[
disable-input-rotation-map - stop KOReader from remapping touch input on rotation.

Replaces Device.input.rotation_map with empty tables for all four rotations so
touch coordinates are passed through unchanged. For devices whose kernel/driver
already reports rotated coordinates, the stock remap double-rotates input.

Targets:
  - KOReader core (device input layer), written against KOReader 2026.03
--]]

local Device = require("device")
Device.input.rotation_map = {[0]={}, [1]={}, [2]={}, [3]={}}