--[[
Add History and Open-Previous-Document icon buttons next to the pagination
chevrons in Project: Title's file-browser footer. Hidden when CoverMenu is
rendering the History list itself. Mutually exclusive with the existing
"Replace folder name with device info" option.

Targets:
  - Project: Title @ joshuacant/ProjectTitle commit 31c6777 (or compatible)
  - KOReader 2026.03 (safe_version 202603000000)

Toggle: in the file browser, open the top menu -> first tab (settings)
        -> Project: Title settings -> Advanced settings -> Footer
        -> "Show history & last-document icons"
--]]

local userpatch = require("userpatch")

local SETTING_KEY = "show_footer_nav_icons"

local function patchCoverBrowser(plugin)
    if plugin._pt_footer_patch_applied then return end
    plugin._pt_footer_patch_applied = true

    local CoverMenu       = require("covermenu")
    local BookInfoManager = require("bookinfomanager")
    local _               = require("l10n.gettext")

    local IconButton      = require("ui/widget/iconbutton")
    local HorizontalSpan  = require("ui/widget/horizontalspan")
    local UIManager       = require("ui/uimanager")
    local Screen          = require("device").screen
    local Menu            = require("ui/widget/menu")

    -- Hosts where we want footer icons (matches CoverMenu/booklist widget names).
    local SUPPORTED_HOSTS = {
        filemanager = true,
        history     = true,
        collections = true,
    }

    -- ---------------------------------------------------------------------
    -- 1. Footer rendering: inject icons into the page_info row.
    --    PT redirects `Menu.init = CoverMenu.menuInit` at plugin load, so
    --    we must patch the live dispatch point too.
    -- ---------------------------------------------------------------------
    local _menuInit_orig = CoverMenu.menuInit
    local function patchedMenuInit(self)
        _menuInit_orig(self)

        if not SUPPORTED_HOSTS[self.name] then return end
        if not BookInfoManager:getSetting(SETTING_KEY) then return end
        if BookInfoManager:getSetting("replace_footer_text") then return end
        if not self.page_info then return end

        local FileManager = require("apps/filemanager/filemanager")
        -- Match the chevron text weight: shrink to ~70% of the row height
        -- so the icons read as the same visual size as "1 of 1".
        local row_h    = self.page_info:getSize().h
        local icon_h   = math.floor(row_h * 0.7)
        local gap      = Screen:scaleBySize(14)

        local function makeBtn(icon_name, on_tap)
            return IconButton:new {
                icon        = icon_name,
                width       = icon_h,
                height      = icon_h,
                padding     = 0,
                callback    = on_tap,
                show_parent = self.show_parent,
            }
        end

        local buttons = {}
        if self.name ~= "history" then
            buttons[#buttons + 1] = makeBtn("history", function()
                if FileManager.instance and FileManager.instance.history then
                    FileManager.instance.history:onShowHist()
                end
            end)
        end
        buttons[#buttons + 1] = makeBtn("last_document", function()
            if FileManager.instance and FileManager.instance.menu then
                FileManager.instance.menu:onOpenLastDoc()
            end
        end)

        if #buttons == 0 then return end

        local reverse = BookInfoManager:getSetting("reverse_footer")
        if reverse then
            -- Chevrons sit on the left; append icons after them: [chevrons][gap][btn][gap][btn]
            for _, btn in ipairs(buttons) do
                self.page_info[#self.page_info + 1] = HorizontalSpan:new { width = gap }
                self.page_info[#self.page_info + 1] = btn
            end
        else
            -- Chevrons sit on the right; prepend icons: [btn][gap][btn][gap][chevrons]
            local idx = 1
            for _, btn in ipairs(buttons) do
                table.insert(self.page_info, idx, btn);                                 idx = idx + 1
                table.insert(self.page_info, idx, HorizontalSpan:new { width = gap });  idx = idx + 1
            end
        end
        self.page_info:resetLayout()

        if self.cur_folder_text and self.cur_folder_text.setMaxWidth then
            self.cur_folder_text:setMaxWidth(self.screen_w * 0.94 - self.page_info:getSize().w)
        end
    end
    CoverMenu.menuInit = patchedMenuInit
    Menu.init          = patchedMenuInit

    -- ---------------------------------------------------------------------
    -- 2. Menu: append a toggle to the existing Footer submenu, mutually
    --    exclusive with replace_footer_text.
    -- ---------------------------------------------------------------------
    local _addToMainMenu_orig = plugin.addToMainMenu
    plugin.addToMainMenu = function(self, menu_items)
        _addToMainMenu_orig(self, menu_items)

        local root = menu_items.filemanager_display_mode
        if not (root and root.sub_item_table) then return end

        local function findByText(tbl, ...)
            local wanted = { ... }
            for _, item in ipairs(tbl) do
                for _, w in ipairs(wanted) do
                    if item.text == w then return item end
                end
            end
        end

        local advanced = findByText(root.sub_item_table,
            _("Advanced settings"), "Advanced settings")
        if not (advanced and advanced.sub_item_table) then return end

        local footer = findByText(advanced.sub_item_table, _("Footer"), "Footer")
        if not (footer and footer.sub_item_table) then return end

        local replace_item = findByText(footer.sub_item_table,
            _("Replace folder name with device info"),
            "Replace folder name with device info")
        if replace_item then
            local orig_cb = replace_item.callback
            replace_item.callback = function()
                if not BookInfoManager:getSetting("replace_footer_text") then
                    BookInfoManager:saveSetting(SETTING_KEY, false)
                end
                orig_cb()
            end
        end

        table.insert(footer.sub_item_table, {
            text = _("Show history & last-document icons"),
            checked_func = function()
                return BookInfoManager:getSetting(SETTING_KEY)
            end,
            callback = function()
                if not BookInfoManager:getSetting(SETTING_KEY) then
                    BookInfoManager:saveSetting("replace_footer_text", false)
                end
                BookInfoManager:toggleSetting(SETTING_KEY)
                UIManager:askForRestart()
            end,
        })
    end
end

userpatch.registerPatchPluginFunc("coverbrowser", patchCoverBrowser)
