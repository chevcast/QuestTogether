-- This file contains all methods for handling various WoW events.

-- When a quest is accepted we need to start tracking it.
-- To ensure quest API functions return updated information we schedule our tracking logic to run after QUEST_LOG_UPDATE.
function QuestTogether:QUEST_ACCEPTED(event, questId)
	self:Debug("QUEST_ACCEPTED(" .. questId .. ")")
	table.insert(self.onQuestLogUpdate, function()
		if QuestTogether.db.global.questTrackers[UnitName("player")][questId] == nil then
			local questLogIndex = C_QuestLog.GetLogIndexForQuestID(questId)
			local questInfo = C_QuestLog.GetInfo(questLogIndex)
			if questInfo.isHidden then
				return
			end
			local message = "Quest Accepted: " .. questInfo.title
			if self.db.profile.announceAccepted then
				self:Announce(message)
			end
			self:WatchQuest(questId, questInfo)
		end
	end)
end

-- This event fires the moment a quest is turned in. We need to keep track of turned in quest IDs so we can determine
-- if a quest was completed or abandoned.
function QuestTogether:QUEST_TURNED_IN(event, questId)
	self:Debug("QUEST_TURNED_IN(" .. questId .. ")")
	self.questsCompleted[questId] = true
end

-- When a quest is removed from the quest log it's usually an indicator that the quest has been completed or abandoned.
-- To ensure quest API functions return updated information we schedule our tracking logic to run after QUEST_LOG_UPDATE.
function QuestTogether:QUEST_REMOVED(event, questId)
	self:Debug("QUEST_REMOVED(" .. questId .. ")")
	table.insert(self.onQuestLogUpdate, function()
		C_Timer.After(0.5, function()
			if QuestTogether.db.global.questTrackers[UnitName("player")][questId] then
				local questTitle = QuestTogether.db.global.questTrackers[UnitName("player")][questId].title
				if self.questsCompleted[questId] then
					local message = "Quest Completed: " .. questTitle
					if self.db.profile.announceCompleted then
						self:Announce(message)
						if self.db.profile.doEmotes then
							local randomEmote = self.completionEmotes[math.random(#self.completionEmotes)]
							DoEmote(randomEmote, UnitName("player"))
							self:Broadcase("EMOTE", randomEmote)
						end
					end
					self.questsCompleted[questId] = nil
				else
					local message = "Quest Removed: " .. questTitle
					if self.db.profile.announceRemoved then
						self:Announce(message)
					end
				end
				QuestTogether.db.global.questTrackers[UnitName("player")][questId] = nil
			end
		end)
	end)
end

function QuestTogether:SUPER_TRACKING_CHANGED(event)
	local questId = C_SuperTrack.GetSuperTrackedQuestID()
	self:Debug("SUPER_TRACKING_CHANGED(" .. questId .. ")")
	self:Broadcast("SUPER_TRACK", questId)
end

-- When the player's quest log changes it's usually an indicator that the player has updated quest objective information.
-- To ensure quest API functions return updated information we schedule our tracking logic to run after QUEST_LOG_UPDATE.
function QuestTogether:UNIT_QUEST_LOG_CHANGED(event, unit)
	self:Debug("UNIT_QUEST_LOG_CHANGED(" .. unit .. ")")
	if unit == "player" then
		table.insert(self.onQuestLogUpdate, function()
			for questId, quest in pairs(QuestTogether.db.global.questTrackers[UnitName("player")]) do
				local questLogIndex = C_QuestLog.GetLogIndexForQuestID(questId)
				local numObjectives = GetNumQuestLeaderBoards(questLogIndex)
				for objectiveIndex = 1, numObjectives do
					local objectiveText, type, complete, currentValue, maxValue =
						GetQuestObjectiveInfo(questId, objectiveIndex, false)
					if type == "progressbar" then
						local progress = GetQuestProgressBarPercent(questId)
						objectiveText = progress .. "% " .. objectiveText
						currentValue = progress
					end
					if
						QuestTogether.db.global.questTrackers[UnitName("player")][questId].objectives[objectiveIndex]
						~= objectiveText
					then
						if currentValue and currentValue > 0 then
							if QuestTogether.db.profile.announceProgress then
								self:Announce(objectiveText)
							end
						end
						QuestTogether.db.global.questTrackers[UnitName("player")][questId].objectives[objectiveIndex] =
							objectiveText
					end
				end
			end
		end)
	end
end

-- When this event fires it indicates that the quest log has up to date information.
-- We run any scheduled tasks at this time to ensure those tasks have access to the latest information.
function QuestTogether:QUEST_LOG_UPDATE()
	self:Debug("QUEST_LOG_UPDATE()")
	local numTasks = #self.onQuestLogUpdate
	if numTasks ~= nil then
		for index = 1, numTasks, 1 do
			self.onQuestLogUpdate[index]()
		end
		self.onQuestLogUpdate = {}
		if UnitInParty("player") then
			self:Broadcast("UPDATE_QUEST_TRACKER", self.db.global.questTrackers[UnitName("player")])
		end
	end
end

function QuestTogether:GROUP_JOINED()
	self:Broadcast("UPDATE_QUEST_TRACKER", self.db.global.questTrackers[UnitName("player")])
end

function QuestTogether:GROUP_ROSTER_UPDATE()
	self:Broadcast("UPDATE_QUEST_TRACKER", self.db.global.questTrackers[UnitName("player")])
end
