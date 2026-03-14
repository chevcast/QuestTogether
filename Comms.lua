--[[
QuestTogether Announcement Communication Layer

This file handles lightweight announcement events over a shared addon channel.
Local quest events are always published. Each receiving client applies its own
display preferences when deciding whether to render bubbles or print chat logs.
]]

local QuestTogether = _G.QuestTogether

local ANNOUNCEMENT_WIRE_VERSION = 3
local ANNOUNCEMENT_COMMAND = "ANN"
local PING_REQUEST_VERSION = 1
local PING_REQUEST_COMMAND = "PING"
local PING_RESPONSE_VERSION = 2
local PING_RESPONSE_COMMAND = "PONG"
local QUEST_COMPARE_REQUEST_VERSION = 1
local QUEST_COMPARE_REQUEST_COMMAND = "QCMP"
local QUEST_COMPARE_ENTRY_VERSION = 1
local QUEST_COMPARE_ENTRY_COMMAND = "QCQE"
local QUEST_COMPARE_DONE_VERSION = 1
local QUEST_COMPARE_DONE_COMMAND = "QCDN"
local ANNOUNCEMENT_MAX_TEXT_LENGTH = 220
local PING_REQUEST_TIMEOUT_SECONDS = 10
local QUEST_COMPARE_TIMEOUT_SECONDS = 10
local ANNOUNCEMENT_CHANNEL_FILTER_EVENTS = {
	"CHAT_MSG_CHANNEL",
	"CHAT_MSG_CHANNEL_NOTICE",
	"CHAT_MSG_CHANNEL_NOTICE_USER",
}

local function SafeDebugString(value)
	if QuestTogether and QuestTogether.SafeToString then
		return QuestTogether:SafeToString(value, "<secret>")
	end

	-- Debug logging must never throw when formatting potentially protected values.
	local ok, stringValue = pcall(tostring, value)
	if ok then
		return stringValue
	end
	return "<secret>"
end

local function SafeChannelNumber(addon, value)
	if addon and addon.SafeToNumber then
		return addon:SafeToNumber(value)
	end

	-- Fallback numeric coercion should never throw on protected values.
	local ok, numberValue = pcall(tonumber, value)
	if not ok then
		return nil
	end

	return numberValue
end

local function MatchesAnnouncementChannelName(addon, value)
	if type(value) ~= "string" or value == "" then
		return false
	end

	local channelName = tostring(addon.announcementChannelName or "")
	if channelName == "" then
		return false
	end

	if value == channelName then
		return true
	end

	return string.find(value, channelName, 1, true) ~= nil
end

local function SplitByDelimiter(text, delimiter)
	local pieces = {}
	if text == nil or text == "" then
		return pieces
	end

	local startIndex = 1
	while true do
		local delimiterIndex = string.find(text, delimiter, startIndex, true)
		if not delimiterIndex then
			pieces[#pieces + 1] = string.sub(text, startIndex)
			break
		end
		pieces[#pieces + 1] = string.sub(text, startIndex, delimiterIndex - 1)
		startIndex = delimiterIndex + #delimiter
	end

	return pieces
end

local function SafeNumber(addon, value)
	if addon and addon.SafeToNumber then
		return addon:SafeToNumber(value)
	end

	-- Fallback numeric coercion should never throw on protected values.
	local ok, numberValue = pcall(tonumber, value)
	if not ok then
		return nil
	end

	return numberValue
end

local function NormalizeRealmName(addon, realmName)
	local sourceRealm = realmName
	if sourceRealm == nil or sourceRealm == "" then
		sourceRealm = addon and addon.API and addon.API.GetRealmName and addon.API.GetRealmName() or ""
	end
	if addon and addon.SafeStripWhitespace then
		return addon:SafeStripWhitespace(sourceRealm, "")
	end
	-- Realm normalization is called from chat/nameplate paths; keep failures non-fatal.
	local okText, textValue = pcall(tostring, sourceRealm)
	if not okText then
		return ""
	end
	local okStrip, stripped = pcall(string.gsub, textValue, "%s+", "")
	if not okStrip then
		return ""
	end
	return stripped
end

function QuestTogether:EscapePayload(value)
	local text = tostring(value or "")
	return (string.gsub(text, "([^%w%-_%.~])", function(character)
		return string.format("%%%02X", string.byte(character))
	end))
end

function QuestTogether:UnescapePayload(value)
	local text = tostring(value or "")
	return (string.gsub(text, "%%(%x%x)", function(hex)
		local firstChar = string.sub(hex or "", 1, 1)
		local secondChar = string.sub(hex or "", 2, 2)
		local firstNibble = nil
		local secondNibble = nil
		if firstChar ~= "" then
			local firstByte = string.byte(string.upper(firstChar))
			if firstByte >= string.byte("0") and firstByte <= string.byte("9") then
				firstNibble = firstByte - string.byte("0")
			elseif firstByte >= string.byte("A") and firstByte <= string.byte("F") then
				firstNibble = firstByte - string.byte("A") + 10
			end
		end
		if secondChar ~= "" then
			local secondByte = string.byte(string.upper(secondChar))
			if secondByte >= string.byte("0") and secondByte <= string.byte("9") then
				secondNibble = secondByte - string.byte("0")
			elseif secondByte >= string.byte("A") and secondByte <= string.byte("F") then
				secondNibble = secondByte - string.byte("A") + 10
			end
		end
		if firstNibble == nil or secondNibble == nil then
			return ""
		end
		return string.char((firstNibble * 16) + secondNibble)
	end))
end

function QuestTogether:SerializeWireMessage(command, payload)
	return tostring(command or "") .. "|" .. tostring(payload or "")
end

function QuestTogether:DeserializeWireMessage(message)
	if not message then
		return nil, nil
	end

	local command, payload = string.match(message, "^([^|]+)|?(.*)$")
	if not command or command == "" then
		return nil, nil
	end

	return command, payload
end

function QuestTogether:SanitizeAnnouncementText(text)
	local sanitized = tostring(text or "")
	sanitized = string.gsub(sanitized, "^%s+", "")
	sanitized = string.gsub(sanitized, "%s+$", "")
	if #sanitized > ANNOUNCEMENT_MAX_TEXT_LENGTH then
		sanitized = string.sub(sanitized, 1, ANNOUNCEMENT_MAX_TEXT_LENGTH)
	end
	return sanitized
end

function QuestTogether:EncodePingRequestPayload(requestData)
	local fields = {
		tostring(PING_REQUEST_VERSION),
		self:EscapePayload(requestData.requestId or ""),
		self:EscapePayload(requestData.requesterName or ""),
	}

	return table.concat(fields, ",")
end

function QuestTogether:DecodePingRequestPayload(payload)
	if not payload or payload == "" then
		return nil
	end

	local fields = SplitByDelimiter(payload, ",")
	local version = SafeNumber(self, fields[1] or "")
	if version ~= PING_REQUEST_VERSION then
		return nil
	end

	local requestId = self:UnescapePayload(fields[2] or "")
	local requesterName = self:UnescapePayload(fields[3] or "")
	if requestId == "" then
		return nil
	end

	return {
		version = version,
		requestId = requestId,
		requesterName = requesterName,
	}
end

function QuestTogether:EncodePingResponsePayload(responseData)
	local fields = {
		tostring(PING_RESPONSE_VERSION),
		self:EscapePayload(responseData.requestId or ""),
		self:EscapePayload(responseData.senderName or ""),
		self:EscapePayload(responseData.realmName or ""),
		self:EscapePayload(responseData.raceName or ""),
		self:EscapePayload(responseData.classFile or ""),
		self:EscapePayload(responseData.className or ""),
		self:EscapePayload(responseData.level or ""),
		self:EscapePayload(responseData.zoneName or ""),
		self:EscapePayload(responseData.coordX or ""),
		self:EscapePayload(responseData.coordY or ""),
		self:EscapePayload(responseData.warMode or ""),
		self:EscapePayload(responseData.mapID or ""),
		self:EscapePayload(responseData.addonVersion or ""),
	}

	return table.concat(fields, ",")
end

function QuestTogether:DecodePingResponsePayload(payload)
	if not payload or payload == "" then
		return nil
	end

	local fields = SplitByDelimiter(payload, ",")
	local version = SafeNumber(self, fields[1] or "")
	if version ~= 1 and version ~= PING_RESPONSE_VERSION then
		return nil
	end

	local requestId = self:UnescapePayload(fields[2] or "")
	local senderName = self:UnescapePayload(fields[3] or "")
	local realmName = self:UnescapePayload(fields[4] or "")
	local raceName = self:UnescapePayload(fields[5] or "")
	local classFile = self:UnescapePayload(fields[6] or "")
	local className = self:UnescapePayload(fields[7] or "")
	local level = self:UnescapePayload(fields[8] or "")
	local zoneName = self:UnescapePayload(fields[9] or "")
	local coordX = self:UnescapePayload(fields[10] or "")
	local coordY = self:UnescapePayload(fields[11] or "")
	local warMode = self:UnescapePayload(fields[12] or "")
	local mapID = self:UnescapePayload(fields[13] or "")
	local addonVersion = self:UnescapePayload(fields[14] or "")
	if requestId == "" or senderName == "" then
		return nil
	end

	return {
		version = version,
		requestId = requestId,
		senderName = senderName,
		realmName = realmName,
		raceName = raceName,
		classFile = classFile,
		className = className,
		level = level,
		zoneName = zoneName,
		coordX = coordX,
		coordY = coordY,
		warMode = warMode,
		mapID = mapID,
		addonVersion = addonVersion,
	}
end

function QuestTogether:EncodeQuestCompareRequestPayload(requestData)
	local fields = {
		tostring(QUEST_COMPARE_REQUEST_VERSION),
		self:EscapePayload(requestData.requestId or ""),
		self:EscapePayload(requestData.requesterName or ""),
		self:EscapePayload(requestData.targetName or ""),
	}

	return table.concat(fields, ",")
end

function QuestTogether:DecodeQuestCompareRequestPayload(payload)
	if not payload or payload == "" then
		return nil
	end

	local fields = SplitByDelimiter(payload, ",")
	local version = SafeNumber(self, fields[1] or "")
	if version ~= QUEST_COMPARE_REQUEST_VERSION then
		return nil
	end

	local requestId = self:UnescapePayload(fields[2] or "")
	local requesterName = self:UnescapePayload(fields[3] or "")
	local targetName = self:UnescapePayload(fields[4] or "")
	if requestId == "" or targetName == "" then
		return nil
	end

	return {
		version = version,
		requestId = requestId,
		requesterName = requesterName,
		targetName = targetName,
	}
end

function QuestTogether:EncodeQuestCompareEntryPayload(entryData)
	local fields = {
		tostring(QUEST_COMPARE_ENTRY_VERSION),
		self:EscapePayload(entryData.requestId or ""),
		self:EscapePayload(entryData.senderName or ""),
		self:EscapePayload(entryData.classFile or ""),
		self:EscapePayload(entryData.questId or ""),
		self:EscapePayload(entryData.questTitle or ""),
		self:EscapePayload(entryData.isComplete and "1" or "0"),
		self:EscapePayload(entryData.isPushable and "1" or "0"),
	}

	return table.concat(fields, ",")
end

function QuestTogether:DecodeQuestCompareEntryPayload(payload)
	if not payload or payload == "" then
		return nil
	end

	local fields = SplitByDelimiter(payload, ",")
	local version = SafeNumber(self, fields[1] or "")
	if version ~= QUEST_COMPARE_ENTRY_VERSION then
		return nil
	end

	local requestId = self:UnescapePayload(fields[2] or "")
	local senderName = self:UnescapePayload(fields[3] or "")
	local classFile = ""
	local questId = ""
	local questTitle = ""
	local isComplete = false
	local isPushable = false

	if fields[8] ~= nil then
		classFile = self:UnescapePayload(fields[4] or "")
		questId = self:UnescapePayload(fields[5] or "")
		questTitle = self:UnescapePayload(fields[6] or "")
		isComplete = self:UnescapePayload(fields[7] or "") == "1"
		isPushable = self:UnescapePayload(fields[8] or "") == "1"
	else
		questId = self:UnescapePayload(fields[4] or "")
		questTitle = self:UnescapePayload(fields[5] or "")
		isComplete = self:UnescapePayload(fields[6] or "") == "1"
		isPushable = self:UnescapePayload(fields[7] or "") == "1"
	end
	if requestId == "" or senderName == "" or questId == "" then
		return nil
	end

	return {
		version = version,
		requestId = requestId,
		senderName = senderName,
		classFile = classFile,
		questId = questId,
		questTitle = questTitle,
		isComplete = isComplete,
		isPushable = isPushable,
	}
end

function QuestTogether:EncodeQuestCompareDonePayload(doneData)
	local fields = {
		tostring(QUEST_COMPARE_DONE_VERSION),
		self:EscapePayload(doneData.requestId or ""),
		self:EscapePayload(doneData.senderName or ""),
		self:EscapePayload(doneData.classFile or ""),
		self:EscapePayload(doneData.count or ""),
	}

	return table.concat(fields, ",")
end

function QuestTogether:DecodeQuestCompareDonePayload(payload)
	if not payload or payload == "" then
		return nil
	end

	local fields = SplitByDelimiter(payload, ",")
	local version = SafeNumber(self, fields[1] or "")
	if version ~= QUEST_COMPARE_DONE_VERSION then
		return nil
	end

	local requestId = self:UnescapePayload(fields[2] or "")
	local senderName = self:UnescapePayload(fields[3] or "")
	local classFile = ""
	local count = ""
	if fields[5] ~= nil then
		classFile = self:UnescapePayload(fields[4] or "")
		count = self:UnescapePayload(fields[5] or "")
	else
		count = self:UnescapePayload(fields[4] or "")
	end
	if requestId == "" or senderName == "" then
		return nil
	end

	return {
		version = version,
		requestId = requestId,
		senderName = senderName,
		classFile = classFile,
		count = SafeNumber(self, count) or 0,
	}
end

function QuestTogether:EncodeAnnouncementPayload(eventData)
	local fields = {
		tostring(ANNOUNCEMENT_WIRE_VERSION),
		self:EscapePayload(eventData.eventType or ""),
		self:EscapePayload(eventData.senderGUID or ""),
		self:EscapePayload(eventData.classFile or ""),
		self:EscapePayload(eventData.senderName or ""),
		self:EscapePayload(eventData.text or ""),
		self:EscapePayload(eventData.questId or ""),
		self:EscapePayload(eventData.iconAsset or ""),
		self:EscapePayload(eventData.iconKind or ""),
		self:EscapePayload(eventData.zoneName or ""),
		self:EscapePayload(eventData.coordX or ""),
		self:EscapePayload(eventData.coordY or ""),
		self:EscapePayload(eventData.warMode or ""),
		self:EscapePayload(eventData.emoteToken or ""),
	}

	return table.concat(fields, ",")
end

function QuestTogether:DecodeAnnouncementPayload(payload)
	if not payload or payload == "" then
		return nil
	end

	local fields = SplitByDelimiter(payload, ",")
	local version = SafeNumber(self, fields[1] or "")
	if version ~= 1 and version ~= 2 and version ~= ANNOUNCEMENT_WIRE_VERSION then
		return nil
	end

	local eventType = self:UnescapePayload(fields[2] or "")
	local senderGUID = self:UnescapePayload(fields[3] or "")
	local classFile = self:UnescapePayload(fields[4] or "")
	local senderName = self:UnescapePayload(fields[5] or "")
	local text = self:UnescapePayload(fields[6] or "")
	local questId = self:UnescapePayload(fields[7] or "")
	local iconAsset = self:UnescapePayload(fields[8] or "")
	local iconKind = self:UnescapePayload(fields[9] or "")
	local zoneName = self:UnescapePayload(fields[10] or "")
	local coordX = self:UnescapePayload(fields[11] or "")
	local coordY = self:UnescapePayload(fields[12] or "")
	local warMode = self:UnescapePayload(fields[13] or "")
	local emoteToken = self:UnescapePayload(fields[14] or "")

	if eventType == "" or senderName == "" or text == "" then
		return nil
	end

	return {
		version = version,
		eventType = eventType,
		senderGUID = senderGUID,
		classFile = classFile,
		senderName = senderName,
		text = text,
		questId = questId,
		iconAsset = iconAsset,
		iconKind = iconKind,
		zoneName = zoneName,
		coordX = coordX,
		coordY = coordY,
		warMode = warMode,
		emoteToken = emoteToken,
	}
end

function QuestTogether:GetAnnouncementChannelLocalID()
	if not self.API or not self.API.GetChannelName then
		return nil
	end

	local localID = self.API.GetChannelName(self.announcementChannelName)
	local numericLocalID = SafeChannelNumber(self, localID)
	if numericLocalID and numericLocalID > 0 then
		return numericLocalID
	end

	return nil
end

function QuestTogether:GetAnnouncementChannelTarget()
	local localID = self:GetAnnouncementChannelLocalID() or self.announcementChannelLocalID
	if type(localID) == "number" and localID > 0 then
		return localID
	end

	return self.announcementChannelName
end

function QuestTogether:AnnouncementChannelChatFilter(_, _, ...)
	for argumentIndex = 1, select("#", ...) do
		if MatchesAnnouncementChannelName(self, select(argumentIndex, ...)) then
			return true
		end
	end

	return false
end

function QuestTogether:RegisterAnnouncementChannelChatFilters()
	if self.announcementChannelChatFiltersRegistered then
		return
	end
	if not self.API or not self.API.AddMessageEventFilter then
		return
	end

	self.announcementChannelChatFilterFunc = self.announcementChannelChatFilterFunc
		or function(...)
			return QuestTogether:AnnouncementChannelChatFilter(...)
		end

	for _, eventName in ipairs(ANNOUNCEMENT_CHANNEL_FILTER_EVENTS) do
		self.API.AddMessageEventFilter(eventName, self.announcementChannelChatFilterFunc)
	end
	self.announcementChannelChatFiltersRegistered = true
end

function QuestTogether:UnregisterAnnouncementChannelChatFilters()
	if not self.announcementChannelChatFiltersRegistered then
		return
	end
	if not self.API or not self.API.RemoveMessageEventFilter or not self.announcementChannelChatFilterFunc then
		self.announcementChannelChatFiltersRegistered = nil
		return
	end

	for _, eventName in ipairs(ANNOUNCEMENT_CHANNEL_FILTER_EVENTS) do
		self.API.RemoveMessageEventFilter(eventName, self.announcementChannelChatFilterFunc)
	end
	self.announcementChannelChatFiltersRegistered = nil
end

function QuestTogether:HideAnnouncementChannelFromChatWindows()
	if not self.API or not self.API.GetNumChatWindows or not self.API.GetChatFrameByID or not self.API.RemoveChatWindowChannel then
		return
	end

	local maxWindows = SafeNumber(self, self.API.GetNumChatWindows()) or 0
	for chatFrameID = 1, maxWindows do
		local chatFrame = self.API.GetChatFrameByID(chatFrameID)
		if chatFrame then
			-- Some chat frames reject channel removal in edge states; keep cleanup best-effort.
			pcall(self.API.RemoveChatWindowChannel, chatFrame, self.announcementChannelName)
		end
	end
end

function QuestTogether:EnsureAnnouncementChannelJoined()
	if not self.isEnabled then
		self:Debug("Skipping channel join because addon is disabled", "comms")
		return false
	end

	local currentLocalID = self:GetAnnouncementChannelLocalID()
	if currentLocalID then
		self.announcementChannelLocalID = currentLocalID
		if self.HideAnnouncementChannelFromChatWindows then
			self:HideAnnouncementChannelFromChatWindows()
		end
		return true
	end

	if not self.API or not self.API.JoinPermanentChannel then
		self:Debug("JoinPermanentChannel API unavailable", "comms")
		return false
	end

	if self.RegisterAnnouncementChannelChatFilters then
		self:RegisterAnnouncementChannelChatFilters()
	end

	local chatFrameId = (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.GetID and DEFAULT_CHAT_FRAME:GetID()) or 1
	self:Debugf(
		"comms",
		"Joining announcement channel name=%s chatFrameId=%s",
		tostring(self.announcementChannelName),
		tostring(chatFrameId)
	)
	self.API.JoinPermanentChannel(self.announcementChannelName, nil, chatFrameId, 1)

	currentLocalID = self:GetAnnouncementChannelLocalID()
	if currentLocalID then
		self.announcementChannelLocalID = currentLocalID
		if self.HideAnnouncementChannelFromChatWindows then
			self:HideAnnouncementChannelFromChatWindows()
		end
		self:Debugf("comms", "Joined announcement channel localID=%s", tostring(currentLocalID))
		return true
	end

	self:Debug("Unable to join announcement channel " .. tostring(self.announcementChannelName), "comms")
	return false
end

function QuestTogether:LeaveAnnouncementChannel()
	if self.API and self.API.LeaveChannelByName then
		self:Debugf("comms", "Leaving announcement channel name=%s", tostring(self.announcementChannelName))
		-- Channel leave can fail if Blizzard already removed it; no need to hard fail disable.
		pcall(self.API.LeaveChannelByName, self.announcementChannelName)
	end
	self.announcementChannelLocalID = nil
	if self.UnregisterAnnouncementChannelChatFilters then
		self:UnregisterAnnouncementChannelChatFilters()
	end
end

function QuestTogether:GetPlayerPingMetadata()
	local fullName = self:GetPlayerFullName() or self:GetPlayerName() or "Unknown"
	local unitName, unitRealm = self.API.UnitFullName and self.API.UnitFullName("player")
	local realmName = unitRealm or (self.API.GetRealmName and self.API.GetRealmName()) or ""
	local className, classFile = self.API.UnitClass and self.API.UnitClass("player")
	local raceName = nil
	if self.API.UnitRace then
		raceName = self.API.UnitRace("player")
	end
	local level = self.API.UnitLevel and self.API.UnitLevel("player") or ""
	local locationInfo = self.GetPlayerAnnouncementLocationInfo and self:GetPlayerAnnouncementLocationInfo() or {}
	local numericCoordX = locationInfo and self.SafeToNumber and self:SafeToNumber(locationInfo.coordX) or nil
	local numericCoordY = locationInfo and self.SafeToNumber and self:SafeToNumber(locationInfo.coordY) or nil

	return {
		senderName = tostring(fullName or ""),
		realmName = tostring(realmName or ""),
		raceName = tostring(raceName or ""),
		classFile = tostring(classFile or ""),
		className = tostring(className or ""),
		addonVersion = tostring(self:GetAddonVersion() or ""),
		level = level and tostring(level) or "",
		zoneName = locationInfo and tostring(locationInfo.zoneName or "") or "",
		coordX = numericCoordX and string.format("%.1f", numericCoordX) or "",
		coordY = numericCoordY and string.format("%.1f", numericCoordY) or "",
		warMode = locationInfo and tostring(locationInfo.warMode and "1" or "0") or "",
		mapID = locationInfo and tostring(locationInfo.mapID or "") or "",
	}
end

function QuestTogether:BuildChannelRequestId(prefix)
	local requestPrefix = tostring(prefix or "req")
	return string.format(
		"%s-%s-%d-%d",
		requestPrefix,
		tostring(self:GetPlayerName() or "player"),
		math.floor((self.API.GetTime and self.API.GetTime() or 0) * 1000),
		self.API.Random and self.API.Random(1000, 9999) or 1000
	)
end

function QuestTogether:BuildLocalAnnouncementEvent(eventType, text, questId, extraData)
	local senderName = self:GetPlayerFullName() or self:GetPlayerName()
	local senderGUID = self.API.UnitGUID and self.API.UnitGUID("player") or ""
	local sanitizedText = self:SanitizeAnnouncementText(text)
	local iconAsset, iconKind = self:GetAnnouncementIconInfo(eventType, questId)
	if type(extraData) == "table" then
		local overrideIconAsset = tostring(extraData.iconAsset or "")
		local overrideIconKind = tostring(extraData.iconKind or "")
		if overrideIconAsset ~= "" then
			iconAsset = overrideIconAsset
			iconKind = overrideIconKind ~= "" and overrideIconKind or iconKind
		end
	end
	local locationInfo = self.GetPlayerAnnouncementLocationInfo and self:GetPlayerAnnouncementLocationInfo() or nil
	local numericCoordX = locationInfo and self.SafeToNumber and self:SafeToNumber(locationInfo.coordX) or nil
	local numericCoordY = locationInfo and self.SafeToNumber and self:SafeToNumber(locationInfo.coordY) or nil
	if sanitizedText == "" then
		return nil
	end

	return {
		version = ANNOUNCEMENT_WIRE_VERSION,
		eventType = tostring(eventType or ""),
		senderGUID = tostring(senderGUID or ""),
		classFile = tostring(self:GetPlayerClassFile() or ""),
		senderName = tostring(senderName or ""),
		text = sanitizedText,
		questId = questId and tostring(questId) or "",
		iconAsset = tostring(iconAsset or ""),
		iconKind = tostring(iconKind or ""),
		zoneName = locationInfo and tostring(locationInfo.zoneName or "") or "",
		coordX = numericCoordX and string.format("%.1f", numericCoordX) or "",
		coordY = numericCoordY and string.format("%.1f", numericCoordY) or "",
		warMode = locationInfo and tostring(locationInfo.warMode and "1" or "0") or "",
		emoteToken = type(extraData) == "table" and tostring(extraData.emoteToken or "") or "",
	}
end

function QuestTogether:BuildAnnouncementEventForUnit(unitToken, eventType, text)
	if type(unitToken) ~= "string" or unitToken == "" then
		return nil
	end

	local sanitizedText = self:SanitizeAnnouncementText(text)
	if sanitizedText == "" then
		return nil
	end

	local unitName, unitRealm = self.API.UnitFullName(unitToken)
	if not unitName or unitName == "" then
		return nil
	end

	local _, classFile = self.API.UnitClass(unitToken)
	local senderGUID = self.API.UnitGUID and self.API.UnitGUID(unitToken) or ""
	local senderName = tostring(unitName) .. "-" .. tostring(NormalizeRealmName(self, unitRealm))

	return {
		version = ANNOUNCEMENT_WIRE_VERSION,
		eventType = tostring(eventType or ""),
		senderGUID = tostring(senderGUID or ""),
		classFile = tostring(classFile or ""),
		senderName = senderName,
		text = sanitizedText,
		questId = "",
		iconAsset = "",
		iconKind = "",
		zoneName = "",
		coordX = "",
		coordY = "",
		warMode = "",
		emoteToken = "",
	}
end

function QuestTogether:BuildPingResponse(requestId)
	if type(requestId) ~= "string" or requestId == "" then
		return nil
	end

	local payload = self:GetPlayerPingMetadata()
	payload.requestId = requestId
	return payload
end

function QuestTogether:BuildQuestCompareEntries()
	local entries = {}
	local numQuestLogEntries = SafeNumber(self, self.API.GetNumQuestLogEntries and self.API.GetNumQuestLogEntries()) or 0

	for questLogIndex = 1, numQuestLogEntries do
		local questInfo = self.API.GetQuestLogInfo and self.API.GetQuestLogInfo(questLogIndex)
		if questInfo and not questInfo.isHeader and not questInfo.isHidden and questInfo.questID then
			entries[#entries + 1] = {
				questId = tostring(questInfo.questID),
				questTitle = self:GetQuestTitle(questInfo.questID, questInfo),
				isComplete = questInfo.isComplete and true or false,
				isPushable = self.API.IsPushableQuest and self.API.IsPushableQuest(questInfo.questID) and true or false,
			}
		end
	end

	return entries
end

function QuestTogether:SendQuestCompareEntry(requestId, entryData)
	if type(requestId) ~= "string" or requestId == "" or type(entryData) ~= "table" then
		return false
	end

	local wireMessage = self:SerializeWireMessage(
		QUEST_COMPARE_ENTRY_COMMAND,
		self:EncodeQuestCompareEntryPayload({
			requestId = requestId,
			senderName = self:GetPlayerFullName() or self:GetPlayerName() or "",
			classFile = self:GetPlayerClassFile() or "",
			questId = entryData.questId or "",
			questTitle = entryData.questTitle or "",
			isComplete = entryData.isComplete and true or false,
			isPushable = entryData.isPushable and true or false,
		})
	)
	self.API.SendAddonMessage(self.commPrefix, wireMessage, "CHANNEL", self:GetAnnouncementChannelTarget())
	return true
end

function QuestTogether:SendQuestCompareDone(requestId, count)
	if type(requestId) ~= "string" or requestId == "" then
		return false
	end

	local wireMessage = self:SerializeWireMessage(
		QUEST_COMPARE_DONE_COMMAND,
		self:EncodeQuestCompareDonePayload({
			requestId = requestId,
			senderName = self:GetPlayerFullName() or self:GetPlayerName() or "",
			classFile = self:GetPlayerClassFile() or "",
			count = SafeNumber(self, count) or 0,
		})
	)
	self.API.SendAddonMessage(self.commPrefix, wireMessage, "CHANNEL", self:GetAnnouncementChannelTarget())
	return true
end

function QuestTogether:HandleQuestCompareRequest(requestData)
	if type(requestData) ~= "table" or type(requestData.requestId) ~= "string" or requestData.requestId == "" then
		return false
	end

	local targetName = self:NormalizeMemberName(requestData.targetName) or requestData.targetName
	local playerName = self:GetPlayerFullName() or self:GetPlayerName() or ""
	local normalizedPlayerName = self:NormalizeMemberName(playerName) or playerName
	if targetName ~= normalizedPlayerName then
		return false
	end
	if not self:EnsureAnnouncementChannelJoined() then
		return false
	end

	local entries = self:BuildQuestCompareEntries()
	for _, entryData in ipairs(entries) do
		self:SendQuestCompareEntry(requestData.requestId, entryData)
	end
	self:SendQuestCompareDone(requestData.requestId, #entries)
	return true
end

function QuestTogether:HandleQuestCompareEntry(entryData)
	if type(entryData) ~= "table" or type(entryData.requestId) ~= "string" or entryData.requestId == "" then
		return false
	end

	self.pendingQuestCompareRequests = self.pendingQuestCompareRequests or {}
	local pending = self.pendingQuestCompareRequests[entryData.requestId]
	if type(pending) ~= "table" then
		return false
	end

	local senderName = self:NormalizeMemberName(entryData.senderName) or entryData.senderName
	if pending.targetName ~= senderName then
		return false
	end

	if type(entryData.classFile) == "string" and entryData.classFile ~= "" then
		pending.classFile = entryData.classFile
	end
	pending.count = (pending.count or 0) + 1
	if self.PrintQuestCompareMessage then
		self:PrintQuestCompareMessage(senderName, entryData, pending.classFile)
	end
	return true
end

function QuestTogether:HandleQuestCompareDone(doneData)
	if type(doneData) ~= "table" or type(doneData.requestId) ~= "string" or doneData.requestId == "" then
		return false
	end

	self.pendingQuestCompareRequests = self.pendingQuestCompareRequests or {}
	local pending = self.pendingQuestCompareRequests[doneData.requestId]
	if type(pending) ~= "table" then
		return false
	end

	local senderName = self:NormalizeMemberName(doneData.senderName) or doneData.senderName
	if pending.targetName ~= senderName then
		return false
	end

	if type(doneData.classFile) == "string" and doneData.classFile ~= "" then
		pending.classFile = doneData.classFile
	end
	self.pendingQuestCompareRequests[doneData.requestId] = nil
	if self.PrintQuestCompareDone then
		self:PrintQuestCompareDone(senderName, doneData.count, pending.classFile)
	end
	return true
end

function QuestTogether:RequestQuestCompare(speakerName)
	local targetName = self:NormalizeMemberName(speakerName) or tostring(speakerName or "")
	if targetName == "" then
		return false
	end

	if self.PrintQuestCompareStart then
		self:PrintQuestCompareStart(targetName, self:GetGroupedSenderClassFile(targetName))
	end

	local playerName = self:GetPlayerFullName() or self:GetPlayerName() or ""
	local normalizedPlayerName = self:NormalizeMemberName(playerName) or playerName
	if targetName == normalizedPlayerName then
		local localEntries = self:BuildQuestCompareEntries()
		for _, entryData in ipairs(localEntries) do
			if self.PrintQuestCompareMessage then
				self:PrintQuestCompareMessage(targetName, entryData, self:GetPlayerClassFile())
			end
		end
		if self.PrintQuestCompareDone then
			self:PrintQuestCompareDone(targetName, #localEntries, self:GetPlayerClassFile())
		end
		return true
	end

	if not self.isEnabled or not self:EnsureAnnouncementChannelJoined() then
		return false
	end

	local requestId = self:BuildChannelRequestId("qcmp")
	self.pendingQuestCompareRequests = self.pendingQuestCompareRequests or {}
	self.pendingQuestCompareRequests[requestId] = {
		targetName = targetName,
		classFile = self:GetGroupedSenderClassFile(targetName),
		count = 0,
	}
	self.API.Delay(QUEST_COMPARE_TIMEOUT_SECONDS, function()
		local pending = QuestTogether.pendingQuestCompareRequests and QuestTogether.pendingQuestCompareRequests[requestId]
		if pending then
			QuestTogether.pendingQuestCompareRequests[requestId] = nil
		end
	end)

	local wireMessage = self:SerializeWireMessage(
		QUEST_COMPARE_REQUEST_COMMAND,
		self:EncodeQuestCompareRequestPayload({
			requestId = requestId,
			requesterName = playerName,
			targetName = targetName,
		})
	)
	self.API.SendAddonMessage(self.commPrefix, wireMessage, "CHANNEL", self:GetAnnouncementChannelTarget())
	return true
end

function QuestTogether:IsAnnouncementChannelEvent(channel, localID, name)
	if channel ~= "CHANNEL" then
		return false
	end

	if type(name) == "string" and name ~= "" and name == self.announcementChannelName then
		return true
	end

	local expectedLocalID = SafeChannelNumber(self, self.announcementChannelLocalID)
	local incomingLocalID = SafeChannelNumber(self, localID)
	return expectedLocalID ~= nil and incomingLocalID ~= nil and expectedLocalID == incomingLocalID
end

function QuestTogether:SendAnnouncementEvent(eventType, text, questId, extraData)
	if not self.isEnabled then
		self:Debugf("comms", "Skipping announcement send while disabled eventType=%s", tostring(eventType))
		return false
	end

	local eventData = self:BuildLocalAnnouncementEvent(eventType, text, questId, extraData)
	if not eventData then
		self:Debugf("comms", "Failed to build local announcement event eventType=%s", tostring(eventType))
		return false
	end

	self:DebugState("comms", "localAnnouncement", eventData)
	return self:SendAnnouncementWireEvent(eventData)
end

function QuestTogether:IsSpecialCompletionEmote(emoteToken)
	return emoteToken == "mountspecial" or emoteToken == "forthealliance" or emoteToken == "forthehorde"
end

function QuestTogether:GetSafeRemoteCompletionEmote(emoteToken)
	local token = tostring(emoteToken or "")
	if token == "" then
		return nil
	end

	if not self:IsSpecialCompletionEmote(token) then
		return token
	end

	if token == "mountspecial" and self.API and self.API.IsMounted and self.API.IsMounted() then
		return token
	end

	if token == "forthealliance" or token == "forthehorde" then
		local faction = self.API and self.API.GetFaction and self.API.GetFaction() or nil
		if faction == "Alliance" then
			return "forthealliance"
		end
		if faction == "Horde" then
			return "forthehorde"
		end
	end

	local safetyCounter = 0
	repeat
		safetyCounter = safetyCounter + 1
		token = self:PickRandomCompletionEmote()
	until not self:IsSpecialCompletionEmote(token) or safetyCounter > 20

	if self:IsSpecialCompletionEmote(token) then
		return nil
	end

	return token
end

function QuestTogether:PlayRemoteCompletionEmote(eventData, nearbyUnitToken, senderName)
	if type(eventData) ~= "table" or not self:GetOption("emoteOnNearbyPlayerQuestCompletion") then
		return false
	end

	local token = self:GetSafeRemoteCompletionEmote(eventData.emoteToken)
	if not token then
		return false
	end

	local emoteTarget = nearbyUnitToken or senderName
	if not emoteTarget or emoteTarget == "" or not (self.API and self.API.DoEmote) then
		return false
	end

	self.API.DoEmote(token, emoteTarget)
	return true
end

function QuestTogether:SendAnnouncementWireEvent(eventData)
	if not self.isEnabled or type(eventData) ~= "table" then
		self:DebugState("comms", "Rejected wire event", eventData)
		return false
	end

	if not self:EnsureAnnouncementChannelJoined() then
		self:Debugf("comms", "Unable to send eventType=%s because channel join failed", tostring(eventData.eventType))
		return false
	end

	local wireMessage = self:SerializeWireMessage(ANNOUNCEMENT_COMMAND, self:EncodeAnnouncementPayload(eventData))
	self:Debugf(
		"comms",
		"Sending wire eventType=%s sender=%s target=%s bytes=%d",
		tostring(eventData.eventType),
		tostring(eventData.senderName),
		tostring(self:GetAnnouncementChannelTarget()),
		#wireMessage
	)
	self.API.SendAddonMessage(self.commPrefix, wireMessage, "CHANNEL", self:GetAnnouncementChannelTarget())
	return true
end

function QuestTogether:SendPingRequest()
	if not self.isEnabled then
		return false, "QuestTogether is disabled."
	end
	if not self:EnsureAnnouncementChannelJoined() then
		return false, "Unable to join the QuestTogether announcement channel."
	end

	local requestId = self:BuildChannelRequestId("ping")
	local requesterName = self:GetPlayerFullName() or self:GetPlayerName() or ""
	self.pendingPingRequests = self.pendingPingRequests or {}
	self.pendingPingRequests[requestId] = true
	self.API.Delay(PING_REQUEST_TIMEOUT_SECONDS, function()
		if QuestTogether.pendingPingRequests then
			QuestTogether.pendingPingRequests[requestId] = nil
		end
	end)

	local requestData = {
		requestId = requestId,
		requesterName = requesterName,
	}
	local wireMessage = self:SerializeWireMessage(PING_REQUEST_COMMAND, self:EncodePingRequestPayload(requestData))
	self:Debugf("comms", "Sending ping request id=%s", tostring(requestId))
	self.API.SendAddonMessage(self.commPrefix, wireMessage, "CHANNEL", self:GetAnnouncementChannelTarget())

	local localResponse = self:BuildPingResponse(requestId)
	if localResponse and self.HandlePingResponse then
		self:HandlePingResponse(localResponse)
	end

	return true, requestId
end

function QuestTogether:SendPingResponse(requestId)
	local responseData = self:BuildPingResponse(requestId)
	if not responseData then
		return false
	end

	local wireMessage = self:SerializeWireMessage(PING_RESPONSE_COMMAND, self:EncodePingResponsePayload(responseData))
	self:Debugf("comms", "Sending ping response id=%s sender=%s", tostring(requestId), tostring(responseData.senderName))
	self.API.SendAddonMessage(self.commPrefix, wireMessage, "CHANNEL", self:GetAnnouncementChannelTarget())
	return true
end

function QuestTogether:HandlePingRequest(requestData)
	if type(requestData) ~= "table" or type(requestData.requestId) ~= "string" or requestData.requestId == "" then
		return false
	end
	if not self:EnsureAnnouncementChannelJoined() then
		return false
	end
	return self:SendPingResponse(requestData.requestId)
end

function QuestTogether:HandlePingResponse(responseData)
	if type(responseData) ~= "table" or type(responseData.requestId) ~= "string" or responseData.requestId == "" then
		return false
	end

	self.pendingPingRequests = self.pendingPingRequests or {}
	if not self.pendingPingRequests[responseData.requestId] then
		return false
	end

	if self.PrintPingResponse then
		self:PrintPingResponse(responseData)
	end
	return true
end

function QuestTogether:SendBubbleAnnouncementTest(text, senderName)
	if not self.isEnabled then
		return false, "QuestTogether is disabled."
	end

	local eventData = nil
	if self.API.UnitExists and self.API.UnitExists("target") then
		if not self.API.UnitIsPlayer or not self.API.UnitIsPlayer("target") then
			return false, "Your target must be a player."
		end
		self:Debug("bubbletest using current target", "comms")

		eventData = self:BuildAnnouncementEventForUnit("target", "QUEST_PROGRESS", text)
		if not eventData then
			return false, "Unable to build a test announcement from your target."
		end
	else
		local trimmedSenderName = tostring(senderName or "")
		trimmedSenderName = string.gsub(trimmedSenderName, "^%s+", "")
		trimmedSenderName = string.gsub(trimmedSenderName, "%s+$", "")
		if trimmedSenderName == "" then
			return false, "Target a nearby player or provide a visible player name."
		end
		if not self.FindVisiblePlayerNameplateForSender then
			return false, "Visible player lookup is unavailable."
		end

		local nameplate = self:FindVisiblePlayerNameplateForSender("", trimmedSenderName)
		local unitToken = nameplate and nameplate.GetUnit and nameplate:GetUnit() or nil
		if not unitToken or unitToken == "" then
			return false, "No visible nearby player matched that name."
		end
		self:Debugf("comms", "bubbletest resolved explicit sender=%s unitToken=%s", tostring(trimmedSenderName), tostring(unitToken))

		eventData = self:BuildAnnouncementEventForUnit(unitToken, "QUEST_PROGRESS", text)
		if not eventData then
			return false, "Unable to build a test announcement for that player."
		end
	end

	if not self:SendAnnouncementWireEvent(eventData) then
		return false, "Unable to send the bubble test announcement."
	end

	self:HandleAnnouncementEvent(eventData, false)
	return true, eventData.senderName
end

function QuestTogether:ShouldShowAnnouncementsForRemoteSender(senderName, hasNearbyNameplate)
	local isGrouped = self:IsGroupedSender(senderName)
	local scope = self:GetOption("showProgressFor")

	if scope == "party_only" then
		return isGrouped
	end

	return isGrouped or hasNearbyNameplate
end

function QuestTogether:ShouldPlayRemoteEmoteForAnnouncement(eventData)
	if type(eventData) ~= "table" then
		return false
	end

	return eventData.eventType == "QUEST_COMPLETED"
		or eventData.eventType == "WORLD_QUEST_COMPLETED"
		or eventData.eventType == "BONUS_OBJECTIVE_COMPLETED"
end

function QuestTogether:HandleAnnouncementEvent(eventData, isLocal)
	if type(eventData) ~= "table" then
		self:Debug("Rejected announcement event because payload was not a table", "comms")
		return false
	end
	if not self:ShouldDisplayAnnouncementType(eventData.eventType) then
		self:Debugf("comms", "Filtered eventType=%s by local display settings", tostring(eventData.eventType))
		return false
	end

	local senderName = self:NormalizeMemberName(eventData.senderName) or eventData.senderName
	local classFile = eventData.classFile
	local isGrouped = false
	if (not classFile or classFile == "") and not isLocal then
		classFile = self:GetGroupedSenderClassFile(senderName)
	end

	local nearbyNameplate = nil
	local hasNearbyNameplate = false
	local nearbyUnitToken = nil
	local nearbyByLocation = false
	local hasNearbySignal = false
	if not isLocal and self.FindVisiblePlayerNameplateForSender then
		nearbyNameplate = self:FindVisiblePlayerNameplateForSender(eventData.senderGUID, senderName)
		hasNearbyNameplate = nearbyNameplate ~= nil
	end
	if not isLocal and not hasNearbyNameplate and self.FindNearbyPlayerUnitTokenForSender then
		nearbyUnitToken = self:FindNearbyPlayerUnitTokenForSender(eventData.senderGUID, senderName)
	end
	if not isLocal and not hasNearbyNameplate and nearbyUnitToken == nil and self.IsAnnouncementSenderNearbyByLocation then
		nearbyByLocation = self:IsAnnouncementSenderNearbyByLocation(eventData)
	end
	hasNearbySignal = hasNearbyNameplate or nearbyUnitToken ~= nil or nearbyByLocation
	isGrouped = self:IsGroupedSender(senderName)
	local forceAllChatLogs = not isLocal
		and self:GetOption("showChatLogs")
		and self:GetOption("devLogAllAnnouncements")
	local allowRemoteDisplay = isLocal or self:ShouldShowAnnouncementsForRemoteSender(senderName, hasNearbySignal)
	self:Debugf(
		"comms",
		"HandleAnnouncement eventType=%s sender=%s isLocal=%s grouped=%s nearbyNameplate=%s nearbyUnit=%s nearbyLocation=%s forceLogs=%s",
		tostring(eventData.eventType),
		tostring(senderName),
		tostring(isLocal),
		tostring(isGrouped),
		tostring(hasNearbyNameplate),
		tostring(nearbyUnitToken),
		tostring(nearbyByLocation),
		tostring(forceAllChatLogs)
	)

	if not allowRemoteDisplay and not forceAllChatLogs then
		self:Debugf("comms", "Filtered remote sender=%s by showProgressFor scope", tostring(senderName))
		return false
	end

	if self:GetOption("showChatLogs") then
		local shouldPrint = isLocal or isGrouped or hasNearbySignal or forceAllChatLogs
		if shouldPrint then
			self:Debugf("comms", "Printing chat log sender=%s class=%s", tostring(senderName), tostring(classFile))
			self:PrintConsoleAnnouncement(
				eventData.text,
				senderName,
				classFile,
				eventData.eventType,
				eventData.iconAsset,
				eventData.iconKind,
				eventData
			)
		else
			self:Debugf("comms", "Skipped chat log sender=%s reason=no nearby/group signal", tostring(senderName))
		end
	else
		self:Debug("Chat log display disabled", "comms")
	end

	if
		not isLocal
		and allowRemoteDisplay
		and hasNearbySignal
		and self:ShouldPlayRemoteEmoteForAnnouncement(eventData)
	then
		local emoteTarget = nearbyUnitToken
		if not emoteTarget and hasNearbyNameplate and nearbyNameplate and nearbyNameplate.GetUnit then
			emoteTarget = nearbyNameplate:GetUnit()
		end
		if self:PlayRemoteCompletionEmote(eventData, emoteTarget, senderName) then
			self:Debugf("comms", "Played remote completion emote sender=%s token=%s", tostring(senderName), tostring(eventData.emoteToken))
		end
	end

	if self:GetOption("showChatBubbles") then
		if isLocal then
			if not self:GetOption("hideMyOwnChatBubbles") and self.ShowAnnouncementBubbleOnUnitNameplate then
				self:Debug("Showing local personal bubble", "bubble")
				self:ShowAnnouncementBubbleOnUnitNameplate(
					"player",
					eventData.text,
					eventData.eventType,
					eventData.iconAsset,
					eventData.iconKind
				)
			else
				self:Debug("Skipped local personal bubble due to hideMyOwnChatBubbles or unavailable renderer", "bubble")
			end
		elseif allowRemoteDisplay and hasNearbyNameplate and self.ShowAnnouncementBubbleOnNameplate then
			self:Debugf("bubble", "Showing remote nearby bubble sender=%s", tostring(senderName))
			self:ShowAnnouncementBubbleOnNameplate(
				nearbyNameplate,
				eventData.text,
				eventData.eventType,
				eventData.iconAsset,
				eventData.iconKind
			)
		else
			self:Debugf("bubble", "Skipped remote bubble sender=%s reason=no nearby nameplate", tostring(senderName))
		end
	else
		self:Debug("Chat bubble display disabled", "bubble")
	end

	return true
end

function QuestTogether:PublishAnnouncementEvent(eventType, text, questId, extraData)
	if self.API.UnitIsDeadOrGhost and self.API.UnitIsDeadOrGhost("player") then
		self:Debugf("comms", "PublishAnnouncementEvent suppressed while dead eventType=%s", tostring(eventType))
		return false
	end

	local eventData = self:BuildLocalAnnouncementEvent(eventType, text, questId, extraData)
	if not eventData then
		self:Debugf("comms", "PublishAnnouncementEvent dropped eventType=%s due to empty payload", tostring(eventType))
		return false
	end

	self:DebugState("comms", "publishAnnouncement", eventData)
	self:SendAnnouncementEvent(eventType, text, questId, extraData)
	self:HandleAnnouncementEvent(eventData, true)
	return true
end

function QuestTogether:CHAT_MSG_ADDON(_, prefix, message, channel, sender, _, _, localID, name)
	self:OnCommReceived(prefix, message, channel, sender, localID, name)
end

function QuestTogether:OnCommReceived(prefix, message, channel, sender, localID, name)
	if prefix ~= self.commPrefix then
		return
	end
	self:Debugf(
		"comms",
		"Received addon message channel=%s sender=%s name=%s bytes=%d",
		SafeDebugString(channel),
		SafeDebugString(sender),
		SafeDebugString(name),
		type(message) == "string" and #message or 0
	)
	if self:IsSelfSender(sender) then
		self:Debugf("comms", "Ignoring self-sent addon message sender=%s", SafeDebugString(sender))
		return
	end
	if self.IsIgnoredPlayerName and self:IsIgnoredPlayerName(self:NormalizeMemberName(sender) or sender) then
		self:Debugf("comms", "Ignoring addon message from ignored sender=%s", SafeDebugString(sender))
		return
	end
	if not self:IsAnnouncementChannelEvent(channel, localID, name) then
		self:Debugf("comms", "Ignoring addon message outside announcement channel sender=%s", SafeDebugString(sender))
		return
	end

	local command, payload = self:DeserializeWireMessage(message)
	if command == ANNOUNCEMENT_COMMAND then
		local eventData = self:DecodeAnnouncementPayload(payload)
		if not eventData then
			self:Debug("Failed to decode announcement payload", "comms")
			return
		end

		if not eventData.senderName or eventData.senderName == "" then
			eventData.senderName = self:NormalizeMemberName(sender) or sender
		end

		self:DebugState("comms", "receivedAnnouncement", eventData)
		self:HandleAnnouncementEvent(eventData, false)
		return
	end

	if command == PING_REQUEST_COMMAND then
		local requestData = self:DecodePingRequestPayload(payload)
		if not requestData then
			self:Debug("Failed to decode ping request payload", "comms")
			return
		end
		self:HandlePingRequest(requestData)
		return
	end

	if command == PING_RESPONSE_COMMAND then
		local responseData = self:DecodePingResponsePayload(payload)
		if not responseData then
			self:Debug("Failed to decode ping response payload", "comms")
			return
		end
		self:HandlePingResponse(responseData)
		return
	end

	if command == QUEST_COMPARE_REQUEST_COMMAND then
		local requestData = self:DecodeQuestCompareRequestPayload(payload)
		if not requestData then
			self:Debug("Failed to decode quest compare request payload", "comms")
			return
		end
		self:HandleQuestCompareRequest(requestData)
		return
	end

	if command == QUEST_COMPARE_ENTRY_COMMAND then
		local entryData = self:DecodeQuestCompareEntryPayload(payload)
		if not entryData then
			self:Debug("Failed to decode quest compare entry payload", "comms")
			return
		end
		self:HandleQuestCompareEntry(entryData)
		return
	end

	if command == QUEST_COMPARE_DONE_COMMAND then
		local doneData = self:DecodeQuestCompareDonePayload(payload)
		if not doneData then
			self:Debug("Failed to decode quest compare done payload", "comms")
			return
		end
		self:HandleQuestCompareDone(doneData)
		return
	end

	self:Debugf("comms", "Ignoring addon command=%s", tostring(command))
end
