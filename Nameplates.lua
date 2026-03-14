--[[
QuestTogether Nameplate Augmentation

Purpose:
- Add a quest icon on Blizzard default nameplates for quest-objective units.
- Optionally tint quest-objective health bars using an addon overlay, without mutating Blizzard bar colors.

Design constraints:
- Keep the implementation minimal and non-invasive.
- Do not replace Blizzard templates or secure handlers.
- Hook post-update paths so Blizzard remains source-of-truth for baseline behavior.
]]

local QuestTogether = _G.QuestTogether
local QUEST_SCAN_CACHE_TTL_SECONDS = 0.5
local ANNOUNCEMENT_BUBBLE_Y_OFFSET = 22
local ANNOUNCEMENT_BUBBLE_FADE_IN_SECONDS = 0.2
local ANNOUNCEMENT_BUBBLE_FADE_OUT_SECONDS = 0.4
local PERSONAL_BUBBLE_SETTINGS_DIALOG_WIDTH = 380
local PERSONAL_BUBBLE_SETTINGS_DIALOG_HEIGHT = 220
local ApplyQuestIconVisual
local SafeUiNumber

-- Original icon used by this addon's first nameplate implementation.
QuestTogether.NAMEPLATE_QUEST_ICON_TEXTURE = "Interface\\OPTIONSFRAME\\UI-OptionsFrame-NewFeatureIcon"
QuestTogether.NAMEPLATE_QUEST_ICON_ATLAS = nil
QuestTogether.NAMEPLATE_QUEST_ICON_TEX_COORDS = nil
QuestTogether.NAMEPLATE_QUEST_ICON_WIDTH = 21
QuestTogether.NAMEPLATE_QUEST_ICON_HEIGHT = 21

-- Default burnt-orange tint for quest-objective units.
QuestTogether.NAMEPLATE_QUEST_HEALTH_COLOR = {
	r = 0.95,
	g = 0.45,
	b = 0.05,
}
QuestTogether.NAMEPLATE_HEALTH_FILL_ATLAS = "UI-HUD-CoolDownManager-Bar"
QuestTogether.knownNameplateAddons = QuestTogether.knownNameplateAddons or {
	"Plater",
	"TidyPlates_ThreatPlates",
	"Kui_Nameplates",
	"NeatPlates",
	"bdNameplates",
	"Aloft",
}

local function ClampColorComponent(value, fallback)
	local numberValue = SafeUiNumber and SafeUiNumber(value, nil) or nil
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

local function IsNonEmptyString(value)
	return type(value) == "string" and value ~= ""
end

SafeUiNumber = function(value, fallback)
	local numericValue = nil
	if QuestTogether and QuestTogether.SafeToNumber then
		numericValue = QuestTogether:SafeToNumber(value)
	end
	if numericValue == nil then
		return fallback
	end
	return numericValue
end

QuestTogether.nameplateQuestTitleCache = QuestTogether.nameplateQuestTitleCache or {}
QuestTogether.nameplateQuestObjectiveCache = QuestTogether.nameplateQuestObjectiveCache or {}
QuestTogether.nameplateQuestStateByUnitToken = QuestTogether.nameplateQuestStateByUnitToken or {}
QuestTogether.nameplateIconByUnitFrame = QuestTogether.nameplateIconByUnitFrame
	or setmetatable({}, { __mode = "k" })
QuestTogether.nameplateHealthOverlayByUnitFrame = QuestTogether.nameplateHealthOverlayByUnitFrame
	or setmetatable({}, { __mode = "k" })
QuestTogether.nameplateBubbleByUnitFrame = QuestTogether.nameplateBubbleByUnitFrame
	or setmetatable({}, { __mode = "k" })
QuestTogether.nameplateRefreshPendingByUnitToken = QuestTogether.nameplateRefreshPendingByUnitToken or {}
QuestTogether.nameplateHealthTintRefreshPendingByUnitToken =
	QuestTogether.nameplateHealthTintRefreshPendingByUnitToken or {}
QuestTogether.nameplateHealthTintRetryCountByUnitToken = QuestTogether.nameplateHealthTintRetryCountByUnitToken or {}
QuestTogether.nameplateFullRefreshGeneration = QuestTogether.nameplateFullRefreshGeneration or 0

local function GetAnnouncementBubbleLifetimeSeconds()
	local configuredDuration = QuestTogether:NormalizeChatBubbleDurationValue(QuestTogether:GetOption("chatBubbleDuration"))
	if not configuredDuration or configuredDuration <= 0 then
		configuredDuration = QuestTogether.DEFAULTS.profile.chatBubbleDuration
	end
	return SafeUiNumber(configuredDuration, QuestTogether.DEFAULTS.profile.chatBubbleDuration)
end

local function GetAnnouncementBubbleUnitFrame(hostFrame)
	if not hostFrame then
		return nil
	end
	return hostFrame.UnitFrame or hostFrame
end

local function ScaleBubbleMetric(baseValue, sizeScale, minimumValue)
	local scaledValue = math.floor((baseValue * sizeScale) + 0.5)
	if minimumValue then
		return math.max(minimumValue, scaledValue)
	end
	return scaledValue
end

local function GetPersonalBubbleAnchorFontDefinition()
	if ChatBubbleFont and ChatBubbleFont.GetFont then
		local fontPath, _, fontFlags = ChatBubbleFont:GetFont()
		if fontPath and fontPath ~= "" then
			return fontPath, fontFlags
		end
	end

	if GameFontHighlightMedium and GameFontHighlightMedium.GetFont then
		local fontPath, _, fontFlags = GameFontHighlightMedium:GetFont()
		if fontPath and fontPath ~= "" then
			return fontPath, fontFlags
		end
	end

	return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", ""
end

local function GetAnnouncementBubbleVisualConfig()
	local configuredSize = QuestTogether:NormalizeChatBubbleSizeValue(QuestTogether:GetOption("chatBubbleSize"))
		or QuestTogether.DEFAULTS.profile.chatBubbleSize
	local sizeScale = configuredSize / 100

	return {
		fontSize = ScaleBubbleMetric(14, sizeScale, 10),
		iconSize = ScaleBubbleMetric(18, sizeScale, 12),
		iconGap = ScaleBubbleMetric(8, sizeScale, 4),
		minTextWidth = ScaleBubbleMetric(48, sizeScale, 40),
		maxTextWidth = ScaleBubbleMetric(220, sizeScale, 160),
		inset = ScaleBubbleMetric(16, sizeScale, 12),
	}
end

local function EnsurePersonalBubbleAnchorSelection(hostFrame)
	if not hostFrame or hostFrame.Selection then
		return hostFrame and hostFrame.Selection or nil
	end
	if not EditModeManagerFrame then
		return nil
	end

	-- EditMode templates can be unavailable on some clients/states; fail soft and skip selection chrome.
	local ok, selection = pcall(CreateFrame, "Frame", nil, hostFrame, "EditModeSystemSelectionTemplate")
	if not ok or not selection then
		return nil
	end

	selection:SetAllPoints()
	selection:SetFrameLevel(hostFrame:GetFrameLevel() + 20)
	selection:EnableMouse(false)
	selection:Hide()
	if selection.SetSystem then
		selection:SetSystem({
			GetSystemName = function()
				return "QuestTogether Bubble"
			end,
		})
	elseif selection.SetGetLabelTextFunction then
		selection:SetGetLabelTextFunction(function()
			return "QuestTogether Bubble"
		end)
	end
	if selection.Label then
		selection.Label:Hide()
	end
	selection.UpdateLabelVisibility = function(frame)
		if frame.Label then
			frame.Label:Hide()
		end
		if frame.HorizontalLabel then
			frame.HorizontalLabel:Hide()
		end
		if frame.VerticalLabel then
			frame.VerticalLabel:Hide()
		end
	end

	hostFrame.Selection = selection
	return selection
end

local function GetPersonalBubbleAnchorDialogAttachPoint()
	if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
		return "TOPLEFT", EditModeManagerFrame, "TOPRIGHT", 16, -40
	end
	return "CENTER", UIParent, "CENTER", 420, 40
end

local function SavePersonalBubbleDialogPosition(dialog)
	if not dialog then
		return
	end

	local point, _, relativePoint, offsetX, offsetY = dialog:GetPoint(1)
	if not point or not relativePoint then
		return
	end

	dialog.qtUserPlaced = {
		point = point,
		relativePoint = relativePoint,
		x = offsetX,
		y = offsetY,
	}
end

local function GetPersonalBubbleEditSession()
	return QuestTogether.personalBubbleEditSession
end

local function EnsurePersonalBubbleEditSession()
	if QuestTogether.personalBubbleEditSession then
		return QuestTogether.personalBubbleEditSession
	end

	local session = {
		saved = {
			chatBubbleSize = QuestTogether:NormalizeChatBubbleSizeValue(QuestTogether:GetOption("chatBubbleSize"))
				or QuestTogether.DEFAULTS.profile.chatBubbleSize,
			chatBubbleDuration = QuestTogether:NormalizeChatBubbleDurationValue(QuestTogether:GetOption("chatBubbleDuration"))
				or QuestTogether.DEFAULTS.profile.chatBubbleDuration,
			anchor = QuestTogether:DeepCopy(QuestTogether:GetPersonalBubbleAnchor()),
		},
		pending = false,
	}

	QuestTogether.personalBubbleEditSession = session
	return session
end

local function SyncPersonalBubbleEditModeDirtyState()
	local session = GetPersonalBubbleEditSession()
	local isPending = session and session.pending or false
	if not EditModeManagerFrame then
		return
	end

	if isPending then
		if EditModeManagerFrame.SetHasActiveChanges then
			EditModeManagerFrame:SetHasActiveChanges(true)
		end
	elseif EditModeManagerFrame.CheckForSystemActiveChanges then
		EditModeManagerFrame:CheckForSystemActiveChanges()
	end
end

local function IsPersonalBubbleEditSnapshotEqual(snapshot)
	if type(snapshot) ~= "table" then
		return true
	end

	local currentSize = QuestTogether:NormalizeChatBubbleSizeValue(QuestTogether:GetOption("chatBubbleSize"))
		or QuestTogether.DEFAULTS.profile.chatBubbleSize
	local currentDuration = QuestTogether:NormalizeChatBubbleDurationValue(QuestTogether:GetOption("chatBubbleDuration"))
		or QuestTogether.DEFAULTS.profile.chatBubbleDuration
	local currentAnchor = QuestTogether:GetPersonalBubbleAnchor()
	local savedAnchor = snapshot.anchor or QuestTogether.DEFAULT_PERSONAL_BUBBLE_ANCHOR

	return currentSize == snapshot.chatBubbleSize
		and currentDuration == snapshot.chatBubbleDuration
		and currentAnchor.point == savedAnchor.point
		and currentAnchor.relativePoint == savedAnchor.relativePoint
		and currentAnchor.x == savedAnchor.x
		and currentAnchor.y == savedAnchor.y
end

local function IsPersonalBubbleAtDefaultState()
	local defaults = QuestTogether.DEFAULTS.profile
	local anchorDefaults = QuestTogether.DEFAULT_PERSONAL_BUBBLE_ANCHOR
	local currentSize = QuestTogether:NormalizeChatBubbleSizeValue(QuestTogether:GetOption("chatBubbleSize"))
		or defaults.chatBubbleSize
	local currentDuration = QuestTogether:NormalizeChatBubbleDurationValue(QuestTogether:GetOption("chatBubbleDuration"))
		or defaults.chatBubbleDuration
	local currentAnchor = QuestTogether:GetPersonalBubbleAnchor()

	return currentSize == defaults.chatBubbleSize
		and currentDuration == defaults.chatBubbleDuration
		and currentAnchor.point == anchorDefaults.point
		and currentAnchor.relativePoint == anchorDefaults.relativePoint
		and currentAnchor.x == anchorDefaults.x
		and currentAnchor.y == anchorDefaults.y
end

local function UpdatePersonalBubbleEditSessionDirtyState()
	local session = EnsurePersonalBubbleEditSession()
	session.pending = not IsPersonalBubbleEditSnapshotEqual(session.saved)
	if
		QuestTogether.personalBubbleEditModeDialog
		and QuestTogether.personalBubbleEditModeDialog.RevertButton
	then
		QuestTogether.personalBubbleEditModeDialog.RevertButton:SetEnabled(session.pending)
		QuestTogether.personalBubbleEditModeDialog.ResetButton:SetEnabled(not IsPersonalBubbleAtDefaultState())
	end
	SyncPersonalBubbleEditModeDirtyState()
end

local function ConfigureEditModeSlider(settingFrame, settingData, onValueChanged)
	if not settingFrame then
		return
	end

	if settingFrame.cbrHandles then
		settingFrame.cbrHandles:Unregister()
	end
	if not settingFrame.qtCbrHandles then
		settingFrame.qtCbrHandles = EventUtil.CreateCallbackHandleContainer()
	end
	settingFrame.qtCbrHandles:Unregister()
	settingFrame.qtCbrHandles:RegisterCallback(
		settingFrame.Slider,
		MinimalSliderWithSteppersMixin.Event.OnValueChanged,
		function(_, value)
			if type(onValueChanged) == "function" then
				onValueChanged(value)
			end
		end,
		settingFrame
	)
	settingFrame.qtCbrHandles:RegisterCallback(
		settingFrame.Slider,
		MinimalSliderWithSteppersMixin.Event.OnInteractStart,
		function()
		end,
		settingFrame
	)
	settingFrame.qtCbrHandles:RegisterCallback(
		settingFrame.Slider,
		MinimalSliderWithSteppersMixin.Event.OnInteractEnd,
		function()
		end,
		settingFrame
	)

	settingFrame.OnSliderValueChanged = function()
	end
	settingFrame.OnSliderInteractEnd = function()
	end
	settingFrame.OnSliderInteractStart = function()
	end
	settingFrame:SetupSetting(settingData)
	settingFrame:Show()
end

function QuestTogether:ApplyPersonalBubbleEditSnapshot(snapshot)
	self:DebugState("editmode", "ApplyPersonalBubbleEditSnapshot", snapshot)
	if type(snapshot) ~= "table" then
		return
	end

	self.personalBubbleEditSessionRestoring = true

	if snapshot.chatBubbleSize then
		self:SetOption("chatBubbleSize", snapshot.chatBubbleSize)
	end
	if snapshot.chatBubbleDuration then
		self:SetOption("chatBubbleDuration", snapshot.chatBubbleDuration)
	end
	if snapshot.anchor then
		self:SetPersonalBubbleAnchor(
			snapshot.anchor.point,
			snapshot.anchor.relativePoint,
			snapshot.anchor.x,
			snapshot.anchor.y
		)
	end

	self.personalBubbleEditSessionRestoring = false
	self:RefreshPersonalBubbleAnchorVisualState()
	self:AttachPersonalBubbleEditModeDialog()
	self:RefreshPersonalBubbleEditModeDialog()
end

function QuestTogether:CommitPersonalBubbleEditSession()
	self:Debug("Committing personal bubble edit session", "editmode")
	self.personalBubbleEditSession = nil
	self.personalBubbleEditSessionRestoring = false
	SyncPersonalBubbleEditModeDirtyState()
	if self.personalBubbleEditModeDialog and self.personalBubbleEditModeDialog.RevertButton then
		self.personalBubbleEditModeDialog.RevertButton:SetEnabled(false)
	end
end

function QuestTogether:RevertPersonalBubbleEditSession()
	local session = GetPersonalBubbleEditSession()
	if not session then
		return
	end

	self:Debug("Reverting personal bubble edit session", "editmode")
	self:ApplyPersonalBubbleEditSnapshot(session.saved)
	session.pending = false
	SyncPersonalBubbleEditModeDirtyState()
	if self.personalBubbleEditModeDialog and self.personalBubbleEditModeDialog.RevertButton then
		self.personalBubbleEditModeDialog.RevertButton:SetEnabled(false)
	end
end

function QuestTogether:ResetPersonalBubbleEditSessionToDefaults()
	self:Debug("Resetting personal bubble edit session to defaults", "editmode")
	self.personalBubbleEditSessionRestoring = true
	self:SetOption("chatBubbleSize", self.DEFAULTS.profile.chatBubbleSize)
	self:SetOption("chatBubbleDuration", self.DEFAULTS.profile.chatBubbleDuration)
	self:ResetPersonalBubbleAnchor()
	self.personalBubbleEditSessionRestoring = false

	UpdatePersonalBubbleEditSessionDirtyState()
	self:RefreshPersonalBubbleAnchorVisualState()
	self:AttachPersonalBubbleEditModeDialog()
	self:RefreshPersonalBubbleEditModeDialog()
end

local function EnsurePersonalBubbleEditModeDialog()
	if QuestTogether.personalBubbleEditModeDialog then
		return QuestTogether.personalBubbleEditModeDialog
	end
	if not EditModeManagerFrame then
		return nil
	end

	local dialog = CreateFrame("Frame", "QuestTogetherPersonalBubbleSettingsDialog", UIParent)
	dialog:SetSize(PERSONAL_BUBBLE_SETTINGS_DIALOG_WIDTH, PERSONAL_BUBBLE_SETTINGS_DIALOG_HEIGHT)
	dialog:SetFrameStrata("DIALOG")
	dialog:SetFrameLevel(250)
	dialog:SetClampedToScreen(true)
	dialog:SetMovable(true)
	dialog:EnableMouse(true)
	dialog:RegisterForDrag("LeftButton")
	dialog:EnableKeyboard(true)
	dialog:Hide()

	local border = CreateFrame("Frame", nil, dialog, "DialogBorderTranslucentTemplate")
	border:SetAllPoints()
	dialog.Border = border

	local title = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	title:SetPoint("TOP", dialog, "TOP", 0, -15)
	title:SetText("QuestTogether Bubble")
	dialog.Title = title

	local closeButton = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
	closeButton:SetPoint("TOPRIGHT", dialog, "TOPRIGHT")
	closeButton:SetScript("OnClick", function()
		QuestTogether:DeselectPersonalBubbleAnchor()
	end)
	dialog.CloseButton = closeButton

	local dragHandle = CreateFrame("Frame", nil, dialog)
	dragHandle:SetPoint("TOPLEFT", dialog, "TOPLEFT", 8, -8)
	dragHandle:SetPoint("TOPRIGHT", closeButton, "TOPLEFT", -4, -8)
	dragHandle:SetHeight(28)
	dragHandle:EnableMouse(true)
	dragHandle:RegisterForDrag("LeftButton")
	dragHandle:SetScript("OnDragStart", function()
		dialog:StartMoving()
	end)
	dragHandle:SetScript("OnDragStop", function()
		dialog:StopMovingOrSizing()
		SavePersonalBubbleDialogPosition(dialog)
	end)
	dialog.DragHandle = dragHandle

	local sizeSlider = CreateFrame("Frame", nil, dialog, "EditModeSettingSliderTemplate")
	sizeSlider:SetPoint("TOPLEFT", dialog, "TOPLEFT", 24, -48)
	dialog.SizeSlider = sizeSlider

	local durationSlider = CreateFrame("Frame", nil, dialog, "EditModeSettingSliderTemplate")
	durationSlider:SetPoint("TOPLEFT", sizeSlider, "BOTTOMLEFT", 0, -18)
	dialog.DurationSlider = durationSlider

	local revertButton = CreateFrame("Button", nil, dialog, "EditModeSystemSettingsDialogButtonTemplate")
	revertButton:SetSize(160, 28)
	revertButton:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 24, 18)
	revertButton:SetText("Revert Changes")
	revertButton:SetScript("OnClick", function()
		QuestTogether:RevertPersonalBubbleEditSession()
	end)
	dialog.RevertButton = revertButton

	local resetButton = CreateFrame("Button", nil, dialog, "EditModeSystemSettingsDialogButtonTemplate")
	resetButton:SetSize(160, 28)
	resetButton:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -24, 18)
	resetButton:SetText("Reset To Default")
	resetButton:SetScript("OnClick", function()
		QuestTogether:ResetPersonalBubbleEditSessionToDefaults()
	end)
	dialog.ResetButton = resetButton

	dialog:SetScript("OnDragStart", function(frame)
		frame:StartMoving()
	end)
	dialog:SetScript("OnDragStop", function(frame)
		frame:StopMovingOrSizing()
		SavePersonalBubbleDialogPosition(frame)
	end)
	dialog:SetScript("OnHide", function(frame)
		frame:StopMovingOrSizing()
	end)
	dialog:SetScript("OnKeyDown", function(_, key)
		if key == "ESCAPE" then
			QuestTogether:DeselectPersonalBubbleAnchor()
		end
	end)

	QuestTogether.personalBubbleEditModeDialog = dialog
	return dialog
end

local function GetAnnouncementBubbleScreenHostFrame()
	if QuestTogether.announcementBubbleScreenHostFrame then
		return QuestTogether.announcementBubbleScreenHostFrame
	end

	local parentFrame = UIParent or (C_UI and C_UI.GetUIParent and C_UI.GetUIParent()) or nil
	if not parentFrame then
		return nil
	end

	local hostFrame = CreateFrame("Frame", "QuestTogetherPersonalBubbleAnchor", parentFrame)
	hostFrame:SetSize(1, 1)
	hostFrame:SetFrameStrata("LOW")
	hostFrame:SetFrameLevel(parentFrame:GetFrameLevel() + 5)
	hostFrame:SetClampedToScreen(true)
	hostFrame:SetMovable(true)
	hostFrame:RegisterForDrag("LeftButton")
	hostFrame:EnableMouse(false)

	local background = hostFrame:CreateTexture(nil, "BACKGROUND")
	background:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", 6, -6)
	background:SetPoint("BOTTOMRIGHT", hostFrame, "BOTTOMRIGHT", -6, 6)
	background:SetColorTexture(0.03, 0.03, 0.03, 0.68)
	background:Hide()
	hostFrame.EditBackground = background

	local border = hostFrame:CreateTexture(nil, "BORDER")
	border:SetPoint("TOPLEFT", background, "TOPLEFT", 0, 0)
	border:SetPoint("BOTTOMRIGHT", background, "BOTTOMRIGHT", 0, 0)
	border:SetColorTexture(0.45, 0.52, 0.6, 0.35)
	border:Hide()
	hostFrame.EditBorder = border

	local icon = hostFrame:CreateTexture(nil, "ARTWORK")
	icon:SetSize(16, 16)
	icon:SetPoint("LEFT", hostFrame, "LEFT", 16, 0)
	ApplyQuestIconVisual(icon)
	icon:Hide()
	hostFrame.EditIcon = icon

	local label = hostFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
	label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	label:SetJustifyH("LEFT")
	label:SetJustifyV("MIDDLE")
	label:SetTextColor(1, 0.82, 0, 1)
	label:SetText("QuestTogether Bubble")
	label:Hide()
	hostFrame.EditLabel = label

	hostFrame:SetScript("OnEnter", function()
		QuestTogether:RefreshPersonalBubbleAnchorVisualState()
	end)
	hostFrame:SetScript("OnLeave", function()
		QuestTogether:RefreshPersonalBubbleAnchorVisualState()
	end)
	hostFrame:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" then
			return
		end
		QuestTogether:SelectPersonalBubbleAnchor()
	end)
	hostFrame:SetScript("OnDragStart", function(frame)
		if not QuestTogether:IsPersonalBubbleAnchorInEditMode() then
			return
		end
		QuestTogether:SelectPersonalBubbleAnchor()
		frame:StartMoving()
	end)
	hostFrame:SetScript("OnDragStop", function(frame)
		frame:StopMovingOrSizing()
		QuestTogether:SavePersonalBubbleAnchorFromFrame(frame)
		QuestTogether:AttachPersonalBubbleEditModeDialog()
	end)

	QuestTogether.announcementBubbleScreenHostFrame = hostFrame
	QuestTogether:ApplySavedPersonalBubbleAnchor()
	QuestTogether:RefreshPersonalBubbleAnchorVisualState()
	hostFrame:Show()

	return hostFrame
end

function QuestTogether:IsPersonalBubbleAnchorInEditMode()
	return self.isEnabled and EditModeManagerFrame and EditModeManagerFrame:IsShown() and self:GetOption("showChatBubbles")
end

function QuestTogether:ApplySavedPersonalBubbleAnchor()
	local hostFrame = self.announcementBubbleScreenHostFrame
	if not hostFrame then
		return
	end

	local parentFrame = hostFrame:GetParent() or UIParent
	local anchor = self:GetPersonalBubbleAnchor()
	self:DebugState("editmode", "ApplySavedPersonalBubbleAnchor", anchor)
	hostFrame:ClearAllPoints()
	hostFrame:SetPoint(anchor.point, parentFrame, anchor.relativePoint, anchor.x, anchor.y)
	if self.personalBubbleEditModeDialog and self.personalBubbleEditModeDialog:IsShown() then
		self:AttachPersonalBubbleEditModeDialog()
	end
end

local function RoundOffset(value)
	local numberValue = SafeUiNumber(value, 0)
	if numberValue >= 0 then
		return math.floor(numberValue + 0.5)
	end
	return math.ceil(numberValue - 0.5)
end

function QuestTogether:SavePersonalBubbleAnchorFromFrame(hostFrame)
	if not hostFrame then
		return false
	end

	local point, _, relativePoint, offsetX, offsetY = hostFrame:GetPoint(1)
	if not point or not relativePoint then
		return false
	end

	local changed = self:SetPersonalBubbleAnchor(point, relativePoint, RoundOffset(offsetX), RoundOffset(offsetY))
	self:Debugf(
		"editmode",
		"Saved personal bubble anchor point=%s relativePoint=%s x=%s y=%s changed=%s",
		tostring(point),
		tostring(relativePoint),
		tostring(RoundOffset(offsetX)),
		tostring(RoundOffset(offsetY)),
		tostring(changed)
	)
	if changed and self:IsPersonalBubbleAnchorInEditMode() and not self.personalBubbleEditSessionRestoring then
		UpdatePersonalBubbleEditSessionDirtyState()
		self:RefreshPersonalBubbleEditModeDialog()
	end
	return changed
end

function QuestTogether:AttachPersonalBubbleEditModeDialog()
	local dialog = self.personalBubbleEditModeDialog
	if not dialog then
		return
	end

	if dialog.qtUserPlaced then
		self:Debug("Attaching personal bubble dialog using user-placed position", "editmode")
		dialog:ClearAllPoints()
		dialog:SetPoint(
			dialog.qtUserPlaced.point,
			UIParent,
			dialog.qtUserPlaced.relativePoint,
			dialog.qtUserPlaced.x,
			dialog.qtUserPlaced.y
		)
		return
	end

	local point, relativeTo, relativePoint, offsetX, offsetY = GetPersonalBubbleAnchorDialogAttachPoint()
	self:Debugf(
		"editmode",
		"Attaching personal bubble dialog point=%s relativePoint=%s x=%s y=%s",
		tostring(point),
		tostring(relativePoint),
		tostring(offsetX),
		tostring(offsetY)
	)
	dialog:ClearAllPoints()
	dialog:SetPoint(point, relativeTo, relativePoint, offsetX, offsetY)
end

function QuestTogether:RefreshPersonalBubbleEditModeDialog()
	local dialog = EnsurePersonalBubbleEditModeDialog()
	if not dialog then
		return
	end

	local session = GetPersonalBubbleEditSession()

	local function FormatDurationLabel(value)
		local normalized = self:NormalizeChatBubbleDurationValue(value) or self.DEFAULTS.profile.chatBubbleDuration
		if math.abs(normalized - math.floor(normalized)) < 0.001 then
			return string.format("%d sec", normalized)
		end
		return string.format("%.1f sec", normalized)
	end

	ConfigureEditModeSlider(dialog.SizeSlider, {
		displayInfo = {
			setting = "chatBubbleSize",
			formatter = function(value)
				local normalized = self:NormalizeChatBubbleSizeValue(value) or self.DEFAULTS.profile.chatBubbleSize
				return self:GetChatBubbleSizeLabel(normalized)
			end,
			minValue = self.CHAT_BUBBLE_SIZE_MIN,
			maxValue = self.CHAT_BUBBLE_SIZE_MAX,
			stepSize = self.CHAT_BUBBLE_SIZE_STEP,
		},
		currentValue = self:NormalizeChatBubbleSizeValue(self:GetOption("chatBubbleSize")) or self.DEFAULTS.profile.chatBubbleSize,
		settingName = "Font Size",
	}, function(value)
		if self:SetOption("chatBubbleSize", value) and not self.personalBubbleEditSessionRestoring then
			UpdatePersonalBubbleEditSessionDirtyState()
			self:RefreshPersonalBubbleAnchorVisualState()
			self:AttachPersonalBubbleEditModeDialog()
		end
	end)

	ConfigureEditModeSlider(dialog.DurationSlider, {
		displayInfo = {
			setting = "chatBubbleDuration",
			formatter = FormatDurationLabel,
			minValue = self.CHAT_BUBBLE_DURATION_MIN,
			maxValue = self.CHAT_BUBBLE_DURATION_MAX,
			stepSize = self.CHAT_BUBBLE_DURATION_STEP,
		},
		currentValue = self:NormalizeChatBubbleDurationValue(self:GetOption("chatBubbleDuration"))
			or self.DEFAULTS.profile.chatBubbleDuration,
		settingName = "Display Duration",
	}, function(value)
		if self:SetOption("chatBubbleDuration", value) and not self.personalBubbleEditSessionRestoring then
			UpdatePersonalBubbleEditSessionDirtyState()
			self:RefreshPersonalBubbleAnchorVisualState()
			self:AttachPersonalBubbleEditModeDialog()
		end
	end)

	if dialog.RevertButton then
		dialog.RevertButton:SetEnabled(session and session.pending or false)
	end
	if dialog.ResetButton then
		dialog.ResetButton:SetEnabled(not IsPersonalBubbleAtDefaultState())
	end
end

function QuestTogether:SelectPersonalBubbleAnchor()
	if not self:IsPersonalBubbleAnchorInEditMode() then
		return
	end
	self:Debug("Selecting personal bubble anchor", "editmode")

	EnsurePersonalBubbleEditSession()

	local hostFrame = GetAnnouncementBubbleScreenHostFrame()
	if not hostFrame then
		return
	end

	if EditModeManagerFrame and EditModeManagerFrame.ClearSelectedSystem then
		EditModeManagerFrame:ClearSelectedSystem()
	end

	self.personalBubbleAnchorSelected = true
	self:RefreshPersonalBubbleAnchorVisualState()
	self:AttachPersonalBubbleEditModeDialog()
	self:RefreshPersonalBubbleEditModeDialog()

	local dialog = EnsurePersonalBubbleEditModeDialog()
	if dialog then
		dialog:Show()
	end
end

function QuestTogether:DeselectPersonalBubbleAnchor()
	self:Debug("Deselecting personal bubble anchor", "editmode")
	self.personalBubbleAnchorSelected = false
	if self.personalBubbleEditModeDialog then
		self.personalBubbleEditModeDialog:Hide()
	end
	self:RefreshPersonalBubbleAnchorVisualState()
end

function QuestTogether:RefreshPersonalBubbleAnchorVisualState()
	local hostFrame = self.announcementBubbleScreenHostFrame
	if not hostFrame then
		return
	end

	EnsurePersonalBubbleAnchorSelection(hostFrame)

	local editModeActive = self:IsPersonalBubbleAnchorInEditMode()
	local uiParentLevel = SafeUiNumber(
		(UIParent and UIParent.GetFrameLevel and UIParent:GetFrameLevel()) or 0,
		0
	)
	if editModeActive then
		hostFrame:SetFrameStrata("HIGH")
		hostFrame:SetFrameLevel(uiParentLevel + 80)
		local visualConfig = GetAnnouncementBubbleVisualConfig()
		local fontPath, fontFlags = GetPersonalBubbleAnchorFontDefinition()
		hostFrame.EditLabel:SetFont(fontPath, visualConfig.fontSize, fontFlags)
		hostFrame.EditLabel:SetWidth(0)
		hostFrame.EditLabel:SetText("QuestTogether Bubble")

		local labelWidth = hostFrame.EditLabel.GetUnboundedStringWidth and hostFrame.EditLabel:GetUnboundedStringWidth() or 0
		labelWidth = SafeUiNumber(labelWidth, 0)
		local labelHeight = SafeUiNumber(hostFrame.EditLabel:GetStringHeight(), visualConfig.fontSize)
		labelWidth = math.max(visualConfig.minTextWidth, math.min(visualConfig.maxTextWidth, labelWidth))
		local anchorWidth = labelWidth + visualConfig.iconSize + visualConfig.iconGap + (visualConfig.inset * 2)
		local anchorHeight = math.max(visualConfig.iconSize, labelHeight) + (visualConfig.inset * 2)

		hostFrame:SetSize(anchorWidth, anchorHeight)

		hostFrame.EditIcon:SetSize(visualConfig.iconSize, visualConfig.iconSize)
		hostFrame.EditIcon:ClearAllPoints()
		hostFrame.EditIcon:SetPoint("LEFT", hostFrame, "LEFT", visualConfig.inset, 0)

		hostFrame.EditLabel:ClearAllPoints()
		hostFrame.EditLabel:SetPoint("LEFT", hostFrame.EditIcon, "RIGHT", visualConfig.iconGap, 0)
		hostFrame.EditLabel:SetWidth(labelWidth)
	else
		hostFrame:SetFrameStrata("LOW")
		hostFrame:SetFrameLevel(uiParentLevel + 5)
		hostFrame:SetSize(1, 1)
	end

	local activeBubble = self.nameplateBubbleByUnitFrame and self.nameplateBubbleByUnitFrame[hostFrame]
	if activeBubble then
		activeBubble:SetFrameStrata(hostFrame:GetFrameStrata() or "LOW")
		activeBubble:SetFrameLevel(SafeUiNumber(hostFrame:GetFrameLevel(), 0) + 20)
	end
	hostFrame:EnableMouse(editModeActive)

	local visibleFields = {
		hostFrame.EditBackground,
		hostFrame.EditBorder,
		hostFrame.EditIcon,
		hostFrame.EditLabel,
	}

	for _, field in ipairs(visibleFields) do
		if field then
			if editModeActive then
				field:Show()
			else
				field:Hide()
			end
		end
	end

	if hostFrame.Selection then
		if editModeActive then
			if self.personalBubbleAnchorSelected then
				hostFrame.Selection:ShowSelected()
			else
				hostFrame.Selection:ShowHighlighted()
			end
		else
			hostFrame.Selection:Hide()
		end
	end

	if not editModeActive then
		self.personalBubbleAnchorSelected = false
		if self.personalBubbleEditModeDialog then
			self.personalBubbleEditModeDialog:Hide()
		end
	end

	hostFrame:Show()
end

function QuestTogether:TryInstallPersonalBubbleEditModeHooks()
	if self.personalBubbleEditModeHooksInstalled then
		self:Debug("Personal bubble Edit Mode hooks already installed", "editmode")
		return
	end

	if not EditModeManagerFrame or not EditModeManagerFrame.HookScript then
		self:Debug("EditModeManagerFrame unavailable; cannot install personal bubble hooks", "editmode")
		return
	end

	GetAnnouncementBubbleScreenHostFrame()
	EnsurePersonalBubbleEditModeDialog()

	EditModeManagerFrame:HookScript("OnShow", function()
		QuestTogether:Debug("Edit Mode shown", "editmode")
		EnsurePersonalBubbleEditSession()
		QuestTogether:RefreshPersonalBubbleAnchorVisualState()
		QuestTogether:RefreshPersonalBubbleEditModeDialog()
	end)
	EditModeManagerFrame:HookScript("OnHide", function()
		QuestTogether:Debug("Edit Mode hidden", "editmode")
		QuestTogether:DeselectPersonalBubbleAnchor()
	end)

	hooksecurefunc(EditModeManagerFrame, "SelectSystem", function(_, systemFrame)
		local hostFrame = QuestTogether.announcementBubbleScreenHostFrame
		if hostFrame and systemFrame ~= hostFrame then
			QuestTogether:DeselectPersonalBubbleAnchor()
		end
	end)
	hooksecurefunc(EditModeManagerFrame, "ClearSelectedSystem", function()
		QuestTogether:DeselectPersonalBubbleAnchor()
	end)
	hooksecurefunc(EditModeManagerFrame, "SaveLayouts", function()
		QuestTogether:CommitPersonalBubbleEditSession()
	end)
	hooksecurefunc(EditModeManagerFrame, "RevertAllChanges", function()
		QuestTogether:RevertPersonalBubbleEditSession()
	end)
	if EditModeManagerFrame.RevertAllChangesButton and EditModeManagerFrame.RevertAllChangesButton.HookScript then
		EditModeManagerFrame.RevertAllChangesButton:HookScript("OnClick", function()
			QuestTogether:RevertPersonalBubbleEditSession()
		end)
	end

	self.personalBubbleEditModeHooksInstalled = true
	self:Debug("Installed personal bubble Edit Mode hooks", "editmode")
end

-- Returns true only for the dynamic nameplate unit tokens (nameplate1, nameplate2, ...).
function QuestTogether:IsNameplateUnitToken(unitToken)
	return type(unitToken) == "string" and string.find(unitToken, "^nameplate%d+$") ~= nil
end

function QuestTogether:GetNameplateNowSeconds()
	return self.API.GetTime()
end

function QuestTogether:DoesNameplateUnitExist(unitToken)
	return UnitExists(unitToken) and true or false
end

function QuestTogether:GetNameplateUnitGuid(unitToken)
	-- Nameplate unit tokens can disappear between frames; guard transient UnitGUID errors.
	local ok, unitGuid = pcall(UnitGUID, unitToken)
	if not ok or not IsNonEmptyString(unitGuid) then
		return nil
	end
	return unitGuid
end

function QuestTogether:IsNameplateAugmentationBlockedInCurrentContext()
	local isInInstance = self.API and self.API.IsInInstance and self.API.IsInInstance()
	return isInInstance and true or false
end

function QuestTogether:IsNameplateUnitRelatedToActiveQuest(unitToken)
	if not C_QuestLog or not C_QuestLog.UnitIsRelatedToActiveQuest then
		return false
	end
	-- Blizzard quest APIs can throw on transient/invalid unit tokens; treat as "not related".
	local ok, isRelated = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unitToken)
	return ok and isRelated and true or false
end

function QuestTogether:IsNameplateUnitOnQuest(unitToken, questId)
	if not C_QuestLog or not C_QuestLog.IsUnitOnQuest then
		return false
	end
	-- Blizzard quest APIs can throw on transient/invalid unit tokens; treat as "not on quest".
	local ok, isOnQuest = pcall(C_QuestLog.IsUnitOnQuest, unitToken, questId)
	return ok and isOnQuest and true or false
end

function QuestTogether:IsNameplateUnitQuestBoss(unitToken)
	if not UnitIsQuestBoss then
		return false
	end
	return UnitIsQuestBoss(unitToken) and true or false
end

function QuestTogether:CanPlayerAttackNameplateUnit(unitToken)
	return UnitCanAttack("player", unitToken) and true or false
end

function QuestTogether:IsNameplateUnitPlayer(unitToken)
	return UnitIsPlayer(unitToken) and true or false
end

function QuestTogether:IsNameplateUnitConnected(unitToken)
	return UnitIsConnected(unitToken) and true or false
end

function QuestTogether:IsNameplateUnitDead(unitToken)
	return UnitIsDead(unitToken) and true or false
end

function QuestTogether:IsNameplateUnitTapDenied(unitToken)
	return UnitIsTapDenied(unitToken) and true or false
end

function QuestTogether:GetNameplateQuestHealthColor()
	local fallback = self.NAMEPLATE_QUEST_HEALTH_COLOR
	local configured = self:GetOption("nameplateQuestHealthColor")
	if type(configured) ~= "table" then
		return { r = fallback.r, g = fallback.g, b = fallback.b }
	end

	return {
		r = ClampColorComponent(configured.r, fallback.r),
		g = ClampColorComponent(configured.g, fallback.g),
		b = ClampColorComponent(configured.b, fallback.b),
	}
end

function QuestTogether:CreateNameplateHealthOverlayTexture(parentFrame, drawLayer, subLevel)
	if not parentFrame or not parentFrame.CreateTexture then
		return nil
	end

	local texture = parentFrame:CreateTexture(nil, drawLayer or "ARTWORK", nil, subLevel or 0)
	if not texture then
		return nil
	end

	if texture.SetAtlas then
		texture:SetAtlas(self.NAMEPLATE_HEALTH_FILL_ATLAS, true)
	else
		texture:SetTexture("Interface\\Buttons\\WHITE8X8")
	end

	return texture
end

local function GetBooleanFieldIfPresent(tableValue, key)
	if not tableValue then
		return nil
	end
	local value = tableValue[key]
	if value == nil then
		return nil
	end
	return value == true
end

local function GetObjectiveProgressState(text)
	if type(text) ~= "string" or text == "" then
		return "unknown"
	end

	local amountCurrent, amountTotal = string.match(text, "(%d+)%s*/%s*(%d+)")
	if amountCurrent and amountTotal then
		local currentValue = SafeUiNumber(amountCurrent, nil)
		local totalValue = SafeUiNumber(amountTotal, nil)
		if currentValue == nil or totalValue == nil then
			return "unknown"
		end
		if currentValue < totalValue then
			return "unfinished"
		end
		return "complete"
	end

	local percentText = string.match(text, "(%d+)%%")
	if percentText then
		local percentValue = SafeUiNumber(percentText, nil)
		if percentValue == nil then
			return "unknown"
		end
		if percentValue < 100 then
			return "unfinished"
		end
		return "complete"
	end

	return "unknown"
end

function QuestTogether:ClearNameplateQuestObjectiveCache()
	wipe(self.nameplateQuestObjectiveCache)
	wipe(self.nameplateQuestStateByUnitToken)
end

function QuestTogether:RebuildNameplateQuestTitleCache()
	wipe(self.nameplateQuestTitleCache)

	if not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries or not C_QuestLog.GetInfo then
		return
	end

	local totalEntries = C_QuestLog.GetNumQuestLogEntries()
	for entryIndex = 1, totalEntries do
		local questDetails = C_QuestLog.GetInfo(entryIndex)
		if
			questDetails
			and not questDetails.isHeader
			and not questDetails.isHidden
			and type(questDetails.title) == "string"
			and questDetails.title ~= ""
		then
			self.nameplateQuestTitleCache[questDetails.title] = true
		end
	end

	-- Include world quest titles similarly to how Plater seeds its cache.
	if self.API and self.API.InCombatLockdown and self.API.InCombatLockdown() then
		self:Debug("Skipping world quest title cache refresh during combat", "nameplate")
		return
	end

	if C_Map and C_Map.GetBestMapForUnit and C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID then
		local mapId = C_Map.GetBestMapForUnit("player")
		if mapId then
			local getQuestsForMap = C_TaskQuest.GetQuestsForPlayerByMapID or C_TaskQuest.GetQuestsOnMap
			if getQuestsForMap then
				local worldQuestList = getQuestsForMap(mapId)
				if type(worldQuestList) == "table" then
					for _, questInfo in ipairs(worldQuestList) do
						local questId = questInfo and questInfo.questId
						if type(questId) == "number" and questId > 0 then
							local questName = C_TaskQuest.GetQuestInfoByQuestID(questId)
							if type(questName) == "string" and questName ~= "" then
								self.nameplateQuestTitleCache[questName] = true
							end
						end
					end
				end
			end
		end
	end
end

function QuestTogether:GetCachedQuestObjectiveResult(guid)
	local cached = self.nameplateQuestObjectiveCache[guid]
	if not cached then
		return nil
	end

	local nowSeconds = self:GetNameplateNowSeconds()
	if cached.expiresAt and cached.expiresAt > nowSeconds then
		return cached.value
	end

	self.nameplateQuestObjectiveCache[guid] = nil
	return nil
end

function QuestTogether:SetCachedQuestObjectiveResult(guid, value)
	local nowSeconds = self:GetNameplateNowSeconds()
	self.nameplateQuestObjectiveCache[guid] = {
		value = value and true or false,
		expiresAt = nowSeconds + QUEST_SCAN_CACHE_TTL_SECONDS,
	}
end

function QuestTogether:GetNameplateTooltipScanGuid(unitToken, unitFrame)
	local plateFrame = unitFrame and unitFrame.PlateFrame or nil
	local candidateGuids = {
		unitFrame and unitFrame.namePlateUnitGUID or nil,
		unitFrame and unitFrame.qtTooltipScanGuid or nil,
		plateFrame and plateFrame.namePlateUnitGUID or nil,
		plateFrame and plateFrame.qtTooltipScanGuid or nil,
	}

	for index = 1, #candidateGuids do
		local candidateGuid = candidateGuids[index]
		if IsNonEmptyString(candidateGuid) then
			return candidateGuid
		end
	end

	local liveGuid = self:GetNameplateUnitGuid(unitToken)
	if IsNonEmptyString(liveGuid) then
		if unitFrame then
			unitFrame.qtTooltipScanGuid = liveGuid
		end
		if plateFrame then
			plateFrame.qtTooltipScanGuid = liveGuid
		end
		return liveGuid
	end

	return nil
end

function QuestTogether:IsQuestObjectiveViaTooltip(unitToken, unitFrame)
	if not unitToken or not self:DoesNameplateUnitExist(unitToken) then
		return false
	end
	if self:IsNameplateAugmentationBlockedInCurrentContext() then
		return false
	end
	if self:IsNameplateUnitPlayer(unitToken) or not self:CanPlayerAttackNameplateUnit(unitToken) then
		return false
	end

	local unitGuid = self:GetNameplateTooltipScanGuid(unitToken, unitFrame)
	if not IsNonEmptyString(unitGuid) then
		return false
	end

	local cachedValue = self:GetCachedQuestObjectiveResult(unitGuid)
	if cachedValue ~= nil then
		return cachedValue
	end

	if not next(self.nameplateQuestTitleCache) then
		self:RebuildNameplateQuestTitleCache()
	end
	if not next(self.nameplateQuestTitleCache) then
		self:SetCachedQuestObjectiveResult(unitGuid, false)
		return false
	end

	if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink and Enum and Enum.TooltipDataLineType) then
		self:SetCachedQuestObjectiveResult(unitGuid, false)
		return false
	end

	-- Tooltip retrieval can throw for stale GUID hyperlinks; skip tooltip fallback on failure.
	local okTooltip, tooltipData = pcall(function()
		return C_TooltipInfo.GetHyperlink("unit:" .. unitGuid)
	end)
	if not okTooltip then
		self:SetCachedQuestObjectiveResult(unitGuid, false)
		return false
	end
	if not tooltipData or type(tooltipData.lines) ~= "table" then
		self:SetCachedQuestObjectiveResult(unitGuid, false)
		return false
	end

	local scanLines = {}
	for _, lineData in ipairs(tooltipData.lines) do
		local lineType = self:SafeToNumber(lineData and lineData.type)

		if
			lineType == Enum.TooltipDataLineType.QuestObjective
			or lineType == Enum.TooltipDataLineType.QuestTitle
			or lineType == Enum.TooltipDataLineType.QuestPlayer
		then
			local leftText = self:SafeToString(lineData and lineData.leftText, "")
			if IsNonEmptyString(leftText) then
				scanLines[#scanLines + 1] = leftText
			end
		end
	end

	if #scanLines == 0 then
		self:SetCachedQuestObjectiveResult(unitGuid, false)
		return false
	end

	local isQuestUnit = false
	local hasUnfinishedObjective = false

	for lineIndex = 1, #scanLines do
		local lineText = scanLines[lineIndex]
		if self.nameplateQuestTitleCache[lineText] then
			isQuestUnit = true

			local objectiveIndex = lineIndex + 1
			local sawUnknownObjectiveLine = false
			while objectiveIndex <= #scanLines do
				local objectiveLineText = scanLines[objectiveIndex]
				if self.nameplateQuestTitleCache[objectiveLineText] then
					break
				end

				local progressState = GetObjectiveProgressState(objectiveLineText)
				if progressState == "unfinished" then
					hasUnfinishedObjective = true
					break
				elseif progressState == "unknown" and objectiveLineText ~= "" then
					sawUnknownObjectiveLine = true
				end
				objectiveIndex = objectiveIndex + 1
			end

			if not hasUnfinishedObjective and sawUnknownObjectiveLine then
				hasUnfinishedObjective = true
			end

			if hasUnfinishedObjective then
				break
			end
		end
	end

	local result = isQuestUnit and hasUnfinishedObjective
	self:SetCachedQuestObjectiveResult(unitGuid, result)
	return result
end

-- Resolve "is this unit a quest objective?" from available runtime signals.
--
-- Priority:
-- 1) Nameplate frame field used by Plater and other addons: unitFrame.namePlateIsQuestObjective.
-- 2) Public API: C_QuestLog.UnitIsRelatedToActiveQuest(unitToken).
-- 3) Public API: C_QuestLog.IsUnitOnQuest(unitToken, questID) against local tracked quests.
-- 4) Public API fallback: UnitIsQuestBoss(unitToken).
--
-- The first source catches engine-fed objective flags when present.
-- The C_QuestLog calls provide robust fallback on default Blizzard nameplates.
function QuestTogether:IsQuestObjectiveUnit(unitToken, unitFrame)
	local directFlag = GetBooleanFieldIfPresent(unitFrame, "namePlateIsQuestObjective")
	if directFlag == true then
		return true
	end

	local alternateFlag = GetBooleanFieldIfPresent(unitFrame, "isQuestObjective")
	if alternateFlag == true then
		return true
	end

	if not unitToken or not self:DoesNameplateUnitExist(unitToken) then
		return false
	end

	if self:IsNameplateUnitRelatedToActiveQuest(unitToken) then
		return true
	end

	for questId in pairs(self:GetPlayerTracker() or {}) do
		if self:IsNameplateUnitOnQuest(unitToken, questId) then
			return true
		end
	end

	if self:IsQuestObjectiveViaTooltip(unitToken, unitFrame) then
		return true
	end

	return self:IsNameplateUnitQuestBoss(unitToken)
end

function QuestTogether:ShouldShowQuestNameplateIcon(unitToken, unitFrame)
	if not self:GetOption("nameplateQuestIconEnabled") then
		return false
	end
	if self:GetLoadedKnownNameplateAddon() then
		return false
	end
	return self:IsQuestObjectiveNameplate(unitToken, unitFrame)
end

function QuestTogether:GetLoadedKnownNameplateAddon()
	if not self.API or not self.API.IsAddOnLoaded then
		return nil
	end

	for _, addonName in ipairs(self.knownNameplateAddons or {}) do
		if self.API.IsAddOnLoaded(addonName) then
			return addonName
		end
	end

	return nil
end

function QuestTogether:IsKnownNameplateAddonName(addonName)
	if type(addonName) ~= "string" or addonName == "" then
		return false
	end

	for _, candidate in ipairs(self.knownNameplateAddons or {}) do
		if candidate == addonName then
			return true
		end
	end

	return false
end

function QuestTogether:IsQuestObjectiveNameplate(unitToken, unitFrame)
	if not self.isEnabled then
		return false
	end
	if self:IsNameplateAugmentationBlockedInCurrentContext() then
		return false
	end

	if not self:IsNameplateUnitToken(unitToken) then
		return false
	end

	if not unitFrame then
		return false
	end

	-- Feature target is quest mobs/objective enemies, not friendly NPC nameplates.
	if not self:CanPlayerAttackNameplateUnit(unitToken) then
		return false
	end

	return self:IsQuestObjectiveUnit(unitToken, unitFrame)
end

-- Keep tinting conservative so we do not override important Blizzard states.
function QuestTogether:ShouldApplyQuestHealthTint(frame, isQuestObjective)
	if not self.isEnabled then
		return false
	end
	if self:IsNameplateAugmentationBlockedInCurrentContext() then
		return false
	end

	if not self:GetOption("nameplateQuestHealthColorEnabled") then
		return false
	end

	if not frame or not frame.unit then
		return false
	end

	if not self:IsNameplateUnitToken(frame.unit) then
		return false
	end

	if not frame.healthBar then
		return false
	end

	if not self:DoesNameplateUnitExist(frame.unit) then
		return false
	end

	-- Never tint players; this is intended for quest mobs/NPCs.
	if self:IsNameplateUnitPlayer(frame.unit) then
		return false
	end

	-- Avoid tinting non-hostile/friendly nameplates.
	if not self:CanPlayerAttackNameplateUnit(frame.unit) then
		return false
	end

	-- Preserve gray dead/disconnected/tap-denied states from Blizzard.
	if
		not self:IsNameplateUnitConnected(frame.unit)
		or self:IsNameplateUnitDead(frame.unit)
		or self:IsNameplateUnitTapDenied(frame.unit)
	then
		return false
	end

	if isQuestObjective ~= nil then
		return isQuestObjective == true
	end

	local cachedQuestObjective = self.nameplateQuestStateByUnitToken[frame.unit]
	if cachedQuestObjective ~= nil then
		return cachedQuestObjective == true
	end

	return self:IsQuestObjectiveNameplate(frame.unit, frame)
end

local function GetIconBarAnchor(unitFrame)
	if unitFrame.healthBar then
		return unitFrame.healthBar
	end
	if unitFrame.HealthBarsContainer then
		return unitFrame.HealthBarsContainer
	end
	return unitFrame
end

function QuestTogether:ApplyNameplateQuestIconStyle(iconFrame, unitFrame)
	if not iconFrame or not unitFrame then
		return
	end

	local icon = iconFrame.Icon or iconFrame
	local style = self:GetNameplateQuestIconStyle()
	local width = self.NAMEPLATE_QUEST_ICON_WIDTH
	local height = self.NAMEPLATE_QUEST_ICON_HEIGHT

	iconFrame:ClearAllPoints()

	if style == "left" then
		local barAnchor = GetIconBarAnchor(unitFrame)
		iconFrame:SetPoint("RIGHT", barAnchor, "LEFT", -1, 0)
	elseif style == "right" then
		local barAnchor = GetIconBarAnchor(unitFrame)
		iconFrame:SetPoint("LEFT", barAnchor, "RIGHT", 1, 0)
	elseif style == "prefix" then
		local nameText = unitFrame.name
		if nameText then
			-- Prefix places the icon directly against the unit name text.
			width = math.max(7, math.floor(width * 0.75 + 0.5))
			height = math.max(10, math.floor(height * 0.75 + 0.5))
			iconFrame:SetPoint("RIGHT", nameText, "LEFT", 0, 0)
		elseif unitFrame.HealthBarsContainer then
			iconFrame:SetPoint("BOTTOM", unitFrame.HealthBarsContainer, "TOP", 0, 11)
		else
			iconFrame:SetPoint("TOP", unitFrame, "TOP", 0, 7)
		end
	else
		if unitFrame.HealthBarsContainer then
			iconFrame:SetPoint("BOTTOM", unitFrame.HealthBarsContainer, "TOP", 0, 11)
		else
			iconFrame:SetPoint("TOP", unitFrame, "TOP", 0, 7)
		end
	end

	iconFrame:SetSize(width, height)
	icon:SetAllPoints(iconFrame)
end

local function EnsureQuestIcon(unitFrame)
	if not unitFrame then
		return nil
	end

	local existingIcon = QuestTogether.nameplateIconByUnitFrame[unitFrame]
	if existingIcon then
		QuestTogether:ApplyNameplateQuestIconStyle(existingIcon, unitFrame)
		return existingIcon
	end

	local iconFrame = CreateFrame("Frame", nil, unitFrame)
	iconFrame:SetFrameStrata(unitFrame:GetFrameStrata() or "LOW")
	iconFrame:SetFrameLevel(((unitFrame.GetFrameLevel and unitFrame:GetFrameLevel()) or 0) + 10)

	local icon = iconFrame:CreateTexture(nil, "ARTWORK")
	iconFrame.Icon = icon
	QuestTogether.nameplateIconByUnitFrame[unitFrame] = iconFrame

	if icon.SetAtlas and QuestTogether.NAMEPLATE_QUEST_ICON_ATLAS then
		icon:SetAtlas(QuestTogether.NAMEPLATE_QUEST_ICON_ATLAS, true)
		icon:SetTexCoord(0, 1, 0, 1)
	else
		icon:SetTexture(QuestTogether.NAMEPLATE_QUEST_ICON_TEXTURE)
		local coords = QuestTogether.NAMEPLATE_QUEST_ICON_TEX_COORDS
		if coords then
			icon:SetTexCoord(coords.left, coords.right, coords.top, coords.bottom)
		else
			icon:SetTexCoord(0, 1, 0, 1)
		end
	end
	QuestTogether:ApplyNameplateQuestIconStyle(iconFrame, unitFrame)

	iconFrame:Hide()
	return iconFrame
end

local function EnsureQuestHealthOverlay(unitFrame)
	if not unitFrame or not unitFrame.healthBar then
		return nil
	end

	local existingOverlay = QuestTogether.nameplateHealthOverlayByUnitFrame[unitFrame]
	if existingOverlay then
		return existingOverlay
	end

	local healthBar = unitFrame.healthBar
	local fillTexture = QuestTogether:CreateNameplateHealthOverlayTexture(healthBar, "ARTWORK", 0)
	local highlight = healthBar:CreateTexture(nil, "ARTWORK", nil, 1)
	if not fillTexture or not highlight then
		return nil
	end

	local overlay = {
		FillTexture = fillTexture,
		Highlight = highlight,
	}

	if fillTexture.Hide then
		fillTexture:Hide()
	end

	if highlight.SetBlendMode then
		highlight:SetBlendMode("ADD")
	end
	if highlight.Hide then
		highlight:Hide()
	end

	QuestTogether.nameplateHealthOverlayByUnitFrame[unitFrame] = overlay
	return overlay
end

local function AnchorQuestHealthFillTexture(texture, anchorTarget)
	if not texture or not anchorTarget then
		return
	end

	texture:ClearAllPoints()
	texture:SetPoint("TOPLEFT", anchorTarget, "TOPLEFT", 0, 0)
	texture:SetPoint("BOTTOMLEFT", anchorTarget, "BOTTOMLEFT", 0, 0)
	texture:SetPoint("TOPRIGHT", anchorTarget, "TOPRIGHT", 0, 0)
	texture:SetPoint("BOTTOMRIGHT", anchorTarget, "BOTTOMRIGHT", 0, 0)
end

local function GetQuestHealthOverlayAnchorTarget(unitFrame)
	if not unitFrame or not unitFrame.healthBar then
		return false
	end

	local healthBar = unitFrame.healthBar
	if healthBar.IsShown and not healthBar:IsShown() then
		return nil
	end

	local liveFillTexture = healthBar.GetStatusBarTexture and healthBar:GetStatusBarTexture() or nil
	if not liveFillTexture then
		return nil
	end
	if liveFillTexture.IsShown and not liveFillTexture:IsShown() then
		return nil
	end

	return liveFillTexture
end

ApplyQuestIconVisual = function(texture)
	if not texture then
		return
	end

	if texture.SetAtlas and QuestTogether.NAMEPLATE_QUEST_ICON_ATLAS then
		texture:SetAtlas(QuestTogether.NAMEPLATE_QUEST_ICON_ATLAS, true)
		texture:SetTexCoord(0, 1, 0, 1)
	else
		texture:SetTexture(QuestTogether.NAMEPLATE_QUEST_ICON_TEXTURE)
		local coords = QuestTogether.NAMEPLATE_QUEST_ICON_TEX_COORDS
		if coords then
			texture:SetTexCoord(coords.left, coords.right, coords.top, coords.bottom)
		else
			texture:SetTexCoord(0, 1, 0, 1)
		end
	end
end

local function ApplyAnnouncementIconVisual(texture, eventType, iconAsset, iconKind)
	if not texture then
		return
	end

	if type(iconAsset) == "string" and iconAsset ~= "" then
		if iconKind == "atlas" and texture.SetAtlas then
			texture:SetAtlas(iconAsset, true)
			texture:SetTexCoord(0, 1, 0, 1)
			return
		end

		texture:SetTexture(iconAsset)
		texture:SetTexCoord(0, 1, 0, 1)
		return
	end

	if QuestTogether.IsWorldQuestAnnouncementType and QuestTogether:IsWorldQuestAnnouncementType(eventType) then
		if texture.SetAtlas then
			texture:SetAtlas("worldquest-icon", true)
			texture:SetTexCoord(0, 1, 0, 1)
			return
		end
	end
	if QuestTogether.IsBonusObjectiveAnnouncementType and QuestTogether:IsBonusObjectiveAnnouncementType(eventType) then
		if texture.SetAtlas then
			texture:SetAtlas("Bonus-Objective-Star", true)
			texture:SetTexCoord(0, 1, 0, 1)
			return
		end
	end

	ApplyQuestIconVisual(texture)
end

local function CreateAnnouncementBubbleFrame(parentFrame)
	-- ChatBubbleTemplate is not guaranteed in all UI states; degrade to a plain frame bubble.
	local ok, bubble = pcall(CreateFrame, "Frame", nil, parentFrame, "ChatBubbleTemplate")
	if ok and bubble then
		return bubble
	end

	local fallbackBubble = CreateFrame("Frame", nil, parentFrame)
	local background = fallbackBubble:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(1, 1, 1, 0.92)
	fallbackBubble.Background = background

	local text = fallbackBubble:CreateFontString(nil, "ARTWORK", "ChatBubbleFont")
	fallbackBubble.String = text
	if text.SetNonSpaceWrap then
		text:SetNonSpaceWrap(true)
	end

	local tail = fallbackBubble:CreateTexture(nil, "ARTWORK")
	fallbackBubble.Tail = tail
	tail:SetColorTexture(1, 1, 1, 0.92)
	tail:SetSize(10, 10)
	tail:SetPoint("TOP", fallbackBubble, "BOTTOM", 0, 4)
	tail:SetRotation(math.rad(45))

	local icon = fallbackBubble:CreateTexture(nil, "ARTWORK")
	fallbackBubble.Icon = icon
	ApplyAnnouncementIconVisual(icon, nil)

	return fallbackBubble
end

local function ApplyAnnouncementBubbleLayering(hostFrame, unitFrame, bubble)
	if not hostFrame or not unitFrame or not bubble then
		return
	end

	local frameStrata = hostFrame:GetFrameStrata() or "LOW"
	local frameLevel = SafeUiNumber(unitFrame:GetFrameLevel(), 0) + 20
	bubble:SetFrameStrata(frameStrata)
	bubble:SetFrameLevel(frameLevel)
end

local function EnsureAnnouncementBubble(hostFrame)
	local unitFrame = GetAnnouncementBubbleUnitFrame(hostFrame)
	if not hostFrame or not unitFrame then
		return nil
	end

	local existingBubble = QuestTogether.nameplateBubbleByUnitFrame[unitFrame]
	if existingBubble then
		ApplyAnnouncementBubbleLayering(hostFrame, unitFrame, existingBubble)
		return existingBubble
	end

	local bubble = CreateAnnouncementBubbleFrame(hostFrame)
	if not bubble or not bubble.String then
		return nil
	end

	ApplyAnnouncementBubbleLayering(hostFrame, unitFrame, bubble)
	bubble:SetAlpha(0)
	bubble:Hide()

	bubble:ClearAllPoints()

	bubble.String:ClearAllPoints()
	bubble.String:SetJustifyH("LEFT")
	bubble.String:SetJustifyV("MIDDLE")
	bubble.String:SetTextColor(1, 0.82, 0, 1)
	if bubble.String.SetNonSpaceWrap then
		bubble.String:SetNonSpaceWrap(true)
	end
	if bubble.String.SetSpacing then
		bubble.String:SetSpacing(1)
	end

	if not bubble.Icon then
		local icon = bubble:CreateTexture(nil, "ARTWORK", nil, 1)
		bubble.Icon = icon
	end
	ApplyAnnouncementIconVisual(bubble.Icon, nil)

	if bubble.Tail then
		bubble.Tail:ClearAllPoints()
		bubble.Tail:SetPoint("TOP", bubble, "BOTTOM", 0, 6)
	end

	local animationGroup = bubble:CreateAnimationGroup()
	local fadeIn = animationGroup:CreateAnimation("Alpha")
	fadeIn:SetOrder(1)
	fadeIn:SetDuration(ANNOUNCEMENT_BUBBLE_FADE_IN_SECONDS)
	fadeIn:SetFromAlpha(0)
	fadeIn:SetToAlpha(1)

	local hold = animationGroup:CreateAnimation("Alpha")
	hold:SetOrder(2)
	local lifetimeSeconds = SafeUiNumber(GetAnnouncementBubbleLifetimeSeconds(), QuestTogether.DEFAULTS.profile.chatBubbleDuration)
	hold:SetDuration(
		math.max(
			0,
			lifetimeSeconds - ANNOUNCEMENT_BUBBLE_FADE_IN_SECONDS - ANNOUNCEMENT_BUBBLE_FADE_OUT_SECONDS
		)
	)
	hold:SetFromAlpha(1)
	hold:SetToAlpha(1)

	local fadeOut = animationGroup:CreateAnimation("Alpha")
	fadeOut:SetOrder(3)
	fadeOut:SetDuration(ANNOUNCEMENT_BUBBLE_FADE_OUT_SECONDS)
	fadeOut:SetFromAlpha(1)
	fadeOut:SetToAlpha(0)

	animationGroup:SetScript("OnFinished", function()
		bubble:SetAlpha(0)
		bubble:Hide()
	end)
	animationGroup:SetScript("OnStop", function()
		bubble:SetAlpha(0)
		bubble:Hide()
	end)
	bubble.animationGroup = animationGroup
	bubble.fadeInAnimation = fadeIn
	bubble.holdAnimation = hold
	bubble.fadeOutAnimation = fadeOut

	QuestTogether.nameplateBubbleByUnitFrame[unitFrame] = bubble
	return bubble
end

function QuestTogether:HideAnnouncementBubble(hostFrame)
	local unitFrame = GetAnnouncementBubbleUnitFrame(hostFrame)
	if not hostFrame or not unitFrame then
		return
	end

	local bubble = self.nameplateBubbleByUnitFrame[unitFrame]
	if not bubble then
		return
	end
	self:Debugf("bubble", "Hiding bubble host=%s", tostring(unitFrame.unit or unitFrame:GetName() or "<screen>"))

	if bubble.animationGroup and bubble.animationGroup:IsPlaying() then
		bubble.animationGroup:Stop()
	else
		bubble:SetAlpha(0)
		bubble:Hide()
	end
end

function QuestTogether:RefreshActiveAnnouncementBubbles()
	local activeCount = 0
	for _ in pairs(self.nameplateBubbleByUnitFrame) do
		activeCount = activeCount + 1
	end
	self:Debugf("bubble", "Refreshing active bubbles count=%d", activeCount)
	if self:IsNameplateAugmentationBlockedInCurrentContext() then
		for _, bubble in pairs(self.nameplateBubbleByUnitFrame) do
			if bubble then
				if bubble.animationGroup and bubble.animationGroup:IsPlaying() then
					bubble.animationGroup:Stop()
				else
					bubble:SetAlpha(0)
					bubble:Hide()
				end
			end
		end
		return
	end
	for unitFrame, bubble in pairs(self.nameplateBubbleByUnitFrame) do
		if bubble and bubble.qtCurrentText and bubble.qtCurrentText ~= "" then
			local hostFrame = bubble.qtHostFrame
			if hostFrame and self:GetOption("showChatBubbles") then
				if hostFrame == self.announcementBubbleScreenHostFrame or (hostFrame.IsShown and hostFrame:IsShown()) then
					self:ShowAnnouncementBubbleOnNameplate(
						hostFrame,
						bubble.qtCurrentText,
						bubble.qtCurrentEventType,
						bubble.qtCurrentIconAsset,
						bubble.qtCurrentIconKind
					)
				else
					self:HideAnnouncementBubble(hostFrame)
				end
			elseif hostFrame then
				self:HideAnnouncementBubble(hostFrame)
			elseif unitFrame then
				self.nameplateBubbleByUnitFrame[unitFrame] = nil
			end
		end
	end
end

function QuestTogether:GetAnnouncementBubbleHostFrameForUnit(unitToken)
	if unitToken == "player" then
		self:Debug("Resolved player bubble host to personal screen anchor", "bubble")
		return GetAnnouncementBubbleScreenHostFrame()
	end

	local namePlateFrameBase = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unitToken, false)
	if namePlateFrameBase and namePlateFrameBase.UnitFrame and namePlateFrameBase:IsShown() then
		self:Debugf("bubble", "Resolved bubble host for unit=%s", tostring(unitToken))
		return namePlateFrameBase
	end
	self:Debugf("bubble", "No bubble host found for unit=%s", tostring(unitToken))
	return nil
end

function QuestTogether:TryShowAnnouncementBubbleOnUnitNameplate(unitToken, text, eventType, iconAsset, iconKind)
	local hostFrame = self:GetAnnouncementBubbleHostFrameForUnit(unitToken)
	if hostFrame then
		if not self:ShowAnnouncementBubbleOnNameplate(hostFrame, text, eventType, iconAsset, iconKind) then
			self:Debugf("bubble", "Failed to show bubble on host for unit=%s", tostring(unitToken))
			return false, "Unable to show a bubble on that nameplate."
		end
		local unitName = self.API.UnitName and self.API.UnitName(unitToken) or nil
		self:Debugf("bubble", "Showing bubble on unit=%s text=%s", tostring(unitToken), tostring(text))
		return true, unitName or unitToken
	end

	if unitToken ~= "player" then
		return false, "No visible nameplate found for that unit."
	end
	return false, "Your personal bubble anchor is unavailable."
end

function QuestTogether:ShowAnnouncementBubbleOnNameplate(namePlateFrameBase, text, eventType, iconAsset, iconKind)
	local unitFrame = GetAnnouncementBubbleUnitFrame(namePlateFrameBase)
	if not namePlateFrameBase or not unitFrame then
		return false
	end
	if self:IsNameplateAugmentationBlockedInCurrentContext() then
		self:Debug("Skipping announcement bubble in blocked nameplate context", "bubble")
		return false
	end

	local message = tostring(text or "")
	message = string.gsub(message, "^%s+", "")
	message = string.gsub(message, "%s+$", "")
	if message == "" then
		self:Debug("Skipping empty bubble message", "bubble")
		return false
	end

	local bubble = EnsureAnnouncementBubble(namePlateFrameBase)
	if not bubble or not bubble.String then
		self:Debug("Failed to create or resolve bubble frame", "bubble")
		return false
	end
	bubble.qtCurrentText = message
	bubble.qtCurrentEventType = eventType
	bubble.qtCurrentIconAsset = iconAsset
	bubble.qtCurrentIconKind = iconKind
	bubble.qtHostFrame = namePlateFrameBase

	local anchorFrame = unitFrame.HealthBarsContainer or unitFrame
	local visualConfig = GetAnnouncementBubbleVisualConfig()
	local inset = SafeUiNumber(visualConfig.inset, 16)
	local minTextWidth = SafeUiNumber(visualConfig.minTextWidth, 48)
	local maxTextWidth = SafeUiNumber(visualConfig.maxTextWidth, 220)
	local iconSize = SafeUiNumber(visualConfig.iconSize, 18)
	local iconGap = SafeUiNumber(visualConfig.iconGap, 8)
	local fontSize = SafeUiNumber(visualConfig.fontSize, 14)
	local lifetimeSeconds = SafeUiNumber(GetAnnouncementBubbleLifetimeSeconds(), QuestTogether.DEFAULTS.profile.chatBubbleDuration)

	if bubble.animationGroup and bubble.animationGroup:IsPlaying() then
		bubble.animationGroup:Stop()
	end

	if bubble.holdAnimation then
		local holdSeconds = math.max(
			0,
			lifetimeSeconds - ANNOUNCEMENT_BUBBLE_FADE_IN_SECONDS - ANNOUNCEMENT_BUBBLE_FADE_OUT_SECONDS
		)
		bubble.holdAnimation:SetDuration(holdSeconds)
	end

	local fontPath, _, fontFlags = bubble.String:GetFont()
	if fontPath and bubble.String.SetFont then
		bubble.String:SetFont(fontPath, fontSize, fontFlags)
	end

	bubble.String:SetWidth(maxTextWidth)
	bubble.String:SetText(message)

	local unboundedWidth = minTextWidth
	if bubble.String.GetUnboundedStringWidth then
		unboundedWidth = SafeUiNumber(bubble.String:GetUnboundedStringWidth(), minTextWidth)
	end
	local targetTextWidth = math.min(
		maxTextWidth,
		math.max(minTextWidth, unboundedWidth)
	)
	bubble.String:SetWidth(targetTextWidth)

	local textHeight = SafeUiNumber(bubble.String:GetStringHeight(), 0)
	local contentHeight = math.max(iconSize, textHeight)
	local contentWidth = iconSize + iconGap + targetTextWidth
	local bubbleWidth = contentWidth + (inset * 2)
	local bubbleHeight = contentHeight + (inset * 2)
	self:Debugf(
		"bubble",
		"Render bubble host=%s width=%d height=%d font=%d duration=%.1f text=%s",
		tostring(unitFrame.unit or unitFrame:GetName() or "<screen>"),
		bubbleWidth,
		bubbleHeight,
		fontSize,
		lifetimeSeconds,
		tostring(message)
	)

	bubble:ClearAllPoints()
	bubble:SetPoint("BOTTOM", anchorFrame, "TOP", 0, ANNOUNCEMENT_BUBBLE_Y_OFFSET)
	bubble:SetSize(bubbleWidth, bubbleHeight)

	if bubble.Icon then
		ApplyAnnouncementIconVisual(bubble.Icon, eventType, iconAsset, iconKind)
		bubble.Icon:ClearAllPoints()
		bubble.Icon:SetSize(iconSize, iconSize)
		bubble.Icon:SetPoint("CENTER", bubble, "CENTER", -((iconGap + targetTextWidth) / 2), 0)
		bubble.Icon:Show()
	end

	bubble.String:ClearAllPoints()
	bubble.String:SetWidth(targetTextWidth)
	bubble.String:SetPoint("CENTER", bubble, "CENTER", ((iconSize + iconGap) / 2), 0)

	if bubble.SetClampRectInsets then
		bubble:SetClampRectInsets(0, 0, 0, 0)
	end

	bubble:SetAlpha(0)
	bubble:Show()
	if bubble.Tail then
		bubble.Tail:Show()
	end
	if bubble.animationGroup then
		bubble.animationGroup:Play()
	end
	return true
end

function QuestTogether:ShowAnnouncementBubbleOnUnitNameplate(unitToken, text, eventType, iconAsset, iconKind)
	if type(unitToken) ~= "string" or unitToken == "" then
		return false, "No unit token was provided."
	end
	if self:IsNameplateAugmentationBlockedInCurrentContext() then
		return false, "Nameplate augmentation is unavailable in instances."
	end

	if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then
		if unitToken ~= "player" then
			return false, "Nameplates are unavailable."
		end
	end

	return self:TryShowAnnouncementBubbleOnUnitNameplate(unitToken, text, eventType, iconAsset, iconKind)
end

function QuestTogether:ShowAnnouncementBubbleOnRandomVisiblePlayer(text)
	if self:IsNameplateAugmentationBlockedInCurrentContext() then
		return false, "Nameplate augmentation is unavailable in instances."
	end

	local candidateNameplates = {}

	self:ForEachVisibleNamePlate(function(frame)
		if not frame or not frame.UnitFrame then
			return
		end

		local unitToken = (frame.GetUnit and frame:GetUnit()) or nil
		if not unitToken or not self:IsNameplateUnitToken(unitToken) then
			return
		end
		if not self:IsNameplateUnitPlayer(unitToken) then
			return
		end
		if UnitIsUnit and UnitIsUnit(unitToken, "player") then
			return
		end

		candidateNameplates[#candidateNameplates + 1] = frame
	end)

	if #candidateNameplates == 0 then
		return false, "No visible player nameplates found."
	end

	local randomIndex = self.API.Random(1, #candidateNameplates)
	local namePlateFrameBase = candidateNameplates[randomIndex]
	if not self:ShowAnnouncementBubbleOnNameplate(namePlateFrameBase, text) then
		return false, "Unable to show a bubble on the selected nameplate."
	end

	local unitToken = (namePlateFrameBase.GetUnit and namePlateFrameBase:GetUnit()) or nil
	local unitName = unitToken and self.API.UnitName(unitToken) or nil
	return true, unitName or "Unknown"
end

function QuestTogether:ApplyQuestTintToNameplate(unitFrame)
	if not unitFrame then
		return false
	end

	local overlay = EnsureQuestHealthOverlay(unitFrame)
	if not overlay then
		return false
	end

	local healthBar = unitFrame.healthBar
	local color = self:GetNameplateQuestHealthColor()
	local highlightRed = math.min(1, color.r + 0.18)
	local highlightGreen = math.min(1, color.g + 0.18)
	local highlightBlue = math.min(1, color.b + 0.12)
	local anchorTarget = GetQuestHealthOverlayAnchorTarget(unitFrame)
	if not anchorTarget then
		self:RestoreNameplateHealthColor(unitFrame)
		return false
	end
	AnchorQuestHealthFillTexture(overlay.FillTexture, anchorTarget)
	AnchorQuestHealthFillTexture(overlay.Highlight, anchorTarget)

	if overlay.FillTexture then
		if overlay.FillTexture.SetVertexColor then
			overlay.FillTexture:SetVertexColor(color.r, color.g, color.b, 1)
		end
		overlay.FillTexture:Show()
	end
	overlay.Highlight:SetColorTexture(highlightRed, highlightGreen, highlightBlue, 0.14)
	overlay.Highlight:Show()

	if healthBar and healthBar.GetAlpha then
		local alpha = healthBar:GetAlpha() or 1
		if overlay.FillTexture and overlay.FillTexture.SetAlpha then
			overlay.FillTexture:SetAlpha(alpha)
		end
		if overlay.Highlight.SetAlpha then
			overlay.Highlight:SetAlpha(alpha)
		end
	end

	local unitToken = unitFrame.unit or unitFrame.displayedUnit
	if type(unitToken) == "string" and unitToken ~= "" then
		self.nameplateHealthTintRetryCountByUnitToken[unitToken] = nil
	end

	return true
end

function QuestTogether:RestoreNameplateHealthColor(unitFrame)
	if not unitFrame then
		return
	end

	local overlay = self.nameplateHealthOverlayByUnitFrame[unitFrame]
	if overlay then
		if overlay.FillTexture and overlay.FillTexture.Hide then
			overlay.FillTexture:Hide()
		end
		if overlay.Highlight and overlay.Highlight.Hide then
			overlay.Highlight:Hide()
		end
	end
end

function QuestTogether:RefreshNameplateHealthTint(namePlateFrameBase, isQuestObjective)
	if not namePlateFrameBase or not namePlateFrameBase.UnitFrame then
		return
	end

	local unitFrame = namePlateFrameBase.UnitFrame
	local unitToken = unitFrame.unit or unitFrame.displayedUnit
	local shouldTint = self:ShouldApplyQuestHealthTint(unitFrame, isQuestObjective)
	if shouldTint then
		local applied = self:ApplyQuestTintToNameplate(unitFrame)
		if not applied and type(unitToken) == "string" and unitToken ~= "" then
			local retryCount = self.nameplateHealthTintRetryCountByUnitToken[unitToken] or 0
			if retryCount < 3 then
				self.nameplateHealthTintRetryCountByUnitToken[unitToken] = retryCount + 1
				self:ScheduleNameplateHealthTintRefresh(unitToken, 0.05 * (retryCount + 1))
			end
		end
	else
		if type(unitToken) == "string" and unitToken ~= "" then
			self.nameplateHealthTintRetryCountByUnitToken[unitToken] = nil
		end
		self:RestoreNameplateHealthColor(unitFrame)
	end
end

function QuestTogether:ScheduleNameplateHealthTintRefresh(unitToken, delaySeconds)
	if not self:IsNameplateUnitToken(unitToken) then
		return
	end
	if self.nameplateHealthTintRefreshPendingByUnitToken[unitToken] then
		return
	end

	self.nameplateHealthTintRefreshPendingByUnitToken[unitToken] = true
	self.API.Delay(delaySeconds or 0, function()
		self.nameplateHealthTintRefreshPendingByUnitToken[unitToken] = nil
		if not self.isEnabled or not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then
			return
		end

		local namePlateFrameBase = C_NamePlate.GetNamePlateForUnit(unitToken, false)
		if not namePlateFrameBase or not namePlateFrameBase.UnitFrame or not namePlateFrameBase:IsShown() then
			return
		end

		local unitFrame = namePlateFrameBase.UnitFrame
		local isQuestObjective = self.nameplateQuestStateByUnitToken[unitToken]
		if isQuestObjective == nil then
			isQuestObjective = self:IsQuestObjectiveNameplate(unitToken, unitFrame)
			self.nameplateQuestStateByUnitToken[unitToken] = isQuestObjective and true or false
		end

		local shouldTint = self:ShouldApplyQuestHealthTint(unitFrame, isQuestObjective)
		if shouldTint then
			self:ApplyQuestTintToNameplate(unitFrame)
		else
			self:RestoreNameplateHealthColor(unitFrame)
		end
	end)
end

function QuestTogether:ScheduleNameplateRefresh(unitToken)
	if not self:IsNameplateUnitToken(unitToken) then
		return
	end
	if self.nameplateRefreshPendingByUnitToken[unitToken] then
		return
	end

	self.nameplateRefreshPendingByUnitToken[unitToken] = true
	self.API.Delay(0, function()
		self.nameplateRefreshPendingByUnitToken[unitToken] = nil
		if not self.isEnabled or not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then
			return
		end

		local namePlateFrameBase = C_NamePlate.GetNamePlateForUnit(unitToken, false)
		if not namePlateFrameBase or not namePlateFrameBase.UnitFrame or not namePlateFrameBase:IsShown() then
			return
		end

		self:RefreshNameplateIcon(namePlateFrameBase)
	end)
end

function QuestTogether:RefreshNameplateIcon(namePlateFrameBase)
	if not namePlateFrameBase or not namePlateFrameBase.UnitFrame then
		return
	end

	local unitToken = (namePlateFrameBase.GetUnit and namePlateFrameBase:GetUnit()) or nil
	local unitFrame = namePlateFrameBase.UnitFrame
	local isQuestObjective = self:IsQuestObjectiveNameplate(unitToken, unitFrame)
	local shouldShow = self:ShouldShowQuestNameplateIcon(unitToken, unitFrame)
	local icon = self.nameplateIconByUnitFrame[unitFrame]
	if unitToken then
		self.nameplateQuestStateByUnitToken[unitToken] = isQuestObjective and true or false
	end
	self:RefreshNameplateHealthTint(namePlateFrameBase, isQuestObjective)
	if isQuestObjective and type(unitToken) == "string" and unitToken ~= "" then
		self:ScheduleNameplateHealthTintRefresh(unitToken, 0.05)
	end

	if shouldShow then
		if icon then
			self:ApplyNameplateQuestIconStyle(icon, unitFrame)
		else
			icon = EnsureQuestIcon(unitFrame)
		end
		if not icon then
			return
		end
		icon:Show()
	elseif icon then
		icon:Hide()
	end
end

function QuestTogether:HideNameplateIcon(namePlateFrameBase)
	if not namePlateFrameBase or not namePlateFrameBase.UnitFrame then
		return
	end

	local icon = self.nameplateIconByUnitFrame[namePlateFrameBase.UnitFrame]
	if icon then
		icon:Hide()
	end
	self:HideAnnouncementBubble(namePlateFrameBase)
	self:RestoreNameplateHealthColor(namePlateFrameBase.UnitFrame)
end

function QuestTogether:ForEachVisibleNamePlate(callback)
	if type(callback) ~= "function" or not C_NamePlate or not C_NamePlate.GetNamePlates then
		return
	end

	for _, frame in pairs(C_NamePlate.GetNamePlates(false)) do
		callback(frame)
	end
end

function QuestTogether:FindVisiblePlayerNameplateForSender(senderGUID, senderName)
	local normalizedSenderName = self:NormalizeMemberName(senderName)
	local matchedFrame = nil

	self:ForEachVisibleNamePlate(function(frame)
		if matchedFrame or not frame or not frame.UnitFrame then
			return
		end

		local unitToken = (frame.GetUnit and frame:GetUnit()) or nil
		if not unitToken or not self:IsNameplateUnitToken(unitToken) then
			return
		end
		if not self:IsNameplateUnitPlayer(unitToken) then
			return
		end

		local unitGUID = self:GetNameplateUnitGuid(unitToken)
		if senderGUID and senderGUID ~= "" and unitGUID == senderGUID then
			matchedFrame = frame
			return
		end

			if normalizedSenderName then
				local unitName, unitRealm = self.API.UnitFullName(unitToken)
				local fullUnitName = nil
				if unitName then
					local realmName = self:SafeStripWhitespace(unitRealm or self.API.GetRealmName() or "", "")
					fullUnitName = tostring(unitName) .. "-" .. tostring(realmName)
				else
					fullUnitName = self:NormalizeMemberName(self.API.UnitName(unitToken))
				end
				if fullUnitName and self:NormalizeMemberName(fullUnitName) == normalizedSenderName then
					matchedFrame = frame
				end
			end
	end)

	self:Debugf(
		"nameplate",
		"FindVisiblePlayerNameplateForSender guid=%s sender=%s matched=%s",
		tostring(senderGUID),
		tostring(normalizedSenderName),
		tostring(matchedFrame ~= nil)
	)
	return matchedFrame
end

function QuestTogether:DoesUnitTokenMatchSender(unitToken, senderGUID, senderName)
	if type(unitToken) ~= "string" or unitToken == "" then
		return false
	end
	if not self.API.UnitExists or not self.API.UnitExists(unitToken) then
		return false
	end
	if not self:IsNameplateUnitPlayer(unitToken) then
		return false
	end

	local unitGUID = self.API.UnitGUID and self.API.UnitGUID(unitToken) or nil
	if senderGUID and senderGUID ~= "" and unitGUID == senderGUID then
		return true
	end

	local normalizedSenderName = self:NormalizeMemberName(senderName)
	if not normalizedSenderName then
		return false
	end

	local unitName, unitRealm = self.API.UnitFullName and self.API.UnitFullName(unitToken)
	local fullUnitName = nil
	if unitName then
		local realmName = self:SafeStripWhitespace(unitRealm or self.API.GetRealmName() or "", "")
		fullUnitName = tostring(unitName) .. "-" .. tostring(realmName)
	else
		fullUnitName = self:NormalizeMemberName(self.API.UnitName and self.API.UnitName(unitToken) or nil)
	end

	return fullUnitName ~= nil and self:NormalizeMemberName(fullUnitName) == normalizedSenderName
end

function QuestTogether:FindNearbyPlayerUnitTokenForSender(senderGUID, senderName)
	local candidateUnits = {
		"target",
		"mouseover",
		"focus",
	}

	for _, unitToken in ipairs(candidateUnits) do
		if self:DoesUnitTokenMatchSender(unitToken, senderGUID, senderName) then
			self:Debugf("nameplate", "Nearby player unit token match sender=%s unit=%s", tostring(senderName), tostring(unitToken))
			return unitToken
		end
	end

	self:Debugf("nameplate", "No nearby unit token match sender=%s", tostring(senderName))
	return nil
end

function QuestTogether:RefreshNameplateAugmentation()
	if self:IsNameplateAugmentationBlockedInCurrentContext() then
		wipe(self.nameplateQuestStateByUnitToken)
		self:ForEachVisibleNamePlate(function(frame)
			self:HideNameplateIcon(frame)
		end)
		self:RefreshActiveAnnouncementBubbles()
		return
	end

	self:ForEachVisibleNamePlate(function(frame)
		self:RefreshNameplateIcon(frame)
	end)
end

function QuestTogether:ScheduleFullNameplateRefresh(delaySeconds)
	self.nameplateFullRefreshGeneration = (self.nameplateFullRefreshGeneration or 0) + 1
	local generation = self.nameplateFullRefreshGeneration
	local delayList = {
		delaySeconds or 0,
		0.10,
		0.25,
		0.50,
	}

	for index = 1, #delayList do
		local scheduledDelay = delayList[index]
		self.API.Delay(scheduledDelay, function()
			if generation ~= self.nameplateFullRefreshGeneration then
				return
			end
			if not self.isEnabled then
				return
			end

			self:RebuildNameplateQuestTitleCache()
			self:ClearNameplateQuestObjectiveCache()
			self:RefreshNameplateAugmentation()
		end)
	end
end

function QuestTogether:OnNameplateAdded(unitToken)
	if not self.isEnabled then
		return
	end

	if not self:IsNameplateUnitToken(unitToken) then
		return
	end
	if self:IsNameplateAugmentationBlockedInCurrentContext() then
		self.nameplateQuestStateByUnitToken[unitToken] = nil
		return
	end

	self.nameplateQuestStateByUnitToken[unitToken] = nil
	self.nameplateHealthTintRetryCountByUnitToken[unitToken] = nil

	self:ScheduleNameplateRefresh(unitToken)
end

function QuestTogether:OnNameplateRemoved(unitToken)
	if not self:IsNameplateUnitToken(unitToken) then
		return
	end

	self.nameplateQuestStateByUnitToken[unitToken] = nil
	self.nameplateRefreshPendingByUnitToken[unitToken] = nil
	self.nameplateHealthTintRefreshPendingByUnitToken[unitToken] = nil
	self.nameplateHealthTintRetryCountByUnitToken[unitToken] = nil

	local namePlateFrameBase = C_NamePlate.GetNamePlateForUnit(unitToken, false)
	if namePlateFrameBase then
		self:HideNameplateIcon(namePlateFrameBase)
	end
end

function QuestTogether:TryInstallNameplateHooks()
	if self.nameplateHooksInstalled then
		self:Debug("Nameplate hooks already installed", "nameplate")
		return
	end

	-- Avoid secure add/remove hooks into Blizzard's nameplate setup path. The one safe hook we
	-- do want is the global options-update pass, so we can reapply our quest visuals after
	-- Blizzard restyles all visible nameplates.
	if
		not self.nameplateOptionsHookInstalled
		and type(hooksecurefunc) == "function"
		and type(NamePlateDriverMixin) == "table"
		and type(NamePlateDriverMixin.UpdateNamePlateOptions) == "function"
	then
		hooksecurefunc(NamePlateDriverMixin, "UpdateNamePlateOptions", function()
			QuestTogether:Debug("Detected Blizzard nameplate options update; scheduling reapply", "nameplate")
			QuestTogether:ScheduleFullNameplateRefresh(0.05)
		end)
		self.nameplateOptionsHookInstalled = true
	end

	-- Avoid additional secure hooks into Blizzard's frame-setup path. Event-driven refreshes are
	-- enough for our icon and announcement bubble visuals.
	--[[
	if
		not self.nameplateApplyFrameOptionsHookInstalled
		and type(hooksecurefunc) == "function"
		and type(NamePlateBaseMixin) == "table"
		and type(NamePlateBaseMixin.ApplyFrameOptions) == "function"
	then
		hooksecurefunc(NamePlateBaseMixin, "ApplyFrameOptions", function(namePlateFrameBase)
			if not QuestTogether.isEnabled or not namePlateFrameBase then
				return
			end

			local unitToken = namePlateFrameBase.GetUnit and namePlateFrameBase:GetUnit() or namePlateFrameBase.unitToken
			if QuestTogether:IsNameplateUnitToken(unitToken) then
				QuestTogether:ScheduleNameplateRefresh(unitToken)
			end
		end)
		self.nameplateApplyFrameOptionsHookInstalled = true
	end
	]]

	self.nameplateHooksInstalled = true
	self:Debug("Using event-driven nameplate augmentation without shared health-color hooks", "nameplate")
end

function QuestTogether:EnableNameplateAugmentation()
	if not self.nameplateEventFrame then
		self.nameplateEventFrame = CreateFrame("Frame")
		self.nameplateRegisteredEvents = self.nameplateRegisteredEvents or {}
		self.nameplateEventFrame:SetScript("OnEvent", function(_, eventName, ...)
			if eventName == "NAME_PLATE_UNIT_ADDED" then
				self:OnNameplateAdded(...)
			elseif eventName == "NAME_PLATE_UNIT_REMOVED" then
				self:OnNameplateRemoved(...)
			elseif
					eventName == "QUEST_LOG_UPDATE"
					or eventName == "PLAYER_ENTERING_WORLD"
					or eventName == "QUEST_REMOVED"
					or eventName == "QUEST_ACCEPTED"
					or eventName == "QUEST_ACCEPT_CONFIRM"
					or eventName == "QUEST_COMPLETE"
					or eventName == "QUEST_POI_UPDATE"
					or eventName == "QUEST_DETAIL"
					or eventName == "QUEST_FINISHED"
					or eventName == "QUEST_GREETING"
			then
				self:RebuildNameplateQuestTitleCache()
				self:ClearNameplateQuestObjectiveCache()
				self:RefreshNameplateAugmentation()
			elseif eventName == "DISPLAY_SIZE_CHANGED" then
				self:ScheduleFullNameplateRefresh(0.05)
			elseif eventName == "CVAR_UPDATE" then
				local cvarName = ...
				if type(cvarName) == "string" and string.find(string.lower(cvarName), "nameplate", 1, true) then
					self:Debugf("nameplate", "Refreshing nameplate augmentation after CVar change=%s", tostring(cvarName))
					self:ScheduleFullNameplateRefresh(0.05)
				end
			elseif eventName == "UNIT_HEALTH" or eventName == "UNIT_MAXHEALTH" or eventName == "UNIT_CONNECTION" then
				local unitToken = ...
				if self:IsNameplateUnitToken(unitToken) then
					self:ScheduleNameplateHealthTintRefresh(unitToken)
				end
			elseif eventName == "UNIT_QUEST_LOG_CHANGED" then
				local unitToken = ...
				if unitToken == "player" then
					self:RebuildNameplateQuestTitleCache()
					self:ClearNameplateQuestObjectiveCache()
					self:RefreshNameplateAugmentation()
				end
			end
		end)
	end

	local function RegisterNameplateEvent(addon, eventName)
		-- Event availability differs by client build; keep registration best-effort.
		local ok = pcall(addon.nameplateEventFrame.RegisterEvent, addon.nameplateEventFrame, eventName)
		if ok then
			addon.nameplateRegisteredEvents[eventName] = true
			addon:Debugf("nameplate", "Registered augmentation event=%s", tostring(eventName))
		else
			addon.nameplateRegisteredEvents[eventName] = nil
			addon:Debugf("nameplate", "Failed to register augmentation event=%s", tostring(eventName))
		end
	end

	self:TryInstallNameplateHooks()
	self:RebuildNameplateQuestTitleCache()
	self:ClearNameplateQuestObjectiveCache()
	self:Debug("Enabling nameplate augmentation events", "nameplate")
	RegisterNameplateEvent(self, "NAME_PLATE_UNIT_ADDED")
	RegisterNameplateEvent(self, "NAME_PLATE_UNIT_REMOVED")
	RegisterNameplateEvent(self, "QUEST_LOG_UPDATE")
	RegisterNameplateEvent(self, "QUEST_REMOVED")
	RegisterNameplateEvent(self, "QUEST_ACCEPTED")
	RegisterNameplateEvent(self, "QUEST_ACCEPT_CONFIRM")
	RegisterNameplateEvent(self, "QUEST_COMPLETE")
	RegisterNameplateEvent(self, "QUEST_POI_UPDATE")
	RegisterNameplateEvent(self, "QUEST_DETAIL")
	RegisterNameplateEvent(self, "QUEST_FINISHED")
	RegisterNameplateEvent(self, "QUEST_GREETING")
	RegisterNameplateEvent(self, "UNIT_QUEST_LOG_CHANGED")
	RegisterNameplateEvent(self, "UNIT_HEALTH")
	RegisterNameplateEvent(self, "UNIT_MAXHEALTH")
	RegisterNameplateEvent(self, "UNIT_CONNECTION")
	RegisterNameplateEvent(self, "PLAYER_ENTERING_WORLD")
	RegisterNameplateEvent(self, "DISPLAY_SIZE_CHANGED")
	RegisterNameplateEvent(self, "CVAR_UPDATE")
	self:RefreshNameplateAugmentation()
end

function QuestTogether:DisableNameplateAugmentation()
	if not self.nameplateEventFrame then
		return
	end
	self:Debug("Disabling nameplate augmentation", "nameplate")

	for eventName in pairs(self.nameplateRegisteredEvents or {}) do
		-- Unregister should never break disable flow if an event was already invalidated.
		pcall(self.nameplateEventFrame.UnregisterEvent, self.nameplateEventFrame, eventName)
		self:Debugf("nameplate", "Unregistered augmentation event=%s", tostring(eventName))
	end
	if self.nameplateRegisteredEvents then
		wipe(self.nameplateRegisteredEvents)
	end

	-- Hide our icon overlays and clear cached quest objective state.
	wipe(self.nameplateQuestStateByUnitToken)
	wipe(self.nameplateRefreshPendingByUnitToken)
	wipe(self.nameplateHealthTintRefreshPendingByUnitToken)
	self:ForEachVisibleNamePlate(function(frame)
		self:HideNameplateIcon(frame)
	end)
	wipe(self.nameplateHealthOverlayByUnitFrame)
end
