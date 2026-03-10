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
	local originalNameplateBaseHealthColorByUnitFrame = QuestTogether.nameplateBaseHealthColorByUnitFrame
	local originalNameplateBubbleByUnitFrame = QuestTogether.nameplateBubbleByUnitFrame
	local originalNameplateRefreshPendingByUnitToken = QuestTogether.nameplateRefreshPendingByUnitToken
	local originalNameplateHealthTintRefreshPendingByUnitToken =
		QuestTogether.nameplateHealthTintRefreshPendingByUnitToken
	local originalPrototypeBubbleScreenHostFrame = QuestTogether.prototypeBubbleScreenHostFrame
	local originalAnnouncementChannelLocalID = QuestTogether.announcementChannelLocalID
	local originalPendingPingRequests = QuestTogether.pendingPingRequests
	local originalIsLoggingOut = QuestTogether.isLoggingOut
	local originalQuestLogChatFrameID = QuestTogether.db.global.questLogChatFrameID

	if QuestTogether.UnregisterRuntimeEvents then
		QuestTogether:UnregisterRuntimeEvents()
	end
	if QuestTogether.DisableNameplateAugmentation then
		QuestTogether:DisableNameplateAugmentation()
	end

	QuestTogether.db.profile = QuestTogether:DeepCopy(QuestTogether.DEFAULTS.profile)
	QuestTogether.db.global = QuestTogether:DeepCopy(QuestTogether.DEFAULTS.global)
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
	QuestTogether.nameplateBaseHealthColorByUnitFrame = setmetatable({}, { __mode = "k" })
	QuestTogether.nameplateBubbleByUnitFrame = setmetatable({}, { __mode = "k" })
	QuestTogether.nameplateRefreshPendingByUnitToken = {}
	QuestTogether.nameplateHealthTintRefreshPendingByUnitToken = {}
	QuestTogether.prototypeBubbleScreenHostFrame = nil
	QuestTogether.announcementChannelLocalID = nil
	QuestTogether.pendingPingRequests = {}
	QuestTogether.isLoggingOut = false

	local ok, err = pcall(testFn)

	local createdQuestLogChatFrameID = QuestTogether.db
		and QuestTogether.db.global
		and QuestTogether.db.global.questLogChatFrameID
	if
		createdQuestLogChatFrameID
		and createdQuestLogChatFrameID ~= originalQuestLogChatFrameID
		and QuestTogether.CloseQuestLogChatFrame
	then
		pcall(QuestTogether.CloseQuestLogChatFrame, QuestTogether)
	end

	QuestTogether.db.profile = originalProfile
	QuestTogether.db.global = originalGlobal
	QuestTogether.API = originalAPI
	QuestTogether.Print = originalPrint
	QuestTogether.PrintRaw = originalPrintRaw
	QuestTogether.PrintChatLogRaw = originalPrintChatLogRaw
	QuestTogether.partyMembers = originalPartyMembers
	QuestTogether.partyMemberOrder = originalPartyMemberOrder
	QuestTogether.partyRosterFingerprint = originalPartyRosterFingerprint
	QuestTogether.db.profile.enabled = originalProfileEnabled
	QuestTogether.isEnabled = originalIsEnabled
	QuestTogether.worldQuestAreaStateByQuestID = originalWorldQuestAreaStateByQuestID
	QuestTogether.bonusObjectiveAreaStateByQuestID = originalBonusObjectiveAreaStateByQuestID
	QuestTogether.nameplateQuestStateByUnitToken = originalNameplateQuestStateByUnitToken
	QuestTogether.nameplateQuestObjectiveCache = originalNameplateQuestObjectiveCache
	QuestTogether.nameplateQuestTitleCache = originalNameplateQuestTitleCache
	QuestTogether.nameplateBaseHealthColorByUnitFrame = originalNameplateBaseHealthColorByUnitFrame
	QuestTogether.nameplateBubbleByUnitFrame = originalNameplateBubbleByUnitFrame
	QuestTogether.nameplateRefreshPendingByUnitToken = originalNameplateRefreshPendingByUnitToken
	QuestTogether.nameplateHealthTintRefreshPendingByUnitToken =
		originalNameplateHealthTintRefreshPendingByUnitToken
	QuestTogether.prototypeBubbleScreenHostFrame = originalPrototypeBubbleScreenHostFrame
	QuestTogether.announcementChannelLocalID = originalAnnouncementChannelLocalID
	QuestTogether.pendingPingRequests = originalPendingPingRequests
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

	self:Print(BuildTestLogMessage("Running " .. tostring(total) .. " in-game tests..."))

	for _, testCase in ipairs(self.tests) do
		local ok, err = pcall(function()
			WithIsolatedState(testCase.fn)
		end)

		if ok then
			passed = passed + 1
			self:Print(BuildTestLogMessage("[PASS] " .. testCase.name))
		else
			failed = failed + 1
			self:Print(BuildTestLogMessage("[FAIL] " .. testCase.name .. " -> " .. tostring(err)))
		end
	end

	self:Print(BuildTestLogMessage("Test summary: " .. tostring(passed) .. " passed, " .. tostring(failed) .. " failed."))
	return failed == 0
end

QuestTogether:RegisterTest("default profile contains new announcement display options", function()
	AssertTrue(QuestTogether.DEFAULTS.profile.announceAccepted ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.announceBonusObjectiveAreaEnter ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.announceBonusObjectiveAreaLeave ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.announceBonusObjectiveProgress ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.announceBonusObjectiveCompleted ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.showChatBubbles ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.hideMyOwnChatBubbles ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.showChatLogs ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.chatLogDestination ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.showProgressFor ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.chatBubbleSize ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.chatBubbleDuration ~= nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.primaryChannel == nil)
	AssertTrue(QuestTogether.DEFAULTS.profile.fallbackChannel == nil)
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

QuestTogether:RegisterTest("console announcement message includes icon and player name", function()
	local message = QuestTogether:BuildConsoleAnnouncementMessage("MyPlayer-Realm", "hello there", "MAGE")
	AssertTrue(string.find(message, "|T" .. QuestTogether.NAMEPLATE_QUEST_ICON_TEXTURE, 1, true) ~= nil)
	AssertTrue(string.find(message, "MyPlayer", 1, true) ~= nil)
	AssertTrue(string.find(message, "|cffffd200: hello there|r", 1, true) ~= nil)
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
	AssertFalse(string.find(message, "[", 1, true) ~= nil)
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
	QuestTogether.db.global.questLogChatFrameID = 3
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
	AssertEquals(QuestTogether.db.global.questLogChatFrameID, nil)
end)

QuestTogether:RegisterTest("closing QuestTogether chat window reverts chat log destination to main", function()
	local refreshed = 0
	local fakeQuestFrame = {
		GetID = function()
			return 3
		end,
	}

	QuestTogether.db.profile.chatLogDestination = "separate"
	QuestTogether.db.global.questLogChatFrameID = 3
	QuestTogether.API = CreateApiWithOverrides({
		GetChatWindowInfo = function(chatFrameID)
			if chatFrameID == 3 then
				return "QuestTogether", 18
			end
			return nil
		end,
	})

	WithPatchedMethod(QuestTogether, "RefreshOptionsWindow", function()
		refreshed = refreshed + 1
	end, function()
		AssertTrue(QuestTogether:HandleQuestLogChatFrameClosed(fakeQuestFrame))
	end)

	AssertEquals(QuestTogether.db.profile.chatLogDestination, "main")
	AssertEquals(QuestTogether.db.global.questLogChatFrameID, nil)
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

QuestTogether:RegisterTest("scan quest log prints locally and broadcasts scan status", function()
	local sent = {}
	local printed = {}

	QuestTogether.isEnabled = true
	QuestTogether.API = CreateApiWithOverrides({
		GetChannelName = function()
			return 4
		end,
		SendAddonMessage = function(_, message)
			sent[#sent + 1] = message
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
	QuestTogether.PrintChatLogRaw = function(_, message)
		printed[#printed + 1] = message
	end

	WithPatchedMethod(QuestTogether, "GetPlayerTracker", function()
		return {}
	end, function()
		WithPatchedMethod(QuestTogether, "RefreshWorldQuestAreaState", function() end, function()
			WithPatchedMethod(QuestTogether, "RefreshBonusObjectiveAreaState", function() end, function()
				WithPatchedMethod(C_QuestLog, "GetNumQuestLogEntries", function()
					return 0
				end, function()
					QuestTogether:ScanQuestLog()

					AssertEquals(#printed, 1)
					AssertTrue(string.find(printed[1], "quests are being monitored by QuestTogether.", 1, true) ~= nil)
					AssertEquals(#sent, 1)
					AssertTrue(string.find(sent[1], "^ANN|", 1) ~= nil)
					AssertTrue(string.find(sent[1], "SCAN_STATUS", 1, true) ~= nil)
				end)
			end)
		end)
	end)
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
		WithPatchedMethod(QuestTogether, "ShowPrototypeBubbleOnNameplate", function(_, frame, text)
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

	WithPatchedMethod(QuestTogether, "ShowPrototypeBubbleOnNameplate", function()
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

	WithPatchedMethod(QuestTogether, "ShowPrototypeBubbleOnUnitNameplate", function()
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
