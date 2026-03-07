--[[
QuestTogether Options Panel (Esc > Options > AddOns)

This file builds a native settings panel that is registered with Blizzard's
addon settings system. There is no standalone options window.

Open it with:
- /qt
- /qt options
]]

local QuestTogether = _G.QuestTogether

-- Holds references to created controls so we can refresh their values from SavedVariables.
QuestTogether.optionControls = QuestTogether.optionControls or {}

local function CreateSectionLabel(parent, text, x, y)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	label:SetText(text)
	return label
end

local function CreateDescriptionText(parent, text, x, y, width)
	local description = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	description:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	description:SetWidth(width or 620)
	description:SetJustifyH("LEFT")
	description:SetJustifyV("TOP")
	description:SetText(text)
	return description
end

local function CreateCheckbox(parent, optionKey, labelText, tooltipText, x, y)
	local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("LEFT", checkbox, "RIGHT", 6, 0)
	label:SetText(labelText)

	if tooltipText and tooltipText ~= "" then
		checkbox.tooltipText = tooltipText
	end

	checkbox:SetScript("OnClick", function(self)
		QuestTogether:SetOption(optionKey, self:GetChecked() == true)
	end)

	return checkbox
end

local function GetChannelOptions(optionKey)
	if optionKey == "primaryChannel" then
		return QuestTogether.channelOrder
	end
	return QuestTogether:GetAllowedFallbackChannels(QuestTogether:GetOption("primaryChannel"))
end

local function CreateChannelDropdown(parent, optionKey, titleText, tooltipText, x, y)
	local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	title:SetText(titleText)

	local dropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
	dropdown:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -16, -2)

	if tooltipText and tooltipText ~= "" then
		dropdown.tooltipText = tooltipText
	end

	UIDropDownMenu_SetWidth(dropdown, 180)

	local function InitializeDropdown(_, level)
		local options = GetChannelOptions(optionKey)
		for _, channelKey in ipairs(options) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = QuestTogether:GetChannelDisplayName(channelKey)
			info.func = function()
				QuestTogether:SetOption(optionKey, channelKey)
				QuestTogether:RefreshOptionsWindow()
				CloseDropDownMenus()
			end
			info.checked = QuestTogether:GetOption(optionKey) == channelKey
			UIDropDownMenu_AddButton(info, level)
		end
	end

	dropdown.initializeMenu = InitializeDropdown
	UIDropDownMenu_Initialize(dropdown, InitializeDropdown)
	return dropdown
end

function QuestTogether:RefreshOptionsWindow()
	if not self.optionsFrame then
		return
	end

	local controls = self.optionControls
	if controls.announceAccepted then
		controls.announceAccepted:SetChecked(self:GetOption("announceAccepted"))
		controls.announceCompleted:SetChecked(self:GetOption("announceCompleted"))
		controls.announceRemoved:SetChecked(self:GetOption("announceRemoved"))
		controls.announceProgress:SetChecked(self:GetOption("announceProgress"))
		controls.doEmotes:SetChecked(self:GetOption("doEmotes"))
		controls.debugMode:SetChecked(self:GetOption("debugMode"))
	end

	if controls.primaryChannelDropdown then
		UIDropDownMenu_Initialize(controls.primaryChannelDropdown, controls.primaryChannelDropdown.initializeMenu)
		UIDropDownMenu_SetText(
			controls.primaryChannelDropdown,
			self:GetChannelDisplayName(self:GetOption("primaryChannel"))
		)
		UIDropDownMenu_Initialize(controls.fallbackChannelDropdown, controls.fallbackChannelDropdown.initializeMenu)
		UIDropDownMenu_SetText(
			controls.fallbackChannelDropdown,
			self:GetChannelDisplayName(self:GetOption("fallbackChannel"))
		)
	end
end

function QuestTogether:OpenOptionsWindow()
	if not self.optionsCategory and not self.optionsFrame then
		self:InitializeOptionsWindow()
	end

	-- Modern Retail settings API (Dragonflight+ / The War Within).
	if not (Settings and Settings.OpenToCategory and self.optionsCategory and self.optionsCategory.GetID) then
		self:Print("Settings API is unavailable; unable to open options.")
		return
	end

	Settings.OpenToCategory(self.optionsCategory:GetID())
end

function QuestTogether:InitializeOptionsWindow()
	if self.optionsFrame then
		return
	end

	-- This frame is embedded as a panel in Blizzard's Options > AddOns UI.
	local frame = CreateFrame("Frame", "QuestTogetherOptionsPanel")
	frame.name = "QuestTogether"

	-- Title + description.
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
	title:SetText("QuestTogether")

	CreateDescriptionText(
		frame,
		"QuestTogether options.",
		16,
		-42,
		680
	)

	CreateSectionLabel(frame, "Where To Announce", 16, -82)
	local primaryDropdown = CreateChannelDropdown(
		frame,
		"primaryChannel",
		"Primary Chat Channel",
		"Main channel for quest updates.",
		16,
		-106
	)
	local fallbackDropdown = CreateChannelDropdown(
		frame,
		"fallbackChannel",
		"Fallback Chat Channel",
		"Used if primary channel is unavailable.",
		250,
		-106
	)

	CreateSectionLabel(frame, "What To Announce", 16, -186)
	local announceAccepted = CreateCheckbox(
		frame,
		"announceAccepted",
		"Announce Quest Acceptance",
		"Announce when you accept a quest.",
		16,
		-210
	)
	local announceCompleted = CreateCheckbox(
		frame,
		"announceCompleted",
		"Announce Quest Completion",
		"Announce when you complete a quest.",
		16,
		-238
	)
	local announceRemoved = CreateCheckbox(
		frame,
		"announceRemoved",
		"Announce Quest Removal",
		"Announce when you remove/abandon a quest.",
		16,
		-266
	)
	local announceProgress = CreateCheckbox(
		frame,
		"announceProgress",
		"Announce Quest Progress",
		"Announce objective text changes.",
		16,
		-294
	)

	CreateSectionLabel(frame, "Miscellaneous", 16, -338)
	local doEmotes = CreateCheckbox(
		frame,
		"doEmotes",
		"Do Emotes Locally",
		"If disabled, this character never performs emotes (local completions or incoming emote events).",
		16,
		-362
	)
	local debugMode = CreateCheckbox(
		frame,
		"debugMode",
		"Debug Mode",
		"Print debug output in chat.",
		16,
		-390
	)

	local testButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	testButton:SetSize(180, 24)
	testButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -434)
	testButton:SetText("Run In-Game Tests")
	testButton:SetScript("OnClick", function()
		QuestTogether:RunTests()
	end)

	local scanButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	scanButton:SetSize(180, 24)
	scanButton:SetPoint("LEFT", testButton, "RIGHT", 10, 0)
	scanButton:SetText("Rescan Quest Log")
	scanButton:SetScript("OnClick", function()
		QuestTogether:ScanQuestLog()
	end)

	self.optionControls = {
		primaryChannelDropdown = primaryDropdown,
		fallbackChannelDropdown = fallbackDropdown,
		announceAccepted = announceAccepted,
		announceCompleted = announceCompleted,
		announceRemoved = announceRemoved,
		announceProgress = announceProgress,
		doEmotes = doEmotes,
		debugMode = debugMode,
	}

	frame:SetScript("OnShow", function()
		QuestTogether:RefreshOptionsWindow()
	end)

	self.optionsFrame = frame

	-- Register in Esc > Options > AddOns (modern Settings API only).
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
		self:Print("Settings API is unavailable; addon options could not be registered.")
		self.optionsCategory = nil
		return
	end

	local category = Settings.RegisterCanvasLayoutCategory(frame, frame.name, frame.name)
	Settings.RegisterAddOnCategory(category)
	self.optionsCategory = category

	self:RefreshOptionsWindow()
end
