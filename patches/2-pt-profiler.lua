--[[
pt-profiler - enable Project: Title's built-in draw timers.

Flips ptdbg.enabled so PT logs its per-page and per-item draw timings
("Draw whole page", "Draw grid item <name>", "Cache book <path>").

Timings are written both to the normal log (crash.log on e-ink devices,
logcat on Android) and to a plain file `pt-profile.log` in the koreader
data directory, so they are readable on Android without adb. The file
also records which of this repo's PT patches actually loaded, and how
long each FileChooser item-table generation takes (folder counting and
sorting, which PT's own timers do not cover).

Diagnostic patch: install while investigating file-browser performance,
remove afterwards. Logging adds a little overhead per draw and the log
file grows quickly; it is recreated on each restart.

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
    if ptdbg._pt_profiler_wrapped then return end -- plugin can load more than once
    ptdbg._pt_profiler_wrapped = true
    ptdbg.enabled = true

    local DataStorage = require("datastorage")
    local time = require("ui/time")
    local logfile_path = DataStorage:getDataDir() .. "/pt-profile.log"
    os.remove(logfile_path) -- start fresh each session

    local function fileLog(line)
        local f = io.open(logfile_path, "a")
        if f then
            f:write(tostring(os.date("%H:%M:%S")), " ", line, "\n")
            f:close()
        end
    end

    -- Tee ptdbg reports into the file (the original still goes to the
    -- normal log).
    local orig_report = ptdbg.report
    ptdbg.report = function(self, description)
        if ptdbg.enabled and self.start_time then
            fileLog(string.format("%s done in %.3f ms",
                description, time.to_ms(time.since(self.start_time))))
        end
        return orig_report(self, description)
    end

    fileLog("=== pt-profiler loaded ===")
    logger.info("pt-profiler: Project: Title draw timers enabled, writing to", logfile_path)

    -- After startup settles: record which sibling patches took effect and
    -- start timing item-table generation (navigation cost not covered by
    -- PT's draw timers).
    local UIManager = require("ui/uimanager")
    UIManager:scheduleIn(5, function()
        local ptutil_ok, ptutil = pcall(require, "ptutil")
        local bim_ok, BookInfoManager = pcall(require, "bookinfomanager")
        local rounded = false
        local mm_ok, MosaicMenu = pcall(require, "mosaicmenu")
        if mm_ok and type(MosaicMenu) == "table" and MosaicMenu._updateItemsBuildUI then
            local MosaicMenuItem = userpatch.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
            rounded = (MosaicMenuItem and MosaicMenuItem.rounded_folder_covers) and true or false
        end
        fileLog(string.format(
            "patch status: foldercover-perf=%s bookinfo-cache=%s rounded-folder-covers=%s",
            tostring(ptutil_ok and ptutil._foldercover_perf_patched or false),
            tostring(bim_ok and BookInfoManager._bookinfo_cache_patched or false),
            tostring(rounded)))

        local FileChooser = require("ui/widget/filechooser")
        local orig_genItemTable = FileChooser.genItemTable
        FileChooser.genItemTable = function(self, dirs, files, path)
            local t0 = time.now()
            local result = orig_genItemTable(self, dirs, files, path)
            fileLog(string.format("genItemTable(%s): %d items in %.3f ms",
                tostring(path), result and #result or -1, time.to_ms(time.since(t0))))
            return result
        end
        fileLog("genItemTable timing armed")
    end)
end

userpatch.registerPatchPluginFunc("coverbrowser", enableProfiler)
