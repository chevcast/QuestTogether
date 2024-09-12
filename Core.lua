QuestTogether = LibStub("AceAddon-3.0"):NewAddon(
	"QuestTogether",
	"AceComm-3.0",
	"AceConsole-3.0",
	"AceEvent-3.0",
	"AceHook-3.0",
	"AceSerializer-3.0"
)
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

function QuestTogether:Broadcast(cmd, ...)
	local serializedData = self:Serialize(...)
	if UnitInParty("player") then
		self:SendCommMessage("QuestTogether", cmd .. ' "' .. serializedData .. '"', "PARTY")
	end
end

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
	self:RegisterEvent("SUPER_TRACKING_CHANGED")

	-- Schedule task to run initial quest log scan.
	table.insert(self.onQuestLogUpdate, function()
		QuestTogether:Debug("Running initial quest log scan...")
		QuestTogether:ScanQuestLog()
	end)
end

function QuestTogether:OnDisable()
	self:Debug("OnDisable()")
end

function QuestTogether:ScanQuestLog()
	self:Debug("ScanQuestLog()")
	QuestTogether.db.global.questTrackers[UnitName("player")] = {}
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
	self.db.global.questTrackers[UnitName("player")][questId] = {
		title = info.title,
		objectives = {},
	}
	for objectiveIndex = 1, numObjectives do
		local objectiveText, type = GetQuestObjectiveInfo(questId, objectiveIndex, false)
		if type == "progressbar" then
			local progress = GetQuestProgressBarPercent(questId)
			objectiveText = progress .. "% " .. objectiveText
		end
		self.db.global.questTrackers[UnitName("player")][questId].objectives[objectiveIndex] = objectiveText
	end
end

function QuestTogether:OnCommReceived(prefix, message, channel, sender)
	-- Ignore messages from other addons and messages from the player.
	if prefix ~= "QuestTogether" or sender == UnitName("player") then
		return
	end
	self:Debug("OnCommReceived(" .. message .. ", " .. channel .. ", " .. sender .. ")")
	local cmd, serializedData = self:GetArgs(message, 2)
	if cmd == "cmd" then
		local text = self:Deserialize(serializedData)
		DEFAULT_CHAT_FRAME.editBox:SetText(text)
		ChatEdit_SendText(DEFAULT_CHAT_FRAME.editBox, 0)
	elseif cmd == "emote" then
		local faction, _ = UnitFactionGroup("player")
		local randomEmote = self:Deserialize(serializedData)

		if IsMounted() and randomEmote == "mountspecial" then
			DoEmote("mountspecial")
		elseif randomEmote == "forthealliance" or randomEmote == "forthehorde" then
			if faction == "Alliance" then
				DoEmote("forthealliance", sender)
			elseif faction == "Horde" then
				DoEmote("forthehorde", sender)
			end
		else
			-- If the player is not mounted or the emote is not for their faction, roll for a different emote.
			if randomEmote == "mountspecial" or randomEmote == "forthealliance" or randomEmote == "forthehorde" then
				repeat
					randomEmote = self.completionEmotes[math.random(#self.completionEmotes)]
				until randomEmote ~= "mountspecial"
					and randomEmote ~= "forthealliance"
					and randomEmote ~= "forthehorde"
			end
			DoEmote(randomEmote, sender)
		end
	elseif cmd == "update-quest-tracker" then
		local action, data = self:Deserialize(serializedData)
		if action == "full" then
			self.db.global.questTrackers[sender] = data
		end
	end
end

function QuestTogether:Announce(message)
	self:Debug("Announce(" .. message .. ")")
	local primaryChannel = self.db.profile.primaryChannel
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
