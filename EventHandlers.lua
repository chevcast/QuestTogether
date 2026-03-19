--[[
QuestTogether Event Handlers

Responsibilities in this file:
- Detect local quest changes.
- Publish lightweight announcement events.
- Display local announcements according to local options.
]]

local QuestTogether = _G.QuestTogether

local function SafeText(value, fallback)
	return QuestTogether:SafeToString(value, fallback or "")
end

local function SafeMatch(text, pattern)
	local safeText = SafeText(text, "")
	if safeText == "" then
		return nil
	end

	local ok, first, second = pcall(string.match, safeText, pattern)
	if not ok then
		return nil
	end

	return first, second
end

local function NormalizeQuestId(addon, questId)
	if not addon then
		return nil
	end

	if addon.NormalizeQuestID then
		return addon:NormalizeQuestID(questId)
	end

	local numericQuestId = addon.SafeToNumber and addon:SafeToNumber(questId) or nil
	if not numericQuestId or numericQuestId <= 0 then
		return nil
	end
	return math.floor(numericQuestId + 0.5)
end

local function CountKeys(tableValue)
	local count = 0
	for _ in pairs(tableValue or {}) do
		count = count + 1
	end
	return count
end

local function NormalizeBooleanLike(addon, value)
	if value == nil then
		return nil
	end
	if addon and addon.IsSecretValue and addon:IsSecretValue(value) then
		return nil
	end
	if type(value) == "boolean" then
		return value
	end
	if addon and addon.SafeToNumber then
		local numericValue = addon:SafeToNumber(value)
		if numericValue ~= nil then
			return numericValue ~= 0
		end
	end
	if type(value) == "string" then
		local normalized = value:lower()
		if normalized == "true" then
			return true
		end
		if normalized == "false" then
			return false
		end
	end
	return nil
end

local function BuildLocalTaskQuestSet(addon)
	if not addon or not addon.API or type(addon.API.GetLocalTaskQuests) ~= "function" then
		return nil
	end

	local questIds = addon.API.GetLocalTaskQuests()
	if type(questIds) ~= "table" then
		return nil
	end

	local questIdSet = {}
	local addedAny = false
	for index = 1, #questIds do
		local normalizedQuestId = NormalizeQuestId(addon, questIds[index])
		if normalizedQuestId then
			questIdSet[normalizedQuestId] = true
			addedAny = true
		end
	end

	if not addedAny then
		return nil
	end

	return questIdSet
end

local function BuildTaskAreaContext(addon, taskType)
	local localTaskQuestSet = BuildLocalTaskQuestSet(addon)
	-- Do not read C_TaskQuest/C_QuestLog map task arrays here.
	-- Those tables can taint Blizzard map pin update paths such as SharedMapPoiTemplates.
	return localTaskQuestSet, nil
end

local function IsWorldMapVisible(addon)
	if not (addon and addon.API and type(addon.API.IsWorldMapVisible) == "function") then
		return false
	end
	return addon.API.IsWorldMapVisible() and true or false
end

local function BuildQuestLogQuestInfoIndex(addon)
	local questInfoByQuestId = {}

	if not (addon and addon.API and addon.API.GetNumQuestLogEntries and addon.API.GetQuestLogInfo) then
		return questInfoByQuestId
	end

	local totalEntries = addon:SafeToNumber(addon.API.GetNumQuestLogEntries()) or 0
	for entryIndex = 1, totalEntries do
		local questInfo = addon.API.GetQuestLogInfo(entryIndex)
		if questInfo and not questInfo.isHeader and not questInfo.isHidden then
			local normalizedQuestId = NormalizeQuestId(addon, questInfo.questID)
			if normalizedQuestId then
				if not questInfoByQuestId[normalizedQuestId] then
					questInfoByQuestId[normalizedQuestId] = questInfo
				end
			end
		end
	end

	return questInfoByQuestId
end

local function BuildTaskAreaCandidateQuestIds(addon, taskType, questInfoByQuestId, localTaskQuestSet, mapTaskQuestSet)
	local candidateQuestIds = {}

	for normalizedQuestId in pairs(questInfoByQuestId or {}) do
		candidateQuestIds[normalizedQuestId] = true
	end

	for normalizedQuestId in pairs(localTaskQuestSet or {}) do
		candidateQuestIds[normalizedQuestId] = true
	end

	if taskType == "world" then
		return candidateQuestIds
	end

	for normalizedQuestId in pairs(mapTaskQuestSet or {}) do
		candidateQuestIds[normalizedQuestId] = true
	end

	return candidateQuestIds
end

local function ResolveWorldQuestAreaSignals(addon, questInfo, normalizedQuestId, localTaskQuestSet)
	local taskInfoInArea = nil
	local taskInfoOnMap = nil
	if addon and addon.API and addon.API.GetTaskInfo then
		taskInfoInArea, taskInfoOnMap = addon.API.GetTaskInfo(normalizedQuestId)
		taskInfoInArea = NormalizeBooleanLike(addon, taskInfoInArea)
		taskInfoOnMap = NormalizeBooleanLike(addon, taskInfoOnMap)
	end

	local localTaskInArea = nil
	if type(localTaskQuestSet) == "table" and localTaskQuestSet[normalizedQuestId] == true then
		localTaskInArea = true
	end

	local taskActiveRaw = taskInfoInArea
	if addon and addon.API and addon.API.IsTaskQuestActive then
		local isTaskActiveFallback = NormalizeBooleanLike(addon, addon.API.IsTaskQuestActive(normalizedQuestId))
		if taskActiveRaw == nil then
			taskActiveRaw = isTaskActiveFallback
		end
	end

	local mapFlags = questInfo and (questInfo.isOnMap == true or questInfo.hasLocalPOI == true) and true or false
	local mapFallback = nil
	if addon and addon.API and addon.API.IsQuestOnMap then
		mapFallback = NormalizeBooleanLike(addon, addon.API.IsQuestOnMap(normalizedQuestId))
	end

	local hasMapPresence = (localTaskInArea == true) or (taskInfoOnMap == true) or mapFlags or (mapFallback == true)

	local taskActiveForArea = taskActiveRaw
	if taskActiveForArea == true and not hasMapPresence then
		taskActiveForArea = nil
	end

	local areaActive = localTaskInArea == true and taskInfoInArea == true

	local canUseTaskActiveWorldFallback = taskActiveRaw == true and hasMapPresence

	return {
		taskInfoInArea = taskInfoInArea,
		taskInfoOnMap = taskInfoOnMap,
		localTaskInArea = localTaskInArea,
		taskActiveRaw = taskActiveRaw,
		taskActiveForArea = taskActiveForArea,
		mapFlags = mapFlags,
		mapFallback = mapFallback,
		hasMapPresence = hasMapPresence,
		areaActive = areaActive,
		canUseTaskActiveWorldFallback = canUseTaskActiveWorldFallback,
	}
end

local function ResolveQuestAreaSignals(addon, taskType, questInfo, normalizedQuestId, localTaskQuestSet, mapTaskQuestSet)
	if taskType == "world" then
		return ResolveWorldQuestAreaSignals(addon, questInfo, normalizedQuestId, localTaskQuestSet)
	end

	local taskInfoInArea = nil
	local taskInfoOnMap = nil
	if addon and addon.API and addon.API.GetTaskInfo then
		taskInfoInArea, taskInfoOnMap = addon.API.GetTaskInfo(normalizedQuestId)
		taskInfoInArea = NormalizeBooleanLike(addon, taskInfoInArea)
		taskInfoOnMap = NormalizeBooleanLike(addon, taskInfoOnMap)
	end

	local localTaskInArea = nil
	if type(localTaskQuestSet) == "table" and localTaskQuestSet[normalizedQuestId] == true then
		localTaskInArea = true
	end

	local mapTaskInArea = nil
	if type(mapTaskQuestSet) == "table" and mapTaskQuestSet[normalizedQuestId] == true then
		mapTaskInArea = true
	end

	local taskActiveRaw = taskInfoInArea
	if taskActiveRaw == nil and localTaskInArea == true then
		taskActiveRaw = true
	end
	if taskActiveRaw == nil and mapTaskInArea == true then
		taskActiveRaw = true
	end
	if addon and addon.API and addon.API.IsTaskQuestActive then
		local isTaskActiveFallback = NormalizeBooleanLike(addon, addon.API.IsTaskQuestActive(normalizedQuestId))
		if taskActiveRaw == nil then
			taskActiveRaw = isTaskActiveFallback
		end
	end

	local mapFlags = questInfo and (questInfo.isOnMap == true or questInfo.hasLocalPOI == true) and true or false
	local mapFallback = nil
	if addon and addon.API and addon.API.IsQuestOnMap then
		mapFallback = NormalizeBooleanLike(addon, addon.API.IsQuestOnMap(normalizedQuestId))
	end

	local hasMapPresence = (localTaskInArea == true)
		or (mapTaskInArea == true)
		or (taskInfoOnMap == true)
		or mapFlags
		or (mapFallback == true)

	local taskActiveForArea = taskActiveRaw
	if taskActiveForArea == true and not hasMapPresence then
		taskActiveForArea = nil
	end

	local areaActive = nil
	if type(taskInfoInArea) == "boolean" then
		areaActive = taskInfoInArea
	elseif localTaskInArea == true then
		areaActive = true
	elseif mapTaskInArea == true then
		areaActive = true
	elseif type(taskInfoOnMap) == "boolean" then
		areaActive = taskInfoOnMap
	elseif type(taskActiveForArea) == "boolean" then
		areaActive = taskActiveForArea
	else
		areaActive = mapFlags or (mapFallback == true)
	end

	local canUseTaskActiveWorldFallback = taskActiveRaw == true and hasMapPresence

	return {
		taskInfoInArea = taskInfoInArea,
		taskInfoOnMap = taskInfoOnMap,
		localTaskInArea = localTaskInArea,
		mapTaskInArea = mapTaskInArea,
		taskActiveRaw = taskActiveRaw,
		taskActiveForArea = taskActiveForArea,
		mapFlags = mapFlags,
		mapFallback = mapFallback,
		hasMapPresence = hasMapPresence,
		areaActive = areaActive,
		canUseTaskActiveWorldFallback = canUseTaskActiveWorldFallback,
	}
end

local function EvaluateTaskAreaQuestCandidate(addon, taskType, normalizedQuestId, questInfo, localTaskQuestSet, mapTaskQuestSet)
	local title = addon:GetQuestTitle(normalizedQuestId, questInfo)
	local explicitWorld = questInfo and questInfo.isWorldQuest == true or false
	local fallbackWorld = addon:IsWorldQuest(normalizedQuestId)
	local isWorldQuest = explicitWorld or fallbackWorld

	local taskFlag = questInfo and questInfo.isTask == true or false
	local bonusFallback = addon:IsBonusObjective(normalizedQuestId)
	local isTask = taskFlag or isWorldQuest or bonusFallback

	local areaSignals = ResolveQuestAreaSignals(addon, taskType, questInfo, normalizedQuestId, localTaskQuestSet, mapTaskQuestSet)
	local isWorldQuestByActiveTaskFallback = false
	if not isWorldQuest and areaSignals.canUseTaskActiveWorldFallback and not bonusFallback then
		isWorldQuest = true
		isWorldQuestByActiveTaskFallback = true
	end
	local shouldPromoteToTask = areaSignals.areaActive == true
	if taskType ~= "world" and areaSignals.taskActiveForArea == true then
		shouldPromoteToTask = true
	end
	if not isTask and shouldPromoteToTask then
		isTask = true
	end

	local matchesType = false
	if taskType == "world" then
		matchesType = isWorldQuest and true or false
	elseif taskType == "bonus" then
		matchesType = isWorldQuest ~= true
	end

	return {
		title = title,
		explicitWorld = explicitWorld,
		fallbackWorld = fallbackWorld,
		isWorldQuestByActiveTaskFallback = isWorldQuestByActiveTaskFallback,
		isWorldQuest = isWorldQuest,
		taskFlag = taskFlag,
		bonusFallback = bonusFallback,
		isTask = isTask,
		matchesType = matchesType,
		include = isTask and areaSignals.areaActive == true and matchesType,
		areaSignals = areaSignals,
	}
end

local function SortedQuestIdKeys(tableValue)
	local keys = {}
	for questId in pairs(tableValue or {}) do
		keys[#keys + 1] = questId
	end
	table.sort(keys, function(a, b)
		local aNum = QuestTogether:SafeToNumber(a)
		local bNum = QuestTogether:SafeToNumber(b)
		if aNum ~= nil and bNum ~= nil then
			return aNum < bNum
		end
		return SafeText(a, "") < SafeText(b, "")
	end)
	return keys
end

local function DrainQueuedQuestLogTasks(addon)
	if not addon then
		return 0
	end

	local queuedTasks = addon.onQuestLogUpdate
	if type(queuedTasks) ~= "table" or #queuedTasks == 0 then
		addon.onQuestLogUpdate = addon.onQuestLogUpdate or {}
		return 0
	end

	addon.onQuestLogUpdate = {}
	for index = 1, #queuedTasks do
		local taskFn = queuedTasks[index]
		if type(taskFn) == "function" then
			taskFn()
		end
	end

	return #queuedTasks
end

local function ParseObjectiveProgressFromText(objectiveText)
	if type(objectiveText) ~= "string" or objectiveText == "" then
		return nil
	end

	local amountCurrent = SafeMatch(objectiveText, "(%d+)%s*/%s*%d+")
	if amountCurrent then
		return QuestTogether:SafeToNumber(amountCurrent)
	end

	local percent = SafeMatch(objectiveText, "(%d+%.?%d*)%%")
	if percent then
		return QuestTogether:SafeToNumber(percent)
	end

	return nil
end

local function ResolveObjectiveProgressValue(objectiveText, currentValue)
	local numericValue = QuestTogether:SafeToNumber(currentValue)
	if numericValue ~= nil then
		return numericValue
	end
	return ParseObjectiveProgressFromText(objectiveText)
end

local function DidObjectiveProgressIncrease(oldText, oldValue, newText, newValue)
	local previousValue = QuestTogether:SafeToNumber(oldValue)
	if previousValue == nil then
		previousValue = ParseObjectiveProgressFromText(oldText)
	end

	local currentValue = ResolveObjectiveProgressValue(newText, newValue)
	if previousValue == nil or currentValue == nil then
		return false
	end

	return currentValue > previousValue
end

function QuestTogether:PickRandomCompletionEmote()
	if #self.completionEmotes == 0 then
		return "cheer"
	end
	local randomIndex = self.API.Random(1, #self.completionEmotes)
	return self.completionEmotes[randomIndex]
end

function QuestTogether:PlayLocalCompletionEmote(emoteToken)
	if not self:GetOption("emoteOnQuestCompletion") then
		self:Debug("Skipping local emote because emoteOnQuestCompletion is disabled.", "quest")
		return false
	end
	self:Debugf("quest", "Playing completion emote token=%s", SafeText(emoteToken, "<none>"))
	self.API.DoEmote(emoteToken, self:GetPlayerName())
	return true
end

function QuestTogether:HandleQuestCompleted(questTitle, questId, extraData)
	self:Debugf("quest", "Quest completed questId=%s title=%s", SafeText(questId, "?"), SafeText(questTitle, "Unknown"))
	local completionEmote = self:PickRandomCompletionEmote()
	local announcementExtraData = {}
	if type(extraData) == "table" then
		for key, value in pairs(extraData) do
			announcementExtraData[key] = value
		end
	end
	announcementExtraData.emoteToken = completionEmote
	if questId and self:IsWorldQuest(questId) then
		self:PublishAnnouncementEvent(
			"WORLD_QUEST_COMPLETED",
			"World Quest Completed: " .. SafeText(questTitle, "Unknown"),
			questId,
			announcementExtraData
		)
	elseif questId and self:IsBonusObjective(questId) then
		self:PublishAnnouncementEvent(
			"BONUS_OBJECTIVE_COMPLETED",
			"Bonus Objective Completed: " .. SafeText(questTitle, "Unknown"),
			questId,
			announcementExtraData
		)
	else
		self:PublishAnnouncementEvent(
			"QUEST_COMPLETED",
			"Quest Completed: " .. SafeText(questTitle, "Unknown"),
			questId,
			announcementExtraData
		)
	end

	self:PlayLocalCompletionEmote(completionEmote)
end

function QuestTogether:HandleQuestRemoved(questTitle)
	self:Debugf("quest", "Quest removed title=%s", SafeText(questTitle, "Unknown"))
	self:PublishAnnouncementEvent("QUEST_REMOVED", "Quest Removed: " .. SafeText(questTitle, "Unknown"))
end

function QuestTogether:ShouldPublishObjectiveProgress(currentValue)
	return currentValue and currentValue > 0
end

function QuestTogether:GetTaskAnnouncementType(questId)
	if self:IsWorldQuest(questId) then
		return "world"
	end
	if self:IsBonusObjective(questId) then
		return "bonus"
	end
	return nil
end

function QuestTogether:BuildTrackedQuestRemovalData(questId)
	questId = NormalizeQuestId(self, questId)
	if not questId then
		return nil
	end

	local tracker = self:GetPlayerTracker()
	local trackedQuest = tracker[questId]
	if not trackedQuest then
		return nil
	end

	local iconAsset, iconKind = self:GetTrackedQuestAnnouncementIcon(trackedQuest)
	return {
		questId = questId,
		title = trackedQuest.title or ("Quest " .. SafeText(questId, "?")),
		taskAnnouncementType = trackedQuest.taskAnnouncementType or self:GetTaskAnnouncementType(questId),
		iconAsset = iconAsset,
		iconKind = iconKind,
	}
end

function QuestTogether:BuildTrackedQuestCompletionData(questId)
	questId = NormalizeQuestId(self, questId)
	if not questId then
		return nil
	end

	local completionData = self:BuildTrackedQuestRemovalData(questId) or {
		questId = questId,
		title = self:GetQuestTitle(questId),
		taskAnnouncementType = self:GetTaskAnnouncementType(questId),
	}

	local iconAsset, iconKind = self:GetAnnouncementIconInfo("QUEST_READY_TO_TURN_IN", questId)
	if type(iconAsset) == "string" and iconAsset ~= "" then
		completionData.iconAsset = iconAsset
		completionData.iconKind = iconKind
	end

	return completionData
end

function QuestTogether:ClearTrackedQuestState(questId)
	questId = NormalizeQuestId(self, questId)
	if not questId then
		return
	end

	local tracker = self:GetPlayerTracker()
	self.worldQuestAreaStateByQuestID[questId] = nil
	self.bonusObjectiveAreaStateByQuestID[questId] = nil
	tracker[questId] = nil
	self.pendingQuestRemovals[questId] = nil
	self.questsCompleted[questId] = nil
	self:RefreshTaskAreaStates(true)
end

function QuestTogether:ResolvePendingQuestRemoval(questId)
	questId = NormalizeQuestId(self, questId)
	if not questId then
		return false
	end

	local removalData = self.pendingQuestRemovals[questId]
	if not removalData then
		return false
	end

	local completionData = self.questsCompleted[questId]
	local completed = completionData ~= nil
	local questTitle = removalData.title or (completionData and completionData.title) or ("Quest " .. SafeText(questId, "?"))
	local iconAsset = (completionData and completionData.iconAsset) or removalData.iconAsset
	local iconKind = (completionData and completionData.iconKind) or removalData.iconKind

	self:Debugf(
		"quest",
		"Resolving removal questId=%s title=%s taskType=%s completed=%s",
		SafeText(questId, "?"),
		SafeText(questTitle, "Unknown"),
		SafeText(removalData.taskAnnouncementType, ""),
		SafeText(completed, "false")
	)

	if completed then
		self:HandleQuestCompleted(questTitle, questId, {
			iconAsset = iconAsset,
			iconKind = iconKind,
		})
	elseif not removalData.taskAnnouncementType then
		self:PublishAnnouncementEvent("QUEST_REMOVED", "Quest Removed: " .. SafeText(questTitle, "Unknown"), questId)
	end

	self:ClearTrackedQuestState(questId)
	return true
end

function QuestTogether:HandleGroupRosterChanged(reason)
	local previousFingerprint = self:GetPartyRosterFingerprint()
	if self.RefreshPartyRoster then
		self:RefreshPartyRoster()
	end
	local newFingerprint = self:GetPartyRosterFingerprint()
	self:Debugf(
		"group",
		"HandleGroupRosterChanged reason=%s changed=%s prev=%s new=%s",
		SafeText(reason, ""),
		SafeText(previousFingerprint ~= newFingerprint, "false"),
		SafeText(previousFingerprint, ""),
		SafeText(newFingerprint, "")
	)
end

-- Snapshot active task quests from sanitized quest-log rows.
-- World quest area membership intentionally mirrors Blizzard's tracker behavior more closely:
-- candidate quests come from quest-log rows plus GetTasksTable(), and inclusion requires the
-- local task list and GetTaskInfo(...).isInArea to agree before we announce entry/leave.
-- We only copy scalar quest IDs from Blizzard task tables and never retain/mutate their rows.
function QuestTogether:GetTaskAreaSnapshot(taskType)
	local activeByQuestId = {}

	if self.API and self.API.GetNumQuestLogEntries and self.API.GetQuestLogInfo then
		local localTaskQuestSet, mapTaskQuestSet = BuildTaskAreaContext(self, taskType)
		local questInfoByQuestId = BuildQuestLogQuestInfoIndex(self)
		local candidateQuestIds =
			BuildTaskAreaCandidateQuestIds(self, taskType, questInfoByQuestId, localTaskQuestSet, mapTaskQuestSet)
		for _, normalizedQuestId in ipairs(SortedQuestIdKeys(candidateQuestIds)) do
			local questInfo = questInfoByQuestId[normalizedQuestId]
			local evaluation =
				EvaluateTaskAreaQuestCandidate(self, taskType, normalizedQuestId, questInfo, localTaskQuestSet, mapTaskQuestSet)
			if evaluation.include then
				activeByQuestId[normalizedQuestId] = evaluation.title
			end
		end
	end

	return activeByQuestId
end

function QuestTogether:GetActiveWorldQuestAreaSnapshot()
	return self:GetTaskAreaSnapshot("world")
end

function QuestTogether:GetActiveBonusObjectiveAreaSnapshot()
	return self:GetTaskAreaSnapshot("bonus")
end

function QuestTogether:RefreshTaskAreaState(taskType, shouldAnnounce)
	local configByType = {
		world = {
			stateKey = "worldQuestAreaStateByQuestID",
			snapshotMethod = "GetActiveWorldQuestAreaSnapshot",
			enterEvent = "WORLD_QUEST_ENTERED",
			leftEvent = "WORLD_QUEST_LEFT",
			enterPrefix = "World Quest Entered: ",
			leftPrefix = "Left World Quest: ",
			debugLabel = "World quest",
		},
		bonus = {
			stateKey = "bonusObjectiveAreaStateByQuestID",
			snapshotMethod = "GetActiveBonusObjectiveAreaSnapshot",
			enterEvent = "BONUS_OBJECTIVE_ENTERED",
			leftEvent = "BONUS_OBJECTIVE_LEFT",
			enterPrefix = "Bonus Objective Entered: ",
			leftPrefix = "Left Bonus Objective: ",
			debugLabel = "Bonus objective",
		},
	}

	local config = configByType[taskType]
	if not config or type(self[config.snapshotMethod]) ~= "function" then
		return
	end

	local previousStateRaw = self[config.stateKey] or {}
	local currentStateRaw = self[config.snapshotMethod](self) or {}
	local previousState = {}
	local currentState = {}

	for questId, questTitle in pairs(previousStateRaw) do
		local normalizedQuestId = NormalizeQuestId(self, questId)
		if normalizedQuestId then
			previousState[normalizedQuestId] = questTitle
		end
	end

	for questId, questTitle in pairs(currentStateRaw) do
		local normalizedQuestId = NormalizeQuestId(self, questId)
		if normalizedQuestId then
			currentState[normalizedQuestId] = questTitle
		end
	end

	self:Debugf(
		"quest",
		"RefreshTaskAreaState type=%s announce=%s prev=%d curr=%d",
		SafeText(taskType, ""),
		SafeText(shouldAnnounce, "false"),
		CountKeys(previousState),
		CountKeys(currentState)
	)
	for questId, questTitle in pairs(currentState) do
		if not previousState[questId] and shouldAnnounce then
			self:Debugf(
				"quest",
				"%s area entered questId=%s title=%s",
				SafeText(config.debugLabel, ""),
				SafeText(questId, "?"),
				SafeText(questTitle, "Unknown")
			)
			self:PublishAnnouncementEvent(config.enterEvent, config.enterPrefix .. SafeText(questTitle, "Unknown"), questId)
		end
	end

	for questId, previousTitle in pairs(previousState) do
		if not currentState[questId] then
			local wasCompleted = self.questsCompleted[questId] ~= nil
			if shouldAnnounce and not wasCompleted then
				local questTitle = previousTitle or self:GetQuestTitle(questId)
				self:Debugf(
					"quest",
					"%s area left questId=%s title=%s",
					SafeText(config.debugLabel, ""),
					SafeText(questId, "?"),
					SafeText(questTitle, "Unknown")
				)
				self:PublishAnnouncementEvent(config.leftEvent, config.leftPrefix .. SafeText(questTitle, "Unknown"), questId)
			end
		end
	end

	self[config.stateKey] = currentState
end

function QuestTogether:RefreshWorldQuestAreaState(shouldAnnounce)
	self:RefreshTaskAreaState("world", shouldAnnounce)
end

function QuestTogether:RefreshBonusObjectiveAreaState(shouldAnnounce)
	self:RefreshTaskAreaState("bonus", shouldAnnounce)
end

function QuestTogether:ScheduleDeferredTaskAreaRefreshAfterMapHidden()
	if self.taskAreaMapVisibilityRetryPending then
		return
	end

	local delayFn = self.API and self.API.Delay
	if type(delayFn) ~= "function" then
		return
	end

	self.taskAreaMapVisibilityRetryPending = true
	delayFn(0.2, function()
		QuestTogether.taskAreaMapVisibilityRetryPending = false
		if not QuestTogether.isEnabled then
			return
		end
		if not QuestTogether.pendingTaskAreaRefreshAfterMapHidden then
			return
		end
		if IsWorldMapVisible(QuestTogether) then
			QuestTogether:ScheduleDeferredTaskAreaRefreshAfterMapHidden()
			return
		end

		local shouldAnnounce = QuestTogether.pendingTaskAreaRefreshAfterMapHiddenShouldAnnounce and true or false
		QuestTogether.pendingTaskAreaRefreshAfterMapHidden = false
		QuestTogether.pendingTaskAreaRefreshAfterMapHiddenShouldAnnounce = false
		QuestTogether:RefreshTaskAreaStates(shouldAnnounce)
	end)
end

function QuestTogether:RefreshTaskAreaStates(shouldAnnounce)
	local inCombatLockdown = self.API and self.API.InCombatLockdown and self.API.InCombatLockdown()
	if inCombatLockdown then
		self.pendingTaskAreaRefresh = true
		if shouldAnnounce then
			self.pendingTaskAreaRefreshShouldAnnounce = true
		end
		self:Debugf("quest", "Deferring task area refresh during combat announce=%s", SafeText(shouldAnnounce, "false"))
		return false
	end

	if IsWorldMapVisible(self) then
		self.pendingTaskAreaRefreshAfterMapHidden = true
		if shouldAnnounce then
			self.pendingTaskAreaRefreshAfterMapHiddenShouldAnnounce = true
		end
		self:Debugf(
			"quest",
			"Deferring task area refresh while world map is visible announce=%s",
			SafeText(shouldAnnounce, "false")
		)
		self:ScheduleDeferredTaskAreaRefreshAfterMapHidden()
		return false
	end

	local resolvedShouldAnnounce = shouldAnnounce
	if self.pendingTaskAreaRefreshShouldAnnounce or self.pendingTaskAreaRefreshAfterMapHiddenShouldAnnounce then
		resolvedShouldAnnounce = true
	end
	self.pendingTaskAreaRefresh = false
	self.pendingTaskAreaRefreshShouldAnnounce = false
	self.pendingTaskAreaRefreshAfterMapHidden = false
	self.pendingTaskAreaRefreshAfterMapHiddenShouldAnnounce = false

	self:RefreshWorldQuestAreaState(resolvedShouldAnnounce)
	self:RefreshBonusObjectiveAreaState(resolvedShouldAnnounce)
	return true
end

function QuestTogether:PLAYER_REGEN_ENABLED()
	if self.pendingQuestLogTaskDrain then
		self.pendingQuestLogTaskDrain = false
		local drainedCount = DrainQueuedQuestLogTasks(self)
		if drainedCount > 0 then
			self:Debugf("quest", "Resuming deferred quest log tasks after combat count=%d", drainedCount)
		end
	end

	if self.pendingTaskAreaRefresh then
		local shouldAnnounce = self.pendingTaskAreaRefreshShouldAnnounce and true or false
		self:Debugf("quest", "Resuming deferred task area refresh announce=%s", SafeText(shouldAnnounce, "false"))
		self.pendingTaskAreaRefresh = false
		self.pendingTaskAreaRefreshShouldAnnounce = false
		self:RefreshTaskAreaStates(shouldAnnounce)
	end
end

-- QUEST_ACCEPTED fires early; defer reads until QUEST_LOG_UPDATE.
function QuestTogether:QUEST_ACCEPTED(_, questId)
	local normalizedQuestId = NormalizeQuestId(self, questId)
	self:Debugf("events", "QUEST_ACCEPTED questId=%s", SafeText(normalizedQuestId or questId, "?"))
	if not normalizedQuestId then
		return
	end

	self:QueueQuestLogTask(function()
		local tracker = self:GetPlayerTracker()
		if tracker[normalizedQuestId] ~= nil then
			return
		end

		local taskAnnouncementType = self:GetTaskAnnouncementType(normalizedQuestId)
		local questLogIndex = self.API.GetQuestLogIndexForQuestID
			and self.API.GetQuestLogIndexForQuestID(normalizedQuestId)
			if not questLogIndex then
				if taskAnnouncementType then
					local taskQuestTitle = self:GetQuestTitle(normalizedQuestId)
					self:WatchQuest(normalizedQuestId, { title = taskQuestTitle })
					self:RefreshTaskAreaStates(true)
				else
					self:Debugf("quest", "Quest not found in log questId=%s during accept", SafeText(normalizedQuestId, "?"))
				end
				return
		end

		local questInfo = self.API.GetQuestLogInfo and self.API.GetQuestLogInfo(questLogIndex)
		if not questInfo then
			return
		end

		if questInfo.isHidden and not taskAnnouncementType then
			return
		end

		if not taskAnnouncementType then
			self:Debugf(
				"quest",
				"Publishing accepted announcement questId=%s title=%s",
				SafeText(normalizedQuestId, "?"),
				SafeText(questInfo.title, "Unknown")
			)
			self:PublishAnnouncementEvent(
				"QUEST_ACCEPTED",
				"Quest Accepted: " .. SafeText(questInfo.title, "Unknown"),
				normalizedQuestId
			)
		end

			self:WatchQuest(normalizedQuestId, questInfo)
			if taskAnnouncementType then
				self:RefreshTaskAreaStates(true)
			end
		end)
end

function QuestTogether:QUEST_TURNED_IN(_, questId)
	questId = NormalizeQuestId(self, questId)
	self:Debugf("events", "QUEST_TURNED_IN questId=%s", SafeText(questId, "?"))
	if not questId then
		return
	end

	local completionData = self:BuildTrackedQuestCompletionData(questId)
	self.questsCompleted[questId] = completionData
	if self.pendingQuestRemovals[questId] then
		self:ResolvePendingQuestRemoval(questId)
	end
end

function QuestTogether:QUEST_REMOVED(_, questId)
	questId = NormalizeQuestId(self, questId)
	self:Debugf("events", "QUEST_REMOVED questId=%s", SafeText(questId, "?"))
	if not questId then
		return
	end

	local removalData = self:BuildTrackedQuestRemovalData(questId)
	if not removalData then
		return
	end

	self.pendingQuestRemovals[questId] = removalData
	self.API.Delay(0, function()
		if QuestTogether.pendingQuestRemovals and QuestTogether.pendingQuestRemovals[questId] then
			QuestTogether:ResolvePendingQuestRemoval(questId)
		end
	end)
end

function QuestTogether:SUPER_TRACKING_CHANGED()
	self:Debug("SUPER_TRACKING_CHANGED()", "events")
	self:RefreshTaskAreaStates(true)
end

-- UNIT_QUEST_LOG_CHANGED indicates objective and completion changes.
-- Emit local progress announcements only when numeric progress increases.
function QuestTogether:UNIT_QUEST_LOG_CHANGED(_, unit)
	self:Debugf("events", "UNIT_QUEST_LOG_CHANGED unit=%s", SafeText(unit, ""))

	if unit ~= "player" then
		return
	end

	self:QueueQuestLogTask(function()
		local tracker = self:GetPlayerTracker()

		for questId, questData in pairs(tracker) do
			local normalizedQuestId = NormalizeQuestId(self, questId)
			if normalizedQuestId then
				questId = normalizedQuestId
				local questLogIndex = self.API.GetQuestLogIndexForQuestID and self.API.GetQuestLogIndexForQuestID(questId)
				if not questLogIndex then
					self:Debugf("quest", "Quest not found in log questId=%s during objective scan", SafeText(questId, "?"))
				else
					local changedObjectives = {}
					local numObjectives = self.API.GetNumQuestLeaderBoards and self.API.GetNumQuestLeaderBoards(questLogIndex)
						or 0

					for objectiveIndex = 1, numObjectives do
						local objectiveText, objectiveType, _, currentValue =
							self.API.GetQuestObjectiveInfo and self.API.GetQuestObjectiveInfo(questId, objectiveIndex, false)
						if objectiveText == nil and objectiveType == nil and currentValue == nil then
							objectiveText = ""
						end

						if objectiveType == "progressbar" then
							local progress = self.API.GetQuestProgressBarPercent
								and self.API.GetQuestProgressBarPercent(questId)
							local roundedProgress = self:NormalizeQuestProgressPercent(progress) or 0
							objectiveText = SafeText(roundedProgress, "0")
								.. "% "
								.. SafeText(self:StripTrailingParentheticalPercent(objectiveText), "")
							currentValue = roundedProgress
						end

						questData.objectiveValues = questData.objectiveValues or {}
						local oldObjectiveText = questData.objectives[objectiveIndex]
						local oldObjectiveValue = questData.objectiveValues[objectiveIndex]
						if oldObjectiveText ~= objectiveText then
							local isInitialObjectiveBaseline = oldObjectiveText == nil and oldObjectiveValue == nil
							local hasForwardProgress =
								DidObjectiveProgressIncrease(oldObjectiveText, oldObjectiveValue, objectiveText, currentValue)
							local resolvedProgressValue = ResolveObjectiveProgressValue(objectiveText, currentValue)
							self:Debugf(
								"quest",
								"Objective delta questId=%s index=%d old=%s new=%s progress=%s initial=%s forward=%s",
								SafeText(questId, "?"),
								objectiveIndex,
								SafeText(oldObjectiveText, ""),
								SafeText(objectiveText, ""),
								SafeText(resolvedProgressValue, ""),
								SafeText(isInitialObjectiveBaseline, "false"),
								SafeText(hasForwardProgress, "false")
							)
							if (not isInitialObjectiveBaseline) and hasForwardProgress and self:ShouldPublishObjectiveProgress(
								resolvedProgressValue
							) then
								local taskAnnouncementType = self:GetTaskAnnouncementType(questId)
								local eventType = "QUEST_PROGRESS"
								if taskAnnouncementType == "world" then
									eventType = "WORLD_QUEST_PROGRESS"
								elseif taskAnnouncementType == "bonus" then
									eventType = "BONUS_OBJECTIVE_PROGRESS"
								end
								self:Debugf(
									"quest",
									"Publishing progress event questId=%s eventType=%s",
									SafeText(questId, "?"),
									SafeText(eventType, "")
								)
								self:PublishAnnouncementEvent(eventType, objectiveText, questId)
							end
							questData.objectives[objectiveIndex] = objectiveText
							questData.objectiveValues[objectiveIndex] = resolvedProgressValue
							changedObjectives[objectiveIndex] = objectiveText
						else
							questData.objectiveValues[objectiveIndex] =
								ResolveObjectiveProgressValue(objectiveText, currentValue)
						end
					end

					-- Objective list can shrink; emit explicit empty values for removed indices.
					local previousObjectiveCount = #questData.objectives
					if previousObjectiveCount > numObjectives then
						for objectiveIndex = numObjectives + 1, previousObjectiveCount do
							questData.objectives[objectiveIndex] = nil
							if questData.objectiveValues then
								questData.objectiveValues[objectiveIndex] = nil
							end
							changedObjectives[objectiveIndex] = ""
						end
					end

					local currentIsComplete = self.API.IsQuestComplete and self.API.IsQuestComplete(questId) or false
					local completionChanged = questData.isComplete ~= currentIsComplete
					if completionChanged then
						questData.isComplete = currentIsComplete
						self:RefreshTrackedQuestAnnouncementIcon(questId, questData)
						self:Debugf(
							"quest",
							"Completion state changed questId=%s isComplete=%s",
							SafeText(questId, "?"),
							SafeText(currentIsComplete, "false")
						)
					end

					local currentReadyForTurnIn = self.API.IsQuestReadyForTurnIn
						and self.API.IsQuestReadyForTurnIn(questId)
						or false
					local readyForTurnInChanged = questData.isReadyForTurnIn ~= currentReadyForTurnIn
					if readyForTurnInChanged then
						questData.isReadyForTurnIn = currentReadyForTurnIn
						self:RefreshTrackedQuestAnnouncementIcon(questId, questData)
						self:Debugf(
							"quest",
							"Ready for turn-in state changed questId=%s ready=%s",
							SafeText(questId, "?"),
							SafeText(currentReadyForTurnIn, "false")
						)
						if currentReadyForTurnIn and not self:GetTaskAnnouncementType(questId) then
							local questTitle = questData.title or self:GetQuestTitle(questId)
							self:PublishAnnouncementEvent(
								"QUEST_READY_TO_TURN_IN",
								"Ready to Turn In: " .. SafeText(questTitle, "Unknown"),
								questId
							)
						end
					end

					local hasObjectiveChanges = false
					for _ in pairs(changedObjectives) do
						hasObjectiveChanges = true
						break
					end
					if hasObjectiveChanges then
						self:DebugState("quest", "changedObjectives", changedObjectives)
					end
				end
			end
		end
	end)
end

function QuestTogether:QUEST_LOG_UPDATE()
	local inCombatLockdown = self.API and self.API.InCombatLockdown and self.API.InCombatLockdown()
	if inCombatLockdown then
		if type(self.onQuestLogUpdate) == "table" and #self.onQuestLogUpdate > 0 then
			self.pendingQuestLogTaskDrain = true
			self:Debugf("quest", "Deferring queued quest log tasks during combat count=%d", #self.onQuestLogUpdate)
		end
	else
		local drainedCount = DrainQueuedQuestLogTasks(self)
		if drainedCount > 0 then
			self:Debugf("quest", "Drained queued quest log tasks count=%d", drainedCount)
		end
	end

	self:RefreshTaskAreaStates(true)
end

function QuestTogether:QUEST_POI_UPDATE()
	self:RefreshTaskAreaStates(true)
end

function QuestTogether:PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED()
	self:RefreshTaskAreaStates(true)
end

function QuestTogether:AREA_POIS_UPDATED()
	self:RefreshTaskAreaStates(true)
end

function QuestTogether:ZONE_CHANGED()
	self:RefreshTaskAreaStates(true)
end

function QuestTogether:ZONE_CHANGED_INDOORS()
	self:RefreshTaskAreaStates(true)
end

function QuestTogether:ZONE_CHANGED_NEW_AREA()
	self:RefreshTaskAreaStates(true)
end

function QuestTogether:PLAYER_ENTERING_WORLD()
	-- Refresh state after loading screens without emitting synthetic enter/leave lines.
	self:Debug("PLAYER_ENTERING_WORLD()", "events")
	self:RefreshTaskAreaStates(false)
	if self.EnsureAnnouncementChannelJoined and self.isEnabled then
		self:EnsureAnnouncementChannelJoined()
	end
end

function QuestTogether:GROUP_JOINED()
	self:HandleGroupRosterChanged("GROUP_JOINED")
end

function QuestTogether:GROUP_ROSTER_UPDATE()
	self:HandleGroupRosterChanged("GROUP_ROSTER_UPDATE")
end
