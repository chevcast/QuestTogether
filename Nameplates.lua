--[[
QuestTogether Nameplate Augmentation

Purpose:
- Add a quest icon on Blizzard default nameplates for quest-objective units.
- Optionally tint quest-objective nameplate health bars to a burnt orange color.

Design constraints:
- Keep the implementation minimal and non-invasive.
- Do not replace Blizzard templates or secure handlers.
- Hook post-update paths so Blizzard remains source-of-truth for baseline behavior.
]]

local QuestTogether = _G.QuestTogether
local QUEST_SCAN_CACHE_TTL_SECONDS = 0.5

-- Icon copied from the user's prior Plater mod usage for visual familiarity.
QuestTogether.NAMEPLATE_QUEST_ICON_TEXTURE = "Interface\\OPTIONSFRAME\\UI-OptionsFrame-NewFeatureIcon"

-- Default burnt-orange tint for quest-objective units.
QuestTogether.NAMEPLATE_QUEST_HEALTH_COLOR = {
	r = 0.95,
	g = 0.45,
	b = 0.05,
}

local function ClampColorComponent(value, fallback)
	local numberValue = tonumber(value)
	if not numberValue then
		return fallback
	end
	if numberValue < 0 then
		return 0
	end
	if numberValue > 1 then
		return 1
	end
	return numberValue
end

QuestTogether.nameplateQuestTitleCache = QuestTogether.nameplateQuestTitleCache or {}
QuestTogether.nameplateQuestObjectiveCache = QuestTogether.nameplateQuestObjectiveCache or {}
QuestTogether.nameplateQuestStateByUnitToken = QuestTogether.nameplateQuestStateByUnitToken or {}
QuestTogether.nameplateIconByUnitFrame = QuestTogether.nameplateIconByUnitFrame
	or setmetatable({}, { __mode = "k" })
QuestTogether.nameplateBaseHealthColorByUnitFrame = QuestTogether.nameplateBaseHealthColorByUnitFrame
	or setmetatable({}, { __mode = "k" })

-- Returns true only for the dynamic nameplate unit tokens (nameplate1, nameplate2, ...).
function QuestTogether:IsNameplateUnitToken(unitToken)
	return type(unitToken) == "string" and string.find(unitToken, "^nameplate%d+$") ~= nil
end

function QuestTogether:GetNameplateNowSeconds()
	return self.API.GetTime()
end

function QuestTogether:DoesNameplateUnitExist(unitToken)
	return UnitExists(unitToken) and true or false
end

function QuestTogether:GetNameplateUnitGuid(unitToken)
	return UnitGUID(unitToken)
end

function QuestTogether:IsNameplateUnitRelatedToActiveQuest(unitToken)
	if not C_QuestLog or not C_QuestLog.UnitIsRelatedToActiveQuest then
		return false
	end
	local ok, isRelated = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unitToken)
	return ok and isRelated and true or false
end

function QuestTogether:IsNameplateUnitOnQuest(unitToken, questId)
	if not C_QuestLog or not C_QuestLog.IsUnitOnQuest then
		return false
	end
	local ok, isOnQuest = pcall(C_QuestLog.IsUnitOnQuest, unitToken, questId)
	return ok and isOnQuest and true or false
end

function QuestTogether:IsNameplateUnitQuestBoss(unitToken)
	if not UnitIsQuestBoss then
		return false
	end
	return UnitIsQuestBoss(unitToken) and true or false
end

function QuestTogether:CanPlayerAttackNameplateUnit(unitToken)
	return UnitCanAttack("player", unitToken) and true or false
end

function QuestTogether:IsNameplateUnitPlayer(unitToken)
	return UnitIsPlayer(unitToken) and true or false
end

function QuestTogether:IsNameplateUnitConnected(unitToken)
	return UnitIsConnected(unitToken) and true or false
end

function QuestTogether:IsNameplateUnitDead(unitToken)
	return UnitIsDead(unitToken) and true or false
end

function QuestTogether:IsNameplateUnitTapDenied(unitToken)
	return UnitIsTapDenied(unitToken) and true or false
end

function QuestTogether:GetNameplateQuestHealthColor()
	local fallback = self.NAMEPLATE_QUEST_HEALTH_COLOR
	local configured = self:GetOption("nameplateQuestHealthColor")
	if type(configured) ~= "table" then
		return { r = fallback.r, g = fallback.g, b = fallback.b }
	end

	return {
		r = ClampColorComponent(configured.r, fallback.r),
		g = ClampColorComponent(configured.g, fallback.g),
		b = ClampColorComponent(configured.b, fallback.b),
	}
end

local function GetBooleanFieldIfPresent(tableValue, key)
	if not tableValue then
		return nil
	end
	local value = tableValue[key]
	if value == nil then
		return nil
	end
	return value == true
end

local function GetObjectiveProgressState(text)
	if type(text) ~= "string" or text == "" then
		return "unknown"
	end

	local amountCurrent, amountTotal = text:match("(%d+)%s*/%s*(%d+)")
	if amountCurrent and amountTotal then
		if tonumber(amountCurrent) < tonumber(amountTotal) then
			return "unfinished"
		end
		return "complete"
	end

	local percentText = text:match("(%d+)%%")
	if percentText then
		if tonumber(percentText) < 100 then
			return "unfinished"
		end
		return "complete"
	end

	return "unknown"
end

function QuestTogether:ClearNameplateQuestObjectiveCache()
	wipe(self.nameplateQuestObjectiveCache)
	wipe(self.nameplateQuestStateByUnitToken)
end

function QuestTogether:RebuildNameplateQuestTitleCache()
	wipe(self.nameplateQuestTitleCache)

	if not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries or not C_QuestLog.GetInfo then
		return
	end

	local totalEntries = C_QuestLog.GetNumQuestLogEntries()
	for entryIndex = 1, totalEntries do
		local questDetails = C_QuestLog.GetInfo(entryIndex)
		if
			questDetails
			and not questDetails.isHeader
			and not questDetails.isHidden
			and type(questDetails.title) == "string"
			and questDetails.title ~= ""
		then
			self.nameplateQuestTitleCache[questDetails.title] = true
		end
	end

	-- Include world quest titles similarly to how Plater seeds its cache.
	if C_Map and C_Map.GetBestMapForUnit and C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID then
		local mapId = C_Map.GetBestMapForUnit("player")
		if mapId then
			local getQuestsForMap = C_TaskQuest.GetQuestsForPlayerByMapID or C_TaskQuest.GetQuestsOnMap
			if getQuestsForMap then
				local worldQuestList = getQuestsForMap(mapId)
				if type(worldQuestList) == "table" then
					for _, questInfo in ipairs(worldQuestList) do
						local questId = questInfo and questInfo.questId
						if type(questId) == "number" and questId > 0 then
							local questName = C_TaskQuest.GetQuestInfoByQuestID(questId)
							if type(questName) == "string" and questName ~= "" then
								self.nameplateQuestTitleCache[questName] = true
							end
						end
					end
				end
			end
		end
	end
end

function QuestTogether:GetCachedQuestObjectiveResult(guid)
	local cached = self.nameplateQuestObjectiveCache[guid]
	if not cached then
		return nil
	end

	local nowSeconds = self:GetNameplateNowSeconds()
	if cached.expiresAt and cached.expiresAt > nowSeconds then
		return cached.value
	end

	self.nameplateQuestObjectiveCache[guid] = nil
	return nil
end

function QuestTogether:SetCachedQuestObjectiveResult(guid, value)
	local nowSeconds = self:GetNameplateNowSeconds()
	self.nameplateQuestObjectiveCache[guid] = {
		value = value and true or false,
		expiresAt = nowSeconds + QUEST_SCAN_CACHE_TTL_SECONDS,
	}
end

function QuestTogether:IsQuestObjectiveViaTooltip(unitToken)
	if not unitToken or not self:DoesNameplateUnitExist(unitToken) then
		return false
	end

	local unitGuid = self:GetNameplateUnitGuid(unitToken)
	if not unitGuid or unitGuid == "" then
		return false
	end
	if issecretvalue and issecretvalue(unitGuid) then
		return false
	end

	local cachedValue = self:GetCachedQuestObjectiveResult(unitGuid)
	if cachedValue ~= nil then
		return cachedValue
	end

	if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink and Enum and Enum.TooltipDataLineType) then
		self:SetCachedQuestObjectiveResult(unitGuid, false)
		return false
	end

	local tooltipData = C_TooltipInfo.GetHyperlink("unit:" .. unitGuid)
	if not tooltipData or type(tooltipData.lines) ~= "table" then
		self:SetCachedQuestObjectiveResult(unitGuid, false)
		return false
	end

	local scanLines = {}
	for _, lineData in ipairs(tooltipData.lines) do
		local lineType = lineData and lineData.type
		if
			lineType == Enum.TooltipDataLineType.QuestObjective
			or lineType == Enum.TooltipDataLineType.QuestTitle
			or lineType == Enum.TooltipDataLineType.QuestPlayer
		then
			scanLines[#scanLines + 1] = lineData.leftText or ""
		end
	end

	if #scanLines == 0 then
		self:SetCachedQuestObjectiveResult(unitGuid, false)
		return false
	end

	if not next(self.nameplateQuestTitleCache) then
		self:RebuildNameplateQuestTitleCache()
	end

	local isQuestUnit = false
	local hasUnfinishedObjective = false

	for lineIndex = 1, #scanLines do
		local lineText = scanLines[lineIndex]
		if self.nameplateQuestTitleCache[lineText] then
			isQuestUnit = true

			local objectiveIndex = lineIndex + 1
			local sawUnknownObjectiveLine = false
			while objectiveIndex <= #scanLines do
				local objectiveLineText = scanLines[objectiveIndex]
				if self.nameplateQuestTitleCache[objectiveLineText] then
					break
				end

				local progressState = GetObjectiveProgressState(objectiveLineText)
				if progressState == "unfinished" then
					hasUnfinishedObjective = true
					break
				elseif progressState == "unknown" and objectiveLineText ~= "" then
					sawUnknownObjectiveLine = true
				end
				objectiveIndex = objectiveIndex + 1
			end

			if not hasUnfinishedObjective and sawUnknownObjectiveLine then
				hasUnfinishedObjective = true
			end

			if hasUnfinishedObjective then
				break
			end
		end
	end

	local result = isQuestUnit and hasUnfinishedObjective
	self:SetCachedQuestObjectiveResult(unitGuid, result)
	return result
end

-- Resolve "is this unit a quest objective?" from available runtime signals.
--
-- Priority:
-- 1) Nameplate frame field used by Plater and other addons: unitFrame.namePlateIsQuestObjective.
-- 2) Public API: C_QuestLog.UnitIsRelatedToActiveQuest(unitToken).
-- 3) Public API: C_QuestLog.IsUnitOnQuest(unitToken, questID) against local tracked quests.
-- 4) Public API fallback: UnitIsQuestBoss(unitToken).
--
-- The first source catches engine-fed objective flags when present.
-- The C_QuestLog calls provide robust fallback on default Blizzard nameplates.
function QuestTogether:IsQuestObjectiveUnit(unitToken, unitFrame)
	local directFlag = GetBooleanFieldIfPresent(unitFrame, "namePlateIsQuestObjective")
	if directFlag ~= nil then
		return directFlag
	end

	local alternateFlag = GetBooleanFieldIfPresent(unitFrame, "isQuestObjective")
	if alternateFlag ~= nil then
		return alternateFlag
	end

	if not unitToken or not self:DoesNameplateUnitExist(unitToken) then
		return false
	end

	if self:IsNameplateUnitRelatedToActiveQuest(unitToken) then
		return true
	end

	for questId in pairs(self:GetPlayerTracker() or {}) do
		if self:IsNameplateUnitOnQuest(unitToken, questId) then
			return true
		end
	end

	-- Plater-style fallback: parse unit tooltip quest lines for unfinished objectives.
	if self:IsQuestObjectiveViaTooltip(unitToken) then
		return true
	end

	return self:IsNameplateUnitQuestBoss(unitToken)
end

function QuestTogether:ShouldShowQuestNameplateIcon(unitToken, unitFrame)
	if not self:GetOption("nameplateQuestIconEnabled") then
		return false
	end
	return self:IsQuestObjectiveNameplate(unitToken, unitFrame)
end

function QuestTogether:IsQuestObjectiveNameplate(unitToken, unitFrame)
	if not self.isEnabled then
		return false
	end

	if not self:IsNameplateUnitToken(unitToken) then
		return false
	end

	if not unitFrame then
		return false
	end

	-- Feature target is quest mobs/objective enemies, not friendly NPC nameplates.
	if not self:CanPlayerAttackNameplateUnit(unitToken) then
		return false
	end

	return self:IsQuestObjectiveUnit(unitToken, unitFrame)
end

-- Keep tinting conservative so we do not override important Blizzard states.
function QuestTogether:ShouldApplyQuestHealthTint(frame)
	if not self.isEnabled then
		return false
	end

	if not self:GetOption("nameplateQuestHealthColorEnabled") then
		return false
	end

	if not frame or not frame.unit then
		return false
	end

	if not self:IsNameplateUnitToken(frame.unit) then
		return false
	end

	if not frame.healthBar then
		return false
	end

	if not self:DoesNameplateUnitExist(frame.unit) then
		return false
	end

	-- Never tint players; this is intended for quest mobs/NPCs.
	if self:IsNameplateUnitPlayer(frame.unit) then
		return false
	end

	-- Avoid tinting non-hostile/friendly nameplates.
	if not self:CanPlayerAttackNameplateUnit(frame.unit) then
		return false
	end

	-- Preserve gray dead/disconnected/tap-denied states from Blizzard.
	if
		not self:IsNameplateUnitConnected(frame.unit)
		or self:IsNameplateUnitDead(frame.unit)
		or self:IsNameplateUnitTapDenied(frame.unit)
	then
		return false
	end

	return self:IsQuestObjectiveUnit(frame.unit, frame)
end

local function EnsureQuestIcon(unitFrame)
	if not unitFrame then
		return nil
	end

	local existingIcon = QuestTogether.nameplateIconByUnitFrame[unitFrame]
	if existingIcon then
		return existingIcon
	end

	local icon = unitFrame:CreateTexture(nil, "OVERLAY", nil, 2)
	QuestTogether.nameplateIconByUnitFrame[unitFrame] = icon

	icon:SetTexture(QuestTogether.NAMEPLATE_QUEST_ICON_TEXTURE)
	icon:SetSize(21, 21)

	-- Anchor centered above the health bar for a clean, consistent position.
	-- This is intentionally attached to existing Blizzard regions instead of replacing layout.
	if unitFrame.HealthBarsContainer then
		icon:SetPoint("BOTTOM", unitFrame.HealthBarsContainer, "TOP", 0, 11)
	else
		icon:SetPoint("TOP", unitFrame, "TOP", 0, 7)
	end

	icon:Hide()
	return icon
end

function QuestTogether:RememberNameplateBaseHealthColor(unitFrame)
	if not unitFrame or not unitFrame.healthBar then
		return
	end

	local unitGuid = nil
	if unitFrame.unit then
		local resolvedGuid = self:GetNameplateUnitGuid(unitFrame.unit)
		if type(resolvedGuid) == "string" and resolvedGuid ~= "" then
			unitGuid = resolvedGuid
		end
	end

	local cachedBase = self.nameplateBaseHealthColorByUnitFrame[unitFrame]
	if cachedBase then
		-- If we cannot currently resolve identity, preserve the first captured baseline.
		if not unitGuid then
			return
		end
		if cachedBase.unitGuid == unitGuid then
			return
		end
	end

	local red, green, blue = unitFrame.healthBar:GetStatusBarColor()
	if type(red) ~= "number" or type(green) ~= "number" or type(blue) ~= "number" then
		return
	end

	self.nameplateBaseHealthColorByUnitFrame[unitFrame] = {
		r = red,
		g = green,
		b = blue,
		unitGuid = unitGuid,
	}
end

function QuestTogether:ApplyQuestTintToNameplate(unitFrame)
	if not unitFrame or not unitFrame.healthBar then
		return
	end

	self:RememberNameplateBaseHealthColor(unitFrame)

	local color = self:GetNameplateQuestHealthColor()
	unitFrame.healthBar:SetStatusBarColor(color.r, color.g, color.b)
end

function QuestTogether:RestoreNameplateHealthColor(unitFrame)
	if not unitFrame or not unitFrame.healthBar then
		return
	end

	local cachedBase = self.nameplateBaseHealthColorByUnitFrame[unitFrame]
	if not cachedBase then
		return
	end

	if cachedBase.unitGuid then
		local currentGuid = nil
		if unitFrame.unit then
			local resolvedGuid = self:GetNameplateUnitGuid(unitFrame.unit)
			if type(resolvedGuid) == "string" and resolvedGuid ~= "" then
				currentGuid = resolvedGuid
			end
		end
		if cachedBase.unitGuid ~= currentGuid then
			-- Frame got reused for a different unit; never restore stale color onto it.
			self.nameplateBaseHealthColorByUnitFrame[unitFrame] = nil
			return
		end
	end

	if type(cachedBase.r) ~= "number" or type(cachedBase.g) ~= "number" or type(cachedBase.b) ~= "number" then
		-- Defensive guard for malformed cache entries.
		self.nameplateBaseHealthColorByUnitFrame[unitFrame] = nil
		return
	end

	unitFrame.healthBar:SetStatusBarColor(cachedBase.r, cachedBase.g, cachedBase.b)
	self.nameplateBaseHealthColorByUnitFrame[unitFrame] = nil
end

function QuestTogether:RefreshNameplateHealthTint(namePlateFrameBase, isQuestObjective)
	if not namePlateFrameBase or not namePlateFrameBase.UnitFrame then
		return
	end

	local unitFrame = namePlateFrameBase.UnitFrame
	local shouldTint = self.isEnabled and self:GetOption("nameplateQuestHealthColorEnabled") and isQuestObjective
	if shouldTint then
		self:ApplyQuestTintToNameplate(unitFrame)
	else
		self:RestoreNameplateHealthColor(unitFrame)
	end
end

function QuestTogether:RefreshNameplateIcon(namePlateFrameBase)
	if not namePlateFrameBase or not namePlateFrameBase.UnitFrame then
		return
	end

	local unitToken = (namePlateFrameBase.GetUnit and namePlateFrameBase:GetUnit()) or nil
	local unitFrame = namePlateFrameBase.UnitFrame
	local icon = EnsureQuestIcon(unitFrame)

	if not icon then
		return
	end

	local isQuestObjective = self:IsQuestObjectiveNameplate(unitToken, unitFrame)
	local shouldShow = self:GetOption("nameplateQuestIconEnabled") and isQuestObjective
	if unitToken then
		self.nameplateQuestStateByUnitToken[unitToken] = isQuestObjective and true or false
	end
	self:RefreshNameplateHealthTint(namePlateFrameBase, isQuestObjective)

	if shouldShow then
		icon:Show()
	else
		icon:Hide()
	end
end

function QuestTogether:HideNameplateIcon(namePlateFrameBase)
	if not namePlateFrameBase or not namePlateFrameBase.UnitFrame then
		return
	end

	local icon = self.nameplateIconByUnitFrame[namePlateFrameBase.UnitFrame]
	if icon then
		icon:Hide()
	end
	self:RestoreNameplateHealthColor(namePlateFrameBase.UnitFrame)
end

function QuestTogether:ForEachVisibleNamePlate(callback)
	if type(callback) ~= "function" or not C_NamePlate or not C_NamePlate.GetNamePlates then
		return
	end

	for _, frame in pairs(C_NamePlate.GetNamePlates(false)) do
		callback(frame)
	end
end

function QuestTogether:RefreshNameplateAugmentation()
	self:ForEachVisibleNamePlate(function(frame)
		self:RefreshNameplateIcon(frame)
	end)
end

function QuestTogether:OnNameplateAdded(unitToken)
	if not self.isEnabled then
		return
	end

	if not self:IsNameplateUnitToken(unitToken) then
		return
	end

	local unitGuid = self:GetNameplateUnitGuid(unitToken)
	if unitGuid and self.nameplateQuestObjectiveCache[unitGuid] then
		self.nameplateQuestObjectiveCache[unitGuid] = nil
	end
	self.nameplateQuestStateByUnitToken[unitToken] = nil

	local namePlateFrameBase = C_NamePlate.GetNamePlateForUnit(unitToken, false)
	if namePlateFrameBase then
		self:RefreshNameplateIcon(namePlateFrameBase)
	end
end

function QuestTogether:OnNameplateRemoved(unitToken)
	if not self:IsNameplateUnitToken(unitToken) then
		return
	end

	local unitGuid = self:GetNameplateUnitGuid(unitToken)
	if unitGuid and self.nameplateQuestObjectiveCache[unitGuid] then
		self.nameplateQuestObjectiveCache[unitGuid] = nil
	end
	self.nameplateQuestStateByUnitToken[unitToken] = nil

	local namePlateFrameBase = C_NamePlate.GetNamePlateForUnit(unitToken, false)
	if namePlateFrameBase then
		self:HideNameplateIcon(namePlateFrameBase)
	end
end

function QuestTogether:TryInstallNameplateHooks()
	if self.nameplateHooksInstalled then
		return
	end

	if type(hooksecurefunc) ~= "function" then
		return
	end

	if
		not self.nameplateDriverHookInstalled
		and type(NamePlateDriverMixin) == "table"
		and type(NamePlateDriverMixin.OnNamePlateAdded) == "function"
	then
		hooksecurefunc(NamePlateDriverMixin, "OnNamePlateAdded", function(_, unitToken)
			QuestTogether:OnNameplateAdded(unitToken)
		end)
		hooksecurefunc(NamePlateDriverMixin, "OnNamePlateRemoved", function(_, unitToken)
			QuestTogether:OnNameplateRemoved(unitToken)
		end)
		self.nameplateDriverHookInstalled = true
	end

	if not self.nameplateHealthColorHookInstalled and type(CompactUnitFrame_UpdateHealthColor) == "function" then
		hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(frame)
			if not frame or type(frame.unit) ~= "string" then
				return
			end
			if not QuestTogether:IsNameplateUnitToken(frame.unit) then
				return
			end

			local isQuestObjective = QuestTogether.nameplateQuestStateByUnitToken[frame.unit]
			if isQuestObjective == nil then
				isQuestObjective = QuestTogether:IsQuestObjectiveNameplate(frame.unit, frame)
				QuestTogether.nameplateQuestStateByUnitToken[frame.unit] = isQuestObjective and true or false
			end

			local shouldTint = QuestTogether.isEnabled
				and QuestTogether:GetOption("nameplateQuestHealthColorEnabled")
				and isQuestObjective
			if shouldTint then
				QuestTogether:ApplyQuestTintToNameplate(frame)
			else
				QuestTogether:RestoreNameplateHealthColor(frame)
			end
		end)
		self.nameplateHealthColorHookInstalled = true
	end

	self.nameplateHooksInstalled = self.nameplateDriverHookInstalled and self.nameplateHealthColorHookInstalled
end

function QuestTogether:EnableNameplateAugmentation()
	if not self.nameplateEventFrame then
		self.nameplateEventFrame = CreateFrame("Frame")
		self.nameplateRegisteredEvents = self.nameplateRegisteredEvents or {}
		self.nameplateEventFrame:SetScript("OnEvent", function(_, eventName, ...)
			if eventName == "NAME_PLATE_UNIT_ADDED" then
				self:OnNameplateAdded(...)
			elseif eventName == "NAME_PLATE_UNIT_REMOVED" then
				self:OnNameplateRemoved(...)
				elseif
					eventName == "QUEST_LOG_UPDATE"
					or eventName == "PLAYER_ENTERING_WORLD"
					or eventName == "QUEST_REMOVED"
					or eventName == "QUEST_ACCEPTED"
					or eventName == "QUEST_ACCEPT_CONFIRM"
					or eventName == "QUEST_COMPLETE"
					or eventName == "QUEST_POI_UPDATE"
					or eventName == "QUEST_DETAIL"
					or eventName == "QUEST_FINISHED"
					or eventName == "QUEST_GREETING"
			then
				self:RebuildNameplateQuestTitleCache()
				self:ClearNameplateQuestObjectiveCache()
				self:RefreshNameplateAugmentation()
			elseif eventName == "UNIT_QUEST_LOG_CHANGED" then
				local unitToken = ...
				if unitToken == "player" then
					self:RebuildNameplateQuestTitleCache()
					self:ClearNameplateQuestObjectiveCache()
					self:RefreshNameplateAugmentation()
				end
			end
		end)
	end

	local function RegisterNameplateEvent(addon, eventName)
		local ok = pcall(addon.nameplateEventFrame.RegisterEvent, addon.nameplateEventFrame, eventName)
		if ok then
			addon.nameplateRegisteredEvents[eventName] = true
		else
			addon.nameplateRegisteredEvents[eventName] = nil
		end
	end

	self:TryInstallNameplateHooks()
	self:RebuildNameplateQuestTitleCache()
	self:ClearNameplateQuestObjectiveCache()
	RegisterNameplateEvent(self, "NAME_PLATE_UNIT_ADDED")
	RegisterNameplateEvent(self, "NAME_PLATE_UNIT_REMOVED")
	RegisterNameplateEvent(self, "QUEST_LOG_UPDATE")
	RegisterNameplateEvent(self, "QUEST_REMOVED")
	RegisterNameplateEvent(self, "QUEST_ACCEPTED")
	RegisterNameplateEvent(self, "QUEST_ACCEPT_CONFIRM")
	RegisterNameplateEvent(self, "QUEST_COMPLETE")
	RegisterNameplateEvent(self, "QUEST_POI_UPDATE")
	RegisterNameplateEvent(self, "QUEST_DETAIL")
	RegisterNameplateEvent(self, "QUEST_FINISHED")
	RegisterNameplateEvent(self, "QUEST_GREETING")
	RegisterNameplateEvent(self, "UNIT_QUEST_LOG_CHANGED")
	RegisterNameplateEvent(self, "PLAYER_ENTERING_WORLD")
	self:RefreshNameplateAugmentation()
end

function QuestTogether:DisableNameplateAugmentation()
	if not self.nameplateEventFrame then
		return
	end

	for eventName in pairs(self.nameplateRegisteredEvents or {}) do
		pcall(self.nameplateEventFrame.UnregisterEvent, self.nameplateEventFrame, eventName)
	end
	if self.nameplateRegisteredEvents then
		wipe(self.nameplateRegisteredEvents)
	end

	-- Hide our icon overlays and clear cached quest objective state.
	wipe(self.nameplateQuestStateByUnitToken)
	self:ForEachVisibleNamePlate(function(frame)
		self:HideNameplateIcon(frame)
	end)
	wipe(self.nameplateBaseHealthColorByUnitFrame)
end
