-- cooline.lua
local cooline = CreateFrame('Button', nil, UIParent)
cooline:SetScript('OnEvent', function()
    this[event]()
end)
cooline:RegisterEvent('VARIABLES_LOADED')

local default_settings = {
    x = -50,
    y = -240,
    min_cooldown = 2.5,
    max_cooldown = 30,
    ignore_list = {},
    theme = {
        width = 300,
        height = 20,
        reverse = false,
        font = "Interface\\AddOns\\cooline\\assets\\Expressway.ttf",
        fallback_font = "Fonts\\FRIZQT__.TTF", -- Fallback to standard WoW font
        fontsize = 12,
        fontcolor = {1,1,1,1},
        bgcolor = {0,0,0,0.5}, 
        statusbar = [[Interface\TargetingFrame\UI-StatusBar]],
        iconoutset = 0,
        activealpha = 1,
        inactivealpha = 0.5,
    },
}

-- Initialize variables early to prevent nil access
local cooline_theme = default_settings.theme
local cooline_min_cooldown = default_settings.min_cooldown
local cooline_max_cooldown = default_settings.max_cooldown
local cooline_ignore_list = default_settings.ignore_list

local frame_pool = {}
local cooldowns = {}
local inCombat = false
local hasShownInCombat = false -- Tracks if we've shown the bar during current combat session
local slider_counter = 0 -- Counter for unique slider names
local check_counter = 0 -- Counter for unique check button names

function cooline.hyperlink_name(hyperlink)
    local _, _, name = strfind(hyperlink, '|Hitem:%d+:%d+:%d+:%d+|h[[]([^]]+)[]]|h')
    return name
end

function cooline.detect_cooldowns()
    function start_cooldown(name, texture, start_time, duration)
        if duration > cooline_max_cooldown or duration < cooline_min_cooldown then
            return -- Skip cooldowns outside min/max range
        end

        for _, ignored_name in cooline_ignore_list do
            if strupper(name) == strupper(ignored_name) then
                return
            end
        end

        local end_time = start_time + duration
        
        for _, cooldown in pairs(cooldowns) do
            if cooldown.end_time == end_time then
                return
            end
        end

        cooldowns[name] = cooldowns[name] or tremove(frame_pool) or cooline.cooldown_frame()
        local frame = cooldowns[name]
        frame:SetWidth(cooline.icon_size)
        frame:SetHeight(cooline.icon_size)
        frame.icon:SetTexture(texture)
        frame:SetBackdropColor(0, 0, 0, 1) -- Black border for all icons
        frame:SetAlpha((end_time - GetTime() > cooline_max_cooldown) and 0.6 or 1)
        frame.end_time = end_time
        frame:Show()
    end

    -- Spell cooldowns
    local _, _, offset, spell_count = GetSpellTabInfo(GetNumSpellTabs())
    local total_spells = offset + spell_count
    for id = 1, total_spells do
        local start_time, duration, enabled = GetSpellCooldown(id, BOOKTYPE_SPELL)
        local name = GetSpellName(id, BOOKTYPE_SPELL)
        if enabled == 1 and duration > cooline_min_cooldown then
            start_cooldown(
                name,
                GetSpellTexture(id, BOOKTYPE_SPELL),
                start_time,
                duration
            )
        elseif duration == 0 then
            cooline.clear_cooldown(name)
        end
    end

    -- Bag item cooldowns
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local start_time, duration, enabled = GetContainerItemCooldown(bag, slot)
            local texture = GetContainerItemInfo(bag, slot)
            local link = GetContainerItemLink(bag, slot)
            if link then
                local name = cooline.hyperlink_name(link)
                if enabled == 1 and duration > cooline_min_cooldown then
                    start_cooldown(
                        name,
                        texture,
                        start_time,
                        duration
                    )
                elseif duration == 0 then
                    cooline.clear_cooldown(name)
                end
            end
        end
    end

    -- Inventory item cooldowns (e.g., trinkets, equipped items)
    for slot = 1, 19 do
        local start_time, duration, enabled = GetInventoryItemCooldown("player", slot)
        local texture = GetInventoryItemTexture("player", slot)
        local link = GetInventoryItemLink("player", slot)
        if link then
            local name = cooline.hyperlink_name(link)
            if enabled == 1 and duration > cooline_min_cooldown then
                start_cooldown(
                    name,
                    texture,
                    start_time,
                    duration
                )
            elseif duration == 0 then
                cooline.clear_cooldown(name)
            end
        end
    end

    cooline.on_update(true)
end

function cooline.PLAYER_REGEN_DISABLED()
    inCombat = true
    hasShownInCombat = false -- Reset at start of combat
    cooline.on_update(true)
end

function cooline.PLAYER_REGEN_ENABLED()
    inCombat = false
    hasShownInCombat = false -- Reset at end of combat
    cooline.on_update(true)
end

function cooline.cooldown_frame()
    local frame = CreateFrame('Frame', nil, cooline)
    frame:SetBackdrop({ bgFile=[[Interface\\AddOns\\cooline\\assets\\backdrop.tga]] })
    frame.icon = frame:CreateTexture(nil, 'ARTWORK')
    frame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    frame.icon:SetPoint('TOPLEFT', 1, -1)
    frame.icon:SetPoint('BOTTOMRIGHT', -1, 1)
    return frame
end

local function place_H(this, offset, just)
    this:SetPoint(just or 'CENTER', cooline, 'LEFT', offset, 0)
end
local function place_HR(this, offset, just)
    this:SetPoint(just or 'CENTER', cooline, 'LEFT', cooline_theme.width - offset, 0)
end

function cooline.clear_cooldown(name)
    if cooldowns[name] then
        cooldowns[name]:Hide()
        tinsert(frame_pool, cooldowns[name])
        cooldowns[name] = nil
    end
end

local relevel, throt = false, 0

function getKeysSortedByValue(tbl, sortFunction)
    local keys = {}
    for key in pairs(tbl) do
        table.insert(keys, key)
    end

    table.sort(keys, function(a, b)
        return sortFunction(tbl[a], tbl[b])
    end)

    return keys
end

function cooline.update_cooldown(name, frame, position, tthrot, relevel)
    throt = min(throt, tthrot)
    
    if frame.end_time - GetTime() < 3 then
        local sorted = getKeysSortedByValue(cooldowns, function(a, b) return a.end_time > b.end_time end)
        for i, k in ipairs(sorted) do
            if name == k then
                frame:SetFrameLevel(i+2)
            end
        end
    else
        if relevel then
            frame:SetFrameLevel(random(1,5) + 2)
        end
    end
    
    cooline.place(frame, position)
end

do
    local last_update, last_relevel = GetTime(), GetTime()
    
    function cooline.on_update(level)
    if not cooline_theme then return end -- Skip if theme not initialized
    if GetTime() - last_update < throt and not force then return end
    last_update = GetTime()

    relevel = false
    if GetTime() - last_relevel > 0.4 then
        relevel, last_relevel = true, GetTime()
    end

    local hasActiveCooldowns = false
    throt = 1.5
    
    -- Process all cooldowns
    for name, frame in pairs(cooldowns) do
        local time_left = frame.end_time - GetTime()

        if time_left > 0 then
            hasActiveCooldowns = true
            frame:Show()
        else
            frame:Hide()
            if time_left < -1 then
                throt = min(throt, 0.2)
                cooline.clear_cooldown(name)
            elseif time_left < 0 then
                cooline.update_cooldown(name, frame, 0, 0, relevel)
                frame:SetAlpha(1 + time_left)
            end
        end

        -- Position updates for active cooldowns
        if time_left > 0 then
            if time_left < 0.3 then
                local size = cooline.icon_size * (0.5 - time_left) * 3
                frame:SetWidth(size)
                frame:SetHeight(size)
                cooline.update_cooldown(name, frame, cooline.section * time_left, 0, relevel)
            elseif time_left < 1 then
                cooline.update_cooldown(name, frame, cooline.section * time_left, 0, relevel)
            elseif time_left < 3 then
                cooline.update_cooldown(name, frame, cooline.section * (time_left + 1) * 0.5, 0.02, relevel)
            elseif time_left < 10 then
                cooline.update_cooldown(name, frame, cooline.section * (time_left + 11) * 0.14286, time_left > 4 and 0.05 or 0.02, relevel)
            elseif time_left < 30 then
                cooline.update_cooldown(name, frame, cooline.section * (time_left + 50) * 0.05, 0.06, relevel)
            elseif time_left < 120 then
                cooline.update_cooldown(name, frame, cooline.section * (time_left + 330) * 0.011111, 0.18, relevel)  -- 4 + (time_left - 30) / 90
            elseif time_left < 360 then
                cooline.update_cooldown(name, frame, cooline.section * (time_left + 1080) * 0.0041667, 1.2, relevel)  -- 5 + (time_left - 120) / 240
                frame:SetAlpha(cooline_theme.activealpha)
            end
        end
    end
    
    -- Update hasShownInCombat if there are active cooldowns
    if hasActiveCooldowns then
        hasShownInCombat = true
    end

    -- Show bar only in combat with active cooldowns or if it has been shown
    local shouldShow = inCombat and (hasActiveCooldowns or hasShownInCombat)
    cooline:SetAlpha(shouldShow and cooline_theme.activealpha or cooline_theme.inactivealpha)
end
end

function cooline.label(text, offset, just)
    local fs = cooline.overlay:CreateFontString(nil, 'OVERLAY')
    -- Try custom font, fall back to default if it fails
    local font = cooline_theme.font
    local success = fs:SetFont(font, cooline_theme.fontsize)
    if not success then
        fs:SetFont(cooline_theme.fallback_font, cooline_theme.fontsize)
    end
    fs:SetTextColor(unpack(cooline_theme.fontcolor))
    fs:SetText(text)
    fs:SetWidth(cooline_theme.fontsize * 3)
    fs:SetHeight(cooline_theme.fontsize + 2)
    fs:SetShadowColor(unpack(cooline_theme.bgcolor))
    fs:SetShadowOffset(1, -1)
    if just then
        fs:ClearAllPoints()
        if cooline_theme.reverse then
            just = (just == 'LEFT' and 'RIGHT') or 'LEFT'
            offset = offset + ((just == 'LEFT' and 1) or -1)
            fs:SetJustifyH(just)
        else
            offset = offset + ((just == 'LEFT' and 1) or -1)
            fs:SetJustifyH(just)
        end
    else
        fs:SetJustifyH('CENTER')
    end
    cooline.place(fs, offset, just)
    return fs
end

function cooline:InitUI()
    self:SetWidth(cooline_theme.width)
    self:SetHeight(cooline_theme.height)
    -- Validate position to prevent off-screen
    local x = cooline_settings.x or default_settings.x
    local y = cooline_settings.y or default_settings.y
    if type(x) ~= "number" or type(y) ~= "number" then
        x, y = default_settings.x, default_settings.y
        cooline_settings.x, cooline_settings.y = x, y
    end
    self:SetPoint('CENTER', x, y)
    self:SetClampedToScreen(true)
    
    cooline.bg:SetTexture(cooline_theme.statusbar)
	cooline.bg:SetVertexColor(unpack(cooline_theme.bgcolor))
    cooline.bg:SetTexCoord(0, 1, 0, 1)

    local sectionCount = 4
    if cooline_settings.max_cooldown >= 120 then
        sectionCount = sectionCount + 1
    end
    
    if cooline_settings.max_cooldown >= 360 then
        sectionCount = sectionCount + 1
    end   
    
    self.section = cooline_theme.width / sectionCount
    self.icon_size = cooline_theme.height + cooline_theme.iconoutset * 2
    self.place = cooline_theme.reverse and place_HR or place_H

    -- Recreate labels to apply new settings
    if self.tick0 then self.tick0:Hide() end
    if self.tick1 then self.tick1:Hide() end
    if self.tick3 then self.tick3:Hide() end
    if self.tick10 then self.tick10:Hide() end
    if self.tick30 then self.tick30:Hide() end
    if self.tick120 then self.tick120:Hide() end
    if self.tick300 then self.tick300:Hide() end

    self.tick0 = self.label('0', 0, 'LEFT')
    self.tick1 = self.label('1', self.section)
    self.tick3 = self.label('3', self.section * 2)
    self.tick10 = self.label('10', self.section * 3)
    self.tick30 = self.label('30', self.section * 4)
    
    if cooline_settings.max_cooldown >= 120 then
        self.tick120 = cooline.label('2m', cooline.section * 5)
    end
    
    if cooline_settings.max_cooldown >= 360 then
        self.tick300 = cooline.label('6m', cooline.section * 6, 'RIGHT')
    end    
    
    -- Force update to apply changes
    self.detect_cooldowns()
end

local function CreateConfig()
    local config = CreateFrame("Frame", "CoolineConfig", UIParent)
    if not config then
        return
    end

    config:SetWidth(400)
    config:SetHeight(600)
    config:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    config:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    config:SetMovable(true)
    config:EnableMouse(true)
    config:RegisterForDrag("LeftButton")
    config:SetScript("OnDragStart", function() this:StartMoving() end)
    config:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

    local title = config:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Cooline Configuration")

    local close = CreateFrame("Button", nil, config, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", config, "TOPRIGHT")

    local yOffset = -50

    local function AddSlider(name, minVal, maxVal, step, getFunc, setFunc)
        slider_counter = slider_counter + 1
        local slider = CreateFrame("Slider", "CoolineConfigSlider_" .. slider_counter, config, "OptionsSliderTemplate")
        if not slider then
            return
        end
        slider:SetWidth(200)
        slider:SetPoint("TOP", 0, yOffset)
        slider:SetMinMaxValues(minVal, maxVal)
        slider:SetValueStep(step)
        slider:SetValue(getFunc())
        local sliderName = slider:GetName()
        getglobal(sliderName .. "Text"):SetText(name)
        getglobal(sliderName .. "Low"):SetText(tostring(minVal))
        getglobal(sliderName .. "High"):SetText(tostring(maxVal))

        -- Add value display
        local valueText = config:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        valueText:SetPoint("LEFT", slider, "RIGHT", 5, 0)
        local allowsDecimal = name == "Min Cooldown (seconds)" or name == "Active Alpha" or name == "Inactive Alpha"
        valueText:SetText(string.format(allowsDecimal and "%.1f" or "%d", getFunc()))

        -- Add input box
        local inputBox = CreateFrame("EditBox", "CoolineConfigSliderInput_" .. slider_counter, config, "InputBoxTemplate")
        inputBox:SetPoint("LEFT", valueText, "RIGHT", 5, 0)
        inputBox:SetWidth(50)
        inputBox:SetHeight(20)
        inputBox:SetAutoFocus(false)
        inputBox:SetText(string.format(allowsDecimal and "%.1f" or "%d", getFunc()))

        -- Determine if negative values are allowed
        local allowsNegative = name == "X Position" or name == "Y Position" or name == "Icon Size"

        -- Sync slider and input box
        slider:SetScript("OnValueChanged", function()
            local value = this:GetValue()
            setFunc(value)
            valueText:SetText(string.format(allowsDecimal and "%.1f" or "%d", value))
            inputBox:SetText(string.format(allowsDecimal and "%.1f" or "%d", value))
            cooline:InitUI()
        end)

        inputBox:SetScript("OnEnterPressed", function()
            local text = this:GetText()
            local value = tonumber(text)
            if value then
                -- Clamp value to min/max
                value = math.max(minVal, math.min(maxVal, value))
                -- Round to one decimal place for decimal sliders
                if allowsDecimal then
                    value = math.floor(value * 10 + 0.5) / 10
                else
                    value = math.floor(value + 0.5) -- Round to nearest integer
                end
                -- Ensure non-negative for sliders that don't allow negatives
                if not allowsNegative and value < 0 then
                    value = minVal
                end
                slider:SetValue(value)
                setFunc(value)
                valueText:SetText(string.format(allowsDecimal and "%.1f" or "%d", value))
                this:SetText(string.format(allowsDecimal and "%.1f" or "%d", value))
                cooline:InitUI()
            else
                -- Invalid input, revert to current value
                local currentValue = getFunc()
                this:SetText(string.format(allowsDecimal and "%.1f" or "%d", currentValue))
            end
            this:ClearFocus()
        end)

        inputBox:SetScript("OnEscapePressed", function()
            local currentValue = getFunc()
            this:SetText(string.format(allowsDecimal and "%.1f" or "%d", currentValue))
            this:ClearFocus()
        end)

        yOffset = yOffset - 35
        return slider
    end

    local function AddCheck(name, getFunc, setFunc)
        check_counter = check_counter + 1
        local check = CreateFrame("CheckButton", "CoolineConfigCheck_" .. check_counter, config, "UICheckButtonTemplate")
        if not check then
            return
        end
        check:SetPoint("TOPLEFT", 20, yOffset)
        local checkName = check:GetName()
        getglobal(checkName .. "Text"):SetText(name)
        check:SetChecked(getFunc())
        check:SetScript("OnClick", function()
            setFunc(this:GetChecked())
            cooline:InitUI()
        end)
        yOffset = yOffset - 30
        return check
    end

    AddSlider("Cooldown Bar Width", 100, 500, 1, function() return cooline_theme.width end, function(v) cooline_theme.width = v; cooline_settings.theme.width = v end)
    AddSlider("Cooldown Bar Height", 10, 100, 1, function() return cooline_theme.height end, function(v) cooline_theme.height = v; cooline_settings.theme.height = v end)
    AddSlider("X Position", -800, 800, 1, function() return cooline_settings.x end, function(v) cooline_settings.x = v; cooline:SetPoint("CENTER", v, cooline_settings.y) end)
    AddSlider("Y Position", -600, 600, 1, function() return cooline_settings.y end, function(v) cooline_settings.y = v; cooline:SetPoint("CENTER", cooline_settings.x, v) end)
    AddSlider("Font Size", 8, 20, 1, function() return cooline_theme.fontsize end, function(v) cooline_theme.fontsize = v; cooline_settings.theme.fontsize = v end)
    AddSlider("Icon Size", -5, 5, 1, function() return cooline_theme.iconoutset end, function(v) cooline_theme.iconoutset = v; cooline_settings.theme.iconoutset = v end)
    AddSlider("Min Cooldown (seconds)", 0, 10, 0.5, function() return cooline_settings.min_cooldown end, function(v) cooline_settings.min_cooldown = v; cooline_min_cooldown = v end)
    AddSlider("Max Cooldown (seconds)", 10, 600, 1, function() return cooline_settings.max_cooldown end, function(v) cooline_settings.max_cooldown = v; cooline_max_cooldown = v end)
    AddSlider("Active Alpha", 0, 1, 0.05, function() return cooline_theme.activealpha end, function(v) cooline_theme.activealpha = v; cooline_settings.theme.activealpha = v end)
    AddSlider("Inactive Alpha", 0, 1, 0.05, function() return cooline_theme.inactivealpha end, function(v) cooline_theme.inactivealpha = v; cooline_settings.theme.inactivealpha = v end)

    AddCheck("Reverse", function() return cooline_theme.reverse end, function(v) cooline_theme.reverse = v; cooline_settings.theme.reverse = v end)

    local ignoreLabel = config:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ignoreLabel:SetPoint("TOPLEFT", 20, yOffset)
    ignoreLabel:SetText("Ignore/Unignore Spells (comma separated)")

    yOffset = yOffset - 20

    local ignoreEdit = CreateFrame("EditBox", nil, config, "InputBoxTemplate")
    ignoreEdit:SetPoint("TOPLEFT", 20, yOffset)
    ignoreEdit:SetWidth(300)
    ignoreEdit:SetHeight(25)
    ignoreEdit:SetAutoFocus(false)
    ignoreEdit:SetScript("OnShow", function()
        this:SetText("")
    end)

    yOffset = yOffset - 30

    local ignoreButton = CreateFrame("Button", nil, config, "UIPanelButtonTemplate")
    ignoreButton:SetPoint("TOPLEFT", 20, yOffset)
    ignoreButton:SetWidth(60)
    ignoreButton:SetHeight(25)
    ignoreButton:SetText("Ignore")
    ignoreButton:SetScript("OnClick", function()
        local text = ignoreEdit:GetText()
        local new_ignores = {}
        for name in string.gmatch(text, "[^,]+") do
            name = string.gsub(name, "^%s*(.-)%s*$", "%1")
            if name ~= "" then
                table.insert(new_ignores, name)
            end
        end
        for _, new_ignore in ipairs(new_ignores) do
            local found = false
            for _, ignored_name in ipairs(cooline_ignore_list) do
                if strupper(new_ignore) == strupper(ignored_name) then
                    found = true
                    break
                end
            end
            if not found then
                table.insert(cooline_ignore_list, new_ignore)
            end
        end
        cooline_settings.ignore_list = cooline_ignore_list
        ignoreEdit:SetText("")
        config.currentIgnoredText:SetText(table.concat(cooline_ignore_list, ", "))
        cooline.detect_cooldowns()
    end)

    local unignoreButton = CreateFrame("Button", nil, config, "UIPanelButtonTemplate")
    unignoreButton:SetPoint("LEFT", ignoreButton, "RIGHT", 5, 0)
    unignoreButton:SetWidth(60)
    unignoreButton:SetHeight(25)
    unignoreButton:SetText("Unignore")
    unignoreButton:SetScript("OnClick", function()
        local text = ignoreEdit:GetText()
        local to_remove = {}
        for name in string.gmatch(text, "[^,]+") do
            name = string.gsub(name, "^%s*(.-)%s*$", "%1")
            if name ~= "" then
                table.insert(to_remove, name)
            end
        end
        local new_list = {}
        for _, ignored_name in ipairs(cooline_ignore_list) do
            local remove = false
            for _, remove_name in ipairs(to_remove) do
                if strupper(ignored_name) == strupper(remove_name) then
                    remove = true
                    break
                end
            end
            if not remove then
                table.insert(new_list, ignored_name)
            end
        end
        cooline_ignore_list = new_list
        cooline_settings.ignore_list = cooline_ignore_list
        ignoreEdit:SetText("")
        config.currentIgnoredText:SetText(table.concat(cooline_ignore_list, ", "))
        cooline.detect_cooldowns()
    end)

    yOffset = yOffset - 30

    local currentIgnoredLabel = config:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    currentIgnoredLabel:SetPoint("TOPLEFT", 20, yOffset)
    currentIgnoredLabel:SetText("Current Ignored:")

    yOffset = yOffset - 20

    local currentIgnoredText = config:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    currentIgnoredText:SetPoint("TOPLEFT", 20, yOffset)
    currentIgnoredText:SetWidth(300)
    currentIgnoredText:SetJustifyH("LEFT")
    currentIgnoredText:SetText(table.concat(cooline_ignore_list, ", "))
    config.currentIgnoredText = currentIgnoredText

    config:SetScript("OnShow", function()
        config.currentIgnoredText:SetText(table.concat(cooline_ignore_list, ", "))
    end)

    config:Hide()
end

function cooline.VARIABLES_LOADED()
    -- Initialize cooline_settings with defaults if nil or incomplete
    if not cooline_settings then
        cooline_settings = {}
        for k, v in pairs(default_settings) do
            if type(v) == "table" then
                cooline_settings[k] = {}
                for tk, tv in pairs(v) do
                    -- Skip font to prevent it from being saved
                    if k == "theme" and tk == "font" then
                        cooline_settings.theme.font = default_settings.theme.font
                    elseif k == "theme" and tk == "fallback_font" then
                        cooline_settings.theme.fallback_font = default_settings.theme.fallback_font
                    else
                        cooline_settings[k][tk] = tv
                    end
                end
            else
                cooline_settings[k] = v
            end
        end
    else
        -- Ensure all top-level settings exist
        for k, v in pairs(default_settings) do
            if cooline_settings[k] == nil then
                if type(v) == "table" then
                    cooline_settings[k] = {}
                    for tk, tv in pairs(v) do
                        -- Skip font to prevent it from being saved
                        if k == "theme" and tk == "font" then
                            cooline_settings.theme.font = default_settings.theme.font
                        elseif k == "theme" and tk == "fallback_font" then
                            cooline_settings.theme.fallback_font = default_settings.theme.fallback_font
                        else
                            cooline_settings[k][tk] = tv
                        end
                    end
                else
                    cooline_settings[k] = v
                end
            elseif k == "theme" then
                -- Ensure all theme settings exist, except font
                for tk, tv in pairs(default_settings.theme) do
                    if tk ~= "font" and tk ~= "fallback_font" and cooline_settings.theme[tk] == nil then
                        cooline_settings.theme[tk] = tv
                    end
                end
                -- Always set font from default_settings
                cooline_theme.font = default_settings.theme.font
                cooline_theme.fallback_font = default_settings.theme.fallback_font
            end
        end
    end

    if not cooline_settings.minimapPos then
        cooline_settings.minimapPos = 225
    end

    cooline_theme = cooline_settings.theme
    cooline_theme.font = default_settings.theme.font -- Ensure font is always from default_settings
    cooline_theme.fallback_font = default_settings.theme.fallback_font -- Ensure fallback_font is always from default_settings
    cooline_min_cooldown = cooline_settings.min_cooldown
    cooline_max_cooldown = cooline_settings.max_cooldown
    cooline_ignore_list = cooline_settings.ignore_list

    cooline:SetClampedToScreen(true)
    cooline:SetMovable(true)
    cooline:RegisterForDrag('LeftButton')
    
    function cooline:on_drag_stop()
        this:StopMovingOrSizing()
        local x, y = this:GetCenter()
        local ux, uy = UIParent:GetCenter()
        cooline_settings.x, cooline_settings.y = floor(x - ux + 0.5), floor(y - uy + 0.5)
        this.dragging = false
    end
    
    cooline:SetScript('OnDragStart', function()
        this.dragging = true
        this:StartMoving()
    end)
    
    cooline:SetScript('OnDragStop', function()
        this:on_drag_stop()
    end)
    
    cooline:SetScript('OnUpdate', function()
        if not IsAltKeyDown() and this.dragging then
            this:on_drag_stop()
        end
        cooline.on_update()
    end)

    cooline.bg = cooline:CreateTexture(nil, 'ARTWORK')
    cooline.bg:SetAllPoints(cooline)

    cooline.overlay = CreateFrame('Frame', nil, cooline)
    cooline.overlay:SetFrameLevel(24)

    cooline:InitUI()

    cooline:RegisterEvent('SPELL_UPDATE_COOLDOWN')
    cooline:RegisterEvent('BAG_UPDATE_COOLDOWN')
    cooline:RegisterEvent('PLAYER_REGEN_DISABLED')
    cooline:RegisterEvent('PLAYER_REGEN_ENABLED')
    
    cooline.detect_cooldowns()

    CreateConfig()

    -- Create minimap icon
    local minimapButton = CreateFrame("Button", "CoolineMinimapButton", Minimap)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetWidth(33)
    minimapButton:SetHeight(33)
    minimapButton:SetFrameLevel(8)
    minimapButton:EnableMouse(true)
    minimapButton:RegisterForDrag("LeftButton")

    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

    local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
    icon:SetWidth(18)
    icon:SetHeight(18)
    icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
    icon:SetPoint("CENTER", 0, 0)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

    -- Add border texture
    local border = minimapButton:CreateTexture(nil, "BORDER")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("CENTER", 11, -12)
    border:SetWidth(54)
    border:SetHeight(54)

    local function UpdateMinimapPosition()
        local angle = math.rad(cooline_settings.minimapPos)
        local x = 80 * math.cos(angle)
        local y = 80 * math.sin(angle)
        minimapButton:ClearAllPoints()
        minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    UpdateMinimapPosition()

    minimapButton:SetScript("OnDragStart", function()
        this:StartMoving()
    end)

    minimapButton:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        local mx, my = Minimap:GetCenter()
        local bx, by = this:GetCenter()
        local dx = bx - mx
        local dy = by - my
        cooline_settings.minimapPos = math.deg(math.atan2(dy, dx))
        UpdateMinimapPosition()
    end)

    minimapButton:SetScript("OnClick", function()
        if CoolineConfig:IsShown() then
            CoolineConfig:Hide()
        else
            CoolineConfig:Show()
        end
    end)

    minimapButton:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:SetText("Cooline")
        GameTooltip:AddLine("Click to toggle configuration", 1, 1, 1)
        GameTooltip:Show()
    end)

    minimapButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

SLASH_COOLINE1 = "/cooline"
SlashCmdList["COOLINE"] = function(msg)
    if msg == "config" then
        if CoolineConfig and CoolineConfig:IsShown() then
            CoolineConfig:Hide()
        elseif CoolineConfig then
            CoolineConfig:Show()
        end
    elseif msg == "reset" then
        cooline_settings.x = default_settings.x
        cooline_settings.y = default_settings.y
        cooline_settings.min_cooldown = default_settings.min_cooldown
        cooline_settings.max_cooldown = default_settings.max_cooldown
        cooline_min_cooldown = default_settings.min_cooldown
        cooline_max_cooldown = default_settings.max_cooldown
        cooline:ClearAllPoints()
        cooline:SetPoint("CENTER", cooline_settings.x, cooline_settings.y)
        cooline:InitUI()
    end
end

function cooline.BAG_UPDATE_COOLDOWN()
    cooline.detect_cooldowns()
end

function cooline.SPELL_UPDATE_COOLDOWN()
    cooline.detect_cooldowns()
end