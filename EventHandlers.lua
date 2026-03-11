--[[
QuestTogether Event Handlers

Responsibilities in this file:
- Detect local quest changes.
- Publish lightweight announcement events.
- Display local announcements according to local options.
]]

local QuestTogether = _G.QuestTogether

local function CountKeys(tableValue)
	local count = 0
	for _ in pairs(tableValue or {}) do
		count = count + 1
	end
	return count
end

local function ParseObjectiveProgressFromText(objectiveText)
	if type(objectiveText) ~= "string" or objectiveText == "" then
		return nil
	end

	local amountCurrent = objectiveText:match("(%d+)%s*/%s*%d+")
	if amountCurrent then
		return tonumber(amountCurrent)
	end

	local percent = objectiveText:match("(%d+)%%")
	if percent then
		return tonumber(percent)
	end

	return nil
end

local function ResolveObjectiveProgressValue(objectiveText, currentValue)
	local numericValue = tonumber(currentValue)
	if numericValue ~= nil then
		return numericValue
	end
	return ParseObjectiveProgressFromText(objectiveText)
end

local function DidObjectiveProgressIncrease(oldText, oldValue, newText, newValue)
	local previousValue = tonumber(oldValue)
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
	self:Debugf("quest", "Playing completion emote token=%s", tostring(emoteToken))
	self.API.DoEmote(emoteToken, self:GetPlayerName())
	return true
end

function QuestTogether:HandleQuestCompleted(questTitle, questId)
	self:Debugf("quest", "Quest completed questId=%s title=%s", tostring(questId), tostring(questTitle))
	local completionEmote = self:PickRandomCompletionEmote()
	if questId and self:IsWorldQuest(questId) then
		self:PublishAnnouncementEvent(
			"WORLD_QUEST_COMPLETED",
			"World Quest Completed: " .. tostring(questTitle),
			questId,
			{ emoteToken = completionEmote }
		)
	elseif questId and self:IsBonusObjective(questId) then
		self:PublishAnnouncementEvent(
			"BONUS_OBJECTIVE_COMPLETED",
			"Bonus Objective Completed: " .. tostring(questTitle),
			questId,
			{ emoteToken = completionEmote }
		)
	else
		self:PublishAnnouncementEvent(
			"QUEST_COMPLETED",
			"Quest Completed: " .. tostring(questTitle),
			questId,
			{ emoteToken = completionEmote }
		)
	end

	self:PlayLocalCompletionEmote(completionEmote)
end

function QuestTogether:HandleQuestRemoved(questTitle)
	self:Debugf("quest", "Quest removed title=%s", tostring(questTitle))
	self:PublishAnnouncementEvent("QUEST_REMOVED", "Quest Removed: " .. tostring(questTitle))
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

function QuestTogether:HandleGroupRosterChanged(reason)
	local previousFingerprint = self:GetPartyRosterFingerprint()
	if self.RefreshPartyRoster then
		self:RefreshPartyRoster()
	end
	local newFingerprint = self:GetPartyRosterFingerprint()
	self:Debugf(
		"group",
		"HandleGroupRosterChanged reason=%s changed=%s prev=%s new=%s",
		tostring(reason),
		tostring(previousFingerprint ~= newFingerprint),
		tostring(previousFingerprint),
		tostring(newFingerprint)
	)
end

-- Snapshot area task quests from Blizzard's local task table.
-- World quests and bonus objectives share the same source and differ only by classification.
function QuestTogether:GetTaskAreaSnapshot(taskType)
	local activeByQuestId = {}

	-- Use Blizzard's local task snapshot only.
	-- We intentionally do not merge tracked-watch lists here because watched tasks
	-- are shown by Blizzard even when out of area, which is not suitable for enter/leave.
	if type(GetTasksTable) == "function" then
		local tasksTable = GetTasksTable()
		if type(tasksTable) == "table" then
			for _, questId in ipairs(tasksTable) do
				local matchesType = taskType == "world" and self:IsWorldQuest(questId)
					or taskType == "bonus" and self:IsBonusObjective(questId)
				if matchesType then
					local inArea = type(GetTaskInfo) ~= "function" or (GetTaskInfo(questId) and true or false)
					if inArea then
						activeByQuestId[questId] = self:GetQuestTitle(questId)
					end
				end
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

	local previousState = self[config.stateKey] or {}
	local currentState = self[config.snapshotMethod](self)
	self:Debugf(
		"quest",
		"RefreshTaskAreaState type=%s announce=%s prev=%d curr=%d",
		tostring(taskType),
		tostring(shouldAnnounce),
		CountKeys(previousState),
		CountKeys(currentState)
	)

	for questId, questTitle in pairs(currentState) do
		if not previousState[questId] and shouldAnnounce then
			self:Debugf(
				"quest",
				"%s area entered questId=%s title=%s",
				tostring(config.debugLabel),
				tostring(questId),
				tostring(questTitle)
			)
			self:PublishAnnouncementEvent(config.enterEvent, config.enterPrefix .. tostring(questTitle), questId)
		end
	end

	for questId, previousTitle in pairs(previousState) do
		if not currentState[questId] then
			local wasCompleted = self.questsCompleted[questId] == true
			if shouldAnnounce and not wasCompleted then
				local questTitle = previousTitle or self:GetQuestTitle(questId)
				self:Debugf(
					"quest",
					"%s area left questId=%s title=%s",
					tostring(config.debugLabel),
					tostring(questId),
					tostring(questTitle)
				)
				self:PublishAnnouncementEvent(config.leftEvent, config.leftPrefix .. tostring(questTitle), questId)
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

function QuestTogether:RefreshTaskAreaStates(shouldAnnounce)
	self:RefreshWorldQuestAreaState(shouldAnnounce)
	self:RefreshBonusObjectiveAreaState(shouldAnnounce)
end

-- QUEST_ACCEPTED fires early; defer reads until QUEST_LOG_UPDATE.
function QuestTogether:QUEST_ACCEPTED(_, questId)
	self:Debugf("events", "QUEST_ACCEPTED questId=%s", tostring(questId))

	self:QueueQuestLogTask(function()
		local tracker = self:GetPlayerTracker()
		if tracker[questId] ~= nil then
			return
		end

		local taskAnnouncementType = self:GetTaskAnnouncementType(questId)
		local questLogIndex = C_QuestLog.GetLogIndexForQuestID(questId)
		if not questLogIndex then
			if taskAnnouncementType then
				local taskQuestTitle = self:GetQuestTitle(questId)
				self:WatchQuest(questId, { title = taskQuestTitle })
				self:RefreshTaskAreaState(taskAnnouncementType, true)
			else
				self:Debugf("quest", "Quest not found in log questId=%s during accept", tostring(questId))
			end
			return
		end

		local questInfo = C_QuestLog.GetInfo(questLogIndex)
		if not questInfo then
			return
		end

		if questInfo.isHidden and not taskAnnouncementType then
			return
		end

		if not taskAnnouncementType then
			self:Debugf("quest", "Publishing accepted announcement questId=%s title=%s", tostring(questId), tostring(questInfo.title))
			self:PublishAnnouncementEvent("QUEST_ACCEPTED", "Quest Accepted: " .. tostring(questInfo.title), questId)
		end

		self:WatchQuest(questId, questInfo)
		if taskAnnouncementType then
			self:RefreshTaskAreaState(taskAnnouncementType, true)
		end
	end)
end

function QuestTogether:QUEST_TURNED_IN(_, questId)
	self:Debugf("events", "QUEST_TURNED_IN questId=%s", tostring(questId))
	self.questsCompleted[questId] = true
end

function QuestTogether:QUEST_REMOVED(_, questId)
	self:Debugf("events", "QUEST_REMOVED questId=%s", tostring(questId))

	self:QueueQuestLogTask(function()
		self.API.Delay(0.5, function()
			local tracker = self:GetPlayerTracker()
			local trackedQuest = tracker[questId]
			if not trackedQuest then
				return
			end

			local questTitle = trackedQuest.title or ("Quest " .. tostring(questId))
			local taskAnnouncementType = self:GetTaskAnnouncementType(questId)
			local questWasCompleted = self.questsCompleted[questId] == true
			self:Debugf(
				"quest",
				"Processing removal questId=%s title=%s taskType=%s completed=%s",
				tostring(questId),
				tostring(questTitle),
				tostring(taskAnnouncementType),
				tostring(questWasCompleted)
			)

			if questWasCompleted then
				self:HandleQuestCompleted(questTitle, questId)
			elseif not taskAnnouncementType then
				self:PublishAnnouncementEvent("QUEST_REMOVED", "Quest Removed: " .. tostring(questTitle), questId)
			end

			self.worldQuestAreaStateByQuestID[questId] = nil
			self.bonusObjectiveAreaStateByQuestID[questId] = nil
			tracker[questId] = nil
			self:RefreshTaskAreaStates(true)
			if questWasCompleted then
				self.questsCompleted[questId] = nil
			end
		end)
	end)
end

function QuestTogether:SUPER_TRACKING_CHANGED()
	self:Debug("SUPER_TRACKING_CHANGED is not implemented.", "events")
end

-- UNIT_QUEST_LOG_CHANGED indicates objective and completion changes.
-- Emit local progress announcements only when numeric progress increases.
function QuestTogether:UNIT_QUEST_LOG_CHANGED(_, unit)
	self:Debugf("events", "UNIT_QUEST_LOG_CHANGED unit=%s", tostring(unit))

	if unit ~= "player" then
		return
	end

	self:QueueQuestLogTask(function()
		local tracker = self:GetPlayerTracker()

		for questId, questData in pairs(tracker) do
			local questLogIndex = C_QuestLog.GetLogIndexForQuestID(questId)
			if not questLogIndex then
				self:Debugf("quest", "Quest not found in log questId=%s during objective scan", tostring(questId))
			else
				local changedObjectives = {}
				local numObjectives = GetNumQuestLeaderBoards(questLogIndex)

				for objectiveIndex = 1, numObjectives do
					local objectiveText, objectiveType, _, currentValue =
						GetQuestObjectiveInfo(questId, objectiveIndex, false)

					if objectiveType == "progressbar" then
						local progress = GetQuestProgressBarPercent(questId)
						objectiveText = tostring(progress)
							.. "% "
							.. tostring(self:StripTrailingParentheticalPercent(objectiveText))
						currentValue = progress
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
							tostring(questId),
							objectiveIndex,
							tostring(oldObjectiveText),
							tostring(objectiveText),
							tostring(resolvedProgressValue),
							tostring(isInitialObjectiveBaseline),
							tostring(hasForwardProgress)
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
							self:Debugf("quest", "Publishing progress event questId=%s eventType=%s", tostring(questId), tostring(eventType))
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

				local currentIsComplete = C_QuestLog.IsComplete(questId) and true or false
				local completionChanged = questData.isComplete ~= currentIsComplete
				if completionChanged then
					questData.isComplete = currentIsComplete
					self:Debugf(
						"quest",
						"Completion state changed questId=%s isComplete=%s",
						tostring(questId),
						tostring(currentIsComplete)
					)
				end

				local currentReadyForTurnIn = C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(questId) and true
					or false
				local readyForTurnInChanged = questData.isReadyForTurnIn ~= currentReadyForTurnIn
				if readyForTurnInChanged then
					questData.isReadyForTurnIn = currentReadyForTurnIn
					self:Debugf(
						"quest",
						"Ready for turn-in state changed questId=%s ready=%s",
						tostring(questId),
						tostring(currentReadyForTurnIn)
					)
					if currentReadyForTurnIn and not self:GetTaskAnnouncementType(questId) then
						local questTitle = questData.title or self:GetQuestTitle(questId)
						self:PublishAnnouncementEvent("QUEST_READY_TO_TURN_IN", "Ready to Turn In: " .. tostring(questTitle), questId)
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
	end)
end

function QuestTogether:QUEST_LOG_UPDATE()
	local queuedTasks = self.onQuestLogUpdate
	if #queuedTasks > 0 then
		for index = 1, #queuedTasks do
			local ok, err = pcall(queuedTasks[index])
			if not ok then
				self:Print("Quest task error: " .. tostring(err))
			end
		end
		self.onQuestLogUpdate = {}
	end

	self:RefreshTaskAreaStates(true)
end

function QuestTogether:QUEST_POI_UPDATE()
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
