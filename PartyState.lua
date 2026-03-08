--[[
QuestTogether Party + Remote Quest State

This file owns:
1) Group roster state (party + instance party scope, not raid roster expansion).
2) Remote quest cache by member + questID.
3) Per-quest local/remote revision numbers used by delta sync ordering.

Keeping this isolated makes comms and event handlers easier to reason about.
]]

local QuestTogether = _G.QuestTogether

QuestTogether.partyMembers = QuestTogether.partyMembers or {}
QuestTogether.partyMemberOrder = QuestTogether.partyMemberOrder or {}
QuestTogether.partyRosterFingerprint = QuestTogether.partyRosterFingerprint or ""
QuestTogether.remoteQuestState = QuestTogether.remoteQuestState or {}
QuestTogether.remoteQuestRevision = QuestTogether.remoteQuestRevision or {}
QuestTogether.localQuestRevision = QuestTogether.localQuestRevision or {}
QuestTogether.debugPartyTemplates = QuestTogether.debugPartyTemplates or {
	{ name = "Aly", classFile = "MAGE", role = "adaptive" },
	{ name = "Bram", classFile = "WARRIOR", role = "not_on_quest" },
	{ name = "Cyra", classFile = "PRIEST", role = "unknown" },
	{ name = "Dane", classFile = "DRUID", role = "stale" },
}

local function NormalizeRealmName(addon, realmName)
	if not realmName or realmName == "" then
		realmName = addon.API.GetRealmName() or ""
	end
	return (realmName:gsub("%s+", ""))
end

local function SortNames(nameList)
	table.sort(nameList, function(left, right)
		return tostring(left) < tostring(right)
	end)
end

function QuestTogether:NormalizeMemberName(name)
	if not name or name == "" then
		return nil
	end

	local baseName, realmName = string.match(name, "^([^%-]+)%-(.+)$")
	if not baseName then
		baseName = name
		realmName = NormalizeRealmName(self, nil)
	else
		realmName = NormalizeRealmName(self, realmName)
	end

	return tostring(baseName) .. "-" .. tostring(realmName)
end

function QuestTogether:GetPlayerFullName()
	local name, realm = self.API.UnitFullName("player")
	if not name then
		return nil
	end
	return tostring(name) .. "-" .. tostring(NormalizeRealmName(self, realm))
end

function QuestTogether:InitializePartyState()
	self.partyMembers = self.partyMembers or {}
	self.partyMemberOrder = self.partyMemberOrder or {}
	self.partyRosterFingerprint = self.partyRosterFingerprint or ""
	self.remoteQuestState = self.remoteQuestState or {}
	self.remoteQuestRevision = self.remoteQuestRevision or {}
	self.localQuestRevision = self.localQuestRevision or {}
	self.debugPartyTemplates = self.debugPartyTemplates or QuestTogether.debugPartyTemplates
end

function QuestTogether:GetMemberMeta(memberName)
	if not self.partyMembers[memberName] then
		self.partyMembers[memberName] = {
			fullName = memberName,
			displayName = Ambiguate(memberName, "short"),
			classFile = nil,
			hasData = false,
			lastSeen = 0,
		}
	end
	return self.partyMembers[memberName]
end

function QuestTogether:IsDebugPartySimulationEnabled()
	-- Requested behavior: only fabricate party members when truly solo.
	if not self:GetOption("debugMode") then
		return false
	end

	for partyIndex = 1, 4 do
		if self.API.UnitExists("party" .. tostring(partyIndex)) then
			return false
		end
	end

	return self.API.UnitExists("player") and true or false
end

function QuestTogether:SetMemberHasData(memberName, hasData)
	local meta = self:GetMemberMeta(memberName)
	meta.hasData = hasData and true or false
	meta.lastSeen = self.API.GetTime()
end

function QuestTogether:UpdateMemberClass(memberName, classFile)
	if not classFile or classFile == "" then
		return
	end
	local meta = self:GetMemberMeta(memberName)
	meta.classFile = classFile
end

local function AddUnitToRoster(addon, unitToken, membersByName, orderedNames)
	if not addon.API.UnitExists(unitToken) then
		return
	end

	local fullName
	local unitName, unitRealm = addon.API.UnitFullName(unitToken)
	if unitName then
		fullName = tostring(unitName) .. "-" .. tostring(NormalizeRealmName(addon, unitRealm))
	else
		fullName = addon:NormalizeMemberName(addon.API.UnitName(unitToken))
	end

	if not fullName or membersByName[fullName] then
		return
	end

	local _, classFile = addon.API.UnitClass(unitToken)
	membersByName[fullName] = {
		fullName = fullName,
		displayName = Ambiguate(fullName, "short"),
		classFile = classFile,
		hasData = false,
		lastSeen = 0,
	}
	table.insert(orderedNames, fullName)
end

local function AddDebugMemberToRoster(addon, template, membersByName, orderedNames)
	local fullName = addon:NormalizeMemberName(template.name)
	if not fullName or membersByName[fullName] then
		return
	end

	membersByName[fullName] = {
		fullName = fullName,
		displayName = Ambiguate(fullName, "short"),
		classFile = template.classFile,
		hasData = true,
		lastSeen = 0,
		isDebugSimulated = true,
		debugRole = template.role,
	}
	table.insert(orderedNames, fullName)
end

function QuestTogether:RefreshPartyRoster()
	local previousMembers = self.partyMembers or {}
	local membersByName = {}
	local orderedNames = {}

	-- Scope intentionally limited to player + party slots.
	AddUnitToRoster(self, "player", membersByName, orderedNames)
	for partyIndex = 1, 4 do
		AddUnitToRoster(self, "party" .. tostring(partyIndex), membersByName, orderedNames)
	end
	local realMemberCount = #orderedNames

	-- Debug mock party members are only injected while solo.
	if self:GetOption("debugMode") and realMemberCount <= 1 and #orderedNames < 5 then
		for _, template in ipairs(self.debugPartyTemplates or {}) do
			if #orderedNames >= 5 then
				break
			end
			AddDebugMemberToRoster(self, template, membersByName, orderedNames)
		end
	end

	-- Preserve metadata for continuing members.
	for memberName, meta in pairs(membersByName) do
		local previous = previousMembers[memberName]
		if previous then
			meta.classFile = meta.classFile or previous.classFile
			meta.hasData = previous.hasData or false
			meta.lastSeen = previous.lastSeen or 0
			meta.isDebugSimulated = meta.isDebugSimulated or previous.isDebugSimulated
			meta.debugRole = meta.debugRole or previous.debugRole
		end
	end

	SortNames(orderedNames)
	self.partyMembers = membersByName
	self.partyMemberOrder = orderedNames
	self.partyRosterFingerprint = table.concat(orderedNames, "|")

	-- Purge departed members from remote caches.
	for memberName in pairs(self.remoteQuestState) do
		if not self.partyMembers[memberName] then
			self.remoteQuestState[memberName] = nil
			self.remoteQuestRevision[memberName] = nil
			self.db.global.questTrackers[memberName] = nil
		end
	end

	self:UpdateDebugPartySimulationData()
end

function QuestTogether:GetOrderedPartyMembers()
	return self.partyMemberOrder or {}
end

function QuestTogether:GetPartyRosterFingerprint()
	return self.partyRosterFingerprint or ""
end

function QuestTogether:GetRemoteQuestRevision(memberName, questId)
	local revisions = self.remoteQuestRevision and self.remoteQuestRevision[memberName]
	if not revisions then
		return 0
	end
	return revisions[questId] or 0
end

function QuestTogether:SetRemoteQuestRevision(memberName, questId, revision)
	self.remoteQuestRevision = self.remoteQuestRevision or {}
	if not self.remoteQuestRevision[memberName] then
		self.remoteQuestRevision[memberName] = {}
	end
	self.remoteQuestRevision[memberName][questId] = revision or 0
end

function QuestTogether:GetRemoteQuestState(memberName, questId)
	local memberQuests = self.remoteQuestState and self.remoteQuestState[memberName]
	if not memberQuests then
		return nil
	end
	return memberQuests[questId]
end

function QuestTogether:SetRemoteQuestState(memberName, questId, questData, revision)
	if not memberName or not questId then
		return
	end

	self.remoteQuestState = self.remoteQuestState or {}
	if not self.remoteQuestState[memberName] then
		self.remoteQuestState[memberName] = {}
	end

	local state = {
		title = questData.title,
		objectives = {},
		isComplete = questData.isComplete and true or false,
		revision = revision or 0,
		lastSeen = self.API.GetTime(),
	}

	for objectiveIndex, objectiveText in pairs(questData.objectives or {}) do
		state.objectives[objectiveIndex] = objectiveText
	end

	self.remoteQuestState[memberName][questId] = state
	self:SetRemoteQuestRevision(memberName, questId, revision or 0)
	self:SetMemberHasData(memberName, true)

	-- Maintain legacy cache shape for older code paths.
	self.db.global.questTrackers[memberName] = self.remoteQuestState[memberName]
end

function QuestTogether:RemoveRemoteQuestState(memberName, questId, revision)
	if not memberName or not questId then
		return
	end

	if self.remoteQuestState[memberName] then
		self.remoteQuestState[memberName][questId] = nil
	end
	self:SetRemoteQuestRevision(memberName, questId, revision or 0)
	self:SetMemberHasData(memberName, true)

	if self.remoteQuestState[memberName] then
		self.db.global.questTrackers[memberName] = self.remoteQuestState[memberName]
	end
end

function QuestTogether:ReplaceRemoteSnapshot(memberName, questMap, revisionMap)
	if not memberName then
		return
	end

	self.remoteQuestState[memberName] = {}
	self.remoteQuestRevision[memberName] = {}

	for questId, questData in pairs(questMap or {}) do
		local revision = (revisionMap and revisionMap[questId]) or 0
		self:SetRemoteQuestState(memberName, questId, questData, revision)
	end

	self:SetMemberHasData(memberName, true)
	self.db.global.questTrackers[memberName] = self.remoteQuestState[memberName]
end

function QuestTogether:GetLocalQuestRevision(questId)
	return (self.localQuestRevision and self.localQuestRevision[questId]) or 0
end

function QuestTogether:EnsureLocalQuestRevision(questId)
	if not questId then
		return 0
	end

	self.localQuestRevision = self.localQuestRevision or {}
	if not self.localQuestRevision[questId] or self.localQuestRevision[questId] <= 0 then
		self.localQuestRevision[questId] = 1
	end
	return self.localQuestRevision[questId]
end

function QuestTogether:AdvanceLocalQuestRevision(questId)
	self.localQuestRevision = self.localQuestRevision or {}
	local current = self.localQuestRevision[questId] or 0
	current = current + 1
	self.localQuestRevision[questId] = current
	return current
end

function QuestTogether:RebuildLocalQuestRevisionIndex()
	self.localQuestRevision = self.localQuestRevision or {}
	local rebuilt = {}

	for questId in pairs(self:GetPlayerTracker()) do
		local current = self.localQuestRevision[questId]
		if not current or current <= 0 then
			rebuilt[questId] = 1
		else
			rebuilt[questId] = current
		end
	end

	self.localQuestRevision = rebuilt
end

function QuestTogether:UpdateDebugPartySimulationData()
	if not self:IsDebugPartySimulationEnabled() then
		return
	end

	local tracker = self:GetPlayerTracker()
	local now = self.API.GetTime()

	for memberName, meta in pairs(self.partyMembers or {}) do
		if meta.isDebugSimulated then
			local role = meta.debugRole
			self.remoteQuestState[memberName] = {}
			self.remoteQuestRevision[memberName] = {}

			if role == "unknown" then
				meta.hasData = false
				meta.lastSeen = now
				self.db.global.questTrackers[memberName] = self.remoteQuestState[memberName]
			elseif role == "not_on_quest" then
				meta.hasData = true
				meta.lastSeen = now
				self.db.global.questTrackers[memberName] = self.remoteQuestState[memberName]
			else
				meta.hasData = true
				meta.lastSeen = now

				for questId, localQuest in pairs(tracker) do
					local targetComplete = false
					if role == "adaptive" then
						targetComplete = not (localQuest.isComplete and true or false)
					elseif role == "stale" then
						targetComplete = false
					end

					local objectives = {}
					if role == "adaptive" and targetComplete then
						objectives[1] = "Debug teammate: ready to turn in"
					elseif role == "stale" then
						objectives[1] = "Debug teammate: stale objective data"
					else
						objectives[1] = (localQuest.objectives and localQuest.objectives[1])
							or "Debug teammate: objective progress"
					end

					self:SetRemoteQuestState(memberName, questId, {
						title = localQuest.title,
						objectives = objectives,
						isComplete = targetComplete,
					}, 1)

					if role == "stale" then
						local staleState = self.remoteQuestState[memberName][questId]
						if staleState then
							staleState.lastSeen = now - 600
						end
					end
				end
			end
		end
	end
end
