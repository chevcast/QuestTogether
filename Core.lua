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
QuestTogether.questLogWindowName = "QuestTogether"
QuestTogether.CHAT_BUBBLE_SIZE_MIN = 80
QuestTogether.CHAT_BUBBLE_SIZE_MAX = 160
QuestTogether.CHAT_BUBBLE_SIZE_STEP = 5
QuestTogether.CHAT_BUBBLE_DURATION_MIN = 1
QuestTogether.CHAT_BUBBLE_DURATION_MAX = 8
QuestTogether.CHAT_BUBBLE_DURATION_STEP = 0.5
QuestTogether.ANNOUNCEMENT_NEARBY_RADIUS = 5

-- Runtime state flags.
QuestTogether.isInitialized = QuestTogether.isInitialized or false
QuestTogether.hasLoggedIn = QuestTogether.hasLoggedIn or false
QuestTogether.isEnabled = QuestTogether.isEnabled or false
QuestTogether.pendingPingRequests = QuestTogether.pendingPingRequests or {}
QuestTogether.pendingQuestCompareRequests = QuestTogether.pendingQuestCompareRequests or {}

-- Work queues / state tables used by event handlers.
QuestTogether.onQuestLogUpdate = QuestTogether.onQuestLogUpdate or {}
QuestTogether.questsCompleted = QuestTogether.questsCompleted or {}
QuestTogether.worldQuestAreaStateByQuestID = QuestTogether.worldQuestAreaStateByQuestID or {}
QuestTogether.bonusObjectiveAreaStateByQuestID = QuestTogether.bonusObjectiveAreaStateByQuestID or {}

-- Default settings for SavedVariables.
-- We keep the old profile/global shape so existing logic and future migration are simple.
QuestTogether.DEFAULTS = {
	profile = {
		enabled = true,
		announceAccepted = true,
		announceCompleted = true,
		announceReadyToTurnIn = true,
		announceRemoved = true,
		announceProgress = true,
		announceWorldQuestAreaEnter = true,
		announceWorldQuestAreaLeave = true,
		announceWorldQuestProgress = true,
		announceWorldQuestCompleted = true,
		announceBonusObjectiveAreaEnter = true,
		announceBonusObjectiveAreaLeave = true,
		announceBonusObjectiveProgress = true,
		announceBonusObjectiveCompleted = true,
		showChatBubbles = true,
		hideMyOwnChatBubbles = false,
		showChatLogs = true,
		chatLogDestination = "main",
		showProgressFor = "party_nearby",
		devLogAllAnnouncements = false,
		chatBubbleSize = 100,
		chatBubbleDuration = 3,
		debugMode = false,
		emoteOnQuestCompletion = true,
		emoteOnNearbyPlayerQuestCompletion = true,
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
		questLogChatFrameID = nil,
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

QuestTogether.chatLogDestinationLabels = {
	main = "Main Chat Window",
	separate = "Separate Chat Window",
}

QuestTogether.chatLogDestinationOrder = {
	"main",
	"separate",
}
QuestTogether.chatLogLinkType = "questtogetherlog"
QuestTogether.chatLogQuestLinkType = "questtogetherquest"
QuestTogether.chatLogCoordLinkType = "questtogethercoord"
QuestTogether.questTitleLinkEventTypes = {
	QUEST_ACCEPTED = true,
	QUEST_COMPLETED = true,
	QUEST_READY_TO_TURN_IN = true,
	QUEST_REMOVED = true,
	WORLD_QUEST_ENTERED = true,
	WORLD_QUEST_LEFT = true,
	WORLD_QUEST_COMPLETED = true,
	BONUS_OBJECTIVE_ENTERED = true,
	BONUS_OBJECTIVE_LEFT = true,
	BONUS_OBJECTIVE_COMPLETED = true,
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

function QuestTogether:IsChatLogDestination(value)
	for _, candidate in ipairs(self.chatLogDestinationOrder) do
		if candidate == value then
			return true
		end
	end
	return false
end

function QuestTogether:GetChatLogDestinationLabel(value)
	return self.chatLogDestinationLabels[value] or tostring(value)
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
	GetNumChatWindows = function()
		return NUM_CHAT_WINDOWS or 0
	end,
	GetChatWindowInfo = function(chatFrameID)
		return FCF_GetChatWindowInfo(chatFrameID)
	end,
	GetChatFrameByID = function(chatFrameID)
		return FCF_GetChatFrameByID(chatFrameID)
	end,
	RemoveChatWindowChannel = function(chatFrame, channelName)
		if chatFrame and chatFrame.RemoveChannel then
			return chatFrame:RemoveChannel(channelName)
		end
		if type(ChatFrame_RemoveChannel) == "function" and chatFrame then
			return ChatFrame_RemoveChannel(chatFrame, channelName)
		end
		return nil
	end,
	AddMessageEventFilter = function(eventName, filterFunc)
		if type(ChatFrame_AddMessageEventFilter) == "function" then
			ChatFrame_AddMessageEventFilter(eventName, filterFunc)
		end
	end,
	RemoveMessageEventFilter = function(eventName, filterFunc)
		if type(ChatFrame_RemoveMessageEventFilter) == "function" then
			ChatFrame_RemoveMessageEventFilter(eventName, filterFunc)
		end
	end,
	OpenChatWindow = function(name, noDefaultChannels)
		return FCF_OpenNewWindow(name, noDefaultChannels)
	end,
	CloseChatWindow = function(chatFrame)
		return FCF_Close(chatFrame)
	end,
	SetChatWindowFontSize = function(chatFrame, fontSize)
		return FCF_SetChatWindowFontSize(nil, chatFrame, fontSize)
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
	UnitRace = function(unitToken)
		return UnitRace(unitToken)
	end,
	UnitLevel = function(unitToken)
		return UnitLevel(unitToken)
	end,
	UnitName = function(unitToken)
		return UnitName(unitToken)
	end,
	UnitIsPlayer = function(unitToken)
		return UnitIsPlayer(unitToken)
	end,
	GetQuestLogIndexForQuestID = function(questID)
		if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
			return C_QuestLog.GetLogIndexForQuestID(questID)
		end
		return nil
	end,
	IsQuestFlaggedCompleted = function(questID)
		if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
			return C_QuestLog.IsQuestFlaggedCompleted(questID)
		end
		return false
	end,
	IsQuestReadyForTurnIn = function(questID)
		if C_QuestLog and C_QuestLog.ReadyForTurnIn then
			return C_QuestLog.ReadyForTurnIn(questID)
		end
		return false
	end,
	IsQuestComplete = function(questID)
		if C_QuestLog and C_QuestLog.IsComplete then
			return C_QuestLog.IsComplete(questID)
		end
		return false
	end,
	IsOnQuest = function(questID)
		if C_QuestLog and C_QuestLog.IsOnQuest then
			return C_QuestLog.IsOnQuest(questID)
		end
		return false
	end,
	IsPushableQuest = function(questID)
		if C_QuestLog and C_QuestLog.IsPushableQuest then
			return C_QuestLog.IsPushableQuest(questID)
		end
		return false
	end,
	GetNumQuestLogEntries = function()
		if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
			return C_QuestLog.GetNumQuestLogEntries()
		end
		return 0
	end,
	GetQuestLogInfo = function(questLogIndex)
		if C_QuestLog and C_QuestLog.GetInfo then
			return C_QuestLog.GetInfo(questLogIndex)
		end
		return nil
	end,
	InviteUnit = function(name)
		if C_PartyInfo and C_PartyInfo.InviteUnit then
			return C_PartyInfo.InviteUnit(name)
		end
		return nil
	end,
	SendTell = function(name, chatFrame)
		if ChatFrameUtil and ChatFrameUtil.SendTell then
			return ChatFrameUtil.SendTell(name, chatFrame)
		end
		if type(ChatFrame_SendTell) == "function" then
			return ChatFrame_SendTell(name, chatFrame)
		end
		return nil
	end,
	AddFriend = function(name)
		if C_FriendList and C_FriendList.AddFriend then
			return C_FriendList.AddFriend(name)
		end
		return nil
	end,
	AddOrDelIgnore = function(name)
		if C_FriendList and C_FriendList.AddOrDelIgnore then
			local ok, result = pcall(C_FriendList.AddOrDelIgnore, name)
			return ok and result or nil
		end
		return nil
	end,
	IsOnIgnoredList = function(name)
		if C_FriendList and C_FriendList.IsOnIgnoredList then
			local ok, result = pcall(C_FriendList.IsOnIgnoredList, name)
			return ok and result or false
		end
		return false
	end,
	IsAddOnLoaded = function(addonName)
		if C_AddOns and C_AddOns.IsAddOnLoaded then
			return C_AddOns.IsAddOnLoaded(addonName)
		end
		return IsAddOnLoaded(addonName)
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
	GetBestMapForUnit = function(unitToken)
		if C_Map and C_Map.GetBestMapForUnit then
			return C_Map.GetBestMapForUnit(unitToken)
		end
		return nil
	end,
	GetMapInfo = function(mapID)
		if C_Map and C_Map.GetMapInfo then
			return C_Map.GetMapInfo(mapID)
		end
		return nil
	end,
	GetPlayerMapPosition = function(mapID, unitToken)
		if C_Map and C_Map.GetPlayerMapPosition then
			return C_Map.GetPlayerMapPosition(mapID, unitToken)
		end
		return nil
	end,
	IsWarModeActive = function()
		if C_PvP and C_PvP.IsWarModeDesired then
			return C_PvP.IsWarModeDesired()
		end
		if C_PvP and C_PvP.IsWarModeActive then
			return C_PvP.IsWarModeActive()
		end
		return false
	end,
	CreateUiMapPoint = function(mapID, x, y)
		if UiMapPoint and UiMapPoint.CreateFromCoordinates then
			return UiMapPoint.CreateFromCoordinates(mapID, x, y)
		end
		return nil
	end,
	CanSetUserWaypointOnMap = function(mapID)
		if C_Map and C_Map.CanSetUserWaypointOnMap then
			return C_Map.CanSetUserWaypointOnMap(mapID)
		end
		return false
	end,
	SetUserWaypoint = function(point)
		if C_Map and C_Map.SetUserWaypoint then
			return C_Map.SetUserWaypoint(point)
		end
		return nil
	end,
	SetSuperTrackedUserWaypoint = function(shouldSuperTrack)
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
			return C_SuperTrack.SetSuperTrackedUserWaypoint(shouldSuperTrack)
		end
		return nil
	end,
}

function QuestTogether:IsSecretValue(value)
	if type(issecretvalue) ~= "function" then
		return false
	end

	local ok, result = pcall(issecretvalue, value)
	return ok and result and true or false
end

function QuestTogether:SafeToNumber(value)
	if self:IsSecretValue(value) then
		return nil
	end

	return tonumber(value)
end

function QuestTogether:SafeToString(value, fallback)
	if self:IsSecretValue(value) then
		return fallback or "<secret>"
	end

	return tostring(value)
end

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
	local text = "|cff33ff99QuestTogether|r: " .. self:SafeToString(message)
	local chatFrame = self:GetChatLogFrame()
	if chatFrame and chatFrame.AddMessage then
		chatFrame:AddMessage(text)
	else
		print("QuestTogether:", self:SafeToString(message))
	end
end

function QuestTogether:PrintRaw(message)
	local text = self:SafeToString(message)
	local chatFrame = self:GetChatLogFrame()
	if chatFrame and chatFrame.AddMessage then
		chatFrame:AddMessage(text)
	else
		print(text)
	end
end

function QuestTogether:PrintChatLogSystemMessage(message)
	self:PrintChatLogRaw("|cff33ff99QuestTogether|r: " .. tostring(message))
end

function QuestTogether:GetMainChatFrame()
	return DEFAULT_CHAT_FRAME
end

function QuestTogether:GetConfiguredQuestLogChatFrameID()
	if not self.db or not self.db.global then
		return nil
	end

	local configuredID = tonumber(self.db.global.questLogChatFrameID)
	if configuredID and configuredID > 0 then
		return configuredID
	end

	return nil
end

function QuestTogether:SetConfiguredQuestLogChatFrameID(chatFrameID)
	if not self.db or not self.db.global then
		return false
	end

	local numericID = tonumber(chatFrameID)
	if numericID and numericID > 0 then
		self.db.global.questLogChatFrameID = numericID
	else
		self.db.global.questLogChatFrameID = nil
	end

	return true
end

function QuestTogether:FindQuestLogChatFrame()
	local chatWindowName = self.questLogWindowName or "QuestTogether"
	local configuredID = self:GetConfiguredQuestLogChatFrameID()
	if configuredID and self.API.GetChatFrameByID and self.API.GetChatWindowInfo then
		local configuredFrame = self.API.GetChatFrameByID(configuredID)
		local configuredName = self.API.GetChatWindowInfo(configuredID)
		if configuredFrame and configuredName == chatWindowName then
			return configuredFrame, configuredID
		end
	end

	local maxWindows = tonumber(self.API.GetNumChatWindows and self.API.GetNumChatWindows()) or 0
	for chatFrameID = 1, maxWindows do
		local frameName = self.API.GetChatWindowInfo and self.API.GetChatWindowInfo(chatFrameID)
		if frameName == chatWindowName then
			local chatFrame = nil
			if self.API.GetChatFrameByID then
				chatFrame = self.API.GetChatFrameByID(chatFrameID)
			end
			if not chatFrame then
				chatFrame = _G["ChatFrame" .. tostring(chatFrameID)]
			end
			if chatFrame then
				self:SetConfiguredQuestLogChatFrameID(chatFrameID)
				return chatFrame, chatFrameID
			end
		end
	end

	self:SetConfiguredQuestLogChatFrameID(nil)
	return nil, nil
end

function QuestTogether:GetResolvedChatLogDestination()
	local chatFrame = self:FindVisibleQuestLogChatFrame()
	if chatFrame then
		return "separate"
	end

	return "main"
end

function QuestTogether:FindVisibleQuestLogChatFrame(excludedFrame)
	local chatWindowName = self.questLogWindowName or "QuestTogether"
	local maxWindows = tonumber(self.API.GetNumChatWindows and self.API.GetNumChatWindows()) or 0

	for chatFrameID = 1, maxWindows do
		local frameName = self.API.GetChatWindowInfo and self.API.GetChatWindowInfo(chatFrameID)
		if frameName == chatWindowName then
			local chatFrame = nil
			if self.API.GetChatFrameByID then
				chatFrame = self.API.GetChatFrameByID(chatFrameID)
			end
			if not chatFrame then
				chatFrame = _G["ChatFrame" .. tostring(chatFrameID)]
			end
			if chatFrame and chatFrame ~= excludedFrame and self:IsQuestLogChatFrameVisible(chatFrame) then
				self:SetConfiguredQuestLogChatFrameID(chatFrameID)
				return chatFrame, chatFrameID
			end
		end
	end

	return nil, nil
end

function QuestTogether:IsQuestLogChatFrame(chatFrame)
	if not chatFrame or not chatFrame.GetID then
		return false
	end

	local expectedName = self.questLogWindowName or "QuestTogether"
	local frameID = chatFrame:GetID()
	local configuredID = self:GetConfiguredQuestLogChatFrameID()
	if configuredID and configuredID == frameID then
		return true
	end

	if self.API.GetChatWindowInfo then
		local frameName = self.API.GetChatWindowInfo(frameID)
		if frameName == expectedName then
			return true
		end
	end

	return false
end

function QuestTogether:IsQuestLogChatFrameVisible(chatFrame)
	if not self:IsQuestLogChatFrame(chatFrame) then
		return false
	end

	local frameShown = chatFrame.IsShown and chatFrame:IsShown()
	if frameShown then
		return true
	end

	local frameName = chatFrame.GetName and chatFrame:GetName()
	if not frameName or frameName == "" then
		return false
	end

	local chatTab = _G[frameName .. "Tab"]
	return chatTab and chatTab.IsShown and chatTab:IsShown() or false
end

function QuestTogether:HandleQuestLogChatFrameClosed(chatFrame)
	if self.suppressQuestLogChatCloseHook then
		return false
	end
	if self.isLoggingOut then
		return false
	end
	if not self:IsQuestLogChatFrame(chatFrame) then
		return false
	end

	self:SetConfiguredQuestLogChatFrameID(nil)
	local evaluateClose = function()
		if self.isLoggingOut then
			return
		end

		local existingFrame, existingID = self:FindVisibleQuestLogChatFrame(chatFrame)
		if existingFrame then
			self:SetConfiguredQuestLogChatFrameID(existingID)
			self:Debugf(
				"chat",
				"Ignoring QuestTogether chat window close because a visible replacement exists id=%s",
				tostring(existingID)
			)
			if self.RefreshOptionsWindow then
				self:RefreshOptionsWindow()
			end
			return
		end

		self:Debug("QuestTogether chat window was closed; reverting chat log destination to main chat window", "chat")
		if self.RefreshOptionsWindow then
			self:RefreshOptionsWindow()
		end
		if self.isEnabled and self.hasLoggedIn then
			self:PrintChatLogDestinationMessage()
		end
	end

	if self.API and self.API.Delay then
		self.API.Delay(0, evaluateClose)
	else
		evaluateClose()
	end

	return true
end

function QuestTogether:TryInstallChatWindowHooks()
	if self.chatWindowHooksInstalled then
		return
	end
	if type(hooksecurefunc) ~= "function" or type(FCF_Close) ~= "function" then
		return
	end

	hooksecurefunc("FCF_Close", function(frame, fallback)
		local closedFrame = fallback or frame
		QuestTogether:HandleQuestLogChatFrameClosed(closedFrame)
	end)

	self.chatWindowHooksInstalled = true
	self:Debug("Installed chat window hooks", "chat")
end

function QuestTogether:ActivateQuestLogChatFrame(chatFrame)
	if not chatFrame or not chatFrame.GetID then
		return false
	end

	local chatTab = _G[chatFrame:GetName() .. "Tab"]
	local frameShown = chatFrame.IsShown and chatFrame:IsShown()
	local tabShown = chatTab and chatTab.IsShown and chatTab:IsShown()
	if frameShown or tabShown then
		return true
	end

	if FCF_CheckShowChatFrame then
		FCF_CheckShowChatFrame(chatFrame)
		if chatTab then
			FCF_CheckShowChatFrame(chatTab)
		end
	end
	if SetChatWindowShown then
		SetChatWindowShown(chatFrame:GetID(), true)
	end
	if FCF_DockFrame and FCFDock_GetChatFrames and GENERAL_CHAT_DOCK then
		FCF_DockFrame(chatFrame, (#FCFDock_GetChatFrames(GENERAL_CHAT_DOCK) + 1), true)
	end
	if FCF_FadeInChatFrame and FCFDock_GetSelectedWindow and GENERAL_CHAT_DOCK then
		local selectedFrame = FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
		if selectedFrame then
			FCF_FadeInChatFrame(selectedFrame)
		end
	end
	if ChatFrameUtil and ChatFrameUtil.SetLastActiveWindow and chatFrame.editBox then
		ChatFrameUtil.SetLastActiveWindow(chatFrame.editBox)
	end

	self:Debugf("chat", "Reactivated existing QuestTogether chat window id=%s", tostring(chatFrame:GetID()))
	return true
end

function QuestTogether:EnsureQuestLogChatFrame()
	local existingFrame, existingID = self:FindQuestLogChatFrame()
	if existingFrame then
		self:ActivateQuestLogChatFrame(existingFrame)
		return existingFrame, existingID
	end

	if not self.API.OpenChatWindow then
		return nil, nil
	end

	local chatFrame, chatFrameID = self.API.OpenChatWindow(self.questLogWindowName or "QuestTogether", true)
	if not chatFrame then
		return nil, nil
	end

	if chatFrame.RemoveAllMessageGroups then
		chatFrame:RemoveAllMessageGroups()
	end
	if chatFrame.RemoveAllChannels then
		chatFrame:RemoveAllChannels()
	end
	self:SetConfiguredQuestLogChatFrameID(chatFrameID)
	self:Debugf("chat", "Created QuestTogether chat window id=%s", tostring(chatFrameID))
	return chatFrame, chatFrameID
end

function QuestTogether:CloseQuestLogChatFrame()
	local chatFrame, chatFrameID = self:FindQuestLogChatFrame()
	if not chatFrame then
		self:SetConfiguredQuestLogChatFrameID(nil)
		return false
	end

	if self.API.CloseChatWindow then
		self.suppressQuestLogChatCloseHook = true
		local ok, closeError = pcall(self.API.CloseChatWindow, chatFrame)
		self.suppressQuestLogChatCloseHook = false
		if not ok then
			self:Debugf("chat", "Failed to close QuestTogether chat window id=%s error=%s", tostring(chatFrameID), tostring(closeError))
		end
	end

	self:SetConfiguredQuestLogChatFrameID(nil)
	self:Debugf("chat", "Closed QuestTogether chat window id=%s", tostring(chatFrameID))
	if self.isEnabled and self.hasLoggedIn then
		self:PrintChatLogDestinationMessage()
	end
	return true
end

function QuestTogether:ReconcileQuestLogChatDestination()
	local visibleFrame, visibleID = self:FindVisibleQuestLogChatFrame()
	if visibleFrame and visibleID then
		self:SetConfiguredQuestLogChatFrameID(visibleID)
		self:Debugf("chat", "Adopted existing QuestTogether chat window id=%s on login", tostring(visibleID))
		if self.RefreshOptionsWindow then
			self:RefreshOptionsWindow()
		end
		return true
	end

	self:SetConfiguredQuestLogChatFrameID(nil)
	return false
end

function QuestTogether:ApplyMainChatFontSizeToChatFrame(chatFrame)
	if not chatFrame or not chatFrame.GetID or not self.API.GetChatWindowInfo or not self.API.SetChatWindowFontSize then
		return false
	end
	local mainChatFrame = self:GetMainChatFrame()
	if not mainChatFrame or not mainChatFrame.GetID then
		return false
	end

	local mainChatID = mainChatFrame:GetID()
	local _, fontSize = self.API.GetChatWindowInfo(mainChatID)
	fontSize = tonumber(fontSize)
	if not fontSize or fontSize <= 0 then
		return false
	end

	self.API.SetChatWindowFontSize(chatFrame, fontSize)
	self:Debugf("chat", "Applied main chat font size=%s to QuestTogether chat frame id=%s", tostring(fontSize), tostring(chatFrame:GetID()))
	return true
end

function QuestTogether:GetChatLogFrame()
	if self:GetResolvedChatLogDestination() == "separate" then
		local chatFrame = self:EnsureQuestLogChatFrame()
		if chatFrame and chatFrame.AddMessage then
			return chatFrame
		end
		self:Debug("Separate QuestTogether chat window unavailable; falling back to main chat", "chat")
	end

	return DEFAULT_CHAT_FRAME
end

function QuestTogether:PrintChatLogRaw(message)
	local text = tostring(message)
	local chatFrame = self:GetChatLogFrame()
	if chatFrame and chatFrame.AddMessage then
		chatFrame:AddMessage(text)
	else
		self:PrintRaw(text)
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

function QuestTogether:GetIconChatTagFromAsset(iconAsset, iconKind, size)
	local asset = tostring(iconAsset or "")
	if asset == "" then
		return ""
	end

	local iconSize = math.max(1, math.floor(tonumber(size) or 14))
	if iconKind == "atlas" then
		return "|A:" .. asset .. ":" .. tostring(iconSize) .. ":" .. tostring(iconSize) .. "|a"
	end

	return string.format("|T%s:%d:%d:0:0|t", asset, iconSize, iconSize)
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

function QuestTogether:NormalizeAnnouncementWarModeValue(warMode)
	if type(warMode) == "boolean" then
		return warMode
	end
	if type(warMode) == "string" then
		local normalized = string.lower(warMode)
		if warMode == "1" or normalized == "true" then
			return true
		end
		if warMode == "0" or normalized == "false" then
			return false
		end
	end
	return nil
end

function QuestTogether:GetQuestTagInfo(questId)
	local numericQuestId = tonumber(questId)
	if not numericQuestId or not C_QuestLog or not C_QuestLog.GetQuestTagInfo then
		return nil
	end

	local ok, tagInfo = pcall(C_QuestLog.GetQuestTagInfo, numericQuestId)
	if not ok or type(tagInfo) ~= "table" then
		return nil
	end

	return tagInfo
end

function QuestTogether:GetQuestDetailsThemePoiIcon(questId)
	local numericQuestId = tonumber(questId)
	if not numericQuestId or not C_QuestLog or not C_QuestLog.GetQuestDetailsTheme then
		return nil
	end

	local ok, theme = pcall(C_QuestLog.GetQuestDetailsTheme, numericQuestId)
	if not ok or type(theme) ~= "table" then
		return nil
	end

	local poiIcon = theme.poiIcon
	if type(poiIcon) ~= "string" or poiIcon == "" then
		return nil
	end

	return poiIcon
end

function QuestTogether:GetQuestTagAtlas(tagID, worldQuestType)
	if type(QuestUtils_GetQuestTagAtlas) ~= "function" then
		return nil
	end

	local ok, atlas = pcall(QuestUtils_GetQuestTagAtlas, tagID, worldQuestType)
	if not ok or type(atlas) ~= "string" or atlas == "" then
		return nil
	end

	return atlas
end

function QuestTogether:GetWorldQuestAtlasInfo(questId, tagInfo, inProgress)
	local numericQuestId = tonumber(questId)
	if not numericQuestId or type(tagInfo) ~= "table" or not QuestUtil or not QuestUtil.GetWorldQuestAtlasInfo then
		return nil
	end

	local ok, atlas = pcall(QuestUtil.GetWorldQuestAtlasInfo, numericQuestId, tagInfo, inProgress and true or false)
	if not ok or type(atlas) ~= "string" or atlas == "" then
		return nil
	end

	return atlas
end

function QuestTogether:GetQuestStateAnnouncementIconInfo(eventType, questId)
	local numericQuestId = tonumber(questId)
	if not numericQuestId or not QuestUtil then
		return nil, nil
	end

	local asset = nil
	local isAtlas = nil
	if eventType == "QUEST_ACCEPTED" and QuestUtil.GetQuestIconOfferForQuestID then
		asset, isAtlas = QuestUtil.GetQuestIconOfferForQuestID(numericQuestId)
	elseif
		(
			eventType == "QUEST_PROGRESS"
			or eventType == "QUEST_REMOVED"
			or eventType == "QUEST_COMPLETED"
			or eventType == "QUEST_READY_TO_TURN_IN"
		)
		and QuestUtil.GetQuestIconActiveForQuestID
	then
		asset, isAtlas = QuestUtil.GetQuestIconActiveForQuestID(
			numericQuestId,
			eventType == "QUEST_COMPLETED" or eventType == "QUEST_READY_TO_TURN_IN"
		)
	end

	if type(asset) ~= "string" or asset == "" then
		return nil, nil
	end

	return asset, isAtlas and "atlas" or "texture"
end

function QuestTogether:GetWorldQuestAnnouncementIconInfo(questId)
	local numericQuestId = tonumber(questId)
	if not numericQuestId then
		return "worldquest-icon", "atlas"
	end

	local tagInfo = self:GetQuestTagInfo(numericQuestId)
	if tagInfo then
		local atlas = self:GetWorldQuestAtlasInfo(numericQuestId, tagInfo, false)
		if atlas then
			return atlas, "atlas"
		end
	end

	local poiIcon = self:GetQuestDetailsThemePoiIcon(numericQuestId)
	if poiIcon then
		return poiIcon, "atlas"
	end

	return "worldquest-icon", "atlas"
end

function QuestTogether:GetBonusObjectiveAnnouncementIconInfo(eventType, questId)
	local numericQuestId = tonumber(questId)
	if numericQuestId then
		local tagInfo = self:GetQuestTagInfo(numericQuestId)
		if tagInfo then
			local atlas = self:GetQuestTagAtlas(tagInfo.tagID, tagInfo.worldQuestType)
			if atlas then
				return atlas, "atlas"
			end
		end

		local poiIcon = self:GetQuestDetailsThemePoiIcon(numericQuestId)
		if poiIcon then
			return poiIcon, "atlas"
		end
	end

	local questStateEventType = eventType
	if eventType == "BONUS_OBJECTIVE_ENTERED" then
		questStateEventType = "QUEST_ACCEPTED"
	elseif
		eventType == "BONUS_OBJECTIVE_PROGRESS"
		or eventType == "BONUS_OBJECTIVE_LEFT"
	then
		questStateEventType = "QUEST_PROGRESS"
	elseif eventType == "BONUS_OBJECTIVE_COMPLETED" then
		questStateEventType = "QUEST_COMPLETED"
	end

	local asset, kind = self:GetQuestStateAnnouncementIconInfo(questStateEventType, numericQuestId)
	if asset and kind then
		return asset, kind
	end

	return "Bonus-Objective-Star", "atlas"
end

function QuestTogether:GetAnnouncementIconInfo(eventType, questId)
	if self:IsWorldQuestAnnouncementType(eventType) then
		return self:GetWorldQuestAnnouncementIconInfo(questId)
	end
	if self:IsBonusObjectiveAnnouncementType(eventType) then
		return self:GetBonusObjectiveAnnouncementIconInfo(eventType, questId)
	end

	return self:GetQuestStateAnnouncementIconInfo(eventType, questId)
end

function QuestTogether:GetAnnouncementIconChatTag(eventType, size, iconAsset, iconKind)
	local asset = iconAsset
	local kind = iconKind
	if type(asset) ~= "string" or asset == "" then
		asset, kind = self:GetAnnouncementIconInfo(eventType, nil)
	end
	if type(asset) == "string" and asset ~= "" then
		return self:GetIconChatTagFromAsset(asset, kind, size)
	end

	return self:GetQuestIconChatTag(size)
end

function QuestTogether:GetPlayerAnnouncementLocationInfo()
	local mapID = self.API.GetBestMapForUnit and self.API.GetBestMapForUnit("player") or nil
	local zoneName = nil
	if mapID and self.API.GetMapInfo then
		local mapInfo = self.API.GetMapInfo(mapID)
		if type(mapInfo) == "table" and type(mapInfo.name) == "string" and mapInfo.name ~= "" then
			zoneName = mapInfo.name
		end
	end

	local coordX = nil
	local coordY = nil
	if mapID and self.API.GetPlayerMapPosition then
		local position = self.API.GetPlayerMapPosition(mapID, "player")
		if position then
			local rawX = position.x or (position.GetXY and select(1, position:GetXY())) or nil
			local rawY = position.y or (position.GetXY and select(2, position:GetXY())) or nil
			local numericX = self:SafeToNumber(rawX)
			local numericY = self:SafeToNumber(rawY)
			if numericX and numericY then
				coordX = numericX * 100
				coordY = numericY * 100
			end
		end
	end

	local warModeActive = self.API.IsWarModeActive and self.API.IsWarModeActive() and true or false
	return {
		mapID = mapID,
		zoneName = zoneName or "",
		coordX = coordX,
		coordY = coordY,
		warMode = warModeActive,
	}
end

function QuestTogether:IsAnnouncementSenderNearbyByLocation(locationInfo)
	if type(locationInfo) ~= "table" then
		return false
	end

	local localInfo = self.GetPlayerAnnouncementLocationInfo and self:GetPlayerAnnouncementLocationInfo() or nil
	if type(localInfo) ~= "table" then
		return false
	end

	local localZoneName = type(localInfo.zoneName) == "string" and localInfo.zoneName or ""
	local remoteZoneName = type(locationInfo.zoneName) == "string" and locationInfo.zoneName or ""
	if localZoneName == "" or remoteZoneName == "" or localZoneName ~= remoteZoneName then
		return false
	end

	local localWarMode = self:NormalizeAnnouncementWarModeValue(localInfo.warMode)
	local remoteWarMode = self:NormalizeAnnouncementWarModeValue(locationInfo.warMode)
	if localWarMode == nil or remoteWarMode == nil or localWarMode ~= remoteWarMode then
		return false
	end

	local localCoordX = self:SafeToNumber(localInfo.coordX)
	local localCoordY = self:SafeToNumber(localInfo.coordY)
	local remoteCoordX = self:SafeToNumber(locationInfo.coordX)
	local remoteCoordY = self:SafeToNumber(locationInfo.coordY)
	if not localCoordX or not localCoordY or not remoteCoordX or not remoteCoordY then
		return false
	end

	local deltaX = localCoordX - remoteCoordX
	local deltaY = localCoordY - remoteCoordY
	local radius = self.ANNOUNCEMENT_NEARBY_RADIUS or 5
	return (deltaX * deltaX + deltaY * deltaY) <= (radius * radius)
end

function QuestTogether:BuildAnnouncementLocationSuffix(locationInfo)
	if type(locationInfo) ~= "table" then
		return ""
	end

	local parts = {}
	local zoneName = type(locationInfo.zoneName) == "string" and locationInfo.zoneName or ""
	if zoneName ~= "" then
		parts[#parts + 1] = zoneName
	end

	local coordX = self:SafeToNumber(locationInfo.coordX)
	local coordY = self:SafeToNumber(locationInfo.coordY)
	if coordX and coordY then
		parts[#parts + 1] = string.format("%.1f, %.1f", coordX, coordY)
	end

	local warMode = self:NormalizeAnnouncementWarModeValue(locationInfo.warMode)
	if warMode ~= nil then
		parts[#parts + 1] = warMode and "WM On" or "WM Off"
	end

	if #parts == 0 then
		return ""
	end

	return " |cff999999[" .. table.concat(parts, " | ") .. "]|r"
end

function QuestTogether:BuildChatLogSpeakerLabel(targetName, classFile)
	local trimmedTargetName = self:GetShortDisplayName(targetName)
	local speakerLabel = trimmedTargetName ~= "" and trimmedTargetName or "QT"
	local speakerColor = self:GetClassColorCode(classFile)

	if LinkUtil and LinkUtil.FormatLink then
		local linkDisplayText = "[" .. speakerLabel .. "]"
		local linkText = LinkUtil.FormatLink(self.chatLogLinkType or "questtogetherlog", linkDisplayText, tostring(targetName or ""))
		return speakerColor .. linkText .. "|r"
	end

	return speakerColor .. speakerLabel .. "|r"
end

function QuestTogether:BuildChatLogQuestLabel(questId, questTitle)
	local numericQuestId = tonumber(questId)
	local titleText = tostring(questTitle or "")
	if not numericQuestId or titleText == "" or not LinkUtil or not LinkUtil.FormatLink then
		return titleText
	end

	local linkDisplayText = "[" .. titleText .. "]"
	return LinkUtil.FormatLink(self.chatLogQuestLinkType or "questtogetherquest", linkDisplayText, tostring(numericQuestId))
end

function QuestTogether:DecorateAnnouncementMessageWithQuestLink(message, eventType, questId)
	if not self.questTitleLinkEventTypes or not self.questTitleLinkEventTypes[eventType] then
		return tostring(message or "")
	end

	local numericQuestId = tonumber(questId)
	if not numericQuestId then
		return tostring(message or "")
	end

	local prefixText, questTitle = tostring(message or ""):match("^(.-:%s+)(.+)$")
	if not prefixText or not questTitle or questTitle == "" then
		return tostring(message or "")
	end

	return prefixText .. self:BuildChatLogQuestLabel(numericQuestId, questTitle)
end

function QuestTogether:GetQuestStatusLabel(questId)
	local numericQuestId = tonumber(questId)
	if not numericQuestId then
		return "Unknown"
	end

	if self.API and self.API.IsQuestFlaggedCompleted and self.API.IsQuestFlaggedCompleted(numericQuestId) then
		return "Completed"
	end
	if self.API and self.API.IsQuestReadyForTurnIn and self.API.IsQuestReadyForTurnIn(numericQuestId) then
		return "Ready to Turn In"
	end

	local questLogIndex = self.API and self.API.GetQuestLogIndexForQuestID and self.API.GetQuestLogIndexForQuestID(numericQuestId)
	local isOnQuest = self.API and self.API.IsOnQuest and self.API.IsOnQuest(numericQuestId)
	if questLogIndex or isOnQuest then
		if self.API and self.API.IsQuestComplete and self.API.IsQuestComplete(numericQuestId) then
			return "Objectives Complete"
		end
		return "In Progress"
	end

	return "Not Started"
end

function QuestTogether:GetQuestShareableStatusLabel(questId)
	local numericQuestId = tonumber(questId)
	if not numericQuestId then
		return "Unknown"
	end

	local questLogIndex = self.API and self.API.GetQuestLogIndexForQuestID and self.API.GetQuestLogIndexForQuestID(numericQuestId)
	local isOnQuest = self.API and self.API.IsOnQuest and self.API.IsOnQuest(numericQuestId)
	if not questLogIndex and not isOnQuest then
		return "Unknown"
	end

	if self.API and self.API.IsPushableQuest and self.API.IsPushableQuest(numericQuestId) then
		return "Yes"
	end

	return "No"
end

function QuestTogether:BuildQuestStatusMessage(questId)
	local numericQuestId = tonumber(questId)
	if not numericQuestId then
		return "Quest status unavailable."
	end

	local questTitle = self:GetQuestTitle(numericQuestId)
	local statusLabel = self:GetQuestStatusLabel(numericQuestId)
	local shareableLabel = self:GetQuestShareableStatusLabel(numericQuestId)
	return "Quest Status: " .. tostring(questTitle) .. " - " .. tostring(statusLabel) .. " | Shareable: " .. tostring(shareableLabel)
end

function QuestTogether:GetQuestStatusAnnouncementEventType(questId)
	local statusLabel = self:GetQuestStatusLabel(questId)
	if statusLabel == "Completed" or statusLabel == "Objectives Complete" then
		return "QUEST_COMPLETED"
	end
	if statusLabel == "Ready to Turn In" then
		return "QUEST_READY_TO_TURN_IN"
	end
	if statusLabel == "In Progress" then
		return "QUEST_PROGRESS"
	end
	if statusLabel == "Not Started" then
		return "QUEST_ACCEPTED"
	end

	return "QUEST_PROGRESS"
end

function QuestTogether:PrintQuestStatus(questId)
	local message = self:BuildQuestStatusMessage(questId)
	local eventType = self:GetQuestStatusAnnouncementEventType(questId)
	self:PrintConsoleAnnouncement(message, nil, nil, eventType)
end

function QuestTogether:GetQuestCompareRemoteStatusLabel(isComplete)
	if isComplete then
		return "Complete"
	end

	return "In Progress"
end

function QuestTogether:GetQuestCompareShareableToYouLabel(isPushable)
	if type(isPushable) == "boolean" then
		return isPushable and "Yes" or "No"
	end

	if type(isPushable) == "string" then
		local normalized = string.lower(isPushable)
		if isPushable == "1" or normalized == "true" then
			return "Yes"
		end
		if isPushable == "0" or normalized == "false" then
			return "No"
		end
	end

	return "Unknown"
end

function QuestTogether:BuildQuestCompareMessage(remoteName, compareEntry)
	if type(compareEntry) ~= "table" then
		return "Quest comparison unavailable."
	end

	local questId = tonumber(compareEntry.questId)
	local questTitle = tostring(compareEntry.questTitle or "")
	if questTitle == "" then
		questTitle = self:GetQuestTitle(questId)
	end
	local localStatus = self:GetQuestStatusLabel(questId)
	local shareableLabel = self:GetQuestCompareShareableToYouLabel(compareEntry.isPushable)
	local remoteStatus = self:GetQuestCompareRemoteStatusLabel(compareEntry.isComplete)
	local decoratedQuestTitle = self:BuildChatLogQuestLabel(questId, questTitle)

	return tostring(decoratedQuestTitle)
		.. " | Them: "
		.. tostring(remoteStatus)
		.. " | You: "
		.. tostring(localStatus)
		.. " | Shareable to You: "
		.. tostring(shareableLabel)
end

function QuestTogether:PrintQuestCompareMessage(remoteName, compareEntry)
	local eventType = compareEntry and compareEntry.isComplete and "QUEST_COMPLETED" or "QUEST_PROGRESS"
	local locationInfo = {
		questId = compareEntry and compareEntry.questId or nil,
	}
	self:PrintConsoleAnnouncement(
		self:BuildQuestCompareMessage(remoteName, compareEntry),
		remoteName,
		nil,
		eventType,
		nil,
		nil,
		locationInfo
	)
end

function QuestTogether:PrintQuestCompareStart(remoteName)
	self:PrintConsoleAnnouncement("Comparing quests...", remoteName, nil, "QUEST_PROGRESS")
end

function QuestTogether:PrintQuestCompareDone(remoteName, count)
	local suffix = ""
	local numericCount = self:SafeToNumber(count)
	if numericCount then
		suffix = string.format(" (%d quests)", numericCount)
	end
	self:PrintConsoleAnnouncement("Finished comparing quests" .. suffix .. ".", remoteName, nil, "QUEST_COMPLETED")
end

function QuestTogether:BuildConsoleAnnouncementMessage(targetName, message, classFile, eventType, iconAsset, iconKind, locationInfo)
	local iconTag = self:GetAnnouncementIconChatTag(eventType, 14, iconAsset, iconKind)
	local questId = type(locationInfo) == "table" and locationInfo.questId or nil
	local trimmedMessage = self:DecorateAnnouncementMessageWithQuestLink(tostring(message or ""), eventType, questId)
	local body = trimmedMessage
	local speakerText = self:BuildChatLogSpeakerLabel(targetName, classFile)

	if iconTag ~= "" then
		return iconTag .. speakerText .. "|cffffd200: " .. body .. "|r"
	end

	return speakerText .. "|cffffd200: " .. body .. "|r"
end

function QuestTogether:BuildPingResponseMessage(pongData)
	if type(pongData) ~= "table" then
		return "|cff33ff99QuestTogether|r: Pong: <invalid payload>"
	end

	local senderName = pongData.senderName or "Unknown"
	local speakerLabel = self:GetShortDisplayName(senderName)
	local speakerColor = self:GetClassColorCode(pongData.classFile)
	local coloredName = speakerColor .. tostring(speakerLabel or "Unknown") .. "|r"
	local realmName = tostring(pongData.realmName or "")
	local raceName = tostring(pongData.raceName or "")
	local className = tostring(pongData.className or pongData.classFile or "")
	local level = self:SafeToNumber(pongData.level)

	local parts = {}
	parts[#parts + 1] = coloredName
	if realmName ~= "" then
		parts[#parts + 1] = "(" .. realmName .. ")"
	end
	if level then
		parts[#parts + 1] = "Lvl " .. tostring(math.floor(level))
	end
	if raceName ~= "" then
		parts[#parts + 1] = raceName
	end
	if className ~= "" then
		parts[#parts + 1] = className
	end

	local locationBits = {}
	local zoneName = tostring(pongData.zoneName or "")
	if zoneName ~= "" then
		locationBits[#locationBits + 1] = zoneName
	end
	local coordX = self:SafeToNumber(pongData.coordX)
	local coordY = self:SafeToNumber(pongData.coordY)
	if coordX and coordY then
		locationBits[#locationBits + 1] = self:BuildPingCoordinateLabel(pongData.mapID, coordX, coordY)
	end
	local warMode = self:NormalizeAnnouncementWarModeValue(pongData.warMode)
	if warMode ~= nil then
		locationBits[#locationBits + 1] = warMode and "WM On" or "WM Off"
	end
	if #locationBits > 0 then
		parts[#parts + 1] = "- " .. table.concat(locationBits, " | ")
	end

	return "|cff33ff99QuestTogether|r: Pong: " .. table.concat(parts, " ")
end

function QuestTogether:BuildPingCoordinateLabel(mapID, coordX, coordY)
	local numericX = self:SafeToNumber(coordX)
	local numericY = self:SafeToNumber(coordY)
	if not numericX or not numericY then
		return ""
	end

	local bracketedText = string.format("[%.1f, %.1f]", numericX, numericY)
	local numericMapID = self:SafeToNumber(mapID)
	if not numericMapID or not LinkUtil or not LinkUtil.FormatLink then
		return bracketedText
	end

	local linkData = string.format("%d:%.1f:%.1f", numericMapID, numericX, numericY)
	return LinkUtil.FormatLink(self.chatLogCoordLinkType or "questtogethercoord", bracketedText, linkData)
end

function QuestTogether:PrintPingResponse(pongData)
	self:PrintChatLogRaw(self:BuildPingResponseMessage(pongData))
end

function QuestTogether:CreateTomTomWaypoint(mapID, coordX, coordY)
	local numericMapID = self:SafeToNumber(mapID)
	local numericX = self:SafeToNumber(coordX)
	local numericY = self:SafeToNumber(coordY)
	if not numericMapID or not numericX or not numericY then
		return false
	end

	if not (self.API and self.API.IsAddOnLoaded and self.API.IsAddOnLoaded("TomTom")) then
		return false
	end

	local tomTom = _G.TomTom
	if not (tomTom and tomTom.AddWaypoint) then
		return false
	end

	local ok = pcall(tomTom.AddWaypoint, tomTom, numericMapID, numericX / 100, numericY / 100, {
		title = string.format("QuestTogether %.1f, %.1f", numericX, numericY),
		from = "QuestTogether/ping",
	})
	return ok and true or false
end

function QuestTogether:CreateBlizzardWaypoint(mapID, coordX, coordY)
	local numericMapID = self:SafeToNumber(mapID)
	local numericX = self:SafeToNumber(coordX)
	local numericY = self:SafeToNumber(coordY)
	if not numericMapID or not numericX or not numericY then
		return false
	end

	if not (self.API and self.API.CanSetUserWaypointOnMap and self.API.CanSetUserWaypointOnMap(numericMapID)) then
		return false
	end

	local point = self.API.CreateUiMapPoint and self.API.CreateUiMapPoint(numericMapID, numericX / 100, numericY / 100)
	if not point then
		return false
	end

	if self.API.SetUserWaypoint then
		self.API.SetUserWaypoint(point)
	end
	if self.API.SetSuperTrackedUserWaypoint then
		self.API.SetSuperTrackedUserWaypoint(true)
	end
	return true
end

function QuestTogether:OpenPingWaypoint(mapID, coordX, coordY)
	if self:CreateTomTomWaypoint(mapID, coordX, coordY) then
		return true
	end

	return self:CreateBlizzardWaypoint(mapID, coordX, coordY)
end

function QuestTogether:PrintConsoleAnnouncement(message, targetName, classFile, eventType, iconAsset, iconKind, locationInfo)
	local speakerName = targetName
	if speakerName == nil or speakerName == "" then
		speakerName = self:GetPlayerName()
	end
	local resolvedClassFile = classFile
	if not resolvedClassFile or resolvedClassFile == "" then
		resolvedClassFile = self:GetPlayerClassFile()
	end
	self:PrintChatLogRaw(
		self:BuildConsoleAnnouncementMessage(
			speakerName,
			message,
			resolvedClassFile,
			eventType,
			iconAsset,
			iconKind,
			locationInfo
		)
	)
end

function QuestTogether:ShowChatLogSpeakerMenu(ownerFrame, speakerName)
	if not MenuUtil or not MenuUtil.CreateContextMenu then
		return false
	end

	MenuUtil.CreateContextMenu(ownerFrame, function(_, rootDescription)
		self:PopulateChatLogSpeakerMenu(rootDescription, ownerFrame, speakerName)
	end)
	return true
end

function QuestTogether:IsIgnoredPlayerName(playerName)
	local fullName = tostring(playerName or "")
	if fullName == "" or not self.API or not self.API.IsOnIgnoredList then
		return false
	end

	if self.API.IsOnIgnoredList(fullName) then
		return true
	end

	local shortName = self:GetShortDisplayName(fullName)
	if shortName ~= "" and shortName ~= fullName and self.API.IsOnIgnoredList(shortName) then
		return true
	end

	return false
end

function QuestTogether:InviteChatLogSpeaker(speakerName)
	local fullName = tostring(speakerName or "")
	if fullName == "" or not self.API or not self.API.InviteUnit then
		return false
	end

	self.API.InviteUnit(fullName)
	return true
end

function QuestTogether:WhisperChatLogSpeaker(speakerName, ownerFrame)
	local fullName = tostring(speakerName or "")
	if fullName == "" or not self.API or not self.API.SendTell then
		return false
	end

	self.API.SendTell(fullName, ownerFrame)
	return true
end

function QuestTogether:AddFriendFromChatLogSpeaker(speakerName)
	local fullName = tostring(speakerName or "")
	if fullName == "" or not self.API or not self.API.AddFriend then
		return false
	end

	self.API.AddFriend(fullName)
	return true
end

function QuestTogether:ToggleIgnoreChatLogSpeaker(speakerName)
	local fullName = tostring(speakerName or "")
	if fullName == "" or not self.API or not self.API.AddOrDelIgnore then
		return false
	end

	self.API.AddOrDelIgnore(fullName)
	return true
end

function QuestTogether:CompareQuestsWithChatLogSpeaker(speakerName)
	local fullName = self:NormalizeMemberName(speakerName) or tostring(speakerName or "")
	if fullName == "" or not self.RequestQuestCompare then
		return false
	end

	return self:RequestQuestCompare(fullName)
end

function QuestTogether:PopulateChatLogSpeakerMenu(rootDescription, ownerFrame, speakerName)
	if not rootDescription then
		return false
	end

	local fullName = tostring(speakerName or "")
	local shortName = self:GetShortDisplayName(fullName)
	local isSeparate = self:GetOption("chatLogDestination") == "separate"
	local isIgnored = false
	local ignoredOk, ignoredResult = pcall(function()
		return self:IsIgnoredPlayerName(fullName)
	end)
	if ignoredOk and ignoredResult then
		isIgnored = true
	end

	rootDescription:CreateTitle(shortName ~= "" and shortName or "QuestTogether")

	if fullName ~= "" then
		rootDescription:CreateButton("Invite", function()
			self:InviteChatLogSpeaker(fullName)
		end)
		rootDescription:CreateButton("Whisper", function()
			self:WhisperChatLogSpeaker(fullName, ownerFrame)
		end)
		rootDescription:CreateButton("Add Friend", function()
			self:AddFriendFromChatLogSpeaker(fullName)
		end)
		rootDescription:CreateButton(isIgnored and "Unignore" or "Ignore", function()
			self:ToggleIgnoreChatLogSpeaker(fullName)
		end)
		rootDescription:CreateButton("Compare Quests", function()
			self:CompareQuestsWithChatLogSpeaker(fullName)
		end)
	end

	if rootDescription.CreateDivider then
		rootDescription:CreateDivider()
	end

	local buttonText = isSeparate and "Move QuestTogether Logs to Main Window" or "Move QuestTogether Logs to Separate Window"
	rootDescription:CreateButton(buttonText, function()
		self:SetOption("chatLogDestination", isSeparate and "main" or "separate")
		if self.RefreshOptionsWindow then
			self:RefreshOptionsWindow()
		end
	end)

	return true
end

function QuestTogether:HandleChatLogSpeakerLink(link, text, linkData, contextData)
	local speakerName = linkData and linkData.options
	if not speakerName or speakerName == "" then
		return LinkProcessorResponse.Handled
	end
	if IsModifiedClick and IsModifiedClick() then
		return LinkProcessorResponse.Handled
	end
	return self:ShowChatLogSpeakerMenu(contextData and contextData.frame or UIParent, speakerName) and LinkProcessorResponse.Handled
		or LinkProcessorResponse.Handled
end

function QuestTogether:HandleChatLogQuestLink(link, text, linkData, contextData)
	local questId = linkData and linkData.options
	if not questId or questId == "" then
		return LinkProcessorResponse.Handled
	end
	if IsModifiedClick and IsModifiedClick() then
		return LinkProcessorResponse.Handled
	end

	self:PrintQuestStatus(questId)
	return LinkProcessorResponse.Handled
end

function QuestTogether:HandleChatLogCoordLink(link, text, linkData, contextData)
	local options = tostring(linkData and linkData.options or "")
	local mapID, coordX, coordY = string.match(options, "^([^:]+):([^:]+):([^:]+)$")
	if not mapID or not coordX or not coordY then
		return LinkProcessorResponse.Handled
	end
	if IsModifiedClick and IsModifiedClick() then
		return LinkProcessorResponse.Handled
	end

	self:OpenPingWaypoint(mapID, coordX, coordY)
	return LinkProcessorResponse.Handled
end

function QuestTogether:TryInstallChatLogLinkHandler()
	if self.chatLogLinkHandlerInstalled then
		return
	end
	if not LinkUtil or not LinkUtil.RegisterLinkHandler then
		return
	end

	local speakerRegistered = LinkUtil.IsLinkHandlerRegistered and LinkUtil.IsLinkHandlerRegistered(self.chatLogLinkType)
	if not speakerRegistered then
		LinkUtil.RegisterLinkHandler(self.chatLogLinkType, function(link, text, linkData, contextData)
			return QuestTogether:HandleChatLogSpeakerLink(link, text, linkData, contextData)
		end)
	end

	local questRegistered = LinkUtil.IsLinkHandlerRegistered and LinkUtil.IsLinkHandlerRegistered(self.chatLogQuestLinkType)
	if not questRegistered then
		LinkUtil.RegisterLinkHandler(self.chatLogQuestLinkType, function(link, text, linkData, contextData)
			return QuestTogether:HandleChatLogQuestLink(link, text, linkData, contextData)
		end)
	end
	local coordRegistered = LinkUtil.IsLinkHandlerRegistered and LinkUtil.IsLinkHandlerRegistered(self.chatLogCoordLinkType)
	if not coordRegistered then
		LinkUtil.RegisterLinkHandler(self.chatLogCoordLinkType, function(link, text, linkData, contextData)
			return QuestTogether:HandleChatLogCoordLink(link, text, linkData, contextData)
		end)
	end
	self.chatLogLinkHandlerInstalled = true
end

function QuestTogether:PrintChatLogDestinationMessage()
	self:PrintConsoleAnnouncement("You will now see QuestTogether logs here.")
end

function QuestTogether:Debug(message, category)
	if not self:IsDebugEnabled() then
		return false
	end

	local prefix = "Debug"
	if category and category ~= "" then
		prefix = prefix .. "[" .. tostring(category) .. "]"
	end

	self:PrintChatLogSystemMessage(prefix .. ": " .. tostring(message))
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
		QUEST_READY_TO_TURN_IN = "announceReadyToTurnIn",
		QUEST_REMOVED = "announceRemoved",
		QUEST_PROGRESS = "announceProgress",
		WORLD_QUEST_ENTERED = "announceWorldQuestAreaEnter",
		WORLD_QUEST_LEFT = "announceWorldQuestAreaLeave",
		WORLD_QUEST_PROGRESS = "announceWorldQuestProgress",
		WORLD_QUEST_COMPLETED = "announceWorldQuestCompleted",
		BONUS_OBJECTIVE_ENTERED = "announceBonusObjectiveAreaEnter",
		BONUS_OBJECTIVE_LEFT = "announceBonusObjectiveAreaLeave",
		BONUS_OBJECTIVE_PROGRESS = "announceBonusObjectiveProgress",
		BONUS_OBJECTIVE_COMPLETED = "announceBonusObjectiveCompleted",
	}

	return keysByType[eventType]
end

function QuestTogether:IsWorldQuestAnnouncementType(eventType)
	return eventType == "WORLD_QUEST_ENTERED"
		or eventType == "WORLD_QUEST_LEFT"
		or eventType == "WORLD_QUEST_PROGRESS"
		or eventType == "WORLD_QUEST_COMPLETED"
end

function QuestTogether:IsBonusObjectiveAnnouncementType(eventType)
	return eventType == "BONUS_OBJECTIVE_ENTERED"
		or eventType == "BONUS_OBJECTIVE_LEFT"
		or eventType == "BONUS_OBJECTIVE_PROGRESS"
		or eventType == "BONUS_OBJECTIVE_COMPLETED"
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

function QuestTogether:IsBonusObjective(questId)
	if not questId or not C_QuestLog or not C_QuestLog.IsQuestTask then
		return false
	end

	local ok, isTaskQuest = pcall(C_QuestLog.IsQuestTask, questId)
	if not (ok and isTaskQuest) then
		return false
	end

	return not self:IsWorldQuest(questId)
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

function QuestTogether:StripTrailingParentheticalPercent(objectiveText)
	if type(objectiveText) ~= "string" or objectiveText == "" then
		return objectiveText
	end

	local strippedText = objectiveText:gsub("%s*%(%d+%%%s*%)%s*$", "")
	if strippedText == "" then
		return objectiveText
	end

	return strippedText
end

function QuestTogether:NormalizeNameplateOptions()
	local profile = self.db.profile
	if not self:IsNameplateQuestIconStyle(profile.nameplateQuestIconStyle) then
		profile.nameplateQuestIconStyle = self.DEFAULTS.profile.nameplateQuestIconStyle
	end
end

function QuestTogether:NormalizeAnnouncementDisplayOptions()
	local profile = self.db.profile
	if profile.emoteOnQuestCompletion == nil then
		if profile.doEmotes ~= nil then
			profile.emoteOnQuestCompletion = profile.doEmotes and true or false
		else
			profile.emoteOnQuestCompletion = self.DEFAULTS.profile.emoteOnQuestCompletion
		end
	end
	if profile.emoteOnNearbyPlayerQuestCompletion == nil then
		if profile.doEmotes ~= nil then
			profile.emoteOnNearbyPlayerQuestCompletion = profile.doEmotes and true or false
		else
			profile.emoteOnNearbyPlayerQuestCompletion = self.DEFAULTS.profile.emoteOnNearbyPlayerQuestCompletion
		end
	end
	if not self:IsChatLogDestination(profile.chatLogDestination) then
		profile.chatLogDestination = self.DEFAULTS.profile.chatLogDestination
	end
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
	if key == "chatLogDestination" then
		return self:GetResolvedChatLogDestination()
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
	if key == "chatLogDestination" and not self:IsChatLogDestination(value) then
		self:Debugf("options", "Rejected option change key=%s invalid chat destination=%s", tostring(key), tostring(value))
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
	if key == "chatLogDestination" or key == "showProgressFor" or key == "chatBubbleSize" or key == "chatBubbleDuration" then
		self:NormalizeAnnouncementDisplayOptions()
	end
	if key == "chatLogDestination" and value == "separate" then
		local chatFrame = self:EnsureQuestLogChatFrame()
		if chatFrame then
			self:ApplyMainChatFontSizeToChatFrame(chatFrame)
			if self.isEnabled and self.hasLoggedIn then
				self:PrintChatLogDestinationMessage()
			end
		end
	end
	if key == "chatLogDestination" and value == "main" then
		self:CloseQuestLogChatFrame()
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
	self:Print("/qt debug [on|off|toggle] - Show or control debug mode")
	self:Print("/qt devlogall [on|off|toggle] - Show or control dev all-announcements logging")
	self:Print("/qt set <option> <value> - Set a boolean option (e.g. emoteOnQuestCompletion off)")
	self:Print("/qt get <option> - Read an option value")
	self:Print("/qt scan - Rescan your quest log now")
	self:Print("/qt ping - Request pong metadata from all QuestTogether clients in the shared channel")
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
		if flag == "" then
			self:Print("debugMode = " .. tostring(self:GetOption("debugMode")))
			return
		end
		if flag == "toggle" then
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

	if command == "devlogall" then
		local flag = string.lower(rest or "")
		if flag == "" then
			self:Print("devLogAllAnnouncements = " .. tostring(self:GetOption("devLogAllAnnouncements")))
			return
		end
		if flag == "toggle" then
			self:SetOption("devLogAllAnnouncements", not self:GetOption("devLogAllAnnouncements"))
		else
			local boolValue = self:ParseBoolean(flag)
			if boolValue == nil then
				self:Print("Usage: /qt devlogall on|off|toggle")
				return
			end
			self:SetOption("devLogAllAnnouncements", boolValue)
		end
		self:Print("devLogAllAnnouncements = " .. tostring(self:GetOption("devLogAllAnnouncements")))
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

	if command == "ping" then
		if not self.SendPingRequest then
			self:Print("Ping is unavailable.")
			return
		end

		local ok, requestIdOrError = self:SendPingRequest()
		if not ok then
			self:Print(tostring(requestIdOrError))
			return
		end

		self:PrintChatLogSystemMessage("Ping sent.")
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

	-- Area task quests can exist outside normal quest-log rows.
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
	if self.GetActiveBonusObjectiveAreaSnapshot then
		for questId, questTitle in pairs(self:GetActiveBonusObjectiveAreaSnapshot()) do
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
	if self.RefreshBonusObjectiveAreaState then
		self:RefreshBonusObjectiveAreaState(false)
	end

	self:Debugf("quest", "Scan complete questsTracked=%d", questsTracked)
	local scanMessage = questsTracked .. " quests are being monitored by QuestTogether."
	self:PrintConsoleAnnouncement(scanMessage)
	if self.BuildLocalAnnouncementEvent and self.SendAnnouncementWireEvent then
		local eventData = self:BuildLocalAnnouncementEvent("SCAN_STATUS", scanMessage)
		if eventData then
			self:SendAnnouncementWireEvent(eventData)
		end
	end
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
		isReadyForTurnIn = C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(questId) and true or false,
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
			objectiveText = tostring(progress)
				.. "% "
				.. tostring(self:StripTrailingParentheticalPercent(objectiveText))
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
	self:TryInstallChatLogLinkHandler()
	self:TryInstallChatWindowHooks()
	self:InitializeSlashCommands()
	if self.InitializeOptionsWindow then
		self:InitializeOptionsWindow()
	end
	self.isInitialized = true
	self:Debug("OnInitialize complete.", "core")
end

function QuestTogether:OnLogin()
	self.hasLoggedIn = true
	self.isLoggingOut = false
	self:ReconcileQuestLogChatDestination()
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
	if
		self.isInitialized
		and self.IsKnownNameplateAddonName
		and self:IsKnownNameplateAddonName(loadedAddonName)
		and self.RefreshNameplateAugmentation
	then
		self:Debugf("nameplate", "Detected known nameplate addon=%s; refreshing augmentation compatibility", tostring(loadedAddonName))
		self:RefreshNameplateAugmentation()
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

function QuestTogether:PLAYER_ENTERING_WORLD()
	self.isLoggingOut = false
end

function QuestTogether:PLAYER_LEAVING_WORLD()
	self.isLoggingOut = true
end

function QuestTogether:PLAYER_LOGOUT()
	self.isLoggingOut = true
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
QuestTogether.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
QuestTogether.eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
QuestTogether.eventFrame:RegisterEvent("PLAYER_LOGIN")
QuestTogether.eventFrame:RegisterEvent("PLAYER_LOGOUT")
