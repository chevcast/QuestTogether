--[[
QuestTogether Communication Layer (No AceComm/AceSerializer)

This file handles addon-to-addon messages with native WoW APIs:
- Receive via CHAT_MSG_ADDON
- Send via C_ChatInfo.SendAddonMessage

Message format on the wire:
  <COMMAND>|<PAYLOAD>

Payload encoding strategy:
- Simple strings use percent-encoding (EscapePayload/UnescapePayload).
- Delta and snapshot payloads are compact custom strings.
- Legacy UPDATE_QUEST_TRACKER is still accepted as backward-compat input.
]]

local QuestTogether = _G.QuestTogether

local SNAPSHOT_MAX_CHUNK_SIZE = 900
local OBJECTIVE_DELTA_COALESCE_SECONDS = 0.25

local RAW_PAYLOAD_COMMANDS = {
	SYNC_REQ = true,
	SYNC_SNAP = true,
	Q_ADD = true,
	Q_OBJ = true,
	Q_REM = true,
}

-- Split helper that uses a plain-string delimiter (no Lua pattern magic).
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

-- Percent-encode arbitrary text for safe transport in our delimiter-based format.
function QuestTogether:EscapePayload(value)
	local text = tostring(value or "")
	return (text:gsub("([^%w%-_%.~])", function(character)
		return string.format("%%%02X", string.byte(character))
	end))
end

-- Reverse of EscapePayload.
function QuestTogether:UnescapePayload(value)
	local text = tostring(value or "")
	return (text:gsub("%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end))
end

-- Legacy full snapshot format for UPDATE_QUEST_TRACKER compatibility.
function QuestTogether:EncodeQuestTracker(tracker)
	local encodedQuests = {}
	for questId, questData in pairs(tracker or {}) do
		local objectives = (questData and questData.objectives) or {}
		local objectiveCount = #objectives
		local row = {
			tostring(questId),
			self:EscapePayload((questData and questData.title) or ""),
			tostring(objectiveCount),
		}
		for index = 1, objectiveCount do
			row[#row + 1] = self:EscapePayload(objectives[index] or "")
		end
		encodedQuests[#encodedQuests + 1] = table.concat(row, ",")
	end
	return table.concat(encodedQuests, ";")
end

-- Legacy decoder for backward compatibility.
function QuestTogether:DecodeQuestTracker(payload)
	local tracker = {}
	if payload == nil or payload == "" then
		return tracker
	end

	local questRows = SplitByDelimiter(payload, ";")
	for _, rowText in ipairs(questRows) do
		local fields = SplitByDelimiter(rowText, ",")
		local questId = tonumber(fields[1])
		local title = self:UnescapePayload(fields[2] or "")
		local objectiveCount = tonumber(fields[3]) or 0

		if questId then
			local questData = {
				title = title,
				objectives = {},
			}
			for objectiveIndex = 1, objectiveCount do
				questData.objectives[objectiveIndex] = self:UnescapePayload(fields[3 + objectiveIndex] or "")
			end
			tracker[questId] = questData
		end
	end

	return tracker
end

-- Encode one full quest record with explicit complete + revision metadata.
function QuestTogether:EncodeQuestRecord(questId, questData, revision)
	local objectives = (questData and questData.objectives) or {}
	local objectiveCount = #objectives
	local fields = {
		tostring(questId or 0),
		self:EscapePayload((questData and questData.title) or ""),
		(questData and questData.isComplete) and "1" or "0",
		tostring(revision or 0),
		tostring(objectiveCount),
	}

	for objectiveIndex = 1, objectiveCount do
		fields[#fields + 1] = self:EscapePayload(objectives[objectiveIndex] or "")
	end

	return table.concat(fields, ",")
end

function QuestTogether:DecodeQuestRecord(recordText)
	if not recordText or recordText == "" then
		return nil, nil, nil
	end

	local fields = SplitByDelimiter(recordText, ",")
	local questId = tonumber(fields[1] or "")
	if not questId then
		return nil, nil, nil
	end

	local title = self:UnescapePayload(fields[2] or "")
	local isComplete = (fields[3] == "1")
	local revision = tonumber(fields[4]) or 0
	local objectiveCount = tonumber(fields[5]) or 0
	local objectives = {}

	for objectiveIndex = 1, objectiveCount do
		objectives[objectiveIndex] = self:UnescapePayload(fields[5 + objectiveIndex] or "")
	end

	return questId, {
		title = title,
		objectives = objectives,
		isComplete = isComplete,
	}, revision
end

function QuestTogether:EncodeObjectiveDelta(questId, revision, changedObjectives, optionalIsComplete)
	local changed = changedObjectives or {}
	local objectiveIndices = {}
	for objectiveIndex in pairs(changed) do
		objectiveIndices[#objectiveIndices + 1] = tonumber(objectiveIndex)
	end
	table.sort(objectiveIndices)

	local completeToken = "x"
	if optionalIsComplete ~= nil then
		completeToken = optionalIsComplete and "1" or "0"
	end

	local fields = {
		tostring(questId or 0),
		tostring(revision or 0),
		completeToken,
		tostring(#objectiveIndices),
	}

	for _, objectiveIndex in ipairs(objectiveIndices) do
		fields[#fields + 1] = tostring(objectiveIndex)
		fields[#fields + 1] = self:EscapePayload(changed[objectiveIndex] or "")
	end

	return table.concat(fields, ",")
end

function QuestTogether:DecodeObjectiveDelta(payload)
	if not payload or payload == "" then
		return nil, nil, nil, nil
	end

	local fields = SplitByDelimiter(payload, ",")
	local questId = tonumber(fields[1] or "")
	local revision = tonumber(fields[2] or "")
	local completeToken = fields[3]
	local changedCount = tonumber(fields[4]) or 0
	local changedObjectives = {}
	local fieldIndex = 5

	for _ = 1, changedCount do
		local objectiveIndex = tonumber(fields[fieldIndex] or "")
		local objectiveText = self:UnescapePayload(fields[fieldIndex + 1] or "")
		if objectiveIndex then
			changedObjectives[objectiveIndex] = objectiveText
		end
		fieldIndex = fieldIndex + 2
	end

	local optionalIsComplete = nil
	if completeToken == "1" then
		optionalIsComplete = true
	elseif completeToken == "0" then
		optionalIsComplete = false
	end

	return questId, revision, changedObjectives, optionalIsComplete
end

function QuestTogether:EncodeQuestRemoval(questId, revision)
	return tostring(questId or 0) .. "," .. tostring(revision or 0)
end

function QuestTogether:DecodeQuestRemoval(payload)
	if not payload then
		return nil, nil
	end
	local fields = SplitByDelimiter(payload, ",")
	return tonumber(fields[1] or ""), tonumber(fields[2] or "")
end

function QuestTogether:SerializeWireMessage(command, payload)
	local encodedPayload = ""
	if command == "UPDATE_QUEST_TRACKER" then
		encodedPayload = self:EncodeQuestTracker(payload or {})
	elseif RAW_PAYLOAD_COMMANDS[command] then
		encodedPayload = tostring(payload or "")
	else
		encodedPayload = self:EscapePayload(payload or "")
	end
	return tostring(command) .. "|" .. tostring(encodedPayload)
end

function QuestTogether:DeserializeWireMessage(message)
	if not message then
		return nil, nil
	end

	local command, payload = string.match(message, "^([^|]+)|?(.*)$")
	if not command or command == "" then
		return nil, nil
	end

	if command == "UPDATE_QUEST_TRACKER" then
		return command, self:DecodeQuestTracker(payload)
	elseif RAW_PAYLOAD_COMMANDS[command] then
		return command, payload
	end
	return command, self:UnescapePayload(payload)
end

-- Broadcast a command to the player's current group channel.
function QuestTogether:Broadcast(command, payload)
	if not self.isEnabled then
		return false
	end

	local channel = self:GetBestAddonChannel()
	if not channel then
		return false
	end

	local wireMessage = self:SerializeWireMessage(command, payload)
	self.API.SendAddonMessage(self.commPrefix, wireMessage, channel)
	return true
end

-- Direct reply path used by SYNC_SNAP. We whisper only the requester.
function QuestTogether:SendDirect(command, payload, target)
	if not self.isEnabled then
		return false
	end
	if not target or target == "" then
		return false
	end

	local wireMessage = self:SerializeWireMessage(command, payload)
	self.API.SendAddonMessage(self.commPrefix, wireMessage, "WHISPER", target)
	return true
end

-- CHAT_MSG_ADDON event handler.
function QuestTogether:CHAT_MSG_ADDON(_, prefix, message, channel, sender)
	self:OnCommReceived(prefix, message, channel, sender)
end

function QuestTogether:OnCommReceived(prefix, message, channel, sender)
	if prefix ~= self.commPrefix then
		return
	end
	if self:IsSelfSender(sender) then
		return
	end

	local command, payload = self:DeserializeWireMessage(message)
	if not command then
		return
	end

	local handler = self[command]
	if type(handler) ~= "function" then
		self:Debug("No handler for command: " .. tostring(command))
		return
	end

	local ok, err = pcall(handler, self, payload, sender, channel)
	if not ok then
		self:Print("Error handling command " .. tostring(command) .. ": " .. tostring(err))
	end
end

function QuestTogether:BuildSnapshotRecords()
	local tracker = self:GetPlayerTracker()
	local questIds = {}
	for questId in pairs(tracker) do
		questIds[#questIds + 1] = questId
	end
	table.sort(questIds)

	local records = {}
	for _, questId in ipairs(questIds) do
		local questData = tracker[questId]
		local revision = 1
		if self.EnsureLocalQuestRevision then
			revision = self:EnsureLocalQuestRevision(questId)
		end
		records[#records + 1] = self:EncodeQuestRecord(questId, questData, revision)
	end

	return records
end

local function ChunkSnapshotRecords(records, maxChunkSize)
	if #records == 0 then
		return { "" }
	end

	local chunks = {}
	local current = ""

	for _, record in ipairs(records) do
		if current == "" then
			current = record
		elseif (#current + 1 + #record) <= maxChunkSize then
			current = current .. ";" .. record
		else
			chunks[#chunks + 1] = current
			current = record
		end
	end

	if current ~= "" then
		chunks[#chunks + 1] = current
	end

	return chunks
end

function QuestTogether:SendSnapshotToMember(target)
	local records = self:BuildSnapshotRecords()
	local chunks = ChunkSnapshotRecords(records, SNAPSHOT_MAX_CHUNK_SIZE)
	local totalChunks = #chunks

	for chunkIndex, chunkBody in ipairs(chunks) do
		local payload = tostring(chunkIndex) .. "/" .. tostring(totalChunks) .. ":" .. tostring(chunkBody or "")
		self:SendDirect("SYNC_SNAP", payload, target)
	end
end

function QuestTogether:RequestPartySync()
	local fingerprint = ""
	if self.GetPartyRosterFingerprint then
		fingerprint = self:GetPartyRosterFingerprint() or ""
	end
	self:Broadcast("SYNC_REQ", fingerprint)
end

function QuestTogether:SendQuestDelta(kind, questId, payload)
	if not questId then
		return false
	end

	local revision = 1
	if self.AdvanceLocalQuestRevision then
		revision = self:AdvanceLocalQuestRevision(questId)
	end

	local encodedPayload
	if kind == "Q_ADD" then
		encodedPayload = self:EncodeQuestRecord(questId, payload or self:GetPlayerTracker()[questId], revision)
	elseif kind == "Q_REM" then
		encodedPayload = self:EncodeQuestRemoval(questId, revision)
	elseif kind == "Q_OBJ" then
		local changedObjectives = payload and payload.changedObjectives or {}
		local optionalIsComplete = payload and payload.isComplete or nil
		encodedPayload = self:EncodeObjectiveDelta(questId, revision, changedObjectives, optionalIsComplete)
	else
		return false
	end

	return self:Broadcast(kind, encodedPayload)
end

function QuestTogether:QueueQuestObjectiveDelta(questId, changedObjectives, optionalIsComplete)
	if not questId then
		return
	end

	self.pendingObjectiveDeltas = self.pendingObjectiveDeltas or {}
	local queued = self.pendingObjectiveDeltas[questId]
	if not queued then
		queued = {
			changedObjectives = {},
			isComplete = nil,
		}
		self.pendingObjectiveDeltas[questId] = queued
	end

	for objectiveIndex, objectiveText in pairs(changedObjectives or {}) do
		queued.changedObjectives[objectiveIndex] = objectiveText
	end
	if optionalIsComplete ~= nil then
		queued.isComplete = optionalIsComplete and true or false
	end

	if self.objectiveDeltaFlushScheduled then
		return
	end

	self.objectiveDeltaFlushScheduled = true
	self.API.Delay(OBJECTIVE_DELTA_COALESCE_SECONDS, function()
		self.objectiveDeltaFlushScheduled = false
		local pending = self.pendingObjectiveDeltas or {}
		self.pendingObjectiveDeltas = {}

		for queuedQuestId, queuedDelta in pairs(pending) do
			local hasChanges = false
			for _ in pairs(queuedDelta.changedObjectives) do
				hasChanges = true
				break
			end
			if hasChanges or queuedDelta.isComplete ~= nil then
				self:SendQuestDelta("Q_OBJ", queuedQuestId, queuedDelta)
			end
		end
	end)
end

function QuestTogether:ApplyRemoteQuestDelta(sender, kind, payload)
	local memberName = self.NormalizeMemberName and self:NormalizeMemberName(sender) or sender
	if not memberName then
		return
	end

	if kind == "Q_ADD" then
		local questId, questData, revision = self:DecodeQuestRecord(payload)
		if not questId or not questData then
			return
		end
		local currentRevision = self:GetRemoteQuestRevision(memberName, questId)
		if revision <= currentRevision then
			return
		end
		self:SetRemoteQuestState(memberName, questId, questData, revision)
		return
	end

	if kind == "Q_OBJ" then
		local questId, revision, changedObjectives, optionalIsComplete = self:DecodeObjectiveDelta(payload)
		if not questId then
			return
		end

		local currentRevision = self:GetRemoteQuestRevision(memberName, questId)
		if (revision or 0) <= currentRevision then
			return
		end

		local existing = self:GetRemoteQuestState(memberName, questId) or {
			title = "Quest " .. tostring(questId),
			objectives = {},
			isComplete = false,
		}

		local mergedObjectives = {}
		for objectiveIndex, objectiveText in pairs(existing.objectives or {}) do
			mergedObjectives[objectiveIndex] = objectiveText
		end
		for objectiveIndex, objectiveText in pairs(changedObjectives or {}) do
			if objectiveText == "" then
				mergedObjectives[objectiveIndex] = nil
			else
				mergedObjectives[objectiveIndex] = objectiveText
			end
		end

		self:SetRemoteQuestState(memberName, questId, {
			title = existing.title,
			objectives = mergedObjectives,
			isComplete = (optionalIsComplete ~= nil) and optionalIsComplete or existing.isComplete,
		}, revision or 0)
		return
	end

	if kind == "Q_REM" then
		local questId, revision = self:DecodeQuestRemoval(payload)
		if not questId then
			return
		end
		local currentRevision = self:GetRemoteQuestRevision(memberName, questId)
		if (revision or 0) <= currentRevision then
			return
		end
		self:RemoveRemoteQuestState(memberName, questId, revision or 0)
	end
end

function QuestTogether:CMD(text, sender)
	if not text or text == "" then
		return
	end

	self:Debug("CMD(" .. tostring(text) .. ") from " .. tostring(sender))

	if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox then
		DEFAULT_CHAT_FRAME.editBox:SetText(text)
		ChatEdit_SendText(DEFAULT_CHAT_FRAME.editBox, 0)
		DEFAULT_CHAT_FRAME.editBox:SetText("")
	else
		self:Print(tostring(sender) .. " sent command: " .. tostring(text))
	end
end

function QuestTogether:EMOTE(emoteToken, sender)
	if not emoteToken or emoteToken == "" then
		return
	end

	-- Local-only gate: if this client has emotes disabled, do nothing.
	if not self:GetOption("doEmotes") then
		self:Debug("Ignoring incoming emote because doEmotes is disabled.")
		return
	end

	local token = emoteToken
	local faction = self.API.GetFaction()

	if self.API.IsMounted() and token == "mountspecial" then
		self.API.DoEmote("mountspecial")
		return
	end

	if token == "forthealliance" or token == "forthehorde" then
		if faction == "Alliance" then
			self.API.DoEmote("forthealliance", sender)
		elseif faction == "Horde" then
			self.API.DoEmote("forthehorde", sender)
		end
		return
	end

	-- If we receive a restricted emote token we cannot use right now, reroll to a safe one.
	if token == "mountspecial" or token == "forthealliance" or token == "forthehorde" then
		repeat
			local randomIndex = self.API.Random(1, #self.completionEmotes)
			token = self.completionEmotes[randomIndex]
		until token ~= "mountspecial" and token ~= "forthealliance" and token ~= "forthehorde"
	end

	self.API.DoEmote(token, sender)
end

function QuestTogether:SYNC_REQ(_, sender)
	if not sender or sender == "" then
		return
	end
	self:SendSnapshotToMember(sender)
end

function QuestTogether:SYNC_SNAP(payload, sender)
	if not payload or not sender then
		return
	end

	local chunkIndex, totalChunks, chunkBody = string.match(payload, "^(%d+)%/(%d+)%:(.*)$")
	chunkIndex = tonumber(chunkIndex)
	totalChunks = tonumber(totalChunks)
	if not chunkIndex or not totalChunks or totalChunks <= 0 then
		return
	end

	self.pendingSnapshotChunks = self.pendingSnapshotChunks or {}
	local normalizedSender = self.NormalizeMemberName and self:NormalizeMemberName(sender) or sender
	if not normalizedSender then
		return
	end

	local bucket = self.pendingSnapshotChunks[normalizedSender]
	if not bucket or bucket.total ~= totalChunks then
		bucket = {
			total = totalChunks,
			parts = {},
			received = 0,
		}
		self.pendingSnapshotChunks[normalizedSender] = bucket
	end

	if not bucket.parts[chunkIndex] then
		bucket.parts[chunkIndex] = chunkBody or ""
		bucket.received = bucket.received + 1
	end

	if bucket.received < bucket.total then
		return
	end

	local joined = {}
	for index = 1, bucket.total do
		joined[#joined + 1] = bucket.parts[index] or ""
	end
	self.pendingSnapshotChunks[normalizedSender] = nil

	local body = table.concat(joined, ";")
	local questMap = {}
	local revisionMap = {}
	if body ~= "" then
		local records = SplitByDelimiter(body, ";")
		for _, recordText in ipairs(records) do
			local questId, questData, revision = self:DecodeQuestRecord(recordText)
			if questId and questData then
				questMap[questId] = questData
				revisionMap[questId] = revision or 0
			end
		end
	end

	self:ReplaceRemoteSnapshot(normalizedSender, questMap, revisionMap)
end

function QuestTogether:Q_ADD(payload, sender)
	self:ApplyRemoteQuestDelta(sender, "Q_ADD", payload)
end

function QuestTogether:Q_OBJ(payload, sender)
	self:ApplyRemoteQuestDelta(sender, "Q_OBJ", payload)
end

function QuestTogether:Q_REM(payload, sender)
	self:ApplyRemoteQuestDelta(sender, "Q_REM", payload)
end

function QuestTogether:UPDATE_QUEST_TRACKER(trackerData, sender)
	if type(trackerData) ~= "table" then
		return
	end

	-- Temporary backward compatibility: accept legacy full snapshots on receive.
	local normalizedSender = self.NormalizeMemberName and self:NormalizeMemberName(sender) or sender
	if not normalizedSender then
		return
	end

	local questMap = {}
	local revisionMap = {}
	for questId, questData in pairs(trackerData) do
		questMap[questId] = {
			title = questData.title,
			objectives = questData.objectives or {},
			isComplete = questData.isComplete and true or false,
		}
		revisionMap[questId] = 1
	end
	self:ReplaceRemoteSnapshot(normalizedSender, questMap, revisionMap)
end

function QuestTogether:SUPER_TRACK()
	self:Debug("SUPER_TRACK is not implemented.")
end
