--[[
QuestTogether Event Handlers

Responsibilities in this file:
- Detect local quest changes.
- Announce and emote locally according to options.
- Emit compact quest deltas instead of full tracker snapshots.
- Trigger sync bootstrap requests when roster state changes.
]]

local QuestTogether = _G.QuestTogether

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

function QuestTogether:HandleQuestCompleted(questTitle)
	if self:GetOption("announceCompleted") then
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

-- QUEST_ACCEPTED fires early; defer reads until QUEST_LOG_UPDATE.
function QuestTogether:QUEST_ACCEPTED(_, questId)
	self:Debug("QUEST_ACCEPTED(" .. tostring(questId) .. ")")

	self:QueueQuestLogTask(function()
		local tracker = self:GetPlayerTracker()
		if tracker[questId] ~= nil then
			return
		end

		local questLogIndex = C_QuestLog.GetLogIndexForQuestID(questId)
		if not questLogIndex then
			self:Debug("Quest " .. tostring(questId) .. " not found in quest log.")
			return
		end

		local questInfo = C_QuestLog.GetInfo(questLogIndex)
		if not questInfo or questInfo.isHidden then
			return
		end

		if self:GetOption("announceAccepted") then
			self:Announce("Quest Accepted: " .. tostring(questInfo.title))
		end

		self:WatchQuest(questId, questInfo)
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

			if self.questsCompleted[questId] then
				self:HandleQuestCompleted(questTitle)
				self.questsCompleted[questId] = nil
			else
				self:HandleQuestRemoved(questTitle)
			end

			tracker[questId] = nil
			if self.UpdateDebugPartySimulationData then
				self:UpdateDebugPartySimulationData()
			end
			if self.SendQuestDelta then
				self:SendQuestDelta("Q_REM", questId)
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

					local oldObjectiveText = questData.objectives[objectiveIndex]
					if oldObjectiveText ~= objectiveText then
						if currentValue and currentValue > 0 and self:GetOption("announceProgress") then
							self:Announce(objectiveText)
						end
						questData.objectives[objectiveIndex] = objectiveText
						changedObjectives[objectiveIndex] = objectiveText
					end
				end

				-- Objective list can shrink; emit explicit empty values for removed indices.
				local previousObjectiveCount = #questData.objectives
				if previousObjectiveCount > numObjectives then
					for objectiveIndex = numObjectives + 1, previousObjectiveCount do
						questData.objectives[objectiveIndex] = nil
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
	if #queuedTasks == 0 then
		return
	end

	for index = 1, #queuedTasks do
		local ok, err = pcall(queuedTasks[index])
		if not ok then
			self:Print("Quest task error: " .. tostring(err))
		end
	end

	self.onQuestLogUpdate = {}
end

function QuestTogether:GROUP_JOINED()
	self:HandleGroupRosterChanged("GROUP_JOINED")
end

function QuestTogether:GROUP_ROSTER_UPDATE()
	self:HandleGroupRosterChanged("GROUP_ROSTER_UPDATE")
end
