--[[
QuestTogether Group Roster State

This file now owns only lightweight group identity data:
1) Normalized player/member names.
2) Current party/raid roster membership.
3) Class metadata for grouped players.
]]

local QuestTogether = _G.QuestTogether

QuestTogether.partyMembers = QuestTogether.partyMembers or {}
QuestTogether.partyMemberOrder = QuestTogether.partyMemberOrder or {}
QuestTogether.partyRosterFingerprint = QuestTogether.partyRosterFingerprint or ""

local function NormalizeRealmName(addon, realmName)
	if not realmName or realmName == "" then
		realmName = addon.API.GetRealmName() or ""
	end
	if addon and addon.SafeStripWhitespace then
		return addon:SafeStripWhitespace(realmName, "")
	end
	local okText, textValue = pcall(tostring, realmName)
	if not okText then
		return ""
	end
	local okStrip, stripped = pcall(string.gsub, textValue, "%s+", "")
	if not okStrip then
		return ""
	end
	return stripped
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

	local normalized = tostring(baseName) .. "-" .. tostring(realmName)
	return normalized
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
	self:Debug("Initialized party state", "group")
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
		displayName = addon:GetShortDisplayName(fullName),
		classFile = classFile,
	}
	orderedNames[#orderedNames + 1] = fullName
end

function QuestTogether:RefreshPartyRoster()
	local membersByName = {}
	local orderedNames = {}

	AddUnitToRoster(self, "player", membersByName, orderedNames)

	if self.API.IsInRaid() then
		for raidIndex = 1, 40 do
			AddUnitToRoster(self, "raid" .. tostring(raidIndex), membersByName, orderedNames)
		end
	else
		for partyIndex = 1, 4 do
			AddUnitToRoster(self, "party" .. tostring(partyIndex), membersByName, orderedNames)
		end
	end

	SortNames(orderedNames)
	self.partyMembers = membersByName
	self.partyMemberOrder = orderedNames
	self.partyRosterFingerprint = table.concat(orderedNames, "|")
	self:DebugState("group", "partyMemberOrder", orderedNames)
	self:Debugf("group", "Refreshed party roster fingerprint=%s", tostring(self.partyRosterFingerprint))
end

function QuestTogether:GetPartyRosterFingerprint()
	return self.partyRosterFingerprint or ""
end

function QuestTogether:IsGroupedSender(senderName)
	local normalizedName = self:NormalizeMemberName(senderName)
	if not normalizedName then
		return false
	end
	return self.partyMembers and self.partyMembers[normalizedName] ~= nil
end

function QuestTogether:GetGroupedSenderClassFile(senderName)
	local normalizedName = self:NormalizeMemberName(senderName)
	if not normalizedName then
		return nil
	end

	local member = self.partyMembers and self.partyMembers[normalizedName]
	return member and member.classFile or nil
end
