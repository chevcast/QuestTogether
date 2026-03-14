--[[
QuestTogether In-Game Test Runner
]]

local QuestTogether = _G.QuestTogether

QuestTogether.tests = QuestTogether.tests or {}

function QuestTogether:RegisterTest(name, fn)
	self.tests[#self.tests + 1] = {
		name = name,
		fn = fn,
	}
end

local function BuildTestLogMessage(message)
	local body = tostring(message or "")
	body = body:gsub("^%[PASS%]", "|cff33ff99[PASS]|r")
	body = body:gsub("^%[FAIL%]", "|cffff3333[FAIL]|r")
	return "Debug: " .. body
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

local function WithPatchedMethod(targetTable, methodName, replacement, fn)
	local original = targetTable[methodName]
	targetTable[methodName] = replacement

	local ok, err = pcall(fn)

	targetTable[methodName] = original

	if not ok then
		error(err, 0)
	end
end

local function WithIsolatedState(testFn)
	if not QuestTogether.db then
		QuestTogether:OnInitialize()
	end

	local originalProfile = QuestTogether:DeepCopy(QuestTogether.db.profile)
	local originalGlobal = QuestTogether:DeepCopy(QuestTogether.db.global)
	local originalProfiles = QuestTogether:DeepCopy(QuestTogether.db.profiles or {})
	local originalProfileKeys = QuestTogether:DeepCopy(QuestTogether.db.profileKeys or {})
	local originalActiveProfileKey = QuestTogether.activeProfileKey
	local originalActiveCharacterKey = QuestTogether.activeCharacterKey
	local originalAPI = QuestTogether.API
	local originalPrint = QuestTogether.Print
	local originalPrintRaw = QuestTogether.PrintRaw
	local originalPrintChatLogRaw = QuestTogether.PrintChatLogRaw
	local originalPartyMembers = QuestTogether.partyMembers
	local originalPartyMemberOrder = QuestTogether.partyMemberOrder
	local originalPartyRosterFingerprint = QuestTogether.partyRosterFingerprint
	local originalIsEnabled = QuestTogether.isEnabled
	local originalProfileEnabled = QuestTogether.db.profile.enabled
	local originalWorldQuestAreaStateByQuestID = QuestTogether.worldQuestAreaStateByQuestID
	local originalBonusObjectiveAreaStateByQuestID = QuestTogether.bonusObjectiveAreaStateByQuestID
	local originalNameplateQuestStateByUnitToken = QuestTogether.nameplateQuestStateByUnitToken
	local originalNameplateQuestObjectiveCache = QuestTogether.nameplateQuestObjectiveCache
	local originalNameplateQuestTitleCache = QuestTogether.nameplateQuestTitleCache
	local originalNameplateHealthOverlayByUnitFrame = QuestTogether.nameplateHealthOverlayByUnitFrame
	local originalNameplateBubbleByUnitFrame = QuestTogether.nameplateBubbleByUnitFrame
	local originalNameplateRefreshPendingByUnitToken = QuestTogether.nameplateRefreshPendingByUnitToken
	local originalNameplateHealthTintRefreshPendingByUnitToken =
		QuestTogether.nameplateHealthTintRefreshPendingByUnitToken
	local originalNameplateHealthTintRetryCountByUnitToken = QuestTogether.nameplateHealthTintRetryCountByUnitToken
	local originalAnnouncementBubbleScreenHostFrame = QuestTogether.announcementBubbleScreenHostFrame
	local originalAnnouncementChannelLocalID = QuestTogether.announcementChannelLocalID
	local originalPendingPingRequests = QuestTogether.pendingPingRequests
	local originalPendingQuestCompareRequests = QuestTogether.pendingQuestCompareRequests
	local originalPendingQuestRemovals = QuestTogether.pendingQuestRemovals
	local originalIsLoggingOut = QuestTogether.isLoggingOut
	local originalQuestLogChatFrameID = QuestTogether.db.profile.questLogChatFrameID

	if QuestTogether.UnregisterRuntimeEvents then
		QuestTogether:UnregisterRuntimeEvents()
	end
	if QuestTogether.DisableNameplateAugmentation then
		QuestTogether:DisableNameplateAugmentation()
	end

	QuestTogether.db.profile = QuestTogether:DeepCopy(QuestTogether.DEFAULTS.profile)
	QuestTogether.db.global = QuestTogether:DeepCopy(QuestTogether.DEFAULTS.global)
	QuestTogether.db.profiles = {
		["MyPlayer-Realm"] = QuestTogether.db.profile,
	}
	QuestTogether.db.profileKeys = {
		["MyPlayer-Realm"] = "MyPlayer-Realm",
	}
	QuestTogether.activeCharacterKey = "MyPlayer-Realm"
	QuestTogether.activeProfileKey = "MyPlayer-Realm"
	QuestTogether.db.profile.debugMode = false
	QuestTogether.db.profile.enabled = false
	QuestTogether.isEnabled = false
	QuestTogether.partyMembers = {}
	QuestTogether.partyMemberOrder = {}
	QuestTogether.partyRosterFingerprint = ""
	QuestTogether.worldQuestAreaStateByQuestID = {}
	QuestTogether.bonusObjectiveAreaStateByQuestID = {}
	QuestTogether.nameplateQuestStateByUnitToken = {}
	QuestTogether.nameplateQuestObjectiveCache = {}
	QuestTogether.nameplateQuestTitleCache = {}
	QuestTogether.nameplateHealthOverlayByUnitFrame = setmetatable({}, { __mode = "k" })
	QuestTogether.nameplateBubbleByUnitFrame = setmetatable({}, { __mode = "k" })
	QuestTogether.nameplateRefreshPendingByUnitToken = {}
	QuestTogether.nameplateHealthTintRefreshPendingByUnitToken = {}
	QuestTogether.nameplateHealthTintRetryCountByUnitToken = {}
	QuestTogether.announcementBubbleScreenHostFrame = nil
	QuestTogether.announcementChannelLocalID = nil
	QuestTogether.pendingPingRequests = {}
	QuestTogether.pendingQuestCompareRequests = {}
	QuestTogether.pendingQuestRemovals = {}
	QuestTogether.isLoggingOut = false

	local ok, err = pcall(testFn)

	local createdQuestLogChatFrameID = QuestTogether.db
		and QuestTogether.db.profile
		and QuestTogether.db.profile.questLogChatFrameID
	if
		createdQuestLogChatFrameID
		and createdQuestLogChatFrameID ~= originalQuestLogChatFrameID
		and QuestTogether.CloseQuestLogChatFrame
	then
		pcall(QuestTogether.CloseQuestLogChatFrame, QuestTogether)
	end

	QuestTogether.db.global = originalGlobal
	QuestTogether.db.profiles = originalProfiles
	QuestTogether.db.profileKeys = originalProfileKeys
	QuestTogether.activeProfileKey = originalActiveProfileKey
	QuestTogether.activeCharacterKey = originalActiveCharacterKey
	if
		originalActiveProfileKey
		and QuestTogether.db.profiles
		and type(QuestTogether.db.profiles[originalActiveProfileKey]) == "table"
	then
		QuestTogether.db.profile = QuestTogether.db.profiles[originalActiveProfileKey]
	else
		QuestTogether.db.profile = originalProfile
	end
	QuestTogether.API = originalAPI
	QuestTogether.Print = originalPrint
	QuestTogether.PrintRaw = originalPrintRaw
	QuestTogether.PrintChatLogRaw = originalPrintChatLogRaw
	QuestTogether.partyMembers = originalPartyMembers
	QuestTogether.partyMemberOrder = originalPartyMemberOrder
	QuestTogether.partyRosterFingerprint = originalPartyRosterFingerprint
	if QuestTogether.db.profile then
		QuestTogether.db.profile.enabled = originalProfileEnabled
	end
	QuestTogether.isEnabled = originalIsEnabled
	QuestTogether.worldQuestAreaStateByQuestID = originalWorldQuestAreaStateByQuestID
	QuestTogether.bonusObjectiveAreaStateByQuestID = originalBonusObjectiveAreaStateByQuestID
	QuestTogether.nameplateQuestStateByUnitToken = originalNameplateQuestStateByUnitToken
	QuestTogether.nameplateQuestObjectiveCache = originalNameplateQuestObjectiveCache
	QuestTogether.nameplateQuestTitleCache = originalNameplateQuestTitleCache
	QuestTogether.nameplateHealthOverlayByUnitFrame = originalNameplateHealthOverlayByUnitFrame
	QuestTogether.nameplateBubbleByUnitFrame = originalNameplateBubbleByUnitFrame
	QuestTogether.nameplateRefreshPendingByUnitToken = originalNameplateRefreshPendingByUnitToken
	QuestTogether.nameplateHealthTintRefreshPendingByUnitToken =
		originalNameplateHealthTintRefreshPendingByUnitToken
	QuestTogether.nameplateHealthTintRetryCountByUnitToken = originalNameplateHealthTintRetryCountByUnitToken
	QuestTogether.announcementBubbleScreenHostFrame = originalAnnouncementBubbleScreenHostFrame
	QuestTogether.announcementChannelLocalID = originalAnnouncementChannelLocalID
	QuestTogether.pendingPingRequests = originalPendingPingRequests
	QuestTogether.pendingQuestCompareRequests = originalPendingQuestCompareRequests
	QuestTogether.pendingQuestRemovals = originalPendingQuestRemovals
	QuestTogether.isLoggingOut = originalIsLoggingOut

	if originalIsEnabled then
		if QuestTogether.RegisterRuntimeEvents then
			QuestTogether:RegisterRuntimeEvents()
		end
		if QuestTogether.EnableNameplateAugmentation then
			QuestTogether:EnableNameplateAugmentation()
		end
	end

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

	self:PrintChatLogSystemMessage(BuildTestLogMessage("Running " .. tostring(total) .. " in-game tests..."))

	for _, testCase in ipairs(self.tests) do
		local ok, err = pcall(function()
			WithIsolatedState(testCase.fn)
		end)

		if ok then
			passed = passed + 1
			self:PrintChatLogSystemMessage(BuildTestLogMessage("[PASS] " .. testCase.name))
		else
			failed = failed + 1
			self:PrintChatLogSystemMessage(BuildTestLogMessage("[FAIL] " .. testCase.name .. " -> " .. tostring(err)))
		end
	end

	self:PrintChatLogSystemMessage(
		BuildTestLogMessage("Test summary: " .. tostring(passed) .. " passed, " .. tostring(failed) .. " failed.")
	)
	return failed == 0
end

QuestTogether:RegisterTest("default profile contains new announcement display options", function()
	AssertTrue(QuestTogether.DEFAULTS.profile.announceAccepted ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.announceBonusObjectiveAreaEnter ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.announceBonusObjectiveAreaLeave ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.announceBonusObjectiveProgress ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.announceBonusObjectiveCompleted ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.announceReadyToTurnIn ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.showChatBubbles ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.hideMyOwnChatBubbles ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.showChatLogs ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.chatLogDestination ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.showProgressFor ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.chatBubbleSize ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.chatBubbleDuration ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.emoteOnQuestCompletion ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.emoteOnNearbyPlayerQuestCompletion ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.primaryChannel == nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.fallbackChannel == nil)
end)

QuestTogether:RegisterTest("SafeToNumber accepts numeric values without conversion", function()
	AssertEquals(QuestTogether:SafeToNumber(42), 42)
	AssertEquals(QuestTogether:SafeToNumber(" 42 "), 42)
	AssertEquals(QuestTogether:SafeToNumber(""), nil)
	AssertEquals(QuestTogether:SafeToNumber({}), nil)
end)

QuestTogether:RegisterTest("SafeTrimString and SafeStripWhitespace handle normal and failing values", function()
	AssertEquals(QuestTogether:SafeTrimString("  hello there  "), "hello there")
	AssertEquals(QuestTogether:SafeStripWhitespace(" a b\tc \n d "), "abcd")

	local failingToString = setmetatable({}, {
		__tostring = function()
			error("boom")
		end,
	})
	AssertEquals(QuestTogether:SafeTrimString(failingToString, "fallback"), "fallback")
	AssertEquals(QuestTogether:SafeStripWhitespace(failingToString, "fallback"), "fallback")
end)

QuestTogether:RegisterTest("chat bubble normalizers use SafeToNumber conversion", function()
	local seenValues = {}
	WithPatchedMethod(QuestTogether, "SafeToNumber", function(_, value)
		seenValues[#seenValues + 1] = value
		if value == "size-secret" then
			return 118
		end
		if value == "duration-secret" then
			return 2.26
		end
		return nil
	end, function()
		AssertEquals(QuestTogether:NormalizeChatBubbleSizeValue("size-secret"), 120)
		AssertEquals(QuestTogether:NormalizeChatBubbleDurationValue("duration-secret"), 2.5)
	end)
	AssertEquals(seenValues[1], "size-secret")
	AssertEquals(seenValues[2], "duration-secret")
end)

QuestTogether:RegisterTest("personal bubble anchor numeric parsing uses SafeToNumber", function()
	WithPatchedMethod(QuestTogether, "SafeToNumber", function(_, value)
		if value == "secret-x" then
			return 33
		end
		if value == "secret-y" then
			return -27
		end
		return nil
	end, function()
		QuestTogether:SetPersonalBubbleAnchor("TOP", "TOP", "secret-x", "secret-y")
		local store = QuestTogether:GetPersonalBubbleAnchorStore()
		local key = QuestTogether:GetPersonalBubbleAnchorKey()
		AssertEquals(store[key].x, 33)
		AssertEquals(store[key].y, -27)
	end)
end)

QuestTogether:RegisterTest("profile assignment is stored per character key", function()
	QuestTogether.db.profiles = {}
	QuestTogether.db.profileKeys = {}
	QuestTogether.activeCharacterKey = "Alpha-Realm"
	QuestTogether.activeProfileKey = nil

	local applyCalls = 0
	WithPatchedMethod(QuestTogether, "ApplyActiveProfileState", function()
		applyCalls = applyCalls + 1
		return true
	end, function()
		local okAlpha, errAlpha = QuestTogether:SetActiveProfile("Alpha-Realm")
		AssertTrue(okAlpha, errAlpha)
		AssertEquals(QuestTogether.db.profileKeys["Alpha-Realm"], "Alpha-Realm")

		QuestTogether.activeCharacterKey = "Beta-Realm"
		local okBeta, errBeta = QuestTogether:SetActiveProfile("Beta-Realm")
		AssertTrue(okBeta, errBeta)
		AssertEquals(QuestTogether.db.profileKeys["Beta-Realm"], "Beta-Realm")
	end)

	AssertTrue(QuestTogether.db.profiles["Alpha-Realm"] ~= nil)
	AssertTrue(QuestTogether.db.profiles["Beta-Realm"] ~= nil)
	AssertEquals(applyCalls, 2)
end)

QuestTogether:RegisterTest("profile operations support create, copy, reset, and delete", function()
	QuestTogether.db.profiles = {
		["MyPlayer-Realm"] = QuestTogether:DeepCopy(QuestTogether.DEFAULTS.profile),
		Template = QuestTogether:DeepCopy(QuestTogether.DEFAULTS.profile),
	}
	QuestTogether.db.profileKeys = {
		["MyPlayer-Realm"] = "MyPlayer-Realm",
	}
	QuestTogether.activeCharacterKey = "MyPlayer-Realm"
	QuestTogether.activeProfileKey = "MyPlayer-Realm"
	QuestTogether.db.profile = QuestTogether.db.profiles["MyPlayer-Realm"]

	QuestTogether.db.profiles.Template.showChatLogs = false
	QuestTogether.db.profiles.Template.showChatBubbles = false
	QuestTogether.db.profile.showChatLogs = true
	QuestTogether.db.profile.showChatBubbles = true

	local applyCalls = 0
	WithPatchedMethod(QuestTogether, "ApplyActiveProfileState", function()
		applyCalls = applyCalls + 1
		return true
	end, function()
		local createOk, createErr = QuestTogether:CreateProfile("Disposable", "Template")
		AssertTrue(createOk, createErr)
		AssertTrue(QuestTogether.db.profiles.Disposable ~= nil)

		local copyOk, copyErr = QuestTogether:CopyProfileIntoActiveProfile("Template")
		AssertTrue(copyOk, copyErr)
		AssertFalse(QuestTogether.db.profile.showChatLogs)
		AssertFalse(QuestTogether.db.profile.showChatBubbles)

		QuestTogether.db.profile.showChatLogs = false
		local resetOk, resetErr = QuestTogether:ResetActiveProfile()
		AssertTrue(resetOk, resetErr)
		AssertEquals(QuestTogether.db.profile.showChatLogs, QuestTogether.DEFAULTS.profile.showChatLogs)

		local deleteActiveOk = QuestTogether:DeleteProfile("MyPlayer-Realm")
		AssertFalse(deleteActiveOk)

		local deleteOk, deleteErr = QuestTogether:DeleteProfile("Disposable")
		AssertTrue(deleteOk, deleteErr)
		AssertEquals(QuestTogether.db.profiles.Disposable, nil)
	end)

	AssertEquals(applyCalls, 2)
end)

QuestTogether:RegisterTest("quest status uses ready to turn in announcement event", function()
	QuestTogether.API = CreateApiWithOverrides({
		IsQuestFlaggedCompleted = function()
			return false
		end,
		IsQuestReadyForTurnIn = function()
			return true
		end,
		GetQuestLogIndexForQuestID = function()
			return 1
		end,
		IsOnQuest = function()
			return true
		end,
		IsQuestComplete = function()
			return true
		end,
	})

	AssertEquals(QuestTogether:GetQuestStatusAnnouncementEventType(12345), "QUEST_READY_TO_TURN_IN")
end)

QuestTogether:RegisterTest("quest completion publishes and plays the same emote token", function()
	local published = nil
	local played = nil

	WithPatchedMethod(QuestTogether, "PickRandomCompletionEmote", function()
		return "cheer"
	end, function()
		WithPatchedMethod(QuestTogether, "PublishAnnouncementEvent", function(_, eventType, text, questId, extraData)
			published = {
				eventType = eventType,
				text = text,
				questId = questId,
				extraData = extraData,
			}
		end, function()
			WithPatchedMethod(QuestTogether, "PlayLocalCompletionEmote", function(_, emoteToken)
				played = emoteToken
			end, function()
				QuestTogether:HandleQuestCompleted("Test Quest", 12345)
			end)
		end)
	end)

	AssertEquals(published.eventType, "QUEST_COMPLETED")
	AssertEquals(published.questId, 12345)
	AssertEquals(published.extraData.emoteToken, "cheer")
	AssertEquals(played, "cheer")
end)

QuestTogether:RegisterTest("quest completion preserves cached quest icon metadata", function()
	local published = nil

	WithPatchedMethod(QuestTogether, "PickRandomCompletionEmote", function()
		return "cheer"
	end, function()
		WithPatchedMethod(QuestTogether, "PublishAnnouncementEvent", function(_, eventType, text, questId, extraData)
			published = {
				eventType = eventType,
				text = text,
				questId = questId,
				extraData = extraData,
			}
		end, function()
			QuestTogether:HandleQuestCompleted("Test Quest", 12345, {
				iconAsset = "CampaignCompletedQuestIcon",
				iconKind = "atlas",
			})
		end)
	end)

	AssertEquals(published.eventType, "QUEST_COMPLETED")
	AssertEquals(published.questId, 12345)
	AssertEquals(published.extraData.iconAsset, "CampaignCompletedQuestIcon")
	AssertEquals(published.extraData.iconKind, "atlas")
	AssertEquals(published.extraData.emoteToken, "cheer")
end)

QuestTogether:RegisterTest("quest turn in followed by removal announces completion once", function()
	local delayed = {}
	local completed = nil
	local removed = nil
	local refreshCalls = 0

	QuestTogether.API = CreateApiWithOverrides({
		Delay = function(_, callback)
			delayed[#delayed + 1] = callback
		end,
	})

	WithPatchedMethod(QuestTogether, "GetPlayerName", function()
		return "Tester"
	end, function()
		local tracker = QuestTogether:GetPlayerTracker()
		tracker[12345] = {
			title = "Test Quest",
			iconAsset = "CampaignActiveQuestIcon",
			iconKind = "atlas",
		}

		WithPatchedMethod(QuestTogether, "HandleQuestCompleted", function(_, questTitle, questId, extraData)
			completed = {
				questTitle = questTitle,
				questId = questId,
				extraData = extraData,
			}
		end, function()
			WithPatchedMethod(QuestTogether, "PublishAnnouncementEvent", function(_, eventType, text, questId)
				removed = {
					eventType = eventType,
					text = text,
					questId = questId,
				}
			end, function()
				WithPatchedMethod(QuestTogether, "RefreshTaskAreaStates", function()
					refreshCalls = refreshCalls + 1
				end, function()
					WithPatchedMethod(QuestTogether, "GetAnnouncementIconInfo", function(_, eventType, questId)
						AssertEquals(eventType, "QUEST_READY_TO_TURN_IN")
						AssertEquals(questId, 12345)
						return "CampaignTurnInQuestIcon", "atlas"
					end, function()
						QuestTogether:QUEST_TURNED_IN(nil, 12345)
						QuestTogether:QUEST_REMOVED(nil, 12345)
						AssertEquals(#delayed, 1)
						delayed[1]()
					end)
				end)
			end)
		end)

		AssertTrue(completed ~= nil)
		AssertEquals(completed.questTitle, "Test Quest")
		AssertEquals(completed.questId, 12345)
		AssertEquals(completed.extraData.iconAsset, "CampaignTurnInQuestIcon")
		AssertEquals(completed.extraData.iconKind, "atlas")
		AssertEquals(removed, nil)
		AssertEquals(tracker[12345], nil)
		AssertEquals(QuestTogether.pendingQuestRemovals[12345], nil)
		AssertEquals(QuestTogether.questsCompleted[12345], nil)
		AssertEquals(refreshCalls, 1)
	end)
end)

QuestTogether:RegisterTest("quest removal before turn in still resolves as completion", function()
	local delayed = {}
	local completed = nil
	local removed = nil

	QuestTogether.API = CreateApiWithOverrides({
		Delay = function(_, callback)
			delayed[#delayed + 1] = callback
		end,
	})

	WithPatchedMethod(QuestTogether, "GetPlayerName", function()
		return "Tester"
	end, function()
		local tracker = QuestTogether:GetPlayerTracker()
		tracker[12345] = {
			title = "Test Quest",
			iconAsset = "CampaignActiveQuestIcon",
			iconKind = "atlas",
		}

		WithPatchedMethod(QuestTogether, "HandleQuestCompleted", function(_, questTitle, questId, extraData)
			completed = {
				questTitle = questTitle,
				questId = questId,
				extraData = extraData,
			}
		end, function()
			WithPatchedMethod(QuestTogether, "PublishAnnouncementEvent", function(_, eventType)
				removed = eventType
			end, function()
				WithPatchedMethod(QuestTogether, "RefreshTaskAreaStates", function() end, function()
					QuestTogether:QUEST_REMOVED(nil, 12345)
					AssertEquals(#delayed, 1)
					AssertTrue(QuestTogether.pendingQuestRemovals[12345] ~= nil)
					WithPatchedMethod(QuestTogether, "GetAnnouncementIconInfo", function(_, eventType, questId)
						AssertEquals(eventType, "QUEST_READY_TO_TURN_IN")
						AssertEquals(questId, 12345)
						return "CampaignTurnInQuestIcon", "atlas"
					end, function()
						QuestTogether:QUEST_TURNED_IN(nil, 12345)
					end)
					AssertTrue(completed ~= nil)
					AssertEquals(completed.questTitle, "Test Quest")
					AssertEquals(completed.questId, 12345)
					AssertEquals(completed.extraData.iconAsset, "CampaignTurnInQuestIcon")
					AssertEquals(completed.extraData.iconKind, "atlas")
					AssertEquals(QuestTogether.pendingQuestRemovals[12345], nil)
					delayed[1]()
				end)
			end)
		end)

		AssertEquals(removed, nil)
		AssertEquals(tracker[12345], nil)
		AssertEquals(QuestTogether.questsCompleted[12345], nil)
	end)
end)

QuestTogether:RegisterTest("quest removal without turn in announces removal", function()
	local delayed = {}
	local completed = nil
	local removed = nil

	QuestTogether.API = CreateApiWithOverrides({
		Delay = function(_, callback)
			delayed[#delayed + 1] = callback
		end,
	})

	WithPatchedMethod(QuestTogether, "GetPlayerName", function()
		return "Tester"
	end, function()
		local tracker = QuestTogether:GetPlayerTracker()
		tracker[12345] = {
			title = "Test Quest",
			iconAsset = "CampaignActiveQuestIcon",
			iconKind = "atlas",
		}

		WithPatchedMethod(QuestTogether, "HandleQuestCompleted", function()
			completed = true
		end, function()
			WithPatchedMethod(QuestTogether, "PublishAnnouncementEvent", function(_, eventType, text, questId)
				removed = {
					eventType = eventType,
					text = text,
					questId = questId,
				}
			end, function()
				WithPatchedMethod(QuestTogether, "RefreshTaskAreaStates", function() end, function()
					QuestTogether:QUEST_REMOVED(nil, 12345)
					AssertEquals(#delayed, 1)
					delayed[1]()
				end)
			end)
		end)

		AssertEquals(completed, nil)
		AssertTrue(removed ~= nil)
		AssertEquals(removed.eventType, "QUEST_REMOVED")
		AssertTrue(string.find(removed.text, "Test Quest", 1, true) ~= nil)
		AssertEquals(removed.questId, 12345)
		AssertEquals(tracker[12345], nil)
		AssertEquals(QuestTogether.pendingQuestRemovals[12345], nil)
	end)
end)

QuestTogether:RegisterTest("chat bubble option validation rejects unknown values", function()
	AssertTrue(QuestTogether:SetOption("chatBubbleSize", 140))
	AssertEquals(QuestTogether:GetOption("chatBubbleSize"), 140)
	AssertFalse(QuestTogether:SetOption("chatBubbleSize", 999))
	AssertEquals(QuestTogether:GetOption("chatBubbleSize"), 140)

	AssertTrue(QuestTogether:SetOption("chatBubbleDuration", 4.5))
	AssertEquals(QuestTogether:GetOption("chatBubbleDuration"), 4.5)
	AssertFalse(QuestTogether:SetOption("chatBubbleDuration", 9))
	AssertEquals(QuestTogether:GetOption("chatBubbleDuration"), 4.5)

	AssertTrue(QuestTogether:SetOption("showProgressFor", "party_only"))
	AssertEquals(QuestTogether:GetOption("showProgressFor"), "party_only")
	AssertFalse(QuestTogether:SetOption("showProgressFor", "everyone"))
	AssertEquals(QuestTogether:GetOption("showProgressFor"), "party_only")

	WithPatchedMethod(QuestTogether, "EnsureQuestLogChatFrame", function()
		return {
			AddMessage = function() end,
		}, 3
	end, function()
		AssertTrue(QuestTogether:SetOption("chatLogDestination", "separate"))
		AssertEquals(QuestTogether:GetOption("chatLogDestination"), "separate")
		AssertFalse(QuestTogether:SetOption("chatLogDestination", "guild"))
		AssertEquals(QuestTogether:GetOption("chatLogDestination"), "separate")
	end)
end)

QuestTogether:RegisterTest("legacy bubble settings migrate to numeric values", function()
	QuestTogether.db.profile.chatBubbleSize = "small"
	QuestTogether.db.profile.chatBubbleDuration = "4"
	QuestTogether:NormalizeAnnouncementDisplayOptions()
	AssertEquals(QuestTogether.db.profile.chatBubbleSize, 100)
	AssertEquals(QuestTogether.db.profile.chatBubbleDuration, 4)

	QuestTogether.db.profile.chatBubbleSize = "gigantic"
	QuestTogether.db.profile.chatBubbleDuration = 99
	QuestTogether:NormalizeAnnouncementDisplayOptions()
	AssertEquals(QuestTogether.db.profile.chatBubbleSize, QuestTogether.DEFAULTS.profile.chatBubbleSize)
	AssertEquals(QuestTogether.db.profile.chatBubbleDuration, QuestTogether.DEFAULTS.profile.chatBubbleDuration)
end)

QuestTogether:RegisterTest("legacy doEmotes setting migrates to split emote options", function()
	QuestTogether.db.profile.doEmotes = false
	QuestTogether.db.profile.emoteOnQuestCompletion = nil
	QuestTogether.db.profile.emoteOnNearbyPlayerQuestCompletion = nil

	QuestTogether:NormalizeAnnouncementDisplayOptions()

	AssertFalse(QuestTogether.db.profile.emoteOnQuestCompletion)
	AssertFalse(QuestTogether.db.profile.emoteOnNearbyPlayerQuestCompletion)
end)

QuestTogether:RegisterTest("progressbar objective text strips trailing parenthetical percent", function()
	AssertEquals(
		QuestTogether:StripTrailingParentheticalPercent("Fill the vial (34%)"),
		"Fill the vial"
	)
	AssertEquals(
		QuestTogether:StripTrailingParentheticalPercent("Refine potadpalate"),
		"Refine potadpalate"
	)
end)

QuestTogether:RegisterTest("known nameplate addons suppress the QuestTogether quest icon", function()
	QuestTogether.db.profile.nameplateQuestIconEnabled = true
	QuestTogether.API = CreateApiWithOverrides({
		IsAddOnLoaded = function(addonName)
			return addonName == "Plater"
		end,
	})

	WithPatchedMethod(QuestTogether, "IsQuestObjectiveNameplate", function()
		return true
	end, function()
		AssertFalse(QuestTogether:ShouldShowQuestNameplateIcon("nameplate1", {}))
	end)
end)

QuestTogether:RegisterTest("quest objective detection falls back to tooltip parsing after API misses", function()
	local tooltipChecked = false
	local unitFrame = {}

	WithPatchedMethod(QuestTogether, "DoesNameplateUnitExist", function(_, unitToken)
		AssertEquals(unitToken, "nameplate1")
		return true
	end, function()
		WithPatchedMethod(QuestTogether, "IsNameplateUnitRelatedToActiveQuest", function()
			return false
		end, function()
			WithPatchedMethod(QuestTogether, "GetPlayerTracker", function()
				return {}
			end, function()
				WithPatchedMethod(QuestTogether, "IsQuestObjectiveViaTooltip", function(_, unitToken, candidateFrame)
					AssertEquals(unitToken, "nameplate1")
					AssertEquals(candidateFrame, unitFrame)
					tooltipChecked = true
					return true
				end, function()
					WithPatchedMethod(QuestTogether, "IsNameplateUnitQuestBoss", function()
						return false
					end, function()
						AssertTrue(QuestTogether:IsQuestObjectiveUnit("nameplate1", unitFrame))
					end)
				end)
			end)
		end)
	end)

	AssertTrue(tooltipChecked)
end)

QuestTogether:RegisterTest("quest objective detection does not short-circuit on false frame flags", function()
	local tooltipChecked = false
	local unitFrame = {
		namePlateIsQuestObjective = false,
		isQuestObjective = false,
	}

	WithPatchedMethod(QuestTogether, "DoesNameplateUnitExist", function(_, unitToken)
		AssertEquals(unitToken, "nameplate1")
		return true
	end, function()
		WithPatchedMethod(QuestTogether, "IsNameplateUnitRelatedToActiveQuest", function()
			return false
		end, function()
			WithPatchedMethod(QuestTogether, "GetPlayerTracker", function()
				return {}
			end, function()
				WithPatchedMethod(QuestTogether, "IsQuestObjectiveViaTooltip", function(_, unitToken, candidateFrame)
					AssertEquals(unitToken, "nameplate1")
					AssertEquals(candidateFrame, unitFrame)
					tooltipChecked = true
					return true
				end, function()
					WithPatchedMethod(QuestTogether, "IsNameplateUnitQuestBoss", function()
						return false
					end, function()
						AssertTrue(QuestTogether:IsQuestObjectiveUnit("nameplate1", unitFrame))
					end)
				end)
			end)
		end)
	end)

	AssertTrue(tooltipChecked)
end)

QuestTogether:RegisterTest("tooltip quest detection prefers frame guid over live UnitGUID lookup", function()
	local unitFrame = {
		namePlateUnitGUID = "Creature-0-0-0-0-12345-0000000000",
	}

	WithPatchedMethod(QuestTogether, "GetNameplateUnitGuid", function()
		error("should not fall back to UnitGUID when frame guid is available")
	end, function()
		AssertEquals(
			QuestTogether:GetNameplateTooltipScanGuid("nameplate1", unitFrame),
			"Creature-0-0-0-0-12345-0000000000"
		)
	end)
end)

QuestTogether:RegisterTest("personal bubble anchor persists per character and resets to defaults", function()
	WithPatchedMethod(QuestTogether, "GetPlayerFullName", function()
		return "MyPlayer-Realm"
	end, function()
		local defaults = QuestTogether.DEFAULT_PERSONAL_BUBBLE_ANCHOR
		local initialAnchor = QuestTogether:GetPersonalBubbleAnchor()
		AssertEquals(initialAnchor.point, defaults.point)
		AssertEquals(initialAnchor.relativePoint, defaults.relativePoint)
		AssertEquals(initialAnchor.x, defaults.x)
		AssertEquals(initialAnchor.y, defaults.y)

		AssertTrue(QuestTogether:SetPersonalBubbleAnchor("TOP", "TOP", 10, -25))

		local savedAnchor = QuestTogether:GetPersonalBubbleAnchor()
		AssertEquals(savedAnchor.point, "TOP")
		AssertEquals(savedAnchor.relativePoint, "TOP")
		AssertEquals(savedAnchor.x, 10)
		AssertEquals(savedAnchor.y, -25)

		AssertTrue(QuestTogether:ResetPersonalBubbleAnchor())

		local resetAnchor = QuestTogether:GetPersonalBubbleAnchor()
		AssertEquals(resetAnchor.point, defaults.point)
		AssertEquals(resetAnchor.relativePoint, defaults.relativePoint)
		AssertEquals(resetAnchor.x, defaults.x)
		AssertEquals(resetAnchor.y, defaults.y)
	end)
end)

QuestTogether:RegisterTest("announcement bubbles are blocked in instance contexts", function()
	WithPatchedMethod(QuestTogether, "IsNameplateAugmentationBlockedInCurrentContext", function()
		return true
	end, function()
		local ok = QuestTogether:ShowAnnouncementBubbleOnNameplate({
			UnitFrame = {},
		}, "Test bubble")
		AssertFalse(ok)
	end)
end)

QuestTogether:RegisterTest("console announcement message includes icon and player name", function()
	local message = QuestTogether:BuildConsoleAnnouncementMessage("MyPlayer-Realm", "hello there", "MAGE")
	AssertTrue(string.find(message, "|T" .. QuestTogether.NAMEPLATE_QUEST_ICON_TEXTURE, 1, true) ~= nil)
	AssertTrue(string.find(message, "MyPlayer", 1, true) ~= nil)
	AssertTrue(string.find(message, "|cffffd200: hello there|r", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("chat log speaker link handler opens QuestTogether menu", function()
	local capturedOwner = nil
	local capturedSpeaker = nil

	WithPatchedMethod(QuestTogether, "ShowChatLogSpeakerMenu", function(_, ownerFrame, speakerName)
		capturedOwner = ownerFrame
		capturedSpeaker = speakerName
		return true
	end, function()
		local response = QuestTogether:HandleChatLogSpeakerLink(
			nil,
			nil,
			{ options = "MyPlayer-Realm" },
			{ frame = "ChatFrame1" }
		)
		AssertEquals(response, LinkProcessorResponse.Handled)
	end)

	AssertEquals(capturedOwner, "ChatFrame1")
	AssertEquals(capturedSpeaker, "MyPlayer-Realm")
end)

QuestTogether:RegisterTest("chat log quest link handler prints local quest status", function()
	local printed = {}
	QuestTogether.PrintChatLogRaw = function(_, message)
		printed[#printed + 1] = message
	end

	QuestTogether.API = CreateApiWithOverrides({
		IsQuestFlaggedCompleted = function(questId)
			AssertEquals(questId, 12345)
			return false
		end,
		IsQuestReadyForTurnIn = function(questId)
			AssertEquals(questId, 12345)
			return true
		end,
		GetQuestLogIndexForQuestID = function(questId)
			AssertEquals(questId, 12345)
			return 7
		end,
		IsOnQuest = function(questId)
			AssertEquals(questId, 12345)
			return true
		end,
		IsQuestComplete = function(questId)
			AssertEquals(questId, 12345)
			return true
		end,
		IsPushableQuest = function(questId)
			AssertEquals(questId, 12345)
			return true
		end,
	})

	WithPatchedMethod(QuestTogether, "GetQuestTitle", function(_, questId)
		AssertEquals(questId, 12345)
		return "Test Quest"
	end, function()
		local response = QuestTogether:HandleChatLogQuestLink(
			nil,
			nil,
			{ options = "12345" },
			{ frame = "ChatFrame1" }
		)
		AssertEquals(response, LinkProcessorResponse.Handled)
	end)

	AssertEquals(#printed, 1)
	AssertTrue(string.find(printed[1] or "", "Test Quest", 1, true) ~= nil)
	AssertTrue(string.find(printed[1] or "", "Ready to Turn In", 1, true) ~= nil)
	AssertTrue(string.find(printed[1] or "", "Quest Status:", 1, true) ~= nil)
	AssertTrue(string.find(printed[1] or "", "Shareable: Yes", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("chat log quest link handler falls back to clicked quest title text", function()
	local printed = {}
	QuestTogether.PrintChatLogRaw = function(_, message)
		printed[#printed + 1] = message
	end

	QuestTogether.API = CreateApiWithOverrides({
		IsQuestFlaggedCompleted = function(questId)
			AssertEquals(questId, 28831)
			return false
		end,
		IsQuestReadyForTurnIn = function(questId)
			AssertEquals(questId, 28831)
			return false
		end,
		GetQuestLogIndexForQuestID = function(questId)
			AssertEquals(questId, 28831)
			return nil
		end,
		IsOnQuest = function(questId)
			AssertEquals(questId, 28831)
			return false
		end,
		IsQuestComplete = function(questId)
			AssertEquals(questId, 28831)
			return false
		end,
		IsPushableQuest = function(questId)
			AssertEquals(questId, 28831)
			return false
		end,
	})

	WithPatchedMethod(QuestTogether, "GetQuestTitle", function(_, questId)
		AssertEquals(questId, 28831)
		return "Quest 28831"
	end, function()
		local response = QuestTogether:HandleChatLogQuestLink(
			nil,
			"[Damn You, Frostilicus]",
			{ options = "28831" },
			{ frame = "ChatFrame1" }
		)
		AssertEquals(response, LinkProcessorResponse.Handled)
	end)

	AssertEquals(#printed, 1)
	AssertTrue(string.find(printed[1] or "", "Damn You, Frostilicus", 1, true) ~= nil)
	AssertFalse(string.find(printed[1] or "", "Quest 28831", 1, true) ~= nil)
	AssertTrue(string.find(printed[1] or "", "Not Started", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("chat log coord link handler opens ping waypoint", function()
	local opened = nil
	WithPatchedMethod(QuestTogether, "OpenPingWaypoint", function(_, mapID, coordX, coordY)
		opened = { mapID = mapID, coordX = coordX, coordY = coordY }
		return true
	end, function()
		local response = QuestTogether:HandleChatLogCoordLink(
			nil,
			nil,
			{ options = "999:47.1:69.9" },
			{ frame = "ChatFrame1" }
		)
		AssertEquals(response, LinkProcessorResponse.Handled)
	end)

	AssertEquals(opened.mapID, "999")
	AssertEquals(opened.coordX, "47.1")
	AssertEquals(opened.coordY, "69.9")
end)

QuestTogether:RegisterTest("open ping waypoint prefers TomTom and falls back to Blizzard waypoint", function()
	local calls = {}

	QuestTogether.API = CreateApiWithOverrides({
		IsAddOnLoaded = function(addonName)
			AssertEquals(addonName, "TomTom")
			return false
		end,
		CanSetUserWaypointOnMap = function(mapID)
			AssertEquals(mapID, 999)
			return true
		end,
		CreateUiMapPoint = function(mapID, x, y)
			calls[#calls + 1] = string.format("point:%d:%.3f:%.3f", mapID, x, y)
			return { mapID = mapID, x = x, y = y }
		end,
		SetUserWaypoint = function(point)
			calls[#calls + 1] = string.format("set:%d:%.3f:%.3f", point.mapID, point.x, point.y)
		end,
		SetSuperTrackedUserWaypoint = function(shouldTrack)
			calls[#calls + 1] = "track:" .. tostring(shouldTrack)
		end,
	})

	AssertTrue(QuestTogether:OpenPingWaypoint("999", "47.1", "69.9"))
	AssertEquals(calls[1], "point:999:0.471:0.699")
	AssertEquals(calls[2], "set:999:0.471:0.699")
	AssertEquals(calls[3], "track:true")
end)

QuestTogether:RegisterTest("ping response message includes addon version when available", function()
	local message = QuestTogether:BuildPingResponseMessage({
		senderName = "Remote-Realm",
		classFile = "MAGE",
		className = "Mage",
		level = "80",
		realmName = "Realm",
		addonVersion = "3.0.0",
	})

	AssertTrue(string.find(message, "Remote", 1, true) ~= nil)
	AssertTrue(string.find(message, "QT v3.0.0", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("player ping metadata includes addon version", function()
	QuestTogether.API = CreateApiWithOverrides({
		GetAddOnMetadata = function(addonName, fieldName)
			AssertEquals(addonName, QuestTogether.addonName)
			AssertEquals(fieldName, "Version")
			return " 3.0.0 "
		end,
		UnitFullName = function()
			return "Local", "Realm"
		end,
		GetRealmName = function()
			return "Realm"
		end,
		UnitClass = function()
			return "Mage", "MAGE"
		end,
		UnitRace = function()
			return "Human"
		end,
		UnitLevel = function()
			return 80
		end,
	})

	WithPatchedMethod(QuestTogether, "GetPlayerFullName", function()
		return "Local-Realm"
	end, function()
		WithPatchedMethod(QuestTogether, "GetPlayerAnnouncementLocationInfo", function()
			return {}
		end, function()
			local metadata = QuestTogether:GetPlayerPingMetadata()
			AssertEquals(metadata.addonVersion, "3.0.0")
		end)
	end)
end)

QuestTogether:RegisterTest("ping response payload round trip preserves addon version", function()
	local payload = QuestTogether:EncodePingResponsePayload({
		requestId = "req-1",
		senderName = "Remote-Realm",
		realmName = "Realm",
		raceName = "Human",
		classFile = "MAGE",
		className = "Mage",
		level = "80",
		zoneName = "Stormwind",
		coordX = "12.3",
		coordY = "45.6",
		warMode = "0",
		mapID = "84",
		addonVersion = "3.0.0",
	})
	local decoded = QuestTogether:DecodePingResponsePayload(payload)

	AssertTrue(decoded ~= nil)
	AssertEquals(decoded.addonVersion, "3.0.0")
end)

QuestTogether:RegisterTest("announcement decode rejects nonnumeric version without raw tonumber fallback", function()
	WithPatchedMethod(QuestTogether, "SafeToNumber", function(_, value)
		AssertEquals(value, "secret")
		return nil
	end, function()
		AssertEquals(QuestTogether:DecodeAnnouncementPayload("secret,event,senderGuid,MAGE,Sender,text"), nil)
	end)
end)

QuestTogether:RegisterTest("quest compare done decode treats nonnumeric count as zero safely", function()
	WithPatchedMethod(QuestTogether, "SafeToNumber", function(_, value)
		if value == "1" then
			return 1
		end
		if value == "secret" then
			return nil
		end
		return tonumber(value)
	end, function()
		local decoded = QuestTogether:DecodeQuestCompareDonePayload("1,req,Remote-Realm,secret")
		AssertTrue(decoded ~= nil)
		AssertEquals(decoded.count, 0)
	end)
end)

QuestTogether:RegisterTest("chat log speaker menu includes player actions", function()
	local titles = {}
	local buttons = {}
	local dividers = 0
	local fakeRoot = {
		CreateTitle = function(_, text)
			titles[#titles + 1] = text
		end,
		CreateButton = function(_, text, callback)
			buttons[#buttons + 1] = {
				text = text,
				callback = callback,
			}
		end,
		CreateDivider = function()
			dividers = dividers + 1
		end,
	}

	WithPatchedMethod(QuestTogether, "IsIgnoredPlayerName", function()
		return false
	end, function()
		WithPatchedMethod(QuestTogether, "GetOption", function(_, key)
			if key == "chatLogDestination" then
				return "main"
			end
			return QuestTogether.db.profile[key]
		end, function()
			QuestTogether:PopulateChatLogSpeakerMenu(fakeRoot, "ChatFrame1", "MyPlayer-Realm")
		end)
	end)

	AssertEquals(titles[1], "MyPlayer")
	AssertEquals(buttons[1].text, "Invite")
	AssertEquals(buttons[2].text, "Whisper")
	AssertEquals(buttons[3].text, "Add Friend")
	AssertEquals(buttons[4].text, "Ignore")
	AssertEquals(buttons[5].text, "Compare Quests")
	AssertEquals(buttons[6].text, "Move QuestTogether Logs to Separate Window")
	AssertEquals(dividers, 1)
end)

QuestTogether:RegisterTest("chat log speaker menu compare quests action uses full speaker name", function()
	local comparedName = nil
	WithPatchedMethod(QuestTogether, "RequestQuestCompare", function(_, speakerName)
		comparedName = speakerName
		return true
	end, function()
		AssertTrue(QuestTogether:CompareQuestsWithChatLogSpeaker("MyPlayer-Realm"))
	end)
	AssertEquals(comparedName, "MyPlayer-Realm")
end)

QuestTogether:RegisterTest("chat log speaker menu invite action uses full speaker name", function()
	local invitedName = nil
	WithPatchedMethod(QuestTogether.API, "InviteUnit", function(name)
		invitedName = name
	end, function()
		AssertTrue(QuestTogether:InviteChatLogSpeaker("MyPlayer-Realm"))
	end)
	AssertEquals(invitedName, "MyPlayer-Realm")
end)

QuestTogether:RegisterTest("chat log speaker menu whisper action uses owner frame", function()
	local whisperedName = nil
	local whisperedFrame = nil
	WithPatchedMethod(QuestTogether.API, "SendTell", function(name, chatFrame)
		whisperedName = name
		whisperedFrame = chatFrame
	end, function()
		AssertTrue(QuestTogether:WhisperChatLogSpeaker("MyPlayer-Realm", "ChatFrame9"))
	end)
	AssertEquals(whisperedName, "MyPlayer-Realm")
	AssertEquals(whisperedFrame, "ChatFrame9")
end)

QuestTogether:RegisterTest("chat log speaker menu add friend action uses full speaker name", function()
	local friendName = nil
	WithPatchedMethod(QuestTogether.API, "AddFriend", function(name)
		friendName = name
	end, function()
		AssertTrue(QuestTogether:AddFriendFromChatLogSpeaker("MyPlayer-Realm"))
	end)
	AssertEquals(friendName, "MyPlayer-Realm")
end)

QuestTogether:RegisterTest("chat log speaker menu ignore action uses full speaker name", function()
	local ignoredName = nil
	WithPatchedMethod(QuestTogether.API, "AddOrDelIgnore", function(name)
		ignoredName = name
	end, function()
		AssertTrue(QuestTogether:ToggleIgnoreChatLogSpeaker("MyPlayer-Realm"))
	end)
	AssertEquals(ignoredName, "MyPlayer-Realm")
end)

QuestTogether:RegisterTest("chat log speaker menu shows unignore for ignored speaker", function()
	local buttons = {}
	local fakeRoot = {
		CreateTitle = function() end,
		CreateButton = function(_, text)
			buttons[#buttons + 1] = text
		end,
		CreateDivider = function() end,
	}

	WithPatchedMethod(QuestTogether, "IsIgnoredPlayerName", function(_, speakerName)
		AssertEquals(speakerName, "Ignored-Realm")
		return true
	end, function()
		QuestTogether:PopulateChatLogSpeakerMenu(fakeRoot, "ChatFrame1", "Ignored-Realm")
	end)

	AssertEquals(buttons[4], "Unignore")
end)

QuestTogether:RegisterTest("request quest compare sends compare request for remote speaker", function()
	local sent = {}
	local startedWith = nil
	local startedClass = nil

	QuestTogether.isEnabled = true
	QuestTogether.partyMembers = {
		["Remote-Realm"] = {
			fullName = "Remote-Realm",
			classFile = "DRUID",
		},
	}
	QuestTogether.API = CreateApiWithOverrides({
		GetChannelName = function(channelName)
			AssertEquals(channelName, QuestTogether.announcementChannelName)
			return 9
		end,
		SendAddonMessage = function(prefix, message, channel, target)
			sent[#sent + 1] = {
				prefix = prefix,
				message = message,
				channel = channel,
				target = target,
			}
		end,
		Delay = function() end,
		UnitFullName = function(unitToken)
			AssertEquals(unitToken, "player")
			return "LocalPlayer", "Realm"
		end,
	})

	WithPatchedMethod(QuestTogether, "PrintQuestCompareStart", function(_, remoteName, classFile)
		startedWith = remoteName
		startedClass = classFile
	end, function()
		AssertTrue(QuestTogether:RequestQuestCompare("Remote-Realm"))
	end)

	AssertEquals(startedWith, "Remote-Realm")
	AssertEquals(startedClass, "DRUID")
	AssertEquals(#sent, 1)
	AssertEquals(sent[1].prefix, QuestTogether.commPrefix)
	AssertEquals(sent[1].channel, "CHANNEL")
	AssertEquals(sent[1].target, 9)
	AssertTrue(string.find(sent[1].message, "^QCMP|", 1) ~= nil)
end)

QuestTogether:RegisterTest("quest compare entry prints local status and shareable state", function()
	local printed = {}
	QuestTogether.API = CreateApiWithOverrides({
		IsQuestFlaggedCompleted = function(questId)
			AssertEquals(questId, 12345)
			return false
		end,
		IsQuestReadyForTurnIn = function(questId)
			AssertEquals(questId, 12345)
			return false
		end,
		GetQuestLogIndexForQuestID = function(questId)
			AssertEquals(questId, 12345)
			return 4
		end,
		IsOnQuest = function(questId)
			AssertEquals(questId, 12345)
			return true
		end,
		IsQuestComplete = function(questId)
			AssertEquals(questId, 12345)
			return false
		end,
	})

	WithPatchedMethod(QuestTogether, "PrintConsoleAnnouncement", function(_, message, targetName, classFile, eventType)
		printed[#printed + 1] = {
			message = message,
			targetName = targetName,
			classFile = classFile,
			eventType = eventType,
		}
	end, function()
		QuestTogether:PrintQuestCompareMessage("Remote-Realm", {
			questId = "12345",
			questTitle = "Test Quest",
			isComplete = true,
			isPushable = true,
		}, "WARRIOR")
	end)

	AssertEquals(#printed, 1)
	AssertEquals(printed[1].targetName, "Remote-Realm")
	AssertEquals(printed[1].classFile, "WARRIOR")
	AssertEquals(printed[1].eventType, "QUEST_COMPLETED")
	AssertTrue(string.find(printed[1].message, "Test Quest", 1, true) ~= nil)
	AssertTrue(string.find(printed[1].message, "Them: Complete", 1, true) ~= nil)
	AssertTrue(string.find(printed[1].message, "You: In Progress", 1, true) ~= nil)
	AssertTrue(string.find(printed[1].message, "Shareable to You: Yes", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("quest compare response prints entries and clears pending request on done", function()
	local printed = {}
	QuestTogether.pendingQuestCompareRequests = {
		["qcmp-123"] = {
			targetName = "Remote-Realm",
			classFile = nil,
			count = 0,
		},
	}

	QuestTogether.API = CreateApiWithOverrides({
		IsQuestFlaggedCompleted = function()
			return false
		end,
		IsQuestReadyForTurnIn = function()
			return false
		end,
		GetQuestLogIndexForQuestID = function()
			return nil
		end,
		IsOnQuest = function()
			return false
		end,
		IsQuestComplete = function()
			return false
		end,
	})

	WithPatchedMethod(QuestTogether, "PrintConsoleAnnouncement", function(_, message, targetName, classFile, eventType)
		printed[#printed + 1] = {
			message = message,
			targetName = targetName,
			classFile = classFile,
			eventType = eventType,
		}
	end, function()
		AssertTrue(QuestTogether:HandleQuestCompareEntry({
			requestId = "qcmp-123",
			senderName = "Remote-Realm",
			classFile = "WARRIOR",
			questId = "12345",
			questTitle = "Remote Quest",
			isComplete = false,
			isPushable = false,
		}))
		AssertTrue(QuestTogether:HandleQuestCompareDone({
			requestId = "qcmp-123",
			senderName = "Remote-Realm",
			classFile = "",
			count = 1,
		}))
	end)

	AssertEquals(#printed, 2)
	AssertEquals(printed[1].targetName, "Remote-Realm")
	AssertEquals(printed[1].classFile, "WARRIOR")
	AssertEquals(printed[1].eventType, "QUEST_PROGRESS")
	AssertTrue(string.find(printed[1].message, "Remote Quest", 1, true) ~= nil)
	AssertEquals(printed[2].targetName, "Remote-Realm")
	AssertEquals(printed[2].classFile, "WARRIOR")
	AssertEquals(printed[2].eventType, "QUEST_COMPLETED")
	AssertTrue(string.find(printed[2].message, "Finished comparing quests", 1, true) ~= nil)
	AssertEquals(QuestTogether.pendingQuestCompareRequests["qcmp-123"], nil)
end)

QuestTogether:RegisterTest("world quest console announcement uses world quest icon", function()
	local message =
		QuestTogether:BuildConsoleAnnouncementMessage("MyPlayer-Realm", "entered the area", "MAGE", "WORLD_QUEST_ENTERED")
	AssertTrue(string.find(message, "|A:worldquest%-icon:14:14|a") ~= nil)
	AssertTrue(string.find(message, "MyPlayer", 1, true) ~= nil)
	AssertTrue(string.find(message, "|cffffd200: entered the area|r", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("bonus objective console announcement uses bonus objective icon", function()
	local message = QuestTogether:BuildConsoleAnnouncementMessage(
		"MyPlayer-Realm",
		"entered the area",
		"MAGE",
		"BONUS_OBJECTIVE_ENTERED"
	)
	AssertTrue(string.find(message, "|A:Bonus%-Objective%-Star:14:14|a") ~= nil)
	AssertTrue(string.find(message, "MyPlayer", 1, true) ~= nil)
	AssertTrue(string.find(message, "|cffffd200: entered the area|r", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("world quest announcement icon info uses Blizzard world quest atlas", function()
	WithPatchedMethod(QuestTogether, "GetQuestTagInfo", function(_, questId)
		AssertEquals(questId, 12345)
		return { worldQuestType = 7 }
	end, function()
		WithPatchedMethod(QuestTogether, "GetWorldQuestAtlasInfo", function(_, questId, tagInfo, inProgress)
			AssertEquals(questId, 12345)
			AssertEquals(tagInfo.worldQuestType, 7)
			AssertEquals(inProgress, false)
			return "worldquest-icon-petbattle"
		end, function()
			WithPatchedMethod(QuestTogether, "GetQuestDetailsThemePoiIcon", function()
				return nil
			end, function()
				local asset, kind = QuestTogether:GetAnnouncementIconInfo("WORLD_QUEST_PROGRESS", 12345)
				AssertEquals(asset, "worldquest-icon-petbattle")
				AssertEquals(kind, "atlas")
			end)
		end)
	end)
end)

QuestTogether:RegisterTest("bonus objective announcement icon info prefers quest tag atlas", function()
	WithPatchedMethod(QuestTogether, "GetQuestTagInfo", function(_, questId)
		AssertEquals(questId, 54321)
		return { tagID = 9, worldQuestType = nil }
	end, function()
		WithPatchedMethod(QuestTogether, "GetQuestTagAtlas", function(_, tagID, worldQuestType)
			AssertEquals(tagID, 9)
			AssertEquals(worldQuestType, nil)
			return "poi-door-arrow-up"
		end, function()
			WithPatchedMethod(QuestTogether, "GetQuestDetailsThemePoiIcon", function()
				return nil
			end, function()
				WithPatchedMethod(QuestTogether, "GetQuestStateAnnouncementIconInfo", function()
					return "CampaignInProgressQuestIcon", "atlas"
				end, function()
					local asset, kind = QuestTogether:GetAnnouncementIconInfo("BONUS_OBJECTIVE_PROGRESS", 54321)
					AssertEquals(asset, "poi-door-arrow-up")
					AssertEquals(kind, "atlas")
				end)
			end)
		end)
	end)
end)

QuestTogether:RegisterTest("console announcement uses sender provided quest icon asset", function()
	local message = QuestTogether:BuildConsoleAnnouncementMessage(
		"MyPlayer-Realm",
		"1/3 Objectives",
		"MAGE",
		"QUEST_PROGRESS",
		"CampaignInProgressQuestIcon",
		"atlas"
	)
	AssertTrue(string.find(message, "|A:CampaignInProgressQuestIcon:14:14|a") ~= nil)
	AssertTrue(string.find(message, "MyPlayer", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("dev log all announcements does not append location metadata to chat logs", function()
	QuestTogether.db.profile.devLogAllAnnouncements = true

	local message = QuestTogether:BuildConsoleAnnouncementMessage(
		"MyPlayer-Realm",
		"hello there",
		"MAGE",
		"QUEST_PROGRESS",
		nil,
		nil,
		{
			zoneName = "Silvermoon City",
			coordX = "45.2",
			coordY = "31.8",
			warMode = "1",
		}
	)

	AssertFalse(string.find(message, "Silvermoon City", 1, true) ~= nil)
	AssertFalse(string.find(message, "45.2, 31.8", 1, true) ~= nil)
	AssertFalse(string.find(message, "WM On", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("dev log all announcements omits missing war mode metadata", function()
	QuestTogether.db.profile.devLogAllAnnouncements = true

	local message = QuestTogether:BuildConsoleAnnouncementMessage(
		"MyPlayer-Realm",
		"hello there",
		"MAGE",
		"QUEST_PROGRESS",
		nil,
		nil,
		{
			zoneName = "",
			coordX = "",
			coordY = "",
			warMode = "",
		}
	)

	AssertFalse(string.find(message, "WM Off", 1, true) ~= nil)
	AssertFalse(string.find(message, " |cff999999[", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("local announcement event includes resolved icon metadata", function()
	QuestTogether.API = CreateApiWithOverrides({
		UnitGUID = function(unitToken)
			AssertEquals(unitToken, "player")
			return "Player-1-ABC"
		end,
	})

	WithPatchedMethod(QuestTogether, "GetAnnouncementIconInfo", function(_, eventType, questId)
		AssertEquals(eventType, "QUEST_PROGRESS")
		AssertEquals(questId, 12345)
		return "CampaignInProgressQuestIcon", "atlas"
	end, function()
		local eventData = QuestTogether:BuildLocalAnnouncementEvent("QUEST_PROGRESS", "1/3 Objectives", 12345)
		AssertEquals(eventData.questId, "12345")
		AssertEquals(eventData.iconAsset, "CampaignInProgressQuestIcon")
		AssertEquals(eventData.iconKind, "atlas")
	end)
end)

QuestTogether:RegisterTest("local announcement event prefers provided icon metadata overrides", function()
	QuestTogether.API = CreateApiWithOverrides({
		UnitGUID = function(unitToken)
			AssertEquals(unitToken, "player")
			return "Player-1-ABC"
		end,
	})

	WithPatchedMethod(QuestTogether, "GetAnnouncementIconInfo", function(_, eventType, questId)
		AssertEquals(eventType, "QUEST_COMPLETED")
		AssertEquals(questId, 12345)
		return "QuestNormal", "texture"
	end, function()
		local eventData = QuestTogether:BuildLocalAnnouncementEvent("QUEST_COMPLETED", "Quest Completed: Test Quest", 12345, {
			iconAsset = "CampaignCompletedQuestIcon",
			iconKind = "atlas",
		})
		AssertEquals(eventData.iconAsset, "CampaignCompletedQuestIcon")
		AssertEquals(eventData.iconKind, "atlas")
	end)
end)

QuestTogether:RegisterTest("local announcement event includes location metadata", function()
	QuestTogether.API = CreateApiWithOverrides({
		UnitGUID = function()
			return "Player-1-ABC"
		end,
	})

	WithPatchedMethod(QuestTogether, "GetPlayerFullName", function()
		return "MyPlayer-Realm"
	end, function()
		WithPatchedMethod(QuestTogether, "GetAnnouncementIconInfo", function()
			return nil, nil
		end, function()
			WithPatchedMethod(QuestTogether, "GetPlayerAnnouncementLocationInfo", function()
				return {
					zoneName = "Eversong Woods",
					coordX = 12.3,
					coordY = 45.6,
					warMode = false,
				}
			end, function()
				local eventData = QuestTogether:BuildLocalAnnouncementEvent("QUEST_PROGRESS", "1/3 Objectives", 12345)
				AssertEquals(eventData.zoneName, "Eversong Woods")
				AssertEquals(eventData.coordX, "12.3")
				AssertEquals(eventData.coordY, "45.6")
				AssertEquals(eventData.warMode, "0")
			end)
		end)
	end)
end)

QuestTogether:RegisterTest("console announcements use separate QuestTogether chat frame when configured", function()
	local printedToFrame = {}
	local fallbackPrinted = {}
	local fakeFrame = {
		AddMessage = function(_, message)
			printedToFrame[#printedToFrame + 1] = message
		end,
	}

	QuestTogether.db.profile.chatLogDestination = "separate"
	QuestTogether.PrintRaw = function(_, message)
		fallbackPrinted[#fallbackPrinted + 1] = message
	end

	WithPatchedMethod(QuestTogether, "EnsureQuestLogChatFrame", function()
		return fakeFrame, 3
	end, function()
		QuestTogether:PrintConsoleAnnouncement("hello there", "MyPlayer-Realm", "MAGE")
	end)

	AssertEquals(#printedToFrame, 1)
	AssertEquals(#fallbackPrinted, 0)
	AssertTrue(string.find(printedToFrame[1], "hello there", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("generic print uses resolved QuestTogether chat frame", function()
	local printedToFrame = {}
	local fakeFrame = {
		AddMessage = function(_, message)
			printedToFrame[#printedToFrame + 1] = message
		end,
	}

	WithPatchedMethod(QuestTogether, "GetChatLogFrame", function()
		return fakeFrame
	end, function()
		QuestTogether:Print("separate frame only")
	end)

	AssertEquals(#printedToFrame, 1)
	AssertTrue(string.find(printedToFrame[1], "separate frame only", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("nameplate quest icon helper does not leak a global", function()
	AssertEquals(_G.ApplyQuestIconVisual, nil)
end)

QuestTogether:RegisterTest("nameplate health tint helpers use overlays without touching status bars", function()
	local setColorCalls = 0
	local createdTextures = {}
	local liveFillTexture = {
		points = {},
		SetPoint = function(self, ...)
			self.points[#self.points + 1] = { ... }
		end,
		ClearAllPoints = function(self)
			self.points = {}
		end,
	}
	local unitFrame = {
		unit = "nameplate1",
		healthBar = {
			SetStatusBarColor = function()
				setColorCalls = setColorCalls + 1
			end,
			GetStatusBarTexture = function()
				return liveFillTexture
			end,
			CreateTexture = function()
				local texture = {
					shown = false,
					color = nil,
					points = {},
					allPointsTarget = nil,
					SetPoint = function(self, ...)
						self.points[#self.points + 1] = { ... }
					end,
					ClearAllPoints = function(self)
						self.points = {}
					end,
					SetAllPoints = function(self, target)
						self.allPointsTarget = target
					end,
					SetColorTexture = function(self, ...)
						self.color = { ... }
					end,
					SetTexture = function(self, asset)
						self.textureAsset = asset
					end,
					SetAtlas = function(self, asset, useAtlasSize)
						self.atlasAsset = asset
						self.useAtlasSize = useAtlasSize
					end,
					SetTexCoord = function(self, ...)
						self.texCoord = { ... }
					end,
					SetVertexColor = function(self, ...)
						self.vertexColor = { ... }
					end,
					SetBlendMode = function(self, blendMode)
						self.blendMode = blendMode
					end,
					Show = function(self)
						self.shown = true
					end,
					Hide = function(self)
						self.shown = false
					end,
					SetAlpha = function(self, value)
						self.alpha = value
					end,
				}
				createdTextures[#createdTextures + 1] = texture
				return texture
			end,
			GetAlpha = function()
				return 0.8
			end,
		},
	}

	WithPatchedMethod(QuestTogether, "CreateNameplateHealthOverlayTexture", function(_, parentFrame)
		AssertTrue(parentFrame ~= nil)
		local texture = {
			shown = false,
			color = nil,
			points = {},
			allPointsTarget = nil,
			SetPoint = function(self, ...)
				self.points[#self.points + 1] = { ... }
			end,
			ClearAllPoints = function(self)
				self.points = {}
			end,
			SetAllPoints = function(self, target)
				self.allPointsTarget = target
			end,
			SetColorTexture = function(self, ...)
				self.color = { ... }
			end,
			SetTexture = function(self, asset)
				self.textureAsset = asset
			end,
			SetAtlas = function(self, asset, useAtlasSize)
				self.atlasAsset = asset
				self.useAtlasSize = useAtlasSize
			end,
			SetTexCoord = function(self, ...)
				self.texCoord = { ... }
			end,
			SetVertexColor = function(self, ...)
				self.vertexColor = { ... }
			end,
			SetBlendMode = function(self, blendMode)
				self.blendMode = blendMode
			end,
			Show = function(self)
				self.shown = true
			end,
			Hide = function(self)
				self.shown = false
			end,
			SetAlpha = function(self, value)
				self.alpha = value
			end,
		}
		texture:SetAtlas(QuestTogether.NAMEPLATE_HEALTH_FILL_ATLAS, true)
		createdTextures[#createdTextures + 1] = texture
		return texture
	end, function()
		QuestTogether:ApplyQuestTintToNameplate(unitFrame)
	end)

	AssertEquals(#createdTextures, 2)

	local overlay = QuestTogether.nameplateHealthOverlayByUnitFrame[unitFrame]
	AssertTrue(overlay ~= nil)
	AssertEquals(overlay.FillTexture, createdTextures[1])
	AssertEquals(overlay.Highlight, createdTextures[2])

	AssertTrue(overlay.FillTexture.shown)
	AssertTrue(overlay.Highlight.shown)
	AssertEquals(#overlay.FillTexture.points, 4)
	AssertEquals(overlay.FillTexture.points[1][2], liveFillTexture)
	AssertEquals(overlay.Highlight.blendMode, "ADD")
	AssertEquals(#overlay.Highlight.points, 4)
	AssertEquals(overlay.FillTexture.alpha, 0.8)
	AssertEquals(overlay.Highlight.alpha, 0.8)
	AssertEquals(overlay.FillTexture.atlasAsset, "UI-HUD-CoolDownManager-Bar")
	AssertEquals(overlay.FillTexture.useAtlasSize, true)
	AssertTrue(overlay.FillTexture.vertexColor ~= nil)
	AssertTrue(overlay.Highlight.color ~= nil)
	AssertEquals(overlay.Highlight.color[4], 0.14)

	QuestTogether:RestoreNameplateHealthColor(unitFrame)

	AssertEquals(setColorCalls, 0)
	AssertEquals(QuestTogether.nameplateHealthOverlayByUnitFrame[unitFrame], overlay)
	AssertFalse(overlay.FillTexture.shown)
	AssertFalse(overlay.Highlight.shown)
end)

QuestTogether:RegisterTest("nameplate health tint hides overlay when live fill texture is unavailable", function()
	local unitFrame = {
		unit = "nameplate1",
		healthBar = {
			GetStatusBarTexture = function()
				return nil
			end,
			CreateTexture = function()
				return {
					SetAllPoints = function() end,
					SetTexture = function() end,
					SetAtlas = function() end,
					SetTexCoord = function() end,
					SetVertexColor = function() end,
					SetBlendMode = function() end,
					Show = function() end,
					Hide = function() end,
					SetAlpha = function() end,
					SetPoint = function() end,
					ClearAllPoints = function() end,
				}
			end,
		},
	}

	local restoredUnitFrame = nil
	WithPatchedMethod(QuestTogether, "RestoreNameplateHealthColor", function(_, candidateFrame)
		restoredUnitFrame = candidateFrame
	end, function()
		QuestTogether:ApplyQuestTintToNameplate(unitFrame)
	end)

	AssertEquals(restoredUnitFrame, unitFrame)
end)

QuestTogether:RegisterTest("nameplate health tint schedules a bounded retry when live fill texture is unavailable", function()
	local scheduledUnitToken = nil
	local scheduledDelay = nil
	local namePlateFrameBase = {
		UnitFrame = {
			unit = "nameplate1",
			healthBar = {},
		},
	}

	WithPatchedMethod(QuestTogether, "ShouldApplyQuestHealthTint", function(_, unitFrame, isQuestObjective)
		AssertEquals(unitFrame, namePlateFrameBase.UnitFrame)
		AssertEquals(isQuestObjective, true)
		return true
	end, function()
		WithPatchedMethod(QuestTogether, "ApplyQuestTintToNameplate", function(_, unitFrame)
			AssertEquals(unitFrame, namePlateFrameBase.UnitFrame)
			return false
		end, function()
			WithPatchedMethod(QuestTogether, "ScheduleNameplateHealthTintRefresh", function(_, unitToken, delaySeconds)
				scheduledUnitToken = unitToken
				scheduledDelay = delaySeconds
			end, function()
				QuestTogether:RefreshNameplateHealthTint(namePlateFrameBase, true)
			end)
		end)
	end)

	AssertEquals(scheduledUnitToken, "nameplate1")
	AssertEquals(scheduledDelay, 0.05)
	AssertEquals(QuestTogether.nameplateHealthTintRetryCountByUnitToken["nameplate1"], 1)
end)

QuestTogether:RegisterTest("nameplate icon refresh schedules a short follow-up tint refresh for quest units", function()
	local scheduledUnitToken = nil
	local scheduledDelay = nil
	local namePlateFrameBase = {
		GetUnit = function()
			return "nameplate1"
		end,
		UnitFrame = {
			unit = "nameplate1",
			healthBar = {
			},
		},
	}

	QuestTogether.isEnabled = true
	WithPatchedMethod(QuestTogether, "ShouldShowQuestNameplateIcon", function()
		return false
	end, function()
		WithPatchedMethod(QuestTogether, "IsQuestObjectiveNameplate", function()
			return true
		end, function()
			WithPatchedMethod(QuestTogether, "RefreshNameplateHealthTint", function(_, frameBase, isQuestObjective)
				AssertEquals(frameBase, namePlateFrameBase)
				AssertEquals(isQuestObjective, true)
			end, function()
		WithPatchedMethod(QuestTogether, "ScheduleNameplateHealthTintRefresh", function(_, unitToken, delaySeconds)
			scheduledUnitToken = unitToken
			scheduledDelay = delaySeconds
		end, function()
					QuestTogether:RefreshNameplateIcon(namePlateFrameBase)
				end)
			end)
		end)
	end)

	AssertEquals(scheduledUnitToken, "nameplate1")
	AssertEquals(scheduledDelay, 0.05)
end)

QuestTogether:RegisterTest("nameplate health tint uses resolved quest state from icon refresh", function()
	local appliedUnitFrame = nil
	QuestTogether.isEnabled = true
	local namePlateFrameBase = {
		GetUnit = function()
			return "nameplate1"
		end,
		UnitFrame = {
			unit = "nameplate1",
			healthBar = {},
		},
	}

	WithPatchedMethod(QuestTogether, "ShouldShowQuestNameplateIcon", function(_, unitToken, unitFrame)
		AssertEquals(unitToken, "nameplate1")
		AssertEquals(unitFrame, namePlateFrameBase.UnitFrame)
		return false
	end, function()
		WithPatchedMethod(QuestTogether, "IsQuestObjectiveNameplate", function(_, unitToken, unitFrame)
			AssertEquals(unitToken, "nameplate1")
			AssertEquals(unitFrame, namePlateFrameBase.UnitFrame)
			return true
		end, function()
			WithPatchedMethod(QuestTogether, "ApplyQuestTintToNameplate", function(_, unitFrame)
				appliedUnitFrame = unitFrame
				return true
			end, function()
				WithPatchedMethod(QuestTogether, "DoesNameplateUnitExist", function()
					return true
				end, function()
					WithPatchedMethod(QuestTogether, "IsNameplateUnitPlayer", function()
						return false
					end, function()
						WithPatchedMethod(QuestTogether, "CanPlayerAttackNameplateUnit", function()
							return true
						end, function()
							WithPatchedMethod(QuestTogether, "IsNameplateUnitConnected", function()
								return true
							end, function()
								WithPatchedMethod(QuestTogether, "IsNameplateUnitDead", function()
									return false
								end, function()
									WithPatchedMethod(QuestTogether, "IsNameplateUnitTapDenied", function()
										return false
									end, function()
										WithPatchedMethod(QuestTogether, "IsQuestObjectiveUnit", function()
											return false
										end, function()
											QuestTogether:RefreshNameplateIcon(namePlateFrameBase)
										end)
									end)
								end)
							end)
						end)
					end)
				end)
			end)
		end)
	end)

	AssertEquals(appliedUnitFrame, namePlateFrameBase.UnitFrame)
	AssertEquals(QuestTogether.nameplateQuestStateByUnitToken["nameplate1"], true)
end)

QuestTogether:RegisterTest("separate chat window inherits main chat font size when enabled", function()
	local appliedFontSize = nil
	local fakeMainFrame = {
		GetID = function()
			return 1
		end,
	}
	local fakeQuestFrame = {
		GetID = function()
			return 3
		end,
	}

	QuestTogether.API = CreateApiWithOverrides({
		GetChatWindowInfo = function(chatFrameID)
			if chatFrameID == 1 then
				return "General", 18
			end
			if chatFrameID == 3 then
				return "QuestTogether", 14
			end
			return nil
		end,
		SetChatWindowFontSize = function(chatFrame, fontSize)
			appliedFontSize = {
				frameID = chatFrame:GetID(),
				fontSize = fontSize,
			}
		end,
	})

	local ok, err = pcall(function()
		WithPatchedMethod(QuestTogether, "GetMainChatFrame", function()
			return fakeMainFrame
		end, function()
			WithPatchedMethod(QuestTogether, "EnsureQuestLogChatFrame", function()
				return fakeQuestFrame, 3
			end, function()
				AssertTrue(QuestTogether:SetOption("chatLogDestination", "separate"))
			end)
		end)
	end)
	if not ok then
		error(err, 0)
	end

	AssertTrue(appliedFontSize ~= nil)
	AssertEquals(appliedFontSize.frameID, 3)
	AssertEquals(appliedFontSize.fontSize, 18)
end)

QuestTogether:RegisterTest("switching chat logs back to main closes QuestTogether chat window", function()
	local closeCalls = {}
	local fakeQuestFrame = {
		GetID = function()
			return 3
		end,
	}

	QuestTogether.db.profile.chatLogDestination = "separate"
	QuestTogether.db.profile.questLogChatFrameID = 3
	QuestTogether.API = CreateApiWithOverrides({
		GetChatFrameByID = function(chatFrameID)
			if chatFrameID == 3 then
				return fakeQuestFrame
			end
			return nil
		end,
		GetChatWindowInfo = function(chatFrameID)
			if chatFrameID == 3 then
				return "QuestTogether", 18
			end
			return nil
		end,
		CloseChatWindow = function(chatFrame)
			closeCalls[#closeCalls + 1] = chatFrame:GetID()
		end,
	})

	AssertTrue(QuestTogether:SetOption("chatLogDestination", "main"))
	AssertEquals(#closeCalls, 1)
	AssertEquals(closeCalls[1], 3)
	AssertEquals(QuestTogether.db.profile.questLogChatFrameID, nil)
end)

QuestTogether:RegisterTest("closing QuestTogether chat window reverts chat log destination to main", function()
	local refreshed = 0
	local fakeQuestFrame = {
		GetID = function()
			return 3
		end,
	}

	QuestTogether.db.profile.chatLogDestination = "separate"
	QuestTogether.db.profile.questLogChatFrameID = 3
	QuestTogether.API = CreateApiWithOverrides({
		Delay = function(_, callback)
			callback()
		end,
		GetNumChatWindows = function()
			return 0
		end,
		GetChatWindowInfo = function(chatFrameID)
			if chatFrameID == 3 then
				return "QuestTogether", 18
			end
			return nil
		end,
		GetChatFrameByID = function(chatFrameID)
			if chatFrameID == 3 then
				return fakeQuestFrame
			end
			return nil
		end,
	})

	WithPatchedMethod(QuestTogether, "RefreshOptionsWindow", function()
		refreshed = refreshed + 1
	end, function()
		AssertTrue(QuestTogether:HandleQuestLogChatFrameClosed(fakeQuestFrame))
	end)

	AssertEquals(QuestTogether:GetOption("chatLogDestination"), "main")
	AssertEquals(QuestTogether.db.profile.questLogChatFrameID, nil)
	AssertEquals(refreshed, 1)
end)

QuestTogether:RegisterTest("login adopts visible QuestTogether chat window as separate destination", function()
	local refreshed = 0
	local visibleFrame = {
		GetID = function()
			return 4
		end,
		GetName = function()
			return "ChatFrame4"
		end,
		IsShown = function()
			return true
		end,
	}

	QuestTogether.db.profile.chatLogDestination = "main"
	QuestTogether.db.profile.questLogChatFrameID = nil

	QuestTogether.API = CreateApiWithOverrides({
		GetNumChatWindows = function()
			return 4
		end,
		GetChatWindowInfo = function(chatFrameID)
			if chatFrameID == 4 then
				return "QuestTogether", 18
			end
			return nil
		end,
		GetChatFrameByID = function(chatFrameID)
			if chatFrameID == 4 then
				return visibleFrame
			end
			return nil
		end,
	})

	WithPatchedMethod(QuestTogether, "RefreshOptionsWindow", function()
		refreshed = refreshed + 1
	end, function()
		AssertTrue(QuestTogether:ReconcileQuestLogChatDestination())
	end)

	AssertEquals(QuestTogether:GetOption("chatLogDestination"), "separate")
	AssertEquals(QuestTogether.db.profile.questLogChatFrameID, 4)
	AssertEquals(refreshed, 1)
end)

QuestTogether:RegisterTest("bubble test announcement uses target player when available", function()
	local sent = {}
	QuestTogether.isEnabled = true
	QuestTogether.API = CreateApiWithOverrides({
		GetChannelName = function(channelName)
			AssertEquals(channelName, QuestTogether.announcementChannelName)
			return 7
		end,
		SendAddonMessage = function(prefix, message, channel, target)
			sent[#sent + 1] = {
				prefix = prefix,
				message = message,
				channel = channel,
				target = target,
			}
			return 0
		end,
		UnitFullName = function(unitToken)
			AssertEquals(unitToken, "player")
			return "MyPlayer", "Realm"
		end,
		UnitClass = function(unitToken)
			AssertEquals(unitToken, "player")
			return "Mage", "MAGE"
		end,
		UnitGUID = function(unitToken)
			AssertEquals(unitToken, "player")
			return "Player-1-ABC"
		end,
	})

	local success = QuestTogether:SendAnnouncementEvent("QUEST_PROGRESS", "8/8 Lightblooming Bulb")
	AssertTrue(success)
	AssertEquals(#sent, 1)
	AssertEquals(sent[1].prefix, QuestTogether.commPrefix)
	AssertEquals(sent[1].channel, "CHANNEL")
	AssertEquals(sent[1].target, 7)
	AssertTrue(string.find(sent[1].message, "^ANN|", 1) ~= nil)
end)

QuestTogether:RegisterTest("publish announcement sends even when local option is disabled", function()
	local sent = {}
	local printed = {}
	QuestTogether.isEnabled = true
	QuestTogether.db.profile.announceRemoved = false
	QuestTogether.db.profile.showChatBubbles = false
	QuestTogether.db.profile.showChatLogs = true

	QuestTogether.API = CreateApiWithOverrides({
		GetChannelName = function()
			return 4
		end,
		SendAddonMessage = function(_, message)
			sent[#sent + 1] = message
			return 0
		end,
		UnitFullName = function()
			return "MyPlayer", "Realm"
		end,
		UnitClass = function()
			return "Mage", "MAGE"
		end,
		UnitGUID = function()
			return "Player-1-ABC"
		end,
	})
	QuestTogether.PrintRaw = function(_, message)
		printed[#printed + 1] = message
	end

	local success = QuestTogether:PublishAnnouncementEvent("QUEST_REMOVED", "Quest Removed: Test Quest")
	AssertTrue(success)
	AssertEquals(#sent, 1)
	AssertEquals(#printed, 0)
end)

QuestTogether:RegisterTest("publish announcement is suppressed while player is dead", function()
	local sent = 0
	local handled = 0

	QuestTogether.isEnabled = true
	QuestTogether.API = CreateApiWithOverrides({
		GetChannelName = function()
			return 4
		end,
		SendAddonMessage = function()
			sent = sent + 1
			return 0
		end,
		UnitFullName = function()
			return "MyPlayer", "Realm"
		end,
		UnitClass = function()
			return "Mage", "MAGE"
		end,
		UnitGUID = function()
			return "Player-1-ABC"
		end,
		UnitIsDeadOrGhost = function(unitToken)
			AssertEquals(unitToken, "player")
			return true
		end,
	})

	WithPatchedMethod(QuestTogether, "HandleAnnouncementEvent", function()
		handled = handled + 1
		return true
	end, function()
		local success = QuestTogether:PublishAnnouncementEvent("WORLD_QUEST_ENTERED", "World Quest Entered: Test Quest", 12345)
		AssertFalse(success)
	end)

	AssertEquals(sent, 0)
	AssertEquals(handled, 0)
end)

QuestTogether:RegisterTest("announcement channel chat filter hides QuestTogether channel messages", function()
	AssertTrue(
		QuestTogether:AnnouncementChannelChatFilter(
			nil,
			"CHAT_MSG_CHANNEL_NOTICE_USER",
			"JOINED",
			"Azethmis",
			"",
			QuestTogether.announcementChannelName,
			"",
			"",
			"",
			"1. " .. QuestTogether.announcementChannelName
		)
	)
	AssertFalse(QuestTogether:AnnouncementChannelChatFilter(nil, "CHAT_MSG_CHANNEL_NOTICE_USER", "JOINED", "Azethmis", "", "General"))
end)

QuestTogether:RegisterTest("joining announcement channel removes it from chat windows", function()
	local removed = {}

	QuestTogether.isEnabled = true
	QuestTogether.API = CreateApiWithOverrides({
		GetChannelName = function(name)
			AssertEquals(name, QuestTogether.announcementChannelName)
			return 7
		end,
		JoinPermanentChannel = function() end,
		GetNumChatWindows = function()
			return 2
		end,
		GetChatFrameByID = function(chatFrameID)
			return {
				GetID = function()
					return chatFrameID
				end,
				RemoveChannel = function(_, channelName)
					removed[#removed + 1] = tostring(chatFrameID) .. ":" .. tostring(channelName)
				end,
			}
		end,
		RemoveChatWindowChannel = function(chatFrame, channelName)
			chatFrame:RemoveChannel(channelName)
		end,
		AddMessageEventFilter = function() end,
	})

	AssertTrue(QuestTogether:EnsureAnnouncementChannelJoined())
	AssertEquals(#removed, 2)
	AssertEquals(removed[1], "1:" .. QuestTogether.announcementChannelName)
	AssertEquals(removed[2], "2:" .. QuestTogether.announcementChannelName)
end)

QuestTogether:RegisterTest("target test announcement sends target payload and handles locally as remote", function()
	local sent = {}
	local handledEvent = nil

	QuestTogether.isEnabled = true
	QuestTogether.API = CreateApiWithOverrides({
		UnitExists = function(unitToken)
			AssertEquals(unitToken, "target")
			return true
		end,
		UnitFullName = function(unitToken)
			AssertEquals(unitToken, "target")
			return "Nearby", "Realm"
		end,
		UnitClass = function(unitToken)
			AssertEquals(unitToken, "target")
			return "Mage", "MAGE"
		end,
		UnitGUID = function(unitToken)
			AssertEquals(unitToken, "target")
			return "Player-2-XYZ"
		end,
		UnitIsPlayer = function(unitToken)
			AssertEquals(unitToken, "target")
			return true
		end,
		GetChannelName = function()
			return 8
		end,
		SendAddonMessage = function(prefix, message, channel, target)
			sent[#sent + 1] = {
				prefix = prefix,
				message = message,
				channel = channel,
				target = target,
			}
			return 0
		end,
	})

	WithPatchedMethod(QuestTogether, "HandleAnnouncementEvent", function(_, eventData, isLocal)
		handledEvent = {
			eventType = eventData.eventType,
			senderGUID = eventData.senderGUID,
			classFile = eventData.classFile,
			senderName = eventData.senderName,
			text = eventData.text,
			isLocal = isLocal,
		}
		return true
	end, function()
		local ok, senderName = QuestTogether:SendBubbleAnnouncementTest("Testing nearby player bubble")
		AssertTrue(ok)
		AssertEquals(senderName, "Nearby-Realm")
	end)
	AssertEquals(#sent, 1)
	AssertEquals(sent[1].prefix, QuestTogether.commPrefix)
	AssertEquals(sent[1].channel, "CHANNEL")
	AssertEquals(sent[1].target, 8)
	AssertTrue(string.find(sent[1].message, "^ANN|", 1) ~= nil)
	AssertEquals(handledEvent.eventType, "QUEST_PROGRESS")
	AssertEquals(handledEvent.senderGUID, "Player-2-XYZ")
	AssertEquals(handledEvent.classFile, "MAGE")
	AssertEquals(handledEvent.senderName, "Nearby-Realm")
	AssertEquals(handledEvent.text, "Testing nearby player bubble")
	AssertFalse(handledEvent.isLocal)
end)

QuestTogether:RegisterTest("bubble test announcement uses explicit visible player name without target", function()
	local sentEvent = nil
	local handledEvent = nil
	local nearbyFrame = {
		GetUnit = function()
			return "nameplate7"
		end,
	}
	QuestTogether.isEnabled = true

	QuestTogether.API = CreateApiWithOverrides({
		UnitExists = function(unitToken)
			AssertEquals(unitToken, "target")
			return false
		end,
		UnitFullName = function(unitToken)
			AssertEquals(unitToken, "nameplate7")
			return "Nearby", "Realm"
		end,
		UnitClass = function(unitToken)
			AssertEquals(unitToken, "nameplate7")
			return "Mage", "MAGE"
		end,
		UnitGUID = function(unitToken)
			AssertEquals(unitToken, "nameplate7")
			return "Player-2-XYZ"
		end,
	})

	WithPatchedMethod(QuestTogether, "FindVisiblePlayerNameplateForSender", function(_, senderGUID, senderName)
		AssertEquals(senderGUID, "")
		AssertEquals(senderName, "Nearby")
		return nearbyFrame
	end, function()
		WithPatchedMethod(QuestTogether, "SendAnnouncementWireEvent", function(_, eventData)
			sentEvent = {
				eventType = eventData.eventType,
				senderGUID = eventData.senderGUID,
				classFile = eventData.classFile,
				senderName = eventData.senderName,
				text = eventData.text,
			}
			return true
		end, function()
			WithPatchedMethod(QuestTogether, "HandleAnnouncementEvent", function(_, eventData, isLocal)
				handledEvent = {
					eventType = eventData.eventType,
					senderGUID = eventData.senderGUID,
					classFile = eventData.classFile,
					senderName = eventData.senderName,
					text = eventData.text,
					isLocal = isLocal,
				}
				return true
			end, function()
				local ok, senderName = QuestTogether:SendBubbleAnnouncementTest("Testing nearby player bubble", "Nearby")
				AssertTrue(ok)
				AssertEquals(senderName, "Nearby-Realm")
			end)
		end)
	end)

	AssertTrue(sentEvent ~= nil)
	AssertEquals(sentEvent.eventType, "QUEST_PROGRESS")
	AssertEquals(sentEvent.senderGUID, "Player-2-XYZ")
	AssertEquals(sentEvent.classFile, "MAGE")
	AssertEquals(sentEvent.senderName, "Nearby-Realm")
	AssertEquals(sentEvent.text, "Testing nearby player bubble")
	AssertEquals(handledEvent.eventType, "QUEST_PROGRESS")
	AssertEquals(handledEvent.senderGUID, "Player-2-XYZ")
	AssertEquals(handledEvent.classFile, "MAGE")
	AssertEquals(handledEvent.senderName, "Nearby-Realm")
	AssertEquals(handledEvent.text, "Testing nearby player bubble")
	AssertFalse(handledEvent.isLocal)
end)

QuestTogether:RegisterTest("remote grouped sender prints chat log without nearby nameplate", function()
	local printed = {}
	QuestTogether.db.profile.showChatLogs = true
	QuestTogether.db.profile.showChatBubbles = false
	QuestTogether.db.profile.showProgressFor = "party_only"
	QuestTogether.partyMembers = {
		["Friend-Realm"] = {
			fullName = "Friend-Realm",
			classFile = "WARRIOR",
		},
	}

	QuestTogether.PrintChatLogRaw = function(_, message)
		printed[#printed + 1] = message
	end

	local handled = QuestTogether:HandleAnnouncementEvent({
		eventType = "QUEST_PROGRESS",
		senderGUID = "Player-2-DEF",
		classFile = "WARRIOR",
		senderName = "Friend-Realm",
		text = "6/8 Things",
	}, false)

	AssertTrue(handled)
	AssertEquals(#printed, 1)
	AssertTrue(string.find(printed[1], "Friend", 1, true) ~= nil)
	AssertTrue(string.find(printed[1], "|cffffd200: 6/8 Things|r", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("remote nearby nongroup sender is filtered by party only scope", function()
	local printed = 0
	QuestTogether.db.profile.showChatLogs = true
	QuestTogether.db.profile.showChatBubbles = false
	QuestTogether.db.profile.showProgressFor = "party_only"

	QuestTogether.PrintChatLogRaw = function()
		printed = printed + 1
	end

	WithPatchedMethod(QuestTogether, "FindVisiblePlayerNameplateForSender", function()
		return { UnitFrame = {} }
	end, function()
		local handled = QuestTogether:HandleAnnouncementEvent({
			eventType = "QUEST_PROGRESS",
			senderGUID = "Player-3-GHI",
			classFile = "DRUID",
			senderName = "Nearby-Realm",
			text = "2/4 Crates",
		}, false)

		AssertFalse(handled)
		AssertEquals(printed, 0)
	end)
end)

QuestTogether:RegisterTest("remote nearby sender shows bubble and chat log for party & nearby scope", function()
	local printed = {}
	local bubbleText = nil
	QuestTogether.db.profile.showChatLogs = true
	QuestTogether.db.profile.showChatBubbles = true
	QuestTogether.db.profile.showProgressFor = "party_nearby"

	QuestTogether.PrintChatLogRaw = function(_, message)
		printed[#printed + 1] = message
	end

	local nearbyFrame = { UnitFrame = {} }

	WithPatchedMethod(QuestTogether, "FindVisiblePlayerNameplateForSender", function(_, senderGUID, senderName)
		AssertEquals(senderGUID, "Player-4-JKL")
		AssertEquals(senderName, "Nearby-Realm")
		return nearbyFrame
	end, function()
		WithPatchedMethod(QuestTogether, "ShowAnnouncementBubbleOnNameplate", function(_, frame, text)
			AssertTrue(frame == nearbyFrame)
			bubbleText = text
			return true
		end, function()
			local handled = QuestTogether:HandleAnnouncementEvent({
				eventType = "QUEST_PROGRESS",
				senderGUID = "Player-4-JKL",
				classFile = "PRIEST",
				senderName = "Nearby-Realm",
				text = "4/4 Widgets",
			}, false)

			AssertTrue(handled)
			AssertEquals(#printed, 1)
			AssertEquals(bubbleText, "4/4 Widgets")
		end)
	end)
end)

QuestTogether:RegisterTest("remote nearby completion plays synced emote", function()
	local emoteCalls = {}
	QuestTogether.db.profile.emoteOnNearbyPlayerQuestCompletion = true

	QuestTogether.API = CreateApiWithOverrides({
		DoEmote = function(token, target)
			emoteCalls[#emoteCalls + 1] = token .. ":" .. tostring(target)
		end,
	})

	WithPatchedMethod(QuestTogether, "FindVisiblePlayerNameplateForSender", function()
		return nil
	end, function()
		WithPatchedMethod(QuestTogether, "FindNearbyPlayerUnitTokenForSender", function(_, senderGUID, senderName)
			AssertEquals(senderGUID, "Player-4-JKL")
			AssertEquals(senderName, "Nearby-Realm")
			return "target"
		end, function()
			WithPatchedMethod(QuestTogether, "PrintConsoleAnnouncement", function() end, function()
				AssertTrue(QuestTogether:HandleAnnouncementEvent({
					eventType = "QUEST_COMPLETED",
					senderGUID = "Player-4-JKL",
					classFile = "MAGE",
					senderName = "Nearby-Realm",
					text = "Quest Completed: Widgets",
					emoteToken = "cheer",
				}, false))
			end)
		end)
	end)

	AssertEquals(#emoteCalls, 1)
	AssertEquals(emoteCalls[1], "cheer:target")
end)

QuestTogether:RegisterTest("remote far completion does not play synced emote", function()
	local emoteCalls = 0
	QuestTogether.db.profile.emoteOnNearbyPlayerQuestCompletion = true

	QuestTogether.API = CreateApiWithOverrides({
		DoEmote = function()
			emoteCalls = emoteCalls + 1
		end,
	})

	WithPatchedMethod(QuestTogether, "FindVisiblePlayerNameplateForSender", function()
		return nil
	end, function()
		WithPatchedMethod(QuestTogether, "FindNearbyPlayerUnitTokenForSender", function()
			return nil
		end, function()
			WithPatchedMethod(QuestTogether, "IsAnnouncementSenderNearbyByLocation", function()
				return false
			end, function()
				AssertFalse(QuestTogether:HandleAnnouncementEvent({
					eventType = "QUEST_COMPLETED",
					senderGUID = "Player-4-JKL",
					classFile = "MAGE",
					senderName = "Faraway-Realm",
					text = "Quest Completed: Widgets",
					emoteToken = "cheer",
					zoneName = "Elsewhere",
					coordX = "1.0",
					coordY = "1.0",
					warMode = "1",
				}, false))
			end)
		end)
	end)

	AssertEquals(emoteCalls, 0)
end)

QuestTogether:RegisterTest("remote nearby completion emote obeys nearby-player emote option", function()
	local emoteCalls = 0
	QuestTogether.db.profile.emoteOnNearbyPlayerQuestCompletion = false

	QuestTogether.API = CreateApiWithOverrides({
		DoEmote = function()
			emoteCalls = emoteCalls + 1
		end,
	})

	WithPatchedMethod(QuestTogether, "FindVisiblePlayerNameplateForSender", function()
		return nil
	end, function()
		WithPatchedMethod(QuestTogether, "FindNearbyPlayerUnitTokenForSender", function()
			return "target"
		end, function()
			WithPatchedMethod(QuestTogether, "PrintConsoleAnnouncement", function() end, function()
				AssertTrue(QuestTogether:HandleAnnouncementEvent({
					eventType = "QUEST_COMPLETED",
					senderGUID = "Player-4-JKL",
					classFile = "MAGE",
					senderName = "Nearby-Realm",
					text = "Quest Completed: Widgets",
					emoteToken = "cheer",
				}, false))
			end)
		end)
	end)

	AssertEquals(emoteCalls, 0)
end)

QuestTogether:RegisterTest("remote sender with matching target prints chat log without a nameplate", function()
	local printed = {}
	QuestTogether.db.profile.showChatLogs = true
	QuestTogether.db.profile.showChatBubbles = false
	QuestTogether.db.profile.showProgressFor = "party_nearby"

	QuestTogether.PrintChatLogRaw = function(_, message)
		printed[#printed + 1] = message
	end

	WithPatchedMethod(QuestTogether, "FindVisiblePlayerNameplateForSender", function()
		return nil
	end, function()
		WithPatchedMethod(QuestTogether, "FindNearbyPlayerUnitTokenForSender", function(_, senderGUID, senderName)
			AssertEquals(senderGUID, "Player-9-ZZZ")
			AssertEquals(senderName, "Targeted-Realm")
			return "target"
		end, function()
			local handled = QuestTogether:HandleAnnouncementEvent({
				eventType = "QUEST_PROGRESS",
				senderGUID = "Player-9-ZZZ",
				classFile = "DRUID",
				senderName = "Targeted-Realm",
				text = "7/7 Notes",
			}, false)

			AssertTrue(handled)
			AssertEquals(#printed, 1)
			AssertTrue(string.find(printed[1], "Targeted", 1, true) ~= nil)
			AssertTrue(string.find(printed[1], "|cffffd200: 7/7 Notes|r", 1, true) ~= nil)
		end)
	end)
end)

QuestTogether:RegisterTest("remote sender nearby by location prints chat log without nameplate", function()
	local printed = {}
	QuestTogether.db.profile.showChatLogs = true
	QuestTogether.db.profile.showChatBubbles = false
	QuestTogether.db.profile.showProgressFor = "party_nearby"

	QuestTogether.PrintChatLogRaw = function(_, message)
		printed[#printed + 1] = message
	end

	WithPatchedMethod(QuestTogether, "FindVisiblePlayerNameplateForSender", function()
		return nil
	end, function()
		WithPatchedMethod(QuestTogether, "FindNearbyPlayerUnitTokenForSender", function()
			return nil
		end, function()
			WithPatchedMethod(QuestTogether, "IsAnnouncementSenderNearbyByLocation", function(_, locationInfo)
				AssertEquals(locationInfo.zoneName, "Eversong Woods")
				AssertEquals(locationInfo.coordX, "41.0")
				AssertEquals(locationInfo.coordY, "52.0")
				AssertEquals(locationInfo.warMode, "1")
				return true
			end, function()
				local handled = QuestTogether:HandleAnnouncementEvent({
					eventType = "QUEST_PROGRESS",
					senderGUID = "Player-8-LOC",
					classFile = "PALADIN",
					senderName = "NearbyCoords-Realm",
					text = "3/3 Crystals",
					zoneName = "Eversong Woods",
					coordX = "41.0",
					coordY = "52.0",
					warMode = "1",
				}, false)

				AssertTrue(handled)
				AssertEquals(#printed, 1)
				AssertTrue(string.find(printed[1], "NearbyCoords", 1, true) ~= nil)
				AssertTrue(string.find(printed[1], "|cffffd200: 3/3 Crystals|r", 1, true) ~= nil)
			end)
		end)
	end)
end)

QuestTogether:RegisterTest("remote sender with mismatched location signal stays filtered", function()
	local printed = 0
	QuestTogether.db.profile.showChatLogs = true
	QuestTogether.db.profile.showChatBubbles = false
	QuestTogether.db.profile.showProgressFor = "party_nearby"

	QuestTogether.PrintChatLogRaw = function()
		printed = printed + 1
	end

	WithPatchedMethod(QuestTogether, "FindVisiblePlayerNameplateForSender", function()
		return nil
	end, function()
		WithPatchedMethod(QuestTogether, "FindNearbyPlayerUnitTokenForSender", function()
			return nil
		end, function()
			WithPatchedMethod(QuestTogether, "IsAnnouncementSenderNearbyByLocation", function()
				return false
			end, function()
				local handled = QuestTogether:HandleAnnouncementEvent({
					eventType = "QUEST_PROGRESS",
					senderGUID = "Player-8-FAR",
					classFile = "PALADIN",
					senderName = "FarCoords-Realm",
					text = "3/3 Crystals",
					zoneName = "Eversong Woods",
					coordX = "41.0",
					coordY = "52.0",
					warMode = "0",
				}, false)

				AssertFalse(handled)
				AssertEquals(printed, 0)
			end)
		end)
	end)
end)

QuestTogether:RegisterTest("dev log all announcements prints remote sender without nearby signal", function()
	local printed = {}
	local bubbleCalls = 0
	QuestTogether.db.profile.showChatLogs = true
	QuestTogether.db.profile.showChatBubbles = true
	QuestTogether.db.profile.showProgressFor = "party_only"
	QuestTogether.db.profile.devLogAllAnnouncements = true

	QuestTogether.PrintChatLogRaw = function(_, message)
		printed[#printed + 1] = message
	end

	WithPatchedMethod(QuestTogether, "ShowAnnouncementBubbleOnNameplate", function()
		bubbleCalls = bubbleCalls + 1
		return true
	end, function()
		local handled = QuestTogether:HandleAnnouncementEvent({
			eventType = "QUEST_PROGRESS",
			senderGUID = "Player-7-DEV",
			classFile = "SHAMAN",
			senderName = "Faraway-Realm",
			text = "9/9 Mischief",
		}, false)

		AssertTrue(handled)
		AssertEquals(#printed, 1)
		AssertEquals(bubbleCalls, 0)
		AssertTrue(string.find(printed[1], "Faraway", 1, true) ~= nil)
		AssertTrue(string.find(printed[1], "|cffffd200: 9/9 Mischief|r", 1, true) ~= nil)
	end)
end)

QuestTogether:RegisterTest("local announcement hides own bubble when configured", function()
	local printed = {}
	local bubbleCalls = 0
	QuestTogether.db.profile.showChatLogs = true
	QuestTogether.db.profile.showChatBubbles = true
	QuestTogether.db.profile.hideMyOwnChatBubbles = true

	QuestTogether.PrintChatLogRaw = function(_, message)
		printed[#printed + 1] = message
	end

	WithPatchedMethod(QuestTogether, "ShowAnnouncementBubbleOnUnitNameplate", function()
		bubbleCalls = bubbleCalls + 1
		return true
	end, function()
		local handled = QuestTogether:HandleAnnouncementEvent({
			eventType = "QUEST_ACCEPTED",
			senderGUID = "Player-1-ABC",
			classFile = "MAGE",
			senderName = "MyPlayer-Realm",
			text = "Quest Accepted: Test Quest",
		}, true)

		AssertTrue(handled)
		AssertEquals(#printed, 1)
		AssertEquals(bubbleCalls, 0)
	end)
end)
