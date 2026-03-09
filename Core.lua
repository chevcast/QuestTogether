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
QuestTogether.announcementChannelName = "QuestTogetherAnnounce1"

-- Runtime state flags.
QuestTogether.isInitialized = QuestTogether.isInitialized or false
QuestTogether.hasLoggedIn = QuestTogether.hasLoggedIn or false
QuestTogether.isEnabled = QuestTogether.isEnabled or false

-- Work queues / state tables used by event handlers.
QuestTogether.onQuestLogUpdate = QuestTogether.onQuestLogUpdate or {}
QuestTogether.questsCompleted = QuestTogether.questsCompleted or {}
QuestTogether.worldQuestAreaStateByQuestID = QuestTogether.worldQuestAreaStateByQuestID or {}

-- Default settings for SavedVariables.
-- We keep the old profile/global shape so existing logic and future migration are simple.
QuestTogether.DEFAULTS = {
	profile = {
		enabled = true,
		announceAccepted = true,
		announceCompleted = true,
		announceRemoved = true,
		announceProgress = true,
		announceWorldQuestAreaEnter = true,
		announceWorldQuestAreaLeave = true,
		announceWorldQuestProgress = true,
		announceWorldQuestCompleted = true,
		showChatBubbles = true,
		hideMyOwnChatBubbles = false,
		showChatLogs = true,
		showProgressFor = "party_nearby",
		chatBubbleSize = "medium",
		chatBubbleDuration = 3,
		debugMode = false,
		doEmotes = true,
		nameplateQuestIconEnabled = true,
		nameplateQuestIconStyle = "prefix",
		nameplateQuestHealthColorEnabled = true,
		nameplateQuestHealthColor = {
			r = 0.95,
			g = 0.45,
			b = 0.05,
		},
	},
	global = {
		questTrackers = {},
		personalBubbleAnchors = {},
	},
}

QuestTogether.nameplateQuestIconStyleLabels = {
	left = "Left",
	right = "Right",
	top = "Top",
	prefix = "Prefix",
}

QuestTogether.nameplateQuestIconStyleOrder = {
	"left",
	"right",
	"top",
	"prefix",
}

QuestTogether.showProgressForLabels = {
	party_nearby = "Party & Nearby Players",
	party_only = "Party Only",
}

QuestTogether.showProgressForOrder = {
	"party_nearby",
	"party_only",
}

QuestTogether.chatBubbleSizeLabels = {
	large = "Large",
	medium = "Medium",
	small = "Small",
}

QuestTogether.chatBubbleSizeOrder = {
	"large",
	"medium",
	"small",
}

QuestTogether.chatBubbleDurationLabels = {
	[2] = "2 Seconds",
	[3] = "3 Seconds",
	[4] = "4 Seconds",
	[5] = "5 Seconds",
}

QuestTogether.chatBubbleDurationOrder = {
	2,
	3,
	4,
	5,
}

QuestTogether.DEFAULT_PERSONAL_BUBBLE_ANCHOR = {
	point = "CENTER",
	relativePoint = "CENTER",
	x = 0,
	y = 120,
}

function QuestTogether:IsShowProgressFor(value)
	for _, candidate in ipairs(self.showProgressForOrder) do
		if candidate == value then
			return true
		end
	end
	return false
end

function QuestTogether:IsChatBubbleSize(sizeKey)
	for _, candidate in ipairs(self.chatBubbleSizeOrder) do
		if candidate == sizeKey then
			return true
		end
	end
	return false
end

function QuestTogether:IsChatBubbleDuration(durationValue)
	local numericValue = tonumber(durationValue)
	for _, candidate in ipairs(self.chatBubbleDurationOrder) do
		if candidate == numericValue then
			return true
		end
	end
	return false
end

function QuestTogether:IsNameplateQuestIconStyle(styleKey)
	for _, candidate in ipairs(self.nameplateQuestIconStyleOrder) do
		if candidate == styleKey then
			return true
		end
	end
	return false
end

function QuestTogether:GetNameplateQuestIconStyleLabel(styleKey)
	return self.nameplateQuestIconStyleLabels[styleKey] or tostring(styleKey)
end

function QuestTogether:GetNameplateQuestIconStyle()
	local configured = self:GetOption("nameplateQuestIconStyle")
	if self:IsNameplateQuestIconStyle(configured) then
		return configured
	end
	return self.DEFAULTS.profile.nameplateQuestIconStyle
end

function QuestTogether:GetShowProgressForLabel(value)
	return self.showProgressForLabels[value] or tostring(value)
end

function QuestTogether:GetChatBubbleSizeLabel(sizeKey)
	return self.chatBubbleSizeLabels[sizeKey] or tostring(sizeKey)
end

function QuestTogether:GetChatBubbleDurationLabel(durationValue)
	local numericValue = tonumber(durationValue)
	return self.chatBubbleDurationLabels[numericValue] or tostring(durationValue)
end

function QuestTogether:GetPersonalBubbleAnchorKey()
	if self.GetPlayerFullName then
		local fullName = self:GetPlayerFullName()
		if fullName and fullName ~= "" then
			return fullName
		end
	end

	local playerName = self:GetPlayerName()
	if playerName and playerName ~= "" then
		return playerName
	end

	return "player"
end

function QuestTogether:GetPersonalBubbleAnchorStore()
	if not self.db or not self.db.global then
		return nil
	end

	if type(self.db.global.personalBubbleAnchors) ~= "table" then
		self.db.global.personalBubbleAnchors = {}
	end

	return self.db.global.personalBubbleAnchors
end

function QuestTogether:GetPersonalBubbleAnchor()
	local defaults = self.DEFAULT_PERSONAL_BUBBLE_ANCHOR
	local anchor = {
		point = defaults.point,
		relativePoint = defaults.relativePoint,
		x = defaults.x,
		y = defaults.y,
	}

	local store = self:GetPersonalBubbleAnchorStore()
	local key = self:GetPersonalBubbleAnchorKey()
	local saved = store and store[key] or nil
	if type(saved) ~= "table" then
		return anchor
	end

	if type(saved.point) == "string" and saved.point ~= "" then
		anchor.point = saved.point
	end
	if type(saved.relativePoint) == "string" and saved.relativePoint ~= "" then
		anchor.relativePoint = saved.relativePoint
	end
	if tonumber(saved.x) then
		anchor.x = tonumber(saved.x)
	end
	if tonumber(saved.y) then
		anchor.y = tonumber(saved.y)
	end

	return anchor
end

function QuestTogether:SetPersonalBubbleAnchor(point, relativePoint, offsetX, offsetY)
	local store = self:GetPersonalBubbleAnchorStore()
	if not store then
		return false
	end

	local defaults = self.DEFAULT_PERSONAL_BUBBLE_ANCHOR
	store[self:GetPersonalBubbleAnchorKey()] = {
		point = type(point) == "string" and point ~= "" and point or defaults.point,
		relativePoint = type(relativePoint) == "string" and relativePoint ~= "" and relativePoint or defaults.relativePoint,
		x = tonumber(offsetX) or defaults.x,
		y = tonumber(offsetY) or defaults.y,
	}

	if self.ApplySavedPersonalBubbleAnchor then
		self:ApplySavedPersonalBubbleAnchor()
	end
	if self.RefreshPersonalBubbleAnchorVisualState then
		self:RefreshPersonalBubbleAnchorVisualState()
	end
	return true
end

function QuestTogether:ResetPersonalBubbleAnchor()
	local store = self:GetPersonalBubbleAnchorStore()
	if not store then
		return false
	end

	store[self:GetPersonalBubbleAnchorKey()] = nil
	if self.ApplySavedPersonalBubbleAnchor then
		self:ApplySavedPersonalBubbleAnchor()
	end
	if self.RefreshPersonalBubbleAnchorVisualState then
		self:RefreshPersonalBubbleAnchorVisualState()
	end
	return true
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
	"QUEST_POI_UPDATE",
	"AREA_POIS_UPDATED",
	"ZONE_CHANGED",
	"ZONE_CHANGED_INDOORS",
	"ZONE_CHANGED_NEW_AREA",
	"PLAYER_ENTERING_WORLD",
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
	JoinPermanentChannel = function(name, password, chatFrameId, hasVoice)
		return JoinPermanentChannel(name, password, chatFrameId, hasVoice)
	end,
	LeaveChannelByName = function(name)
		return LeaveChannelByName(name)
	end,
	GetChannelName = function(name)
		return GetChannelName(name)
	end,
	RegisterAddonPrefix = function(prefix)
		return C_ChatInfo.RegisterAddonMessagePrefix(prefix)
	end,
	SendAddonMessage = function(prefix, message, channel, target)
		return C_ChatInfo.SendAddonMessage(prefix, message, channel, target)
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
	IsInInstance = function()
		local inInstance = IsInInstance()
		return inInstance and true or false
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
	GetTime = function()
		return GetTime()
	end,
	UnitExists = function(unitToken)
		return UnitExists(unitToken)
	end,
	UnitGUID = function(unitToken)
		return UnitGUID(unitToken)
	end,
	UnitFullName = function(unitToken)
		return UnitFullName(unitToken)
	end,
	UnitClass = function(unitToken)
		return UnitClass(unitToken)
	end,
	UnitName = function(unitToken)
		return UnitName(unitToken)
	end,
	UnitInParty = function(unitToken)
		return UnitInParty(unitToken)
	end,
	UnitInRaid = function(unitToken)
		return UnitInRaid(unitToken)
	end,
	Ambiguate = function(name, context)
		return Ambiguate(name, context)
	end,
	GetRealmName = function()
		return GetRealmName()
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

function QuestTogether:PrintRaw(message)
	local text = tostring(message)
	if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
		DEFAULT_CHAT_FRAME:AddMessage(text)
	else
		print(text)
	end
end

function QuestTogether:GetQuestIconChatTag(size)
	local texturePath = self.NAMEPLATE_QUEST_ICON_TEXTURE
	if type(texturePath) ~= "string" or texturePath == "" then
		return ""
	end

	local iconSize = math.max(1, math.floor(tonumber(size) or 14))
	return string.format("|T%s:%d:%d:0:0|t", texturePath, iconSize, iconSize)
end

function QuestTogether:GetClassColorCode(classFile)
	local colorTable = nil
	if CUSTOM_CLASS_COLORS and classFile and CUSTOM_CLASS_COLORS[classFile] then
		colorTable = CUSTOM_CLASS_COLORS[classFile]
	elseif RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile] then
		colorTable = RAID_CLASS_COLORS[classFile]
	end

	if not colorTable or not colorTable.colorStr then
		return "|cffffffff"
	end

	return "|c" .. tostring(colorTable.colorStr)
end

function QuestTogether:GetPlayerClassFile()
	local _, classFile = self.API.UnitClass("player")
	return classFile or "PRIEST"
end

function QuestTogether:GetShortDisplayName(name)
	if not name or name == "" then
		return "Unknown"
	end

	local ambiguate = self.API.Ambiguate or Ambiguate
	if type(ambiguate) == "function" then
		return ambiguate(name, "short")
	end

	return tostring(name)
end

function QuestTogether:BuildConsoleAnnouncementMessage(targetName, message, classFile)
	local iconTag = self:GetQuestIconChatTag(14)
	local trimmedTargetName = self:GetShortDisplayName(targetName)
	local trimmedMessage = tostring(message or "")
	local body = trimmedMessage
	local speakerLabel = trimmedTargetName ~= "" and trimmedTargetName or "QT"
	local speakerColor = self:GetClassColorCode(classFile)
	local speakerText = speakerColor .. speakerLabel .. "|r"

	if iconTag ~= "" then
		return iconTag .. " " .. speakerText .. "|cffffd200: " .. body .. "|r"
	end

	return speakerText .. "|cffffd200: " .. body .. "|r"
end

function QuestTogether:PrintConsoleAnnouncement(message, targetName, classFile)
	local speakerName = targetName
	if speakerName == nil or speakerName == "" then
		speakerName = self:GetPlayerName()
	end
	local resolvedClassFile = classFile
	if not resolvedClassFile or resolvedClassFile == "" then
		resolvedClassFile = self:GetPlayerClassFile()
	end
	self:PrintRaw(self:BuildConsoleAnnouncementMessage(speakerName, message, resolvedClassFile))
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

function QuestTogether:GetAnnouncementOptionKey(eventType)
	local keysByType = {
		QUEST_ACCEPTED = "announceAccepted",
		QUEST_COMPLETED = "announceCompleted",
		QUEST_REMOVED = "announceRemoved",
		QUEST_PROGRESS = "announceProgress",
		WORLD_QUEST_ENTERED = "announceWorldQuestAreaEnter",
		WORLD_QUEST_LEFT = "announceWorldQuestAreaLeave",
		WORLD_QUEST_PROGRESS = "announceWorldQuestProgress",
		WORLD_QUEST_COMPLETED = "announceWorldQuestCompleted",
	}

	return keysByType[eventType]
end

function QuestTogether:ShouldDisplayAnnouncementType(eventType)
	local optionKey = self:GetAnnouncementOptionKey(eventType)
	if not optionKey then
		return true
	end
	return self:GetOption(optionKey) and true or false
end

function QuestTogether:IsWorldQuest(questId)
	if not questId or not C_QuestLog or not C_QuestLog.IsWorldQuest then
		return false
	end

	local ok, isWorldQuest = pcall(C_QuestLog.IsWorldQuest, questId)
	return ok and isWorldQuest and true or false
end

function QuestTogether:GetQuestTitle(questId, questInfo)
	if questInfo and type(questInfo.title) == "string" and questInfo.title ~= "" then
		return questInfo.title
	end

	if C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID then
		local taskTitle = C_TaskQuest.GetQuestInfoByQuestID(questId)
		if type(taskTitle) == "string" and taskTitle ~= "" then
			return taskTitle
		end
	end

	if C_QuestLog and C_QuestLog.GetTitleForQuestID then
		local logTitle = C_QuestLog.GetTitleForQuestID(questId)
		if type(logTitle) == "string" and logTitle ~= "" then
			return logTitle
		end
	end

	return "Quest " .. tostring(questId)
end

function QuestTogether:NormalizeNameplateOptions()
	local profile = self.db.profile
	if not self:IsNameplateQuestIconStyle(profile.nameplateQuestIconStyle) then
		profile.nameplateQuestIconStyle = self.DEFAULTS.profile.nameplateQuestIconStyle
	end
end

function QuestTogether:NormalizeAnnouncementDisplayOptions()
	local profile = self.db.profile
	if not self:IsShowProgressFor(profile.showProgressFor) then
		profile.showProgressFor = self.DEFAULTS.profile.showProgressFor
	end
	if not self:IsChatBubbleSize(profile.chatBubbleSize) then
		profile.chatBubbleSize = self.DEFAULTS.profile.chatBubbleSize
	end
	if not self:IsChatBubbleDuration(profile.chatBubbleDuration) then
		profile.chatBubbleDuration = self.DEFAULTS.profile.chatBubbleDuration
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
	if key == "showProgressFor" and not self:IsShowProgressFor(value) then
		return false
	end
	if key == "chatBubbleSize" and not self:IsChatBubbleSize(value) then
		return false
	end
	if key == "chatBubbleDuration" and not self:IsChatBubbleDuration(value) then
		return false
	end
	if key == "nameplateQuestIconStyle" and not self:IsNameplateQuestIconStyle(value) then
		return false
	end
	self.db.profile[key] = value
	if key == "nameplateQuestIconStyle" then
		self:NormalizeNameplateOptions()
	end
	if key == "showProgressFor" or key == "chatBubbleSize" or key == "chatBubbleDuration" then
		self:NormalizeAnnouncementDisplayOptions()
	end
	if key == "debugMode" then
		if self.RefreshPartyRoster then
			self:RefreshPartyRoster()
		end
	end
	if
		key == "showChatBubbles"
		or key == "chatBubbleSize"
		or key == "chatBubbleDuration"
	then
		if self.RefreshPersonalBubbleAnchorVisualState then
			self:RefreshPersonalBubbleAnchorVisualState()
		end
	end
	if
		key == "nameplateQuestIconEnabled"
		or key == "nameplateQuestIconStyle"
		or key == "nameplateQuestHealthColorEnabled"
		or key == "nameplateQuestHealthColor"
	then
		if self.RefreshNameplateAugmentation then
			self:RefreshNameplateAugmentation()
		end
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
	self:NormalizeAnnouncementDisplayOptions()
	self:NormalizeNameplateOptions()
end

function QuestTogether:RegisterRuntimeEvents()
	self.registeredRuntimeEvents = self.registeredRuntimeEvents or {}
	wipe(self.registeredRuntimeEvents)

	for _, eventName in ipairs(self.runtimeEvents) do
		local ok = pcall(self.eventFrame.RegisterEvent, self.eventFrame, eventName)
		if ok then
			self.registeredRuntimeEvents[eventName] = true
		else
			self:Debug("Skipping unavailable runtime event: " .. tostring(eventName))
		end
	end
end

function QuestTogether:UnregisterRuntimeEvents()
	for eventName in pairs(self.registeredRuntimeEvents or {}) do
		pcall(self.eventFrame.UnregisterEvent, self.eventFrame, eventName)
	end

	if self.registeredRuntimeEvents then
		wipe(self.registeredRuntimeEvents)
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
	self.worldQuestAreaStateByQuestID = {}
	if self.EnsureAnnouncementChannelJoined then
		self:EnsureAnnouncementChannelJoined()
	end
	if self.RefreshWorldQuestAreaState then
		self:RefreshWorldQuestAreaState(false)
	end

	if self.EnableNameplateAugmentation then
		self:EnableNameplateAugmentation()
	end
	if self.TryInstallPersonalBubbleEditModeHooks then
		self:TryInstallPersonalBubbleEditModeHooks()
	end
	if self.RefreshPersonalBubbleAnchorVisualState then
		self:RefreshPersonalBubbleAnchorVisualState()
	end

	self:Debug("Addon enabled.")

	if self.RefreshPartyRoster then
		self:RefreshPartyRoster()
	end

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
	self.worldQuestAreaStateByQuestID = {}
	if self.LeaveAnnouncementChannel then
		self:LeaveAnnouncementChannel()
	end

	if self.DisableNameplateAugmentation then
		self:DisableNameplateAugmentation()
	end
	if self.RefreshPersonalBubbleAnchorVisualState then
		self:RefreshPersonalBubbleAnchorVisualState()
	end

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

	-- World quests in the current area can exist outside normal quest-log rows.
	-- Add them explicitly so progress announcements can still operate on them.
	if self.GetActiveWorldQuestAreaSnapshot then
		for questId, questTitle in pairs(self:GetActiveWorldQuestAreaSnapshot()) do
			if not tracker[questId] then
				self:WatchQuest(questId, { title = questTitle })
				if tracker[questId] then
					questsTracked = questsTracked + 1
				end
			end
		end
	end

	if self.RefreshWorldQuestAreaState then
		self:RefreshWorldQuestAreaState(false)
	end

	self:PrintConsoleAnnouncement(questsTracked .. " quests are being monitored by QuestTogether.")
end

-- Store the current objective text state for one quest.
function QuestTogether:WatchQuest(questId, questInfo)
	self:Debug("WatchQuest(" .. tostring(questId) .. ")")

	if not questId or not questInfo then
		return
	end

	local tracker = self:GetPlayerTracker()
	local questLogIndex = C_QuestLog.GetLogIndexForQuestID(questId)
	local questTitle = self:GetQuestTitle(questId, questInfo)

	tracker[questId] = {
		title = questTitle,
		objectives = {},
		-- Cached numeric objective values used to gate progress announcements.
		-- This avoids noisy chat lines caused by text-only objective rewrites.
		objectiveValues = {},
		isComplete = C_QuestLog.IsComplete(questId) and true or false,
	}

	if not questLogIndex then
		return
	end

	local numObjectives = GetNumQuestLeaderBoards(questLogIndex)
	for objectiveIndex = 1, numObjectives do
		local objectiveText, objectiveType, _, currentValue = GetQuestObjectiveInfo(questId, objectiveIndex, false)
		if objectiveType == "progressbar" then
			local progress = GetQuestProgressBarPercent(questId)
			objectiveText = tostring(progress) .. "% " .. tostring(objectiveText)
			currentValue = progress
		end
		tracker[questId].objectives[objectiveIndex] = objectiveText
		tracker[questId].objectiveValues[objectiveIndex] = tonumber(currentValue)
	end
end

function QuestTogether:OnInitialize()
	self:InitializeDatabase()
	if self.InitializePartyState then
		self:InitializePartyState()
	end
	if self.TryInstallNameplateHooks then
		self:TryInstallNameplateHooks()
	end
	if self.TryInstallPersonalBubbleEditModeHooks then
		self:TryInstallPersonalBubbleEditModeHooks()
	end
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
	if self.TryInstallNameplateHooks and self.isInitialized then
		self:TryInstallNameplateHooks()
	end
	if loadedAddonName == "Blizzard_EditMode" and self.TryInstallPersonalBubbleEditModeHooks then
		self:TryInstallPersonalBubbleEditModeHooks()
	end

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
