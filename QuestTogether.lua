QuestTogetherDB = {
	questTracker = {},
	DEBUG = {
		messages = false,
		questLogUpdate = false,
		events = false,
		showDebugInfo = false,
	},
}

if not QuestTogetherDB.DEBUG then
	QuestTogetherDB.DEBUG = {
		messages = false,
		questLogupdate = false,
		events = false,
		showDebugInfo = false,
	}
end

local questTogetherFrame = CreateFrame("FRAME", "QuestTogetherFrame")
local characterName = string.lower(UnitName("player"))
local faction = string.lower(UnitFactionGroup("player"))

C_ChatInfo.RegisterAddonMessagePrefix("QuestTogether")

questTogetherFrame:RegisterEvent("QUEST_ACCEPTED")
questTogetherFrame:RegisterEvent("QUEST_ACCEPT_CONFIRM")
questTogetherFrame:RegisterEvent("QUEST_AUTOCOMPLETE")
questTogetherFrame:RegisterEvent("QUEST_COMPLETE")
questTogetherFrame:RegisterEvent("QUEST_POI_UPDATE")
questTogetherFrame:RegisterEvent("QUEST_DETAIL")
questTogetherFrame:RegisterEvent("QUEST_FINISHED")
questTogetherFrame:RegisterEvent("QUEST_GREETING")
questTogetherFrame:RegisterEvent("QUEST_ITEM_UPDATE")
questTogetherFrame:RegisterEvent("QUEST_LOG_UPDATE")
questTogetherFrame:RegisterEvent("QUEST_PROGRESS")
questTogetherFrame:RegisterEvent("QUEST_REMOVED")
questTogetherFrame:RegisterEvent("QUEST_TURNED_IN")
questTogetherFrame:RegisterEvent("QUEST_WATCH_UPDATE")
questTogetherFrame:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
questTogetherFrame:RegisterEvent("QUEST_LOG_CRITERIA_UPDATE")
questTogetherFrame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
questTogetherFrame:RegisterEvent("PARTY_MEMBER_ENABLE")
questTogetherFrame:RegisterEvent("PARTY_MEMBER_DISABLE")
questTogetherFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
questTogetherFrame:RegisterEvent("AJ_QUEST_LOG_OPEN")
questTogetherFrame:RegisterEvent("QUEST_TURNED_IN")
questTogetherFrame:RegisterEvent("ADVENTURE_MAP_QUEST_UPDATE")
questTogetherFrame:RegisterEvent("SUPER_TRACKING_CHANGED")
questTogetherFrame:RegisterEvent("QUESTLINE_UPDATE")
questTogetherFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
questTogetherFrame:RegisterEvent("CHAT_MSG_ADDON")

local onQuestLogUpdate = {}
local questsTurnedIn = {}

local debugCmd = function(cmd, msg)
	if UnitInParty("player") then
		C_ChatInfo.SendAddonMessage("QuestTogether", "[" .. cmd .. "]:" .. msg, "PARTY")
	else
		C_ChatInfo.SendAddonMessage("QuestTogether", "[" .. cmd .. "]:" .. msg, "YELL", name)
	end
end

local reportInfo = function(msg)
	if UnitInParty("player") then
		SendChatMessage(msg, "PARTY")
	end
	if QuestTogetherDB.DEBUG.messages then
		debugCmd("info", msg)
	end
end

local watchQuest = function(questId)
	local questLogIndex = C_QuestLog.GetLogIndexForQuestID(questId)
	local info = C_QuestLog.GetInfo(questLogIndex)
	local numObjectives = GetNumQuestLeaderBoards(questLogIndex)
	QuestTogetherDB.questTracker[questId] = {
		title = info.title,
		objectives = {},
	}
	for objectiveIndex = 1, numObjectives do
		local objectiveText, type = GetQuestObjectiveInfo(questId, objectiveIndex, false)
		if type == "progressbar" then
			local progress = GetQuestProgressBarPercent(questId)
			objectiveText = progress .. "% " .. objectiveText
		end
		QuestTogetherDB.questTracker[questId].objectives[objectiveIndex] = objectiveText
	end
end

local scanQuestLog = function()
	QuestTogetherDB.questTracker = {}
	local numQuestLogEntries = C_QuestLog.GetNumQuestLogEntries()
	local questsTracked = 0
	for questLogIndex = 1, numQuestLogEntries do
		local info = C_QuestLog.GetInfo(questLogIndex)
		if info.isHeader == false then
			watchQuest(info.questID)
			questsTracked = questsTracked + 1
		end
	end
	print(questsTracked .. " quests are being monitored by QuestTogether.")
	if QuestTogetherDB.DEBUG.messages then
		debugCmd("info", questsTracked .. " quests are being monitored by QuestTogether.")
	end
end

SLASH_QT1 = "/qt"
SlashCmdList["QT"] = function(msg)
	local qtCmd, subCmd, arg = string.match(msg, "^([a-zA-Z]+) ([^ ]+) (.+)$")
	local qtCmds = {
		debug = function(subCmd, arg)
			debugCmd(subCmd, arg)
		end,
	}
	if qtCmds[qtCmd] ~= nil then
		qtCmds[qtCmd](subCmd, arg)
	end
end

local EventHandlers = {

	CHAT_MSG_ADDON = function(prefix, message, channel, sender)
		if prefix == "QuestTogether" then
			local cmd, data = string.match(message, "^%[(.+)%]:(.+)$")
			if cmd == "set-debug-option" then
				local targetCharacter, option, value = string.match(data, "^([a-zA-Z]+);([a-zA-Z]+);([a-zA-Z]+)$")
				if string.lower(targetCharacter) == characterName or targetCharacter == "all" then
					QuestTogetherDB.DEBUG[option] = value == "true" and true or false
				end
			elseif cmd == "get-debug-options" then
				if string.lower(data) == characterName then
					debugCmd(
						"info",
						"\nevents="
							.. tostring(QuestTogetherDB.DEBUG.events)
							.. "\nmessages="
							.. tostring(QuestTogetherDB.DEBUG.messages)
							.. "\nquestLogUpdate="
							.. tostring(QuestTogetherDB.DEBUG.questLogUpdate)
							.. "\nshowDebugInfo="
							.. tostring(QuestTogetherDB.DEBUG.showDebugInfo)
					)
				end
			elseif cmd == "ping" then
				if string.lower(data) == characterName or string.lower(data) == "all" then
					debugCmd("info", "pong!")
				end
			elseif cmd == "info" and QuestTogetherDB.DEBUG.showDebugInfo then
				sender = string.match(sender, "^([a-zA-Z]+)%-")
				print("<" .. sender .. "> " .. data)
			end
		end
	end,

	-- Upon entering world scan quest log for quests to track.
	PLAYER_ENTERING_WORLD = function()
		C_Timer.After(10, function()
			scanQuestLog()
		end)
	end,

	-- Track newly accepted quests.
	QUEST_ACCEPTED = function(questId)
		table.insert(onQuestLogUpdate, function()
			if QuestTogetherDB.questTracker[questId] == nil then
				local questLogIndex = C_QuestLog.GetLogIndexForQuestID(questId)
				local info = C_QuestLog.GetInfo(questLogIndex)
				reportInfo("Picked Up: " .. info.title)
				watchQuest(questId)
			end
		end)
	end,

	-- Track if quest was turned in rather than abandoned.
	QUEST_TURNED_IN = function(questId)
		questsTurnedIn[questId] = true
	end,

	-- Unwatch quest and report completed or removed.
	QUEST_REMOVED = function(questId)
		table.insert(onQuestLogUpdate, function()
			C_Timer.After(0.5, function()
				if QuestTogetherDB.questTracker[questId] then
					local questTitle = QuestTogetherDB.questTracker[questId].title
					if questsTurnedIn[questId] then
						reportInfo("Completed: " .. questTitle)
						questsTurnedIn[questId] = nil
					else
						reportInfo("Removed: " .. questTitle)
					end
					QuestTogetherDB.questTracker[questId] = nil
				end
			end)
		end)
	end,

	-- Look for objective updates to tracked quests.
	UNIT_QUEST_LOG_CHANGED = function(unit)
		if unit == "player" then
			table.insert(onQuestLogUpdate, function()
				for questId, quest in pairs(QuestTogetherDB.questTracker) do
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
						if QuestTogetherDB.questTracker[questId].objectives[objectiveIndex] ~= objectiveText then
							if currentValue > 0 then
								reportInfo(objectiveText)
							end
							QuestTogetherDB.questTracker[questId].objectives[objectiveIndex] = objectiveText
						end
					end
				end
			end)
		end
	end,

	-- Run all scheduled tasks after QUEST_LOG_UPDATE.
	QUEST_LOG_UPDATE = function()
		local hasUpdates = false
		local numTasks = #onQuestLogUpdate
		if QuestTogetherDB.DEBUG.questLogUpdate and numTasks > 0 then
			debugCmd("info", "questLogUpdate: " .. #onQuestLogUpdate .. " scheduled tasks detected.")
			hasUpdates = true
		end
		if numTasks ~= nil then
			for index = 1, numTasks, 1 do
				onQuestLogUpdate[index]()
			end
			onQuestLogUpdate = {}
		end
		if QuestTogetherDB.DEBUG.questLogUpdate and hasUpdates then
			debugCmd("info", "questLogUpdate: All tasks completed.")
			hasUpdates = false
		end
	end,
}

local function eventHandler(self, event, ...)
	if EventHandlers[event] ~= nil then
		EventHandlers[event](...)
	end
	if
		QuestTogetherDB.DEBUG.events
		and event ~= "CHAT_MSG_ADDON"
		and (event ~= "QUEST_LOG_UPDATE" or QuestTogetherDB.DEBUG.questLogUpdate)
	then
		debugCmd("info", "event fired: " .. event)
		-- UIParentLoadAddOn("Blizzard_DebugTools")
		-- DevTools_Dump({ n = select("#", ...); ... })
	end
end
questTogetherFrame:SetScript("OnEvent", eventHandler)
