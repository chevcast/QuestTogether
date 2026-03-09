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
QuestTogether.CHAT_BUBBLE_SIZE_MIN = 80
QuestTogether.CHAT_BUBBLE_SIZE_MAX = 160
QuestTogether.CHAT_BUBBLE_SIZE_STEP = 5
QuestTogether.CHAT_BUBBLE_DURATION_MIN = 1
QuestTogether.CHAT_BUBBLE_DURATION_MAX = 8
QuestTogether.CHAT_BUBBLE_DURATION_STEP = 0.5

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
		chatBubbleSize = 120,
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

function QuestTogether:NormalizeChatBubbleSizeValue(value)
	local legacyValues = {
		small = 100,
		medium = 120,
		large = 140,
	}

	if type(value) == "string" and legacyValues[value] then
		value = legacyValues[value]
	end

	local numericValue = tonumber(value)
	if not numericValue then
		return nil
	end

	local step = self.CHAT_BUBBLE_SIZE_STEP or 5
	numericValue = math.floor((numericValue / step) + 0.5) * step

	if numericValue < self.CHAT_BUBBLE_SIZE_MIN or numericValue > self.CHAT_BUBBLE_SIZE_MAX then
		return nil
	end

	return numericValue
end

function QuestTogether:IsChatBubbleSize(value)
	return self:NormalizeChatBubbleSizeValue(value) ~= nil
end

function QuestTogether:NormalizeChatBubbleDurationValue(value)
	local numericValue = tonumber(value)
	if not numericValue then
		return nil
	end

	local step = self.CHAT_BUBBLE_DURATION_STEP or 0.5
	numericValue = math.floor((numericValue / step) + 0.5) * step
	numericValue = math.floor((numericValue * 10) + 0.5) / 10

	if numericValue < self.CHAT_BUBBLE_DURATION_MIN or numericValue > self.CHAT_BUBBLE_DURATION_MAX then
		return nil
	end

	return numericValue
end

function QuestTogether:IsChatBubbleDuration(value)
	return self:NormalizeChatBubbleDurationValue(value) ~= nil
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
	local numericValue = self:NormalizeChatBubbleSizeValue(sizeKey)
	if not numericValue then
		return tostring(sizeKey)
	end

	return tostring(numericValue) .. "%"
end

function QuestTogether:GetChatBubbleDurationLabel(durationValue)
	local numericValue = self:NormalizeChatBubbleDurationValue(durationValue)
	if not numericValue then
		return tostring(durationValue)
	end

	if math.abs(numericValue - math.floor(numericValue)) < 0.001 then
		return string.format("%d sec", numericValue)
	end

	return string.format("%.1f sec", numericValue)
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

local function SortDebugKeys(keys)
	table.sort(keys, function(left, right)
		return tostring(left) < tostring(right)
	end)
end

local function FormatDebugValue(value, depth, visited)
	local valueType = type(value)
	if valueType == "nil" then
		return "nil"
	end
	if valueType == "boolean" or valueType == "number" then
		return tostring(value)
	end
	if valueType == "string" then
		return string.format("%q", value)
	end
	if valueType ~= "table" then
		return "<" .. tostring(valueType) .. ">"
	end

	depth = depth or 0
	if depth >= 2 then
		return "{...}"
	end

	visited = visited or {}
	if visited[value] then
		return "{<cycle>}"
	end
	visited[value] = true

	local keys = {}
	for key in pairs(value) do
		keys[#keys + 1] = key
	end
	SortDebugKeys(keys)

	local parts = {}
	local maxParts = 8
	for index = 1, math.min(#keys, maxParts) do
		local key = keys[index]
		parts[#parts + 1] = tostring(key) .. "=" .. FormatDebugValue(value[key], depth + 1, visited)
	end
	if #keys > maxParts then
		parts[#parts + 1] = string.format("...(%d more)", #keys - maxParts)
	end

	visited[value] = nil
	return "{" .. table.concat(parts, ", ") .. "}"
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

function QuestTogether:IsDebugEnabled()
	return self.db and self.db.profile and self.db.profile.debugMode == true
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

function QuestTogether:Debug(message, category)
	if not self:IsDebugEnabled() then
		return false
	end

	local prefix = "Debug"
	if category and category ~= "" then
		prefix = prefix .. "[" .. tostring(category) .. "]"
	end

	self:Print(prefix .. ": " .. tostring(message))
	return true
end

function QuestTogether:Debugf(category, formatString, ...)
	if formatString == nil then
		formatString = category
		category = nil
	end
	if not self:IsDebugEnabled() then
		return false
	end

	local ok, formatted = pcall(string.format, tostring(formatString), ...)
	if not ok then
		formatted = tostring(formatString)
	end
	return self:Debug(formatted, category)
end

function QuestTogether:DebugState(category, label, value)
	return self:Debug(tostring(label or "state") .. "=" .. FormatDebugValue(value), category)
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
		self:Debugf("announce", "Display gate eventType=%s option=<none> allowed=true", tostring(eventType))
		return true
	end
	local allowed = self:GetOption(optionKey) and true or false
	self:Debugf(
		"announce",
		"Display gate eventType=%s option=%s allowed=%s",
		tostring(eventType),
		tostring(optionKey),
		tostring(allowed)
	)
	return allowed
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
	profile.chatBubbleSize = self:NormalizeChatBubbleSizeValue(profile.chatBubbleSize)
		or self.DEFAULTS.profile.chatBubbleSize
	profile.chatBubbleDuration = self:NormalizeChatBubbleDurationValue(profile.chatBubbleDuration)
		or self.DEFAULTS.profile.chatBubbleDuration
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
	local oldValue = self.db.profile[key]
	if key == "showProgressFor" and not self:IsShowProgressFor(value) then
		self:Debugf("options", "Rejected option change key=%s invalidValue=%s", tostring(key), FormatDebugValue(value))
		return false
	end
	if key == "chatBubbleSize" then
		value = self:NormalizeChatBubbleSizeValue(value)
		if not value then
			self:Debugf("options", "Rejected option change key=%s invalid bubble size", tostring(key))
			return false
		end
	end
	if key == "chatBubbleDuration" then
		value = self:NormalizeChatBubbleDurationValue(value)
		if not value then
			self:Debugf("options", "Rejected option change key=%s invalid bubble duration", tostring(key))
			return false
		end
	end
	if key == "nameplateQuestIconStyle" and not self:IsNameplateQuestIconStyle(value) then
		self:Debugf("options", "Rejected option change key=%s invalid icon style=%s", tostring(key), tostring(value))
		return false
	end
	self.db.profile[key] = value
	self:Debugf(
		"options",
		"Set option key=%s old=%s new=%s",
		tostring(key),
		FormatDebugValue(oldValue),
		FormatDebugValue(self.db.profile[key])
	)
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
		if self.RefreshActivePrototypeBubbles then
			self:RefreshActivePrototypeBubbles()
		end
		if self.RefreshPersonalBubbleAnchorVisualState then
			self:RefreshPersonalBubbleAnchorVisualState()
		end
		if self.RefreshPersonalBubbleEditModeDialog then
			self:RefreshPersonalBubbleEditModeDialog()
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
		self:Debugf("quest", "Queued quest log task count=%d", #self.onQuestLogUpdate)
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
	self:DebugState("core", "db.profile", self.db.profile)
end

function QuestTogether:RegisterRuntimeEvents()
	self.registeredRuntimeEvents = self.registeredRuntimeEvents or {}
	wipe(self.registeredRuntimeEvents)

	for _, eventName in ipairs(self.runtimeEvents) do
		local ok = pcall(self.eventFrame.RegisterEvent, self.eventFrame, eventName)
		if ok then
			self.registeredRuntimeEvents[eventName] = true
			self:Debugf("events", "Registered runtime event=%s", tostring(eventName))
		else
			self:Debugf("events", "Skipping unavailable runtime event=%s", tostring(eventName))
		end
	end
end

function QuestTogether:UnregisterRuntimeEvents()
	for eventName in pairs(self.registeredRuntimeEvents or {}) do
		pcall(self.eventFrame.UnregisterEvent, self.eventFrame, eventName)
		self:Debugf("events", "Unregistered runtime event=%s", tostring(eventName))
	end

	if self.registeredRuntimeEvents then
		wipe(self.registeredRuntimeEvents)
	end
end

function QuestTogether:Enable()
	self.db.profile.enabled = true
	self:Debugf("core", "Enable requested hasLoggedIn=%s isEnabled=%s", tostring(self.hasLoggedIn), tostring(self.isEnabled))

	if not self.hasLoggedIn then
		-- We only fully enable after PLAYER_LOGIN when WoW APIs are guaranteed to be ready.
		self:Debug("Deferring enable until PLAYER_LOGIN", "core")
		return true
	end
	if self.isEnabled then
		self:Debug("Enable skipped because addon is already enabled", "core")
		return true
	end

	self:RegisterRuntimeEvents()
	self.API.RegisterAddonPrefix(self.commPrefix)
	self:Debugf("comms", "Registered addon prefix=%s", tostring(self.commPrefix))
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

	self:Debug("Addon enabled.", "core")

	if self.RefreshPartyRoster then
		self:RefreshPartyRoster()
	end

	-- Delay initial scan briefly so quest log APIs are stable right after login/reload.
	self.API.Delay(0.25, function()
		if self.isEnabled then
			self:Debug("Running delayed initial quest scan after enable", "quest")
			self:ScanQuestLog()
		end
	end)

	return true
end

function QuestTogether:Disable()
	self.db.profile.enabled = false
	self:Debugf("core", "Disable requested isEnabled=%s", tostring(self.isEnabled))

	if not self.isEnabled then
		self:Debug("Disable skipped because addon is already disabled", "core")
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

	self:Debug("Addon disabled.", "core")
	return true
end

function QuestTogether:OpenHudEditMode()
	if not EditModeManagerFrame then
		self:Debug("Blizzard_EditMode not loaded; attempting to load it", "editmode")
		pcall(UIParentLoadAddOn, "Blizzard_EditMode")
	end

	if EditModeManagerFrame and ShowUIPanel then
		self:Debug("Opening HUD Edit Mode", "editmode")
		ShowUIPanel(EditModeManagerFrame)
		return true
	end

	self:Debug("HUD Edit Mode unavailable", "editmode")
	return false
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
	self:Print("/qt bubbletest <text> - Send a QUEST_PROGRESS test event as your current target")
	self:Print("/qt bubbletest <player> <text> - Send a QUEST_PROGRESS test event as a nearby visible player")
	self:Print("/qt test - Run in-game unit tests")
end

function QuestTogether:HandleSlashCommand(input)
	local command, rest = string.match(input, "^(%S*)%s*(.-)$")
	command = string.lower(command or "")
	self:Debugf("slash", "Command=%s rest=%s", tostring(command), FormatDebugValue(rest))

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

	if command == "bubbletest" then
		if rest == nil or rest == "" then
			self:Print("Usage: /qt bubbletest <text>")
			self:Print("   or: /qt bubbletest <player> <text>")
			return
		end
		if not self.SendBubbleAnnouncementTest then
			self:Print("Bubble test is unavailable.")
			return
		end

		local senderName = nil
		local testText = rest
		if not (self.API.UnitExists and self.API.UnitExists("target")) then
			local explicitSenderName, explicitText = string.match(rest, "^(%S+)%s+(.+)$")
			if not explicitSenderName or not explicitText then
				self:Print("Usage without a target: /qt bubbletest <player> <text>")
				return
			end
			senderName = explicitSenderName
			testText = explicitText
		end

		local ok, senderNameOrError = self:SendBubbleAnnouncementTest(testText, senderName)
		if not ok then
			self:Print(senderNameOrError)
			return
		end
		self:Print("Sent bubble test announcement for " .. tostring(self:GetShortDisplayName(senderNameOrError)))
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

	self:Debug("ScanQuestLog()", "quest")

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

	self:Debugf("quest", "Scan complete questsTracked=%d", questsTracked)
	self:PrintConsoleAnnouncement(questsTracked .. " quests are being monitored by QuestTogether.")
end

-- Store the current objective text state for one quest.
function QuestTogether:WatchQuest(questId, questInfo)
	self:Debugf("quest", "WatchQuest questId=%s", tostring(questId))

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
	self:DebugState("quest", "trackedQuest", tracker[questId])

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
	self:Debug("OnInitialize complete.", "core")
end

function QuestTogether:OnLogin()
	self.hasLoggedIn = true
	self:Debugf("core", "PLAYER_LOGIN processed enabledSetting=%s", tostring(self.db and self.db.profile and self.db.profile.enabled))
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
	self:Debug("PLAYER_LOGIN()", "events")
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
