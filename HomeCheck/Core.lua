HomeCheck = CreateFrame("Frame")

HomeCheck.LibGroupTalents = LibStub("LibGroupTalents-1.0")
HomeCheck.LibSharedMedia = LibStub("LibSharedMedia-3.0")
HomeCheck.LibRangeCheck = LibStub("LibRangeCheck-2.0")

LibStub("AceTimer-3.0"):Embed(HomeCheck)
LibStub("AceComm-3.0"):Embed(HomeCheck)
LibStub("AceSerializer-3.0"):Embed(HomeCheck)

HomeCheck.groups = {}
HomeCheck.localizedSpellNames = {}
HomeCheck.deadUnits = {}
HomeCheck.RebirthTargets = {}
HomeCheck.db_ver = 4

HomeCheck.comms = {
    oRA = "oRA",
    oRA3 = "oRA3",
    BLT = "BLT Raid Cooldowns",
    CTRA = "CTRA",
    RCD2 = "RaidCooldowns",
    FRCD3 = "FatCooldowns",
    FRCD3S = "FatCooldowns (single report)",
    HomeCheck = "HomeCheck",
}

local playerInRaid = UnitInRaid("player")

local updateRaidRosterCooldown = 2
local updateRaidRosterTimestamp
local updateRaidRosterScheduleTimer

local ReadinessTimestamp = {}

local childSpells = {}

local groups = 10

local date, floor, GetTime, pairs, select, string, strsplit, table, time, tonumber, tostring, type, unpack = date, floor, GetTime, pairs, select, {
    find = string.find,
    gmatch = string.gmatch
}, strsplit, {
    insert = table.insert,
    remove = table.remove,
    wipe = table.wipe
}, time, tonumber, tostring, type, unpack

HomeCheck:RegisterEvent("ADDON_LOADED")

function HomeCheck:LibGroupTalents_Update(...)
    local unit = select(3, ...)
    local playerName = UnitName(unit)
    
    if playerName then
        self:refreshPlayerCooldowns(playerName)

        for i = 1, #self.groups do
            for j = 1, #self.groups[i].CooldownFrames do
                local frame = self.groups[i].CooldownFrames[j]


                if frame.playerName == playerName and frame.CDLeft and frame.CDLeft > 0 then

                else

                    if frame.playerName == playerName then
                        local correctMaxCD = self:getSpellCooldown(frame)
                        if frame.CD ~= correctMaxCD then
                            frame.CD = correctMaxCD
                        end
                    end
                end
            end
        end
    end
    
    self:repositionFrames()
end


function HomeCheck:LibGroupTalents_RoleChange(...)
    self:LibGroupTalents_Update(...)
end

HomeCheck:SetScript("OnEvent", function(self, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, combatEvent, _, playerName, _, _, targetName, _, spellID, spellName = ...
        if not UnitInRaid(playerName) and not UnitInParty(playerName) then
            return
        end


        if combatEvent == "SPELL_CAST_SUCCESS" and spellID == 48788 then


            if GetSpellInfo("Verbessertes Handauflegung") or GetSpellInfo("Improved Lay on Hands") then
                self.LoHHasNoBuff = false
            else
                self.LoHHasNoBuff = true 
            end
            

            self:setCooldown(spellID, playerName, true, targetName)


        elseif combatEvent == "SPELL_CAST_SUCCESS" or combatEvent == "SPELL_RESURRECT" or combatEvent == "SPELL_AURA_APPLIED" then
            if not self.spells[spellID] then
                spellID = self.localizedSpellNames[spellName]
            end

            if combatEvent == "SPELL_AURA_APPLIED" then
                targetName = nil
                if spellID == 64843 or spellID == 64901 or spellID == 48447 then
                    if self:getCDLeft(playerName, spellID) > 10 then
                        return
                    end
                end
            end

            self:setCooldown(spellID, playerName, true, targetName)
        elseif combatEvent == "SPELL_HEAL" and spellID == 48153 then
            self:GSProc(targetName)
        elseif combatEvent == "UNIT_DIED" then
            self.deadUnits[playerName] = true
            self:sortFrames() 
        elseif combatEvent == "SPELL_RESURRECT" then
            self:sortFrames()
        end

    -- UNIT_SPELLCAST events are used to detect double Rebirth only
    elseif event == "UNIT_SPELLCAST_SENT"
            or event == "UNIT_SPELLCAST_FAILED"
            or event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, spellName, _, targetName = ...
        local spellID = self.localizedSpellNames[spellName]
        if spellID == 48477 then
            self:Rebirth(event, (UnitName(unit)), targetName)
        end
    elseif event == "RAID_ROSTER_UPDATE" then
        local instant
        if playerInRaid ~= UnitInRaid("player") then
            if playerInRaid then
                self:RegisterEvent("PARTY_MEMBERS_CHANGED")
            else
                self:UnregisterEvent("PARTY_MEMBERS_CHANGED")
                instant = true
            end
            playerInRaid = UnitInRaid("player")
        end
        if playerInRaid then
            self:updateRaidRoster(instant)
        else
            self:updateFramesVisibility()
        end
    elseif event == "PARTY_MEMBERS_CHANGED" then
        self:updateRaidRoster()
        self:updateFramesVisibility()
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:cacheLocalizedSpellNames()
        self:ScheduleTimer(function()
            self:updateRaidCooldowns()
        end, 0.2)
        self:ScheduleTimer(function()
            self:updateRaidCooldowns()
        end, 10)
        self:ScheduleTimer(function()
            self:updateRaidCooldowns()
        end, 30)

        -- Initialize test mode if it was enabled
        if self.db.global.testMode then
            self:setTestMode(true)
        end
    elseif event == "ADDON_LOADED" then
        if (...) ~= "HomeCheck" then
            return
        end
        self.db = LibStub("AceDB-3.0"):New("HomeCheck_DB", self.defaults, true)

        self:upgradeDB()

        for playerName, spells in pairs(self.db.global.CDs) do
            for spellID, cd in pairs(spells) do
                if not cd.timestamp or cd.timestamp < time() then
                    table.wipe(self.db.global.CDs[playerName][spellID])
                end
            end
        end

        for childSpellID, childSpellConfig in pairs(self.spells) do
            if childSpellConfig.parent then
                childSpells[childSpellConfig.parent] = childSpellID
            end
        end

        for i = 1, groups do
            self:getGroup(i)
        end

        self.db.RegisterCallback(self, "OnProfileChanged", "loadProfile")
        self.db.RegisterCallback(self, "OnProfileCopied", "loadProfile")
        self.db.RegisterCallback(self, "OnProfileReset", "loadProfile")

        self:OptionsPanel()
        SLASH_HOMECHECKRESET1 = "/hcreset"
        SLASH_HOMECHECKRESET2 = "/homecheck reset"
        SlashCmdList["HOMECHECKRESET"] = function()
            HomeCheck:ResetAllCooldowns()
        end
        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        self:RegisterEvent("UNIT_SPELLCAST_SENT")
        self:RegisterEvent("UNIT_SPELLCAST_FAILED")
        self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        self:RegisterEvent("RAID_ROSTER_UPDATE")
        if not playerInRaid then
            self:RegisterEvent("PARTY_MEMBERS_CHANGED")
        end
        self:RegisterEvent("PLAYER_ENTERING_WORLD")

        self.LibGroupTalents.RegisterCallback(self, "LibGroupTalents_Update")
        self.LibGroupTalents.RegisterCallback(self, "LibGroupTalents_RoleChange")

        for k, _ in pairs(self.comms) do
            if self.db.global.comms[k] then
                self:RegisterComm(k)
            end
        end

        self:ScheduleRepeatingTimer(function()

            if not self.db.global.testMode and self.units then
                for playerName, _ in pairs(self.units) do
                    if UnitInRaid(playerName) or UnitInParty(playerName) then
                        if CanInspect(playerName) and CheckInteractDistance(playerName, 1) then
                            local trinket1 = GetInventoryItemID(playerName, 13)
                            local trinket2 = GetInventoryItemID(playerName, 14)
                            local refresh = false

                            if trinket1 or trinket2 then
                                if self:getUnit(playerName).trinket1 ~= trinket1 then
                                    self:getUnit(playerName).trinket1 = trinket1
                                    refresh = true
                                end
                                if self:getUnit(playerName).trinket2 ~= trinket2 then
                                    self:getUnit(playerName).trinket2 = trinket2
                                    refresh = true
                                end
                                if refresh then
                                    self:refreshPlayerCooldowns(playerName)
                                end
                            end
                        end
                    end
                end
            end

            local originalSort = self.sortFrames
            self.sortFrames = function() end 
           
             for i = 1, #self.groups do
                for j = 1, #self.groups[i].CooldownFrames do
                    self:setTimerColor(self.groups[i].CooldownFrames[j])
                    self:updateRange(self.groups[i].CooldownFrames[j])
                end
            end
            
            self.sortFrames = originalSort
            
            for i = 1, #self.groups do
                self:sortFrames(i)
                self:repositionFrames(i)
            end
        end, 2)
        local dbmFrame = CreateFrame("Frame")
        dbmFrame:RegisterEvent("ADDON_LOADED")
        dbmFrame:SetScript("OnEvent", function(self, event, addon)
            if addon == "DBM-Core" then
                HomeCheck:ScheduleTimer(function()
                    if DBM and DBM.RegisterCallback then
                        DBM:RegisterCallback("kill", function(mod)
                            HomeCheck:ResetAllCooldowns()
                        end)
                        
                        DBM:RegisterCallback("wipe", function(mod)
                            HomeCheck:ResetAllCooldowns()
                        end)
                        
                        print("|cff00ff00[HomeCheck]|r Hooked into DBM for boss kill/wipe detection")
                    end
                end, 0.5)
            end
        end)
        if IsAddOnLoaded("DBM-Core") then
            self:ScheduleTimer(function()
                if DBM and DBM.RegisterCallback then
                    DBM:RegisterCallback("kill", function(mod)
                        HomeCheck:ResetAllCooldowns()
                    end)

                    DBM:RegisterCallback("wipe", function(mod)
                        HomeCheck:ResetAllCooldowns()
                    end)
                    print("|cff00ff00[HomeCheck]|r Hooked into DBM for boss kill/wipe detection")
                end
            end, 1)
        end
    end
end)

function HomeCheck:OnCommReceived(...)
    local prefix, message, _, sender = ...

    if not self.db.global.comms[prefix] then
        return
    end

    if sender == (UnitName("player")) then
        return
    end

    local success, messageType, spellID, spellName, playerName, CDLeft, target
    if prefix == "oRA3" then
        success, messageType, spellID, CDLeft, target = self:Deserialize(message)

        if not success then
            return
        end

        if type(messageType) ~= "string" or messageType ~= "Cooldown" then
            return
        end
    elseif prefix == "BLT" then
        if not string.find(message, ":") then
            return
        end

        messageType, message = strsplit(":", message)
        if messageType ~= "CD" then
            return
        end

        if not string.find(message, ";") then
            return
        end

        playerName, spellName, spellID, target = strsplit(";", message)
        

        if playerName and playerName ~= "" then
            sender = playerName
        end
    elseif prefix == "oRA" or prefix == "CTRA" then
        spellID, CDLeft = select(3, message:find("CD (%d) (%d+)"))
    elseif prefix == "RCD2" then
        spellID, CDLeft = select(3, message:find("(%d+) (%d+)"))
    elseif prefix == "FRCD3S" then
        spellID, playerName, CDLeft, target = select(3, message:find("(%d+)(%a+)(%d+)(%a*)"))
        
        if playerName and playerName ~= "" then
            sender = playerName
        end
    elseif prefix == "FRCD3" then
        playerName = tostring(sender)
        if not UnitInRaid(playerName) and not UnitInParty(playerName) then
            return
        end

        for w in string.gmatch(message, "([^,]*),") do
            spellID, CDLeft = select(3, w:find("(%d+)-(%d+)"))
            spellID = tonumber(spellID)
            CDLeft = tonumber(CDLeft)

            if not spellID or not CDLeft then
                return
            end

            if not self.spells[spellID] then
                spellName = GetSpellInfo(spellID)
                if spellName then
                    spellID = self.localizedSpellNames[spellName]
                end
            end

            self:setCooldown(spellID, playerName, CDLeft, nil, true)
        end
        return
    elseif prefix == "HomeCheck" then
        success, spellID, playerName, target = self:Deserialize(message)
        if not success then
            return
        end
    end

    if not spellID then
        return
    end

    playerName = playerName and tostring(playerName) or sender

    if not UnitInRaid(playerName) and not UnitInParty(playerName) then
        return
    end

    spellID = tonumber(spellID)

    CDLeft = CDLeft and tonumber(CDLeft)

    if not CDLeft then
        CDLeft = true
    elseif CDLeft <= 0 and not self:getSpellAlwaysShow(spellID) then
        return
    end

    if prefix == "oRA" then
        if spellID == 1 then
            spellID = 48477 -- Rebirth
        elseif spellID == 2 then
            spellID = 21169 -- Reincarnation
        elseif spellID == 3 then
            spellID = 47883 -- Soulstone Resurrection
        elseif spellID == 4 then
            spellID = 19752 -- Divine Intervention
        end
    elseif prefix == "BLT" then
        if spellID == 57934 then
            spellID = 59628
        elseif spellID == 34477 then
            spellID = 35079
        end
    end

    if not self.spells[spellID] then
        if not spellName then
            spellName = GetSpellInfo(spellID)
        end
        if spellName then
            spellID = self.localizedSpellNames[spellName]
        end
    end

    if prefix == "RCD2" and CDLeft == 0 and not self:UnitHasAbility(playerName, spellID) then
        return
    end

    if target then
        if target == "" then
            target = nil
        else
            target = tostring(target)
        end
    end

    self:setCooldown(spellID, playerName, CDLeft, target, true)
end

---@param spellID number
---@param playerName string
---@param CDLeft number|boolean|nil
---@param target string|nil
---@param isRemote boolean|nil
function HomeCheck:setCooldown(spellID, playerName, CDLeft, target, isRemote, testMode)

    if CDLeft == 0 then
        for i = 1, #self.groups do
            for j = 1, #self.groups[i].CooldownFrames do
                local frame = self.groups[i].CooldownFrames[j]
                if frame.spellID == spellID and frame.playerName == playerName then
                    frame.target = nil
                    if frame.targetFontString then 
                        frame.targetFontString:SetText("") 
                    end
                end
            end
        end
    end

    if spellID == 48788 and not testMode then
        local spellProfile = self.db.profile.spells[spellID]
        if spellProfile then
            local pointsLoH = select(5, self.LibGroupTalents:GetTalentInfo(playerName, 1, 8)) or 0
            

            if spellProfile.improvedloh and pointsLoH == 0 then
                self:removeCooldownFrames(playerName, spellID)
                return
            end
        end
    end


    if spellID == 498 and not testMode then
        local tanksOnlySetting = self.db.profile.spells[spellID] and self.db.profile.spells[spellID].tanksonly
        if tanksOnlySetting then
            local role = self.LibGroupTalents:GetUnitRole(playerName)
            local pointsProt = select(5, self.LibGroupTalents:GetTalentInfo(playerName, 2, 13)) or 0
            if role ~= "tank" and pointsProt == 0 then
                self:removeCooldownFrames(playerName, spellID)
                return 
            end
        end
    end


    if spellID == 48792 and not testMode then
        local tanksOnlySetting = self.db.profile.spells[spellID] and self.db.profile.spells[spellID].tanksonly
        if tanksOnlySetting then
            local role = self.LibGroupTalents:GetUnitRole(playerName)
            local pointsWotN = select(5, self.LibGroupTalents:GetTalentInfo(playerName, 1, 24)) or 0
            local pointsImpFrost = select(5, self.LibGroupTalents:GetTalentInfo(playerName, 2, 21)) or 0
            if role ~= "tank" and pointsWotN == 0 and pointsImpFrost == 0 then
                self:removeCooldownFrames(playerName, spellID)
                return 
            end
        end
    end

    if spellID == 51271 and not testMode then
        local tanksOnlySetting = self.db.profile.spells[spellID] and self.db.profile.spells[spellID].tanksonly
        if tanksOnlySetting then
            local role = self.LibGroupTalents:GetUnitRole(playerName)
            local pointsWotN = select(5, self.LibGroupTalents:GetTalentInfo(playerName, 1, 24)) or 0
            local pointsImpFrost = select(5, self.LibGroupTalents:GetTalentInfo(playerName, 2, 21)) or 0
            
            if role ~= "tank" and pointsWotN == 0 and pointsImpFrost == 0 then
                self:removeCooldownFrames(playerName, spellID)
                return 
            end
        end
    end


    if spellID == 48707 and not testMode then
        local tanksOnlySetting = self.db.profile.spells[spellID] and self.db.profile.spells[spellID].tanksonly
        if tanksOnlySetting then
            local role = self.LibGroupTalents:GetUnitRole(playerName)
            local pointsWotN = select(5, self.LibGroupTalents:GetTalentInfo(playerName, 1, 24)) or 0
            local pointsImpFrost = select(5, self.LibGroupTalents:GetTalentInfo(playerName, 2, 21)) or 0
            if role ~= "tank" and pointsWotN == 0 and pointsImpFrost == 0 then
                self:removeCooldownFrames(playerName, spellID)
                return 
            end
        end
    end


    if spellID == 871 and not testMode then
        local tanksOnlySetting = self.db.profile.spells[spellID] and self.db.profile.spells[spellID].tanksonly
        if tanksOnlySetting then
            local role = self.LibGroupTalents:GetUnitRole(playerName)
            local pointsWarrior = select(5, self.LibGroupTalents:GetTalentInfo(playerName, 3, 17)) or 0
            if role ~= "tank" and pointsWarrior == 0 then
                self:removeCooldownFrames(playerName, spellID)
                return 
            end
        end
    end


    if spellID == 22812 and not testMode then
        local tanksOnlySetting = self.db.profile.spells[spellID] and self.db.profile.spells[spellID].tanksonly
        if tanksOnlySetting then
            local role = self.LibGroupTalents:GetUnitRole(playerName)
            local pointsNatReact = select(5, self.LibGroupTalents:GetTalentInfo(playerName, 2, 16)) or 0
            if role ~= "tank" or pointsNatReact == 0 then
                self:removeCooldownFrames(playerName, spellID)
                return 
            end
        end
    end


    if spellID == 61336 and not testMode then
        local tanksOnlySetting = self.db.profile.spells[spellID] and self.db.profile.spells[spellID].tanksonly
        if tanksOnlySetting then
            local role = self.LibGroupTalents:GetUnitRole(playerName)
            local pointsNatReact = select(5, self.LibGroupTalents:GetTalentInfo(playerName, 2, 16)) or 0
            if role ~= "tank" or pointsNatReact == 0 then
                self:removeCooldownFrames(playerName, spellID)
                return 
            end
        end
    end



    if spellID == 23989 then
        -- Readiness
        self:Readiness(playerName)
    end

    if not spellID or not self.spells[spellID] then
        return
    end

    if not isRemote and CDLeft == true then
        self:SendCommMessage("HomeCheck", self:Serialize(spellID, playerName, target), "RAID")
    end

    if self.db.global.selfignore and playerName == UnitName("player") then
        return
    end

    if not self:isSpellEnabled(spellID) then
        return
    end

    if self.spells[spellID].parent then
        local frame = self:getCooldownFrame(playerName, self.spells[spellID].parent)
        if frame then
            if frame.CDLeft ~= 0 then
                self:setTarget(frame, target)
                return
            else
                self:removeCooldownFrames(playerName, self.spells[spellID].parent)
            end
        end
    end

    local frame = self:createCooldownFrame(playerName, spellID, testMode)

    if CDLeft == true then
        CDLeft = self:getSpellCooldown(frame)
    end

    if not CDLeft and frame.CDLeft == 0 and self.db.global.CDs[playerName][spellID].timestamp and self.db.global.CDs[playerName][spellID].timestamp > time() then
        -- restoring CD info from SV
        CDLeft = self.db.global.CDs[playerName][spellID].timestamp - time()
        target = self.db.global.CDs[playerName][spellID].target
        -- unknown data source and reliability, treat it as remote
        isRemote = true
    end

    target = self:setTarget(frame, target)

    if CDLeft then
        if frame.isRemote then
            if isRemote then
                if frame.CDLeft > 5 then
                    if CDLeft >= frame.CDLeft and CDLeft - frame.CDLeft < 5 then
                        return
                    end
                end
            else
                frame.isRemote = false
            end
        else
            if isRemote then
                if frame.CDLeft > 5 then
                    return
                end
                if CDLeft >= frame.CDLeft and CDLeft - frame.CDLeft < 5 then
                    return
                end
            else
                if CDLeft >= frame.CDLeft and CDLeft - frame.CDLeft < 2 then
                    return
                end
            end
        end

        frame.CDLeft = CDLeft
    elseif frame.initialized then
        return
    end

    if childSpells[spellID] then
        if not target then
            self:setTarget(frame, self:getTarget(playerName, childSpells[spellID]))
        end
        self:removeCooldownFrames(playerName, childSpells[spellID])
    end

    frame.CDLeft = CDLeft or frame.CDLeft
    frame.CDReady = GetTime() + frame.CDLeft
    frame.isRemote = isRemote
    frame.CD = self:getSpellCooldown(frame)
    if frame.CD < frame.CDLeft then
        frame.CD = frame.CDLeft
    end

    if not testMode then
        self.db.global.CDs[playerName][spellID].timestamp = frame.CDLeft > 0 and (time() + frame.CDLeft) or nil
    end

    if frame.CDLeft > 0 then
        frame.timerFontString:SetText(date("!%M:%S", frame.CDLeft):gsub('^0+:?0?', ''))

        if not frame.CDtimer then
            local tick = 1.0
            frame.CDtimer = self:ScheduleRepeatingTimer(function()
                frame.CDLeft = frame.CDReady - GetTime()

                if frame.CDLeft <= 0 then
                    self:CancelTimer(frame.CDtimer)
                    frame.CDtimer = nil
                    table.wipe(self.db.global.CDs[playerName][spellID])
                    if not self:getSpellAlwaysShow(spellID) then
                        self:removeCooldownFrames(playerName, spellID)
                        self:repositionFrames(self:getSpellGroup(spellID))
                        return
                    else
                        if frame.CDLeft < 0 then
                            frame.CDLeft = 0
                        end
                        frame.timerFontString:SetText("R")
                        self:setTimerColor(frame)
                    end
                elseif frame.timerText ~= floor(frame.CDLeft) then
                    frame.timerText = floor(frame.CDLeft)
                    frame.timerFontString:SetText(date("!%M:%S", frame.CDLeft):gsub('^0+:?0?', ''))
                    self:setTimerColor(frame)
                end
                self:updateCooldownBarProgress(frame)
            end, tick)
        end
    elseif not self:getSpellAlwaysShow(spellID) then
        self:removeCooldownFrames(playerName, spellID, true)
        self:repositionFrames(self:getSpellGroup(spellID))
        return
    else
        frame.timerFontString:SetText("R")
    end

    self:updateCooldownBarProgress(frame)

    self:sortFrames(self:getSpellGroup(spellID))

    self:setTimerColor(frame)

    frame.initialized = true
end

function HomeCheck:getCooldownFrame(playerName, spellID)
    local group = self:getGroup(self:getSpellGroup(spellID))
    for i = 1, #group.CooldownFrames do
        if group.CooldownFrames[i].playerName == playerName and group.CooldownFrames[i].spellID == spellID then
            return group.CooldownFrames[i]
        end
    end
end

function HomeCheck:createCooldownFrame(playerName, spellID, testMode)
    local frame = self:getCooldownFrame(playerName, spellID)

    if frame then
        return frame
    end

    local group = self:getGroup(self:getSpellGroup(spellID))
    frame = CreateFrame("Frame", nil, group)

    frame.playerName = playerName
    frame.spellID = spellID
    frame.CDLeft = 0
    frame.class = self.spells[spellID].class
    if not frame.class then
        frame.class = testMode and select(2, UnitClass("player")) or select(2, UnitClass(playerName))
    end
    frame.CD = self:getSpellCooldown(frame)
    frame.testMode = testMode

    frame.icon = frame:CreateTexture(nil, "OVERLAY")
    frame.icon:SetPoint("LEFT")
    frame.icon:SetTexture(select(3, GetSpellInfo(spellID)))

    frame.bar = CreateFrame("Frame", nil, frame)
    frame.bar:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT")
    frame.bar:SetPoint("BOTTOMRIGHT")

    frame.bar.active = frame.bar:CreateTexture(nil, "ARTWORK")
    frame.bar.active:SetPoint("LEFT")
    frame.bar.inactive = frame.bar:CreateTexture(nil, "ARTWORK")
    frame.bar.inactive:SetPoint("RIGHT")
    frame.bar.inactive:SetPoint("LEFT", frame.bar.active, "RIGHT")

    self:updateRange(frame)

    frame.playerNameFontString = frame.bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.playerNameFontString:SetText(frame.playerName)
    frame.playerNameFontString:SetTextColor(1, 1, 1, 1)

    frame.targetFontString = frame.bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.targetFontString:SetPoint("LEFT", frame.playerNameFontString, "RIGHT", 1, 0)

    frame.timerFontString = frame.bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")

    self:applyGroupSettings(frame)

    if self.db.global.link then
        self:EnableMouse(frame)
    end

    table.insert(group.CooldownFrames, frame)
    
    if HomeCheck.addonHidden then
        frame:Hide()
    end

    self:updateFramesVisibility(self:getSpellGroup(spellID))
    return frame
end

function HomeCheck:EnableMouse(frame, disable)
    if disable then
        frame:SetScript("OnMouseDown", nil)
        frame:EnableMouse(false)
    else
        frame:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then 
                if IsShiftKeyDown() then
                    local message = self.playerName .. " " .. (GetSpellLink(self.spellID))
                    if self.CDLeft <= 0 then
                        message = message .. " READY"
                    else
                        if self.target then
                            message = message .. " (" .. self.target .. ")"
                        end
                        message = message .. " " .. date("!%M:%S", self.CDLeft)
                    end
                    ChatThrottleLib:SendChatMessage("NORMAL", "HomeCheck", message, (UnitInRaid("player") and "RAID") or "PARTY")
                else
                    -- DOPPELKLICK LOGIK
                    local currentTime = GetTime()
                    if self.lastClick and (currentTime - self.lastClick) < 0.5 then
                        local message = "Use " .. (GetSpellLink(self.spellID)) .. " please!"
                        ChatThrottleLib:SendChatMessage("NORMAL", "HomeCheck", message, "WHISPER", nil, self.playerName)
                        self.lastClick = 0 -- Reset nach Erfolg
                    else
                        self.lastClick = currentTime -- Erster Klick Zeit merken
                    end
                end
            end
        end)
        frame:EnableMouse(true)
    end
end


function HomeCheck:repositionFrames(groupIndex)
    if not groupIndex then
        for i = 1, #self.groups do
            self:repositionFrames(i)
        end
        return
    end
    local titleBarHeight = 0
    if self:getIProp(groupIndex, "showTitleBar") and self.groups[groupIndex].titleBar and self.groups[groupIndex].titleBar:IsShown() then
        titleBarHeight = self:getIProp(groupIndex, "titleBarHeight")
    end
    for j = 1, #self.groups[groupIndex].CooldownFrames do
        self.groups[groupIndex].CooldownFrames[j]:SetPoint("TOPLEFT", 0, -titleBarHeight - (self:getIProp(groupIndex, "iconSize") + self:getIProp(groupIndex, "padding")) * (j - 1))
    end
end

function HomeCheck:loadProfile()
    for i = 1, #self.groups do
        self.groups[i].anchor:ClearAllPoints()
        self.groups[i].anchor:SetPoint(self.db.profile[i].pos.point, self.db.profile[i].pos.relativeTo, self.db.profile[i].pos.relativePoint, self.db.profile[i].pos.xOfs, self.db.profile[i].pos.yOfs)
        for j = 1, #self.groups[i].CooldownFrames do
            if i ~= self:getSpellGroup(self.groups[i].CooldownFrames[j].spellID) then
                self:moveFrameToGroup(self.groups[i].CooldownFrames[j].spellID, i, self:getSpellGroup(self.groups[i].CooldownFrames[j].spellID))
            else
                self:applyGroupSettings(self.groups[i].CooldownFrames[j])
            end
        end
    end
    self:updateRaidCooldowns()
    self:sortFrames()
end

function HomeCheck:removeCooldownFrames(playerName, spellID, onlyWhenReady, startGroup, startIndex, testMode)
    if spellID then
        startGroup = self:getSpellGroup(spellID)
    end
    for i = startGroup or 1, #self.groups do
        for j = startIndex or 1, #self.groups[i].CooldownFrames do
            if (
                    self.groups[i].CooldownFrames[j].playerName == playerName
                            and (not spellID or self.groups[i].CooldownFrames[j].spellID == spellID)
                            and (not onlyWhenReady or self.groups[i].CooldownFrames[j].CDLeft <= 0)
            ) or (
                    testMode and self.groups[i].CooldownFrames[j].testMode
            ) then
                self.groups[i].CooldownFrames[j]:Hide()
                if self.groups[i].CooldownFrames[j].CDtimer then
                    self:CancelTimer(self.groups[i].CooldownFrames[j].CDtimer)
                end
                table.remove(self.groups[i].CooldownFrames, j)
                self:updateFramesVisibility(i)
                if spellID then
                    break
                end
                return self:removeCooldownFrames(playerName, spellID, onlyWhenReady, i, j, testMode)
            end
        end

        if startIndex then
            -- reset start frame index when we proceed to next frames group
            startIndex = nil
        end
    end
end

function HomeCheck:updateRaidRoster(instant, startGroup, startIndex)
    if not instant then
        if updateRaidRosterScheduleTimer then
            -- update is scheduled
            return
        end

        if updateRaidRosterTimestamp and time() - updateRaidRosterTimestamp < updateRaidRosterCooldown then
            -- update is on cooldown
            updateRaidRosterScheduleTimer = self:ScheduleTimer(function()
                updateRaidRosterScheduleTimer = nil
                self:updateRaidRoster()
            end, updateRaidRosterCooldown)
            return
        end
    end

    for i = startGroup or 1, #self.groups do
        for j = startIndex or 1, #self.groups[i].CooldownFrames do
            if not UnitInRaid(self.groups[i].CooldownFrames[j].playerName) and not UnitInParty(self.groups[i].CooldownFrames[j].playerName) or not UnitIsConnected(self.groups[i].CooldownFrames[j].playerName) then
                self:removeCooldownFrames(self.groups[i].CooldownFrames[j].playerName)
                return self:updateRaidRoster(true, i, j)
            end
        end
    end
    self:updateRaidCooldowns()
    updateRaidRosterTimestamp = time()
end

function HomeCheck:updateRaidCooldowns()
    if GetNumRaidMembers() > 0 then
        for i = 1, 40 do
            local playerName, _, _, _, _, class, _, online, isDead = GetRaidRosterInfo(i)
            if isDead then
                self.deadUnits[playerName] = true
            end
            if playerName and online then
                self:refreshPlayerCooldowns(playerName, class)
            end
        end
    else
        self:refreshPlayerCooldowns((UnitName("player")))
        for i = 1, GetNumPartyMembers() do
            if UnitIsConnected("party" .. i) then
                self:refreshPlayerCooldowns((UnitName("party" .. i)))
            end
        end
    end
    self:repositionFrames()
    self:sortFrames()
end

function HomeCheck:refreshPlayerCooldowns(playerName, class)
    local _, pClass = UnitClass(playerName)
    if not pClass then pClass = class end

    for spellID, spellConfig in pairs(self.spells) do
        if not spellConfig.class or spellConfig.class == pClass then
            local spellProfile = self.db.profile.spells[spellID]
            local unitRole = self.LibGroupTalents:GetUnitRole(playerName)
            
            local pointsHeal = select(5, self.LibGroupTalents:GetTalentInfo(playerName, 1, 8)) or 0
            local pointsProt = select(5, self.LibGroupTalents:GetTalentInfo(playerName, 2, 13)) or 0
            local pointsWotN = select(5, self.LibGroupTalents:GetTalentInfo(playerName, 1, 24)) or 0
            local pointsImpFrost = select(5, self.LibGroupTalents:GetTalentInfo(playerName, 2, 21)) or 0
            local pointsWarrior = select(5, self.LibGroupTalents:GetTalentInfo(playerName, 3, 17)) or 0
            local pointsNatReact = select(5, self.LibGroupTalents:GetTalentInfo(playerName, 2, 16)) or 0
            local pointsUA = select(5, self.LibGroupTalents:GetTalentInfo(playerName, 2, 24)) or 0

            local canShow = false

            if spellProfile and self:isSpellEnabled(spellID) and self:UnitHasAbility(playerName, spellID) then
                canShow = true 

                if spellProfile.tanksonly then
                    if spellID == 48792 or spellID == 48707 then
                        if unitRole ~= "tank" and pointsWotN == 0 and pointsImpFrost == 0 then
                            canShow = false
                        end
                    elseif spellID == 51271 then
                        if unitRole ~= "tank" and pointsWotN == 0 and pointsImpFrost == 0 then
                            canShow = false
                        end
                    elseif spellID == 498 then
                        if unitRole ~= "tank" and pointsProt == 0 then
                            canShow = false
                        end
                    elseif spellID == 871 then
                        if unitRole ~= "tank" and pointsWarrior == 0 then
                            canShow = false
                        end
                    elseif spellID == 22812 then
                        if unitRole ~= "tank" or pointsNatReact == 0 then
                            canShow = false
                        end
                    elseif spellID == 61336 then
                        if unitRole ~= "tank" or pointsNatReact == 0 then
                            canShow = false
                        end
                    elseif unitRole ~= "tank" then
                        canShow = false
                    end
                end

                if spellProfile.improvedloh and spellID == 48788 then
                    if pointsHeal == 0 then
                        canShow = false
                    end
                end

                if self.db.global.selfignore and playerName == UnitName("player") then
                    canShow = false
                end
            end

            if canShow then
                if not spellConfig.parent then self:setCooldown(spellID, playerName) end
            else
                self:removeCooldownFrames(playerName, spellID)
            end
        end
    end
end



function HomeCheck:UnitHasAbility(playerName, spellID)
    if self.spells[spellID].parent then
        spellID = self.spells[spellID].parent
    end

    if self.spells[spellID].trinket then
        return self:UnitTrinketEquipped(playerName, self.spells[spellID].trinket)
    end

    if self.spells[spellID].race then
        local _, playerRace = UnitRace(playerName)
        if playerRace ~= self.spells[spellID].race then
            return false
        end
    end

    -- using UnitHasTalent() as GetTalentInfo() does not return correct value right after respec
    return not self.spells[spellID].talentTab or not self.spells[spellID].talentIndex or self.LibGroupTalents:UnitHasTalent(playerName, (GetSpellInfo(spellID)))
end

function HomeCheck:saveFramePosition(groupIndex)
    local point, relativeTo, relativePoint, xOfs, yOfs = self.groups[groupIndex].anchor:GetPoint(0)
    self.db.profile[groupIndex].pos = {
        point = point,
        relativeTo = relativeTo and relativeTo:GetName(),
        relativePoint = relativePoint,
        xOfs = xOfs,
        yOfs = yOfs
    }
end

function HomeCheck:Readiness(hunterName)
    if ReadinessTimestamp[hunterName] and time() - ReadinessTimestamp[hunterName] < 100 then
        return
    end

    local refreshSpellIDs = {}
    for i = 1, #self.groups do
        for j = 1, #self.groups[i].CooldownFrames do
            if self.groups[i].CooldownFrames[j].playerName == hunterName and self.groups[i].CooldownFrames[j].spellID ~= 34477 then
                table.insert(refreshSpellIDs, self.groups[i].CooldownFrames[j].spellID)
            end
        end
    end

    for _, spellID in ipairs(refreshSpellIDs) do
        self:setCooldown(spellID, hunterName, 0)
    end

    ReadinessTimestamp[hunterName] = time()
end

function HomeCheck:GSProc(targetName)
    local spellGroup = self:getSpellGroup(47788)
    for i = #self.groups[spellGroup].CooldownFrames, 1, -1 do
        if self.groups[spellGroup].CooldownFrames[i].spellID == 47788
                and self.groups[spellGroup].CooldownFrames[i].target == targetName
                and self.groups[spellGroup].CooldownFrames[i].CDLeft > 0 then
            self:setCooldown(47788, self.groups[spellGroup].CooldownFrames[i].playerName, 180)
            break
        end
    end
end

function HomeCheck:sortFrames(groupIndex)
    if not groupIndex then
        for i = 1, #self.groups do
            self:sortFrames(i)
        end
        return
    end

    for j = 1, #self.groups[groupIndex].CooldownFrames - 1 do
        for k = j + 1, #self.groups[groupIndex].CooldownFrames do
            if self:cooldownSorter(self.groups[groupIndex].CooldownFrames[j], self.groups[groupIndex].CooldownFrames[k]) then
                self.groups[groupIndex].CooldownFrames[j], self.groups[groupIndex].CooldownFrames[k] = self.groups[groupIndex].CooldownFrames[k], self.groups[groupIndex].CooldownFrames[j]
            end
        end
    end
    self:repositionFrames(groupIndex)
end

---cooldownSorter
---@param frame1 table cooldown frame to be moved
---@param frame2 table cooldown frame to compare against
---@return boolean true if frame1 should be below frame2
function HomeCheck:cooldownSorter(frame1, frame2)
    local groupIndex = self:getSpellGroup(frame1.spellID)


    local isDead1 = UnitIsDeadOrGhost(frame1.playerName) or (UnitHealth(frame1.playerName) == 0 and not UnitIsGhost(frame1.playerName))
    local isDead2 = UnitIsDeadOrGhost(frame2.playerName) or (UnitHealth(frame2.playerName) == 0 and not UnitIsGhost(frame2.playerName))

    if isDead1 ~= isDead2 then
        if isDead1 then return true end
        if isDead2 then return false end
    end


    local spellId1 = self.spells[frame1.spellID].parent or frame1.spellID
    local spellId2 = self.spells[frame2.spellID].parent or frame2.spellID
    

    if frame1.inRange < frame2.inRange then
        if self:getIProp(groupIndex, "rangeUngroup") then
            return true
        elseif spellId1 == spellId2 and self:getIProp(groupIndex, "rangeDimout") then
            return true
        end
    elseif frame1.inRange > frame2.inRange then
        if self:getIProp(groupIndex, "rangeUngroup") or spellId1 == spellId2 then
            return
        end
    end


    if self.db.profile.spells[spellId1].priority < self.db.profile.spells[spellId2].priority then
        return true
    elseif spellId1 == spellId2 then
        if frame1.CDLeft > frame2.CDLeft then
            return true
        end
    elseif self.db.profile.spells[spellId1].priority == self.db.profile.spells[spellId2].priority and spellId1 < spellId2 then
        return true
    end
end

function HomeCheck:getGroup(i)
    i = i or 1
    if self.groups[i] then
        return self.groups[i]
    end
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:ClearAllPoints()

    frame.anchor = CreateFrame("Frame", nil, frame)
    frame.anchor:SetClampedToScreen(true)
    frame.anchor:SetSize(20, 20)
    frame.anchor:SetPoint(self.db.profile[i].pos.point, self.db.profile[i].pos.relativeTo, self.db.profile[i].pos.relativePoint, self.db.profile[i].pos.xOfs, self.db.profile[i].pos.yOfs)
    frame.anchor:SetFrameStrata("HIGH")
    frame.anchor:SetMovable(true)
    frame.anchor:RegisterForDrag("LeftButton")
    frame.anchor:SetScript("OnDragStart", function(s) s:StartMoving() end)
    frame.anchor:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        self:saveFramePosition(i)
    end)
    frame.anchor:EnableMouse(true)

    frame:SetAllPoints(frame.anchor)

    -- Create title bar
    frame.titleBar = CreateFrame("Frame", nil, frame)
    frame.titleBar:SetHeight(self:getIProp(i, "titleBarHeight"))
    frame.titleBar:SetWidth(self:getIProp(i, "frameWidth"))
    frame.titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)

    -- Enable dragging on title bar
    frame.titleBar:EnableMouse(true)
    frame.titleBar:RegisterForDrag("LeftButton")
    frame.titleBar:SetScript("OnDragStart", function() frame.anchor:StartMoving() end)
    frame.titleBar:SetScript("OnDragStop", function()
        frame.anchor:StopMovingOrSizing()
        self:saveFramePosition(i)
    end)

    -- Title background
    frame.titleBar.bg = frame.titleBar:CreateTexture(nil, "BACKGROUND")
    frame.titleBar.bg:SetAllPoints(frame.titleBar)
    frame.titleBar.bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    local bgColor = self:getIProp(i, "titleBackgroundColor")
    frame.titleBar.bg:SetVertexColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

    -- Title text
    frame.titleBar.text = frame.titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.titleBar.text:SetPoint("LEFT", frame.titleBar, "LEFT", 5, 0)
    frame.titleBar.text:SetJustifyH("LEFT")
    local titleText = self:getIProp(i, "titleText")
    local displayText = (titleText and titleText ~= "") and titleText or ("Group " .. i)
    frame.titleBar.text:SetText(displayText)
    frame.titleBar.text:SetTextColor(1, 1, 1, 1)
    local font, size = frame.titleBar.text:GetFont()
    frame.titleBar.text:SetFont(font, self:getIProp(i, "titleFontSize") or size)


    if not frame.refreshBtn then
        frame.refreshBtn = CreateFrame("Button", nil, frame.titleBar)
        frame.refreshBtn:SetSize(16, 16)
        frame.refreshBtn:SetPoint("RIGHT", frame.titleBar, "RIGHT", -5, 0)
        frame.refreshBtn:SetFrameLevel(frame.titleBar:GetFrameLevel() + 10)
        
        frame.refreshBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        frame.refreshBtn:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
        frame.refreshBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        
        frame.refreshBtn:SetScript("OnClick", function()

            local lohProfile = self.db.profile.spells[48788]
            
            if lohProfile then
                lohProfile.enable = false
                self:removeCooldownFrames(UnitName("player"), 48788)
                
                lohProfile.enable = true
                self:refreshPlayerCooldowns(UnitName("player"))
                
                print("|cffff0000[HomeCheck]|r LoH time has been corrected & Tanks-only frames resetted!")
            end
        end)
        
        frame.refreshBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Dual Spec: Fix own LoH time & Tank-only cds")
            GameTooltip:AddLine("Fix: Sync own LoH and reset Tank-only frames after changing talents via Dual Spec.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        frame.refreshBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    if i == 1 and not frame.toggleBtn then
        frame.toggleBtn = CreateFrame("Button", nil, frame.titleBar)
        frame.toggleBtn:SetSize(16, 16)
        frame.toggleBtn:SetPoint("RIGHT", frame.refreshBtn, "LEFT", -5, 0)
        frame.toggleBtn:SetFrameLevel(frame.titleBar:GetFrameLevel() + 10)
        
        frame.toggleBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
        frame.toggleBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
        frame.toggleBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        
        frame.toggleBtn.addonHidden = false
        
        frame.toggleBtn:SetScript("OnClick", function(self)
            HomeCheck.addonHidden = not HomeCheck.addonHidden

            if HomeCheck.addonHidden then
                for g = 1, #HomeCheck.groups do
                    if HomeCheck.groups[g] and HomeCheck.groups[g].CooldownFrames and #HomeCheck.groups[g].CooldownFrames > 0 then
                        if g == 1 then
                            for f = 1, #HomeCheck.groups[g].CooldownFrames do
                                HomeCheck.groups[g].CooldownFrames[f]:Hide()
                            end
                        else
                            HomeCheck.groups[g]:Hide()
                        end
                    end
                end
                self:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
                self:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
            else
                for g = 1, #HomeCheck.groups do
                    if HomeCheck.groups[g] and HomeCheck.groups[g].CooldownFrames then
                        if #HomeCheck.groups[g].CooldownFrames > 0 or g == 1 then
                            if HomeCheck.db.profile[g].showTitleBar then
                                HomeCheck.groups[g]:Show()
                            end
                            for f = 1, #HomeCheck.groups[g].CooldownFrames do
                                HomeCheck.groups[g].CooldownFrames[f]:Show()
                            end
                        end
                    end
                end
                if HomeCheck.repositionFrames then
                    HomeCheck:repositionFrames()
                end
                self:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
                self:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
            end
        end)
        
        frame.toggleBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Toggle Addon Visibility")
            GameTooltip:AddLine("Click to hide or show all active cooldown frames.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        frame.toggleBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    if self:getIProp(i, "showTitleBar") then
        frame.titleBar:Show()
    else
        frame.titleBar:Hide()
    end

    frame.CooldownFrames = {}
    frame:Hide()
    table.insert(self.groups, frame)
    return frame
end

---@param playerName string
---@param spellID number
function HomeCheck:getCDLeft(playerName, spellID)
    for i = 1, #self.groups[self:getSpellGroup(spellID)].CooldownFrames do
        if playerName == self.groups[self:getSpellGroup(spellID)].CooldownFrames[i].playerName
                and spellID == self.groups[self:getSpellGroup(spellID)].CooldownFrames[i].spellID then
            return self.groups[self:getSpellGroup(spellID)].CooldownFrames[i].CDLeft
        end
    end
    return 0
end

function HomeCheck:getTarget(playerName, spellID)
    for i = 1, #self.groups[self:getSpellGroup(spellID)].CooldownFrames do
        if playerName == self.groups[self:getSpellGroup(spellID)].CooldownFrames[i].playerName
                and spellID == self.groups[self:getSpellGroup(spellID)].CooldownFrames[i].spellID then
            return self.groups[self:getSpellGroup(spellID)].CooldownFrames[i].target
        end
    end
end

function HomeCheck:setTarget(frame, target)
    if not target or self.spells[frame.spellID].notarget then
        return
    end
    if self.spells[frame.spellID].noself and target == frame.playerName then
        return
    end
    
 
    local class = select(2, UnitClass(target))
    if class then
        local targetClassColor = RAID_CLASS_COLORS[class]
        frame.targetFontString:SetTextColor(targetClassColor.r, targetClassColor.g, targetClassColor.b, 1)
    end


    if target == frame.target then
        return target
    end

    frame.target = target
    self.db.global.CDs[frame.playerName][frame.spellID].target = target
    frame.targetFontString:SetText(target)
    
    return target
end

function HomeCheck:updateRange(frame)
    local alive = UnitIsDeadOrGhost(frame.playerName) == false

    if not frame.inRange then
        if frame.testMode then
            frame.inRange = (random(1, 100) <= 80) and 1 or 0
        else
            frame.inRange = alive and self:UnitInRange(frame.playerName) and 1 or 0
        end
        self:sortFrames()
    elseif not frame.testMode then
        if alive then
            if frame.inRange == 0 and self:UnitInRange(frame.playerName) then
                frame.inRange = 1
                self:sortFrames()
            elseif frame.inRange == 1 and not self:UnitInRange(frame.playerName) then
                frame.inRange = 0
                self:sortFrames()
            end
        else
            frame.inRange = 0
            self:sortFrames()
        end
    end

    self:setBarColor(frame)

    if frame.letterFontString and frame.timerFontString then
        if alive then
            frame.letterFontString:SetTextColor(0,1,0,1)
        else
            frame.letterFontString:SetTextColor(1,0,0,1)
        end

        local onCD = frame.cdActive or false
        if alive or onCD then
            frame.timerFontString:SetTextColor(1,1,0,1)
        else
            frame.timerFontString:SetTextColor(1,0,0,1)
        end
    end
end

---@param frame
function HomeCheck:setBarColor(frame)
    local playerClassColor = RAID_CLASS_COLORS[frame.class]
    

    if frame.testMode then
        if playerClassColor then
            frame.bar.active:SetVertexColor(playerClassColor.r, playerClassColor.g, playerClassColor.b, self:getIPropBySpellId(frame.spellID, "opacity"))
        end
        return
    end
    local isDead = UnitIsDeadOrGhost(frame.playerName) or (UnitHealth(frame.playerName) == 0 and not UnitIsGhost(frame.playerName))

    local inRange = self:UnitInRange(frame.playerName)

    local useDimout = self:getIPropBySpellId(frame.spellID, "rangeDimout")

    if isDead then

        frame.bar.active:SetVertexColor(0.4, 0.4, 0.4, self:getIPropBySpellId(frame.spellID, "opacity"))
    elseif (not useDimout or inRange) then

        if playerClassColor then
            frame.bar.active:SetVertexColor(playerClassColor.r, playerClassColor.g, playerClassColor.b, self:getIPropBySpellId(frame.spellID, "opacity"))
        end
    else

        frame.bar.active:SetVertexColor(0.2, 0.2, 0.2, self:getIPropBySpellId(frame.spellID, "opacity"))
    end
end


function HomeCheck:setTimerColor(frame)
    if not frame or not frame.timerFontString or not frame.icon then return end


    if frame.testMode then
        local _, _, spellIconPath = GetSpellInfo(frame.spellID or 0)
        frame.icon:SetTexture(spellIconPath or "Interface\\Icons\\INV_Misc_QuestionMark")

        frame.targetFontString:SetText("Test")        

        if frame.timerFontString:GetText() == "R" then
            frame.timerFontString:SetTextColor(0, 1, 0, 1) -- R ist GRÜN
        else
            frame.timerFontString:SetTextColor(0.9, 0.7, 0, 1) -- Zahlen sind GELB
        end
        return
    end

    local isDead = UnitIsDeadOrGhost(frame.playerName) or (UnitHealth(frame.playerName) == 0 and not UnitIsGhost(frame.playerName))
    

    local skullIcon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
    local _, _, spellIconPath = GetSpellInfo(frame.spellID)

    if isDead then

        frame.timerFontString:SetTextColor(1, 0, 0, 1)
        frame.icon:SetTexture(skullIcon)
    else

        if frame.CDLeft <= 0 then
            frame.timerFontString:SetTextColor(0, 1, 0, 1)
        else
            frame.timerFontString:SetTextColor(0.9, 0.7, 0, 1)
        end
        

        if spellIconPath then
            frame.icon:SetTexture(spellIconPath)
        end
    end
end



function HomeCheck:getSpellCooldown(frame)
    local CDmodifier = 0
    if frame.spellID == 498 or frame.spellID == 642 then
        -- Divine Shield and Divine Protection
        CDmodifier = -30 * (select(5, self.LibGroupTalents:GetTalentInfo(frame.playerName, 2, 14)) or 0)
    elseif frame.spellID == 10278 then
        -- HoP
        CDmodifier = -60 * (select(5, self.LibGroupTalents:GetTalentInfo(frame.playerName, 2, 4)) or 0)
    elseif frame.spellID == 48788 then
        -- Lay on Hands
        local pointsLoH = select(5, self.LibGroupTalents:GetTalentInfo(frame.playerName, 1, 8)) or 0        
        if self.LoHHasNoBuff then
            pointsLoH = 0
        end
        self.LoHHasNoBuff = nil 
        CDmodifier = -120 * pointsLoH
        if self:UnitHasGlyph(frame.playerName, 57955) then
            CDmodifier = CDmodifier - 300
        end
    elseif frame.spellID == 20608 then
        -- Reincarnation
        local talentPoints = select(5, self.LibGroupTalents:GetTalentInfo(frame.playerName, 3, 3))
        if talentPoints == 1 then
            CDmodifier = -420
        elseif talentPoints == 2 then
            CDmodifier = -900
        end
    elseif frame.spellID == 10308 then
        -- Hammer of Justice
        local talentPoints = select(5, self.LibGroupTalents:GetTalentInfo(frame.playerName, 2, 10)) or 0        
        if talentPoints == 1 then
            CDmodifier = -10
        elseif talentPoints == 2 then
            CDmodifier = -20
        end
    elseif frame.spellID == 871 then
        -- Shield Wall
        CDmodifier = -30 * (select(5, self.LibGroupTalents:GetTalentInfo(frame.playerName, 3, 13)) or 0)
        if self:UnitHasGlyph(frame.playerName, 63329) then
            CDmodifier = CDmodifier - 120
        end
    elseif frame.spellID == 12975 then
        -- Last Stand
        if self:UnitHasGlyph(frame.playerName, 58376) then
            CDmodifier = CDmodifier - 60
        end
    elseif frame.spellID == 48447 then
        -- Tranquility
        local talentPoints = select(5, self.LibGroupTalents:GetTalentInfo(frame.playerName, 3, 14))
        if talentPoints == 1 then
            CDmodifier = -(self.spells[frame.spellID] and self.spells[frame.spellID].cd or 0) * 0.3
        elseif talentPoints == 2 then
            CDmodifier = -(self.spells[frame.spellID] and self.spells[frame.spellID].cd or 0) * 0.5
        end
    elseif frame.spellID == 47585 then
        -- Dispersion
        if self:UnitHasGlyph(frame.playerName, 63229) then
            CDmodifier = CDmodifier - 45
        end
    elseif frame.spellID == 45438 then
        -- Ice Block
        local talentPoints = select(5, self.LibGroupTalents:GetTalentInfo(frame.playerName, 3, 3))
        if talentPoints == 1 then
            CDmodifier = -(self.spells[frame.spellID] and self.spells[frame.spellID].cd or 0) * 0.07
        elseif talentPoints == 2 then
            CDmodifier = -(self.spells[frame.spellID] and self.spells[frame.spellID].cd or 0) * 0.14
        elseif talentPoints == 3 then
            CDmodifier = -(self.spells[frame.spellID] and self.spells[frame.spellID].cd or 0) * 0.2
        end
    elseif frame.spellID == 66 or frame.spellID == 12051 then
        -- Invisibility or Evocation
        CDmodifier = -(self.spells[frame.spellID] and self.spells[frame.spellID].cd or 0) * 0.15 * (select(5, self.LibGroupTalents:GetTalentInfo(frame.playerName, 1, 24)) or 0)
    elseif frame.spellID == 12292 then
        -- Death Wish
        CDmodifier = -(self.spells[frame.spellID] and self.spells[frame.spellID].cd or 0) * 0.11 * (select(5, self.LibGroupTalents:GetTalentInfo(frame.playerName, 2, 18)) or 0)
    elseif frame.spellID == 10060 or frame.spellID == 33206 then
        -- Power Infusion and Pain Suppression
        CDmodifier = -(self.spells[frame.spellID] and self.spells[frame.spellID].cd or 0) * 0.1 * (select(5, self.LibGroupTalents:GetTalentInfo(frame.playerName, 1, 23)) or 0)
    elseif frame.spellID == 47788 then
        -- Guardian spirit
        if frame.CDLeft > self.spells[frame.spellID].cd then
            return 180
        end
        if not self:UnitHasGlyph(frame.playerName, 63231, true) then
            return 180
        end
    elseif frame.spellID == 42650 then
        -- Army of the Dead
        CDmodifier = -120 * (select(5, self.LibGroupTalents:GetTalentInfo(frame.playerName, 3, 13)) or 0)
    end

    return self.spells[frame.spellID].cd + CDmodifier
end

function HomeCheck:cacheLocalizedSpellNames()
    for spellID, _ in pairs(self.spells) do
        local spellName = GetSpellInfo(spellID)
        self.localizedSpellNames[spellName] = spellID
    end
end

function HomeCheck:getSpellGroup(spellID)
    return self.spells[spellID].parent and self.db.profile.spells[self.spells[spellID].parent].group or self.db.profile.spells[spellID].group
end

function HomeCheck:applyGroupSettings(frame, groupIndex)
    groupIndex = groupIndex or self:getSpellGroup(frame.spellID)

    frame:SetParent(self:getGroup(groupIndex))

    self:setFrameHeight(frame, self:getIProp(groupIndex, "iconSize"))
    frame:SetWidth(self:getIProp(groupIndex, "frameWidth"))
    frame.playerNameFontString:SetFont(self.LibSharedMedia:Fetch("font", self:getIProp(groupIndex, "fontPlayer")), self:getIProp(groupIndex, "fontSize"))
    frame.targetFontString:SetFont(self.LibSharedMedia:Fetch("font", self:getIProp(groupIndex, "fontTarget")), self:getIProp(groupIndex, "fontSizeTarget"))
    frame.targetFontString:SetJustifyH(self:getIProp(groupIndex, "targetJustify") == "l" and "LEFT" or "RIGHT")
    self:setBarTexture(frame, self.LibSharedMedia:Fetch("statusbar", self:getIProp(groupIndex, "statusbar")))
    self:setBarColor(frame)
    frame.bar.inactive:SetVertexColor(unpack(self:getIProp(groupIndex, "background")))
    frame.timerFontString:SetFont(self.LibSharedMedia:Fetch("font", self:getIProp(groupIndex, "fontTimer")), self:getIProp(groupIndex, "fontSizeTimer"))
    self:setTimerPosition(frame)
end

function HomeCheck:setSpellGroupIndex(spellID, groupIndex)
    if self.db.profile.spells[spellID].group == groupIndex then
        return
    end
    self:moveFrameToGroup(spellID, self.db.profile.spells[spellID].group, groupIndex)
    self:sortFrames(self.db.profile.spells[spellID].group)
    self:sortFrames(groupIndex)
    self.db.profile.spells[spellID].group = groupIndex
end

function HomeCheck:moveFrameToGroup(spellID, sourceGroupIndex, destGroupIndex, startIndex)
    for i = startIndex or 1, #self.groups[sourceGroupIndex].CooldownFrames do
        if spellID == self.groups[sourceGroupIndex].CooldownFrames[i].spellID then
            local frame = table.remove(self.groups[sourceGroupIndex].CooldownFrames, i)
            self:updateFramesVisibility(sourceGroupIndex)
            self:applyGroupSettings(frame, destGroupIndex)
            table.insert(self.groups[destGroupIndex].CooldownFrames, frame)
            self:updateFramesVisibility(destGroupIndex)
            return self:moveFrameToGroup(spellID, sourceGroupIndex, destGroupIndex, i)
        end
    end
end

function HomeCheck:UnitInRange(unit)
    return select(2, self.LibRangeCheck:GetRange(unit))
end

function HomeCheck:updateCooldownBarProgress(frame)
    local pct = frame.CDLeft / frame.CD
    if self:getIPropBySpellId(frame.spellID, "invertColors") then
        if pct ~= 0 then
            if not frame.bar.active:IsShown() then
                frame.bar.active:Show()
                frame.bar.inactive:SetPoint("LEFT", frame.bar.active, "RIGHT")
            end
            frame.bar.active:SetWidth((self:getIPropBySpellId(frame.spellID, "frameWidth") - self:getIPropBySpellId(frame.spellID, "iconSize")) * pct)
        elseif frame.bar.active:IsShown() then
            frame.bar.active:Hide()
            frame.bar.inactive:SetPoint("LEFT", frame.icon, "RIGHT")
        end
    else
        if pct ~= 1 then
            if not frame.bar.active:IsShown() then
                frame.bar.active:Show()
                frame.bar.inactive:SetPoint("LEFT", frame.bar.active, "RIGHT")
            end
            frame.bar.active:SetWidth((self:getIPropBySpellId(frame.spellID, "frameWidth") - self:getIPropBySpellId(frame.spellID, "iconSize")) * (1 - pct))
        elseif frame.bar.active:IsShown() then
            frame.bar.active:Hide()
            frame.bar.inactive:SetPoint("LEFT", frame.icon, "RIGHT")
        end
    end
end

function HomeCheck:setTimerPosition(frame)
    frame.timerFontString:ClearAllPoints()
    if self:getIPropBySpellId(frame.spellID, "timerPosition") == "l" then
        frame.timerFontString:SetPoint("LEFT", frame.icon, "RIGHT", 1, 0)
        frame.playerNameFontString:SetPoint("LEFT", frame.timerFontString, "RIGHT", 2, 0)
        frame.targetFontString:SetPoint("RIGHT", frame, "RIGHT", -2, 0)
    else
        frame.timerFontString:SetPoint("RIGHT", frame, "RIGHT", -2, 0)
        frame.playerNameFontString:SetPoint("LEFT", frame.icon, "RIGHT", 1, 0)
        frame.targetFontString:SetPoint("RIGHT", frame.timerFontString, "LEFT", -1, 0)
    end
end

function HomeCheck:getSpellAlwaysShow(spellID)
    return self.spells[spellID]
            and self.spells[spellID].parent
            and self.db.profile.spells[self.spells[spellID].parent].alwaysShow
            or self.db.profile.spells[spellID].alwaysShow
end

function HomeCheck:isSpellEnabled(spellID)
    return self.spells[spellID].parent and self.db.profile.spells[self.spells[spellID].parent].enable or self.db.profile.spells[spellID].enable
end

function HomeCheck:isSpellTanksOnly(spellID)
    return self.spells[spellID].parent and self.db.profile.spells[self.spells[spellID].parent].tanksonly or self.db.profile.spells[spellID].tanksonly
end

function HomeCheck:Rebirth(event, playerName, target)
    if event == "UNIT_SPELLCAST_SENT" then
        self.RebirthTargets[playerName] = target
    elseif event == "UNIT_SPELLCAST_FAILED" then
        self.RebirthTargets[playerName] = nil
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        self:setCooldown(48477, playerName, true, self.RebirthTargets[playerName])
        self.RebirthTargets[playerName] = nil
    end
end

function HomeCheck:UnitHasGlyph(unit, glyphID, default)

    if self.LibGroupTalents:UnitHasGlyph(unit, glyphID) then
        return true
    end

    local a, b, c, d, e, f = self.LibGroupTalents:GetUnitGlyphs(unit)
    

    if a == nil and b == nil and c == nil and d == nil and e == nil and f == nil then
        if unit and UnitExists(unit) and UnitAura(unit, GetSpellInfo(glyphID)) then
            return true
        end
    end


    if not default then
        return false
    end
    if a or b or c or d or e or f then
        return false
    end
    return true
end

function HomeCheck:setBarTexture(frame, texture)
    frame.bar.active:SetTexture(texture)
    frame.bar.inactive:SetTexture(texture)
end

function HomeCheck:setFrameHeight(frame, height)
    if not height then
        height = self:getIPropBySpellId(frame.spellID, "iconSize")
    end
    frame:SetHeight(height)
    frame.icon:SetSize(height, height)
    frame.bar.active:SetHeight(height)
    frame.bar.inactive:SetHeight(height)
    self:updateCooldownBarProgress(frame)
end

---getIProp
---@param frameId number frame group number
---@param propertyName string property name to get
function HomeCheck:getIProp(frameId, propertyName)
    -- Title bar properties are never inherited - always use the specific group's settings
    local titleBarProperties = {
        showTitleBar = true,
        titleText = true,
        titleBarHeight = true,
        titleFontSize = true,
        titleBackgroundColor = true
    }

    if titleBarProperties[propertyName] then
        return self.db.profile[frameId][propertyName]
    else
        return self.db.profile[self.db.profile[frameId].inherit or frameId][propertyName]
    end
end

function HomeCheck:getIPropBySpellId(spellId, propertyName)
    return self:getIProp(self:getSpellGroup(spellId), propertyName)
end

function HomeCheck:updateFramesVisibility(groupIndex)
    if self.addonHidden then return end

    if groupIndex then
        local isSolo = not UnitInRaid("player") and GetNumPartyMembers() == 0
        local hideSolo = self.db.global.hidesolo
        local hasFrames = #self.groups[groupIndex].CooldownFrames > 0


        if hideSolo and isSolo then
            self.groups[groupIndex]:Hide()
        elseif not hasFrames then
            self.groups[groupIndex]:Hide()
        else
            self.groups[groupIndex]:Show()
        end
        return
    end


    for i = 1, #self.groups do
        self:updateFramesVisibility(i)
    end
end

function HomeCheck:setTestMode(enable)
    self.db.global.testMode = enable
    if enable then
        for spellId, _ in pairs(self.db.profile.spells) do
            if self.spells[spellId] then
                -- Create test cooldown with varying times
                local testCDLeft = random(1, 5) * 10
                self:setCooldown(spellId, "Test frame", testCDLeft, nil, nil, true)
            end
        end
    else

        self:removeCooldownFrames(nil, nil, nil, nil, nil, true)
    end

    self:repositionFrames()
end

function HomeCheck:ResetAllCooldowns()
    print("|cff00ff00[HomeCheck]|r Resetting all raid cooldowns...")
    
    for i = 1, #self.groups do
        for j = 1, #self.groups[i].CooldownFrames do
            local frame = self.groups[i].CooldownFrames[j]
            if frame then

                frame.target = nil
                

                if frame.targetFontString then 
                    frame.targetFontString:SetText("") 
                end
                

                if frame.spellID ~= 47883 then
                    self:setCooldown(frame.spellID, frame.playerName, 0)
                end
            end
        end
    end
    
    self:repositionFrames()
end

function HomeCheck:getUnit(playerName)
    if not self.units then self.units = {} end
    if not self.units[playerName] then
        self.units[playerName] = {
            dead = UnitIsDeadOrGhost(playerName),
            range = self:UnitInRange(playerName) and 1 or 0
        }
        -- Sofort-Scan für dich selbst beim Einloggen/Reload
        if playerName == UnitName("player") then
            self.units[playerName].trinket1 = GetInventoryItemID("player", 13)
            self.units[playerName].trinket2 = GetInventoryItemID("player", 14)
        end
    end
    return self.units[playerName]
end

function HomeCheck:UnitTrinketEquipped(playerName, trinketId)
    if type(trinketId) == "table" then
        for _, id in ipairs(trinketId) do
            if self:getUnit(playerName).trinket1 == id or self:getUnit(playerName).trinket2 == id then
                return true
            end
        end
    elseif self:getUnit(playerName).trinket1 == trinketId or self:getUnit(playerName).trinket2 == trinketId then
        return true
    end

    return false
end