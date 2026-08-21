--[[
pt-mm-noborders - remove separator lines in Project: Title's mosaic view.

Overrides ptutil.mediumBlackLine with a zero-width span and ptutil.thinGrayLine
with the thin white variant, so mosaic book covers render without horizontal
border lines.

Targets:
  - KOReader 2026.07.1 (safe_version 202607010000)
  - projecttitle @ joshuacant/ProjectTitle 2026.07-v3.8.3 (ptutil line helpers)
--]]

local userpatch = require("userpatch")
local logger = require("logger")
local VerticalSpan = require("ui/widget/verticalspan")

local function patchMosaicMenu(plugin)
    
    local ptutil = require("ptutil")
    
    local original_mediumBlackLine = ptutil.mediumBlackLine
    local original_thinGrayLine = ptutil.thinGrayLine
    
    ptutil.mediumBlackLine = function(width)
        return VerticalSpan:new { width = 0 }
    end
    
    ptutil.thinGrayLine = function(width)
        return ptutil.thinWhiteLine(width)
    end
    
    logger.info("MosaicMenu patched: ptutil line functions overridden to remove borders")
end

userpatch.registerPatchPluginFunc("projecttitle", patchMosaicMenu)