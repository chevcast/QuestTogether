QuestTogether = LibStub("AceAddon-3.0"):NewAddon("QuestTogether", "AceConsole-3.0", "AceEvent-3.0", "AceComm-3.0")
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

function QuestTogether:Debug(message)
	if self.db.profile.debugMode then
		self:Print("Debug: " .. message)
	end
end

function QuestTogether:OnInitialize()
	-- Initialize settings database.
	self.db = LibStub("AceDB-3.0"):New("QuestTogetherDB", self.defaultOptions, true)

	-- Register options table with Blizzard UI.
	AceConfig:RegisterOptionsTable("QuestTogether", self.options)
	self.optionsFrame = AceConfigDialog:AddToBlizOptions("QuestTogether", "QuestTogether")

	-- Register the profiles panel with Blizzard UI.
	local profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
	AceConfig:RegisterOptionsTable("QuestTogether_Profiles", profiles)
	AceConfigDialog:AddToBlizOptions("QuestTogether_Profiles", "Profiles", "QuestTogether")

	-- Register slash commands.
	self:RegisterChatCommand("qt", "SlashCmd")
	self:RegisterChatCommand("questtogether", "SlashCmd")
	self:RegisterChatCommand("questogether", "SlashCmd") -- Typo fallback.

	-- Register comm prefix.
	self:RegisterComm("QuestTogetherComm")

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

function QuestTogether:SlashCmd(input)
	self:Debug("WatchQuest(" .. input .. ")")
	local command, arg = self:GetArgs(input, 2)
	if command == "debug" then
		self.db.profile.debugMode = not self.db.profile.debugMode
	elseif command == "nearby" then
		self.db.profile.showNearby = not self.db.profile.showNearby
	elseif command == "enable" then
		self:Enable()
	elseif command == "disable" then
		self:Disable()
	elseif command == "channel" then
		-- Set primary chat channel.
		local channels = self.options.args.primaryChannel.values
		if arg == nil then
			self:Print("Usage: /qt channel <" .. string.lower(table.concat(channels, "||")) .. ">")
			self:Print("Current primary channel: " .. string.lower(channels[self.db.profile.primaryChannel]))
			return
		end
		local channel = string.lower(arg)
		for index, name in ipairs(channels) do
			if string.lower(self:StripColorData(name)) == channel then
				self.db.profile.primaryChannel = index
				self:Print("Primary channel set to " .. string.lower(name) .. ".")
				break
			end
		end
	elseif command == "fallback" then
		-- Set fallback chat channel.
		local channels = self.options.args.fallbackChannel.values()
		if arg == nil then
			self:Print("Usage: /qt fallback <" .. string.lower(table.concat(channels, "||")) .. ">")
			self:Print("Current fallback channel: " .. string.lower(channels[self.db.profile.fallbackChannel]))
			return
		end
		local channel = string.lower(arg)
		for key, value in pairs(channels) do
			if channel == key then
				self.db.profile.fallbackChannel = key
				self:Print("Fallback channel set to " .. string.lower(value) .. ".")
				break
			end
		end
	else
		local commandList = {
			"|cff00ff00enable|r - Enable QuestTogether.",
			"|cff00ff00disable|r - Disable QuestTogether.",
			"|cff00ff00channel|r |cff00ffff<channel>|r - Set primary chat channel.",
			"|cff00ff00fallback|r |cff00ffff<channel>|r - Set fallback chat channel.",
		}
		self:Print("|cffffff00Available Commands:|r\n" .. table.concat(commandList, "\n"))
	end
end

function QuestTogether:OnCommReceived(prefix, message, channel, sender)
	self:Debug("OnCommReceived(" .. prefix .. ", " .. message .. ", " .. channel .. ", " .. sender .. ")")
	-- Ignore messages from other addons.
	if prefix ~= "QuestTogetherComm" then
		return
	end
	if self.db.profile.showNearby then
		self:Print(sender .. ": " .. message)
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
			self:SendCommMessage("QuestTogetherComm", message, "YELL")
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
					self:SendCommMessage("QuestTogetherComm", message, "YELL")
					if self.db.profile.announceCompleted then
						self:Announce(message)
					end
					self.db.char.questsCompleted[questId] = nil
				else
					local message = "Quest Removed: " .. questTitle
					self:SendCommMessage("QuestTogetherComm", message, "YELL")
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
						if currenvValue and currentValue > 0 then
							self:SendCommMessage("QuestTogetherComm", objectiveText, "YELL")
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
