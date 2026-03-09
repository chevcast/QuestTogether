--[[
QuestTogether Options Panel (Esc > Options > AddOns)
]]

local QuestTogether = _G.QuestTogether

QuestTogether.optionControls = QuestTogether.optionControls or {}

local function CreateSectionLabel(parent, text, x, y)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	label:SetText(text)
	return label
end

local function CreateCheckbox(parent, optionKey, labelText, tooltipText, x, y)
	local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("LEFT", checkbox, "RIGHT", 6, 0)
	label:SetText(labelText)
	checkbox.Label = label

	if tooltipText and tooltipText ~= "" then
		checkbox.tooltipText = tooltipText
	end

	checkbox:SetScript("OnClick", function(self)
		QuestTogether:SetOption(optionKey, self:GetChecked() == true)
		QuestTogether:RefreshOptionsWindow()
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
		QuestTogether:RefreshOptionsWindow()
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

local function CreateDropdown(parent, titleText, tooltipText, x, y, width, initializeMenu)
	local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	title:SetText(titleText)

	local dropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
	dropdown:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -16, -2)
	dropdown.initializeMenu = initializeMenu
	dropdown.title = title

	if tooltipText and tooltipText ~= "" then
		dropdown.tooltipText = tooltipText
	end

	UIDropDownMenu_SetWidth(dropdown, width or 180)
	UIDropDownMenu_Initialize(dropdown, initializeMenu)
	return dropdown
end

local function CreateShowProgressForDropdown(parent, x, y)
	return CreateDropdown(
		parent,
		"Show Progress For",
		"Choose whether to display grouped players only, or grouped plus nearby players with visible nameplates.",
		x,
		y,
		200,
		function(_, level)
			for _, value in ipairs(QuestTogether.showProgressForOrder) do
				local info = UIDropDownMenu_CreateInfo()
				info.text = QuestTogether:GetShowProgressForLabel(value)
				info.func = function()
					QuestTogether:SetOption("showProgressFor", value)
					QuestTogether:RefreshOptionsWindow()
					CloseDropDownMenus()
				end
				info.checked = QuestTogether:GetOption("showProgressFor") == value
				UIDropDownMenu_AddButton(info, level)
			end
		end
	)
end

local function CreateBubbleSizeDropdown(parent, x, y)
	return CreateDropdown(
		parent,
		"Chat Bubble Size",
		"Adjust the font size used in QuestTogether chat bubbles.",
		x,
		y,
		150,
		function(_, level)
			for _, value in ipairs(QuestTogether.chatBubbleSizeOrder) do
				local info = UIDropDownMenu_CreateInfo()
				info.text = QuestTogether:GetChatBubbleSizeLabel(value)
				info.func = function()
					QuestTogether:SetOption("chatBubbleSize", value)
					QuestTogether:RefreshOptionsWindow()
					CloseDropDownMenus()
				end
				info.checked = QuestTogether:GetOption("chatBubbleSize") == value
				UIDropDownMenu_AddButton(info, level)
			end
		end
	)
end

local function CreateBubbleDurationDropdown(parent, x, y)
	return CreateDropdown(
		parent,
		"Chat Bubble Duration",
		"How long QuestTogether bubbles stay visible before fading out.",
		x,
		y,
		150,
		function(_, level)
			for _, value in ipairs(QuestTogether.chatBubbleDurationOrder) do
				local info = UIDropDownMenu_CreateInfo()
				info.text = QuestTogether:GetChatBubbleDurationLabel(value)
				info.func = function()
					QuestTogether:SetOption("chatBubbleDuration", value)
					QuestTogether:RefreshOptionsWindow()
					CloseDropDownMenus()
				end
				info.checked = tonumber(QuestTogether:GetOption("chatBubbleDuration")) == value
				UIDropDownMenu_AddButton(info, level)
			end
		end
	)
end

local function CreateNameplateIconStyleDropdown(parent, x, y)
	return CreateDropdown(
		parent,
		"Quest Icon Style",
		"Choose where to place the quest icon on the nameplate.",
		x,
		y,
		140,
		function(_, level)
			for _, styleKey in ipairs(QuestTogether.nameplateQuestIconStyleOrder) do
				local info = UIDropDownMenu_CreateInfo()
				info.text = QuestTogether:GetNameplateQuestIconStyleLabel(styleKey)
				info.func = function()
					QuestTogether:SetOption("nameplateQuestIconStyle", styleKey)
					QuestTogether:RefreshOptionsWindow()
					CloseDropDownMenus()
				end
				info.checked = QuestTogether:GetNameplateQuestIconStyle() == styleKey
				UIDropDownMenu_AddButton(info, level)
			end
		end
	)
end

function QuestTogether:RefreshOptionsWindow()
	if not self.optionsFrame then
		return
	end

	local controls = self.optionControls
	controls.announceAccepted:SetChecked(self:GetOption("announceAccepted"))
	controls.announceCompleted:SetChecked(self:GetOption("announceCompleted"))
	controls.announceRemoved:SetChecked(self:GetOption("announceRemoved"))
	controls.announceProgress:SetChecked(self:GetOption("announceProgress"))
	controls.announceWorldQuestAreaEnter:SetChecked(self:GetOption("announceWorldQuestAreaEnter"))
	controls.announceWorldQuestAreaLeave:SetChecked(self:GetOption("announceWorldQuestAreaLeave"))
	controls.announceWorldQuestProgress:SetChecked(self:GetOption("announceWorldQuestProgress"))
	controls.announceWorldQuestCompleted:SetChecked(self:GetOption("announceWorldQuestCompleted"))
	controls.showChatBubbles:SetChecked(self:GetOption("showChatBubbles"))
	controls.hideMyOwnChatBubbles:SetChecked(self:GetOption("hideMyOwnChatBubbles"))
	controls.showChatLogs:SetChecked(self:GetOption("showChatLogs"))
	controls.nameplateQuestIconEnabled:SetChecked(self:GetOption("nameplateQuestIconEnabled"))
	controls.nameplateQuestHealthColorEnabled:SetChecked(self:GetOption("nameplateQuestHealthColorEnabled"))
	controls.doEmotes:SetChecked(self:GetOption("doEmotes"))
	controls.debugMode:SetChecked(self:GetOption("debugMode"))

	UIDropDownMenu_Initialize(controls.showProgressForDropdown, controls.showProgressForDropdown.initializeMenu)
	UIDropDownMenu_SetText(
		controls.showProgressForDropdown,
		self:GetShowProgressForLabel(self:GetOption("showProgressFor"))
	)

	UIDropDownMenu_Initialize(controls.chatBubbleSizeDropdown, controls.chatBubbleSizeDropdown.initializeMenu)
	UIDropDownMenu_SetText(
		controls.chatBubbleSizeDropdown,
		self:GetChatBubbleSizeLabel(self:GetOption("chatBubbleSize"))
	)

	UIDropDownMenu_Initialize(controls.chatBubbleDurationDropdown, controls.chatBubbleDurationDropdown.initializeMenu)
	UIDropDownMenu_SetText(
		controls.chatBubbleDurationDropdown,
		self:GetChatBubbleDurationLabel(self:GetOption("chatBubbleDuration"))
	)

	UIDropDownMenu_Initialize(
		controls.nameplateQuestIconStyleDropdown,
		controls.nameplateQuestIconStyleDropdown.initializeMenu
	)
	UIDropDownMenu_SetText(
		controls.nameplateQuestIconStyleDropdown,
		self:GetNameplateQuestIconStyleLabel(self:GetNameplateQuestIconStyle())
	)

	local color = GetColorOption("nameplateQuestHealthColor", self.NAMEPLATE_QUEST_HEALTH_COLOR)
	controls.nameplateQuestHealthColor.ColorTexture:SetColorTexture(color.r, color.g, color.b, 1)

	if IsColorOptionAtDefault("nameplateQuestHealthColor", self.NAMEPLATE_QUEST_HEALTH_COLOR) then
		controls.resetNameplateQuestHealthColor:Hide()
	else
		controls.resetNameplateQuestHealthColor:Show()
	end

	local showBubbleControls = self:GetOption("showChatBubbles")
	controls.hideMyOwnChatBubbles:SetShown(showBubbleControls)
	controls.hideMyOwnChatBubbles.Label:SetShown(showBubbleControls)
	controls.chatBubbleSizeDropdown:SetShown(showBubbleControls)
	controls.chatBubbleDurationDropdown:SetShown(showBubbleControls)
	controls.chatBubbleSizeDropdown.title:SetShown(showBubbleControls)
	controls.chatBubbleDurationDropdown.title:SetShown(showBubbleControls)
	controls.personalBubbleEditHint:SetShown(showBubbleControls)
	controls.resetPersonalBubbleAnchor:SetShown(showBubbleControls)
end

function QuestTogether:OpenOptionsWindow()
	if not self.optionsCategory and not self.optionsFrame then
		self:InitializeOptionsWindow()
	end

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

	local frame = CreateFrame("Frame", "QuestTogetherOptionsPanel")
	frame.name = "QuestTogether"

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
	title:SetText("QuestTogether Options")

	CreateSectionLabel(frame, "What To Announce", 16, -58)
	local announceAccepted = CreateCheckbox(frame, "announceAccepted", "Announce Quest Acceptance", "", 16, -82)
	local announceCompleted = CreateCheckbox(frame, "announceCompleted", "Announce Quest Completion", "", 16, -110)
	local announceRemoved = CreateCheckbox(frame, "announceRemoved", "Announce Quest Removal", "", 16, -138)
	local announceProgress = CreateCheckbox(frame, "announceProgress", "Announce Quest Progress", "", 16, -166)
	local announceWorldQuestAreaEnter = CreateCheckbox(frame, "announceWorldQuestAreaEnter", "Announce World Quest Area Enter", "", 330, -82)
	local announceWorldQuestAreaLeave = CreateCheckbox(frame, "announceWorldQuestAreaLeave", "Announce World Quest Area Leave", "", 330, -110)
	local announceWorldQuestProgress = CreateCheckbox(frame, "announceWorldQuestProgress", "Announce World Quest Progress", "", 330, -138)
	local announceWorldQuestCompleted = CreateCheckbox(frame, "announceWorldQuestCompleted", "Announce World Quest Completed", "", 330, -166)

	CreateSectionLabel(frame, "Display", 16, -212)
	local showChatBubbles = CreateCheckbox(
		frame,
		"showChatBubbles",
		"Show Chat Bubbles",
		"Display QuestTogether bubbles over nearby players and on your personal bubble anchor.",
		16,
		-236
	)
	local hideMyOwnChatBubbles = CreateCheckbox(
		frame,
		"hideMyOwnChatBubbles",
		"Hide My Own Chat Bubbles",
		"If enabled, your client still sends local progress to others but does not show your own QuestTogether bubbles.",
		36,
		-264
	)
	local showChatLogs = CreateCheckbox(
		frame,
		"showChatLogs",
		"Show Chat Logs",
		"Print QuestTogether announcements in chat when the sender is grouped or nearby.",
		16,
		-320
	)
	local showProgressForDropdown = CreateShowProgressForDropdown(frame, 330, -236)
	local chatBubbleSizeDropdown = CreateBubbleSizeDropdown(frame, 36, -292)
	local chatBubbleDurationDropdown = CreateBubbleDurationDropdown(frame, 220, -292)
	local personalBubbleEditHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	personalBubbleEditHint:SetPoint("TOPLEFT", frame, "TOPLEFT", 36, -346)
	personalBubbleEditHint:SetJustifyH("LEFT")
	personalBubbleEditHint:SetWidth(360)
	personalBubbleEditHint:SetText("Open Blizzard Edit Mode and drag the QuestTogether Bubble anchor to move your personal bubble.")

	local resetPersonalBubbleAnchor = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	resetPersonalBubbleAnchor:SetSize(160, 22)
	resetPersonalBubbleAnchor:SetPoint("TOPLEFT", frame, "TOPLEFT", 410, -342)
	resetPersonalBubbleAnchor:SetText("Reset Bubble Position")
	resetPersonalBubbleAnchor:SetScript("OnClick", function()
		QuestTogether:ResetPersonalBubbleAnchor()
	end)

	CreateSectionLabel(frame, "Nameplates", 16, -410)
	local nameplateQuestIconEnabled = CreateCheckbox(
		frame,
		"nameplateQuestIconEnabled",
		"Quest Objective Icon",
		"Show a quest icon on default Blizzard nameplates when a unit is a quest objective.",
		16,
		-434
	)
	local nameplateQuestIconStyleDropdown = CreateNameplateIconStyleDropdown(frame, 36, -460)
	local nameplateQuestHealthColorEnabled = CreateCheckbox(
		frame,
		"nameplateQuestHealthColorEnabled",
		"Quest Objective Health Color",
		"Tint quest-objective nameplate health bars with your selected quest color.",
		16,
		-502
	)
	local nameplateQuestHealthColor = CreateColorSwatch(
		frame,
		"nameplateQuestHealthColor",
		"Quest Health Color",
		"Choose the color used to tint quest-objective nameplate health bars.",
		QuestTogether.NAMEPLATE_QUEST_HEALTH_COLOR,
		36,
		-529
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

	CreateSectionLabel(frame, "Miscellaneous", 16, -580)
	local doEmotes = CreateCheckbox(
		frame,
		"doEmotes",
		"Quest Completion Emotes",
		"If disabled, this character never performs local completion emotes.",
		16,
		-604
	)
	local debugMode = CreateCheckbox(frame, "debugMode", "Debug Mode", "Print debug output in chat.", 16, -632)

	local testButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	testButton:SetSize(180, 24)
	testButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -674)
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
		announceAccepted = announceAccepted,
		announceCompleted = announceCompleted,
		announceRemoved = announceRemoved,
		announceProgress = announceProgress,
		announceWorldQuestAreaEnter = announceWorldQuestAreaEnter,
		announceWorldQuestAreaLeave = announceWorldQuestAreaLeave,
		announceWorldQuestProgress = announceWorldQuestProgress,
		announceWorldQuestCompleted = announceWorldQuestCompleted,
		showChatBubbles = showChatBubbles,
		hideMyOwnChatBubbles = hideMyOwnChatBubbles,
		showChatLogs = showChatLogs,
		showProgressForDropdown = showProgressForDropdown,
		chatBubbleSizeDropdown = chatBubbleSizeDropdown,
		chatBubbleDurationDropdown = chatBubbleDurationDropdown,
		personalBubbleEditHint = personalBubbleEditHint,
		resetPersonalBubbleAnchor = resetPersonalBubbleAnchor,
		nameplateQuestIconEnabled = nameplateQuestIconEnabled,
		nameplateQuestIconStyleDropdown = nameplateQuestIconStyleDropdown,
		nameplateQuestHealthColorEnabled = nameplateQuestHealthColorEnabled,
		nameplateQuestHealthColor = nameplateQuestHealthColor,
		resetNameplateQuestHealthColor = resetNameplateQuestHealthColor,
		doEmotes = doEmotes,
		debugMode = debugMode,
	}

	frame:SetScript("OnShow", function()
		QuestTogether:RefreshOptionsWindow()
	end)

	self.optionsFrame = frame

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
