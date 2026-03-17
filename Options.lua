--[[
QuestTogether Options Panel (Esc > Options > AddOns)
]]

local QuestTogether = _G.QuestTogether

QuestTogether.optionControls = QuestTogether.optionControls or {}
QuestTogether.announcementControls = QuestTogether.announcementControls or {}
QuestTogether.whereToAnnounceControls = QuestTogether.whereToAnnounceControls or {}
QuestTogether.questPlateControls = QuestTogether.questPlateControls or {}
QuestTogether.miscControls = QuestTogether.miscControls or {}
QuestTogether.homeControls = QuestTogether.homeControls or {}
QuestTogether.profileControls = QuestTogether.profileControls or {}
QuestTogether.profileUIState = QuestTogether.profileUIState or {}

local function SafeText(value, fallback)
	return QuestTogether:SafeToString(value, fallback or "")
end

local function IsFrameMutable(frame)
	if not frame then
		return false
	end

	-- Avoid touching forbidden Blizzard frames to reduce taint propagation.
	if frame.IsForbidden and frame:IsForbidden() then
		return false
	end

	return true
end

local QUEST_PLATE_PREVIEW_SCALE = 1.35
local QUEST_PLATE_PREVIEW_FRAME_HEIGHT = 195
local QUEST_PLATE_PREVIEW_BAR_VISUAL_SCALE = 1.25
local QUEST_PLATE_PREVIEW_RANDOM_NAMES = {
	"Koda Bug",
	"Rue Angel",
	"Pi Floof",
	"Sammy Bear",
	"Cinder Kitten",
	"Lilly Pig",
	"Booker Bean",
	"Piper Hippo",
	"Wifebeast",
	"Husblebee",
}
local NAMEPLATE_STYLE_MODERN = Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.Modern or 1
local NAMEPLATE_STYLE_BLOCK = Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.Block or 3
local NAMEPLATE_STYLE_HEALTH_FOCUS = Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.HealthFocus or 4
local NAMEPLATE_STYLE_LEGACY = Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.Legacy or 6
local NAMEPLATE_SIZE_MEDIUM = Enum and Enum.NamePlateSize and Enum.NamePlateSize.Medium or 2
local NAMEPLATE_INFO_PERCENT = Enum and Enum.NamePlateInfoDisplay and Enum.NamePlateInfoDisplay.CurrentHealthPercent or 1
local NAMEPLATE_INFO_VALUE = Enum and Enum.NamePlateInfoDisplay and Enum.NamePlateInfoDisplay.CurrentHealthValue or 2

local NAMEPLATE_PREVIEW_SCALES = {
	[1] = { horizontal = 0.75, vertical = 0.8 },
	[2] = { horizontal = 1.0, vertical = 1.0 },
	[3] = { horizontal = 1.25, vertical = 1.25 },
	[4] = { horizontal = 1.4, vertical = 1.4 },
	[5] = { horizontal = 1.6, vertical = 1.6 },
}

local function HasBit(mask, bitValue)
	if type(mask) ~= "number" or type(bitValue) ~= "number" or bitValue <= 0 then
		return false
	end

	if bit and bit.band then
		return bit.band(mask, bitValue) ~= 0
	end
	if bit32 and bit32.band then
		return bit32.band(mask, bitValue) ~= 0
	end

	local remainder = mask % (bitValue * 2)
	return remainder >= bitValue
end

local function GetNumericCVarValue(cvarName, fallbackValue)
	if not (C_CVar and C_CVar.GetCVar and type(cvarName) == "string" and cvarName ~= "") then
		return fallbackValue
	end

	local rawValue = C_CVar.GetCVar(cvarName)
	local numericValue = QuestTogether:SafeToNumber(rawValue)
	if numericValue == nil then
		return fallbackValue
	end

	return numericValue
end

local function AnchorPreviewFillTexture(texture, healthBar)
	if not (texture and healthBar and texture.ClearAllPoints and texture.SetPoint) then
		return
	end

	local fillTexture = healthBar.GetStatusBarTexture and healthBar:GetStatusBarTexture() or nil
	if not fillTexture then
		return
	end

	texture:ClearAllPoints()
	texture:SetPoint("TOPLEFT", fillTexture, "TOPLEFT", 0, 0)
	texture:SetPoint("BOTTOMLEFT", fillTexture, "BOTTOMLEFT", 0, 0)
	texture:SetPoint("TOPRIGHT", fillTexture, "TOPRIGHT", 0, 0)
	texture:SetPoint("BOTTOMRIGHT", fillTexture, "BOTTOMRIGHT", 0, 0)
end

local function GetRandomQuestPlatePreviewName()
	local totalNames = #QUEST_PLATE_PREVIEW_RANDOM_NAMES
	if totalNames <= 0 then
		return "Quest Mob"
	end

	if not (math and type(math.random) == "function") then
		return QUEST_PLATE_PREVIEW_RANDOM_NAMES[1]
	end

	local randomIndex = math.random(totalNames)
	if type(randomIndex) ~= "number" or randomIndex < 1 or randomIndex > totalNames then
		randomIndex = 1
	end

	return QUEST_PLATE_PREVIEW_RANDOM_NAMES[randomIndex]
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
		QuestTogether:Debugf(
			"options",
			"Checkbox clicked key=%s checked=%s",
			SafeText(optionKey, ""),
			SafeText(self:GetChecked() == true, "false")
		)
		QuestTogether:SetOption(optionKey, self:GetChecked() == true)
		QuestTogether:RefreshOptionsWindow()
	end)

	return checkbox
end

local function ClampColorComponent(value, fallback)
	local numberValue = QuestTogether:SafeToNumber(value)
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
			SafeText(optionKey, ""),
			QuestTogether:SafeToNumber(r) or 0,
			QuestTogether:SafeToNumber(g) or 0,
			QuestTogether:SafeToNumber(b) or 0
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
					QuestTogether:Debugf(
						"options",
						"Dropdown selected key=%s value=%s",
						SafeText(optionKey, ""),
						SafeText(value, "")
					)
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
	if type(controls) ~= "table" then
		return
	end

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

local function RefreshQuestPlatesPreview(controls)
	if type(controls) ~= "table" then
		return
	end

	local previewFrame = controls.previewFrame
	local previewUnitFrame = controls.previewUnitFrame
	if not IsFrameMutable(previewUnitFrame) or not previewUnitFrame.healthBar then
		return
	end

	if previewUnitFrame.SetScale then
		previewUnitFrame:SetScale(QUEST_PLATE_PREVIEW_SCALE)
	end

	local nameplateStyle = GetNumericCVarValue("nameplateStyle", NAMEPLATE_STYLE_MODERN)
	local nameplateSize = GetNumericCVarValue("nameplateSize", NAMEPLATE_SIZE_MEDIUM)
	local infoDisplayMask = GetNumericCVarValue("nameplateInfoDisplay", 0)
	local scaleData = NAMEPLATE_PREVIEW_SCALES[nameplateSize] or NAMEPLATE_PREVIEW_SCALES[NAMEPLATE_SIZE_MEDIUM]
	local horizontalScale = scaleData.horizontal or 1
	local verticalScale = scaleData.vertical or 1
	local largeHealthBar = nameplateStyle == NAMEPLATE_STYLE_MODERN
		or nameplateStyle == NAMEPLATE_STYLE_BLOCK
		or nameplateStyle == NAMEPLATE_STYLE_HEALTH_FOCUS
	local nameInsideHealthBar = nameplateStyle == NAMEPLATE_STYLE_MODERN or nameplateStyle == NAMEPLATE_STYLE_BLOCK
	local barWidth = math.max(120, math.floor((230 * horizontalScale * QUEST_PLATE_PREVIEW_BAR_VISUAL_SCALE) + 0.5))
	local barHeight =
		math.max(8, math.floor(((largeHealthBar and 20 or 10) * verticalScale * QUEST_PLATE_PREVIEW_BAR_VISUAL_SCALE) + 0.5))
	local nameFontSize = math.max(10, math.floor((12 * verticalScale) + 0.5))

	local healthContainer = previewUnitFrame.HealthBarsContainer
	if healthContainer and healthContainer.SetSize then
		healthContainer:SetSize(barWidth, barHeight)
		healthContainer:ClearAllPoints()
		healthContainer:SetPoint("CENTER", previewUnitFrame, "CENTER", 0, nameInsideHealthBar and 0 or -6)
	end

	if previewUnitFrame.SetSize then
		local frameWidth = barWidth + 140
		local frameHeight = math.max(72, barHeight + (nameInsideHealthBar and 34 or 50))
		previewUnitFrame:SetSize(frameWidth, frameHeight)
	end
	if previewFrame and previewUnitFrame.ClearAllPoints and previewUnitFrame.SetPoint then
		previewUnitFrame:ClearAllPoints()
		previewUnitFrame:SetPoint("CENTER", previewFrame, "CENTER", 0, 0)
	end

	local nameLabel = previewUnitFrame.name
	local healthText = previewUnitFrame.questPreviewHealthText
	if nameLabel then
		local fontPath, _, fontFlags = nameLabel:GetFont()
		if fontPath and nameLabel.SetFont then
			nameLabel:SetFont(fontPath, nameFontSize, fontFlags)
		end
		nameLabel:ClearAllPoints()
		if nameLabel.SetDrawLayer then
			nameLabel:SetDrawLayer("OVERLAY", 7)
		end
		if nameLabel.SetJustifyH then
			nameLabel:SetJustifyH("LEFT")
		end
		if nameLabel.SetWidth then
			nameLabel:SetWidth(math.max(40, barWidth - 72))
		end
		if nameInsideHealthBar and healthContainer then
			nameLabel:SetPoint("LEFT", healthContainer, "LEFT", 6, 0)
		elseif healthContainer then
			nameLabel:SetPoint("BOTTOMLEFT", healthContainer, "TOPLEFT", 6, 2)
		else
			nameLabel:SetPoint("TOP", previewUnitFrame, "TOP", 0, 0)
		end
		if nameplateStyle == NAMEPLATE_STYLE_LEGACY and nameLabel.SetTextColor then
			nameLabel:SetTextColor(1, 0, 0, 1)
		elseif nameLabel.SetTextColor then
			nameLabel:SetTextColor(1, 1, 1, 1)
		end
	end

	local healthBar = previewUnitFrame.healthBar
	local baseFill = previewUnitFrame.questPreviewBaseFillTexture
	local tintOverlay = previewUnitFrame.questPreviewTintTexture
	local tintHighlight = previewUnitFrame.questPreviewTintHighlight
	if healthBar and healthBar.SetMinMaxValues and healthBar.SetValue then
		healthBar:SetMinMaxValues(0, 100)
		healthBar:SetValue(100)
	end
	if baseFill then
		AnchorPreviewFillTexture(baseFill, healthBar)
		baseFill:Show()
	end
	if tintOverlay then
		AnchorPreviewFillTexture(tintOverlay, healthBar)
	end
	if tintHighlight then
		AnchorPreviewFillTexture(tintHighlight, healthBar)
	end

	local tintEnabled = QuestTogether:GetOption("nameplateQuestHealthColorEnabled") == true
	local enemyBarColor = { r = 0.82, g = 0.14, b = 0.14 }
	local previewBarColor = enemyBarColor
	if tintEnabled then
		previewBarColor = GetColorOption("nameplateQuestHealthColor", QuestTogether.NAMEPLATE_QUEST_HEALTH_COLOR)
	end
	if baseFill and baseFill.SetVertexColor then
		baseFill:SetVertexColor(previewBarColor.r, previewBarColor.g, previewBarColor.b, 1)
	end

	-- For preview accuracy keep the fill opaque and avoid additive tints.
	if tintOverlay and tintOverlay.Hide then
		tintOverlay:Hide()
	end
	if tintHighlight and tintHighlight.Hide then
		tintHighlight:Hide()
	end

	if healthText then
		if healthText.SetDrawLayer then
			healthText:SetDrawLayer("OVERLAY", 7)
		end
		if healthText.SetJustifyH then
			healthText:SetJustifyH("RIGHT")
		end
		healthText:ClearAllPoints()
		if nameInsideHealthBar and healthContainer then
			healthText:SetPoint("RIGHT", healthContainer, "RIGHT", -6, 0)
		elseif healthContainer then
			healthText:SetPoint("BOTTOMRIGHT", healthContainer, "TOPRIGHT", -6, 2)
		end

		local showPercent = HasBit(infoDisplayMask, NAMEPLATE_INFO_PERCENT)
		local showValue = HasBit(infoDisplayMask, NAMEPLATE_INFO_VALUE)
		if showPercent or showValue then
			if showPercent and showValue then
				healthText:SetText("241 K  100%")
			elseif showValue then
				healthText:SetText("241 K")
			else
				healthText:SetText("100%")
			end
			healthText:Show()
		else
			healthText:Hide()
		end
	end

	local previewIconFrame = controls.previewIconFrame
	local previewIcon = controls.previewIconTexture
	if not previewIconFrame or controls.previewIconOwner ~= previewUnitFrame then
		local iconParent = previewFrame or previewUnitFrame
		previewIconFrame = CreateFrame("Frame", nil, iconParent)
		previewIconFrame:SetFrameStrata("HIGH")
		local parentFrameLevel = 0
		if healthContainer and healthContainer.GetFrameLevel and QuestTogether.SafeToNumber then
			parentFrameLevel = QuestTogether:SafeToNumber(healthContainer:GetFrameLevel()) or 0
		elseif iconParent and iconParent.GetFrameLevel and QuestTogether.SafeToNumber then
			parentFrameLevel = QuestTogether:SafeToNumber(iconParent:GetFrameLevel()) or 0
		end
		previewIconFrame:SetFrameLevel(parentFrameLevel + 30)

		previewIcon = previewIconFrame:CreateTexture(nil, "OVERLAY")
		previewIcon:SetAllPoints()
		previewIconFrame.Icon = previewIcon

		controls.previewIconFrame = previewIconFrame
		controls.previewIconTexture = previewIcon
		controls.previewIconOwner = previewUnitFrame
	end

	local showIcon = QuestTogether:GetOption("nameplateQuestIconEnabled") == true
	if showIcon then
		ApplyAnnouncementGroupIcon(previewIcon, "nameplatePreview")
		if QuestTogether.ApplyNameplateQuestIconStyle then
			QuestTogether:ApplyNameplateQuestIconStyle(previewIconFrame, previewUnitFrame)
		else
			previewIconFrame:ClearAllPoints()
			previewIconFrame:SetPoint("BOTTOM", previewUnitFrame.HealthBarsContainer, "TOP", 0, 11)
		end
		previewIconFrame:Show()
	else
		previewIconFrame:Hide()
	end

	if IsFrameMutable(previewFrame) and previewFrame.Preview then
		previewFrame.Preview:SetText("Previewing - Quest Mob")
	end
end

function QuestTogether:RefreshOptionsWindow()
	self:Debug("Refreshing options window", "options")

	self:RefreshHomeWindow()
	self:RefreshAnnouncementsWindow()
	self:RefreshWhereToAnnounceWindow()
	self:RefreshQuestPlatesWindow()
	self:RefreshMiscWindow()
end

function QuestTogether:RefreshHomeWindow()
	if not self.optionsFrame then
		return
	end

	local controls = self.homeControls
	if type(controls) ~= "table" then
		return
	end

	local activeProfile = SafeText(self:GetCurrentProfileKey() or self.activeProfileKey or "Unknown", "Unknown")
	local showProgressForLabel = self:GetShowProgressForLabel(self:GetOption("showProgressFor"))
	local chatLogsEnabled = self:GetOption("showChatLogs") and "On" or "Off"
	local chatLogDestination = self:GetChatLogDestinationLabel(self:GetOption("chatLogDestination"))
	local chatBubblesEnabled = self:GetOption("showChatBubbles") and "On" or "Off"
	local questIconEnabled = self:GetOption("nameplateQuestIconEnabled") and "On" or "Off"
	local questIconStyle = self:GetNameplateQuestIconStyleLabel(self:GetNameplateQuestIconStyle())
	local questTintEnabled = self:GetOption("nameplateQuestHealthColorEnabled") and "On" or "Off"

	if controls.statusText then
		controls.statusText:SetText(
			string.format(
				"Active profile: %s\nShow progress for: %s\nChat logs: %s (%s)\nChat bubbles: %s\nQuest icon: %s (%s)\nQuest health tint: %s",
				activeProfile,
				SafeText(showProgressForLabel, "Unknown"),
				chatLogsEnabled,
				SafeText(chatLogDestination, "Unknown"),
				chatBubblesEnabled,
				questIconEnabled,
				SafeText(questIconStyle, "Unknown"),
				questTintEnabled
			)
		)
	end

	if controls.openHudEditMode then
		local bubblesEnabled = self:GetOption("showChatBubbles") == true
		controls.openHudEditMode:SetEnabled(bubblesEnabled)
		controls.openHudEditMode:SetAlpha(bubblesEnabled and 1 or 0.5)
	end
end

function QuestTogether:RefreshWhereToAnnounceWindow()
	if not self.whereToAnnounceFrame then
		return
	end

	local controls = self.whereToAnnounceControls
	RefreshCheckboxOptions(controls)

	if controls.showProgressForDropdown then
		RefreshDropdownControl(
			controls.showProgressForDropdown,
			self:GetShowProgressForLabel(self:GetOption("showProgressFor"))
		)
	end

	if controls.chatLogDestinationDropdown then
		RefreshDropdownControl(
			controls.chatLogDestinationDropdown,
			self:GetChatLogDestinationLabel(self:GetOption("chatLogDestination"))
		)
	end

	local showBubbleControls = self:GetOption("showChatBubbles")
	if controls.hideMyOwnChatBubbles then
		controls.hideMyOwnChatBubbles:SetShown(showBubbleControls)
		if controls.hideMyOwnChatBubbles.Label then
			controls.hideMyOwnChatBubbles.Label:SetShown(showBubbleControls)
		end
	end
	if controls.personalBubbleEditHint then
		controls.personalBubbleEditHint:SetShown(showBubbleControls)
	end
	if controls.openHudEditMode then
		controls.openHudEditMode:SetShown(showBubbleControls)
	end

	local showChatLogControls = self:GetOption("showChatLogs")
	if controls.chatLogDestinationDropdown then
		if UIDropDownMenu_EnableDropDown and UIDropDownMenu_DisableDropDown then
			if showChatLogControls then
				UIDropDownMenu_EnableDropDown(controls.chatLogDestinationDropdown)
			else
				UIDropDownMenu_DisableDropDown(controls.chatLogDestinationDropdown)
			end
		end
		controls.chatLogDestinationDropdown:SetAlpha(showChatLogControls and 1 or 0.5)
		if controls.chatLogDestinationDropdown.title then
			controls.chatLogDestinationDropdown.title:SetAlpha(showChatLogControls and 1 or 0.5)
		end
	end
end

function QuestTogether:RefreshQuestPlatesWindow()
	if not self.questPlatesFrame then
		return
	end

	local controls = self.questPlateControls
	RefreshCheckboxOptions(controls)

	if controls.nameplateQuestIconStyleDropdown then
		RefreshDropdownControl(
			controls.nameplateQuestIconStyleDropdown,
			self:GetNameplateQuestIconStyleLabel(self:GetNameplateQuestIconStyle())
		)
	end

	if not controls.nameplateQuestHealthColor then
		return
	end
	local color = GetColorOption("nameplateQuestHealthColor", self.NAMEPLATE_QUEST_HEALTH_COLOR)
	controls.nameplateQuestHealthColor.ColorTexture:SetColorTexture(color.r, color.g, color.b, 1)

	if controls.resetNameplateQuestHealthColor then
		if IsColorOptionAtDefault("nameplateQuestHealthColor", self.NAMEPLATE_QUEST_HEALTH_COLOR) then
			controls.resetNameplateQuestHealthColor:Hide()
		else
			controls.resetNameplateQuestHealthColor:Show()
		end
	end

	RefreshQuestPlatesPreview(controls)
end

function QuestTogether:RefreshMiscWindow()
	if not self.miscFrame then
		return
	end

	RefreshCheckboxOptions(self.miscControls)
end

function QuestTogether:RefreshAnnouncementsWindow()
	if not self.announcementsFrame then
		return
	end

	RefreshCheckboxOptions(self.announcementControls)
end

local function RegisterSubcategory(parentCategory, frame, categoryName)
	if not (Settings and Settings.RegisterCanvasLayoutSubcategory and parentCategory and frame) then
		return nil
	end

	local subcategory = nil
	local ok, categoryOrError =
		pcall(Settings.RegisterCanvasLayoutSubcategory, parentCategory, frame, categoryName, categoryName)
	if ok then
		subcategory = categoryOrError
	end
	if not subcategory then
		-- Older signatures omit the extra name parameter.
		ok, categoryOrError = pcall(Settings.RegisterCanvasLayoutSubcategory, parentCategory, frame, categoryName)
		if ok then
			subcategory = categoryOrError
		end
	end
	if not subcategory then
		return nil
	end

	if Settings.RegisterAddOnCategory then
		Settings.RegisterAddOnCategory(subcategory)
	end
	return subcategory
end

local function OpenSettingsCategory(category)
	if not (Settings and Settings.OpenToCategory and category and category.GetID) then
		return false
	end

	Settings.OpenToCategory(category:GetID())
	return true
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

	local characterKey = SafeText(self.activeCharacterKey or self:GetCurrentCharacterKey() or "Unknown", "Unknown")
	controls.profileSummary:SetText(
		string.format(
			"Character: %s\nActive profile: %s\nSaved profiles: %d",
			characterKey,
			SafeText(currentProfileKey, ""),
			#allProfileKeys
		)
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
						QuestTogether:Print(SafeText(err, "Unknown error"))
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
	if copyFromDropdown and copyFromDropdown.Button then
		copyButton:SetPoint("LEFT", copyFromDropdown.Button, "RIGHT", 16, 0)
	else
		copyButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 280, -185)
	end
	copyButton:SetText("Copy")
	copyButton:SetScript("OnClick", function()
		local sourceProfileKey = QuestTogether.profileUIState.copyFromProfileKey
		local ok, err = QuestTogether:CopyProfileIntoActiveProfile(sourceProfileKey)
		if not ok then
			QuestTogether:Print(SafeText(err, "Unknown error"))
			return
		end
		QuestTogether:Print("Copied profile settings from " .. SafeText(sourceProfileKey, "") .. ".")
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
			QuestTogether:Print(SafeText(err, "Unknown error"))
			return
		end

		local switchOk, switchErr = QuestTogether:SetActiveProfile(requestedProfileName)
		if not switchOk then
			QuestTogether:Print(SafeText(switchErr, "Unknown error"))
			return
		end

		createProfileEdit:SetText("")
		QuestTogether:Print("Created and switched to profile " .. SafeText(QuestTogether:GetCurrentProfileKey(), "") .. ".")
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
			QuestTogether:Print(SafeText(err, "Unknown error"))
			return
		end
		QuestTogether:Print("Reset profile " .. SafeText(QuestTogether:GetCurrentProfileKey(), "") .. " to defaults.")
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
	if deleteProfileDropdown and deleteProfileDropdown.Button then
		deleteButton:SetPoint("LEFT", deleteProfileDropdown.Button, "RIGHT", 16, 0)
	else
		deleteButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 280, -395)
	end
	deleteButton:SetText("Delete")
	deleteButton:SetScript("OnClick", function()
		local deleteProfileKey = QuestTogether.profileUIState.deleteProfileKey
		local ok, err = QuestTogether:DeleteProfile(deleteProfileKey)
		if not ok then
			QuestTogether:Print(SafeText(err, "Unknown error"))
			return
		end
		QuestTogether:Print("Deleted profile " .. SafeText(deleteProfileKey, "") .. ".")
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

	local profileCategory = RegisterSubcategory(parentCategory, frame, frame.name)
	if not profileCategory and Settings and Settings.RegisterCanvasLayoutCategory then
		profileCategory = Settings.RegisterCanvasLayoutCategory(frame, "QuestTogether Profiles", "QuestTogether Profiles")
	end

	self.profilesCategory = profileCategory
	self:RefreshProfilesWindow()
end

function QuestTogether:InitializeAnnouncementsWindow(parentCategory)
	if self.announcementsFrame then
		return
	end

	local frame = CreateFrame("Frame", "QuestTogetherAnnouncementsPanel")
	frame.name = "What to Announce"
	frame.parent = "QuestTogether"

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
	title:SetText("What To Announce")

	local description = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	description:SetWidth(640)
	description:SetJustifyH("LEFT")
	description:SetText("Choose exactly which quest-related events QuestTogether should broadcast to others.")

	CreateAnnouncementGroupHeader(frame, "Quests", "quest", 16, -82, 620)
	local announceAccepted = CreateCheckbox(frame, "announceAccepted", "Announce Quest Acceptance", "", 32, -112)
	local announceCompleted = CreateCheckbox(frame, "announceCompleted", "Announce Quest Completion", "", 32, -140)
	local announceReadyToTurnIn = CreateCheckbox(frame, "announceReadyToTurnIn", "Announce Ready To Turn In", "", 32, -168)
	local announceRemoved = CreateCheckbox(frame, "announceRemoved", "Announce Quest Removal", "", 32, -196)
	local announceProgress = CreateCheckbox(frame, "announceProgress", "Announce Quest Progress", "", 32, -224)

	CreateAnnouncementGroupHeader(frame, "World Quests", "world", 16, -270, 620)
	local announceWorldQuestAreaEnter =
		CreateCheckbox(frame, "announceWorldQuestAreaEnter", "Announce Area Enter", "", 32, -300)
	local announceWorldQuestAreaLeave =
		CreateCheckbox(frame, "announceWorldQuestAreaLeave", "Announce Area Leave", "", 32, -328)
	local announceWorldQuestProgress = CreateCheckbox(frame, "announceWorldQuestProgress", "Announce Progress", "", 32, -356)
	local announceWorldQuestCompleted =
		CreateCheckbox(frame, "announceWorldQuestCompleted", "Announce Completion", "", 32, -384)

	CreateAnnouncementGroupHeader(frame, "Bonus Objectives", "bonus", 16, -430, 620)
	local announceBonusObjectiveAreaEnter =
		CreateCheckbox(frame, "announceBonusObjectiveAreaEnter", "Announce Area Enter", "", 32, -460)
	local announceBonusObjectiveAreaLeave =
		CreateCheckbox(frame, "announceBonusObjectiveAreaLeave", "Announce Area Leave", "", 32, -488)
	local announceBonusObjectiveProgress =
		CreateCheckbox(frame, "announceBonusObjectiveProgress", "Announce Progress", "", 32, -516)
	local announceBonusObjectiveCompleted =
		CreateCheckbox(frame, "announceBonusObjectiveCompleted", "Announce Completion", "", 32, -544)

	self.announcementControls = {
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
	}

	frame:SetScript("OnShow", function()
		QuestTogether:RefreshAnnouncementsWindow()
	end)

	self.announcementsFrame = frame
	self.announcementsCategory = RegisterSubcategory(parentCategory, frame, frame.name)
	self:RefreshAnnouncementsWindow()
end

function QuestTogether:InitializeWhereToAnnounceWindow(parentCategory)
	if self.whereToAnnounceFrame then
		return
	end

	local frame = CreateFrame("Frame", "QuestTogetherWhereToAnnouncePanel")
	frame.name = "Where to Announce"
	frame.parent = "QuestTogether"

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
	title:SetText("Where To Announce")

	local description = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	description:SetWidth(640)
	description:SetJustifyH("LEFT")
	description:SetText("Control where QuestTogether displays progress updates and chat output.")

	local chatLogHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	chatLogHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -82)
	chatLogHeader:SetText("Chat Log Output")

	local showChatLogs = CreateCheckbox(
		frame,
		"showChatLogs",
		"Show Chat Logs",
		"Print QuestTogether announcements in chat when the sender is grouped or nearby.",
		16,
		-106
	)
	local chatLogDestinationDropdown = CreateChatLogDestinationDropdown(frame, 330, -106)
	local showProgressForDropdown = CreateShowProgressForDropdown(frame, 330, -152)

	local bubbleHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	bubbleHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -196)
	bubbleHeader:SetText("Chat Bubbles")

	local showChatBubbles = CreateCheckbox(
		frame,
		"showChatBubbles",
		"Show Chat Bubbles",
		"Display QuestTogether bubbles over nearby players and on your personal bubble anchor.",
		16,
		-220
	)
	local hideMyOwnChatBubbles = CreateCheckbox(
		frame,
		"hideMyOwnChatBubbles",
		"Hide My Own Chat Bubbles",
		"If enabled, your client still sends local progress to others but does not show your own QuestTogether bubbles.",
		36,
		-248
	)

	local openHudEditMode = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	openHudEditMode:SetSize(180, 24)
	openHudEditMode:SetPoint("TOPLEFT", frame, "TOPLEFT", 36, -280)
	openHudEditMode:SetText("Open HUD Edit Mode")
	openHudEditMode:SetScript("OnClick", function()
		QuestTogether:Debug("Open HUD Edit Mode button clicked", "options")
		if not QuestTogether:OpenHudEditMode() then
			QuestTogether:Print("HUD Edit Mode is unavailable right now.")
		end
	end)

	local personalBubbleEditHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	personalBubbleEditHint:SetPoint("TOPLEFT", frame, "TOPLEFT", 36, -312)
	personalBubbleEditHint:SetJustifyH("LEFT")
	personalBubbleEditHint:SetWidth(560)
	personalBubbleEditHint:SetText(
		"Use HUD Edit Mode to move your personal bubble and adjust its size and duration from the QuestTogether Bubble settings panel."
	)

	self.whereToAnnounceControls = {
		showChatBubbles = showChatBubbles,
		hideMyOwnChatBubbles = hideMyOwnChatBubbles,
		showChatLogs = showChatLogs,
		chatLogDestinationDropdown = chatLogDestinationDropdown,
		showProgressForDropdown = showProgressForDropdown,
		openHudEditMode = openHudEditMode,
		personalBubbleEditHint = personalBubbleEditHint,
	}
	-- Keep legacy field wired for code that still references optionControls.
	self.optionControls = self.whereToAnnounceControls
	self.whereToAnnounceFrame = frame

	frame:SetScript("OnShow", function()
		QuestTogether:RefreshWhereToAnnounceWindow()
	end)

	self.whereToAnnounceCategory = RegisterSubcategory(parentCategory, frame, frame.name)
	self:RefreshWhereToAnnounceWindow()
end

function QuestTogether:InitializeQuestPlatesWindow(parentCategory)
	if self.questPlatesFrame then
		return
	end

	local frame = CreateFrame("Frame", "QuestTogetherQuestPlatesPanel")
	frame.name = "Quest Plates"
	frame.parent = "QuestTogether"

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
	title:SetText("Quest Plates")

	local description = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	description:SetWidth(640)
	description:SetJustifyH("LEFT")
	description:SetText("Customize quest objective visuals on Blizzard nameplates.")

	local nameplateQuestIconEnabled = CreateCheckbox(
		frame,
		"nameplateQuestIconEnabled",
		"Quest Objective Icon",
		"Show a quest icon on default Blizzard nameplates when a unit is a quest objective.",
		16,
		-82
	)
	local nameplateQuestIconStyleDropdown = CreateNameplateIconStyleDropdown(frame, 36, -108)
	local nameplateQuestHealthColorEnabled = CreateCheckbox(
		frame,
		"nameplateQuestHealthColorEnabled",
		"Quest Objective Health Color",
		"Tint quest-objective nameplate health bars with your selected quest color.",
		16,
		-150
	)
	local nameplateQuestHealthColor = CreateColorSwatch(
		frame,
		"nameplateQuestHealthColor",
		"Quest Health Color",
		"Choose the color used to tint quest-objective nameplate health bars.",
		QuestTogether.NAMEPLATE_QUEST_HEALTH_COLOR,
		36,
		-177
	)
	local resetNameplateQuestHealthColor = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
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

	local previewHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	previewHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -238)
	previewHeader:SetText("Preview")

	local previewHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	previewHint:SetPoint("TOPLEFT", previewHeader, "BOTTOMLEFT", 0, -4)
	previewHint:SetWidth(640)
	previewHint:SetJustifyH("LEFT")
	previewHint:SetText("This isolated preview uses your current nameplate style CVars and quest visual settings.")

	-- Use an isolated local frame instead of Blizzard's script nameplate preview template.
	-- This avoids registering a real preview nameplate/unit token and reduces taint risk.
	local previewFrame = CreateFrame("Frame", nil, frame)
	previewFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -280)
	previewFrame:SetSize(620, QUEST_PLATE_PREVIEW_FRAME_HEIGHT)

	local previewBackground = previewFrame:CreateTexture(nil, "BACKGROUND")
	previewBackground:SetAllPoints()
	previewBackground:SetColorTexture(0.03, 0.03, 0.05, 0.62)

	local previewCaption = previewFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	previewCaption:SetPoint("TOPLEFT", previewFrame, "TOPLEFT", 16, -14)
	previewCaption:SetText("Previewing - Quest Mob")
	previewFrame.Preview = previewCaption

	local fallbackUnitFrame = CreateFrame("Frame", nil, previewFrame)
	fallbackUnitFrame:SetSize(360, 92)
	fallbackUnitFrame:SetPoint("CENTER", previewFrame, "CENTER", 0, 0)

	local fallbackHealthBarsContainer = CreateFrame("Frame", nil, fallbackUnitFrame)
	fallbackHealthBarsContainer:SetSize(260, 18)
	fallbackHealthBarsContainer:SetPoint("TOP", fallbackUnitFrame, "TOP", 0, -26)
	fallbackUnitFrame.HealthBarsContainer = fallbackHealthBarsContainer

	local fallbackHealthBar = CreateFrame("StatusBar", nil, fallbackHealthBarsContainer)
	fallbackHealthBar:SetAllPoints()
	fallbackHealthBar:SetMinMaxValues(0, 100)
	fallbackHealthBar:SetValue(100)
	fallbackHealthBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	fallbackHealthBar:SetStatusBarColor(0, 0, 0, 0)
	fallbackUnitFrame.healthBar = fallbackHealthBar

	local fallbackHealthBarBackground = fallbackHealthBar:CreateTexture(nil, "BACKGROUND")
	fallbackHealthBarBackground:SetPoint("TOPLEFT", fallbackHealthBar, "TOPLEFT", -2, 3)
	fallbackHealthBarBackground:SetPoint("BOTTOMRIGHT", fallbackHealthBar, "BOTTOMRIGHT", 6, -6)
	if fallbackHealthBarBackground.SetAtlas then
		fallbackHealthBarBackground:SetAtlas("UI-HUD-CoolDownManager-Bar-BG", true)
	else
		fallbackHealthBarBackground:SetColorTexture(0.10, 0.10, 0.10, 0.82)
	end

	local fallbackBaseFill = nil
	if QuestTogether.CreateNameplateHealthOverlayTexture then
		fallbackBaseFill = QuestTogether:CreateNameplateHealthOverlayTexture(fallbackHealthBar, "ARTWORK", 0)
	end
	if not fallbackBaseFill then
		fallbackBaseFill = fallbackHealthBar:CreateTexture(nil, "ARTWORK", nil, 0)
		if fallbackBaseFill.SetAtlas then
			fallbackBaseFill:SetAtlas(QuestTogether.NAMEPLATE_HEALTH_FILL_ATLAS or "UI-HUD-CoolDownManager-Bar", true)
		else
			fallbackBaseFill:SetTexture("Interface\\Buttons\\WHITE8X8")
		end
	end
	if fallbackBaseFill then
		fallbackBaseFill:SetVertexColor(0.22, 0.80, 0.22, 1)
		fallbackUnitFrame.questPreviewBaseFillTexture = fallbackBaseFill
	end

	local fallbackTintOverlay = nil
	if QuestTogether.CreateNameplateHealthOverlayTexture then
		fallbackTintOverlay = QuestTogether:CreateNameplateHealthOverlayTexture(fallbackHealthBar, "ARTWORK", 1)
	end
	if not fallbackTintOverlay then
		fallbackTintOverlay = fallbackHealthBar:CreateTexture(nil, "ARTWORK", nil, 1)
		if fallbackTintOverlay.SetAtlas then
			fallbackTintOverlay:SetAtlas(QuestTogether.NAMEPLATE_HEALTH_FILL_ATLAS or "UI-HUD-CoolDownManager-Bar", true)
		else
			fallbackTintOverlay:SetTexture("Interface\\Buttons\\WHITE8X8")
		end
	end
	fallbackTintOverlay:SetVertexColor(1, 0.5, 0.1, 0.32)
	fallbackTintOverlay:Hide()
	fallbackUnitFrame.questPreviewTintTexture = fallbackTintOverlay

	local fallbackTintHighlight = fallbackHealthBar:CreateTexture(nil, "ARTWORK", nil, 2)
	fallbackTintHighlight:SetAllPoints()
	fallbackTintHighlight:SetBlendMode("ADD")
	fallbackTintHighlight:SetColorTexture(1, 0.75, 0.35, 0.16)
	fallbackTintHighlight:Hide()
	fallbackUnitFrame.questPreviewTintHighlight = fallbackTintHighlight

	local fallbackDeselectedOverlay = fallbackHealthBar:CreateTexture(nil, "OVERLAY", nil, 3)
	if fallbackDeselectedOverlay.SetAtlas then
		fallbackDeselectedOverlay:SetAtlas("ui-hud-nameplates-deselected-overlay", true)
	else
		fallbackDeselectedOverlay:SetColorTexture(0.95, 0.95, 0.95, 0.16)
	end
	fallbackDeselectedOverlay:SetPoint("TOPLEFT", fallbackHealthBar, "TOPLEFT", 0, 1)
	fallbackDeselectedOverlay:SetPoint("BOTTOMRIGHT", fallbackHealthBar, "BOTTOMRIGHT", 0, -1)
	fallbackUnitFrame.questPreviewDeselectedOverlay = fallbackDeselectedOverlay

	local fallbackSelectedBorder = fallbackHealthBar:CreateTexture(nil, "OVERLAY", nil, 4)
	if fallbackSelectedBorder.SetAtlas then
		fallbackSelectedBorder:SetAtlas("UI-HUD-Nameplates-Selected", true)
	else
		fallbackSelectedBorder:SetColorTexture(0.95, 0.95, 0.95, 0.22)
	end
	fallbackSelectedBorder:SetPoint("TOPLEFT", fallbackHealthBarBackground, "TOPLEFT", -1, 1)
	fallbackSelectedBorder:SetPoint("BOTTOMRIGHT", fallbackHealthBarBackground, "BOTTOMRIGHT", -3, 3)
	fallbackSelectedBorder:Hide()
	fallbackUnitFrame.questPreviewSelectedBorder = fallbackSelectedBorder

	local fallbackTextOverlay = CreateFrame("Frame", nil, fallbackHealthBarsContainer)
	fallbackTextOverlay:SetAllPoints()
	fallbackTextOverlay:SetFrameStrata(fallbackHealthBarsContainer:GetFrameStrata() or "LOW")
	fallbackTextOverlay:SetFrameLevel((fallbackHealthBar:GetFrameLevel() or 0) + 20)
	fallbackUnitFrame.questPreviewTextOverlay = fallbackTextOverlay

	local fallbackName = fallbackTextOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fallbackName:SetPoint("LEFT", fallbackHealthBarsContainer, "LEFT", 6, 0)
	fallbackName:SetJustifyH("LEFT")
	fallbackName:SetWidth(160)
	fallbackName:SetText(GetRandomQuestPlatePreviewName())
	fallbackUnitFrame.name = fallbackName

	local fallbackHealthValue = fallbackTextOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fallbackHealthValue:SetPoint("LEFT", fallbackHealthBarsContainer, "RIGHT", 8, 0)
	fallbackHealthValue:SetText("241 K")
	fallbackHealthValue:SetJustifyH("RIGHT")
	fallbackUnitFrame.questPreviewHealthText = fallbackHealthValue

	self.questPlateControls = {
		nameplateQuestIconEnabled = nameplateQuestIconEnabled,
		nameplateQuestIconStyleDropdown = nameplateQuestIconStyleDropdown,
		nameplateQuestHealthColorEnabled = nameplateQuestHealthColorEnabled,
		nameplateQuestHealthColor = nameplateQuestHealthColor,
		resetNameplateQuestHealthColor = resetNameplateQuestHealthColor,
		previewFrame = previewFrame,
		previewNamePlate = nil,
		previewNameLabel = fallbackName,
		previewUnitFrame = fallbackUnitFrame,
	}
	self.questPlatesFrame = frame

	frame:SetScript("OnShow", function()
		local controls = QuestTogether.questPlateControls
		if controls and controls.previewNameLabel then
			controls.previewNameLabel:SetText(GetRandomQuestPlatePreviewName())
		end
		QuestTogether:RefreshQuestPlatesWindow()
	end)

	self.questPlatesCategory = RegisterSubcategory(parentCategory, frame, frame.name)
	self:RefreshQuestPlatesWindow()
end

function QuestTogether:InitializeMiscWindow(parentCategory)
	if self.miscFrame then
		return
	end

	local frame = CreateFrame("Frame", "QuestTogetherMiscPanel")
	frame.name = "Miscellaneous"
	frame.parent = "QuestTogether"

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
	title:SetText("Miscellaneous")

	local description = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	description:SetWidth(640)
	description:SetJustifyH("LEFT")
	description:SetText("Other behavior toggles and utility actions.")

	local emoteOnQuestCompletion = CreateCheckbox(
		frame,
		"emoteOnQuestCompletion",
		"Emote On Quest Completion",
		"If disabled, this character never performs local quest completion emotes.",
		16,
		-82
	)
	local emoteOnNearbyPlayerQuestCompletion = CreateCheckbox(
		frame,
		"emoteOnNearbyPlayerQuestCompletion",
		"Emote On Nearby Player Quest Completion",
		"If disabled, this character will not mirror nearby players' quest completion emotes.",
		16,
		-110
	)
	local debugMode = CreateCheckbox(frame, "debugMode", "Debug Mode", "Print debug output in chat.", 16, -138)

	local testButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	testButton:SetSize(180, 24)
	testButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -180)
	testButton:SetText("Run In-Game Tests")
	testButton:SetScript("OnClick", function()
		QuestTogether:Debug("Run In-Game Tests button clicked", "options")
		QuestTogether:RunTests()
	end)

	local scanButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	scanButton:SetSize(180, 24)
	scanButton:SetPoint("LEFT", testButton, "RIGHT", 10, 0)
	scanButton:SetText("Rescan Quest Log")
	scanButton:SetScript("OnClick", function()
		QuestTogether:Debug("Rescan Quest Log button clicked", "options")
		QuestTogether:ScanQuestLog()
	end)

	self.miscControls = {
		emoteOnQuestCompletion = emoteOnQuestCompletion,
		emoteOnNearbyPlayerQuestCompletion = emoteOnNearbyPlayerQuestCompletion,
		debugMode = debugMode,
	}
	self.miscFrame = frame

	frame:SetScript("OnShow", function()
		QuestTogether:RefreshMiscWindow()
	end)

	self.miscCategory = RegisterSubcategory(parentCategory, frame, frame.name)
	self:RefreshMiscWindow()
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

	local frame = CreateFrame("Frame", "QuestTogetherHomePanel")
	frame.name = "QuestTogether"

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
	title:SetText("QuestTogether")

	local description = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	description:SetWidth(640)
	description:SetJustifyH("LEFT")
	description:SetText(
		"QuestTogether shares quest progress between party members and nearby players so everyone can see objectives move in real time."
	)

	local statusPanel = CreateFrame("Frame", nil, frame)
	statusPanel:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -18)
	statusPanel:SetSize(360, 220)

	local statusPanelBackground = statusPanel:CreateTexture(nil, "BACKGROUND")
	statusPanelBackground:SetAllPoints()
	statusPanelBackground:SetColorTexture(0.03, 0.03, 0.05, 0.62)

	local statusPanelBorder = statusPanel:CreateTexture(nil, "BORDER")
	statusPanelBorder:SetAllPoints()
	statusPanelBorder:SetColorTexture(1, 1, 1, 0.08)

	local statusHeader = statusPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	statusHeader:SetPoint("TOPLEFT", statusPanel, "TOPLEFT", 12, -10)
	statusHeader:SetText("Quick Status")

	local statusText = statusPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	statusText:SetPoint("TOPLEFT", statusHeader, "BOTTOMLEFT", 0, -8)
	statusText:SetWidth(336)
	statusText:SetJustifyH("LEFT")
	if statusText.SetSpacing then
		statusText:SetSpacing(2)
	end
	statusText:SetText("")

	local actionsPanel = CreateFrame("Frame", nil, frame)
	actionsPanel:SetPoint("TOPLEFT", statusPanel, "TOPRIGHT", 16, 0)
	actionsPanel:SetSize(260, 220)

	local actionsPanelBackground = actionsPanel:CreateTexture(nil, "BACKGROUND")
	actionsPanelBackground:SetAllPoints()
	actionsPanelBackground:SetColorTexture(0.03, 0.03, 0.05, 0.62)

	local actionsPanelBorder = actionsPanel:CreateTexture(nil, "BORDER")
	actionsPanelBorder:SetAllPoints()
	actionsPanelBorder:SetColorTexture(1, 1, 1, 0.08)

	local actionsHeader = actionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	actionsHeader:SetPoint("TOPLEFT", actionsPanel, "TOPLEFT", 12, -10)
	actionsHeader:SetText("Quick Actions")

	local function CreateHomeActionButton(parent, text, x, y, onClick)
		local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		button:SetSize(232, 22)
		button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
		button:SetText(text)
		button:SetScript("OnClick", onClick)
		return button
	end

	local openWhatToAnnounce = CreateHomeActionButton(actionsPanel, "Open What to Announce", 12, -34, function()
		OpenSettingsCategory(QuestTogether.announcementsCategory)
	end)
	local openWhereToAnnounce = CreateHomeActionButton(actionsPanel, "Open Where to Announce", 12, -60, function()
		OpenSettingsCategory(QuestTogether.whereToAnnounceCategory)
	end)
	local openQuestPlates = CreateHomeActionButton(actionsPanel, "Open Quest Plates", 12, -86, function()
		OpenSettingsCategory(QuestTogether.questPlatesCategory)
	end)
	local openProfiles = CreateHomeActionButton(actionsPanel, "Open Profiles", 12, -112, function()
		OpenSettingsCategory(QuestTogether.profilesCategory)
	end)
	local openHudEditMode = CreateHomeActionButton(actionsPanel, "Open HUD Edit Mode", 12, -138, function()
		if not QuestTogether:OpenHudEditMode() then
			QuestTogether:Print("HUD Edit Mode is unavailable right now.")
		end
	end)
	local rescanQuestLog = CreateHomeActionButton(actionsPanel, "Rescan Quest Log", 12, -164, function()
		QuestTogether:ScanQuestLog()
	end)
	local printHelp = CreateHomeActionButton(actionsPanel, "Print /qt Help", 12, -190, function()
		QuestTogether:PrintHelp()
	end)

	local tipsHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	tipsHeader:SetPoint("TOPLEFT", statusPanel, "BOTTOMLEFT", 0, -18)
	tipsHeader:SetText("Tips")

	local tipsText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	tipsText:SetPoint("TOPLEFT", tipsHeader, "BOTTOMLEFT", 0, -8)
	tipsText:SetWidth(640)
	tipsText:SetJustifyH("LEFT")
	if tipsText.SetSpacing then
		tipsText:SetSpacing(3)
	end
	tipsText:SetText(
		"/qt options opens these settings.\n"
			.. "Use What to Announce for event types, Where to Announce for output targets,\n"
			.. "and Quest Plates for icon/tint visuals."
	)

	self.homeControls = {
		statusText = statusText,
		openWhatToAnnounce = openWhatToAnnounce,
		openWhereToAnnounce = openWhereToAnnounce,
		openQuestPlates = openQuestPlates,
		openProfiles = openProfiles,
		openHudEditMode = openHudEditMode,
		rescanQuestLog = rescanQuestLog,
		printHelp = printHelp,
	}

	frame:SetScript("OnShow", function()
		QuestTogether:RefreshHomeWindow()
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

	-- Register subcategories in the same order they should appear in the left nav.
	self:InitializeAnnouncementsWindow(category)
	self:InitializeWhereToAnnounceWindow(category)
	self:InitializeQuestPlatesWindow(category)
	self:InitializeMiscWindow(category)
	self:InitializeProfilesWindow(category)

	self:RefreshOptionsWindow()
	self:RefreshProfilesWindow()
end
