--[[
QuestTogether Core (No Ace Dependencies)

This file intentionally contains a lot of explanatory comments.
The goal is to make the addon understandable even for someone new to WoW addon development.

Key responsibilities in this file:
1. Create and expose the global addon table.
2. Initialize and maintain SavedVariables with defaults.
3. Handle addon lifecycle (load, login, enable/disable).
4. Provide utility methods used by the other files (events/comms/options/tests).
5. Implement slash commands and shared behavior like announcements.
]]

local addonName, addonTable = ...

-- Reuse an existing global table if it already exists (for safety), otherwise use the loader table.
local QuestTogether = _G.QuestTogether or addonTable or {}
_G.QuestTogether = QuestTogether

QuestTogether.addonName = addonName or "QuestTogether"
QuestTogether.commPrefix = "QuestTogether"

-- Runtime state flags.
QuestTogether.isInitialized = QuestTogether.isInitialized or false
QuestTogether.hasLoggedIn = QuestTogether.hasLoggedIn or false
QuestTogether.isEnabled = QuestTogether.isEnabled or false

-- Work queues / state tables used by event handlers.
QuestTogether.onQuestLogUpdate = QuestTogether.onQuestLogUpdate or {}
QuestTogether.questsCompleted = QuestTogether.questsCompleted or {}

-- Default settings for SavedVariables.
-- We keep the old profile/global shape so existing logic and future migration are simple.
QuestTogether.DEFAULTS = {
	profile = {
		enabled = true,
		announceAccepted = true,
		announceCompleted = true,
		announceRemoved = true,
		announceProgress = true,
		debugMode = false,
		doEmotes = true,
		fallbackChannel = "console",
		primaryChannel = "party",
	},
	global = {
		questTrackers = {},
	},
}

-- Channels users can pick from in settings.
QuestTogether.channelLabels = {
	none = "None",
	console = "Console",
	guild = "Guild",
	instance = "Instance",
	party = "Party",
	raid = "Raid",
}

QuestTogether.channelOrder = {
	"console",
	"guild",
	"instance",
	"party",
	"raid",
}

function QuestTogether:IsPrimaryChannel(channelKey)
	for _, candidate in ipairs(self.channelOrder) do
		if candidate == channelKey then
			return true
		end
	end
	return false
end

-- Emotes used when celebrating completed quests.
QuestTogether.completionEmotes = {
	"applaud",
	"bow",
	"cheer",
	"clap",
	"commend",
	"congratulate",
	"curtsey",
	"dance",
	"golfclap",
	"happy",
	"highfive",
	"huzzah",
	"impressed",
	"praise",
	"proud",
	"roar",
	"sexy",
	"smirk",
	"strut",
	"victory",
}

-- The runtime event list that should only be registered while the addon is enabled.
QuestTogether.runtimeEvents = {
	"CHAT_MSG_ADDON",
	"QUEST_ACCEPTED",
	"QUEST_TURNED_IN",
	"QUEST_REMOVED",
	"UNIT_QUEST_LOG_CHANGED",
	"QUEST_LOG_UPDATE",
	"SUPER_TRACKING_CHANGED",
	"GROUP_JOINED",
	"GROUP_ROSTER_UPDATE",
}

--[[
API wrapper table.

Why this exists:
- Production code uses these wrappers to call WoW globals.
- Tests can replace one or more wrappers to observe behavior without touching global WoW APIs.
]]
QuestTogether.API = QuestTogether.API or {
	Delay = function(seconds, callback)
		C_Timer.After(seconds, callback)
	end,
	RegisterAddonPrefix = function(prefix)
		return C_ChatInfo.RegisterAddonMessagePrefix(prefix)
	end,
	SendAddonMessage = function(prefix, message, channel, target)
		C_ChatInfo.SendAddonMessage(prefix, message, channel, target)
	end,
	SendChatMessage = function(message, channel)
		SendChatMessage(message, channel)
	end,
	IsInGuild = function()
		return IsInGuild()
	end,
	IsInInstanceGroup = function()
		return IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
	end,
	IsInParty = function()
		return UnitInParty("player")
	end,
	IsInRaid = function()
		return IsInRaid()
	end,
	DoEmote = function(emoteToken, target)
		DoEmote(emoteToken, target)
	end,
	IsMounted = function()
		return IsMounted()
	end,
	GetFaction = function()
		local faction = UnitFactionGroup("player")
		return faction
	end,
	Random = function(low, high)
		return math.random(low, high)
	end,
}

-- Deep copy helper used for defaults merging and tests.
function QuestTogether:DeepCopy(value)
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, nestedValue in pairs(value) do
		copy[key] = self:DeepCopy(nestedValue)
	end
	return copy
end

-- Merge defaults into destination recursively without deleting existing values.
function QuestTogether:ApplyDefaults(destination, defaults)
	for key, defaultValue in pairs(defaults) do
		if destination[key] == nil then
			destination[key] = self:DeepCopy(defaultValue)
		elseif type(destination[key]) == "table" and type(defaultValue) == "table" then
			self:ApplyDefaults(destination[key], defaultValue)
		end
	end
end

function QuestTogether:Print(message)
	local text = "|cff33ff99QuestTogether|r: " .. tostring(message)
	if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
		DEFAULT_CHAT_FRAME:AddMessage(text)
	else
		print("QuestTogether:", tostring(message))
	end
end

function QuestTogether:Debug(message)
	if self.db and self.db.profile and self.db.profile.debugMode then
		self:Print("Debug: " .. tostring(message))
	end
end

function QuestTogether:GetPlayerName()
	return UnitName("player") or "Unknown"
end

function QuestTogether:IsSelfSender(sender)
	if not sender then
		return false
	end
	return Ambiguate(sender, "short") == self:GetPlayerName()
end

function QuestTogether:GetChannelDisplayName(channelKey)
	return self.channelLabels[channelKey] or tostring(channelKey)
end

function QuestTogether:GetAllowedFallbackChannels(primaryChannel)
	local allowed = {}
	for _, channelKey in ipairs(self.channelOrder) do
		if channelKey ~= primaryChannel then
			allowed[#allowed + 1] = channelKey
		end
	end
	allowed[#allowed + 1] = "none"
	return allowed
end

function QuestTogether:NormalizeChannels()
	local profile = self.db.profile
	if not self:IsPrimaryChannel(profile.primaryChannel) then
		profile.primaryChannel = self.DEFAULTS.profile.primaryChannel
	end
	if not self.channelLabels[profile.fallbackChannel] then
		profile.fallbackChannel = self.DEFAULTS.profile.fallbackChannel
	end

	-- Fallback channel should never equal the primary channel.
	if profile.fallbackChannel == profile.primaryChannel then
		local fallbacks = self:GetAllowedFallbackChannels(profile.primaryChannel)
		profile.fallbackChannel = fallbacks[1] or "console"
	end
end

function QuestTogether:GetOption(key)
	if not self.db or not self.db.profile then
		return nil
	end
	return self.db.profile[key]
end

function QuestTogether:SetOption(key, value)
	if not self.db or not self.db.profile then
		return false
	end
	if key == "primaryChannel" and not self:IsPrimaryChannel(value) then
		return false
	end
	self.db.profile[key] = value
	if key == "primaryChannel" or key == "fallbackChannel" then
		self:NormalizeChannels()
	end
	return true
end

-- Compatibility helpers so old option-style code still works.
function QuestTogether:GetValue(infoOrKey)
	local key = infoOrKey
	if type(infoOrKey) == "table" then
		key = infoOrKey[#infoOrKey]
	end
	return self:GetOption(key)
end

function QuestTogether:SetValue(infoOrKey, value)
	local key = infoOrKey
	if type(infoOrKey) == "table" then
		key = infoOrKey[#infoOrKey]
	end
	return self:SetOption(key, value)
end

function QuestTogether:GetPlayerTracker()
	local playerName = self:GetPlayerName()
	if not self.db.global.questTrackers[playerName] then
		self.db.global.questTrackers[playerName] = {}
	end
	return self.db.global.questTrackers[playerName]
end

function QuestTogether:QueueQuestLogTask(taskFn)
	if type(taskFn) == "function" then
		table.insert(self.onQuestLogUpdate, taskFn)
	end
end

-- SavedVariables initializer.
function QuestTogether:InitializeDatabase()
	if type(_G.QuestTogetherDB) ~= "table" then
		_G.QuestTogetherDB = {}
	end
	self.db = _G.QuestTogetherDB
	self:ApplyDefaults(self.db, self.DEFAULTS)
	self:NormalizeChannels()
end

function QuestTogether:CanUseChatChannel(channelKey)
	if channelKey == "console" then
		return true
	elseif channelKey == "none" then
		return false
	elseif channelKey == "guild" then
		return self.API.IsInGuild()
	elseif channelKey == "instance" then
		return self.API.IsInInstanceGroup()
	elseif channelKey == "party" then
		return self.API.IsInParty()
	elseif channelKey == "raid" then
		return self.API.IsInRaid()
	end
	return false
end

function QuestTogether:SendToChannel(channelKey, message)
	if channelKey == "console" then
		self:Print(message)
		return true
	end

	if not self:CanUseChatChannel(channelKey) then
		return false
	end

	if channelKey == "guild" then
		self.API.SendChatMessage(message, "GUILD")
		return true
	elseif channelKey == "instance" then
		self.API.SendChatMessage(message, "INSTANCE_CHAT")
		return true
	elseif channelKey == "party" then
		self.API.SendChatMessage(message, "PARTY")
		return true
	elseif channelKey == "raid" then
		self.API.SendChatMessage(message, "RAID")
		return true
	end

	return false
end

function QuestTogether:Announce(message)
	self:Debug("Announce(" .. tostring(message) .. ")")

	local primaryChannel = self:GetOption("primaryChannel")
	local fallbackChannel = self:GetOption("fallbackChannel")

	if self:SendToChannel(primaryChannel, message) then
		return true
	end
	if self:SendToChannel(fallbackChannel, message) then
		return true
	end

	self:Debug(
		"Unable to send message to primary or fallback channel: "
			.. tostring(primaryChannel)
			.. "|"
			.. tostring(fallbackChannel)
	)
	return false
end

function QuestTogether:GetBestAddonChannel()
	if self.API.IsInInstanceGroup() then
		return "INSTANCE_CHAT"
	end
	if self.API.IsInRaid() then
		return "RAID"
	end
	if self.API.IsInParty() then
		return "PARTY"
	end
	return nil
end

function QuestTogether:RegisterRuntimeEvents()
	for _, eventName in ipairs(self.runtimeEvents) do
		self.eventFrame:RegisterEvent(eventName)
	end
end

function QuestTogether:UnregisterRuntimeEvents()
	for _, eventName in ipairs(self.runtimeEvents) do
		self.eventFrame:UnregisterEvent(eventName)
	end
end

function QuestTogether:Enable()
	self.db.profile.enabled = true

	if not self.hasLoggedIn then
		-- We only fully enable after PLAYER_LOGIN when WoW APIs are guaranteed to be ready.
		return true
	end
	if self.isEnabled then
		return true
	end

	self:RegisterRuntimeEvents()
	self.API.RegisterAddonPrefix(self.commPrefix)
	self.isEnabled = true

	self:Debug("Addon enabled.")

	-- Delay initial scan briefly so quest log APIs are stable right after login/reload.
	self.API.Delay(0.25, function()
		if self.isEnabled then
			self:ScanQuestLog()
		end
	end)

	return true
end

function QuestTogether:Disable()
	self.db.profile.enabled = false

	if not self.isEnabled then
		return true
	end

	self:UnregisterRuntimeEvents()
	self.isEnabled = false
	self:Debug("Addon disabled.")
	return true
end

function QuestTogether:InitializeSlashCommands()
	SLASH_QUESTTOGETHER1 = "/qt"
	SLASH_QUESTTOGETHER2 = "/questtogether"
	SLASH_QUESTTOGETHER3 = "/questogether"

	SlashCmdList.QUESTTOGETHER = function(input)
		QuestTogether:HandleSlashCommand(input or "")
	end
end

function QuestTogether:ParseBoolean(text)
	if not text then
		return nil
	end
	local normalized = string.lower(text)
	if normalized == "true" or normalized == "1" or normalized == "on" or normalized == "yes" then
		return true
	end
	if normalized == "false" or normalized == "0" or normalized == "off" or normalized == "no" then
		return false
	end
	return nil
end

function QuestTogether:PrintHelp()
	self:Print("Commands:")
	self:Print("/qt options - Open the QuestTogether options window")
	self:Print("/qt enable | disable - Enable or disable runtime behavior")
	self:Print("/qt debug on|off|toggle - Control debug mode")
	self:Print("/qt set <option> <value> - Set a boolean option (e.g. doEmotes off)")
	self:Print("/qt get <option> - Read an option value")
	self:Print("/qt channel primary <console|guild|instance|party|raid>")
	self:Print("/qt channel fallback <console|guild|instance|party|raid|none>")
	self:Print("/qt cmd <chat command> - Send a remote command to group members running this addon")
	self:Print("/qt scan - Rescan your quest log now")
	self:Print("/qt test - Run in-game unit tests")
end

function QuestTogether:HandleSlashCommand(input)
	local command, rest = string.match(input, "^(%S*)%s*(.-)$")
	command = string.lower(command or "")

	if command == "" or command == "options" then
		self:OpenOptionsWindow()
		return
	end

	if command == "help" then
		self:PrintHelp()
		return
	end

	if command == "enable" then
		self:Enable()
		self:Print("QuestTogether enabled.")
		return
	end

	if command == "disable" then
		self:Disable()
		self:Print("QuestTogether disabled.")
		return
	end

	if command == "debug" then
		local flag = string.lower(rest or "")
		if flag == "toggle" or flag == "" then
			self:SetOption("debugMode", not self:GetOption("debugMode"))
		else
			local boolValue = self:ParseBoolean(flag)
			if boolValue == nil then
				self:Print("Usage: /qt debug on|off|toggle")
				return
			end
			self:SetOption("debugMode", boolValue)
		end
		self:Print("debugMode = " .. tostring(self:GetOption("debugMode")))
		return
	end

	if command == "set" then
		local optionKey, optionValueText = string.match(rest, "^(%S+)%s+(.+)$")
		if not optionKey or not optionValueText then
			self:Print("Usage: /qt set <option> <value>")
			return
		end
		local boolValue = self:ParseBoolean(optionValueText)
		if boolValue == nil then
			self:Print("Only boolean values are supported here: true/false, on/off, 1/0")
			return
		end
		if self:GetOption(optionKey) == nil then
			self:Print("Unknown option key: " .. tostring(optionKey))
			return
		end
		self:SetOption(optionKey, boolValue)
		self:Print(optionKey .. " = " .. tostring(self:GetOption(optionKey)))
		if self.RefreshOptionsWindow then
			self:RefreshOptionsWindow()
		end
		return
	end

	if command == "get" then
		local optionKey = string.match(rest, "^(%S+)$")
		if not optionKey then
			self:Print("Usage: /qt get <option>")
			return
		end
		self:Print(optionKey .. " = " .. tostring(self:GetOption(optionKey)))
		return
	end

	if command == "channel" then
		local which, value = string.match(rest, "^(%S+)%s+(%S+)$")
		which = string.lower(which or "")
		value = string.lower(value or "")

		if which ~= "primary" and which ~= "fallback" then
			self:Print("Usage: /qt channel primary <console|guild|instance|party|raid>")
			self:Print("Usage: /qt channel fallback <console|guild|instance|party|raid|none>")
			return
		end
		if not self.channelLabels[value] then
			self:Print("Unknown channel: " .. tostring(value))
			return
		end
		if which == "primary" and value == "none" then
			self:Print("Primary channel cannot be 'none'.")
			return
		end

		if which == "primary" then
			self:SetOption("primaryChannel", value)
			self:Print("primaryChannel = " .. tostring(self:GetOption("primaryChannel")))
		else
			self:SetOption("fallbackChannel", value)
			self:Print("fallbackChannel = " .. tostring(self:GetOption("fallbackChannel")))
		end

		if self.RefreshOptionsWindow then
			self:RefreshOptionsWindow()
		end
		return
	end

	if command == "cmd" then
		if rest == "" then
			self:Print("Usage: /qt cmd <chat command>")
			return
		end
		self:Broadcast("CMD", rest)
		return
	end

	if command == "scan" then
		self:ScanQuestLog()
		return
	end

	if command == "test" or command == "runtests" then
		if self.RunTests then
			self:RunTests()
		else
			self:Print("Tests have not been loaded yet.")
		end
		return
	end

	self:Print("Unknown command: " .. tostring(command))
	self:PrintHelp()
end

-- Full quest log scan to build local objective snapshots.
function QuestTogether:ScanQuestLog()
	if not self.db or not self.db.global then
		return
	end

	self:Debug("ScanQuestLog()")

	local tracker = self:GetPlayerTracker()
	wipe(tracker)

	local numQuestLogEntries = C_QuestLog.GetNumQuestLogEntries()
	local questsTracked = 0

	for questLogIndex = 1, numQuestLogEntries do
		local questInfo = C_QuestLog.GetInfo(questLogIndex)
		if questInfo and not questInfo.isHeader and not questInfo.isHidden then
			self:WatchQuest(questInfo.questID, questInfo)
			questsTracked = questsTracked + 1
		end
	end

	self:Print(questsTracked .. " quests are being monitored.")
end

-- Store the current objective text state for one quest.
function QuestTogether:WatchQuest(questId, questInfo)
	self:Debug("WatchQuest(" .. tostring(questId) .. ")")

	if not questId or not questInfo then
		return
	end

	local tracker = self:GetPlayerTracker()
	local questLogIndex = C_QuestLog.GetLogIndexForQuestID(questId)
	if not questLogIndex then
		return
	end

	local numObjectives = GetNumQuestLeaderBoards(questLogIndex)
	tracker[questId] = {
		title = questInfo.title,
		objectives = {},
	}

	for objectiveIndex = 1, numObjectives do
		local objectiveText, objectiveType = GetQuestObjectiveInfo(questId, objectiveIndex, false)
		if objectiveType == "progressbar" then
			local progress = GetQuestProgressBarPercent(questId)
			objectiveText = tostring(progress) .. "% " .. tostring(objectiveText)
		end
		tracker[questId].objectives[objectiveIndex] = objectiveText
	end
end

function QuestTogether:OnInitialize()
	self:InitializeDatabase()
	self:InitializeSlashCommands()
	if self.InitializeOptionsWindow then
		self:InitializeOptionsWindow()
	end
	self.isInitialized = true
	self:Debug("OnInitialize complete.")
end

function QuestTogether:OnLogin()
	self.hasLoggedIn = true
	if self.db.profile.enabled then
		self:Enable()
	end
end

-- Bootstrap event handlers always registered.
function QuestTogether:ADDON_LOADED(_, loadedAddonName)
	if loadedAddonName ~= self.addonName then
		return
	end
	if not self.isInitialized then
		self:OnInitialize()
	end
end

function QuestTogether:PLAYER_LOGIN()
	if not self.isInitialized then
		self:OnInitialize()
	end
	self:OnLogin()
end

-- Shared event dispatcher for all WoW events this addon listens for.
local function DispatchEvent(_, eventName, ...)
	local handler = QuestTogether[eventName]
	if type(handler) ~= "function" then
		return
	end

	local ok, err = pcall(handler, QuestTogether, eventName, ...)
	if not ok then
		QuestTogether:Print("Error in event " .. tostring(eventName) .. ": " .. tostring(err))
	end
end

QuestTogether.eventFrame = QuestTogether.eventFrame or CreateFrame("Frame")
QuestTogether.eventFrame:SetScript("OnEvent", DispatchEvent)
QuestTogether.eventFrame:RegisterEvent("ADDON_LOADED")
QuestTogether.eventFrame:RegisterEvent("PLAYER_LOGIN")
