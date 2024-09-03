QuestTogether = LibStub("AceAddon-3.0"):NewAddon("QuestTogether", "AceConsole-3.0", "AceEvent-3.0", "AceComm-3.0")
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

QuestTogether.completionEmotes = {
	"applaud",
	"applause",
	"bow",
	"cheer",
	"clap",
	"commend",
	"congratulate",
	"curtsey",
	"dance",
	"forthealliacne",
	"forthehorde",
	"golfclap",
	"grin",
	"happy",
	"highfive",
	"huzzah",
	"impressed",
	"mountspecial",
	"praise",
	"proud",
	"purr",
	"quack",
	"roar",
	"sexy",
	"smirk",
	"strut",
	"victory",
}

function QuestTogether:Debug(message)
	if self.db.profile.debugMode then
		self:Print("Debug: " .. message)
	end
end

function QuestTogether:OnInitialize()
	-- Initialize settings database.
	self.db = LibStub("AceDB-3.0"):New("QuestTogetherDB", self.defaultOptions, true)

	-- Register options table with Blizzard UI.
	AceConfig:RegisterOptionsTable("QuestTogether", self.options, { "qt", "questtogether", "questogether" })
	self.optionsFrame = AceConfigDialog:AddToBlizOptions("QuestTogether", "QuestTogether")

	-- Register the profiles panel with Blizzard UI.
	local profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
	AceConfig:RegisterOptionsTable("QuestTogether_Profiles", profiles)
	AceConfigDialog:AddToBlizOptions("QuestTogether_Profiles", "Profiles", "QuestTogether")

	-- Register comm prefix.
	self:RegisterComm("QuestTogether")

	self:Debug("Initialized.")
end

function QuestTogether:StripColorData(text)
	return text:gsub("|c%x%x%x%x%x%x%x%x(.-)|r", "%1")
end

function QuestTogether:OnEnable()
	self:Debug("OnEnable()")

	self:RegisterEvent("QUEST_ACCEPTED")
	self:RegisterEvent("QUEST_TURNED_IN")
	self:RegisterEvent("QUEST_REMOVED")
	self:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
	self:RegisterEvent("QUEST_LOG_UPDATE")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")

	self:Debug("OnEnable() end")
end

function QuestTogether:OnDisable()
	self:Debug("OnDisable()")
end

function QuestTogether:ScanQuestLog()
	self:Debug("ScanQuestLog()")
	QuestTogether.db.char.questTracker = {}
	local numQuestLogEntries = C_QuestLog.GetNumQuestLogEntries()
	local questsTracked = 0
	for questLogIndex = 1, numQuestLogEntries do
		local info = C_QuestLog.GetInfo(questLogIndex)
		if info.isHeader == false then
			self:WatchQuest(info.questID)
			questsTracked = questsTracked + 1
		end
	end
	self:Print(questsTracked .. " quests are being monitored.")
end

function QuestTogether:WatchQuest(questId)
	self:Debug("WatchQuest(" .. questId .. ")")
	local questLogIndex = C_QuestLog.GetLogIndexForQuestID(questId)
	local info = C_QuestLog.GetInfo(questLogIndex)
	local numObjectives = GetNumQuestLeaderBoards(questLogIndex)
	self.db.char.questTracker[questId] = {
		title = info.title,
		objectives = {},
	}
	for objectiveIndex = 1, numObjectives do
		local objectiveText, type = GetQuestObjectiveInfo(questId, objectiveIndex, false)
		if type == "progressbar" then
			local progress = GetQuestProgressBarPercent(questId)
			objectiveText = progress .. "% " .. objectiveText
		end
		self.db.char.questTracker[questId].objectives[objectiveIndex] = objectiveText
	end
end

function QuestTogether:OnCommReceived(prefix, message, channel, sender)
	self:Debug("OnCommReceived(" .. prefix .. ", " .. message .. ", " .. channel .. ", " .. sender .. ")")
	-- Ignore messages from other addons.
	if prefix ~= "QuestTogether" then
		return
	end
	local cmd, arg = self:GetArgs(message, 2)
	if cmd == "cmd" then
		DEFAULT_CHAT_FRAME.editBox:SetText(arg)
		ChatEdit_SendText(DEFAULT_CHAT_FRAME.editBox, 0)
	elseif cmd == "grats" then
		DoEmote("cheer", arg)
	end
end

function QuestTogether:Announce(message)
	self:Debug("Announce(" .. message .. ")")
	local primaryChannel = channel or self.db.profile.primaryChannel
	local fallbackChannel = self.db.profile.fallbackChannel
	if primaryChannel == "console" then
		self:Print(message)
	elseif primaryChannel == "guild" and IsInGuild() then
		SendChatMessage(message, "GUILD")
	elseif primaryChannel == "instance" and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
		SendChatMessage(message, "INSTANCE_CHAT")
	elseif primaryChannel == "party" and UnitInParty("player") then
		SendChatMessage(message, "PARTY")
	elseif primaryChannel == "raid" and IsInRaid() then
		SendChatMessage(message, "RAID")
	else
		if fallbackChannel == "console" then
			self:Print(message)
		elseif fallbackChannel == "guild" and IsInGuild() then
			SendChatMessage(message, "GUILD")
		elseif fallbackChannel == "instance" and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
			SendChatMessage(message, "INSTANCE_CHAT")
		elseif fallbackChannel == "party" and UnitInParty("player") then
			SendChatMessage(message, "PARTY")
		elseif fallbackChannel == "raid" and IsInRaid() then
			SendChatMessage(message, "RAID")
		else
			self:Debug(
				"Unable to send message to primary or fallback channel: " .. primaryChannel .. "|" .. fallbackChannel
			)
			return
		end
	end
end

function QuestTogether:PLAYER_ENTERING_WORLD()
	self:Debug("PLAYER_ENTERING_WORLD()")
	C_Timer.After(10, function()
		self:ScanQuestLog()
	end)
end

function QuestTogether:QUEST_ACCEPTED(event, questId)
	self:Debug("QUEST_ACCEPTED(" .. questId .. ")")
	table.insert(self.db.char.onQuestLogUpdate, function()
		if QuestTogether.db.char.questTracker[questId] == nil then
			local questLogIndex = C_QuestLog.GetLogIndexForQuestID(questId)
			local info = C_QuestLog.GetInfo(questLogIndex)
			local message = "Quest Accepted: " .. info.title
			if self.db.profile.announceAccepted then
				self:Announce(message)
			end
			self:WatchQuest(questId)
		end
	end)
end

function QuestTogether:QUEST_TURNED_IN(event, questId)
	self:Debug("QUEST_TURNED_IN(" .. questId .. ")")
	self.db.char.questsCompleted[questId] = true
end

function QuestTogether:QUEST_REMOVED(event, questId)
	self:Debug("QUEST_REMOVED(" .. questId .. ")")
	table.insert(self.db.char.onQuestLogUpdate, function()
		C_Timer.After(0.5, function()
			if QuestTogether.db.char.questTracker[questId] then
				local questTitle = QuestTogether.db.char.questTracker[questId].title
				if self.db.char.questsCompleted[questId] then
					local message = "Quest Completed: " .. questTitle
					if self.db.profile.announceCompleted then
						self:Announce(message)
					end
					if self.db.profile.doEmotes then
						DoEmote(self.completionEmotes[math.random(#self.completionEmotes)])
					end
					self.db.char.questsCompleted[questId] = nil
				else
					local message = "Quest Removed: " .. questTitle
					if self.db.profile.announceRemoved then
						self:Announce(message)
					end
				end
				QuestTogether.db.char.questTracker[questId] = nil
			end
		end)
	end)
end

function QuestTogether:UNIT_QUEST_LOG_CHANGED(event, unit)
	self:Debug("UNIT_QUEST_LOG_CHANGED(" .. unit .. ")")
	if unit == "player" then
		table.insert(self.db.char.onQuestLogUpdate, function()
			for questId, quest in pairs(QuestTogether.db.char.questTracker) do
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
					if QuestTogether.db.char.questTracker[questId].objectives[objectiveIndex] ~= objectiveText then
						if currentValue and currentValue > 0 then
							if QuestTogether.db.profile.announceProgress then
								self:Announce(objectiveText)
							end
						end
						QuestTogether.db.char.questTracker[questId].objectives[objectiveIndex] = objectiveText
					end
				end
			end
		end)
	end
end

function QuestTogether:QUEST_LOG_UPDATE(event)
	self:Debug("QUEST_LOG_UPDATE()")
	local numTasks = #self.db.char.onQuestLogUpdate
	if numTasks ~= nil then
		for index = 1, numTasks, 1 do
			self.db.char.onQuestLogUpdate[index]()
		end
		self.db.char.onQuestLogUpdate = {}
	end
end
