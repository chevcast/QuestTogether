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

local raw_tostring = tostring
local raw_string_match = string.match
local raw_string_find = string.find
local raw_issecretvalue = type(issecretvalue) == "function" and issecretvalue or nil

local function SafeText(value, fallback)
	if QuestTogether and QuestTogether.SafeToString then
		return QuestTogether:SafeToString(value, fallback ~= nil and fallback or "<secret>")
	end

	local ok, textValue = pcall(raw_tostring, value)
	if ok then
		return textValue
	end

	if fallback ~= nil then
		return fallback
	end
	return "<secret>"
end

local function SafeMatch(text, pattern)
	local safeText = SafeText(text, "")
	if safeText == "" then
		return nil
	end

	local ok, first, second, third, fourth = pcall(raw_string_match, safeText, pattern)
	if not ok then
		return nil
	end

	return first, second, third, fourth
end

local function SafeFind(text, pattern, init, plain)
	local safeText = SafeText(text, "")
	if safeText == "" then
		return nil
	end

	local ok, firstIndex, secondIndex = pcall(raw_string_find, safeText, pattern, init, plain)
	if not ok then
		return nil
	end

	return firstIndex, secondIndex
end

local tostring = SafeText

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
QuestTogether.activeProfileKey = QuestTogether.activeProfileKey or nil
QuestTogether.activeCharacterKey = QuestTogether.activeCharacterKey or nil
QuestTogether.pendingPingRequests = QuestTogether.pendingPingRequests or {}
QuestTogether.pendingQuestCompareRequests = QuestTogether.pendingQuestCompareRequests or {}
QuestTogether.testResultLogLines = QuestTogether.testResultLogLines or {}

-- Work queues / state tables used by event handlers.
QuestTogether.onQuestLogUpdate = QuestTogether.onQuestLogUpdate or {}
QuestTogether.questsCompleted = QuestTogether.questsCompleted or {}
QuestTogether.pendingQuestRemovals = QuestTogether.pendingQuestRemovals or {}
QuestTogether.worldQuestAreaStateByQuestID = QuestTogether.worldQuestAreaStateByQuestID or {}
QuestTogether.bonusObjectiveAreaStateByQuestID = QuestTogether.bonusObjectiveAreaStateByQuestID or {}
QuestTogether.questBlobInsideStateByQuestID = QuestTogether.questBlobInsideStateByQuestID or {}

-- Default settings for SavedVariables.
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
		-- Stored per profile so each character/profile can pick its own chat tab.
		questLogChatFrameID = nil,
	},
	global = {
		questTrackers = {},
		personalBubbleAnchors = {},
		-- Legacy location kept for migration from older versions.
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

	local numericValue = self:SafeToNumber(value)
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
	local numericValue = self:SafeToNumber(value)
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
	local numericX = self:SafeToNumber(saved.x)
	if numericX ~= nil then
		anchor.x = numericX
	end
	local numericY = self:SafeToNumber(saved.y)
	if numericY ~= nil then
		anchor.y = numericY
	end

	return anchor
end

function QuestTogether:SetPersonalBubbleAnchor(point, relativePoint, offsetX, offsetY)
	local store = self:GetPersonalBubbleAnchorStore()
	if not store then
		return false
	end

	local defaults = self.DEFAULT_PERSONAL_BUBBLE_ANCHOR
	local numericOffsetX = self:SafeToNumber(offsetX)
	local numericOffsetY = self:SafeToNumber(offsetY)
	store[self:GetPersonalBubbleAnchorKey()] = {
		point = type(point) == "string" and point ~= "" and point or defaults.point,
		relativePoint = type(relativePoint) == "string" and relativePoint ~= "" and relativePoint or defaults.relativePoint,
		x = numericOffsetX ~= nil and numericOffsetX or defaults.x,
		y = numericOffsetY ~= nil and numericOffsetY or defaults.y,
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
	"PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED",
	"ZONE_CHANGED",
	"ZONE_CHANGED_INDOORS",
	"ZONE_CHANGED_NEW_AREA",
	"PLAYER_REGEN_ENABLED",
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
-- API wrapper layer:
-- Guard Blizzard calls that can throw (invalid token, secure context, or transient data race)
-- so runtime features fail soft instead of tainting shared execution paths.
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
			local ok, result = pcall(C_ChatInfo.RegisterAddonMessagePrefix, prefix)
			return ok and result or nil
		end,
		SendAddonMessage = function(prefix, message, channel, target)
			local ok, result = pcall(C_ChatInfo.SendAddonMessage, prefix, message, channel, target)
			return ok and result or nil
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
	InCombatLockdown = function()
		if InCombatLockdown then
			return InCombatLockdown() and true or false
		end
		return false
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
			local ok, exists = pcall(UnitExists, unitToken)
			return ok and exists and true or false
		end,
	UnitGUID = function(unitToken)
		local ok, guidValue = pcall(UnitGUID, unitToken)
		if not ok then
			return nil
		end
		if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(guidValue) then
			return nil
		end
		return guidValue
	end,
	UnitFullName = function(unitToken)
		local ok, unitName, unitRealm = pcall(UnitFullName, unitToken)
		if not ok then
			return nil, nil
		end
		if QuestTogether and QuestTogether.IsSecretValue then
			if QuestTogether:IsSecretValue(unitName) then
				unitName = nil
			end
			if QuestTogether:IsSecretValue(unitRealm) then
				unitRealm = nil
			end
		end
		return unitName, unitRealm
	end,
	UnitClass = function(unitToken)
		local ok, className, classFile = pcall(UnitClass, unitToken)
		if not ok then
			return nil, nil
		end
		if QuestTogether and QuestTogether.IsSecretValue then
			if QuestTogether:IsSecretValue(className) then
				className = nil
			end
			if QuestTogether:IsSecretValue(classFile) then
				classFile = nil
			end
		end
		return className, classFile
	end,
	UnitRace = function(unitToken)
		local ok, raceName = pcall(UnitRace, unitToken)
		if not ok then
			return nil
		end
		if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(raceName) then
			return nil
		end
		return raceName
	end,
	UnitLevel = function(unitToken)
		local ok, levelValue = pcall(UnitLevel, unitToken)
		if not ok then
			return nil
		end
		if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(levelValue) then
			return nil
		end
		return levelValue
	end,
	UnitName = function(unitToken)
		local ok, unitName = pcall(UnitName, unitToken)
		if not ok then
			return nil
		end
		if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(unitName) then
			return nil
		end
		return unitName
	end,
		UnitHealth = function(unitToken)
			local ok, unitHealth = pcall(UnitHealth, unitToken)
			if not ok then
				return nil
			end
			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(unitHealth) then
				return nil
			end
			return unitHealth
		end,
		UnitHealthMax = function(unitToken)
			local ok, maxHealth = pcall(UnitHealthMax, unitToken)
			if not ok then
				return nil
			end
			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(maxHealth) then
				return nil
			end
			return maxHealth
		end,
		UnitIsDeadOrGhost = function(unitToken)
			if type(UnitIsDeadOrGhost) == "function" then
				local ok, result = pcall(UnitIsDeadOrGhost, unitToken)
				return ok and result and true or false
			end
			if type(UnitIsDead) == "function" then
				local ok, result = pcall(UnitIsDead, unitToken)
				return ok and result and true or false
			end
			return false
		end,
		UnitIsPlayer = function(unitToken)
			local ok, result = pcall(UnitIsPlayer, unitToken)
			return ok and result and true or false
		end,
		GetQuestLogIndexForQuestID = function(questID)
			if InCombatLockdown and InCombatLockdown() then
				return nil
			end
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return nil
			end
			if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
				local ok, questLogIndex = pcall(C_QuestLog.GetLogIndexForQuestID, numericQuestID)
				if not ok then
					return nil
				end
				if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(questLogIndex) then
					return nil
				end
				return questLogIndex
			end
			return nil
		end,
		IsQuestFlaggedCompleted = function(questID)
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return false
			end
			if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
				local ok, isCompleted = pcall(C_QuestLog.IsQuestFlaggedCompleted, numericQuestID)
				return ok and isCompleted and true or false
			end
			return false
		end,
		IsQuestReadyForTurnIn = function(questID)
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return false
			end
			if C_QuestLog and C_QuestLog.ReadyForTurnIn then
				local ok, isReady = pcall(C_QuestLog.ReadyForTurnIn, numericQuestID)
				return ok and isReady and true or false
			end
			return false
		end,
		IsQuestComplete = function(questID)
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return false
			end
			if C_QuestLog and C_QuestLog.IsComplete then
				local ok, isComplete = pcall(C_QuestLog.IsComplete, numericQuestID)
				return ok and isComplete and true or false
			end
			return false
		end,
		IsQuestOnMap = function(questID)
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return false
			end
			if C_QuestLog and C_QuestLog.IsOnMap then
				local ok, isOnMap = pcall(C_QuestLog.IsOnMap, numericQuestID)
				if not ok then
					return false
				end
				if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(isOnMap) then
					return false
				end
				if type(isOnMap) == "boolean" then
					return isOnMap
				end
				local numericFlag = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(isOnMap) or nil
				if numericFlag ~= nil then
					return numericFlag ~= 0
				end
			end
			return false
		end,
		IsTaskQuestActive = function(questID)
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return nil
			end
			if C_TaskQuest and C_TaskQuest.IsActive then
				local ok, isActive = pcall(C_TaskQuest.IsActive, numericQuestID)
				if not ok then
					return nil
				end
				if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(isActive) then
					return nil
				end
				if type(isActive) == "boolean" then
					return isActive
				end
				local numericFlag = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(isActive) or nil
				if numericFlag ~= nil then
					return numericFlag ~= 0
				end
			end
			return nil
		end,
		GetTaskInfo = function(questID)
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return nil, nil, nil, nil, nil
			end
			if type(GetTaskInfo) ~= "function" then
				return nil, nil, nil, nil, nil
			end

			local ok, isInArea, isOnMap, numObjectives, taskName, displayAsObjective = pcall(GetTaskInfo, numericQuestID)
			if not ok then
				return nil, nil, nil, nil, nil
			end

			local function NormalizeBooleanFlag(rawValue)
				if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(rawValue) then
					return nil
				end
				if type(rawValue) == "boolean" then
					return rawValue
				end
				local numericFlag = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(rawValue) or nil
				if numericFlag ~= nil then
					return numericFlag ~= 0
				end
				return nil
			end

			local normalizedInArea = NormalizeBooleanFlag(isInArea)
			local normalizedOnMap = NormalizeBooleanFlag(isOnMap)
			local normalizedDisplayAsObjective = NormalizeBooleanFlag(displayAsObjective)

			local normalizedObjectiveCount = nil
			if not (QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(numObjectives)) then
				normalizedObjectiveCount = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(numObjectives)
					or nil
				if normalizedObjectiveCount ~= nil then
					normalizedObjectiveCount = math.floor(normalizedObjectiveCount + 0.5)
					if normalizedObjectiveCount < 0 then
						normalizedObjectiveCount = 0
					end
				end
			end

			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(taskName) then
				taskName = nil
			end
			if type(taskName) ~= "string" or taskName == "" then
				taskName = nil
			end

			return normalizedInArea, normalizedOnMap, normalizedObjectiveCount, taskName, normalizedDisplayAsObjective
		end,
		GetPlayerMapID = function(unitToken)
			if not (C_Map and C_Map.GetBestMapForUnit) then
				return nil
			end

			local normalizedUnitToken = type(unitToken) == "string" and unitToken ~= "" and unitToken or "player"
			local ok, mapID = pcall(C_Map.GetBestMapForUnit, normalizedUnitToken)
			if not ok then
				return nil
			end
			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(mapID) then
				return nil
			end
			local numericMapID = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(mapID) or nil
			if not numericMapID or numericMapID <= 0 then
				return nil
			end
			return math.floor(numericMapID + 0.5)
		end,
		GetLocalTaskQuests = function()
			if type(GetTasksTable) ~= "function" then
				return nil
			end

			-- Blizzard's objective tracker uses GetTasksTable() as the local-area task list.
			-- Call it behind pcall for transient quest-log races, then copy only scalar quest IDs
			-- out so we never retain Blizzard-owned tables.
			local ok, tasks = pcall(GetTasksTable)
			if not ok or (QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(tasks)) then
				return nil
			end
			if type(tasks) ~= "table" then
				return nil
			end

			local questIds = {}
			for index = 1, #tasks do
				local questID = tasks[index]
				if not (QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(questID)) then
					local numericQuestID = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(questID)
						or nil
					if numericQuestID and numericQuestID > 0 then
						questIds[#questIds + 1] = math.floor(numericQuestID + 0.5)
					end
				end
			end

			return questIds
		end,
		GetTaskQuestsOnMap = function(mapID)
			local numericMapID = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(mapID) or nil
			if not numericMapID or numericMapID <= 0 then
				return nil
			end
			numericMapID = math.floor(numericMapID + 0.5)

			if not (C_TaskQuest and C_TaskQuest.GetQuestsOnMap) then
				return nil
			end

			local ok, tasks = pcall(C_TaskQuest.GetQuestsOnMap, numericMapID)
			if not ok or (QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(tasks)) then
				return nil
			end
			if type(tasks) ~= "table" then
				return nil
			end

			local questIds = {}
			for index = 1, #tasks do
				local taskInfo = tasks[index]
				if type(taskInfo) == "table" and not (QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(taskInfo)) then
					local questID = taskInfo.questID
					if not (QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(questID)) then
						local numericQuestID = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(questID)
							or nil
						if numericQuestID and numericQuestID > 0 then
							questIds[#questIds + 1] = math.floor(numericQuestID + 0.5)
						end
					end
				end
			end

			return questIds
		end,
		GetQuestPOIsOnMap = function(mapID)
			local numericMapID = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(mapID) or nil
			if not numericMapID or numericMapID <= 0 then
				return nil
			end
			numericMapID = math.floor(numericMapID + 0.5)

			if not (C_QuestLog and C_QuestLog.GetQuestsOnMap) then
				return nil
			end

			local ok, pois = pcall(C_QuestLog.GetQuestsOnMap, numericMapID)
			if not ok or (QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(pois)) then
				return nil
			end
			if type(pois) ~= "table" then
				return nil
			end

			local sanitized = {}
			for index = 1, #pois do
				local poi = pois[index]
				if type(poi) == "table" and not (QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(poi)) then
					local questID = poi.questID
					if not (QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(questID)) then
						local numericQuestID = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(questID)
							or nil
						if numericQuestID and numericQuestID > 0 then
							local function NormalizeBool(rawValue)
								if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(rawValue) then
									return nil
								end
								if type(rawValue) == "boolean" then
									return rawValue
								end
								local numericFlag = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(rawValue)
									or nil
								if numericFlag ~= nil then
									return numericFlag ~= 0
								end
								return nil
							end

							local questTagType = nil
							if not (QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(poi.questTagType)) then
								questTagType = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(poi.questTagType)
									or nil
								if questTagType ~= nil then
									questTagType = math.floor(questTagType + 0.5)
								end
							end

							sanitized[#sanitized + 1] = {
								questID = math.floor(numericQuestID + 0.5),
								inProgress = NormalizeBool(poi.inProgress),
								isQuestStart = NormalizeBool(poi.isQuestStart),
								isMapIndicatorQuest = NormalizeBool(poi.isMapIndicatorQuest),
								questTagType = questTagType,
							}
						end
					end
				end
			end

			return sanitized
		end,
		IsInsideQuestBlob = function(questID)
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return nil
			end
			if not (C_Minimap and C_Minimap.IsInsideQuestBlob) then
				return nil
			end

			local ok, isInside = pcall(C_Minimap.IsInsideQuestBlob, numericQuestID)
			if not ok then
				return nil
			end
			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(isInside) then
				return nil
			end
			if type(isInside) == "boolean" then
				return isInside
			end
			local numericFlag = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(isInside) or nil
			if numericFlag ~= nil then
				return numericFlag ~= 0
			end
			return nil
		end,
		IsOnQuest = function(questID)
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return false
			end
			if C_QuestLog and C_QuestLog.IsOnQuest then
				local ok, isOnQuest = pcall(C_QuestLog.IsOnQuest, numericQuestID)
				return ok and isOnQuest and true or false
			end
			return false
		end,
		IsPushableQuest = function(questID)
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return false
			end
			if C_QuestLog and C_QuestLog.IsPushableQuest then
				local ok, isPushable = pcall(C_QuestLog.IsPushableQuest, numericQuestID)
				return ok and isPushable and true or false
			end
			return false
		end,
		GetNumQuestLogEntries = function()
			if InCombatLockdown and InCombatLockdown() then
				return 0
			end
			if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
				local ok, count = pcall(C_QuestLog.GetNumQuestLogEntries)
				if not ok then
					return 0
				end
				if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(count) then
					return 0
				end
				if type(count) ~= "number" then
					return 0
				end
				return count
			end
			return 0
		end,
		GetQuestLogInfo = function(questLogIndex)
			if InCombatLockdown and InCombatLockdown() then
				return nil
			end
			local numericQuestLogIndex = QuestTogether and QuestTogether.SafeToNumber
				and QuestTogether:SafeToNumber(questLogIndex)
				or nil
			if numericQuestLogIndex == nil then
				return nil
			end
			numericQuestLogIndex = math.floor(numericQuestLogIndex + 0.5)
			if numericQuestLogIndex <= 0 then
				return nil
			end

			if C_QuestLog and C_QuestLog.GetInfo then
				local ok, questInfo = pcall(C_QuestLog.GetInfo, numericQuestLogIndex)
				if not ok then
					return nil
				end
				if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(questInfo) then
					return nil
				end
				if type(questInfo) ~= "table" then
					return nil
				end

					local function NormalizeQuestInfoFlag(rawValue)
						if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(rawValue) then
							return nil
						end
						if type(rawValue) == "boolean" then
							return rawValue
						end
						local numericFlag = QuestTogether and QuestTogether.SafeToNumber
							and QuestTogether:SafeToNumber(rawValue)
							or nil
						if numericFlag ~= nil then
							return numericFlag ~= 0
						end
						return nil
					end

					-- Keep quest-log snapshots to a strict scalar allowlist.
					-- Broadly copying the C_QuestLog info table can carry secure/forbidden references
					-- that later taint Blizzard map pin update paths.
					local titleValue = questInfo.title
					local titleIsSecret = QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(titleValue)
					local sanitizedInfo = {
						title = (type(titleValue) == "string" and not titleIsSecret) and titleValue or nil,
						isHeader = NormalizeQuestInfoFlag(questInfo.isHeader) == true,
						isHidden = NormalizeQuestInfoFlag(questInfo.isHidden) == true,
						isTask = NormalizeQuestInfoFlag(questInfo.isTask) == true,
						isOnMap = NormalizeQuestInfoFlag(questInfo.isOnMap) == true,
						hasLocalPOI = NormalizeQuestInfoFlag(questInfo.hasLocalPOI) == true,
						isComplete = NormalizeQuestInfoFlag(questInfo.isComplete) == true,
					}

					-- Preserve unknown world-quest classification as nil so snapshot code can fall
					-- back to C_QuestLog.IsWorldQuest(questID).
					local normalizedIsWorldQuest = NormalizeQuestInfoFlag(questInfo.isWorldQuest)
					if normalizedIsWorldQuest ~= nil then
						sanitizedInfo.isWorldQuest = normalizedIsWorldQuest
					end

					local numericQuestID = QuestTogether and QuestTogether.SafeToNumber
						and QuestTogether:SafeToNumber(questInfo.questID)
						or nil
					if (not numericQuestID or numericQuestID <= 0) and C_QuestLog and C_QuestLog.GetQuestIDForLogIndex then
						local okQuestId, questIDFromIndex = pcall(C_QuestLog.GetQuestIDForLogIndex, numericQuestLogIndex)
						if okQuestId and not (QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(questIDFromIndex)) then
							numericQuestID = QuestTogether and QuestTogether.SafeToNumber
								and QuestTogether:SafeToNumber(questIDFromIndex)
								or nil
						end
					end
					if numericQuestID and numericQuestID > 0 then
						sanitizedInfo.questID = math.floor(numericQuestID + 0.5)
					end

				return sanitizedInfo
			end
			return nil
		end,
		GetNumQuestLeaderBoards = function(questLogIndex)
			if InCombatLockdown and InCombatLockdown() then
				return 0
			end
			if type(GetNumQuestLeaderBoards) ~= "function" then
				return 0
			end
			local ok, objectiveCount = pcall(GetNumQuestLeaderBoards, questLogIndex)
			if not ok then
				return 0
			end
			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(objectiveCount) then
				return 0
			end
			if type(objectiveCount) ~= "number" then
				return 0
			end
			return objectiveCount
		end,
		GetQuestObjectiveInfo = function(questID, objectiveIndex, displayComplete)
			if InCombatLockdown and InCombatLockdown() then
				return nil, nil, nil, nil
			end
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return nil, nil, nil, nil
			end

			local numericObjectiveIndex = QuestTogether and QuestTogether.SafeToNumber
				and QuestTogether:SafeToNumber(objectiveIndex)
				or nil
			if numericObjectiveIndex == nil then
				return nil, nil, nil, nil
			end
			numericObjectiveIndex = math.floor(numericObjectiveIndex + 0.5)
			if numericObjectiveIndex <= 0 then
				return nil, nil, nil, nil
			end

			if type(GetQuestObjectiveInfo) ~= "function" then
				return nil, nil, nil, nil
			end
			local ok, text, objectiveType, finished, currentValue =
				pcall(GetQuestObjectiveInfo, numericQuestID, numericObjectiveIndex, displayComplete)
			if not ok then
				return nil, nil, nil, nil
			end
			if QuestTogether and QuestTogether.IsSecretValue then
				if QuestTogether:IsSecretValue(text) then
					text = nil
				end
				if QuestTogether:IsSecretValue(objectiveType) then
					objectiveType = nil
				end
				if QuestTogether:IsSecretValue(finished) then
					finished = nil
				end
				if QuestTogether:IsSecretValue(currentValue) then
					currentValue = nil
				end
			end
			return text, objectiveType, finished, currentValue
		end,
		GetQuestProgressBarPercent = function(questID)
			if InCombatLockdown and InCombatLockdown() then
				return nil
			end
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return nil
			end

			if type(GetQuestProgressBarPercent) ~= "function" then
				return nil
			end
			local ok, progressValue = pcall(GetQuestProgressBarPercent, numericQuestID)
			if not ok then
				return nil
			end
			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(progressValue) then
				return nil
			end
			return progressValue
		end,
		InviteUnit = function(name)
			if C_PartyInfo and C_PartyInfo.InviteUnit then
				local ok, result = pcall(C_PartyInfo.InviteUnit, name)
				return ok and result or nil
			end
			return nil
		end,
		SendTell = function(name, chatFrame)
			if ChatFrameUtil and ChatFrameUtil.SendTell then
				local ok, result = pcall(ChatFrameUtil.SendTell, name, chatFrame)
				return ok and result or nil
			end
			if type(ChatFrame_SendTell) == "function" then
				local ok, result = pcall(ChatFrame_SendTell, name, chatFrame)
				return ok and result or nil
			end
			return nil
		end,
		AddFriend = function(name)
			if C_FriendList and C_FriendList.AddFriend then
				local ok, result = pcall(C_FriendList.AddFriend, name)
				return ok and result or nil
			end
			return nil
		end,
	AddOrDelIgnore = function(name)
		if C_FriendList and C_FriendList.AddOrDelIgnore then
			-- Ignore-list APIs can throw for invalid names; keep menu actions non-fatal.
			local ok, result = pcall(C_FriendList.AddOrDelIgnore, name)
			return ok and result or nil
		end
		return nil
	end,
	IsOnIgnoredList = function(name)
		if C_FriendList and C_FriendList.IsOnIgnoredList then
			-- Ignore-list lookups can throw on malformed names; treat as "not ignored".
			local ok, result = pcall(C_FriendList.IsOnIgnoredList, name)
			return ok and result or false
		end
		return false
	end,
		IsAddOnLoaded = function(addonName)
			if C_AddOns and C_AddOns.IsAddOnLoaded then
				local ok, isLoaded = pcall(C_AddOns.IsAddOnLoaded, addonName)
				return ok and isLoaded and true or false
			end
			local ok, isLoaded = pcall(IsAddOnLoaded, addonName)
			return ok and isLoaded and true or false
		end,
		GetAddOnMetadata = function(addonName, fieldName)
			if C_AddOns and C_AddOns.GetAddOnMetadata then
				local ok, metadata = pcall(C_AddOns.GetAddOnMetadata, addonName, fieldName)
				if not ok then
					return nil
				end
				if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(metadata) then
					return nil
				end
				return metadata
			end
			if type(GetAddOnMetadata) == "function" then
				local ok, metadata = pcall(GetAddOnMetadata, addonName, fieldName)
				if not ok then
					return nil
				end
				if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(metadata) then
					return nil
				end
				return metadata
			end
			return nil
		end,
		UnitInParty = function(unitToken)
			local ok, result = pcall(UnitInParty, unitToken)
			return ok and result and true or false
		end,
		UnitInRaid = function(unitToken)
			local ok, result = pcall(UnitInRaid, unitToken)
			return ok and result and true or false
		end,
		Ambiguate = function(name, context)
			local ok, result = pcall(Ambiguate, name, context)
			if not ok then
				return nil
			end
			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(result) then
				return nil
			end
			return result
		end,
	GetRealmName = function()
		local ok, realmName = pcall(GetRealmName)
		if not ok then
			return ""
		end
		if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(realmName) then
			return ""
		end
		return realmName
	end,
	GetBestMapForUnit = function(unitToken)
		if C_Map and C_Map.GetBestMapForUnit then
			local ok, mapID = pcall(C_Map.GetBestMapForUnit, unitToken)
			if not ok then
				return nil
			end
			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(mapID) then
				return nil
			end
			return mapID
		end
		return nil
	end,
		GetMapInfo = function(mapID)
			if C_Map and C_Map.GetMapInfo then
				local ok, mapInfo = pcall(C_Map.GetMapInfo, mapID)
				return ok and mapInfo or nil
			end
			return nil
		end,
			GetPlayerMapPosition = function(mapID, unitToken)
				if C_Map and C_Map.GetPlayerMapPosition then
					local ok, mapPosition = pcall(C_Map.GetPlayerMapPosition, mapID, unitToken)
					return ok and mapPosition or nil
				end
				return nil
			end,
		GetTooltipDataForHyperlink = function(hyperlink)
			if C_TooltipInfo and C_TooltipInfo.GetHyperlink and type(hyperlink) == "string" and hyperlink ~= "" then
				local ok, tooltipData = pcall(C_TooltipInfo.GetHyperlink, hyperlink)
				if not ok then
					return nil
				end
				if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(tooltipData) then
					return nil
				end
				return tooltipData
			end
			return nil
		end,
		GetTooltipDataForUnit = function(unitToken)
			if C_TooltipInfo and C_TooltipInfo.GetUnit then
				local ok, tooltipData = pcall(C_TooltipInfo.GetUnit, unitToken)
				if not ok then
					return nil
				end
				if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(tooltipData) then
					return nil
				end
				return tooltipData
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
				local ok, canSet = pcall(C_Map.CanSetUserWaypointOnMap, mapID)
				return ok and canSet and true or false
			end
			return false
		end,
		SetUserWaypoint = function(point)
			if C_Map and C_Map.SetUserWaypoint then
				local ok, result = pcall(C_Map.SetUserWaypoint, point)
				return ok and result or nil
			end
			return nil
		end,
		SetSuperTrackedUserWaypoint = function(shouldSuperTrack)
			if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
				local ok, result = pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, shouldSuperTrack)
				return ok and result or nil
			end
			return nil
		end,
}

function QuestTogether:IsSecretValue(value)
	if not raw_issecretvalue then
		return false
	end

	return raw_issecretvalue(value) and true or false
end

function QuestTogether:SafeToNumber(value)
	if self:IsSecretValue(value) then
		return nil
	end

	local valueType = type(value)
	if valueType == "number" then
		-- Reject NaN/inf to keep downstream math safe and deterministic.
		if value ~= value or value == math.huge or value == -math.huge then
			return nil
		end
		return value
	end

	if valueType ~= "string" then
		return nil
	end

	local trimmedValue = self:SafeTrimString(value, "")
	if trimmedValue == "" then
		return nil
	end

	local numericValue = tonumber(trimmedValue)
	if type(numericValue) ~= "number" then
		return nil
	end

	if numericValue ~= numericValue or numericValue == math.huge or numericValue == -math.huge then
		return nil
	end

	return numericValue
end

function QuestTogether:NormalizeQuestID(questId)
	local numericQuestId = self:SafeToNumber(questId)
	if not numericQuestId or numericQuestId <= 0 then
		return nil
	end

	return math.floor(numericQuestId + 0.5)
end

function QuestTogether:SafeToString(value, fallback)
	if self:IsSecretValue(value) then
		if fallback ~= nil then
			return fallback
		end
		return "<secret>"
	end

	local valueType = type(value)
	if valueType == "string" then
		return value
	end
	if valueType == "number" or valueType == "boolean" or valueType == "nil" then
		return raw_tostring(value)
	end

	-- String coercion is intentionally shielded so debug/log paths never trigger taint errors.
	local ok, stringValue = pcall(raw_tostring, value)
	if ok then
		return stringValue
	end

	if fallback ~= nil then
		return fallback
	end
	return "<secret>"
end

function QuestTogether:SafeTrimString(value, fallback)
	local fallbackValue = fallback or ""
	if type(value) ~= "string" or self:IsSecretValue(value) then
		return fallbackValue
	end

	local trimmedValue = string.match(value, "^%s*(.-)%s*$")
	if type(trimmedValue) ~= "string" or self:IsSecretValue(trimmedValue) then
		return fallbackValue
	end
	return trimmedValue
end

function QuestTogether:SafeStripWhitespace(value, fallback)
	local fallbackValue = fallback or ""
	if type(value) ~= "string" or self:IsSecretValue(value) then
		return fallbackValue
	end

	local stripped = string.gsub(value, "%s+", "")
	if type(stripped) ~= "string" or self:IsSecretValue(stripped) then
		return fallbackValue
	end
	return stripped
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
	if QuestTogether:IsSecretValue(value) then
		return "<secret>"
	end

	local valueType = type(value)
	if valueType == "nil" then
		return "nil"
	end
	if valueType == "boolean" or valueType == "number" then
		return tostring(value)
	end
	if valueType == "string" then
		local ok, quoted = pcall(string.format, "%q", value)
		if ok then
			return quoted
		end
		return tostring(value, "<secret>")
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

local function NormalizeProfileKey(profileKey)
	if type(profileKey) ~= "string" then
		return nil
	end

	local trimmed = QuestTogether:SafeTrimString(profileKey, "")
	if trimmed == "" then
		return nil
	end
	return trimmed
end

function QuestTogether:GetCurrentCharacterKey()
	local fullName = self.GetPlayerFullName and self:GetPlayerFullName() or nil
	if type(fullName) == "string" and fullName ~= "" then
		return fullName
	end

	local playerName = self:GetPlayerName() or "Unknown"
	if SafeFind(playerName, "-", 1, true) then
		return playerName
	end

	local realmName = self:SafeStripWhitespace(self.API.GetRealmName and self.API.GetRealmName() or "", "")
	if realmName ~= "" then
		return playerName .. "-" .. realmName
	end

	return playerName
end

function QuestTogether:EnsureProfileStorage()
	if not self.db then
		return false
	end

	if type(self.db.profiles) ~= "table" then
		self.db.profiles = {}
	end
	if type(self.db.profileKeys) ~= "table" then
		self.db.profileKeys = {}
	end

	return true
end

function QuestTogether:GetCurrentProfileKey()
	return self.activeProfileKey
end

function QuestTogether:GetProfileKeys()
	if not self.db then
		return {}
	end
	self:EnsureProfileStorage()

	local keys = {}
	for profileKey, profileData in pairs(self.db.profiles) do
		if type(profileKey) == "string" and type(profileData) == "table" then
			keys[#keys + 1] = profileKey
		end
	end
	table.sort(keys, function(left, right)
		return tostring(left) < tostring(right)
	end)
	return keys
end

function QuestTogether:EnsureProfile(profileKey, sourceProfile)
	if not self.db or not self:EnsureProfileStorage() then
		return nil, nil
	end

	local normalizedKey = NormalizeProfileKey(profileKey)
	if not normalizedKey then
		return nil, nil
	end

	if type(self.db.profiles[normalizedKey]) ~= "table" then
		self.db.profiles[normalizedKey] = self:DeepCopy(sourceProfile or self.DEFAULTS.profile)
	end
	self:ApplyDefaults(self.db.profiles[normalizedKey], self.DEFAULTS.profile)
	return normalizedKey, self.db.profiles[normalizedKey]
end

function QuestTogether:ApplyActiveProfileState(changeReason)
	if not self.db or not self.db.profile then
		return false
	end

	self:NormalizeAnnouncementDisplayOptions()
	self:NormalizeNameplateOptions()

	if self.db.profile.chatLogDestination == "separate" then
		local chatFrame = self:EnsureQuestLogChatFrame()
		if chatFrame then
			self:ApplyMainChatFontSizeToChatFrame(chatFrame)
		end
	else
		self:CloseQuestLogChatFrame()
	end

	if self.hasLoggedIn then
		if self.db.profile.enabled then
			self:Enable()
		else
			self:Disable()
		end
	end

	if self.RefreshPartyRoster then
		self:RefreshPartyRoster()
	end
	if self.RefreshNameplateAugmentation then
		self:RefreshNameplateAugmentation()
	end
	if self.RefreshActiveAnnouncementBubbles then
		self:RefreshActiveAnnouncementBubbles()
	end
	if self.RefreshPersonalBubbleAnchorVisualState then
		self:RefreshPersonalBubbleAnchorVisualState()
	end
	if self.RefreshPersonalBubbleEditModeDialog then
		self:RefreshPersonalBubbleEditModeDialog()
	end
	if self.RefreshOptionsWindow then
		self:RefreshOptionsWindow()
	end
	if self.RefreshProfilesWindow then
		self:RefreshProfilesWindow()
	end

	self:Debugf(
		"profile",
		"Applied active profile state reason=%s character=%s profile=%s",
		tostring(changeReason or "unknown"),
		tostring(self.activeCharacterKey),
		tostring(self.activeProfileKey)
	)
	return true
end

function QuestTogether:SetActiveProfile(profileKey)
	if not self.db or not self:EnsureProfileStorage() then
		return false, "Profile database is unavailable."
	end

	local normalizedKey, profileData = self:EnsureProfile(profileKey)
	if not normalizedKey or not profileData then
		return false, "Profile name cannot be empty."
	end

	local characterKey = self.activeCharacterKey or self:GetCurrentCharacterKey()
	self.activeCharacterKey = characterKey
	self.activeProfileKey = normalizedKey
	self.db.profileKeys[characterKey] = normalizedKey
	self.db.profile = profileData

	self:ApplyActiveProfileState("switch")
	return true
end

function QuestTogether:CreateProfile(profileKey, sourceProfileKey)
	if not self.db or not self:EnsureProfileStorage() then
		return false, "Profile database is unavailable."
	end

	local normalizedKey = NormalizeProfileKey(profileKey)
	if not normalizedKey then
		return false, "Profile name cannot be empty."
	end
	if type(self.db.profiles[normalizedKey]) == "table" then
		return false, "A profile with that name already exists."
	end

	local sourceProfile = self.db.profile
	local normalizedSource = NormalizeProfileKey(sourceProfileKey)
	if normalizedSource and type(self.db.profiles[normalizedSource]) == "table" then
		sourceProfile = self.db.profiles[normalizedSource]
	end

	self.db.profiles[normalizedKey] = self:DeepCopy(sourceProfile or self.DEFAULTS.profile)
	self:ApplyDefaults(self.db.profiles[normalizedKey], self.DEFAULTS.profile)
	return true
end

function QuestTogether:CopyProfileIntoActiveProfile(sourceProfileKey)
	if not self.db or not self:EnsureProfileStorage() then
		return false, "Profile database is unavailable."
	end

	local sourceKey = NormalizeProfileKey(sourceProfileKey)
	if not sourceKey then
		return false, "Profile name cannot be empty."
	end
	if type(self.db.profiles[sourceKey]) ~= "table" then
		return false, "Profile not found: " .. tostring(sourceKey)
	end
	if not self.activeProfileKey then
		return false, "No active profile is set."
	end

	self.db.profiles[self.activeProfileKey] = self:DeepCopy(self.db.profiles[sourceKey])
	self:ApplyDefaults(self.db.profiles[self.activeProfileKey], self.DEFAULTS.profile)
	self.db.profile = self.db.profiles[self.activeProfileKey]
	self:ApplyActiveProfileState("copy")
	return true
end

function QuestTogether:ResetActiveProfile()
	if not self.db or not self:EnsureProfileStorage() then
		return false, "Profile database is unavailable."
	end
	if not self.activeProfileKey then
		return false, "No active profile is set."
	end

	self.db.profiles[self.activeProfileKey] = self:DeepCopy(self.DEFAULTS.profile)
	self.db.profile = self.db.profiles[self.activeProfileKey]
	self:ApplyActiveProfileState("reset")
	return true
end

function QuestTogether:DeleteProfile(profileKey)
	if not self.db or not self:EnsureProfileStorage() then
		return false, "Profile database is unavailable."
	end

	local normalizedKey = NormalizeProfileKey(profileKey)
	if not normalizedKey then
		return false, "Profile name cannot be empty."
	end
	if normalizedKey == self.activeProfileKey then
		return false, "You cannot delete the active profile."
	end
	if type(self.db.profiles[normalizedKey]) ~= "table" then
		return false, "Profile not found: " .. tostring(normalizedKey)
	end

	self.db.profiles[normalizedKey] = nil

	for characterKey, mappedProfileKey in pairs(self.db.profileKeys) do
		if mappedProfileKey == normalizedKey then
			local fallbackProfileKey = NormalizeProfileKey(characterKey) or tostring(characterKey)
			self.db.profileKeys[characterKey] = fallbackProfileKey
			self:EnsureProfile(fallbackProfileKey, self.DEFAULTS.profile)
		end
	end

	return true
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
	self:PrintChatLogRaw("|cff33ff99QuestTogether|r: " .. self:SafeToString(message, ""))
end

function QuestTogether:GetMainChatFrame()
	return DEFAULT_CHAT_FRAME
end

function QuestTogether:GetConfiguredQuestLogChatFrameID()
	if not self.db then
		return nil
	end

	local configuredID = self:SafeToNumber(self.db.profile and self.db.profile.questLogChatFrameID)
	if not configuredID and self.db.global then
		-- Legacy fallback for migration from pre-profile versions.
		configuredID = self:SafeToNumber(self.db.global.questLogChatFrameID)
	end
	if configuredID and configuredID > 0 then
		return configuredID
	end

	return nil
end

function QuestTogether:SetConfiguredQuestLogChatFrameID(chatFrameID)
	if not self.db then
		return false
	end

	local numericID = self:SafeToNumber(chatFrameID)
	if numericID and numericID > 0 then
		if self.db.profile then
			self.db.profile.questLogChatFrameID = numericID
		end
	else
		if self.db.profile then
			self.db.profile.questLogChatFrameID = nil
		end
	end

	-- Always clear legacy global storage so this stays profile-scoped.
	if self.db.global then
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

	local maxWindows = self:SafeToNumber(self.API.GetNumChatWindows and self.API.GetNumChatWindows()) or 0
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
	local maxWindows = self:SafeToNumber(self.API.GetNumChatWindows and self.API.GetNumChatWindows()) or 0

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
		-- Closing chat windows can fail in restricted UI states; keep close flow resilient.
		local ok = pcall(self.API.CloseChatWindow, chatFrame)
		self.suppressQuestLogChatCloseHook = false
		if not ok then
			self:Debugf("chat", "Failed to close QuestTogether chat window id=%s", tostring(chatFrameID))
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
	fontSize = self:SafeToNumber(fontSize)
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

	local iconSize = math.max(1, math.floor((self:SafeToNumber(size) or 14)))
	return string.format("|T%s:%d:%d:0:0|t", texturePath, iconSize, iconSize)
end

function QuestTogether:GetIconChatTagFromAsset(iconAsset, iconKind, size)
	local asset = tostring(iconAsset or "")
	if asset == "" then
		return ""
	end

	local iconSize = math.max(1, math.floor((self:SafeToNumber(size) or 14)))
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

function QuestTogether:GetAddonVersion()
	local metadata = self.API and self.API.GetAddOnMetadata and self.API.GetAddOnMetadata(self.addonName, "Version")
	if type(metadata) ~= "string" then
		return ""
	end

	local version = self:SafeTrimString(metadata, "")
	if version == "" then
		return ""
	end

	return version
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
	local numericQuestId = self:SafeToNumber(questId)
	if not numericQuestId or not C_QuestLog or not C_QuestLog.GetQuestTagInfo then
		return nil
	end

	-- Blizzard quest metadata calls can throw on stale quest IDs.
	local ok, tagInfo = pcall(C_QuestLog.GetQuestTagInfo, numericQuestId)
	if not ok or type(tagInfo) ~= "table" then
		return nil
	end

	return tagInfo
end

function QuestTogether:GetQuestDetailsThemePoiIcon(questId)
	local numericQuestId = self:SafeToNumber(questId)
	if not numericQuestId or not C_QuestLog or not C_QuestLog.GetQuestDetailsTheme then
		return nil
	end

	-- Blizzard quest metadata calls can throw on stale quest IDs.
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

	-- Atlas resolver can throw for unknown combinations; fail soft to default icons.
	local ok, atlas = pcall(QuestUtils_GetQuestTagAtlas, tagID, worldQuestType)
	if not ok or type(atlas) ~= "string" or atlas == "" then
		return nil
	end

	return atlas
end

function QuestTogether:GetWorldQuestAtlasInfo(questId, tagInfo, inProgress)
	local numericQuestId = self:SafeToNumber(questId)
	if not numericQuestId or type(tagInfo) ~= "table" or not QuestUtil or not QuestUtil.GetWorldQuestAtlasInfo then
		return nil
	end

	-- Atlas resolver can throw for quest states that are mid-refresh.
	local ok, atlas = pcall(QuestUtil.GetWorldQuestAtlasInfo, numericQuestId, tagInfo, inProgress and true or false)
	if not ok or type(atlas) ~= "string" or atlas == "" then
		return nil
	end

	return atlas
end

function QuestTogether:GetQuestStateAnnouncementIconInfo(eventType, questId)
	local numericQuestId = self:SafeToNumber(questId)
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
	local numericQuestId = self:SafeToNumber(questId)
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
	local numericQuestId = self:SafeToNumber(questId)
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
	local numericQuestId = self:SafeToNumber(questId)
	local titleText = tostring(questTitle or "")
	if not numericQuestId or titleText == "" or not LinkUtil or not LinkUtil.FormatLink then
		return titleText
	end

	local linkDisplayText = "[" .. titleText .. "]"
	return LinkUtil.FormatLink(self.chatLogQuestLinkType or "questtogetherquest", linkDisplayText, tostring(numericQuestId))
end

function QuestTogether:DecorateAnnouncementMessageWithQuestLink(message, eventType, questId)
	if not self.questTitleLinkEventTypes or not self.questTitleLinkEventTypes[eventType] then
		return self:SafeToString(message, "")
	end

	local numericQuestId = self:SafeToNumber(questId)
	if not numericQuestId then
		return self:SafeToString(message, "")
	end

	local messageText = self:SafeToString(message, "")
	local prefixText, questTitle = SafeMatch(messageText, "^(.-:%s+)(.+)$")
	if not prefixText or not questTitle or questTitle == "" then
		return messageText
	end

	return prefixText .. self:BuildChatLogQuestLabel(numericQuestId, questTitle)
end

function QuestTogether:GetQuestStatusLabel(questId)
	local numericQuestId = self:SafeToNumber(questId)
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
	local numericQuestId = self:SafeToNumber(questId)
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

function QuestTogether:NormalizeQuestLinkTitleText(titleText)
	local normalizedText = self:SafeTrimString(titleText, "")
	if SafeMatch(normalizedText, "^%[.+%]$") then
		normalizedText = string.sub(normalizedText, 2, -2)
	end
	return normalizedText
end

function QuestTogether:BuildQuestStatusMessage(questId, fallbackTitle)
	local numericQuestId = self:SafeToNumber(questId)
	if not numericQuestId then
		return "Quest status unavailable."
	end

	local questTitle = self:GetQuestTitle(numericQuestId)
	local normalizedFallbackTitle = self:NormalizeQuestLinkTitleText(fallbackTitle)
	if
		normalizedFallbackTitle ~= ""
		and (questTitle == nil or questTitle == "" or questTitle == ("Quest " .. tostring(numericQuestId)))
	then
		questTitle = normalizedFallbackTitle
	end
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

function QuestTogether:GetTrackedQuestAnnouncementIcon(questData)
	if type(questData) ~= "table" then
		return nil, nil
	end

	local iconAsset = tostring(questData.iconAsset or "")
	if iconAsset == "" then
		return nil, nil
	end

	local iconKind = tostring(questData.iconKind or "")
	if iconKind == "" then
		iconKind = nil
	end

	return iconAsset, iconKind
end

function QuestTogether:RefreshTrackedQuestAnnouncementIcon(questId, questData, eventType)
	local numericQuestId = self:SafeToNumber(questId)
	if not numericQuestId or type(questData) ~= "table" then
		return nil, nil
	end

	local resolvedEventType = eventType or self:GetQuestStatusAnnouncementEventType(numericQuestId)
	local iconAsset, iconKind = self:GetAnnouncementIconInfo(resolvedEventType, numericQuestId)
	questData.iconAsset = iconAsset or nil
	questData.iconKind = iconKind or nil
	return iconAsset, iconKind
end

function QuestTogether:PrintQuestStatus(questId, fallbackTitle)
	local message = self:BuildQuestStatusMessage(questId, fallbackTitle)
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

	local questId = self:SafeToNumber(compareEntry.questId)
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

function QuestTogether:PrintQuestCompareMessage(remoteName, compareEntry, classFile)
	local eventType = compareEntry and compareEntry.isComplete and "QUEST_COMPLETED" or "QUEST_PROGRESS"
	local locationInfo = {
		questId = compareEntry and compareEntry.questId or nil,
	}
	self:PrintConsoleAnnouncement(
		self:BuildQuestCompareMessage(remoteName, compareEntry),
		remoteName,
		classFile,
		eventType,
		nil,
		nil,
		locationInfo
	)
end

function QuestTogether:PrintQuestCompareStart(remoteName, classFile)
	self:PrintConsoleAnnouncement("Comparing quests...", remoteName, classFile, "QUEST_PROGRESS")
end

function QuestTogether:PrintQuestCompareDone(remoteName, count, classFile)
	local suffix = ""
	local numericCount = self:SafeToNumber(count)
	if numericCount then
		suffix = string.format(" (%d quests)", numericCount)
	end
	self:PrintConsoleAnnouncement("Finished comparing quests" .. suffix .. ".", remoteName, classFile, "QUEST_COMPLETED")
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
	local addonVersion = tostring(pongData.addonVersion or "")
	if addonVersion ~= "" then
		parts[#parts + 1] = "QT v" .. addonVersion
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

	-- TomTom may reject waypoint creation during transient map states; keep fallback path alive.
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
	if self.API and self.API.InCombatLockdown and self.API.InCombatLockdown() then
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
	-- Super-tracking can trigger protected world-map pin refreshes while state changes are still
	-- settling, so this remains best-effort and non-fatal.
	if self.API.SetSuperTrackedUserWaypoint then
		pcall(self.API.SetSuperTrackedUserWaypoint, true)
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
	local isRemoteSpeaker = false
	if speakerName == nil or speakerName == "" then
		speakerName = self:GetPlayerName()
	end
	local resolvedClassFile = classFile
	if not resolvedClassFile or resolvedClassFile == "" then
		if speakerName ~= nil and speakerName ~= "" and self.NormalizeMemberName then
			local normalizedSpeaker = self:NormalizeMemberName(speakerName)
			local normalizedPlayer = self:NormalizeMemberName(self:GetPlayerFullName() or self:GetPlayerName() or "")
			isRemoteSpeaker = normalizedSpeaker and normalizedPlayer and normalizedSpeaker ~= normalizedPlayer and true or false
			if isRemoteSpeaker then
				resolvedClassFile = self.GetGroupedSenderClassFile and self:GetGroupedSenderClassFile(speakerName) or nil
			end
		end
		if (not resolvedClassFile or resolvedClassFile == "") and not isRemoteSpeaker then
			resolvedClassFile = self:GetPlayerClassFile()
		end
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
	-- Context menus should stay usable even if ignored-list lookups fail for edge-case names.
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

	self:PrintQuestStatus(questId, text)
	return LinkProcessorResponse.Handled
end

function QuestTogether:HandleChatLogCoordLink(link, text, linkData, contextData)
	local options = tostring(linkData and linkData.options or "")
	local mapID, coordX, coordY = SafeMatch(options, "^([^:]+):([^:]+):([^:]+)$")
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

	-- Debug formatting should never crash addon logic due to bad format strings.
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
	local playerName = self.API and self.API.UnitName and self.API.UnitName("player") or nil
	return playerName or "Unknown"
end

function QuestTogether:IsSelfSender(sender)
	if not sender then
		return false
	end
	local shortName = self.API and self.API.Ambiguate and self.API.Ambiguate(sender, "short") or nil
	return shortName == self:GetPlayerName()
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
	local numericQuestId = self:NormalizeQuestID(questId)
	if not numericQuestId then
		return false
	end

	if C_QuestLog and C_QuestLog.IsWorldQuest then
		-- Quest APIs may throw on IDs that disappear mid-update; treat as false.
		local ok, isWorldQuest = pcall(C_QuestLog.IsWorldQuest, numericQuestId)
		if ok then
			if self:IsSecretValue(isWorldQuest) then
				isWorldQuest = nil
			end
			if type(isWorldQuest) == "boolean" then
				if isWorldQuest then
					return true
				end
			else
				local worldFlag = self:SafeToNumber(isWorldQuest)
				if worldFlag ~= nil and worldFlag ~= 0 then
					return true
				end
			end
		end
	end

	-- Some task quest variants do not reliably flag IsWorldQuest, but they expose
	-- world-quest metadata through quest tags.
	local tagInfo = self:GetQuestTagInfo(numericQuestId)
	if type(tagInfo) ~= "table" then
		return false
	end

	local worldQuestType = nil
	if not self:IsSecretValue(tagInfo.worldQuestType) then
		worldQuestType = self:SafeToNumber(tagInfo.worldQuestType)
	end
	if worldQuestType ~= nil and worldQuestType > 0 then
		return true
	end

	if Enum and Enum.QuestTag and Enum.QuestTag.WorldQuest then
		local tagID = nil
		if not self:IsSecretValue(tagInfo.tagID) then
			tagID = self:SafeToNumber(tagInfo.tagID)
		end
		if tagID ~= nil and tagID == Enum.QuestTag.WorldQuest then
			return true
		end
	end

	return false
end

function QuestTogether:IsBonusObjective(questId)
	local numericQuestId = self:NormalizeQuestID(questId)
	if not numericQuestId or not C_QuestLog or not C_QuestLog.IsQuestTask then
		return false
	end

	-- Quest APIs may throw on IDs that disappear mid-update; treat as false.
	local ok, isTaskQuest = pcall(C_QuestLog.IsQuestTask, numericQuestId)
	if not (ok and isTaskQuest) then
		return false
	end

	return not self:IsWorldQuest(numericQuestId)
end

function QuestTogether:GetQuestTitle(questId, questInfo)
	local numericQuestId = self:NormalizeQuestID(questId)
	if not numericQuestId then
		return "Quest " .. tostring(questId)
	end

	if questInfo and type(questInfo.title) == "string" and questInfo.title ~= "" then
		return questInfo.title
	end

	if C_QuestLog and C_QuestLog.GetTitleForQuestID then
		local okLogTitle, logTitle = pcall(C_QuestLog.GetTitleForQuestID, numericQuestId)
		if okLogTitle and self:IsSecretValue(logTitle) then
			logTitle = nil
		end
		if type(logTitle) == "string" and logTitle ~= "" then
			return logTitle
		end
	end

	return "Quest " .. tostring(numericQuestId)
end

function QuestTogether:NormalizeQuestProgressPercent(progressValue)
	local numericProgress = self:SafeToNumber(progressValue)
	if numericProgress == nil then
		return nil
	end

	-- Blizzard progress bars can return floating values; format chat/objectives as whole percents.
	if numericProgress < 0 then
		numericProgress = 0
	elseif numericProgress > 100 then
		numericProgress = 100
	end

	return math.floor(numericProgress + 0.5)
end

function QuestTogether:StripTrailingParentheticalPercent(objectiveText)
	if type(objectiveText) ~= "string" or objectiveText == "" or self:IsSecretValue(objectiveText) then
		return objectiveText
	end

	local strippedText = string.gsub(objectiveText, "%s*%(%d+%%%s*%)%s*$", "")
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
		if self.RefreshActiveAnnouncementBubbles then
			self:RefreshActiveAnnouncementBubbles()
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
		if self.API and self.API.InCombatLockdown and self.API.InCombatLockdown() then
			self.pendingQuestLogTaskDrain = true
		end
		self:Debugf("quest", "Queued quest log task count=%d", #self.onQuestLogUpdate)
	end
end

-- SavedVariables initializer.
function QuestTogether:InitializeDatabase()
	if type(_G.QuestTogetherDB) ~= "table" then
		_G.QuestTogetherDB = {}
	end
	self.db = _G.QuestTogetherDB

	if type(self.db.global) ~= "table" then
		self.db.global = {}
	end
	self:ApplyDefaults(self.db.global, self.DEFAULTS.global)
	self:EnsureProfileStorage()

	local legacyProfile = nil
	if type(self.db.profile) == "table" then
		legacyProfile = self:DeepCopy(self.db.profile)
	end

	local hasExistingProfiles = false
	for _, profileData in pairs(self.db.profiles) do
		if type(profileData) == "table" then
			hasExistingProfiles = true
			break
		end
	end

	local characterKey = self:GetCurrentCharacterKey()
	local defaultProfileKey = NormalizeProfileKey(characterKey) or "Character"
	local assignedProfileKey = NormalizeProfileKey(self.db.profileKeys[characterKey])
	if not assignedProfileKey then
		assignedProfileKey = defaultProfileKey
		self.db.profileKeys[characterKey] = assignedProfileKey
	end

	if type(self.db.profiles[assignedProfileKey]) ~= "table" then
		if legacyProfile and not hasExistingProfiles then
			self.db.profiles[assignedProfileKey] = legacyProfile
		else
			self.db.profiles[assignedProfileKey] = self:DeepCopy(self.DEFAULTS.profile)
		end
	end

	self.activeCharacterKey = characterKey
	self.activeProfileKey = assignedProfileKey
	self.db.profile = self.db.profiles[assignedProfileKey]
	self:ApplyDefaults(self.db.profile, self.DEFAULTS.profile)

	if self.db.profile.questLogChatFrameID == nil and self.db.global.questLogChatFrameID ~= nil then
		self.db.profile.questLogChatFrameID = self.db.global.questLogChatFrameID
	end
	self.db.global.questLogChatFrameID = nil

	self:NormalizeAnnouncementDisplayOptions()
	self:NormalizeNameplateOptions()
	self:DebugState("core", "db.profile", self.db.profile)
	self:Debugf(
		"profile",
		"Initialized profile database character=%s profile=%s profiles=%d",
		tostring(self.activeCharacterKey),
		tostring(self.activeProfileKey),
		#self:GetProfileKeys()
	)
end

function QuestTogether:RegisterRuntimeEvents()
	self.registeredRuntimeEvents = self.registeredRuntimeEvents or {}
	wipe(self.registeredRuntimeEvents)

	for _, eventName in ipairs(self.runtimeEvents) do
		-- Event lists vary slightly by client flavor/build; register best-effort.
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
		-- Unregister should not block disable if Blizzard already removed an event.
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
	self.bonusObjectiveAreaStateByQuestID = {}
	self.questBlobInsideStateByQuestID = {}
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
	self.bonusObjectiveAreaStateByQuestID = {}
	self.questBlobInsideStateByQuestID = {}
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
		-- Loading Blizzard UI modules can fail if unavailable; we handle the missing panel below.
		pcall(UIParentLoadAddOn, "Blizzard_EditMode")
	end

	if self.API and self.API.InCombatLockdown and self.API.InCombatLockdown() then
		self:Debug("Skipping HUD Edit Mode open during combat", "editmode")
		return false
	end

	if not EditModeManagerFrame then
		self:Debug("HUD Edit Mode unavailable", "editmode")
		return false
	end

	-- Avoid ShowUIPanel() to keep UIParentPanelManager taint risk low.
	if EditModeManagerFrame.EnterEditMode then
		local ok = pcall(EditModeManagerFrame.EnterEditMode, EditModeManagerFrame)
		if ok then
			self:Debug("Opening HUD Edit Mode via EnterEditMode", "editmode")
			return true
		end
	end

	if EditModeManagerFrame.Show then
		local ok = pcall(EditModeManagerFrame.Show, EditModeManagerFrame)
		if ok then
			self:Debug("Opening HUD Edit Mode via Show", "editmode")
			return true
		end
	end

	self:Debug("HUD Edit Mode unavailable", "editmode")
	return false
end

function QuestTogether:ClearTestResultLog()
	self.testResultLogLines = {}
	self:RefreshCopyableWindow()
end

function QuestTogether:GetTestResultLogText()
	return table.concat(self.testResultLogLines or {}, "\n")
end

function QuestTogether:SetTestResultLogLines(lines)
	local sanitized = {}
	if type(lines) == "table" then
		for index = 1, #lines do
			local line = lines[index]
			sanitized[#sanitized + 1] = tostring(line or "")
		end
	end
	self.testResultLogLines = sanitized
	self:RefreshCopyableWindow()
end

function QuestTogether:RefreshCopyableWindow()
	local frame = self.copyableWindow
	if not frame or not frame.editBox or not frame.scrollFrame then
		return
	end

	local titleText = type(frame.copyableTitle) == "string" and frame.copyableTitle or "QuestTogether"
	local hintText = type(frame.copyableHint) == "string" and frame.copyableHint or ""
	local getText = frame.copyableGetText
	local text = type(frame.copyableText) == "string" and frame.copyableText or ""
	if type(getText) == "function" then
		local ok, resolvedText = pcall(getText, self)
		if ok and type(resolvedText) == "string" then
			text = resolvedText
		elseif ok and resolvedText ~= nil then
			text = tostring(resolvedText)
		else
			text = ""
		end
	end

	if frame.titleLabel then
		frame.titleLabel:SetText(titleText)
	end
	if frame.hintLabel then
		frame.hintLabel:SetText(hintText)
	end
	frame.editBox:SetText(text)
	frame.editBox:ClearFocus()
	frame.editBox:HighlightText(0, 0)
	frame.editBox:SetCursorPosition(0)
	if frame.clearButton then
		local hasClearHandler = type(frame.copyableOnClear) == "function"
		frame.clearButton:SetShown(hasClearHandler)
		frame.clearButton:SetText(type(frame.copyableClearLabel) == "string" and frame.copyableClearLabel or "Clear")
	end

	local maxScroll = math.max(0, frame.editBox:GetHeight() - frame.scrollFrame:GetHeight())
	frame.scrollFrame:SetVerticalScroll(maxScroll)
end

function QuestTogether:EnsureCopyableWindow()
	if self.copyableWindow then
		return self.copyableWindow
	end

	local frame = CreateFrame("Frame", "QuestTogetherCopyableWindow", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(900, 560)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetScript("OnShow", function()
		QuestTogether:RefreshCopyableWindow()
	end)

	local title = frame.TitleText or frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	if not frame.TitleText then
		title:SetPoint("TOP", frame, "TOP", 0, -8)
	end
	title:SetText("QuestTogether")

	local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -34)
	hint:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -34)
	hint:SetJustifyH("LEFT")
	hint:SetText("")

	local textInset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate3")
	textInset:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -54)
	textInset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 44)

	local scrollFrame = CreateFrame("ScrollFrame", nil, textInset, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", textInset, "TOPLEFT", 6, -6)
	scrollFrame:SetPoint("BOTTOMRIGHT", textInset, "BOTTOMRIGHT", -28, 6)

	local editBox = CreateFrame("EditBox", nil, scrollFrame)
	editBox:SetMultiLine(true)
	editBox:SetAutoFocus(false)
	editBox:EnableMouse(true)
	editBox:SetFontObject(ChatFontNormal)
	editBox:SetWidth(1)
	editBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	scrollFrame:SetScrollChild(editBox)
	scrollFrame:SetScript("OnSizeChanged", function(scrollChildFrame, width)
		editBox:SetWidth(math.max(1, width - 8))
	end)

	local selectAllButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	selectAllButton:SetSize(96, 24)
	selectAllButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 12)
	selectAllButton:SetText("Select All")
	selectAllButton:SetScript("OnClick", function()
		editBox:SetFocus()
		editBox:HighlightText()
	end)

	local clearButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	clearButton:SetSize(80, 24)
	clearButton:SetPoint("LEFT", selectAllButton, "RIGHT", 8, 0)
	clearButton:SetText("Clear")
	clearButton:SetScript("OnClick", function()
		local onClear = frame.copyableOnClear
		if type(onClear) == "function" then
			onClear(QuestTogether)
		end
	end)

	local closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	closeButton:SetSize(80, 24)
	closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
	closeButton:SetText("Close")
	closeButton:SetScript("OnClick", function()
		frame:Hide()
	end)

	frame.scrollFrame = scrollFrame
	frame.editBox = editBox
	frame.selectAllButton = selectAllButton
	frame.clearButton = clearButton
	frame.closeButton = closeButton
	frame.titleLabel = title
	frame.hintLabel = hint
	self.copyableWindow = frame

	return frame
end

function QuestTogether:ShowCopyableWindow(options)
	local frame = self:EnsureCopyableWindow()
	if not frame then
		return false
	end

	options = options or {}
	frame.copyableTitle = type(options.title) == "string" and options.title or "QuestTogether"
	frame.copyableHint = type(options.hint) == "string" and options.hint or ""
	frame.copyableText = type(options.text) == "string" and options.text or nil
	frame.copyableGetText = type(options.getText) == "function" and options.getText or nil
	frame.copyableOnClear = type(options.onClear) == "function" and options.onClear or nil
	frame.copyableClearLabel = type(options.clearLabel) == "string" and options.clearLabel or "Clear"

	frame:Show()
	frame:Raise()
	self:RefreshCopyableWindow()
	return true
end

function QuestTogether:ShowTestResultsWindow()
	return self:ShowCopyableWindow({
		title = "QuestTogether Test Results",
		hint = "Results from /qt test. Click Select All, then Ctrl+C.",
		getText = function(addon)
			return addon:GetTestResultLogText()
		end,
		onClear = function(addon)
			addon:ClearTestResultLog()
		end,
		clearLabel = "Clear",
	})
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
	self:Print("/qt test - Run in-game unit tests and open results in a copyable window")
end

function QuestTogether:HandleSlashCommand(input)
	local command, rest = SafeMatch(input, "^(%S*)%s*(.-)$")
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
		local optionKey, optionValueText = SafeMatch(rest, "^(%S+)%s+(.+)$")
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
		local optionKey = SafeMatch(rest, "^(%S+)$")
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
			local explicitSenderName, explicitText = SafeMatch(rest, "^(%S+)%s+(.+)$")
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

	local numQuestLogEntries = self.API and self.API.GetNumQuestLogEntries and self.API.GetNumQuestLogEntries() or 0
	local questsTracked = 0

	for questLogIndex = 1, numQuestLogEntries do
		local questInfo = self.API and self.API.GetQuestLogInfo and self.API.GetQuestLogInfo(questLogIndex) or nil
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
	local numericQuestId = self:NormalizeQuestID(questId)
	self:Debugf("quest", "WatchQuest questId=%s", tostring(numericQuestId or questId))

	if not numericQuestId or not questInfo then
		return
	end

	local tracker = self:GetPlayerTracker()
	local questLogIndex = self.API
		and self.API.GetQuestLogIndexForQuestID
		and self.API.GetQuestLogIndexForQuestID(numericQuestId)
	local questTitle = self:GetQuestTitle(numericQuestId, questInfo)

	tracker[numericQuestId] = {
		title = questTitle,
		taskAnnouncementType = self:GetTaskAnnouncementType(numericQuestId),
		objectives = {},
		-- Cached numeric objective values used to gate progress announcements.
		-- This avoids noisy chat lines caused by text-only objective rewrites.
		objectiveValues = {},
		isComplete = self.API and self.API.IsQuestComplete and self.API.IsQuestComplete(numericQuestId) or false,
		isReadyForTurnIn = self.API and self.API.IsQuestReadyForTurnIn and self.API.IsQuestReadyForTurnIn(numericQuestId)
			or false,
	}
	self:RefreshTrackedQuestAnnouncementIcon(numericQuestId, tracker[numericQuestId])
	self:DebugState("quest", "trackedQuest", tracker[numericQuestId])

	if not questLogIndex then
		return
	end

	local numObjectives = self.API and self.API.GetNumQuestLeaderBoards and self.API.GetNumQuestLeaderBoards(questLogIndex)
		or 0
	for objectiveIndex = 1, numObjectives do
		local objectiveText, objectiveType, _, currentValue =
			self.API.GetQuestObjectiveInfo and self.API.GetQuestObjectiveInfo(numericQuestId, objectiveIndex, false)
		if objectiveText == nil and objectiveType == nil and currentValue == nil then
			objectiveText = ""
		end
		if objectiveType == "progressbar" then
			local progress = self.API.GetQuestProgressBarPercent and self.API.GetQuestProgressBarPercent(numericQuestId)
			local roundedProgress = self:NormalizeQuestProgressPercent(progress) or 0
			objectiveText = tostring(roundedProgress)
				.. "% "
				.. tostring(self:StripTrailingParentheticalPercent(objectiveText))
			currentValue = roundedProgress
		end
		tracker[numericQuestId].objectives[objectiveIndex] = objectiveText
		tracker[numericQuestId].objectiveValues[objectiveIndex] = self:SafeToNumber(currentValue)
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

	handler(QuestTogether, eventName, ...)
end

QuestTogether.eventFrame = QuestTogether.eventFrame or CreateFrame("Frame")
QuestTogether.eventFrame:SetScript("OnEvent", DispatchEvent)
QuestTogether.eventFrame:RegisterEvent("ADDON_LOADED")
QuestTogether.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
QuestTogether.eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
QuestTogether.eventFrame:RegisterEvent("PLAYER_LOGIN")
QuestTogether.eventFrame:RegisterEvent("PLAYER_LOGOUT")
