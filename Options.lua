--[[
QuestTogether Options Panel (Esc > Options > AddOns)
]]

local QuestTogether = _G.QuestTogether

QuestTogether.optionControls = QuestTogether.optionControls or {}
QuestTogether.profileControls = QuestTogether.profileControls or {}
QuestTogether.profileUIState = QuestTogether.profileUIState or {}

local function CreateSectionLabel(parent, text, x, y)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	label:SetText(text)
	return label
end

local function ApplyAnnouncementGroupIcon(texture, iconType)
	if not texture then
		return
	end

	if iconType == "world" and texture.SetAtlas then
		texture:SetAtlas("worldquest-icon", true)
		texture:SetTexCoord(0, 1, 0, 1)
		return
	end

	if iconType == "bonus" and texture.SetAtlas then
		texture:SetAtlas("Bonus-Objective-Star", true)
		texture:SetTexCoord(0, 1, 0, 1)
		return
	end

	if iconType == "quest" then
		texture:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
		texture:SetTexCoord(0, 1, 0, 1)
		return
	end

	if QuestTogether.NAMEPLATE_QUEST_ICON_ATLAS and texture.SetAtlas then
		texture:SetAtlas(QuestTogether.NAMEPLATE_QUEST_ICON_ATLAS, true)
		texture:SetTexCoord(0, 1, 0, 1)
		return
	end

	texture:SetTexture(QuestTogether.NAMEPLATE_QUEST_ICON_TEXTURE)
	if QuestTogether.NAMEPLATE_QUEST_ICON_TEX_COORDS then
		local coords = QuestTogether.NAMEPLATE_QUEST_ICON_TEX_COORDS
		texture:SetTexCoord(coords.left, coords.right, coords.top, coords.bottom)
	else
		texture:SetTexCoord(0, 1, 0, 1)
	end
end

local function CreateAnnouncementGroupHeader(parent, text, iconType, x, y, width)
	local icon = parent:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	icon:SetSize(16, 16)
	ApplyAnnouncementGroupIcon(icon, iconType)

	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	label:SetText(text)

	local divider = parent:CreateTexture(nil, "BORDER")
	divider:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -8)
	divider:SetSize(width or 620, 1)
	divider:SetColorTexture(1, 1, 1, 0.12)

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
		QuestTogether:Debugf("options", "Checkbox clicked key=%s checked=%s", tostring(optionKey), tostring(self:GetChecked() == true))
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
		QuestTogether:Debugf(
			"options",
			"Color option changed key=%s r=%.3f g=%.3f b=%.3f",
			tostring(optionKey),
			tonumber(r) or 0,
			tonumber(g) or 0,
			tonumber(b) or 0
		)
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

local function CreateOptionDropdown(parent, titleText, tooltipText, x, y, width, values, getLabel, optionKey, currentValueGetter)
	return CreateDropdown(
		parent,
		titleText,
		tooltipText,
		x,
		y,
		width,
		function(_, level)
			for _, value in ipairs(values) do
				local info = UIDropDownMenu_CreateInfo()
				info.text = getLabel(value)
				info.func = function()
					QuestTogether:Debugf("options", "Dropdown selected key=%s value=%s", tostring(optionKey), tostring(value))
					QuestTogether:SetOption(optionKey, value)
					QuestTogether:RefreshOptionsWindow()
					CloseDropDownMenus()
				end
				info.checked = currentValueGetter() == value
				UIDropDownMenu_AddButton(info, level)
			end
		end
	)
end

local function CreateShowProgressForDropdown(parent, x, y)
	return CreateOptionDropdown(
		parent,
		"Show Progress For",
		"Choose whether to display grouped players only, or grouped plus nearby players with visible nameplates.",
		x,
		y,
		200,
		QuestTogether.showProgressForOrder,
		function(value)
			return QuestTogether:GetShowProgressForLabel(value)
		end,
		"showProgressFor",
		function()
			return QuestTogether:GetOption("showProgressFor")
		end
	)
end

local function CreateChatLogDestinationDropdown(parent, x, y)
	return CreateOptionDropdown(
		parent,
		"Chat Log Destination",
		"Choose whether QuestTogether chat logs print to your main chat frame or a dedicated QuestTogether chat frame.",
		x,
		y,
		190,
		QuestTogether.chatLogDestinationOrder,
		function(value)
			return QuestTogether:GetChatLogDestinationLabel(value)
		end,
		"chatLogDestination",
		function()
			return QuestTogether:GetOption("chatLogDestination")
		end
	)
end

local function CreateNameplateIconStyleDropdown(parent, x, y)
	return CreateOptionDropdown(
		parent,
		"Quest Icon Style",
		"Choose where to place the quest icon on the nameplate.",
		x,
		y,
		140,
		QuestTogether.nameplateQuestIconStyleOrder,
		function(styleKey)
			return QuestTogether:GetNameplateQuestIconStyleLabel(styleKey)
		end,
		"nameplateQuestIconStyle",
		function()
			return QuestTogether:GetNameplateQuestIconStyle()
		end
	)
end

local CHECKBOX_OPTION_KEYS = {
	"announceAccepted",
	"announceCompleted",
	"announceReadyToTurnIn",
	"announceRemoved",
	"announceProgress",
	"announceWorldQuestAreaEnter",
	"announceWorldQuestAreaLeave",
	"announceWorldQuestProgress",
	"announceWorldQuestCompleted",
	"announceBonusObjectiveAreaEnter",
	"announceBonusObjectiveAreaLeave",
	"announceBonusObjectiveProgress",
	"announceBonusObjectiveCompleted",
	"showChatBubbles",
	"hideMyOwnChatBubbles",
	"showChatLogs",
	"nameplateQuestIconEnabled",
	"nameplateQuestHealthColorEnabled",
	"emoteOnQuestCompletion",
	"emoteOnNearbyPlayerQuestCompletion",
	"debugMode",
}

local function RefreshCheckboxOptions(controls)
	for _, optionKey in ipairs(CHECKBOX_OPTION_KEYS) do
		local control = controls[optionKey]
		if control then
			control:SetChecked(QuestTogether:GetOption(optionKey))
		end
	end
end

local function RefreshDropdownControl(dropdown, labelText)
	UIDropDownMenu_Initialize(dropdown, dropdown.initializeMenu)
	UIDropDownMenu_SetText(dropdown, labelText)
end

function QuestTogether:RefreshOptionsWindow()
	if not self.optionsFrame then
		return
	end
	self:Debug("Refreshing options window", "options")

	local controls = self.optionControls
	RefreshCheckboxOptions(controls)

	RefreshDropdownControl(
		controls.showProgressForDropdown,
		self:GetShowProgressForLabel(self:GetOption("showProgressFor"))
	)

	RefreshDropdownControl(
		controls.chatLogDestinationDropdown,
		self:GetChatLogDestinationLabel(self:GetOption("chatLogDestination"))
	)

	RefreshDropdownControl(
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
	controls.personalBubbleEditHint:SetShown(showBubbleControls)
	controls.openHudEditMode:SetShown(showBubbleControls)

	local showChatLogControls = self:GetOption("showChatLogs")
	if UIDropDownMenu_EnableDropDown and UIDropDownMenu_DisableDropDown then
		if showChatLogControls then
			UIDropDownMenu_EnableDropDown(controls.chatLogDestinationDropdown)
		else
			UIDropDownMenu_DisableDropDown(controls.chatLogDestinationDropdown)
		end
	end
	controls.chatLogDestinationDropdown:SetAlpha(showChatLogControls and 1 or 0.5)
	controls.chatLogDestinationDropdown.title:SetAlpha(showChatLogControls and 1 or 0.5)
end

local function BuildProfileKeyList(excludedKey)
	local profileKeys = QuestTogether:GetProfileKeys()
	local filtered = {}
	for _, profileKey in ipairs(profileKeys) do
		if profileKey ~= excludedKey then
			filtered[#filtered + 1] = profileKey
		end
	end
	return filtered
end

function QuestTogether:RefreshProfilesWindow()
	if not self.profilesFrame then
		return
	end

	local controls = self.profileControls
	local uiState = self.profileUIState or {}
	self.profileUIState = uiState

	local currentProfileKey = self:GetCurrentProfileKey()
	local allProfileKeys = self:GetProfileKeys()
	local nonActiveProfileKeys = BuildProfileKeyList(currentProfileKey)

	if not uiState.copyFromProfileKey or uiState.copyFromProfileKey == currentProfileKey then
		uiState.copyFromProfileKey = nonActiveProfileKeys[1]
	end
	if not uiState.deleteProfileKey or uiState.deleteProfileKey == currentProfileKey then
		uiState.deleteProfileKey = nonActiveProfileKeys[1]
	end

	RefreshDropdownControl(controls.currentProfileDropdown, currentProfileKey or "None")
	RefreshDropdownControl(controls.copyFromProfileDropdown, uiState.copyFromProfileKey or "No Other Profiles")
	RefreshDropdownControl(controls.deleteProfileDropdown, uiState.deleteProfileKey or "No Other Profiles")

	local canCopy = uiState.copyFromProfileKey ~= nil
	local canDelete = uiState.deleteProfileKey ~= nil

	if UIDropDownMenu_EnableDropDown and UIDropDownMenu_DisableDropDown then
		if canCopy then
			UIDropDownMenu_EnableDropDown(controls.copyFromProfileDropdown)
		else
			UIDropDownMenu_DisableDropDown(controls.copyFromProfileDropdown)
		end

		if canDelete then
			UIDropDownMenu_EnableDropDown(controls.deleteProfileDropdown)
		else
			UIDropDownMenu_DisableDropDown(controls.deleteProfileDropdown)
		end
	end

	controls.copyButton:SetEnabled(canCopy)
	controls.deleteButton:SetEnabled(canDelete)

	local characterKey = tostring(self.activeCharacterKey or self:GetCurrentCharacterKey() or "Unknown")
	controls.profileSummary:SetText(
		string.format("Character: %s\nActive profile: %s\nSaved profiles: %d", characterKey, tostring(currentProfileKey), #allProfileKeys)
	)
end

function QuestTogether:InitializeProfilesWindow(parentCategory)
	if self.profilesFrame then
		return
	end

	local frame = CreateFrame("Frame", "QuestTogetherProfilesPanel")
	frame.name = "Profiles"
	frame.parent = "QuestTogether"

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
	title:SetText("QuestTogether Profiles")

	local description = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	description:SetWidth(640)
	description:SetJustifyH("LEFT")
	description:SetText(
		"QuestTogether now defaults each character to its own profile. Use this page to switch, copy, create, reset, or delete profiles."
	)

	local currentProfileDropdown = CreateDropdown(
		frame,
		"Current Profile",
		"Switch this character to another profile.",
		16,
		-92,
		240,
		function(_, level)
			local currentProfileKey = QuestTogether:GetCurrentProfileKey()
			for _, profileKey in ipairs(QuestTogether:GetProfileKeys()) do
				local info = UIDropDownMenu_CreateInfo()
				info.text = profileKey
				info.checked = profileKey == currentProfileKey
				info.func = function()
					local ok, err = QuestTogether:SetActiveProfile(profileKey)
					if not ok then
						QuestTogether:Print(tostring(err))
					end
					QuestTogether:RefreshProfilesWindow()
					CloseDropDownMenus()
				end
				UIDropDownMenu_AddButton(info, level)
			end
		end
	)

	local copyFromDropdown = CreateDropdown(
		frame,
		"Copy Into Current Profile",
		"Pick another profile, then click Copy.",
		16,
		-160,
		240,
		function(_, level)
			local currentProfileKey = QuestTogether:GetCurrentProfileKey()
			for _, profileKey in ipairs(BuildProfileKeyList(currentProfileKey)) do
				local info = UIDropDownMenu_CreateInfo()
				info.text = profileKey
				info.checked = QuestTogether.profileUIState.copyFromProfileKey == profileKey
				info.func = function()
					QuestTogether.profileUIState.copyFromProfileKey = profileKey
					QuestTogether:RefreshProfilesWindow()
					CloseDropDownMenus()
				end
				UIDropDownMenu_AddButton(info, level)
			end
		end
	)

	local copyButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	copyButton:SetSize(90, 22)
	copyButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 280, -186)
	copyButton:SetText("Copy")
	copyButton:SetScript("OnClick", function()
		local sourceProfileKey = QuestTogether.profileUIState.copyFromProfileKey
		local ok, err = QuestTogether:CopyProfileIntoActiveProfile(sourceProfileKey)
		if not ok then
			QuestTogether:Print(tostring(err))
			return
		end
		QuestTogether:Print("Copied profile settings from " .. tostring(sourceProfileKey) .. ".")
		QuestTogether:RefreshProfilesWindow()
	end)

	local createProfileTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	createProfileTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -240)
	createProfileTitle:SetText("Create And Switch To New Profile")

	local createProfileEdit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	createProfileEdit:SetAutoFocus(false)
	createProfileEdit:SetSize(240, 24)
	createProfileEdit:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -264)
	createProfileEdit:SetTextInsets(6, 6, 0, 0)

	local createProfileButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	createProfileButton:SetSize(90, 22)
	createProfileButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 280, -266)
	createProfileButton:SetText("Create")

	local function CreateAndActivateProfile()
		local requestedProfileName = createProfileEdit:GetText() or ""
		local ok, err = QuestTogether:CreateProfile(requestedProfileName, QuestTogether:GetCurrentProfileKey())
		if not ok then
			QuestTogether:Print(tostring(err))
			return
		end

		local switchOk, switchErr = QuestTogether:SetActiveProfile(requestedProfileName)
		if not switchOk then
			QuestTogether:Print(tostring(switchErr))
			return
		end

		createProfileEdit:SetText("")
		QuestTogether:Print("Created and switched to profile " .. tostring(QuestTogether:GetCurrentProfileKey()) .. ".")
		QuestTogether:RefreshProfilesWindow()
	end

	createProfileButton:SetScript("OnClick", CreateAndActivateProfile)
	createProfileEdit:SetScript("OnEnterPressed", function(self)
		CreateAndActivateProfile()
		self:ClearFocus()
	end)

	local resetButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	resetButton:SetSize(180, 22)
	resetButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -314)
	resetButton:SetText("Reset Active Profile")
	resetButton:SetScript("OnClick", function()
		local ok, err = QuestTogether:ResetActiveProfile()
		if not ok then
			QuestTogether:Print(tostring(err))
			return
		end
		QuestTogether:Print("Reset profile " .. tostring(QuestTogether:GetCurrentProfileKey()) .. " to defaults.")
		QuestTogether:RefreshProfilesWindow()
	end)

	local deleteProfileDropdown = CreateDropdown(
		frame,
		"Delete Profile",
		"Pick another profile, then click Delete.",
		16,
		-370,
		240,
		function(_, level)
			local currentProfileKey = QuestTogether:GetCurrentProfileKey()
			for _, profileKey in ipairs(BuildProfileKeyList(currentProfileKey)) do
				local info = UIDropDownMenu_CreateInfo()
				info.text = profileKey
				info.checked = QuestTogether.profileUIState.deleteProfileKey == profileKey
				info.func = function()
					QuestTogether.profileUIState.deleteProfileKey = profileKey
					QuestTogether:RefreshProfilesWindow()
					CloseDropDownMenus()
				end
				UIDropDownMenu_AddButton(info, level)
			end
		end
	)

	local deleteButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	deleteButton:SetSize(90, 22)
	deleteButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 280, -396)
	deleteButton:SetText("Delete")
	deleteButton:SetScript("OnClick", function()
		local deleteProfileKey = QuestTogether.profileUIState.deleteProfileKey
		local ok, err = QuestTogether:DeleteProfile(deleteProfileKey)
		if not ok then
			QuestTogether:Print(tostring(err))
			return
		end
		QuestTogether:Print("Deleted profile " .. tostring(deleteProfileKey) .. ".")
		QuestTogether.profileUIState.deleteProfileKey = nil
		QuestTogether.profileUIState.copyFromProfileKey = nil
		QuestTogether:RefreshProfilesWindow()
	end)

	local profileSummary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	profileSummary:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -448)
	profileSummary:SetWidth(640)
	profileSummary:SetJustifyH("LEFT")
	profileSummary:SetText("")

	self.profileControls = {
		currentProfileDropdown = currentProfileDropdown,
		copyFromProfileDropdown = copyFromDropdown,
		copyButton = copyButton,
		createProfileEdit = createProfileEdit,
		createProfileButton = createProfileButton,
		resetButton = resetButton,
		deleteProfileDropdown = deleteProfileDropdown,
		deleteButton = deleteButton,
		profileSummary = profileSummary,
	}
	self.profilesFrame = frame

	frame:SetScript("OnShow", function()
		QuestTogether:RefreshProfilesWindow()
	end)

	local profileCategory = nil
	if Settings and Settings.RegisterCanvasLayoutSubcategory and parentCategory then
		local ok, categoryOrError = pcall(Settings.RegisterCanvasLayoutSubcategory, parentCategory, frame, frame.name, frame.name)
		if ok then
			profileCategory = categoryOrError
		end
		if not profileCategory then
			ok, categoryOrError = pcall(Settings.RegisterCanvasLayoutSubcategory, parentCategory, frame, frame.name)
			if ok then
				profileCategory = categoryOrError
			end
		end
	end
	if not profileCategory and Settings and Settings.RegisterCanvasLayoutCategory then
		profileCategory = Settings.RegisterCanvasLayoutCategory(frame, "QuestTogether Profiles", "QuestTogether Profiles")
	end
	if profileCategory and Settings and Settings.RegisterAddOnCategory then
		Settings.RegisterAddOnCategory(profileCategory)
	end

	self.profilesCategory = profileCategory
	self:RefreshProfilesWindow()
end

function QuestTogether:OpenOptionsWindow()
	if not self.optionsCategory and not self.optionsFrame then
		self:InitializeOptionsWindow()
	end

	if not (Settings and Settings.OpenToCategory and self.optionsCategory and self.optionsCategory.GetID) then
		self:Print("Settings API is unavailable; unable to open options.")
		return
	end

	self:Debug("Opening addon options category", "options")
	Settings.OpenToCategory(self.optionsCategory:GetID())
end

function QuestTogether:InitializeOptionsWindow()
	if self.optionsFrame then
		return
	end
	self:Debug("Initializing options window", "options")

	local frame = CreateFrame("Frame", "QuestTogetherOptionsPanel")
	frame.name = "QuestTogether"

	local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
	scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 8)

	local content = CreateFrame("Frame", nil, scrollFrame)
	content:SetSize(680, 1160)
	scrollFrame:SetScrollChild(content)
	frame.ScrollFrame = scrollFrame
	frame.Content = content

	local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -16)
	title:SetText("QuestTogether Options")

	CreateSectionLabel(content, "What To Announce", 16, -58)
	CreateAnnouncementGroupHeader(content, "Quests", "quest", 16, -86, 620)
	local announceAccepted = CreateCheckbox(content, "announceAccepted", "Announce Quest Acceptance", "", 32, -116)
	local announceCompleted = CreateCheckbox(content, "announceCompleted", "Announce Quest Completion", "", 32, -144)
	local announceReadyToTurnIn =
		CreateCheckbox(content, "announceReadyToTurnIn", "Announce Ready To Turn In", "", 32, -172)
	local announceRemoved = CreateCheckbox(content, "announceRemoved", "Announce Quest Removal", "", 32, -200)
	local announceProgress = CreateCheckbox(content, "announceProgress", "Announce Quest Progress", "", 32, -228)

	CreateAnnouncementGroupHeader(content, "World Quests", "world", 16, -274, 620)
	local announceWorldQuestAreaEnter =
		CreateCheckbox(content, "announceWorldQuestAreaEnter", "Announce Area Enter", "", 32, -304)
	local announceWorldQuestAreaLeave =
		CreateCheckbox(content, "announceWorldQuestAreaLeave", "Announce Area Leave", "", 32, -332)
	local announceWorldQuestProgress =
		CreateCheckbox(content, "announceWorldQuestProgress", "Announce Progress", "", 32, -360)
	local announceWorldQuestCompleted =
		CreateCheckbox(content, "announceWorldQuestCompleted", "Announce Completion", "", 32, -388)

	CreateAnnouncementGroupHeader(content, "Bonus Objectives", "bonus", 16, -434, 620)
	local announceBonusObjectiveAreaEnter =
		CreateCheckbox(content, "announceBonusObjectiveAreaEnter", "Announce Area Enter", "", 32, -464)
	local announceBonusObjectiveAreaLeave =
		CreateCheckbox(content, "announceBonusObjectiveAreaLeave", "Announce Area Leave", "", 32, -492)
	local announceBonusObjectiveProgress =
		CreateCheckbox(content, "announceBonusObjectiveProgress", "Announce Progress", "", 32, -520)
	local announceBonusObjectiveCompleted =
		CreateCheckbox(content, "announceBonusObjectiveCompleted", "Announce Completion", "", 32, -548)

	CreateSectionLabel(content, "Display", 16, -596)
	local showChatBubbles = CreateCheckbox(
		content,
		"showChatBubbles",
		"Show Chat Bubbles",
		"Display QuestTogether bubbles over nearby players and on your personal bubble anchor.",
		16,
		-620
	)
	local hideMyOwnChatBubbles = CreateCheckbox(
		content,
		"hideMyOwnChatBubbles",
		"Hide My Own Chat Bubbles",
		"If enabled, your client still sends local progress to others but does not show your own QuestTogether bubbles.",
		36,
		-648
	)
	local showChatLogs = CreateCheckbox(
		content,
		"showChatLogs",
		"Show Chat Logs",
		"Print QuestTogether announcements in chat when the sender is grouped or nearby.",
		16,
		-676
	)
	local chatLogDestinationDropdown = CreateChatLogDestinationDropdown(content, 330, -676)
	local showProgressForDropdown = CreateShowProgressForDropdown(content, 330, -620)

	local openHudEditMode = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	openHudEditMode:SetSize(180, 24)
	openHudEditMode:SetPoint("TOPLEFT", content, "TOPLEFT", 36, -708)
	openHudEditMode:SetText("Open HUD Edit Mode")
	openHudEditMode:SetScript("OnClick", function()
		QuestTogether:Debug("Open HUD Edit Mode button clicked", "options")
		if not QuestTogether:OpenHudEditMode() then
			QuestTogether:Print("HUD Edit Mode is unavailable right now.")
		end
	end)

	local personalBubbleEditHint = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	personalBubbleEditHint:SetPoint("TOPLEFT", content, "TOPLEFT", 36, -740)
	personalBubbleEditHint:SetJustifyH("LEFT")
	personalBubbleEditHint:SetWidth(520)
	personalBubbleEditHint:SetText(
		"Use HUD Edit Mode to move your personal bubble and adjust its size and duration from the QuestTogether Bubble settings panel."
	)

	CreateSectionLabel(content, "Nameplates", 16, -808)
	local nameplateQuestIconEnabled = CreateCheckbox(
		content,
		"nameplateQuestIconEnabled",
		"Quest Objective Icon",
		"Show a quest icon on default Blizzard nameplates when a unit is a quest objective.",
		16,
		-832
	)
	local nameplateQuestIconStyleDropdown = CreateNameplateIconStyleDropdown(content, 36, -858)
	local nameplateQuestHealthColorEnabled = CreateCheckbox(
		content,
		"nameplateQuestHealthColorEnabled",
		"Quest Objective Health Color",
		"Tint quest-objective nameplate health bars with your selected quest color.",
		16,
		-900
	)
	local nameplateQuestHealthColor = CreateColorSwatch(
		content,
		"nameplateQuestHealthColor",
		"Quest Health Color",
		"Choose the color used to tint quest-objective nameplate health bars.",
		QuestTogether.NAMEPLATE_QUEST_HEALTH_COLOR,
		36,
		-927
	)
	local resetNameplateQuestHealthColor = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	resetNameplateQuestHealthColor:SetSize(70, 20)
	resetNameplateQuestHealthColor:SetPoint("LEFT", nameplateQuestHealthColor, "RIGHT", 140, 0)
	resetNameplateQuestHealthColor:SetText("Reset")
	resetNameplateQuestHealthColor:SetScript("OnClick", function()
		local defaults = QuestTogether.DEFAULTS.profile.nameplateQuestHealthColor
			or QuestTogether.NAMEPLATE_QUEST_HEALTH_COLOR
		QuestTogether:Debug("Resetting nameplate quest health color to default", "options")
		QuestTogether:SetOption("nameplateQuestHealthColor", {
			r = defaults.r,
			g = defaults.g,
			b = defaults.b,
		})
		QuestTogether:RefreshOptionsWindow()
	end)

	CreateSectionLabel(content, "Miscellaneous", 16, -978)
	local emoteOnQuestCompletion = CreateCheckbox(
		content,
		"emoteOnQuestCompletion",
		"Emote On Quest Completion",
		"If disabled, this character never performs local quest completion emotes.",
		16,
		-1002
	)
	local emoteOnNearbyPlayerQuestCompletion = CreateCheckbox(
		content,
		"emoteOnNearbyPlayerQuestCompletion",
		"Emote On Nearby Player Quest Completion",
		"If disabled, this character will not mirror nearby players' quest completion emotes.",
		16,
		-1030
	)
	local debugMode = CreateCheckbox(content, "debugMode", "Debug Mode", "Print debug output in chat.", 16, -1058)

	local testButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	testButton:SetSize(180, 24)
	testButton:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -1100)
	testButton:SetText("Run In-Game Tests")
	testButton:SetScript("OnClick", function()
		QuestTogether:Debug("Run In-Game Tests button clicked", "options")
		QuestTogether:RunTests()
	end)

	local scanButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	scanButton:SetSize(180, 24)
	scanButton:SetPoint("LEFT", testButton, "RIGHT", 10, 0)
	scanButton:SetText("Rescan Quest Log")
	scanButton:SetScript("OnClick", function()
		QuestTogether:Debug("Rescan Quest Log button clicked", "options")
		QuestTogether:ScanQuestLog()
	end)

	self.optionControls = {
		announceAccepted = announceAccepted,
		announceCompleted = announceCompleted,
		announceReadyToTurnIn = announceReadyToTurnIn,
		announceRemoved = announceRemoved,
		announceProgress = announceProgress,
		announceWorldQuestAreaEnter = announceWorldQuestAreaEnter,
		announceWorldQuestAreaLeave = announceWorldQuestAreaLeave,
		announceWorldQuestProgress = announceWorldQuestProgress,
		announceWorldQuestCompleted = announceWorldQuestCompleted,
		announceBonusObjectiveAreaEnter = announceBonusObjectiveAreaEnter,
		announceBonusObjectiveAreaLeave = announceBonusObjectiveAreaLeave,
		announceBonusObjectiveProgress = announceBonusObjectiveProgress,
		announceBonusObjectiveCompleted = announceBonusObjectiveCompleted,
		showChatBubbles = showChatBubbles,
		hideMyOwnChatBubbles = hideMyOwnChatBubbles,
		showChatLogs = showChatLogs,
		chatLogDestinationDropdown = chatLogDestinationDropdown,
		showProgressForDropdown = showProgressForDropdown,
		openHudEditMode = openHudEditMode,
		personalBubbleEditHint = personalBubbleEditHint,
		nameplateQuestIconEnabled = nameplateQuestIconEnabled,
		nameplateQuestIconStyleDropdown = nameplateQuestIconStyleDropdown,
		nameplateQuestHealthColorEnabled = nameplateQuestHealthColorEnabled,
		nameplateQuestHealthColor = nameplateQuestHealthColor,
		resetNameplateQuestHealthColor = resetNameplateQuestHealthColor,
		emoteOnQuestCompletion = emoteOnQuestCompletion,
		emoteOnNearbyPlayerQuestCompletion = emoteOnNearbyPlayerQuestCompletion,
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
	self:InitializeProfilesWindow(category)

	self:RefreshOptionsWindow()
	self:RefreshProfilesWindow()
end
