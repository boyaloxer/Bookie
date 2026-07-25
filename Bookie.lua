-- Bookie
-- Extra spellbook tab that lists your macros (account + character) in a
-- spellbook-style grid. Drag them onto action bars like spells.
--
-- Intentionally does NOT call SpellBookFrame_Update / page buttons — those
-- taint the real spell buttons. We overlay our own page and hide theirs.

local ADDON = ...
local VERSION = "1.0.0"

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
-- Macro list (account macros first, then character)
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
        if shown and not active then SpellBookPageText:Show() elseif active then SpellBookPageText:Hide() end
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
        if t and t.SetChecked then
            t:SetChecked(false)
        end
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
        local entry = list[start + i]
        if entry then
            btn.macroIndex = entry.index
            btn.macroName = entry.name
            btn.icon:SetTexture(entry.icon or TAB_ICON)
            btn.name:SetText(entry.name)
            local sub = entry.scope == "character" and "Character" or "General"
            btn.subName:SetText(sub)
            btn:Enable()
            btn:SetAlpha(1)
            btn:Show()
        else
            btn.macroIndex = nil
            btn.macroName = nil
            btn.icon:SetTexture(nil)
            btn.name:SetText("")
            btn.subName:SetText("")
            btn:Disable()
            btn:SetAlpha(0.35)
            btn:Show()
        end
    end

    if pageText then
        pageText:SetText(string.format("Page %d/%d", page, pages))
    end
    if prevBtn then
        if page <= 1 then prevBtn:Disable() else prevBtn:Enable() end
    end
    if nextBtn then
        if page >= pages then nextBtn:Disable() else nextBtn:Enable() end
    end
end

local function ShowMacrosTab()
    if not SpellBookFrame or not SpellBookFrame:IsShown() then return end
    active = true
    DeselectSkillLineTabs()
    if tabButton and tabButton.SetChecked then tabButton:SetChecked(true) end
    SetSpellButtonsShown(false)
    panel:Show()
    UpdateMacroButtons()
end

local function HideMacrosTab()
    if not active then return end
    active = false
    if tabButton and tabButton.SetChecked then tabButton:SetChecked(false) end
    if panel then panel:Hide() end
    SetSpellButtonsShown(true)
end

------------------------------------------------------------------------
-- Button factory (spellbook-ish look)
------------------------------------------------------------------------
local function CreateMacroButton(parent, index)
    local btn = CreateFrame("CheckButton", "BookieButton" .. index, parent)
    btn:SetSize(37, 37)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

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

    btn.name = btn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    btn.name:SetPoint("LEFT", btn, "RIGHT", 6, 6)
    btn.name:SetPoint("RIGHT", parent, "RIGHT", -20, 0)
    btn.name:SetJustifyH("LEFT")
    btn.name:SetTextColor(1, 0.82, 0)

    btn.subName = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    btn.subName:SetPoint("TOPLEFT", btn.name, "BOTTOMLEFT", 0, -2)
    btn.subName:SetJustifyH("LEFT")
    btn.subName:SetTextColor(0.7, 0.7, 0.7)

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
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)

    btn:SetScript("OnDragStart", function(self)
        if not self.macroIndex then return end
        if InCombatLockdown and InCombatLockdown() then
            Print("Can't drag macros onto bars in combat.")
            return
        end
        PickupMacro(self.macroIndex)
    end)

    btn:SetScript("OnClick", function(self, button)
        if button == "RightButton" and self.macroIndex then
            if type(ShowMacroFrame) == "function" then
                ShowMacroFrame()
            elseif MacroFrame then
                ShowUIPanel(MacroFrame)
            end
            if MacroFrame_SelectMacro and self.macroIndex then
                pcall(MacroFrame_SelectMacro, self.macroIndex)
            end
        end
    end)

    return btn
end

local function LayoutButtons()
    for i = 1, BUTTONS_PER_PAGE do
        local btn = buttons[i]
        local col = (i > 6) and 2 or 1
        local row = ((i - 1) % 6) + 1
        btn:ClearAllPoints()
        if col == 1 then
            btn:SetPoint("TOPLEFT", panel, "TOPLEFT", 32, -40 - (row - 1) * 50)
        else
            btn:SetPoint("TOPLEFT", panel, "TOPLEFT", 225, -40 - (row - 1) * 50)
        end
    end
end

------------------------------------------------------------------------
-- Build UI once SpellBookFrame exists
------------------------------------------------------------------------
local function EnsureUI()
    if panel or not SpellBookFrame then return end

    panel = CreateFrame("Frame", "BookiePanel", SpellBookFrame)
    panel:SetPoint("TOPLEFT", SpellBookFrame, "TOPLEFT", 20, -75)
    panel:SetPoint("BOTTOMRIGHT", SpellBookFrame, "BOTTOMRIGHT", -40, 80)
    panel:Hide()

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", panel, "TOP", 0, -4)
    title:SetText("Macros")

    for i = 1, BUTTONS_PER_PAGE do
        buttons[i] = CreateMacroButton(panel, i)
    end
    LayoutButtons()

    prevBtn = CreateFrame("Button", "BookiePrevPage", panel)
    prevBtn:SetSize(32, 32)
    prevBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 40, 8)
    prevBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    prevBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
    prevBtn:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled")
    prevBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    prevBtn:SetScript("OnClick", function()
        page = page - 1
        UpdateMacroButtons()
    end)

    nextBtn = CreateFrame("Button", "BookieNextPage", panel)
    nextBtn:SetSize(32, 32)
    nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
    nextBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    nextBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    nextBtn:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled")
    nextBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    nextBtn:SetScript("OnClick", function()
        page = page + 1
        UpdateMacroButtons()
    end)

    pageText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    pageText:SetPoint("LEFT", nextBtn, "RIGHT", 10, 0)

    local template = "SpellBookSkillLineTabTemplate"
    local ok
    ok = pcall(function()
        tabButton = CreateFrame("CheckButton", "BookieTab", SpellBookFrame, template)
    end)
    if not ok or not tabButton then
        tabButton = CreateFrame("CheckButton", "BookieTab", SpellBookFrame)
        tabButton:SetSize(32, 32)
        tabButton:SetNormalTexture(TAB_ICON)
        local ht = tabButton:CreateTexture(nil, "HIGHLIGHT")
        ht:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        ht:SetAllPoints()
        ht:SetBlendMode("ADD")
        tabButton:SetHighlightTexture(ht)
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

    if tabButton.GetNormalTexture and tabButton:GetNormalTexture() then
        pcall(function() tabButton:SetNormalTexture(TAB_ICON) end)
    end
    local icon = _G[tabButton:GetName() .. "IconTexture"] or tabButton.IconTexture or tabButton.icon
    if icon and icon.SetTexture then icon:SetTexture(TAB_ICON) end

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
        tabButton:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -15)
    else
        tabButton:SetPoint("TOPLEFT", SpellBookFrame, "TOPRIGHT", 0, -80)
    end
    tabButton:Show()

    for i = 1, (MAX_SKILLLINE_TABS or 8) do
        local t = _G["SpellBookSkillLineTab" .. i]
        if t then
            t:HookScript("OnClick", function()
                HideMacrosTab()
            end)
        end
    end
end

local function ReanchorTab()
    if not tabButton then return end
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
        tabButton:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -15)
    else
        tabButton:SetPoint("TOPLEFT", SpellBookFrame, "TOPRIGHT", 0, -80)
    end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("UPDATE_MACROS")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 ~= ADDON then return end
    if event == "UPDATE_MACROS" then
        if active then UpdateMacroButtons() end
        return
    end
    EnsureUI()
    if SpellBookFrame then
        SpellBookFrame:HookScript("OnShow", function()
            EnsureUI()
            ReanchorTab()
            if active then
                ShowMacrosTab()
            else
                if tabButton then tabButton:Show() end
            end
        end)
        SpellBookFrame:HookScript("OnHide", function()
            if panel then panel:Hide() end
        end)
    end
end)

SLASH_BOOKIE1 = "/bookie"
SLASH_BOOKIE2 = "/sbm"
SlashCmdList["BOOKIE"] = function()
    Print("v" .. VERSION .. " — open the spellbook (P) and click the Macros tab on the right.")
    if SpellBookFrame and not SpellBookFrame:IsShown() then
        if type(ToggleSpellBook) == "function" then
            pcall(ToggleSpellBook, BOOKTYPE_SPELL or "spell")
        else
            ShowUIPanel(SpellBookFrame)
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, function()
            EnsureUI()
            ShowMacrosTab()
        end)
    end
end
