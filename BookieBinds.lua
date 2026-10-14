-- Bookie — spellbook keybinds (optional)
-- Toggle: /bookie binds on|off
-- When on: Alt-Right-Click a spell (or Bookie macro) → press a key to bind.
-- Dragging that spell/macro onto a bar moves the key onto that bar button.
-- Off by default; your normal ACTIONBUTTON binds are untouched until you rebind.

local ADDON = ...

BookieBinds = BookieBinds or {}
local M = BookieBinds

local binder
local pending -- { kind="spell"|"macro", name=string, key=string|nil }
local listening -- { kind, name }
local spellHotkeys = {}

local MOD_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, LMETA = true, RMETA = true,
}

local function Print(msg)
    print("|cff66ccffBookie|r " .. msg)
end

local function DB()
    if not BookieDB then BookieDB = {} end
    return BookieDB
end

function M.IsEnabled()
    return DB().bindsMode == true
end

-- Always persist Bookie edits as CHARACTER binds (2), never account (1).
-- Saving to the account set was overwriting ACTIONBUTTON keys for every toon.
local function CharacterBindingSet()
    return (CHARACTER_BINDINGS or 2)
end

local function SaveBindChanges()
    if type(SaveBindings) ~= "function" then
        return
    end
    local which = CharacterBindingSet()
    -- If account binds are currently loaded, this writes a per-character overlay
    -- from the in-memory set (including our edit) without touching account binds on disk.
    pcall(SaveBindings, which)
end

------------------------------------------------------------------------
-- Action slot → binding command
------------------------------------------------------------------------
local function ActionSlotToCommand(slot)
    slot = tonumber(slot)
    if not slot then return nil end
    if slot >= 1 and slot <= 12 then
        return "ACTIONBUTTON" .. slot
    elseif slot >= 13 and slot <= 24 then
        return "MULTIACTIONBAR1BUTTON" .. (slot - 12)
    elseif slot >= 25 and slot <= 36 then
        return "MULTIACTIONBAR2BUTTON" .. (slot - 24)
    elseif slot >= 37 and slot <= 48 then
        return "MULTIACTIONBAR3BUTTON" .. (slot - 36)
    elseif slot >= 49 and slot <= 60 then
        return "MULTIACTIONBAR4BUTTON" .. (slot - 48)
    elseif slot >= 61 and slot <= 72 then
        return "BONUSACTIONBUTTON" .. (slot - 60)
    end
    return nil
end

-- Classic/TBC: bare "SPELL Fear" applies to the spell name (all ranks / max).
-- Rank-specific binds use "Fear(Rank 3)" with no space before "(".
local function SpellBindName(name, sub)
    if not name or name == "" then return nil end
    if sub and sub ~= "" and string.match(sub, "^[Rr]ank%s*%d+") then
        return name .. "(" .. sub .. ")"
    end
    return name
end

local function SpellBaseName(bindName)
    if not bindName then return nil end
    return string.match(bindName, "^(.-)%s*%(") or bindName
end

local function BindingCommandForTarget(kind, name)
    if not name then return nil end
    if kind == "spell" then
        return "SPELL " .. name
    elseif kind == "macro" then
        return "MACRO " .. name
    end
    return nil
end

local function KeyForTarget(kind, name)
    local cmd = BindingCommandForTarget(kind, name)
    if not cmd or type(GetBindingKey) ~= "function" then return nil end
    local k1 = GetBindingKey(cmd)
    return k1
end

-- Remove a bare unranked "SPELL Name" bind so it doesn't cover every rank.
local function ClearUnrankedSpellBind(bindName, keepKey)
    local base = SpellBaseName(bindName)
    if not base or base == bindName then return end
    if type(GetBindingKey) ~= "function" then return end
    local k1, k2 = GetBindingKey("SPELL " .. base)
    if k1 and k1 ~= keepKey then SetBinding(k1) end
    if k2 and k2 ~= keepKey then SetBinding(k2) end
end

local function FormatKey(key)
    if not key or key == "" then return "" end
    if type(GetBindingText) == "function" then
        local ok, text = pcall(GetBindingText, key, "KEY_", 1)
        if ok and text and text ~= "" then return text end
    end
    return key
end

------------------------------------------------------------------------
-- Spellbook item helpers
------------------------------------------------------------------------
local function SpellInfoFromButton(btn)
    if not btn then return nil end
    local slot, bookType
    if type(SpellBook_GetSpellBookSlot) == "function" then
        local ok, s, b = pcall(SpellBook_GetSpellBookSlot, btn)
        if ok then slot, bookType = s, b end
    end
    if not slot then
        slot = btn.spellBookID or btn:GetID()
        bookType = BOOKTYPE_SPELL or "spell"
    end
    if not slot or slot == 0 then return nil end
    bookType = bookType or BOOKTYPE_SPELL or "spell"

    local name, sub
    if type(GetSpellBookItemName) == "function" then
        local ok, n, s = pcall(GetSpellBookItemName, slot, bookType)
        if ok then name, sub = n, s end
    end
    if not name and type(GetSpellName) == "function" then
        local ok, n, s = pcall(GetSpellName, slot, bookType)
        if ok then name, sub = n, s end
    end
    if not name or name == "" then return nil end
    return name, sub, slot, bookType
end

------------------------------------------------------------------------
-- Hotkey labels on Blizzard spell buttons
------------------------------------------------------------------------
local function EnsureSpellHotkey(btn)
    if not btn then return nil end
    local fs = spellHotkeys[btn]
    if fs then return fs end
    fs = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    fs:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 2, -2)
    fs:SetJustifyH("RIGHT")
    spellHotkeys[btn] = fs
    return fs
end

function M.RefreshSpellHotkeys()
    for i = 1, 12 do
        local btn = _G["SpellButton" .. i]
        if btn then
            local fs = EnsureSpellHotkey(btn)
            if not M.IsEnabled() or not btn:IsShown() then
                fs:SetText("")
                fs:Hide()
            else
                local name, sub = SpellInfoFromButton(btn)
                local bindName = SpellBindName(name, sub)
                local key = bindName and KeyForTarget("spell", bindName)
                if key then
                    fs:SetText(FormatKey(key))
                    fs:Show()
                else
                    fs:SetText("")
                    fs:Hide()
                end
            end
        end
    end
end

function M.HotkeyTextForMacro(macroIndex)
    if not M.IsEnabled() or not macroIndex then return "" end
    local name = GetMacroInfo(macroIndex)
    if not name then return "" end
    return FormatKey(KeyForTarget("macro", name) or "")
end

------------------------------------------------------------------------
-- Key capture
------------------------------------------------------------------------
local function StopListening(silent)
    listening = nil
    if binder then
        binder:Hide()
        binder:EnableKeyboard(false)
    end
    if not silent then
        Print("Bind cancelled.")
    end
end

local function ApplyBind(key)
    if not listening or not key then return end
    if InCombatLockdown and InCombatLockdown() then
        Print("Can't change keybinds in combat.")
        StopListening(true)
        return
    end

    local kind, name = listening.kind, listening.name
    local existing = type(GetBindingByKey) == "function" and GetBindingByKey(key) or nil
    if existing and existing ~= "" and existing ~= BindingCommandForTarget(kind, name) then
        Print("Note: " .. FormatKey(key) .. " was " .. existing .. " — replacing.")
    end

    local ok
    if kind == "spell" and type(SetBindingSpell) == "function" then
        ok = SetBindingSpell(key, name)
    elseif kind == "macro" and type(SetBindingMacro) == "function" then
        ok = SetBindingMacro(key, name)
    else
        ok = SetBinding(key, BindingCommandForTarget(kind, name))
    end

    if ok then
        if kind == "spell" then
            ClearUnrankedSpellBind(name, key)
        end
        SaveBindChanges()
        Print(string.format("Bound %s → %s (%s).", FormatKey(key), name, kind))
        DB().owned = DB().owned or {}
        DB().owned[key] = { kind = kind, name = name }
    else
        Print("Could not bind " .. FormatKey(key) .. ".")
    end

    listening = nil
    if binder then
        binder:Hide()
        binder:EnableKeyboard(false)
    end
    M.RefreshSpellHotkeys()
    if type(Bookie_RefreshMacroHotkeys) == "function" then
        Bookie_RefreshMacroHotkeys()
    end
end

local function ModifierPrefix()
    local parts = {}
    if IsAltKeyDown and IsAltKeyDown() then parts[#parts + 1] = "ALT" end
    if IsControlKeyDown and IsControlKeyDown() then parts[#parts + 1] = "CTRL" end
    if IsShiftKeyDown and IsShiftKeyDown() then parts[#parts + 1] = "SHIFT" end
    if #parts == 0 then return "" end
    return table.concat(parts, "-") .. "-"
end

local function EnsureBinder()
    if binder then return binder end
    binder = CreateFrame("Frame", "BookieBinder", UIParent)
    binder:SetFrameStrata("FULLSCREEN_DIALOG")
    binder:EnableMouse(true)
    binder:SetAllPoints(UIParent)
    binder:Hide()

    local bg = binder:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if bg.SetColorTexture then
        bg:SetColorTexture(0, 0, 0, 0.35)
    else
        bg:SetTexture(0, 0, 0, 0.35)
    end

    local text = binder:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("CENTER", 0, 40)
    binder.text = text

    local hint = binder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    hint:SetPoint("TOP", text, "BOTTOM", 0, -8)
    hint:SetText("Press a key (Esc to cancel, Backspace to clear)")
    binder.hint = hint

    binder:SetScript("OnKeyDown", function(self, key)
        if not listening then return end
        if MOD_KEYS[key] then return end
        if key == "ESCAPE" then
            StopListening()
            return
        end
        if key == "BACKSPACE" or key == "DELETE" then
            local cmd = BindingCommandForTarget(listening.kind, listening.name)
            local k1, k2 = GetBindingKey(cmd)
            if k1 then SetBinding(k1) end
            if k2 then SetBinding(k2) end
            SaveBindChanges()
            Print("Cleared bind for " .. listening.name)
            listening = nil
            self:Hide()
            self:EnableKeyboard(false)
            M.RefreshSpellHotkeys()
            if type(Bookie_RefreshMacroHotkeys) == "function" then
                Bookie_RefreshMacroHotkeys()
            end
            return
        end
        ApplyBind(ModifierPrefix() .. key)
    end)

    binder:SetScript("OnMouseDown", function(self, button)
        if not listening then return end
        if button == "LeftButton" or button == "RightButton" or button == "MiddleButton" then
            return -- ignore normal clicks on the dimmer
        end
        -- BUTTON4 / BUTTON5
        local map = { Button4 = "BUTTON4", Button5 = "BUTTON5" }
        local b = map[button]
        if b then ApplyBind(ModifierPrefix() .. b) end
    end)

    binder:SetScript("OnMouseWheel", function(self, delta)
        if not listening then return end
        local wheel = delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"
        ApplyBind(ModifierPrefix() .. wheel)
    end)

    return binder
end

function M.StartBind(kind, name)
    if not M.IsEnabled() then
        Print("Spellbook binds are off. Use |cffffffff/bookie binds on|r first.")
        return
    end
    if not name or name == "" then return end
    if InCombatLockdown and InCombatLockdown() then
        Print("Can't change keybinds in combat.")
        return
    end
    listening = { kind = kind, name = name }
    local f = EnsureBinder()
    f.text:SetText("Bind key for: " .. name)
    f:Show()
    f:EnableKeyboard(true)
    if f.SetPropagateKeyboardInput then
        pcall(function() f:SetPropagateKeyboardInput(false) end)
    end
    Print("Listening for a key…")
end

function M.StartBindSpellButton(btn)
    local name, sub = SpellInfoFromButton(btn)
    local bindName = SpellBindName(name, sub)
    if not bindName then
        Print("No spell on that button.")
        return
    end
    M.StartBind("spell", bindName)
end

function M.NoteDrag(kind, name, sub)
    if not M.IsEnabled() or not name then
        pending = nil
        return
    end
    local bindName = name
    if kind == "spell" then
        bindName = SpellBindName(name, sub) or name
    end
    pending = {
        kind = kind,
        name = bindName,
        key = KeyForTarget(kind, bindName),
    }
end

function M.ClearPending()
    pending = nil
end

------------------------------------------------------------------------
-- Place on action bar → move key onto that button
------------------------------------------------------------------------
local function TransferPendingToSlot(slot)
    if not M.IsEnabled() or not pending or not pending.key then
        pending = nil
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        Print("Can't move keybinds in combat.")
        pending = nil
        return
    end
    local cmd = ActionSlotToCommand(slot)
    if not cmd then
        pending = nil
        return
    end
    local key = pending.key
    local label = pending.name
    local ok = SetBinding(key, cmd)
    if ok then
        SaveBindChanges()
        Print(string.format("Moved %s with %s → %s.", label, FormatKey(key), cmd))
    else
        Print("Could not move bind to action slot " .. tostring(slot) .. ".")
    end
    pending = nil
    M.RefreshSpellHotkeys()
    if type(Bookie_RefreshMacroHotkeys) == "function" then
        Bookie_RefreshMacroHotkeys()
    end
end

------------------------------------------------------------------------
-- Hook spellbook buttons
------------------------------------------------------------------------
local hookedSpells

local function HookSpellButtons()
    if hookedSpells then return end
    hookedSpells = true
    for i = 1, 12 do
        local btn = _G["SpellButton" .. i]
        if btn then
            EnsureSpellHotkey(btn)
            btn:HookScript("OnMouseUp", function(self, button)
                if not M.IsEnabled() then return end
                if button == "RightButton" and IsAltKeyDown and IsAltKeyDown() then
                    M.StartBindSpellButton(self)
                end
            end)
            btn:HookScript("OnDragStart", function(self)
                if not M.IsEnabled() then return end
                local name, sub = SpellInfoFromButton(self)
                if name then M.NoteDrag("spell", name, sub) end
            end)
            btn:HookScript("OnEnter", function(self)
                if not M.IsEnabled() or not GameTooltip:IsShown() then return end
                local name, sub = SpellInfoFromButton(self)
                local bindName = SpellBindName(name, sub)
                if not bindName then return end
                local key = KeyForTarget("spell", bindName)
                GameTooltip:AddLine(" ")
                if key then
                    GameTooltip:AddLine("Bookie bind: " .. FormatKey(key) .. " → " .. bindName, 0.4, 0.8, 1)
                end
                GameTooltip:AddLine("Alt-Right-Click to keybind this rank", 0.2, 1, 0.2)
                if key then
                    GameTooltip:AddLine("Drag to a bar to attach this key to the slot", 0.6, 0.6, 0.6)
                end
                GameTooltip:Show()
            end)
        end
    end
end

------------------------------------------------------------------------
-- Enable / disable
------------------------------------------------------------------------
function M.SetEnabled(on)
    DB().bindsMode = on and true or false
    if not on then
        StopListening(true)
        pending = nil
    end
    M.RefreshSpellHotkeys()
    if type(Bookie_RefreshMacroHotkeys) == "function" then
        Bookie_RefreshMacroHotkeys()
    end
    if on then
        Print("Spellbook binds |cff00ff00ON|r — Alt-Right-Click a spell, then press a key.")
        Print("Drag a bound spell onto a bar to attach that key to the bar button.")
        Print("Bookie saves those binds |cff66ccffper character|r (won't rewrite account-wide binds for alts).")
        Print("Note: a key can only do one thing — binding it in the book replaces that key on the bar |cffaaaaaafor this character|r.")
    else
        Print("Spellbook binds |cffff6666OFF|r — normal action-bar keybinds only.")
    end
end

function M.HandleSlash(arg)
    arg = strtrim(string.lower(arg or ""))
    if arg == "on" or arg == "1" or arg == "enable" then
        M.SetEnabled(true)
    elseif arg == "off" or arg == "0" or arg == "disable" then
        M.SetEnabled(false)
    elseif arg == "status" or arg == "" then
        Print("Spellbook binds: " .. (M.IsEnabled() and "|cff00ff00ON|r" or "|cffff6666OFF|r"))
        Print("Usage: /bookie binds on|off|status")
    else
        Print("Usage: /bookie binds on|off|status")
    end
end

------------------------------------------------------------------------
-- Events / secure hooks
------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("UPDATE_BINDINGS")
f:RegisterEvent("SPELLS_CHANGED")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        BookieDB = BookieDB or {}
        return
    end
    HookSpellButtons()
    if event == "UPDATE_BINDINGS" or event == "SPELLS_CHANGED" or event == "PLAYER_LOGIN" then
        M.RefreshSpellHotkeys()
    end
end)

if type(hooksecurefunc) == "function" then
    pcall(hooksecurefunc, "PlaceAction", function(slot)
        TransferPendingToSlot(slot)
    end)
    pcall(hooksecurefunc, "PickupAction", function()
        -- picking up from a bar shouldn't keep a spellbook pending
        -- (only clear if we're not mid spellbook drag — hard to know; leave pending)
    end)
end

local function HookSpellBookChrome()
    if SpellBookFrame and not SpellBookFrame.BookieBindsShowHooked then
        SpellBookFrame.BookieBindsShowHooked = true
        SpellBookFrame:HookScript("OnShow", function()
            HookSpellButtons()
            if C_Timer and C_Timer.After then
                C_Timer.After(0.05, M.RefreshSpellHotkeys)
            else
                M.RefreshSpellHotkeys()
            end
        end)
    end
    local function afterPage()
        if C_Timer and C_Timer.After then
            C_Timer.After(0.05, M.RefreshSpellHotkeys)
        else
            M.RefreshSpellHotkeys()
        end
    end
    if SpellBookPrevPageButton and not SpellBookPrevPageButton.BookieBindsHooked then
        SpellBookPrevPageButton.BookieBindsHooked = true
        SpellBookPrevPageButton:HookScript("OnClick", afterPage)
    end
    if SpellBookNextPageButton and not SpellBookNextPageButton.BookieBindsHooked then
        SpellBookNextPageButton.BookieBindsHooked = true
        SpellBookNextPageButton:HookScript("OnClick", afterPage)
    end
    for i = 1, (MAX_SKILLLINE_TABS or 8) do
        local t = _G["SpellBookSkillLineTab" .. i]
        if t and not t.BookieBindsHooked then
            t.BookieBindsHooked = true
            t:HookScript("OnClick", afterPage)
        end
    end
end

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", HookSpellBookChrome)
