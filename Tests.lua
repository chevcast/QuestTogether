--[[
QuestTogether In-Game Test Runner

These are "unit-style" tests that run inside the WoW client.
Why in-game:
- The addon depends heavily on WoW runtime APIs.
- Running in pure Lua outside the game would require a large shim layer.

How to run:
- /qt test
- Press "Run In-Game Tests" in the options window

Notes:
- Tests temporarily patch addon methods/wrappers, then restore state after each case.
- Results are printed to chat.
]]

local QuestTogether = _G.QuestTogether

QuestTogether.tests = QuestTogether.tests or {}

function QuestTogether:RegisterTest(name, fn)
	self.tests[#self.tests + 1] = {
		name = name,
		fn = fn,
	}
end

local function AssertTrue(value, message)
	if not value then
		error(message or "Expected true but got false/nil")
	end
end

local function AssertFalse(value, message)
	if value then
		error(message or "Expected false but got true")
	end
end

local function AssertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "Values differ") .. " (expected=" .. tostring(expected) .. ", actual=" .. tostring(actual) .. ")")
	end
end

local function DeepEquals(left, right)
	if type(left) ~= type(right) then
		return false
	end
	if type(left) ~= "table" then
		return left == right
	end

	for key, value in pairs(left) do
		if not DeepEquals(value, right[key]) then
			return false
		end
	end
	for key in pairs(right) do
		if left[key] == nil then
			return false
		end
	end
	return true
end

local function CreateApiWithOverrides(overrides)
	local merged = {}
	for key, value in pairs(QuestTogether.API) do
		merged[key] = value
	end
	for key, value in pairs(overrides or {}) do
		merged[key] = value
	end
	return merged
end

local function WithIsolatedState(testFn)
	if not QuestTogether.db then
		QuestTogether:OnInitialize()
	end

	local originalProfile = QuestTogether:DeepCopy(QuestTogether.db.profile)
	local originalGlobal = QuestTogether:DeepCopy(QuestTogether.db.global)
	local originalAPI = QuestTogether.API
	local originalPrint = QuestTogether.Print
	local originalBroadcast = QuestTogether.Broadcast
	local originalSendQuestDelta = QuestTogether.SendQuestDelta
	local originalSendSnapshotToMember = QuestTogether.SendSnapshotToMember
	local originalPendingObjectiveDeltas = QuestTogether.pendingObjectiveDeltas
	local originalObjectiveDeltaFlushScheduled = QuestTogether.objectiveDeltaFlushScheduled
	local originalPendingSnapshotChunks = QuestTogether.pendingSnapshotChunks
	local originalPartyMembers = QuestTogether.partyMembers
	local originalPartyMemberOrder = QuestTogether.partyMemberOrder
	local originalPartyRosterFingerprint = QuestTogether.partyRosterFingerprint
	local originalRemoteQuestState = QuestTogether.remoteQuestState
	local originalRemoteQuestRevision = QuestTogether.remoteQuestRevision
	local originalLocalQuestRevision = QuestTogether.localQuestRevision
	local originalDebugPartyTemplates = QuestTogether.debugPartyTemplates
	local originalIsEnabled = QuestTogether.isEnabled

	-- Keep tests deterministic regardless of the player's current debugMode setting.
	QuestTogether.db.profile.debugMode = false

	local ok, err = pcall(testFn)

	QuestTogether.db.profile = originalProfile
	QuestTogether.db.global = originalGlobal
	QuestTogether.API = originalAPI
	QuestTogether.Print = originalPrint
	QuestTogether.Broadcast = originalBroadcast
	QuestTogether.SendQuestDelta = originalSendQuestDelta
	QuestTogether.SendSnapshotToMember = originalSendSnapshotToMember
	QuestTogether.pendingObjectiveDeltas = originalPendingObjectiveDeltas
	QuestTogether.objectiveDeltaFlushScheduled = originalObjectiveDeltaFlushScheduled
	QuestTogether.pendingSnapshotChunks = originalPendingSnapshotChunks
	QuestTogether.partyMembers = originalPartyMembers
	QuestTogether.partyMemberOrder = originalPartyMemberOrder
	QuestTogether.partyRosterFingerprint = originalPartyRosterFingerprint
	QuestTogether.remoteQuestState = originalRemoteQuestState
	QuestTogether.remoteQuestRevision = originalRemoteQuestRevision
	QuestTogether.localQuestRevision = originalLocalQuestRevision
	QuestTogether.debugPartyTemplates = originalDebugPartyTemplates
	QuestTogether.isEnabled = originalIsEnabled

	if not ok then
		error(err, 0)
	end
end

local function WithMockUnitFunctions(unitsByToken, fn)
	local oldUnitExists = UnitExists
	local oldUnitFullName = UnitFullName
	local oldUnitClass = UnitClass
	local oldUnitName = UnitName
	local oldGetRealmName = GetRealmName

	UnitExists = function(unitToken)
		return unitsByToken[unitToken] ~= nil
	end
	UnitFullName = function(unitToken)
		local unit = unitsByToken[unitToken]
		if not unit then
			return nil, nil
		end
		return unit.name, unit.realm
	end
	UnitClass = function(unitToken)
		local unit = unitsByToken[unitToken]
		if not unit then
			return nil, nil
		end
		return unit.classFile, unit.classFile
	end
	UnitName = function(unitToken)
		local unit = unitsByToken[unitToken]
		return unit and unit.name or nil
	end
	GetRealmName = function()
		return "Realm"
	end

	local ok, err = pcall(fn)

	UnitExists = oldUnitExists
	UnitFullName = oldUnitFullName
	UnitClass = oldUnitClass
	UnitName = oldUnitName
	GetRealmName = oldGetRealmName

	if not ok then
		error(err, 0)
	end
end

function QuestTogether:RunTests()
	if not self.isInitialized then
		self:OnInitialize()
	end

	local total = #self.tests
	local passed = 0
	local failed = 0

	self:Print("Running " .. tostring(total) .. " in-game tests...")

	for _, testCase in ipairs(self.tests) do
		local ok, err = pcall(function()
			WithIsolatedState(testCase.fn)
		end)

		if ok then
			passed = passed + 1
			self:Print("[PASS] " .. testCase.name)
		else
			failed = failed + 1
			self:Print("[FAIL] " .. testCase.name .. " -> " .. tostring(err))
		end
	end

	self:Print("Test summary: " .. tostring(passed) .. " passed, " .. tostring(failed) .. " failed.")
	return failed == 0
end

-- ---
-- Test cases
-- ---

QuestTogether:RegisterTest("default profile contains expected options", function()
	AssertTrue(QuestTogether.DEFAULTS.profile.doEmotes ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.announceAccepted ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.announceCompleted ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.announceRemoved ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.announceProgress ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.primaryChannel ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.fallbackChannel ~= nil)
end)

QuestTogether:RegisterTest("set/get option updates profile", function()
	AssertTrue(QuestTogether:SetOption("doEmotes", false))
	AssertFalse(QuestTogether:GetOption("doEmotes"))
	AssertTrue(QuestTogether:SetOption("doEmotes", true))
	AssertTrue(QuestTogether:GetOption("doEmotes"))
end)

QuestTogether:RegisterTest("announce uses primary channel when available", function()
	local sent = {}
	QuestTogether.db.profile.primaryChannel = "party"
	QuestTogether.db.profile.fallbackChannel = "console"

	QuestTogether.API = CreateApiWithOverrides({
		IsInParty = function()
			return true
		end,
		SendChatMessage = function(message, channel)
			sent[#sent + 1] = { message = message, channel = channel }
		end,
	})

	local success = QuestTogether:Announce("hello party")
	AssertTrue(success)
	AssertEquals(#sent, 1)
	AssertEquals(sent[1].channel, "PARTY")
	AssertEquals(sent[1].message, "hello party")
end)

QuestTogether:RegisterTest("announce falls back when primary unavailable", function()
	local sent = {}
	QuestTogether.db.profile.primaryChannel = "guild"
	QuestTogether.db.profile.fallbackChannel = "party"

	QuestTogether.API = CreateApiWithOverrides({
		IsInGuild = function()
			return false
		end,
		IsInParty = function()
			return true
		end,
		SendChatMessage = function(message, channel)
			sent[#sent + 1] = { message = message, channel = channel }
		end,
	})

	local success = QuestTogether:Announce("fallback test")
	AssertTrue(success)
	AssertEquals(#sent, 1)
	AssertEquals(sent[1].channel, "PARTY")
end)

QuestTogether:RegisterTest("announce fails gracefully when no channel available", function()
	local sent = {}
	QuestTogether.db.profile.primaryChannel = "guild"
	QuestTogether.db.profile.fallbackChannel = "raid"

	QuestTogether.API = CreateApiWithOverrides({
		IsInGuild = function()
			return false
		end,
		IsInRaid = function()
			return false
		end,
		SendChatMessage = function(message, channel)
			sent[#sent + 1] = { message = message, channel = channel }
		end,
	})

	local success = QuestTogether:Announce("no route")
	AssertFalse(success)
	AssertEquals(#sent, 0)
end)

QuestTogether:RegisterTest("fallback none suppresses announcements when primary unavailable", function()
	local sent = {}
	local printed = 0
	QuestTogether.db.profile.primaryChannel = "guild"
	QuestTogether.db.profile.fallbackChannel = "none"

	QuestTogether.API = CreateApiWithOverrides({
		IsInGuild = function()
			return false
		end,
		SendChatMessage = function(message, channel)
			sent[#sent + 1] = { message = message, channel = channel }
		end,
	})

	QuestTogether.Print = function()
		printed = printed + 1
	end

	local success = QuestTogether:Announce("quiet please")
	AssertFalse(success)
	AssertEquals(#sent, 0)
	AssertEquals(printed, 0)
end)

QuestTogether:RegisterTest("doEmotes=false blocks incoming emote playback", function()
	local emoteCount = 0
	QuestTogether.db.profile.doEmotes = false

	QuestTogether.API = CreateApiWithOverrides({
		DoEmote = function()
			emoteCount = emoteCount + 1
		end,
	})

	QuestTogether:EMOTE("cheer", "Friend")
	AssertEquals(emoteCount, 0)
end)

QuestTogether:RegisterTest("doEmotes=true allows incoming emote playback", function()
	local emoteCount = 0
	local lastToken
	QuestTogether.db.profile.doEmotes = true

	QuestTogether.API = CreateApiWithOverrides({
		DoEmote = function(token)
			emoteCount = emoteCount + 1
			lastToken = token
		end,
	})

	QuestTogether:EMOTE("cheer", "Friend")
	AssertEquals(emoteCount, 1)
	AssertEquals(lastToken, "cheer")
end)

QuestTogether:RegisterTest("quest tracker encode/decode roundtrip", function()
	local tracker = {
		[101] = {
			title = "Collect 10 Apples",
			objectives = {
				"Apples: 6/10",
				"Return to Farmer, then celebrate!",
			},
		},
		[202] = {
			title = "Defend the Town | Part 2",
			objectives = {
				"Wave 1/3",
			},
		},
	}

	local encoded = QuestTogether:EncodeQuestTracker(tracker)
	local decoded = QuestTogether:DecodeQuestTracker(encoded)

	AssertTrue(DeepEquals(decoded, tracker), "Decoded tracker did not match original")
end)

QuestTogether:RegisterTest("completion always broadcasts emote token", function()
	local broadcastCount = 0
	local localEmoteCount = 0

	QuestTogether.db.profile.doEmotes = false

	QuestTogether.API = CreateApiWithOverrides({
		Random = function()
			return 1
		end,
		DoEmote = function()
			localEmoteCount = localEmoteCount + 1
		end,
	})

	QuestTogether.Broadcast = function(_, command, payload)
		if command == "EMOTE" and payload and payload ~= "" then
			broadcastCount = broadcastCount + 1
		end
		return true
	end

	QuestTogether:HandleQuestCompleted("Any Quest")
	AssertEquals(broadcastCount, 1)
	AssertEquals(localEmoteCount, 0)
end)

QuestTogether:RegisterTest("slash set command updates doEmotes", function()
	QuestTogether:HandleSlashCommand("set doEmotes off")
	AssertFalse(QuestTogether:GetOption("doEmotes"))

	QuestTogether:HandleSlashCommand("set doEmotes on")
	AssertTrue(QuestTogether:GetOption("doEmotes"))
end)

QuestTogether:RegisterTest("slash fallback none is accepted", function()
	QuestTogether:HandleSlashCommand("channel fallback none")
	AssertEquals(QuestTogether:GetOption("fallbackChannel"), "none")
end)

QuestTogether:RegisterTest("slash primary none is rejected", function()
	local before = QuestTogether:GetOption("primaryChannel")
	QuestTogether:HandleSlashCommand("channel primary none")
	AssertEquals(QuestTogether:GetOption("primaryChannel"), before)
end)

QuestTogether:RegisterTest("on-comm ignores self sender", function()
	local triggered = false
	local oldMethod = QuestTogether.IsSelfSender
	local oldCMD = QuestTogether.CMD
	QuestTogether.IsSelfSender = function()
		return true
	end

	QuestTogether.CMD = function()
		triggered = true
	end

	QuestTogether:OnCommReceived(QuestTogether.commPrefix, "CMD|anything", "PARTY", "Player-Realm")

	QuestTogether.IsSelfSender = oldMethod
	QuestTogether.CMD = oldCMD
	AssertFalse(triggered)
end)

QuestTogether:RegisterTest("quest record encode/decode keeps completion and revision", function()
	local record = QuestTogether:EncodeQuestRecord(777, {
		title = "Test Quest",
		objectives = { "One", "Two" },
		isComplete = true,
	}, 9)

	local questId, questData, revision = QuestTogether:DecodeQuestRecord(record)
	AssertEquals(questId, 777)
	AssertEquals(revision, 9)
	AssertEquals(questData.title, "Test Quest")
	AssertTrue(questData.isComplete)
	AssertEquals(questData.objectives[1], "One")
	AssertEquals(questData.objectives[2], "Two")
end)

QuestTogether:RegisterTest("objective delta encode/decode roundtrip", function()
	local payload = QuestTogether:EncodeObjectiveDelta(451, 12, {
		[1] = "Collect 3/10",
		[3] = "",
	}, false)

	local questId, revision, changedObjectives, isComplete = QuestTogether:DecodeObjectiveDelta(payload)
	AssertEquals(questId, 451)
	AssertEquals(revision, 12)
	AssertEquals(changedObjectives[1], "Collect 3/10")
	AssertEquals(changedObjectives[3], "")
	AssertFalse(isComplete)
end)

QuestTogether:RegisterTest("objective delta coalescing merges rapid updates", function()
	local delayedCallback
	local sent = {}

	QuestTogether.API = CreateApiWithOverrides({
		Delay = function(_, callback)
			delayedCallback = callback
		end,
	})

	QuestTogether.SendQuestDelta = function(_, kind, questId, payload)
		sent[#sent + 1] = {
			kind = kind,
			questId = questId,
			payload = payload,
		}
		return true
	end

	QuestTogether:QueueQuestObjectiveDelta(91, { [1] = "A 1/2" }, nil)
	QuestTogether:QueueQuestObjectiveDelta(91, { [1] = "A 2/2", [2] = "Bonus 1/1" }, true)

	AssertEquals(#sent, 0)
	AssertTrue(type(delayedCallback) == "function")
	delayedCallback()

	AssertEquals(#sent, 1)
	AssertEquals(sent[1].kind, "Q_OBJ")
	AssertEquals(sent[1].questId, 91)
	AssertEquals(sent[1].payload.changedObjectives[1], "A 2/2")
	AssertEquals(sent[1].payload.changedObjectives[2], "Bonus 1/1")
	AssertTrue(sent[1].payload.isComplete)
end)

QuestTogether:RegisterTest("request party sync emits SYNC_REQ only", function()
	local sent = {}
	QuestTogether.isEnabled = true

	QuestTogether.API = CreateApiWithOverrides({
		IsInParty = function()
			return true
		end,
		IsInInstanceGroup = function()
			return false
		end,
		SendAddonMessage = function(prefix, message, channel, target)
			sent[#sent + 1] = {
				prefix = prefix,
				message = message,
				channel = channel,
				target = target,
			}
		end,
	})

	QuestTogether:RequestPartySync()
	AssertEquals(#sent, 1)
	AssertTrue(string.find(sent[1].message, "^SYNC_REQ|") ~= nil)
	AssertEquals(sent[1].channel, "PARTY")
end)

QuestTogether:RegisterTest("sync request receives snapshot response", function()
	local snapshotsSent = 0
	QuestTogether.isEnabled = true

	QuestTogether.SendSnapshotToMember = function(_, target)
		if target == "Friend-Realm" then
			snapshotsSent = snapshotsSent + 1
		end
	end

	QuestTogether:SYNC_REQ("", "Friend-Realm")
	AssertEquals(snapshotsSent, 1)
end)

QuestTogether:RegisterTest("stale remote revisions are ignored", function()
	if QuestTogether.InitializePartyState then
		QuestTogether:InitializePartyState()
	end

	local sender = "Friend-Realm"
	local newer = QuestTogether:EncodeQuestRecord(303, {
		title = "New",
		objectives = { "step" },
		isComplete = false,
	}, 5)
	local older = QuestTogether:EncodeQuestRecord(303, {
		title = "Old",
		objectives = { "oldstep" },
		isComplete = true,
	}, 4)

	QuestTogether:ApplyRemoteQuestDelta(sender, "Q_ADD", newer)
	QuestTogether:ApplyRemoteQuestDelta(sender, "Q_ADD", older)

	local state = QuestTogether:GetRemoteQuestState(sender, 303)
	AssertEquals(state.title, "New")
	AssertFalse(state.isComplete)
	AssertEquals(QuestTogether:GetRemoteQuestRevision(sender, 303), 5)
end)

QuestTogether:RegisterTest("snapshot chunks reassemble into remote state", function()
	if QuestTogether.InitializePartyState then
		QuestTogether:InitializePartyState()
	end

	local sender = "Ally-Realm"
	local rec1 = QuestTogether:EncodeQuestRecord(801, {
		title = "One",
		objectives = { "A" },
		isComplete = false,
	}, 2)
	local rec2 = QuestTogether:EncodeQuestRecord(802, {
		title = "Two",
		objectives = { "B" },
		isComplete = true,
	}, 7)

	QuestTogether:SYNC_SNAP("1/2:" .. rec1, sender)
	QuestTogether:SYNC_SNAP("2/2:" .. rec2, sender)

	local one = QuestTogether:GetRemoteQuestState(sender, 801)
	local two = QuestTogether:GetRemoteQuestState(sender, 802)
	AssertEquals(one.title, "One")
	AssertFalse(one.isComplete)
	AssertEquals(two.title, "Two")
	AssertTrue(two.isComplete)
	AssertEquals(QuestTogether:GetRemoteQuestRevision(sender, 802), 7)
end)

QuestTogether:RegisterTest("debug mode fills mock roster to full party only when solo", function()
	if QuestTogether.InitializePartyState then
		QuestTogether:InitializePartyState()
	end

	QuestTogether.db.profile.debugMode = true

	WithMockUnitFunctions({
		player = { name = "Player", realm = "Realm", classFile = "PALADIN" },
	}, function()
		QuestTogether:RefreshPartyRoster()
	end)

	local ordered = QuestTogether:GetOrderedPartyMembers()
	AssertEquals(#ordered, 5)

	local debugCount = 0
	for _, memberName in ipairs(ordered) do
		local meta = QuestTogether:GetMemberMeta(memberName)
		if meta.isDebugSimulated then
			debugCount = debugCount + 1
		end
	end
	AssertEquals(debugCount, 4)
end)

QuestTogether:RegisterTest("debug mode does not inject mock members while grouped", function()
	if QuestTogether.InitializePartyState then
		QuestTogether:InitializePartyState()
	end

	QuestTogether.db.profile.debugMode = true

	WithMockUnitFunctions({
		player = { name = "Player", realm = "Realm", classFile = "PALADIN" },
		party1 = { name = "Friend", realm = "Realm", classFile = "MAGE" },
	}, function()
		QuestTogether:RefreshPartyRoster()
	end)

	local ordered = QuestTogether:GetOrderedPartyMembers()
	AssertEquals(#ordered, 2)

	for _, memberName in ipairs(ordered) do
		local meta = QuestTogether:GetMemberMeta(memberName)
		AssertFalse(meta.isDebugSimulated and true or false)
	end
end)

QuestTogether:RegisterTest("debug solo simulation creates remote quest mock data", function()
	if QuestTogether.InitializePartyState then
		QuestTogether:InitializePartyState()
	end

	QuestTogether.db.profile.debugMode = true
	local tracker = QuestTogether:GetPlayerTracker()
	tracker[9001] = {
		title = "Debug Quest",
		objectives = { "Collect 1/3" },
		isComplete = false,
	}

	WithMockUnitFunctions({
		player = { name = "Player", realm = "Realm", classFile = "PALADIN" },
	}, function()
		QuestTogether:RefreshPartyRoster()
	end)

	local foundRemoteQuest = false
	for memberName, memberQuests in pairs(QuestTogether.remoteQuestState or {}) do
		local meta = QuestTogether:GetMemberMeta(memberName)
		if meta.isDebugSimulated and memberQuests[9001] then
			foundRemoteQuest = true
			break
		end
	end

	AssertTrue(foundRemoteQuest, "Expected at least one simulated member quest state.")
end)
