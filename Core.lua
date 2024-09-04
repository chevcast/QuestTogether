QuestTogether =
	LibStub("AceAddon-3.0"):NewAddon("QuestTogether", "AceConsole-3.0", "AceEvent-3.0", "AceComm-3.0", "AceHook-3.0")
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

	-- Register events.
	self:RegisterEvent("QUEST_ACCEPTED")
	self:RegisterEvent("QUEST_TURNED_IN")
	self:RegisterEvent("QUEST_REMOVED")
	self:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
	self:RegisterEvent("QUEST_LOG_UPDATE")

	-- Schedule task to run initial quest log scan.
	table.insert(self.onQuestLogUpdate, function()
		QuestTogether:Debug("Running initial quest log scan...")
		QuestTogether:ScanQuestLog()
	end)

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
		if info.isHeader == false and info.isHidden == false then
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
