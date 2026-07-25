-- Bookie
-- Extra spellbook tab that lists your macros (account + character) in a
-- spellbook-style grid. Drag them onto action bars like spells.
--
-- Layout matches Blizzard's SpellButton1-12 (left column first, then right —
-- see SpellBook_GetButtonForID). Chrome copies EmptySlot from SpellButton1.

local ADDON = ...
local VERSION = "1.1.0"

local BUTTONS_PER_PAGE = 12
local TAB_ICON = "Interface\\MacroFrame\\MacroFrame-Icon"

local active = false
local page = 1
local buttons = {}
local tabButton
local pageText
local prevBtn, nextBtn
local panel

local function Print(msg)
    print("|cff66ccffBookie|r " .. msg)
end

------------------------------------------------------------------------
-- Map logical slot 1-12 -> the real SpellButton frame Blizzard uses
------------------------------------------------------------------------
local function SpellButtonForSlot(slot)
    if type(SpellBook_GetButtonForID) == "function" then
        local ok, b = pcall(SpellBook_GetButtonForID, slot)
        if ok and b then return b end
    end
    if slot <= 6 then
        return _G["SpellButton" .. (((slot - 1) * 2) + 1)]
    end
    return _G["SpellButton" .. ((slot - 6) * 2)]
end

------------------------------------------------------------------------
-- Chrome (must be defined BEFORE LayoutToSpellButtons uses it)
------------------------------------------------------------------------
local function ApplySpellButtonChrome(btn)
    if not btn then return end
    local ref = _G["SpellButton1"]
    local emptyTex = "Interface\\Spellbook\\UI-Spellbook-SpellBackground"
    local emptyW, emptyH, emptyX, emptyY = 64, 64, -3, 3

    local es = ref and (ref.EmptySlot or _G["SpellButton1Background"])
    if es then
        local ok, t = pcall(function() return es:GetTexture() end)
        if ok and t then emptyTex = t end
        local ok2, w, h = pcall(function() return es:GetSize() end)
        if ok2 and w and w > 0 then emptyW, emptyH = w, h end
        local ok3, _, _, _, x, y = pcall(function() return es:GetPoint(1) end)
        if ok3 and x then emptyX, emptyY = x, y end
    end

    if not btn.emptySlot then
        btn.emptySlot = btn:CreateTexture(nil, "BACKGROUND")
    end
    pcall(function()
        btn.emptySlot:SetTexture(emptyTex)
        if es and es.GetAtlas then
            local atlas = es:GetAtlas()
            if atlas and atlas ~= "" then
                btn.emptySlot:SetAtlas(atlas, true)
            end
        end
    end)
    btn.emptySlot:ClearAllPoints()
    btn.emptySlot:SetSize(emptyW, emptyH)
    btn.emptySlot:SetPoint("TOPLEFT", btn, "TOPLEFT", emptyX, emptyY)
    btn.emptySlot:Show()

    -- Optional SlotFrame / TextBackground (newer book art)
    local sf = ref and (ref.SlotFrame or _G["SpellButton1SlotFrame"])
    if sf then
        local ok, tex = pcall(function() return sf:GetTexture() end)
        if ok and tex then
            if not btn.slotFrame then
                btn.slotFrame = btn:CreateTexture(nil, "OVERLAY", nil, -1)
            end
            pcall(function()
                btn.slotFrame:SetTexture(tex)
                if sf.GetAtlas then
                    local atlas = sf:GetAtlas()
                    if atlas and atlas ~= "" then btn.slotFrame:SetAtlas(atlas, true) end
                end
            end)
            btn.slotFrame:ClearAllPoints()
            local okp, p, _, rp, x, y = pcall(function() return sf:GetPoint(1) end)
            if okp and p then
                btn.slotFrame:SetPoint(p, btn, rp or p, x or 0, y or 0)
                local okw, w, h = pcall(function() return sf:GetSize() end)
                if okw and w and w > 0 then btn.slotFrame:SetSize(w, h) end
            else
                btn.slotFrame:SetAllPoints(btn)
            end
            btn.slotFrame:Show()
        end
    end

    local tb = ref and (ref.TextBackground or _G["SpellButton1TextBackground"])
    if tb then
        local ok, tex = pcall(function() return tb:GetTexture() end)
        if ok and tex then
            if not btn.textBg then
                btn.textBg = btn:CreateTexture(nil, "BACKGROUND")
            end
            pcall(function()
                btn.textBg:SetTexture(tex)
                if tb.GetAtlas then
                    local atlas = tb:GetAtlas()
                    if atlas and atlas ~= "" then btn.textBg:SetAtlas(atlas, true) end
                end
            end)
            btn.textBg:ClearAllPoints()
            local okp, p, _, rp, x, y = pcall(function() return tb:GetPoint(1) end)
            if okp and p then
                btn.textBg:SetPoint(p, btn, rp or "TOPRIGHT", x or -4, y or -5)
            else
                btn.textBg:SetPoint("TOPLEFT", btn, "TOPRIGHT", -4, -5)
            end
            local okw, w, h = pcall(function() return tb:GetSize() end)
            if okw and w and w > 0 then btn.textBg:SetSize(w, h) end
            btn.textBg:Show()
        end
    end
end

------------------------------------------------------------------------
-- Macro list
------------------------------------------------------------------------
local function BuildMacroList()
    local list = {}
    local numAccount, numChar = GetNumMacros()
    numAccount = numAccount or 0
    numChar = numChar or 0
    local maxAccount = MAX_ACCOUNT_MACROS or 120

    for i = 1, numAccount do
        local name, icon, body = GetMacroInfo(i)
        if name then
            list[#list + 1] = { index = i, name = name, icon = icon, body = body, scope = "account" }
        end
    end
    for i = 1, numChar do
        local idx = maxAccount + i
        local name, icon, body = GetMacroInfo(idx)
        if name then
            list[#list + 1] = { index = idx, name = name, icon = icon, body = body, scope = "character" }
        end
    end
    return list
end

local function NumPages(list)
    return math.max(1, math.ceil(#list / BUTTONS_PER_PAGE))
end

------------------------------------------------------------------------
-- Show / hide overlay vs real spellbook page
------------------------------------------------------------------------
local function SetSpellButtonsShown(shown)
    for i = 1, BUTTONS_PER_PAGE do
        local b = _G["SpellButton" .. i]
        if b then
            if shown then b:Show() else b:Hide() end
        end
    end
    if SpellBookPageText then
        if active then SpellBookPageText:Hide() elseif shown then SpellBookPageText:Show() end
    end
    if SpellBookPrevPageButton then
        if active then SpellBookPrevPageButton:Hide() elseif shown then SpellBookPrevPageButton:Show() end
    end
    if SpellBookNextPageButton then
        if active then SpellBookNextPageButton:Hide() elseif shown then SpellBookNextPageButton:Show() end
    end
end

local function DeselectSkillLineTabs()
    for i = 1, (MAX_SKILLLINE_TABS or 8) do
        local t = _G["SpellBookSkillLineTab" .. i]
        if t and t.SetChecked then t:SetChecked(false) end
    end
end

local function UpdateMacroButtons()
    if not panel then return end
    local list = BuildMacroList()
    local pages = NumPages(list)
    if page > pages then page = pages end
    if page < 1 then page = 1 end

    local start = (page - 1) * BUTTONS_PER_PAGE
    for i = 1, BUTTONS_PER_PAGE do
        local btn = buttons[i]
        if not btn then break end
        local entry = list[start + i]
        if entry then
            btn.macroIndex = entry.index
            btn.icon:SetTexture(entry.icon or TAB_ICON)
            btn.name:SetText(entry.name)
            btn.subName:SetText(entry.scope == "character" and "Character" or "General")
            if btn.hotkey then
                local hk = ""
                if BookieBinds and BookieBinds.HotkeyTextForMacro then
                    hk = BookieBinds.HotkeyTextForMacro(entry.index) or ""
                end
                btn.hotkey:SetText(hk)
                if hk ~= "" then btn.hotkey:Show() else btn.hotkey:Hide() end
            end
            btn:Enable()
            btn:Show()
            btn.icon:Show()
            btn.name:Show()
            btn.subName:Show()
        else
            btn.macroIndex = nil
            btn.icon:SetTexture(nil)
            btn.icon:Hide()
            btn.name:SetText("")
            btn.subName:SetText("")
            if btn.hotkey then
                btn.hotkey:SetText("")
                btn.hotkey:Hide()
            end
            btn:Disable()
            btn:Show()
        end
    end

    if pageText then pageText:SetText(string.format("%d / %d", page, pages)) end
    if prevBtn then if page <= 1 then prevBtn:Disable() else prevBtn:Enable() end end
    if nextBtn then if page >= pages then nextBtn:Disable() else nextBtn:Enable() end end
end

local function LayoutToSpellButtons()
    for i = 1, BUTTONS_PER_PAGE do
        local btn = buttons[i]
        local sb = SpellButtonForSlot(i)
        if btn and sb then
            btn:ClearAllPoints()
            btn:SetAllPoints(sb)
            local w, h = sb:GetSize()
            if w and w > 0 then btn:SetSize(w, h) end
            pcall(ApplySpellButtonChrome, btn)

            btn.name:ClearAllPoints()
            btn.subName:ClearAllPoints()
            local sn = sb.SpellName or _G[sb:GetName() .. "SpellName"]
            local ssn = sb.SpellSubName or _G[sb:GetName() .. "SpellSubName"]
            if sn then
                local ok, point, _, relativePoint, x, y = pcall(function() return sn:GetPoint(1) end)
                if ok and point then
                    btn.name:SetPoint(point, btn, relativePoint or "RIGHT", x or 5, y or 3)
                else
                    btn.name:SetPoint("LEFT", btn, "RIGHT", 5, 3)
                end
                local okw, nw = pcall(function() return sn:GetWidth() end)
                if okw and nw and nw > 0 then btn.name:SetWidth(nw) end
            else
                btn.name:SetPoint("LEFT", btn, "RIGHT", 5, 3)
                btn.name:SetWidth(103)
            end
            if ssn then
                local ok, point, _, relativePoint, x, y = pcall(function() return ssn:GetPoint(1) end)
                if ok and point then
                    btn.subName:SetPoint(point, btn.name, relativePoint or "BOTTOMLEFT", x or 0, y or -2)
                else
                    btn.subName:SetPoint("TOPLEFT", btn.name, "BOTTOMLEFT", 0, -2)
                end
            else
                btn.subName:SetPoint("TOPLEFT", btn.name, "BOTTOMLEFT", 0, -2)
                btn.subName:SetSize(79, 18)
            end
        end
    end

    if prevBtn and SpellBookPrevPageButton then
        prevBtn:ClearAllPoints()
        prevBtn:SetAllPoints(SpellBookPrevPageButton)
        prevBtn:SetFrameLevel(SpellBookPrevPageButton:GetFrameLevel() + 5)
    end
    if nextBtn and SpellBookNextPageButton then
        nextBtn:ClearAllPoints()
        nextBtn:SetAllPoints(SpellBookNextPageButton)
        nextBtn:SetFrameLevel(SpellBookNextPageButton:GetFrameLevel() + 5)
    end
    if pageText and SpellBookPageText then
        pageText:ClearAllPoints()
        pageText:SetAllPoints(SpellBookPageText)
        pcall(function()
            pageText:SetFontObject(SpellBookPageText:GetFontObject())
            pageText:SetJustifyH(SpellBookPageText:GetJustifyH())
        end)
    end
end

local function ShowMacrosTab()
    if not SpellBookFrame or not SpellBookFrame:IsShown() then return end
    if not panel then return end
    active = true
    DeselectSkillLineTabs()
    if tabButton and tabButton.SetChecked then tabButton:SetChecked(true) end
    LayoutToSpellButtons()
    SetSpellButtonsShown(false)
    panel:Show()
    if prevBtn then prevBtn:Show() end
    if nextBtn then nextBtn:Show() end
    if pageText then pageText:Show() end
    UpdateMacroButtons()
end

local function HideMacrosTab()
    if not active then return end
    active = false
    if tabButton and tabButton.SetChecked then tabButton:SetChecked(false) end
    if panel then panel:Hide() end
    if prevBtn then prevBtn:Hide() end
    if nextBtn then nextBtn:Hide() end
    if pageText then pageText:Hide() end
    SetSpellButtonsShown(true)
end

------------------------------------------------------------------------
-- Button factory
------------------------------------------------------------------------
local function CreateMacroButton(parent, index)
    local btn = CreateFrame("CheckButton", "BookieButton" .. index, parent)
    btn:SetSize(37, 37)
    btn:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 1) + 10)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    pcall(ApplySpellButtonChrome, btn)

    btn.icon = btn:CreateTexture(nil, "BORDER")
    btn.icon:SetAllPoints()

    local nt = btn:CreateTexture(nil, "ARTWORK")
    nt:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    nt:SetSize(64, 64)
    nt:SetPoint("CENTER", 0, 0)
    btn:SetNormalTexture(nt)

    local pt = btn:CreateTexture(nil, "ARTWORK")
    pt:SetTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    pt:SetAllPoints()
    btn:SetPushedTexture(pt)

    local ht = btn:CreateTexture(nil, "HIGHLIGHT")
    ht:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    ht:SetAllPoints()
    ht:SetBlendMode("ADD")
    btn:SetHighlightTexture(ht)

    local ct = btn:CreateTexture(nil, "ARTWORK")
    ct:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    ct:SetAllPoints()
    ct:SetBlendMode("ADD")
    btn:SetCheckedTexture(ct)

    btn.name = btn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    btn.name:SetJustifyH("LEFT")
    btn.name:SetWordWrap(true)
    btn.name:SetWidth(103)
    if btn.name.SetMaxLines then btn.name:SetMaxLines(3) end

    local subFont = "GameFontHighlightSmall"
    if type(SubSpellFont) == "table" or type(SubSpellFont) == "string" then
        subFont = "SubSpellFont"
    end
    local okFont, fs = pcall(function()
        return btn:CreateFontString(nil, "ARTWORK", subFont)
    end)
    btn.subName = (okFont and fs) or btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    btn.subName:SetJustifyH("LEFT")
    btn.subName:SetSize(79, 18)

    btn.hotkey = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    btn.hotkey:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 2, -2)
    btn.hotkey:SetJustifyH("RIGHT")
    btn.hotkey:Hide()

    btn:SetScript("OnEnter", function(self)
        if not self.macroIndex then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local name, _, body = GetMacroInfo(self.macroIndex)
        GameTooltip:AddLine(name or "?", 1, 1, 1)
        if body and body ~= "" then
            GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Drag to an action bar", 0.2, 1, 0.2)
        GameTooltip:AddLine("Right-click to edit", 0.6, 0.6, 0.6)
        if BookieBinds and BookieBinds.IsEnabled and BookieBinds.IsEnabled() then
            local hk = BookieBinds.HotkeyTextForMacro and BookieBinds.HotkeyTextForMacro(self.macroIndex)
            if hk and hk ~= "" then
                GameTooltip:AddLine("Bookie bind: " .. hk, 0.4, 0.8, 1)
            end
            GameTooltip:AddLine("Alt-Right-Click to keybind", 0.2, 1, 0.2)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)

    btn:SetScript("OnDragStart", function(self)
        if not self.macroIndex then return end
        if InCombatLockdown and InCombatLockdown() then
            Print("Can't drag macros onto bars in combat.")
            return
        end
        local name = GetMacroInfo(self.macroIndex)
        if BookieBinds and BookieBinds.NoteDrag and name then
            BookieBinds.NoteDrag("macro", name)
        end
        PickupMacro(self.macroIndex)
    end)

    btn:SetScript("OnClick", function(self, button)
        if button == "RightButton" and self.macroIndex then
            if BookieBinds and BookieBinds.IsEnabled and BookieBinds.IsEnabled()
                and IsAltKeyDown and IsAltKeyDown() then
                local name = GetMacroInfo(self.macroIndex)
                if name and BookieBinds.StartBind then
                    BookieBinds.StartBind("macro", name)
                end
                self:SetChecked(false)
                return
            end
            if type(ShowMacroFrame) == "function" then
                ShowMacroFrame()
            elseif MacroFrame then
                ShowUIPanel(MacroFrame)
            end
            if MacroFrame_SelectMacro then
                pcall(MacroFrame_SelectMacro, self.macroIndex)
            end
        end
        self:SetChecked(false)
    end)

    return btn
end

local function ReanchorTab()
    if not tabButton or not SpellBookFrame then return end
    local anchor
    for i = (MAX_SKILLLINE_TABS or 8), 1, -1 do
        local t = _G["SpellBookSkillLineTab" .. i]
        if t and t:IsShown() then
            anchor = t
            break
        end
    end
    tabButton:ClearAllPoints()
    if anchor then
        tabButton:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -17)
    elseif SpellBookSkillLineTab1 then
        tabButton:SetPoint("TOPLEFT", SpellBookSkillLineTab1, "BOTTOMLEFT", 0, -17)
    else
        tabButton:SetPoint("TOPLEFT", SpellBookFrame, "TOPRIGHT", 0, -72)
    end
    tabButton:Show()
end

------------------------------------------------------------------------
-- Build UI
------------------------------------------------------------------------
local function EnsureUI()
    if not SpellBookFrame then return end
    if panel and tabButton then
        ReanchorTab()
        return
    end

    local ok, err = pcall(function()
        if not panel then
            local parent = SpellBookSpellIconsFrame or SpellBookFrame
            panel = CreateFrame("Frame", "BookiePanel", parent)
            panel:SetAllPoints(parent)
            panel:Hide()

            for i = 1, BUTTONS_PER_PAGE do
                buttons[i] = CreateMacroButton(panel, i)
            end
        end

        if not prevBtn then
            prevBtn = CreateFrame("Button", "BookiePrevPage", SpellBookFrame)
            prevBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
            prevBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
            prevBtn:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled")
            prevBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
            prevBtn:SetScript("OnClick", function()
                page = page - 1
                UpdateMacroButtons()
                if PlaySound then PlaySound(SOUNDKIT and SOUNDKIT.IG_ABILITY_PAGE_TURN or 450) end
            end)
            prevBtn:Hide()
        end

        if not nextBtn then
            nextBtn = CreateFrame("Button", "BookieNextPage", SpellBookFrame)
            nextBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
            nextBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
            nextBtn:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled")
            nextBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
            nextBtn:SetScript("OnClick", function()
                page = page + 1
                UpdateMacroButtons()
                if PlaySound then PlaySound(SOUNDKIT and SOUNDKIT.IG_ABILITY_PAGE_TURN or 450) end
            end)
            nextBtn:Hide()
        end

        if not pageText then
            pageText = SpellBookFrame:CreateFontString("BookiePageText", "ARTWORK", "GameFontHighlightSmall")
            pageText:Hide()
        end

        pcall(LayoutToSpellButtons)

        if not tabButton then
            local created
            created = pcall(function()
                tabButton = CreateFrame("CheckButton", "BookieTab", SpellBookFrame, "SpellBookSkillLineTabTemplate")
            end)
            if not created or not tabButton then
                tabButton = CreateFrame("CheckButton", "BookieTab", SpellBookFrame)
                tabButton:SetSize(32, 32)
                local ht = tabButton:CreateTexture(nil, "HIGHLIGHT")
                ht:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
                ht:SetAllPoints()
                ht:SetBlendMode("ADD")
                tabButton:SetHighlightTexture(ht)
            end

            if SpellBookSideTabsFrame then
                tabButton:SetParent(SpellBookSideTabsFrame)
            end

            pcall(function() tabButton:SetNormalTexture(TAB_ICON) end)
            local icon = _G["BookieTabIconTexture"] or tabButton.IconTexture or tabButton.icon
            if icon and icon.SetTexture then
                icon:SetTexture(TAB_ICON)
            elseif tabButton.GetNormalTexture and tabButton:GetNormalTexture() then
                tabButton:GetNormalTexture():SetTexture(TAB_ICON)
            else
                tabButton:SetNormalTexture(TAB_ICON)
            end

            tabButton:SetScript("OnClick", function()
                ShowMacrosTab()
            end)
            tabButton:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Macros")
                GameTooltip:AddLine("Browse and drag your macros like spells.", 1, 1, 1, true)
                GameTooltip:Show()
            end)
            tabButton:SetScript("OnLeave", GameTooltip_Hide)

            for i = 1, (MAX_SKILLLINE_TABS or 8) do
                local t = _G["SpellBookSkillLineTab" .. i]
                if t and not t.BookieHooked then
                    t.BookieHooked = true
                    t:HookScript("OnClick", function()
                        HideMacrosTab()
                    end)
                end
            end
        end

        ReanchorTab()
    end)

    if not ok then
        Print("UI setup error: " .. tostring(err))
    end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local hookedShow
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("UPDATE_MACROS")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 ~= ADDON then return end
    if event == "UPDATE_MACROS" then
        if active then UpdateMacroButtons() end
        return
    end

    EnsureUI()

    if SpellBookFrame and not hookedShow then
        hookedShow = true
        SpellBookFrame:HookScript("OnShow", function()
            EnsureUI()
            ReanchorTab()
            pcall(LayoutToSpellButtons)
            if active then
                ShowMacrosTab()
            elseif tabButton then
                tabButton:Show()
            end
        end)
        SpellBookFrame:HookScript("OnHide", function()
            if panel then panel:Hide() end
            if prevBtn then prevBtn:Hide() end
            if nextBtn then nextBtn:Hide() end
            if pageText then pageText:Hide() end
        end)
    end
end)

function Bookie_RefreshMacroHotkeys()
    if active then UpdateMacroButtons() end
end

SLASH_BOOKIE1 = "/bookie"
SLASH_BOOKIE2 = "/sbm"
SlashCmdList["BOOKIE"] = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = string.lower(cmd or "")

    if cmd == "binds" or cmd == "bind" or cmd == "keybind" then
        if BookieBinds and BookieBinds.HandleSlash then
            BookieBinds.HandleSlash(rest)
        else
            Print("Binds module missing — reinstall Bookie.")
        end
        return
    end

    if cmd == "help" then
        Print("v" .. VERSION)
        Print("/bookie — open Macros tab")
        Print("/bookie binds on|off|status — spellbook keybinds (off by default)")
        return
    end

    Print("v" .. VERSION .. " — open the spellbook (P) and click the Macros tab.")
    Print("Optional: /bookie binds on — bind spells in the book, then drag to bars.")
    EnsureUI()
    if SpellBookFrame and not SpellBookFrame:IsShown() then
        if type(ToggleSpellBook) == "function" then
            pcall(ToggleSpellBook, BOOKTYPE_SPELL or "spell")
        else
            ShowUIPanel(SpellBookFrame)
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.15, function()
            EnsureUI()
            ShowMacrosTab()
            if tabButton then
                Print("tab visible=" .. tostring(tabButton:IsShown()))
            else
                Print("tab missing — check for a Bookie UI setup error above.")
            end
        end)
    end
end
