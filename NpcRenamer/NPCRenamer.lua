-- #############################################################
-- NPCRenamer.lua (RETAIL FULL VERSION - TWW)
-- Pełna rekonstrukcja funkcjonalności z zachowaniem standardów Retail.
-- #############################################################

NPCRenamerDB = NPCRenamerDB or {}
NPCRenamerMissing = NPCRenamerMissing or {}

local FONT_PATH = "Interface\\AddOns\\NPCRenamer\\fonts\\frizquadratatt_pl.ttf"
local FONT_SIZE_FRAME = 12
local FONT_SIZE_NAMEPLATE = 12
local FONT_FLAGS = ""

---------------------------------------------------------------
-- Utils & Safety
---------------------------------------------------------------
local function Trim(s)
    if not s then return s end
    s = tostring(s)
    return s:match("^%s*(.-)%s*$")
end

local function SafeApplyFont(obj, size, flags)
    if not obj or obj:IsForbidden() then return false end
    size = size or FONT_SIZE_FRAME
    flags = flags or FONT_FLAGS
    pcall(function()
        if type(obj.SetFont) == "function" then
            obj:SetFont(FONT_PATH, size, flags)
        elseif type(obj.GetFontString) == "function" then
            local fs = obj:GetFontString()
            if fs then fs:SetFont(FONT_PATH, size, flags) end
        end
    end)
end

local function SafeGetText(obj)
    if not obj or obj:IsForbidden() then return nil end
    local ok, res = pcall(function() return obj:GetText() end)
    return ok and res or nil
end

local function SafeSetText(obj, text)
    if not obj or not text or obj:IsForbidden() then return false end
    pcall(function() obj:SetText(text) end)
end

---------------------------------------------------------------
-- Logika Nazw (Wszystkie wzorce przywrócone)
---------------------------------------------------------------
local function IsValidNPCName(name)
    if not name then return false end
    local s = Trim(name)
    if s == "" or not s:match("%a") then return false end
    local blacklist = {
        ["Title Text"]=true, ["TitleText"]=true, ["Merchant Name"]=true,
        ["Trainer Name"]=true, ["Name"]=true, ["Name Text"]=true,
        ["Text"]=true, ["Title"]=true,
    }
    return not blacklist[s] and not s:match("^%[.*%]$")
end

local function TranslateCreatureType(t)
    local map = {
        ["Aquatic"] = "Wodny", ["Beast"] = "Bestia", ["Critter"] = "Stworzenie",
        ["Dragonkin"] = "Smoczek", ["Elemental"] = "Żywiołak", ["Flying"] = "Latający",
        ["Humanoid"] = "Humanoidalny", ["Magic"] = "Magiczny", ["Mechanical"] = "Mechaniczny",
        ["Undead"] = "Nieumarły", ["Corpse"] = "Zwłoki",
    }
    return map[t] or t
end

local NPCCache = {}

local function GetCustomName(original)
    if not original or original == "" then return nil end
    local orig = Trim(original)
    if not IsValidNPCName(orig) then return nil end
    if NPCCache[orig] then return NPCCache[orig] end

    -- Zwierzaki gracza
    local playerName = UnitName("player")
    if playerName then
        local escapedName = playerName:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
        local owner = orig:match("^" .. escapedName .. "'s%s+(%a+)$")
        if owner == "Pet" then return "Zwierzak " .. playerName
        elseif owner == "Guardian" then return "Opiekun " .. playerName end
    end

    -- Rozbudowane wzorce poziomów i typów
    local petLevel, petType = orig:match("^Pet%s+Level%s*([%d?]+)%s*(%a+)$")
    if petLevel then return string.format("Zwierzak Poziom %s %s", petLevel, TranslateCreatureType(petType)) end

    local lvlNonCombat = orig:match("^Level%s*([%d?]+)%s+Non%-combat%s+Pet$")
    if lvlNonCombat then return string.format("Poziom %s Zwierzak Niebojowy", lvlNonCombat) end

    local lvl, creature, extra = orig:match("^Level%s*([%d?]+)%s*([%a]+)%s*%(([^)]+)%)$")
    if lvl and creature then return string.format("Poziom %s %s (%s)", lvl, TranslateCreatureType(creature), extra) end

    lvl, creature = orig:match("^Level%s*([%d?]+)%s*([%a]+)$")
    if lvl then return string.format("Poziom %s %s", lvl, TranslateCreatureType(creature)) end

    lvl, extra = orig:match("^Level%s*([%d?]+)%s*%(([^)]+)%)$")
    if lvl then
        local suffix = Trim(extra):lower()
        if suffix == "elite" then return "Poziom " .. lvl .. " (Elitarny)"
        elseif suffix == "boss" then return "Poziom " .. lvl .. " (Boss)"
        else return "Poziom " .. lvl .. " (" .. extra .. ")" end
    end

    local threatValue = orig:match("^(%d+)%% Threat$")
    if threatValue then return string.format("Zagrożenie %s%%", threatValue) end

    -- Bazy danych
    if NPCRenamerDB[orig] then return NPCRenamerDB[orig] end
    if NPCNames and NPCNames[orig] then return NPCNames[orig] end
    if ZoneNames and ZoneNames[orig] then return ZoneNames[orig] end

    -- Ochrona przed PL -> EN
    if NPCNames then
        for eng, pl in pairs(NPCNames) do if pl == orig then return nil end end
    end

    if not NPCRenamerMissing[orig] then NPCRenamerMissing[orig] = true end
    return nil
end

local function ApplyGenderTag(text, unit)
    if not text or not text:find("%$P") then return text end
    local sex = unit and UnitSex(unit) or 1
    return text:gsub("%$P%(([^;]+);([^)]+)%)", function(m, f) return (sex == 3) and f or m end)
end

---------------------------------------------------------------
-- Nameplates
---------------------------------------------------------------
if type(_G["CompactUnitFrame_UpdateName"]) == "function" then
    hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
        if not frame or frame:IsForbidden() or not frame.unit then return end
        if InCombatLockdown() then return end
        if UnitIsPlayer(frame.unit) then return end

        pcall(function()
            local unit = frame.unit
            local orig = UnitName(unit)
            local custom = GetCustomName(orig) or orig
            custom = ApplyGenderTag(custom, unit)
            local r, g, b = UnitSelectionColor(unit)

            if not frame.customTextFrame then
                frame.customTextFrame = CreateFrame("Frame", nil, frame)
                frame.customTextFrame:SetSize(400, 60)
                frame.customTextFrame:SetPoint("BOTTOM", frame.healthBar, "TOP", 0, 0)

                frame.newName = frame.customTextFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                -- Obniżone z 20 na 10, żeby nazwa była bliżej paska
                frame.newName:SetPoint("BOTTOM", frame.customTextFrame, "BOTTOM", 0, 10)

                frame.newRole = frame.customTextFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                frame.newRole:SetPoint("TOP", frame.newName, "BOTTOM", 0, 0) -- Rola tuż pod nazwą
            end

            if frame.name then frame.name:SetAlpha(0) end

            SafeSetText(frame.newName, custom)
            SafeApplyFont(frame.newName, FONT_SIZE_NAMEPLATE)
            frame.newName:SetTextColor(r or 1, g or 1, b or 1)
            frame.newName:SetShadowOffset(1, -1)

            frame.newRole:Hide()

            local roleText = nil
            for i = 2, 3 do
                local line = _G["GameTooltipTextLeft" .. i]
                local t = SafeGetText(line)
                if t and t ~= "" and not t:match("Poziom") and not t:match("Level") and not t:match("%%") and not t:match("PvP") then
                    roleText = GetCustomName(t) or t
                    break
                end
            end

            if roleText then
                roleText = ApplyGenderTag(roleText, unit)
                frame.newRole:SetText("<" .. roleText .. ">")
                SafeApplyFont(frame.newRole, FONT_SIZE_NAMEPLATE - 2)
                frame.newRole:SetTextColor(r or 0.8, g or 0.8, b or 0.8)
                frame.newRole:SetShadowOffset(1, -1)
                frame.newRole:Show()

                -- Offset dla widocznej roli (zmniejszony z 10 na 6)
                frame.customTextFrame:SetPoint("BOTTOM", frame.healthBar, "TOP", 0, 6)
            else
                -- Offset bez roli (zmniejszony z 4 na 1)
                frame.customTextFrame:SetPoint("BOTTOM", frame.healthBar, "TOP", 0, 1)
            end
        end)
    end)
end

---------------------------------------------------------------
-- Tooltip (Pełne filtrowanie i Retail API)
---------------------------------------------------------------
local function ProcessTooltip(self)
    if self:IsForbidden() then return end
    local name, unit = self:GetUnit()
    if not unit or UnitIsPlayer(unit) then return end

    local playerName = UnitName("player")
    local orig = UnitName(unit)
    local custom = GetCustomName(orig)

    if custom then
        local left1 = _G[self:GetName() .. "TextLeft1"]
        if left1 then
            custom = ApplyGenderTag(custom, unit)
            SafeSetText(left1, custom)
            SafeApplyFont(left1, FONT_SIZE_FRAME)
        end
    end

    local i = 2
    while true do
        local line = _G[self:GetName() .. "TextLeft" .. i]
        if not line then break end
        local text = SafeGetText(line)
        if not text or text == "" then break end

        local skip = false
        if text:match("^%s*%-") or (playerName and text:match("^" .. playerName)) then
            skip = true
        end

        -- Pomijanie tytułów questów po kolorze (R>0.8, G>0.4, B<0.1)
        if not skip then
            local r, g, b = line:GetTextColor()
            if r > 0.8 and g > 0.4 and b < 0.1 then skip = true end
        end

        if not skip then
            text = text:gsub("Alliance", "Przymierze"):gsub("Horde", "Horda")
            local trans = GetCustomName(text)
            if trans then
                trans = ApplyGenderTag(trans, unit)
                SafeSetText(line, trans)
                SafeApplyFont(line, FONT_SIZE_FRAME)
            end
        end
        i = i + 1
    end

    -- Szara linia oryginału
    if custom and orig and orig ~= custom then
        pcall(function()
            self:AddLine(" ")
            self:AddLine(orig, 0.5, 0.5, 0.5, true)
        end)
    end
end

if TooltipDataProcessor then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, ProcessTooltip)
end

---------------------------------------------------------------
-- Player Tooltip (Rasy i Klasy)
---------------------------------------------------------------
local function TranslatePlayerTooltip(self)
    if self:IsForbidden() then return end
    local _, unit = self:GetUnit()
    if not unit or not UnitIsPlayer(unit) then return end

    local raceTrans = {
        ["Human"] = "Człowiek", ["Dwarf"] = "Krasnolud", ["Night Elf"] = "Nocny Elf",
        ["Gnome"] = "Gnom", ["Draenei"] = "Draenei", ["Worgen"] = "Worgen",
        ["Orc"] = "Ork", ["Troll"] = "Troll", ["Tauren"] = "Tauren",
        ["Undead"] = "Nieumarły", ["Blood Elf"] = "Krwawy Elf", ["Goblin"] = "Goblin",
        ["Pandaren"] = "Pandaren", ["Nightborne"] = "Dziecię Nocy",
        ["Highmountain Tauren"] = "Tauren z Wysokiej Góry", ["Void Elf"] = "Elf Pustki",
        ["Lightforged Draenei"] = "Świetlisty Draenei", ["Dark Iron Dwarf"] = "Krasnolud Czarnorytny",
        ["Zandalari Troll"] = "Zandalari Troll", ["Kul Tiran"] = "Kul Tiranin",
        ["Mag'har Orc"] = "Mag'har Ork", ["Mechagnome"] = "Mechagnom",
        ["Dracthyr"] = "Dracthyr", ["Vulpera"] = "Vulpera", ["Earthen"] = "Ziemny"
    }
    local classTrans = {
        ["Warrior"] = "Wojownik", ["Paladin"] = "Paladyn", ["Hunter"] = "Łowca",
        ["Rogue"] = "Łotrzyk", ["Priest"] = "Kapłan", ["Death Knight"] = "Rycerz Śmierci",
        ["Shaman"] = "Szaman", ["Mage"] = "Mag", ["Warlock"] = "Czarnoksiężnik",
        ["Monk"] = "Mnich", ["Druid"] = "Druid", ["Demon Hunter"] = "Łowca Demonów",
        ["Evoker"] = "Przywoływacz"
    }

    for i = 1, self:NumLines() do
        local line = _G[self:GetName() .. "TextLeft" .. i]
        local text = SafeGetText(line)
        if text then
            local new = text:gsub("Level%s+(%d+)", "Poziom %1"):gsub("%(Player%)", "(Gracz)")
            for en, pl in pairs(raceTrans) do new = new:gsub(en, pl) end
            for en, pl in pairs(classTrans) do new = new:gsub(en, pl) end
            if new ~= text then SafeSetText(line, new) end
        end
    end
end

GameTooltip:HookScript("OnUpdate", TranslatePlayerTooltip)

---------------------------------------------------------------
-- Ramki Interfejsu (Gossip, Merchant, Quest)
---------------------------------------------------------------
local function UpdateRetailFrames()
    -- Retail używa .TitleContainer.TitleText w większości nowych okien
    local frames = {
        {f = GossipFrame, t = GossipFrame.TitleContainer and GossipFrame.TitleContainer.TitleText},
        {f = MerchantFrame, t = MerchantFrame.TitleContainer and MerchantFrame.TitleContainer.TitleText},
        {f = QuestFrame, t = QuestFrame.TitleContainer and QuestFrame.TitleContainer.TitleText},
        {f = ClassTrainerFrame, t = ClassTrainerFrame.TitleContainer and ClassTrainerFrame.TitleContainer.TitleText}
    }
    for _, cfg in ipairs(frames) do
        if cfg.f and cfg.f:IsShown() then
            local obj = cfg.t
            local txt = SafeGetText(obj)
            if txt then
                local custom = GetCustomName(txt)
                if custom then SafeSetText(obj, custom) SafeApplyFont(obj) end
            end
        end
    end
end

---------------------------------------------------------------
-- Hooki i Eventy
---------------------------------------------------------------
local function UpdateUnitFrame(self)
    if not self or not self.unit or self:IsForbidden() then return end
    if UnitIsPlayer(self.unit) then return end
    local custom = GetCustomName(UnitName(self.unit))
    if custom and self.name then
        SafeSetText(self.name, ApplyGenderTag(custom, self.unit))
        SafeApplyFont(self.name, FONT_SIZE_NAMEPLATE)
    end
end

if TargetFrame then hooksecurefunc(TargetFrame, "Update", UpdateUnitFrame) end
if FocusFrame then hooksecurefunc(FocusFrame, "Update", UpdateUnitFrame) end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GOSSIP_SHOW")
f:RegisterEvent("MERCHANT_SHOW")
f:RegisterEvent("QUEST_SHOW")
f:RegisterEvent("TRAINER_SHOW")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("PLAYER_FOCUS_CHANGED")

f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_TARGET_CHANGED" then UpdateUnitFrame(TargetFrame)
    elseif event == "PLAYER_FOCUS_CHANGED" then UpdateUnitFrame(FocusFrame)
    else C_Timer.After(0.05, UpdateRetailFrames) end
end)

---------------------------------------------------------------
-- Slash Commands (Kompletne)
---------------------------------------------------------------
SLASH_NPCNAME1 = "/npcname"
SlashCmdList["NPCNAME"] = function(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    if cmd == "set" then
        local t = UnitName("target")
        if t then NPCRenamerDB[t] = rest print("Ustawiono: "..t.." -> "..rest) end
    elseif cmd == "list" then
        for k, v in pairs(NPCRenamerDB) do print(k.." => "..v) end
    elseif cmd == "del" then
        NPCRenamerDB[rest] = nil print("Usunięto: "..rest)
    elseif cmd == "missing" then
        print("Brakujące NPC:")
        for n in pairs(NPCRenamerMissing) do print(" - "..n) end
    elseif cmd == "font" then
        FONT_PATH = rest
        print("Ustawiono czcionkę: "..rest)
    end
end

print("|cFF00FF00NPCRenamer:|r Załadowano pełną wersję Retail (TWW).")