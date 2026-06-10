--[[
pt-profiler - enable Project: Title's built-in draw timers.

Flips ptdbg.enabled so PT logs its per-page and per-item draw timings
("Draw whole page", "Draw grid item <name>", "Draw cover list page",
"Cache book <path>") to crash.log at info level.

Diagnostic patch: install while investigating file-browser performance,
remove afterwards. The logging itself adds a little overhead and grows
crash.log quickly (one line per visible item per page draw).

Targets:
  - coverbrowser @ joshuacant/ProjectTitle 2026.03-v3.7 (ptdbg)
--]]

local userpatch = require("userpatch")
local logger = require("logger")

local function enableProfiler(plugin)
    local ok, ptdbg = pcall(require, "ptdbg")
    if not ok or type(ptdbg) ~= "table" then
        logger.warn("pt-profiler: ptdbg module not found, timers not enabled")
        return
    end
    ptdbg.enabled = true
    logger.info("pt-profiler: Project: Title draw timers enabled")
end

userpatch.registerPatchPluginFunc("coverbrowser", enableProfiler)
