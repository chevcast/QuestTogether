--[[
QuestTogether Event Handlers

Responsibilities in this file:
- Detect local quest changes.
- Announce and emote locally according to options.
- Emit compact quest deltas instead of full tracker snapshots.
- Trigger sync bootstrap requests when roster state changes.
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
	if not self:GetOption("doEmotes") then
		self:Debug("Skipping local emote because doEmotes is disabled.")
		return false
	end
	self.API.DoEmote(emoteToken, self:GetPlayerName())
	return true
end

function QuestTogether:HandleQuestCompleted(questTitle, questId)
	if questId and self:IsWorldQuest(questId) then
		if self:GetOption("announceWorldQuestCompleted") then
			self:Announce("World Quest Completed: " .. tostring(questTitle))
		end
	elseif self:GetOption("announceCompleted") then
		self:Announce("Quest Completed: " .. tostring(questTitle))
	end

	-- Always send the token. Receivers decide locally via their own doEmotes option.
	local emoteToken = self:PickRandomCompletionEmote()
	self:Broadcast("EMOTE", emoteToken)
	self:PlayLocalCompletionEmote(emoteToken)
end

function QuestTogether:HandleQuestRemoved(questTitle)
	if self:GetOption("announceRemoved") then
		self:Announce("Quest Removed: " .. tostring(questTitle))
	end
end

function QuestTogether:ShouldAnnounceObjectiveProgress(questId, currentValue)
	if not currentValue or currentValue <= 0 then
		return false
	end

	if self:IsWorldQuest(questId) then
		return self:GetOption("announceWorldQuestProgress")
	end

	return self:GetOption("announceProgress")
end

function QuestTogether:ScheduleSyncRequest()
	if not self.isEnabled then
		return
	end
	if self.syncRequestScheduled then
		return
	end

	self.syncRequestScheduled = true
	local jitterSeconds = (self.API.Random(200, 600) or 300) / 1000
	self.API.Delay(jitterSeconds, function()
		self.syncRequestScheduled = false
		if self.isEnabled and self.RequestPartySync then
			self:RequestPartySync()
		end
	end)
end

function QuestTogether:HandleGroupRosterChanged(reason)
	local previousFingerprint = self:GetPartyRosterFingerprint()
	if self.RefreshPartyRoster then
		self:RefreshPartyRoster()
	end
	local newFingerprint = self:GetPartyRosterFingerprint()

	if reason == "GROUP_JOINED" or previousFingerprint ~= newFingerprint then
		self:ScheduleSyncRequest()
	end
end

-- Snapshot world quests from the current area task table.
-- Blizzard's tracker uses GetTasksTable() for local-area world quests.
function QuestTogether:GetActiveWorldQuestAreaSnapshot()
	local activeByQuestId = {}

	-- Use Blizzard's local task snapshot only.
	-- We intentionally do not merge tracked-watch lists here because watched world quests
	-- are shown by Blizzard even when out of area, which is not suitable for enter/leave.
	if type(GetTasksTable) == "function" then
		local tasksTable = GetTasksTable()
		if type(tasksTable) == "table" then
			for _, questId in ipairs(tasksTable) do
				if self:IsWorldQuest(questId) then
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

-- Track area enter/leave transitions for world quests.
-- We compare Blizzard's current local-area task snapshot with our previous snapshot.
function QuestTogether:RefreshWorldQuestAreaState(shouldAnnounce)
	local previousState = self.worldQuestAreaStateByQuestID or {}
	local currentState = self:GetActiveWorldQuestAreaSnapshot()
	self:Debug(
		"RefreshWorldQuestAreaState(announce="
			.. tostring(shouldAnnounce)
			.. ", prev="
			.. tostring(CountKeys(previousState))
			.. ", curr="
			.. tostring(CountKeys(currentState))
			.. ")"
	)

	for questId, questTitle in pairs(currentState) do
		if not previousState[questId] and shouldAnnounce and self:GetOption("announceWorldQuestAreaEnter") then
			self:Announce("World Quest Entered: " .. tostring(questTitle))
		end
	end

	for questId, previousTitle in pairs(previousState) do
		if not currentState[questId] then
			local wasCompleted = self.questsCompleted[questId] == true
			if shouldAnnounce and not wasCompleted and self:GetOption("announceWorldQuestAreaLeave") then
				local questTitle = previousTitle or self:GetQuestTitle(questId)
				self:Announce("Left World Quest: " .. tostring(questTitle))
			end
		end
	end

	self.worldQuestAreaStateByQuestID = currentState
end

-- QUEST_ACCEPTED fires early; defer reads until QUEST_LOG_UPDATE.
function QuestTogether:QUEST_ACCEPTED(_, questId)
	self:Debug("QUEST_ACCEPTED(" .. tostring(questId) .. ")")

	self:QueueQuestLogTask(function()
		local tracker = self:GetPlayerTracker()
		if tracker[questId] ~= nil then
			return
		end

		local isWorldQuest = self:IsWorldQuest(questId)
		local questLogIndex = C_QuestLog.GetLogIndexForQuestID(questId)
		if not questLogIndex then
			if isWorldQuest then
				local worldQuestTitle = self:GetQuestTitle(questId)
				self:WatchQuest(questId, { title = worldQuestTitle })
				self:RefreshWorldQuestAreaState(true)
				if self.UpdateDebugPartySimulationData then
					self:UpdateDebugPartySimulationData()
				end
				if self.SendQuestDelta then
					self:SendQuestDelta("Q_ADD", questId, tracker[questId])
				end
			else
				self:Debug("Quest " .. tostring(questId) .. " not found in quest log.")
			end
			return
		end

		local questInfo = C_QuestLog.GetInfo(questLogIndex)
		if not questInfo then
			return
		end

		if questInfo.isHidden and not isWorldQuest then
			return
		end

		if not isWorldQuest and self:GetOption("announceAccepted") then
			self:Announce("Quest Accepted: " .. tostring(questInfo.title))
		end

		self:WatchQuest(questId, questInfo)
		if isWorldQuest then
			self:RefreshWorldQuestAreaState(true)
		end
		if self.UpdateDebugPartySimulationData then
			self:UpdateDebugPartySimulationData()
		end
		if self.SendQuestDelta then
			self:SendQuestDelta("Q_ADD", questId, tracker[questId])
		end
	end)
end

function QuestTogether:QUEST_TURNED_IN(_, questId)
	self:Debug("QUEST_TURNED_IN(" .. tostring(questId) .. ")")
	self.questsCompleted[questId] = true
end

function QuestTogether:QUEST_REMOVED(_, questId)
	self:Debug("QUEST_REMOVED(" .. tostring(questId) .. ")")

	self:QueueQuestLogTask(function()
		self.API.Delay(0.5, function()
			local tracker = self:GetPlayerTracker()
			local trackedQuest = tracker[questId]
			if not trackedQuest then
				return
			end

			local questTitle = trackedQuest.title or ("Quest " .. tostring(questId))
			local isWorldQuest = self:IsWorldQuest(questId)
			local questWasCompleted = self.questsCompleted[questId] == true

			if questWasCompleted then
				self:HandleQuestCompleted(questTitle, questId)
			elseif not isWorldQuest then
				self:HandleQuestRemoved(questTitle)
			end

			self.worldQuestAreaStateByQuestID[questId] = nil
			tracker[questId] = nil
			if self.UpdateDebugPartySimulationData then
				self:UpdateDebugPartySimulationData()
			end
			if self.SendQuestDelta then
				self:SendQuestDelta("Q_REM", questId)
			end
			self:RefreshWorldQuestAreaState(true)
			if questWasCompleted then
				self.questsCompleted[questId] = nil
			end
		end)
	end)
end

function QuestTogether:SUPER_TRACKING_CHANGED()
	self:Debug("SUPER_TRACKING_CHANGED is not implemented.")
end

-- UNIT_QUEST_LOG_CHANGED indicates objective and completion changes.
-- Emit compact objective deltas only for changed indices.
function QuestTogether:UNIT_QUEST_LOG_CHANGED(_, unit)
	self:Debug("UNIT_QUEST_LOG_CHANGED(" .. tostring(unit) .. ")")

	if unit ~= "player" then
		return
	end

	self:QueueQuestLogTask(function()
		local tracker = self:GetPlayerTracker()

		for questId, questData in pairs(tracker) do
			local questLogIndex = C_QuestLog.GetLogIndexForQuestID(questId)
			if not questLogIndex then
				self:Debug("Quest " .. tostring(questId) .. " not found in quest log.")
			else
				local changedObjectives = {}
				local numObjectives = GetNumQuestLeaderBoards(questLogIndex)

				for objectiveIndex = 1, numObjectives do
					local objectiveText, objectiveType, _, currentValue =
						GetQuestObjectiveInfo(questId, objectiveIndex, false)

					if objectiveType == "progressbar" then
						local progress = GetQuestProgressBarPercent(questId)
						objectiveText = tostring(progress) .. "% " .. tostring(objectiveText)
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
						if
							(not isInitialObjectiveBaseline)
							and hasForwardProgress
							and self:ShouldAnnounceObjectiveProgress(questId, resolvedProgressValue)
						then
							self:Announce(objectiveText)
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
				end

				local hasObjectiveChanges = false
				for _ in pairs(changedObjectives) do
					hasObjectiveChanges = true
					break
				end

				if hasObjectiveChanges or completionChanged then
					self:QueueQuestObjectiveDelta(
						questId,
						changedObjectives,
						completionChanged and currentIsComplete or nil
					)
				end
			end
		end

		if self.UpdateDebugPartySimulationData then
			self:UpdateDebugPartySimulationData()
		end
	end)
end

function QuestTogether:QUEST_LOG_UPDATE()
	self:Debug("QUEST_LOG_UPDATE()")

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

	self:RefreshWorldQuestAreaState(true)
end

function QuestTogether:QUEST_POI_UPDATE()
	self:RefreshWorldQuestAreaState(true)
end

function QuestTogether:AREA_POIS_UPDATED()
	self:RefreshWorldQuestAreaState(true)
end

function QuestTogether:ZONE_CHANGED()
	self:RefreshWorldQuestAreaState(true)
end

function QuestTogether:ZONE_CHANGED_INDOORS()
	self:RefreshWorldQuestAreaState(true)
end

function QuestTogether:ZONE_CHANGED_NEW_AREA()
	self:RefreshWorldQuestAreaState(true)
end

function QuestTogether:PLAYER_ENTERING_WORLD()
	-- Refresh state after loading screens without emitting synthetic enter/leave lines.
	self:RefreshWorldQuestAreaState(false)
end

function QuestTogether:GROUP_JOINED()
	self:HandleGroupRosterChanged("GROUP_JOINED")
end

function QuestTogether:GROUP_ROSTER_UPDATE()
	self:HandleGroupRosterChanged("GROUP_ROSTER_UPDATE")
end
