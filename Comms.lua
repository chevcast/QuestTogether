--[[
QuestTogether Announcement Communication Layer

This file handles lightweight announcement events over a shared addon channel.
Local quest events are always published. Each receiving client applies its own
display preferences when deciding whether to render bubbles or print chat logs.
]]

local QuestTogether = _G.QuestTogether

local ANNOUNCEMENT_WIRE_VERSION = 2
local ANNOUNCEMENT_COMMAND = "ANN"
local PING_REQUEST_VERSION = 1
local PING_REQUEST_COMMAND = "PING"
local PING_RESPONSE_VERSION = 1
local PING_RESPONSE_COMMAND = "PONG"
local ANNOUNCEMENT_MAX_TEXT_LENGTH = 220
local PING_REQUEST_TIMEOUT_SECONDS = 10
local ANNOUNCEMENT_CHANNEL_FILTER_EVENTS = {
	"CHAT_MSG_CHANNEL",
	"CHAT_MSG_CHANNEL_NOTICE",
	"CHAT_MSG_CHANNEL_NOTICE_USER",
}

local function IsSecretValue(value)
	if type(issecretvalue) ~= "function" then
		return false
	end

	local ok, result = pcall(issecretvalue, value)
	return ok and result and true or false
end

local function SafeDebugString(value)
	if IsSecretValue(value) then
		return "<secret>"
	end

	return tostring(value)
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

function QuestTogether:EscapePayload(value)
	local text = tostring(value or "")
	return (text:gsub("([^%w%-_%.~])", function(character)
		return string.format("%%%02X", string.byte(character))
	end))
end

function QuestTogether:UnescapePayload(value)
	local text = tostring(value or "")
	return (text:gsub("%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
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
	local version = tonumber(fields[1] or "")
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
	}

	return table.concat(fields, ",")
end

function QuestTogether:DecodePingResponsePayload(payload)
	if not payload or payload == "" then
		return nil
	end

	local fields = SplitByDelimiter(payload, ",")
	local version = tonumber(fields[1] or "")
	if version ~= PING_RESPONSE_VERSION then
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
	}

	return table.concat(fields, ",")
end

function QuestTogether:DecodeAnnouncementPayload(payload)
	if not payload or payload == "" then
		return nil
	end

	local fields = SplitByDelimiter(payload, ",")
	local version = tonumber(fields[1] or "")
	if version ~= 1 and version ~= ANNOUNCEMENT_WIRE_VERSION then
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
	}
end

function QuestTogether:GetAnnouncementChannelLocalID()
	if not self.API or not self.API.GetChannelName then
		return nil
	end

	local localID = self.API.GetChannelName(self.announcementChannelName)
	if IsSecretValue(localID) then
		return nil
	end
	if type(localID) == "number" and localID > 0 then
		return localID
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

	local maxWindows = tonumber(self.API.GetNumChatWindows()) or 0
	for chatFrameID = 1, maxWindows do
		local chatFrame = self.API.GetChatFrameByID(chatFrameID)
		if chatFrame then
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
		level = level and tostring(level) or "",
		zoneName = locationInfo and tostring(locationInfo.zoneName or "") or "",
		coordX = numericCoordX and string.format("%.1f", numericCoordX) or "",
		coordY = numericCoordY and string.format("%.1f", numericCoordY) or "",
		warMode = locationInfo and tostring(locationInfo.warMode and "1" or "0") or "",
	}
end

function QuestTogether:BuildLocalAnnouncementEvent(eventType, text, questId)
	local senderName = self:GetPlayerFullName() or self:GetPlayerName()
	local senderGUID = self.API.UnitGUID and self.API.UnitGUID("player") or ""
	local sanitizedText = self:SanitizeAnnouncementText(text)
	local iconAsset, iconKind = self:GetAnnouncementIconInfo(eventType, questId)
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
	local senderName = tostring(unitName) .. "-" .. tostring((unitRealm or self.API.GetRealmName() or ""):gsub("%s+", ""))

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

function QuestTogether:IsAnnouncementChannelEvent(channel, localID, name)
	if channel ~= "CHANNEL" then
		return false
	end

	return type(name) == "string" and name ~= "" and name == self.announcementChannelName
end

function QuestTogether:SendAnnouncementEvent(eventType, text, questId)
	if not self.isEnabled then
		self:Debugf("comms", "Skipping announcement send while disabled eventType=%s", tostring(eventType))
		return false
	end

	local eventData = self:BuildLocalAnnouncementEvent(eventType, text, questId)
	if not eventData then
		self:Debugf("comms", "Failed to build local announcement event eventType=%s", tostring(eventType))
		return false
	end

	self:DebugState("comms", "localAnnouncement", eventData)
	return self:SendAnnouncementWireEvent(eventData)
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

	local requestId = string.format(
		"%s-%d-%d",
		tostring(self:GetPlayerName() or "player"),
		math.floor((self.API.GetTime and self.API.GetTime() or 0) * 1000),
		self.API.Random and self.API.Random(1000, 9999) or 1000
	)
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

	if self:GetOption("showChatBubbles") then
		if isLocal then
			if not self:GetOption("hideMyOwnChatBubbles") and self.ShowPrototypeBubbleOnUnitNameplate then
				self:Debug("Showing local personal bubble", "bubble")
				self:ShowPrototypeBubbleOnUnitNameplate(
					"player",
					eventData.text,
					eventData.eventType,
					eventData.iconAsset,
					eventData.iconKind
				)
			else
				self:Debug("Skipped local personal bubble due to hideMyOwnChatBubbles or unavailable renderer", "bubble")
			end
		elseif allowRemoteDisplay and hasNearbyNameplate and self.ShowPrototypeBubbleOnNameplate then
			self:Debugf("bubble", "Showing remote nearby bubble sender=%s", tostring(senderName))
			self:ShowPrototypeBubbleOnNameplate(
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

function QuestTogether:PublishAnnouncementEvent(eventType, text, questId)
	local eventData = self:BuildLocalAnnouncementEvent(eventType, text, questId)
	if not eventData then
		self:Debugf("comms", "PublishAnnouncementEvent dropped eventType=%s due to empty payload", tostring(eventType))
		return false
	end

	self:DebugState("comms", "publishAnnouncement", eventData)
	self:SendAnnouncementEvent(eventType, text, questId)
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
		tostring(channel),
		tostring(sender),
		tostring(name),
		type(message) == "string" and #message or 0
	)
	if self:IsSelfSender(sender) then
		self:Debugf("comms", "Ignoring self-sent addon message sender=%s", tostring(sender))
		return
	end
	if self.IsIgnoredPlayerName and self:IsIgnoredPlayerName(self:NormalizeMemberName(sender) or sender) then
		self:Debugf("comms", "Ignoring addon message from ignored sender=%s", tostring(sender))
		return
	end
	if not self:IsAnnouncementChannelEvent(channel, localID, name) then
		self:Debugf("comms", "Ignoring addon message outside announcement channel sender=%s", tostring(sender))
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

	self:Debugf("comms", "Ignoring addon command=%s", tostring(command))
end
