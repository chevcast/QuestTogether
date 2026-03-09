--[[
QuestTogether Announcement Communication Layer

This file handles lightweight announcement events over a shared addon channel.
Local quest events are always published. Each receiving client applies its own
display preferences when deciding whether to render bubbles or print chat logs.
]]

local QuestTogether = _G.QuestTogether

local ANNOUNCEMENT_WIRE_VERSION = 1
local ANNOUNCEMENT_COMMAND = "ANN"
local ANNOUNCEMENT_MAX_TEXT_LENGTH = 220

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

function QuestTogether:EncodeAnnouncementPayload(eventData)
	local fields = {
		tostring(ANNOUNCEMENT_WIRE_VERSION),
		self:EscapePayload(eventData.eventType or ""),
		self:EscapePayload(eventData.senderGUID or ""),
		self:EscapePayload(eventData.classFile or ""),
		self:EscapePayload(eventData.senderName or ""),
		self:EscapePayload(eventData.text or ""),
	}

	return table.concat(fields, ",")
end

function QuestTogether:DecodeAnnouncementPayload(payload)
	if not payload or payload == "" then
		return nil
	end

	local fields = SplitByDelimiter(payload, ",")
	local version = tonumber(fields[1] or "")
	if version ~= ANNOUNCEMENT_WIRE_VERSION then
		return nil
	end

	local eventType = self:UnescapePayload(fields[2] or "")
	local senderGUID = self:UnescapePayload(fields[3] or "")
	local classFile = self:UnescapePayload(fields[4] or "")
	local senderName = self:UnescapePayload(fields[5] or "")
	local text = self:UnescapePayload(fields[6] or "")

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
	}
end

function QuestTogether:GetAnnouncementChannelLocalID()
	if not self.API or not self.API.GetChannelName then
		return nil
	end

	local localID = self.API.GetChannelName(self.announcementChannelName)
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

function QuestTogether:EnsureAnnouncementChannelJoined()
	if not self.isEnabled then
		self:Debug("Skipping channel join because addon is disabled", "comms")
		return false
	end

	local currentLocalID = self:GetAnnouncementChannelLocalID()
	if currentLocalID then
		self.announcementChannelLocalID = currentLocalID
		return true
	end

	if not self.API or not self.API.JoinPermanentChannel then
		self:Debug("JoinPermanentChannel API unavailable", "comms")
		return false
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
end

function QuestTogether:BuildLocalAnnouncementEvent(eventType, text)
	local senderName = self:GetPlayerFullName() or self:GetPlayerName()
	local senderGUID = self.API.UnitGUID and self.API.UnitGUID("player") or ""
	local sanitizedText = self:SanitizeAnnouncementText(text)
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
	}
end

function QuestTogether:IsAnnouncementChannelEvent(channel, localID, name)
	if channel ~= "CHANNEL" then
		return false
	end

	local expectedLocalID = self:GetAnnouncementChannelLocalID() or self.announcementChannelLocalID
	if type(expectedLocalID) == "number" and expectedLocalID > 0 and type(localID) == "number" then
		return expectedLocalID == localID
	end

	return name == self.announcementChannelName
end

function QuestTogether:SendAnnouncementEvent(eventType, text)
	if not self.isEnabled then
		self:Debugf("comms", "Skipping announcement send while disabled eventType=%s", tostring(eventType))
		return false
	end

	local eventData = self:BuildLocalAnnouncementEvent(eventType, text)
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
	local hasNearbySignal = false
	if not isLocal and self.FindVisiblePlayerNameplateForSender then
		nearbyNameplate = self:FindVisiblePlayerNameplateForSender(eventData.senderGUID, senderName)
		hasNearbyNameplate = nearbyNameplate ~= nil
	end
	if not isLocal and not hasNearbyNameplate and self.FindNearbyPlayerUnitTokenForSender then
		nearbyUnitToken = self:FindNearbyPlayerUnitTokenForSender(eventData.senderGUID, senderName)
	end
	hasNearbySignal = hasNearbyNameplate or nearbyUnitToken ~= nil
	isGrouped = self:IsGroupedSender(senderName)
	self:Debugf(
		"comms",
		"HandleAnnouncement eventType=%s sender=%s isLocal=%s grouped=%s nearbyNameplate=%s nearbyUnit=%s",
		tostring(eventData.eventType),
		tostring(senderName),
		tostring(isLocal),
		tostring(isGrouped),
		tostring(hasNearbyNameplate),
		tostring(nearbyUnitToken)
	)

	if not isLocal and not self:ShouldShowAnnouncementsForRemoteSender(senderName, hasNearbySignal) then
		self:Debugf("comms", "Filtered remote sender=%s by showProgressFor scope", tostring(senderName))
		return false
	end

	if self:GetOption("showChatLogs") then
		local shouldPrint = isLocal or isGrouped or hasNearbySignal
		if shouldPrint then
			self:Debugf("comms", "Printing chat log sender=%s class=%s", tostring(senderName), tostring(classFile))
			self:PrintConsoleAnnouncement(eventData.text, senderName, classFile, eventData.eventType)
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
				self:ShowPrototypeBubbleOnUnitNameplate("player", eventData.text, eventData.eventType)
			else
				self:Debug("Skipped local personal bubble due to hideMyOwnChatBubbles or unavailable renderer", "bubble")
			end
		elseif hasNearbyNameplate and self.ShowPrototypeBubbleOnNameplate then
			self:Debugf("bubble", "Showing remote nearby bubble sender=%s", tostring(senderName))
			self:ShowPrototypeBubbleOnNameplate(nearbyNameplate, eventData.text, eventData.eventType)
		else
			self:Debugf("bubble", "Skipped remote bubble sender=%s reason=no nearby nameplate", tostring(senderName))
		end
	else
		self:Debug("Chat bubble display disabled", "bubble")
	end

	return true
end

function QuestTogether:PublishAnnouncementEvent(eventType, text)
	local eventData = self:BuildLocalAnnouncementEvent(eventType, text)
	if not eventData then
		self:Debugf("comms", "PublishAnnouncementEvent dropped eventType=%s due to empty payload", tostring(eventType))
		return false
	end

	self:DebugState("comms", "publishAnnouncement", eventData)
	self:SendAnnouncementEvent(eventType, text)
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
		"Received addon message channel=%s sender=%s localID=%s name=%s bytes=%d",
		tostring(channel),
		tostring(sender),
		tostring(localID),
		tostring(name),
		type(message) == "string" and #message or 0
	)
	if self:IsSelfSender(sender) then
		self:Debugf("comms", "Ignoring self-sent addon message sender=%s", tostring(sender))
		return
	end
	if not self:IsAnnouncementChannelEvent(channel, localID, name) then
		self:Debugf("comms", "Ignoring addon message outside announcement channel sender=%s", tostring(sender))
		return
	end

	local command, payload = self:DeserializeWireMessage(message)
	if command ~= ANNOUNCEMENT_COMMAND then
		self:Debugf("comms", "Ignoring addon command=%s", tostring(command))
		return
	end

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
end
