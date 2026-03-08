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

local function ClampColorComponent(value, fallback)
	local numberValue = tonumber(value)
	if not numberValue then
		return fallback
	end
	if numberValue < 0 then
		return 0
	end
	if numberValue > 1 then
		return 1
	end
	return numberValue
end

local function ColorsNearlyEqual(left, right)
	return math.abs((left or 0) - (right or 0)) < 0.001
end

local function GetColorOption(optionKey, fallbackColor)
	local configuredColor = QuestTogether:GetOption(optionKey)
	if type(configuredColor) ~= "table" then
		return {
			r = fallbackColor.r,
			g = fallbackColor.g,
			b = fallbackColor.b,
		}
	end

	return {
		r = ClampColorComponent(configuredColor.r, fallbackColor.r),
		g = ClampColorComponent(configuredColor.g, fallbackColor.g),
		b = ClampColorComponent(configuredColor.b, fallbackColor.b),
	}
end

local function IsColorOptionAtDefault(optionKey, fallbackColor)
	local current = GetColorOption(optionKey, fallbackColor)
	return ColorsNearlyEqual(current.r, fallbackColor.r)
		and ColorsNearlyEqual(current.g, fallbackColor.g)
		and ColorsNearlyEqual(current.b, fallbackColor.b)
end

local function CreateColorSwatch(parent, optionKey, labelText, tooltipText, fallbackColor, x, y)
	local swatchButton = CreateFrame("Button", nil, parent)
	swatchButton:SetSize(22, 22)
	swatchButton:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

	local border = swatchButton:CreateTexture(nil, "BORDER")
	border:SetAllPoints()
	border:SetColorTexture(0, 0, 0, 1)
	swatchButton.Border = border

	local colorTexture = swatchButton:CreateTexture(nil, "ARTWORK")
	colorTexture:SetPoint("TOPLEFT", swatchButton, "TOPLEFT", 1, -1)
	colorTexture:SetPoint("BOTTOMRIGHT", swatchButton, "BOTTOMRIGHT", -1, 1)
	swatchButton.ColorTexture = colorTexture

	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("LEFT", swatchButton, "RIGHT", 8, 0)
	label:SetText(labelText)

	if tooltipText and tooltipText ~= "" then
		swatchButton.tooltipText = tooltipText
	end

	local function SetColorOption(r, g, b)
		QuestTogether:SetOption(optionKey, {
			r = ClampColorComponent(r, fallbackColor.r),
			g = ClampColorComponent(g, fallbackColor.g),
			b = ClampColorComponent(b, fallbackColor.b),
		})
		if QuestTogether.RefreshOptionsWindow then
			QuestTogether:RefreshOptionsWindow()
		else
			local nextColor = GetColorOption(optionKey, fallbackColor)
			swatchButton.ColorTexture:SetColorTexture(nextColor.r, nextColor.g, nextColor.b, 1)
		end
	end

	swatchButton:SetScript("OnClick", function()
		if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then
			QuestTogether:Print("Color picker is unavailable right now.")
			return
		end

		local currentColor = GetColorOption(optionKey, fallbackColor)
		local previousColor = {
			r = currentColor.r,
			g = currentColor.g,
			b = currentColor.b,
		}

		local info = {}
		info.r = currentColor.r
		info.g = currentColor.g
		info.b = currentColor.b
		info.hasOpacity = false
		info.swatchFunc = function()
			local r, g, b = ColorPickerFrame:GetColorRGB()
			SetColorOption(r, g, b)
		end
		info.cancelFunc = function()
			SetColorOption(previousColor.r, previousColor.g, previousColor.b)
		end
		ColorPickerFrame:SetupColorPickerAndShow(info)
	end)

	local startingColor = GetColorOption(optionKey, fallbackColor)
	swatchButton.ColorTexture:SetColorTexture(startingColor.r, startingColor.g, startingColor.b, 1)

	return swatchButton
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

local function CreateNameplateIconStyleDropdown(parent, optionKey, titleText, tooltipText, x, y)
	local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	title:SetText(titleText)

	local dropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
	dropdown:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -16, -2)

	if tooltipText and tooltipText ~= "" then
		dropdown.tooltipText = tooltipText
	end

	UIDropDownMenu_SetWidth(dropdown, 140)

	local function InitializeDropdown(_, level)
		for _, styleKey in ipairs(QuestTogether.nameplateQuestIconStyleOrder) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = QuestTogether:GetNameplateQuestIconStyleLabel(styleKey)
			info.func = function()
				QuestTogether:SetOption(optionKey, styleKey)
				QuestTogether:RefreshOptionsWindow()
				CloseDropDownMenus()
			end
			info.checked = QuestTogether:GetNameplateQuestIconStyle() == styleKey
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
		if controls.announceWorldQuestAreaEnter then
			controls.announceWorldQuestAreaEnter:SetChecked(self:GetOption("announceWorldQuestAreaEnter"))
		end
		if controls.announceWorldQuestAreaLeave then
			controls.announceWorldQuestAreaLeave:SetChecked(self:GetOption("announceWorldQuestAreaLeave"))
		end
		if controls.announceWorldQuestProgress then
			controls.announceWorldQuestProgress:SetChecked(self:GetOption("announceWorldQuestProgress"))
		end
		if controls.announceWorldQuestCompleted then
			controls.announceWorldQuestCompleted:SetChecked(self:GetOption("announceWorldQuestCompleted"))
		end
		controls.doEmotes:SetChecked(self:GetOption("doEmotes"))
		controls.debugMode:SetChecked(self:GetOption("debugMode"))
		if controls.nameplateQuestIconEnabled then
			controls.nameplateQuestIconEnabled:SetChecked(self:GetOption("nameplateQuestIconEnabled"))
		end
		if controls.nameplateQuestIconStyleDropdown then
			UIDropDownMenu_Initialize(
				controls.nameplateQuestIconStyleDropdown,
				controls.nameplateQuestIconStyleDropdown.initializeMenu
			)
			UIDropDownMenu_SetText(
				controls.nameplateQuestIconStyleDropdown,
				self:GetNameplateQuestIconStyleLabel(self:GetNameplateQuestIconStyle())
			)
		end
		if controls.nameplateQuestHealthColorEnabled then
			controls.nameplateQuestHealthColorEnabled:SetChecked(self:GetOption("nameplateQuestHealthColorEnabled"))
		end
		if controls.nameplateQuestHealthColor then
			local color = GetColorOption("nameplateQuestHealthColor", self.NAMEPLATE_QUEST_HEALTH_COLOR)
			controls.nameplateQuestHealthColor.ColorTexture:SetColorTexture(color.r, color.g, color.b, 1)
		end
		if controls.resetNameplateQuestHealthColor then
			if IsColorOptionAtDefault("nameplateQuestHealthColor", self.NAMEPLATE_QUEST_HEALTH_COLOR) then
				controls.resetNameplateQuestHealthColor:Hide()
			else
				controls.resetNameplateQuestHealthColor:Show()
			end
		end
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
	title:SetText("QuestTogether Options")

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
	local announceWorldQuestAreaEnter = CreateCheckbox(
		frame,
		"announceWorldQuestAreaEnter",
		"Announce World Quest Area Enter",
		"Announce when a world quest becomes active in your current area.",
		330,
		-210
	)
	local announceWorldQuestAreaLeave = CreateCheckbox(
		frame,
		"announceWorldQuestAreaLeave",
		"Announce World Quest Area Leave",
		"Announce when a world quest is no longer active in your current area.",
		330,
		-238
	)
	local announceWorldQuestProgress = CreateCheckbox(
		frame,
		"announceWorldQuestProgress",
		"Announce World Quest Progress",
		"Announce objective progress updates for world quests.",
		330,
		-266
	)
	local announceWorldQuestCompleted = CreateCheckbox(
		frame,
		"announceWorldQuestCompleted",
		"Announce World Quest Completed",
		"Announce world quest completion separately from normal quests.",
		330,
		-294
	)

	CreateSectionLabel(frame, "Nameplates", 16, -338)
	local nameplateQuestIconEnabled = CreateCheckbox(
		frame,
		"nameplateQuestIconEnabled",
		"Quest Objective Icon",
		"Show a quest icon on default Blizzard nameplates when a unit is a quest objective.",
		16,
		-362
	)
	local nameplateQuestIconStyleDropdown = CreateNameplateIconStyleDropdown(
		frame,
		"nameplateQuestIconStyle",
		"Quest Icon Style",
		"Choose where to place the quest icon on the nameplate.",
		36,
		-388
	)
	local nameplateQuestHealthColorEnabled = CreateCheckbox(
		frame,
		"nameplateQuestHealthColorEnabled",
		"Quest Objective Health Color",
		"Tint quest-objective nameplate health bars with your selected quest color.",
		16,
		-430
	)
	local nameplateQuestHealthColor = CreateColorSwatch(
		frame,
		"nameplateQuestHealthColor",
		"Quest Health Color",
		"Choose the color used to tint quest-objective nameplate health bars.",
		QuestTogether.NAMEPLATE_QUEST_HEALTH_COLOR,
		36,
		-457
	)
	local resetNameplateQuestHealthColor = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	resetNameplateQuestHealthColor:SetSize(70, 20)
	resetNameplateQuestHealthColor:SetPoint("LEFT", nameplateQuestHealthColor, "RIGHT", 140, 0)
	resetNameplateQuestHealthColor:SetText("Reset")
	resetNameplateQuestHealthColor:SetScript("OnClick", function()
		local defaults = QuestTogether.DEFAULTS.profile.nameplateQuestHealthColor
			or QuestTogether.NAMEPLATE_QUEST_HEALTH_COLOR
		QuestTogether:SetOption("nameplateQuestHealthColor", {
			r = defaults.r,
			g = defaults.g,
			b = defaults.b,
		})
		QuestTogether:RefreshOptionsWindow()
	end)

	CreateSectionLabel(frame, "Miscellaneous", 16, -508)
	local doEmotes = CreateCheckbox(
		frame,
		"doEmotes",
		"Quest Completion Emotes",
		"If disabled, this character never performs emotes (local completions or incoming emote events).",
		16,
		-532
	)
	local debugMode = CreateCheckbox(
		frame,
		"debugMode",
		"Debug Mode",
		"Print debug output in chat.",
		16,
		-560
	)

	local testButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	testButton:SetSize(180, 24)
	testButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -602)
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
		announceWorldQuestAreaEnter = announceWorldQuestAreaEnter,
		announceWorldQuestAreaLeave = announceWorldQuestAreaLeave,
		announceWorldQuestProgress = announceWorldQuestProgress,
		announceWorldQuestCompleted = announceWorldQuestCompleted,
		doEmotes = doEmotes,
		debugMode = debugMode,
		nameplateQuestIconEnabled = nameplateQuestIconEnabled,
		nameplateQuestIconStyleDropdown = nameplateQuestIconStyleDropdown,
		nameplateQuestHealthColorEnabled = nameplateQuestHealthColorEnabled,
		nameplateQuestHealthColor = nameplateQuestHealthColor,
		resetNameplateQuestHealthColor = resetNameplateQuestHealthColor,
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
