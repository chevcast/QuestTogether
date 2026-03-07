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
	local originalIsEnabled = QuestTogether.isEnabled

	local ok, err = pcall(testFn)

	QuestTogether.db.profile = originalProfile
	QuestTogether.db.global = originalGlobal
	QuestTogether.API = originalAPI
	QuestTogether.Print = originalPrint
	QuestTogether.Broadcast = originalBroadcast
	QuestTogether.isEnabled = originalIsEnabled

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
