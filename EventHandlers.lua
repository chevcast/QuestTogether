--[[
QuestTogether Event Handlers

This file contains runtime event logic and intentionally explains *why* each step exists.
The important pattern used throughout this addon:
- Some WoW quest events fire before quest APIs are fully updated.
- We therefore queue work and run it on QUEST_LOG_UPDATE.
]]

local QuestTogether = _G.QuestTogether

-- Utility: pick a random celebratory emote token.
function QuestTogether:PickRandomCompletionEmote()
	if #self.completionEmotes == 0 then
		return "cheer"
	end
	local randomIndex = self.API.Random(1, #self.completionEmotes)
	return self.completionEmotes[randomIndex]
end

-- Utility: play an emote *locally* only when local settings allow it.
function QuestTogether:PlayLocalCompletionEmote(emoteToken)
	if not self:GetOption("doEmotes") then
		self:Debug("Skipping local emote because doEmotes is disabled.")
		return false
	end
	self.API.DoEmote(emoteToken, self:GetPlayerName())
	return true
end

-- Helper used by QUEST_REMOVED when we have confirmed a completed quest.
function QuestTogether:HandleQuestCompleted(questTitle)
	-- Completion announcement is controlled by the announceCompleted option.
	if self:GetOption("announceCompleted") then
		self:Announce("Quest Completed: " .. tostring(questTitle))
	end

	-- IMPORTANT BEHAVIOR:
	-- We *always* broadcast the emote token so party members can respond based on *their* local setting.
	-- This fixes the bug/behavior mismatch discussed in the rewrite requirements.
	local emoteToken = self:PickRandomCompletionEmote()
	self:Broadcast("EMOTE", emoteToken)

	-- Local playback remains controlled by doEmotes.
	self:PlayLocalCompletionEmote(emoteToken)
end

function QuestTogether:HandleQuestRemoved(questTitle)
	if self:GetOption("announceRemoved") then
		self:Announce("Quest Removed: " .. tostring(questTitle))
	end
end

-- QUEST_ACCEPTED fires quickly; we defer quest-log reads until QUEST_LOG_UPDATE.
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
	end)
end

-- Track turn-ins so QUEST_REMOVED can distinguish completed vs abandoned.
function QuestTogether:QUEST_TURNED_IN(_, questId)
	self:Debug("QUEST_TURNED_IN(" .. tostring(questId) .. ")")
	self.questsCompleted[questId] = true
end

-- QUEST_REMOVED usually means either completion or abandon.
-- We defer and delay slightly to let API state settle.
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
		end)
	end)
end

function QuestTogether:SUPER_TRACKING_CHANGED()
	self:Debug("SUPER_TRACKING_CHANGED is not implemented.")
end

-- UNIT_QUEST_LOG_CHANGED indicates objectives may have changed.
-- We queue to QUEST_LOG_UPDATE so all objective API calls read fresh state.
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
				-- Quest can disappear between events (abandon/turn-in); skip it safely.
				self:Debug("Quest " .. tostring(questId) .. " not found in quest log.")
			else
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
					end
				end
			end
		end
	end)
end

-- When QUEST_LOG_UPDATE fires, queued tasks should now see fresh quest data.
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
	self:Broadcast("UPDATE_QUEST_TRACKER", self:GetPlayerTracker())
end

function QuestTogether:GROUP_ROSTER_UPDATE()
	self:Broadcast("UPDATE_QUEST_TRACKER", self:GetPlayerTracker())
end
