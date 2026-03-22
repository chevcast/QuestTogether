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
local DEFAULT_ENABLE_TOOLTIP_QUEST_SCAN_FALLBACK = true
local PLATER_QUEST_STATE_REFRESH_DELAY_SECONDS = 1.0
local PLATER_INITIAL_QUEST_LOG_UPDATED_DELAY_SECONDS = 4.1
local PLATER_INITIAL_FULL_REFRESH_DELAY_SECONDS = 5.1
local NAMEPLATE_WORLD_MAP_REFRESH_DELAY_SECONDS = 0.2
local NAMEPLATE_SCAN_TOOLTIP_NAME = "QuestTogetherNameplateScanTooltip"
local ANNOUNCEMENT_BUBBLE_Y_OFFSET = 22
local ANNOUNCEMENT_BUBBLE_FADE_IN_SECONDS = 0.2
local ANNOUNCEMENT_BUBBLE_FADE_OUT_SECONDS = 0.4
local PERSONAL_BUBBLE_SETTINGS_DIALOG_WIDTH = 380
local PERSONAL_BUBBLE_SETTINGS_DIALOG_HEIGHT = 220
local ApplyQuestIconVisual
local EnsureQuestIcon
local ResolveNameplateUnitToken
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

local function IsFrameForbidden(frame)
	if QuestTogether and QuestTogether.IsForbiddenFrame then
		return QuestTogether:IsForbiddenFrame(frame)
	end

	local frameType = type(frame)
	if not frame or (frameType ~= "table" and frameType ~= "userdata") then
		return false
	end
	if not frame.IsForbidden then
		return false
	end

	-- Forbidden checks can be unavailable on some userdata-backed frames; fail open.
	local ok, forbidden = pcall(frame.IsForbidden, frame)
	return ok and forbidden and true or false
end

local function CanMutateFrame(frame)
	if QuestTogether and QuestTogether.CanAccessForeignFrame then
		return QuestTogether:CanAccessForeignFrame(frame)
	end
	return frame ~= nil and not IsFrameForbidden(frame)
end

local function SafeText(value, fallback)
	if QuestTogether and QuestTogether.SafeToString then
		return QuestTogether:SafeToString(value, fallback or "")
	end

	local ok, text = pcall(tostring, value)
	if ok then
		return text
	end
	return fallback or ""
end

local function SafeMatch(text, pattern)
	local safeText = SafeText(text, "")
	if safeText == "" then
		return nil
	end

	local ok, first, second = pcall(string.match, safeText, pattern)
	if not ok then
		return nil
	end

	return first, second
end

local function SafeTrimText(text)
	if QuestTogether and QuestTogether.SafeTrimString then
		return QuestTogether:SafeTrimString(text, "")
	end
	return SafeText(text, "")
end

local function SafeFindPlain(text, pattern)
	local safeText = SafeText(text, "")
	if safeText == "" then
		return nil
	end

	local ok, index = pcall(string.find, safeText, pattern, 1, true)
	if not ok then
		return nil
	end

	return index
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
QuestTogether.nameplateQuestStateByGuid = QuestTogether.nameplateQuestStateByGuid or {}
QuestTogether.nameplateQuestStateByUnitToken = QuestTogether.nameplateQuestStateByUnitToken or {}
QuestTogether.nameplateQuestGuidByUnitToken = QuestTogether.nameplateQuestGuidByUnitToken or {}
QuestTogether.nameplateIconByUnitFrame = QuestTogether.nameplateIconByUnitFrame
	or setmetatable({}, { __mode = "k" })
QuestTogether.nameplateHealthOverlayByUnitFrame = QuestTogether.nameplateHealthOverlayByUnitFrame
	or setmetatable({}, { __mode = "k" })
QuestTogether.nameplateBubbleByUnitFrame = QuestTogether.nameplateBubbleByUnitFrame
	or setmetatable({}, { __mode = "k" })
QuestTogether.nameplateBubbleStateByFrame = QuestTogether.nameplateBubbleStateByFrame
	or setmetatable({}, { __mode = "k" })
QuestTogether.personalBubbleSliderHandlesByFrame = QuestTogether.personalBubbleSliderHandlesByFrame
	or setmetatable({}, { __mode = "k" })
QuestTogether.personalBubbleDialogPositionByFrame = QuestTogether.personalBubbleDialogPositionByFrame
	or setmetatable({}, { __mode = "k" })
QuestTogether.nameplateRefreshPendingByUnitToken = QuestTogether.nameplateRefreshPendingByUnitToken or {}
QuestTogether.nameplateRefreshGenerationByUnitToken = QuestTogether.nameplateRefreshGenerationByUnitToken or {}
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
	if not hostFrame or IsFrameForbidden(hostFrame) then
		return nil
	end

	local unitFrame = hostFrame.UnitFrame or hostFrame
	if IsFrameForbidden(unitFrame) then
		return nil
	end
	return unitFrame
end

local function GetSavedPersonalBubbleDialogPosition(dialog)
	if not dialog or not QuestTogether.personalBubbleDialogPositionByFrame then
		return nil
	end
	return QuestTogether.personalBubbleDialogPositionByFrame[dialog]
end

local function SetSavedPersonalBubbleDialogPosition(dialog, position)
	if not dialog or type(position) ~= "table" then
		return
	end
	QuestTogether.personalBubbleDialogPositionByFrame[dialog] = position
end

local function GetAnnouncementBubbleState(bubble)
	if not bubble or not QuestTogether.nameplateBubbleStateByFrame then
		return nil
	end
	return QuestTogether.nameplateBubbleStateByFrame[bubble]
end

local function SetAnnouncementBubbleState(bubble, state)
	if not bubble or type(state) ~= "table" then
		return nil
	end
	QuestTogether.nameplateBubbleStateByFrame[bubble] = state
	return state
end

local function ClearAnnouncementBubbleState(bubble)
	if not bubble or not QuestTogether.nameplateBubbleStateByFrame then
		return
	end
	QuestTogether.nameplateBubbleStateByFrame[bubble] = nil
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

local function EstimateBubbleTextWidth(text, fontSize, minTextWidth, maxTextWidth)
	local textValue = type(text) == "string" and text or ""
	if textValue == "" then
		return minTextWidth
	end

	local characterWidth = math.max(5, fontSize * 0.55)
	local estimatedWidth = math.floor((string.len(textValue) * characterWidth) + 0.5)
	return math.min(maxTextWidth, math.max(minTextWidth, estimatedWidth))
end

local function EstimateBubbleTextHeight(text, textWidth, fontSize)
	local textValue = type(text) == "string" and text or ""
	local lineHeight = math.max(fontSize, math.floor((fontSize * 1.2) + 0.5))
	if textValue == "" then
		return lineHeight
	end

	local characterWidth = math.max(5, fontSize * 0.55)
	local maxCharsPerLine = math.max(1, math.floor(textWidth / characterWidth))
	local lineCount = math.max(1, math.ceil(string.len(textValue) / maxCharsPerLine))
	return lineCount * lineHeight
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

	SetSavedPersonalBubbleDialogPosition(dialog, {
		point = point,
		relativePoint = relativePoint,
		x = offsetX,
		y = offsetY,
	})
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

	local callbackHandles = QuestTogether.personalBubbleSliderHandlesByFrame[settingFrame]
	if not callbackHandles then
		callbackHandles = EventUtil.CreateCallbackHandleContainer()
		QuestTogether.personalBubbleSliderHandlesByFrame[settingFrame] = callbackHandles
	end
	callbackHandles:Unregister()
	callbackHandles:RegisterCallback(
		settingFrame.Slider,
		MinimalSliderWithSteppersMixin.Event.OnValueChanged,
		function(_, value)
			if type(onValueChanged) == "function" then
				onValueChanged(value)
			end
		end,
		settingFrame
	)
	callbackHandles:RegisterCallback(
		settingFrame.Slider,
		MinimalSliderWithSteppersMixin.Event.OnInteractStart,
		function()
		end,
		settingFrame
	)
	callbackHandles:RegisterCallback(
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
		SafeText(point, ""),
		SafeText(relativePoint, ""),
		SafeText(RoundOffset(offsetX), "0"),
		SafeText(RoundOffset(offsetY), "0"),
		SafeText(changed, "false")
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

	local savedPosition = GetSavedPersonalBubbleDialogPosition(dialog)
	if savedPosition then
		self:Debug("Attaching personal bubble dialog using user-placed position", "editmode")
		dialog:ClearAllPoints()
		dialog:SetPoint(
			savedPosition.point,
			UIParent,
			savedPosition.relativePoint,
			savedPosition.x,
			savedPosition.y
		)
		return
	end

	local point, relativeTo, relativePoint, offsetX, offsetY = GetPersonalBubbleAnchorDialogAttachPoint()
	self:Debugf(
		"editmode",
		"Attaching personal bubble dialog point=%s relativePoint=%s x=%s y=%s",
		SafeText(point, ""),
		SafeText(relativePoint, ""),
		SafeText(offsetX, "0"),
		SafeText(offsetY, "0")
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
	if type(unitToken) ~= "string" then
		return false
	end

	local ok, isMatch = pcall(string.find, unitToken, "^nameplate%d+$")
	return ok and isMatch ~= nil
end

function QuestTogether:DoesNameplateUnitExist(unitToken)
	if self.API and self.API.UnitExists then
		return self.API.UnitExists(unitToken)
	end
	local ok, exists = pcall(UnitExists, unitToken)
	return ok and exists and true or false
end

function QuestTogether:GetNameplateUnitGuid(unitToken)
	if self.API and self.API.UnitGUID then
		local unitGuid = self.API.UnitGUID(unitToken)
		if not IsNonEmptyString(unitGuid) then
			return nil
		end
		return unitGuid
	end

	-- Nameplate unit tokens can disappear between frames; guard transient UnitGUID errors.
	local ok, unitGuid = pcall(UnitGUID, unitToken)
	if self:IsSecretValue(unitGuid) then
		return nil
	end
	if not ok or not IsNonEmptyString(unitGuid) then
		return nil
	end
	return unitGuid
end

function QuestTogether:GetAccessibleNameplateFrameForUnit(unitToken, requireShown)
	if not self:IsNameplateUnitToken(unitToken) then
		return nil, nil
	end
	if not (self.API and type(self.API.GetNamePlateForUnit) == "function") then
		return nil, nil
	end

	local namePlateFrameBase = self.API.GetNamePlateForUnit(unitToken)
	if not namePlateFrameBase or not namePlateFrameBase.UnitFrame then
		return nil, nil
	end
	if IsFrameForbidden(namePlateFrameBase) or IsFrameForbidden(namePlateFrameBase.UnitFrame) then
		return nil, nil
	end
	if requireShown and namePlateFrameBase.IsShown then
		local okShown, isShown = pcall(namePlateFrameBase.IsShown, namePlateFrameBase)
		if not okShown or not isShown then
			return nil, nil
		end
	end

	return namePlateFrameBase, namePlateFrameBase.UnitFrame
end

-- Plater's update_quest_cache bails in instances in local retail Plater.lua:11373-11376.
-- QuestTogether applies that same open-world boundary to nameplate quest detection.
function QuestTogether:IsNameplateAugmentationBlockedInCurrentContext()
	local isInInstance = self.API and self.API.IsInInstance and self.API.IsInInstance()
	return isInInstance and true or false
end

function QuestTogether:IsWorldMapVisibleForNameplateRefresh()
	if not (self.API and type(self.API.IsWorldMapVisible) == "function") then
		return false
	end

	local ok, isVisible = pcall(self.API.IsWorldMapVisible)
	return ok and isVisible and true or false
end

function QuestTogether:IsNameplateUnitPlayer(unitToken)
	if self.API and self.API.UnitIsPlayer then
		return self.API.UnitIsPlayer(unitToken)
	end
	local ok, isPlayer = pcall(UnitIsPlayer, unitToken)
	return ok and isPlayer and true or false
end

function QuestTogether:IsNameplateUnitConnected(unitToken)
	local ok, isConnected = pcall(UnitIsConnected, unitToken)
	return ok and isConnected and true or false
end

function QuestTogether:IsNameplateUnitDead(unitToken)
	local ok, isDead = pcall(UnitIsDead, unitToken)
	return ok and isDead and true or false
end

function QuestTogether:IsNameplateUnitTapDenied(unitToken)
	local ok, isTapDenied = pcall(UnitIsTapDenied, unitToken)
	return ok and isTapDenied and true or false
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
	if IsFrameForbidden(parentFrame) then
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

-- Mirrors the unfinished-objective checks in Plater.IsQuestObjective
-- (local retail Plater.lua:11256-11315): only x/y and percent progress count.
local function GetObjectiveProgressState(text)
	if type(text) ~= "string" or text == "" then
		return "unknown"
	end

	local amountCurrent, amountTotal = SafeMatch(text, "(%d+)%s*/%s*(%d+)")
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

	local percentText = SafeMatch(text, "(%d+)%%")
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

local function IsKnownQuestTitleLine(text)
	local trimmedText = SafeTrimText(text)
	if trimmedText == "" then
		return false
	end
	return QuestTogether and QuestTogether.nameplateQuestTitleCache and QuestTogether.nameplateQuestTitleCache[trimmedText]
		or false
end

local function IsTooltipQuestObjectiveLineType(lineType)
	if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(lineType) then
		return false
	end

	local normalizedType = SafeText(lineType, "")
	if normalizedType == "QuestObjective" then
		return true
	end

	if Enum and Enum.TooltipDataLineType then
		return lineType == Enum.TooltipDataLineType.QuestObjective
	end

	return false
end

local function IsTooltipQuestPlayerLineType(lineType)
	if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(lineType) then
		return false
	end

	local normalizedType = SafeText(lineType, "")
	if normalizedType == "QuestPlayer" then
		return true
	end

	if Enum and Enum.TooltipDataLineType then
		return lineType == Enum.TooltipDataLineType.QuestPlayer
	end

	return false
end

local function IsTooltipQuestTitleLineType(lineType)
	if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(lineType) then
		return false
	end

	local normalizedType = SafeText(lineType, "")
	if normalizedType == "QuestTitle" then
		return true
	end

	if Enum and Enum.TooltipDataLineType then
		return lineType == Enum.TooltipDataLineType.QuestTitle
	end

	return false
end

local function GetTooltipQuestLinePrimaryText(lineData)
	if type(lineData) ~= "table" then
		return nil
	end

	local leftText = SafeTrimText(lineData.leftText)
	if leftText ~= "" then
		return leftText
	end

	return nil
end

local function IsThreatTooltipMarkerText(text)
	if type(text) ~= "string" or text == "" then
		return false
	end
	if type(THREAT_TOOLTIP) ~= "string" or THREAT_TOOLTIP == "" then
		return false
	end

	return SafeTrimText(text) == SafeTrimText(THREAT_TOOLTIP)
end

local function GetTooltipQuestLeftText(addon, lineData)
	local leftText = lineData and lineData.leftText or nil
	if addon and addon.IsSecretValue then
		if addon:IsSecretValue(leftText) then
			leftText = nil
		end
	end

	if type(leftText) ~= "string" then
		return ""
	end

	return SafeTrimText(leftText)
end

-- Mirrors Plater.IsQuestObjective (local retail Plater.lua:11219-11347):
-- find a matched quest title, walk following lines, stop at THREAT_TOOLTIP,
-- and only mark the unit when at least one following objective is unfinished.
function QuestTogether:TooltipLineHasUnfinishedObjectiveEvidence(lineData)
	local leftText = GetTooltipQuestLeftText(self, lineData)
	if leftText ~= "" and GetObjectiveProgressState(leftText) == "unfinished" then
		return true
	end

	return false
end

function QuestTogether:EvaluateTooltipQuestObjectiveLines(tooltipLines)
	if type(tooltipLines) ~= "table" then
		return false
	end

	local matchedQuestTitle = false

	for _, lineData in ipairs(tooltipLines) do
		if self:IsSecretValue(lineData) then
			break
		end

		local lineType = lineData and lineData.type or nil
		if self:IsSecretValue(lineType) then
			break
		end

		local primaryText = GetTooltipQuestLinePrimaryText(lineData)
		if IsKnownQuestTitleLine(primaryText) then
			matchedQuestTitle = true
		elseif matchedQuestTitle then
			if IsThreatTooltipMarkerText(primaryText) then
				matchedQuestTitle = false
			elseif self:TooltipLineHasUnfinishedObjectiveEvidence(lineData) then
				return true
			end
		end
	end

	return false
end

function QuestTogether:ClearNameplateResolvedQuestState()
	wipe(self.nameplateQuestStateByUnitToken)
	wipe(self.nameplateQuestGuidByUnitToken)
end

-- Keep detection state GUID-owned so recycled unit tokens only mirror the
-- current render state instead of acting as the source of truth.
function QuestTogether:ClearNameplateQuestDetectionCache()
	wipe(self.nameplateQuestStateByGuid)
end

function QuestTogether:ForgetResolvedNameplateQuestState(unitToken)
	if not self:IsNameplateUnitToken(unitToken) then
		return
	end

	self.nameplateQuestStateByUnitToken[unitToken] = nil
	self.nameplateQuestGuidByUnitToken[unitToken] = nil
end

function QuestTogether:StoreResolvedNameplateQuestState(unitToken, unitGuid, isQuestObjective)
	if not IsNonEmptyString(unitGuid) then
		return
	end

	self.nameplateQuestStateByGuid[unitGuid] = isQuestObjective and true or false
	if self:IsNameplateUnitToken(unitToken) then
		self.nameplateQuestStateByUnitToken[unitToken] = isQuestObjective and true or false
		self.nameplateQuestGuidByUnitToken[unitToken] = unitGuid
	end
end

function QuestTogether:TryGetCachedQuestObjectiveStateForGuid(unitGuid)
	if not IsNonEmptyString(unitGuid) then
		return false, nil
	end

	local cachedQuestObjective = self.nameplateQuestStateByGuid[unitGuid]
	if cachedQuestObjective == nil then
		return false, nil
	end

	return true, cachedQuestObjective == true
end

-- QuestTogether keeps the title cache on the quest-log side only.
-- Plater also adds current-map world quest titles from C_TaskQuest map arrays,
-- but those map-owned tables taint Blizzard POI/widget paths on the default UI.
-- Hidden quest-log rows still cover active world quest titles without touching
-- shared map state, which keeps default-nameplate quest detection boundary-safe.
function QuestTogether:RebuildNameplateQuestTitleCache()
	wipe(self.nameplateQuestTitleCache)

	if self.API and self.API.IsInInstance and self.API.IsInInstance() then
		return
	end

	if self.API and self.API.GetNumQuestLogEntries and self.API.GetQuestLogInfo then
		local totalEntries = SafeUiNumber(self.API.GetNumQuestLogEntries(), 0) or 0
		for entryIndex = 1, totalEntries do
			local questDetails = self.API.GetQuestLogInfo(entryIndex)
			if
				questDetails
				and not questDetails.isHeader
				and type(questDetails.title) == "string"
				and questDetails.title ~= ""
			then
				self.nameplateQuestTitleCache[questDetails.title] = true
			end
		end
	end
end

function QuestTogether:TryGetReusableCachedNameplateQuestState(unitToken, unitGuid)
	local hasCachedQuestState, cachedQuestState = self:TryGetCachedQuestObjectiveStateForGuid(unitGuid)
	if not hasCachedQuestState then
		return false, nil
	end

	if self:IsNameplateUnitToken(unitToken) then
		self.nameplateQuestStateByUnitToken[unitToken] = cachedQuestState and true or false
		self.nameplateQuestGuidByUnitToken[unitToken] = unitGuid
	end

	return true, cachedQuestState
end

-- Plater.IsQuestObjective starts from the plate GUID at local retail
-- Plater.lua:11170-11180. QuestTogether keeps that same GUID-first entry point,
-- but routes the read through guarded helpers instead of touching foreign frames directly.
function QuestTogether:GetNameplateTooltipScanGuid(unitToken, unitFrame)
	if IsFrameForbidden(unitFrame) then
		unitFrame = nil
	end

	local plateFrame = unitFrame and unitFrame.PlateFrame or nil
	if IsFrameForbidden(plateFrame) then
		plateFrame = nil
	end

	local unitFrameGuid = unitFrame and unitFrame.namePlateUnitGUID or nil
	if self:IsSecretValue(unitFrameGuid) then
		unitFrameGuid = nil
	end
	if IsNonEmptyString(unitFrameGuid) then
		return unitFrameGuid
	end

	local plateFrameGuid = plateFrame and plateFrame.namePlateUnitGUID or nil
	if self:IsSecretValue(plateFrameGuid) then
		plateFrameGuid = nil
	end
	if IsNonEmptyString(plateFrameGuid) then
		return plateFrameGuid
	end

	local liveGuid = self:GetNameplateUnitGuid(unitToken)
	if IsNonEmptyString(liveGuid) then
		return liveGuid
	end

	return nil
end

-- Plater reads MEMBER_NPCID directly when calling QuestieTooltips.GetTooltip
-- in local retail Plater.lua:11191-11196. QuestTogether derives the same NPC id
-- from the unit GUID so the Questie source can stay frame-agnostic and guarded.
local function GetNpcIdFromUnitGuid(unitGuid)
	if type(unitGuid) ~= "string" or unitGuid == "" then
		return nil
	end

	local npcIdText = SafeMatch(unitGuid, "^[^-]+%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)%-")
	local npcId = SafeUiNumber(npcIdText, nil)
	if npcId and npcId > 0 then
		return npcId
	end

	return nil
end

-- Questie normalization mirrors the cleanup Plater applies in local retail
-- Plater.lua:11211-11217 before it matches titles against QuestCache.
local function NormalizeQuestieTooltipQuestLineText(textValue)
	if type(textValue) ~= "string" or textValue == "" then
		return nil
	end

	local normalizedText = string.gsub(textValue, "|c%x%x%x%x%x%x%x%x", "")
	normalizedText = string.gsub(normalizedText, "|r", "")
	normalizedText = string.gsub(normalizedText, "%[.*%] ", "")
	normalizedText = string.gsub(normalizedText, " %(%d+%)", "")
	normalizedText = SafeTrimText(normalizedText)
	if normalizedText == "" then
		return nil
	end

	return normalizedText
end

function QuestTogether:SanitizeTooltipQuestLineText(textValue)
	if self:IsSecretValue(textValue) or type(textValue) ~= "string" then
		return nil
	end

	local trimmedValue = SafeTrimText(textValue)
	if trimmedValue == "" then
		return nil
	end

	return trimmedValue
end

-- Plater keeps only QuestObjective, QuestTitle, and QuestPlayer lines from
-- C_TooltipInfo in local retail Plater.lua:11197-11203. QuestTogether applies
-- the same line-type filter before any parsing and ignores all other payload data.
function QuestTogether:SanitizeTooltipLineForQuestDetection(lineData)
	if type(lineData) ~= "table" or self:IsSecretValue(lineData) then
		return nil
	end

	local lineType = lineData.type
	if self:IsSecretValue(lineType) then
		return nil
	end
	if
		not IsTooltipQuestObjectiveLineType(lineType)
		and not IsTooltipQuestTitleLineType(lineType)
		and not IsTooltipQuestPlayerLineType(lineType)
	then
		return nil
	end

	local leftText = self:SanitizeTooltipQuestLineText(lineData.leftText)
	if not leftText then
		return nil
	end

	return {
		type = lineType,
		leftText = leftText,
	}
end

function QuestTogether:ExtractQuestObjectiveTooltipLinesFromTooltipData(tooltipData)
	if type(tooltipData) ~= "table" or self:IsSecretValue(tooltipData) then
		return nil
	end

	local tooltipLineData = tooltipData.lines
	if type(tooltipLineData) ~= "table" or self:IsSecretValue(tooltipLineData) then
		return nil
	end

	local tooltipLines = {}
	for lineIndex = 1, #tooltipLineData do
		local sanitizedLine = self:SanitizeTooltipLineForQuestDetection(tooltipLineData[lineIndex])
		if sanitizedLine then
			tooltipLines[#tooltipLines + 1] = sanitizedLine
		end
	end

	return tooltipLines
end

-- Questie is Plater's first quest-tooltip source in local retail Plater.lua:11191-11196.
-- We mirror that source order, but read the Questie module through guarded accessors.
function QuestTogether:GetQuestieQuestObjectiveTooltipLines(unitGuid)
	local npcId = GetNpcIdFromUnitGuid(unitGuid)
	if not npcId then
		return nil
	end

	local questieLoader = _G and _G.QuestieLoader or nil
	if type(questieLoader) ~= "table" or self:IsSecretValue(questieLoader) then
		return nil
	end

	local modules = questieLoader._modules
	if type(modules) ~= "table" or self:IsSecretValue(modules) then
		return nil
	end

	local questieTooltips = modules["QuestieTooltips"]
	if type(questieTooltips) ~= "table" or self:IsSecretValue(questieTooltips) then
		return nil
	end
	if type(questieTooltips.GetTooltip) ~= "function" then
		return nil
	end

	local ok, tooltipData = pcall(questieTooltips.GetTooltip, "m_" .. tostring(npcId))
	if not ok or type(tooltipData) ~= "table" or self:IsSecretValue(tooltipData) then
		return nil
	end

	local tooltipLines = {}
	for lineIndex = 1, #tooltipData do
		local rawLine = tooltipData[lineIndex]
		if self:IsSecretValue(rawLine) then
			break
		end

		local normalizedText = NormalizeQuestieTooltipQuestLineText(rawLine)
		if normalizedText then
			tooltipLines[#tooltipLines + 1] = {
				leftText = normalizedText,
			}
		end
	end

	if #tooltipLines > 0 then
		return tooltipLines
	end

	return nil
end

-- Structured Blizzard tooltip data is Plater's second source on retail/mainline
-- in local retail Plater.lua:11208-11218 after Questie.
function QuestTogether:GetStructuredQuestObjectiveTooltipLines(unitToken, unitGuid)
	if type(unitGuid) ~= "string" or unitGuid == "" then
		return nil
	end
	if not self.API then
		return nil
	end

	if type(self.API.GetTooltipDataForHyperlink) == "function" then
		local tooltipLines =
			self:ExtractQuestObjectiveTooltipLinesFromTooltipData(self.API.GetTooltipDataForHyperlink("unit:" .. unitGuid))
		if type(tooltipLines) == "table" and #tooltipLines > 0 then
			return tooltipLines
		end
	end

	return nil
end

-- The hidden GameTooltip scan is only the non-mainline branch in Plater.IsQuestObjective
-- at local retail Plater.lua:11219-11226. On retail clients, Plater stops after C_TooltipInfo.
function QuestTogether:GetHiddenQuestObjectiveTooltipLines(unitGuid)
	if type(unitGuid) ~= "string" or unitGuid == "" then
		return nil
	end

	local scanTooltip = self:GetOrCreateNameplateScanTooltip()
	if not scanTooltip then
		return nil
	end

	return self:ReadNameplateScanTooltipLines(scanTooltip, unitGuid)
end

function QuestTogether:CanUseStructuredQuestTooltipAPI()
	if not self.API then
		return false
	end

	return type(self.API.GetTooltipDataForHyperlink) == "function"
end

-- Test/helper entry point that mirrors Plater's client-specific source order:
-- retail/mainline uses Questie -> C_TooltipInfo (Plater.lua:11200-11218),
-- while the legacy branch falls back to a hidden GameTooltip instead
-- (Plater.lua:11219-11226).
function QuestTogether:GetQuestObjectiveTooltipLines(unitToken, unitGuid)
	if type(unitGuid) ~= "string" or unitGuid == "" then
		return nil
	end

	local questieTooltipLines = self:GetQuestieQuestObjectiveTooltipLines(unitGuid)
	if type(questieTooltipLines) == "table" and #questieTooltipLines > 0 then
		return questieTooltipLines
	end

	local structuredTooltipLines = self:GetStructuredQuestObjectiveTooltipLines(unitToken, unitGuid)
	if type(structuredTooltipLines) == "table" and #structuredTooltipLines > 0 then
		return structuredTooltipLines
	end

	if self:CanUseStructuredQuestTooltipAPI() then
		return nil
	end

	return self:GetHiddenQuestObjectiveTooltipLines(unitGuid)
end

function QuestTogether:GetOrCreateNameplateScanTooltip()
	local scanTooltip = self.nameplateScanTooltip
	if scanTooltip and IsFrameForbidden(scanTooltip) then
		scanTooltip = nil
	end
	if scanTooltip then
		return scanTooltip
	end

	local existingTooltip = _G and _G[NAMEPLATE_SCAN_TOOLTIP_NAME] or nil
	if existingTooltip and not IsFrameForbidden(existingTooltip) then
		self.nameplateScanTooltip = existingTooltip
		return existingTooltip
	end

	if type(CreateFrame) ~= "function" then
		return nil
	end

	local parentFrame = UIParent or WorldFrame or nil
	local ok, createdTooltip = pcall(
		CreateFrame,
		"GameTooltip",
		NAMEPLATE_SCAN_TOOLTIP_NAME,
		parentFrame,
		"GameTooltipTemplate"
	)
	if not ok or not createdTooltip or IsFrameForbidden(createdTooltip) then
		return nil
	end

	self.nameplateScanTooltip = createdTooltip
	return createdTooltip
end

function QuestTogether:GetNameplateScanTooltipLineCount(scanTooltip)
	if not scanTooltip or IsFrameForbidden(scanTooltip) or not scanTooltip.NumLines then
		return 0
	end

	local ok, lineCount = pcall(scanTooltip.NumLines, scanTooltip)
	if not ok or self:IsSecretValue(lineCount) then
		return 0
	end

	return SafeUiNumber(lineCount, 0) or 0
end

function QuestTogether:GetNameplateScanTooltipLeftText(scanTooltip, lineIndex)
	if not scanTooltip or IsFrameForbidden(scanTooltip) or type(lineIndex) ~= "number" then
		return nil
	end

	local tooltipName = nil
	if scanTooltip.GetName then
		local ok, resolvedName = pcall(scanTooltip.GetName, scanTooltip)
		if ok and not self:IsSecretValue(resolvedName) and IsNonEmptyString(resolvedName) then
			tooltipName = resolvedName
		end
	end
	if not IsNonEmptyString(tooltipName) then
		return nil
	end

	local fontString = _G and _G[tooltipName .. "TextLeft" .. tostring(lineIndex)] or nil
	if not fontString or IsFrameForbidden(fontString) or self:IsSecretValue(fontString) or not fontString.GetText then
		return nil
	end

	local ok, textValue = pcall(fontString.GetText, fontString)
	if not ok or self:IsSecretValue(textValue) or type(textValue) ~= "string" then
		return nil
	end

	return textValue
end

function QuestTogether:ReadNameplateScanTooltipLines(scanTooltip, unitGuid)
	if not scanTooltip or IsFrameForbidden(scanTooltip) or type(unitGuid) ~= "string" or unitGuid == "" then
		return nil
	end

	if scanTooltip.Hide then
		pcall(scanTooltip.Hide, scanTooltip)
	end
	if scanTooltip.ClearLines then
		pcall(scanTooltip.ClearLines, scanTooltip)
	end

	local ownerFrame = WorldFrame or UIParent or nil
	if ownerFrame and scanTooltip.SetOwner then
		pcall(scanTooltip.SetOwner, scanTooltip, ownerFrame, "ANCHOR_NONE")
	end
	if not scanTooltip.SetHyperlink then
		return nil
	end

	local ok = pcall(scanTooltip.SetHyperlink, scanTooltip, "unit:" .. unitGuid)
	if not ok then
		if scanTooltip.Hide then
			pcall(scanTooltip.Hide, scanTooltip)
		end
		if scanTooltip.ClearLines then
			pcall(scanTooltip.ClearLines, scanTooltip)
		end
		return nil
	end

	local tooltipLines = {}
	local lineCount = self:GetNameplateScanTooltipLineCount(scanTooltip)
	for lineIndex = 1, lineCount do
		local leftText = SafeTrimText(self:GetNameplateScanTooltipLeftText(scanTooltip, lineIndex))
		if leftText ~= "" then
			tooltipLines[#tooltipLines + 1] = {
				type = nil,
				leftText = leftText,
			}
		end
	end

	if scanTooltip.Hide then
		pcall(scanTooltip.Hide, scanTooltip)
	end
	if scanTooltip.ClearLines then
		pcall(scanTooltip.ClearLines, scanTooltip)
	end

	return tooltipLines
end

function QuestTogether:IsNameplateTooltipScanEnabled()
	-- On retail clients Plater stops after C_TooltipInfo (Plater.lua:11208-11218),
	-- so the legacy hidden-tooltip path is disabled whenever structured tooltip APIs exist.
	-- The hidden fallback remains enabled only for the non-mainline branch
	-- mirrored from Plater.lua:11219-11226.
	if self:CanUseStructuredQuestTooltipAPI() then
		return false
	end
	return DEFAULT_ENABLE_TOOLTIP_QUEST_SCAN_FALLBACK
end

-- Mirrors the client-specific source order in Plater.IsQuestObjective:
-- retail/mainline uses Questie -> C_TooltipInfo (Plater.lua:11200-11218),
-- while legacy clients use Questie -> hidden GameTooltip (Plater.lua:11219-11226).
-- Plater does not special-case world-map visibility here, but QuestTogether has to.
-- On the default UI, live unit-tooltip reads while AreaPOI/GameTooltip widget sets are
-- active can taint Blizzard's shared world-map tooltip/widget path, so the tooltip
-- evaluator reports "unresolved" there and lets the cache-driven resolver decide.
function QuestTogether:TryEvaluateQuestObjectiveViaTooltip(unitToken, unitFrame, unitGuid)
	if not unitToken then
		return false, false, nil
	end
	if self:IsNameplateAugmentationBlockedInCurrentContext() then
		return false, false, nil
	end

	if not IsNonEmptyString(unitGuid) then
		unitGuid = self:GetNameplateTooltipScanGuid(unitToken, unitFrame)
	end
	if self:IsSecretValue(unitGuid) then
		return false, false, nil
	end
	if not IsNonEmptyString(unitGuid) then
		return false, false, nil
	end

	if self:IsWorldMapVisibleForNameplateRefresh() then
		return false, false, unitGuid
	end

	local tooltipLines = self:GetQuestObjectiveTooltipLines(unitToken, unitGuid)
	if type(tooltipLines) ~= "table" or #tooltipLines == 0 then
		return false, false, unitGuid
	end

	return true, self:EvaluateTooltipQuestObjectiveLines(tooltipLines), unitGuid
end

function QuestTogether:IsQuestObjectiveViaTooltip(unitToken, unitFrame)
	local hasResolvedQuestState, isQuestObjective, unitGuid =
		self:TryEvaluateQuestObjectiveViaTooltip(unitToken, unitFrame)
	if hasResolvedQuestState then
		return isQuestObjective
	end

	local hasCachedQuestState, cachedQuestState = self:TryGetReusableCachedNameplateQuestState(unitToken, unitGuid)
	if hasCachedQuestState then
		return cachedQuestState
	end

	return false
end

function QuestTogether:TryResolveNameplateQuestObjectiveState(unitToken, unitFrame, allowLiveScan)
	if not self.isEnabled then
		return false, false, nil
	end
	if self:IsNameplateAugmentationBlockedInCurrentContext() then
		return false, false, nil
	end
	if not self:IsNameplateUnitToken(unitToken) then
		return false, false, nil
	end
	if not unitFrame or IsFrameForbidden(unitFrame) then
		return false, false, nil
	end

	local unitGuid = self:GetNameplateTooltipScanGuid(unitToken, unitFrame)
	if self:IsSecretValue(unitGuid) or not IsNonEmptyString(unitGuid) then
		return false, false, nil
	end

	local hasCachedQuestState, cachedQuestState = self:TryGetReusableCachedNameplateQuestState(unitToken, unitGuid)
	if hasCachedQuestState then
		return true, cachedQuestState, unitGuid
	end

	if not allowLiveScan then
		return false, false, unitGuid
	end

	local hasResolvedQuestState, isQuestObjective = self:TryEvaluateQuestObjectiveViaTooltip(unitToken, unitFrame, unitGuid)
	if not hasResolvedQuestState then
		return false, false, unitGuid
	end

	self:StoreResolvedNameplateQuestState(unitToken, unitGuid, isQuestObjective)
	return true, isQuestObjective, unitGuid
end

-- Plater's quest-unit decision is tooltip-driven in local retail
-- Plater.IsQuestObjective (Plater.lua:11169-11347). We keep QuestTogether on
-- that same narrow path on purpose and do not layer extra Blizzard quest APIs,
-- assist-token fallbacks, or foreign-frame flags on top of it.
function QuestTogether:IsQuestObjectiveUnit(unitToken, unitFrame)
	if not unitToken then
		return false
	end

	return self:IsQuestObjectiveViaTooltip(unitToken, unitFrame)
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
	local hasResolvedQuestState, isQuestObjective = self:TryResolveNameplateQuestObjectiveState(
		unitToken,
		unitFrame,
		not self:IsWorldMapVisibleForNameplateRefresh()
	)
	if not hasResolvedQuestState then
		return false
	end

	return isQuestObjective
end

function QuestTogether:ShouldShowQuestNameplateIconForResolvedState(unitToken, unitFrame, isQuestObjective)
	if not self:GetOption("nameplateQuestIconEnabled") then
		return false
	end

	return self:ShouldApplyResolvedQuestVisualState(unitToken, unitFrame, isQuestObjective)
end

function QuestTogether:ApplyResolvedQuestStateToNameplate(
	namePlateFrameBase,
	unitToken,
	unitFrame,
	isQuestObjective,
	scheduleTintFollowUp
)
	if not namePlateFrameBase or not unitFrame then
		return
	end

	local resolvedUnitToken = unitToken
	if not self:IsNameplateUnitToken(resolvedUnitToken) then
		resolvedUnitToken = ResolveNameplateUnitToken(namePlateFrameBase, unitFrame)
	end
	local resolvedUnitGuid = nil
	if self:IsNameplateUnitToken(resolvedUnitToken) then
		resolvedUnitGuid = self:GetNameplateTooltipScanGuid(resolvedUnitToken, unitFrame)
	end

	local shouldShow = self:ShouldShowQuestNameplateIconForResolvedState(resolvedUnitToken, unitFrame, isQuestObjective)
	local icon = self.nameplateIconByUnitFrame[unitFrame]
	if resolvedUnitToken and resolvedUnitGuid then
		self:StoreResolvedNameplateQuestState(resolvedUnitToken, resolvedUnitGuid, isQuestObjective)
	end

	self:RefreshNameplateHealthTint(namePlateFrameBase, isQuestObjective)
	if scheduleTintFollowUp and isQuestObjective and type(resolvedUnitToken) == "string" and resolvedUnitToken ~= "" then
		self:ScheduleNameplateHealthTintRefresh(resolvedUnitToken, 0.05, true)
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
		if not IsFrameForbidden(icon) then
			icon:Show()
		end
	elseif icon then
		if not IsFrameForbidden(icon) then
			icon:Hide()
		end
		if isQuestObjective ~= true then
			self:RestoreNameplateHealthColor(unitFrame)
		end
	end
end

function QuestTogether:ShouldApplyResolvedQuestVisualState(unitToken, unitFrame, isQuestObjective)
	if not self.isEnabled then
		return false
	end
	if self:IsNameplateAugmentationBlockedInCurrentContext() then
		return false
	end
	if isQuestObjective ~= true then
		return false
	end

	if not unitFrame then
		return false
	end
	if IsFrameForbidden(unitFrame) then
		return false
	end

	local resolvedUnitToken = unitToken
	if not self:IsNameplateUnitToken(resolvedUnitToken) then
		resolvedUnitToken = ResolveNameplateUnitToken(nil, unitFrame)
	end
	if not self:IsNameplateUnitToken(resolvedUnitToken) then
		return false
	end

	if not unitFrame.healthBar then
		return false
	end
	if IsFrameForbidden(unitFrame.healthBar) then
		return false
	end

	if not self:DoesNameplateUnitExist(resolvedUnitToken) then
		return false
	end

	-- Never tint players; this is intended for quest mobs/NPCs.
	if self:IsNameplateUnitPlayer(resolvedUnitToken) then
		return false
	end

	-- Plater's quest-color path only suppresses tap-denied hostile units
	-- (local retail Plater.lua:8993-9004). It does not gate quest visuals on
	-- dead or disconnected state, so keep the visual decision aligned here.
	if self:IsNameplateUnitTapDenied(resolvedUnitToken) then
		return false
	end

	return true
end

-- Keep tinting conservative so we do not override important Blizzard states.
function QuestTogether:ShouldApplyQuestHealthTint(frame, isQuestObjective)
	if not self:GetOption("nameplateQuestHealthColorEnabled") then
		return false
	end

	local resolvedUnitToken = ResolveNameplateUnitToken(nil, frame)
	if not resolvedUnitToken then
		return false
	end

	if isQuestObjective ~= nil then
		return self:ShouldApplyResolvedQuestVisualState(resolvedUnitToken, frame, isQuestObjective)
	end

	local cachedQuestObjective = self.nameplateQuestStateByUnitToken[resolvedUnitToken]
	local cachedUnitGuid = self.nameplateQuestGuidByUnitToken[resolvedUnitToken]
	if cachedQuestObjective ~= nil and IsNonEmptyString(cachedUnitGuid) then
		local hasCachedQuestState, resolvedCachedQuestState =
			self:TryGetReusableCachedNameplateQuestState(resolvedUnitToken, cachedUnitGuid)
		if hasCachedQuestState then
			return self:ShouldApplyResolvedQuestVisualState(resolvedUnitToken, frame, resolvedCachedQuestState)
		end
	end

	local hasResolvedQuestState, isQuestObjectiveNameplate = self:TryResolveNameplateQuestObjectiveState(
		resolvedUnitToken,
		frame,
		not self:IsWorldMapVisibleForNameplateRefresh()
	)
	if not hasResolvedQuestState then
		return false
	end

	return self:ShouldApplyResolvedQuestVisualState(resolvedUnitToken, frame, isQuestObjectiveNameplate)
end

local function GetIconBarAnchor(unitFrame)
	if unitFrame.healthBar and not IsFrameForbidden(unitFrame.healthBar) then
		return unitFrame.healthBar
	end
	if unitFrame.HealthBarsContainer and not IsFrameForbidden(unitFrame.HealthBarsContainer) then
		return unitFrame.HealthBarsContainer
	end
	return unitFrame
end

local function GetNameplateNameTextAnchor(unitFrame)
	local unitFrameName = unitFrame and unitFrame.unitName or nil
	if unitFrameName and not IsFrameForbidden(unitFrameName) then
		return unitFrameName
	end

	local unitFrameFallbackName = unitFrame and unitFrame.name or nil
	if unitFrameFallbackName and not IsFrameForbidden(unitFrameFallbackName) then
		return unitFrameFallbackName
	end

	local healthBarName = unitFrame and unitFrame.healthBar and unitFrame.healthBar.unitName or nil
	if healthBarName and not IsFrameForbidden(healthBarName) then
		return healthBarName
	end

	local healthBarFallbackName = unitFrame and unitFrame.healthBar and unitFrame.healthBar.name or nil
	if healthBarFallbackName and not IsFrameForbidden(healthBarFallbackName) then
		return healthBarFallbackName
	end

	return nil
end

ResolveNameplateUnitToken = function(namePlateFrameBase, unitFrame)
	local plateFrameToken =
		namePlateFrameBase and not IsFrameForbidden(namePlateFrameBase) and namePlateFrameBase.namePlateUnitToken or nil
	if QuestTogether:IsNameplateUnitToken(plateFrameToken) then
		return plateFrameToken
	end

	local plateFrameGetUnitToken =
		namePlateFrameBase and not IsFrameForbidden(namePlateFrameBase) and namePlateFrameBase.GetUnit and namePlateFrameBase:GetUnit()
			or nil
	if QuestTogether:IsNameplateUnitToken(plateFrameGetUnitToken) then
		return plateFrameGetUnitToken
	end

	local unitFrameNamePlateToken = unitFrame and unitFrame.namePlateUnitToken or nil
	if QuestTogether:IsNameplateUnitToken(unitFrameNamePlateToken) then
		return unitFrameNamePlateToken
	end

	local unitFrameUnitToken = unitFrame and unitFrame.unit or nil
	if QuestTogether:IsNameplateUnitToken(unitFrameUnitToken) then
		return unitFrameUnitToken
	end

	local displayedUnitToken = unitFrame and unitFrame.displayedUnit or nil
	if QuestTogether:IsNameplateUnitToken(displayedUnitToken) then
		return displayedUnitToken
	end

	return nil
end

function QuestTogether:ApplyNameplateQuestIconStyle(iconFrame, unitFrame)
	if not iconFrame or not unitFrame then
		return
	end
	if not CanMutateFrame(iconFrame) or IsFrameForbidden(unitFrame) then
		return
	end

	local icon = iconFrame.Icon or iconFrame
	local style = self:GetNameplateQuestIconStyle()
	local width = self.NAMEPLATE_QUEST_ICON_WIDTH
	local height = self.NAMEPLATE_QUEST_ICON_HEIGHT

	iconFrame:ClearAllPoints()

	if style == "left" then
		local barAnchor = GetIconBarAnchor(unitFrame)
		if IsFrameForbidden(barAnchor) then
			barAnchor = unitFrame
		end
		iconFrame:SetPoint("RIGHT", barAnchor, "LEFT", -1, 0)
	elseif style == "right" then
		local barAnchor = GetIconBarAnchor(unitFrame)
		if IsFrameForbidden(barAnchor) then
			barAnchor = unitFrame
		end
		iconFrame:SetPoint("LEFT", barAnchor, "RIGHT", 1, 0)
	elseif style == "prefix" then
		local nameText = GetNameplateNameTextAnchor(unitFrame)
		if nameText then
			-- Keep the prefix icon large enough to remain legible on live nameplates.
			width = math.max(14, math.floor(width * 0.8 + 0.5))
			height = math.max(14, math.floor(height * 0.8 + 0.5))
			iconFrame:SetPoint("RIGHT", nameText, "LEFT", -2, 0)
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
	if icon and icon.SetAllPoints then
		icon:SetAllPoints(iconFrame)
	end
end

EnsureQuestIcon = function(unitFrame)
	if not unitFrame then
		return nil
	end
	if not CanMutateFrame(unitFrame) then
		return nil
	end

	local existingIcon = QuestTogether.nameplateIconByUnitFrame[unitFrame]
	if existingIcon then
		QuestTogether:ApplyNameplateQuestIconStyle(existingIcon, unitFrame)
		return existingIcon
	end

	local iconFrame = CreateFrame("Frame", nil, unitFrame)
	iconFrame:SetFrameStrata(unitFrame:GetFrameStrata() or "LOW")
	iconFrame:SetFrameLevel(((unitFrame.GetFrameLevel and unitFrame:GetFrameLevel()) or 0) + 30)

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
	if not CanMutateFrame(unitFrame) or not CanMutateFrame(unitFrame.healthBar) then
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
	if not CanMutateFrame(texture) or IsFrameForbidden(anchorTarget) then
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
	if IsFrameForbidden(unitFrame) or IsFrameForbidden(unitFrame.healthBar) then
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
	if not CanMutateFrame(hostFrame) or not CanMutateFrame(unitFrame) or not CanMutateFrame(bubble) then
		return
	end

	local frameStrata = hostFrame:GetFrameStrata() or "LOW"
	local frameLevel = SafeUiNumber(unitFrame:GetFrameLevel(), 0) + 20
	bubble:SetFrameStrata(frameStrata)
	bubble:SetFrameLevel(frameLevel)
end

local function EnsureAnnouncementBubble(hostFrame)
	if not CanMutateFrame(hostFrame) then
		return nil
	end

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
	if not CanMutateFrame(bubble) then
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
	self:Debugf("bubble", "Hiding bubble host=%s", SafeText(unitFrame.unit or unitFrame:GetName() or "<screen>", "<screen>"))

	if bubble.animationGroup and bubble.animationGroup:IsPlaying() then
		bubble.animationGroup:Stop()
	elseif CanMutateFrame(bubble) then
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
				elseif CanMutateFrame(bubble) then
					bubble:SetAlpha(0)
					bubble:Hide()
				end
			end
		end
		return
	end
	for unitFrame, bubble in pairs(self.nameplateBubbleByUnitFrame) do
		local bubbleState = GetAnnouncementBubbleState(bubble)
		if bubble and bubbleState and bubbleState.text and bubbleState.text ~= "" then
			local hostFrame = bubbleState.unitToken and self:GetAnnouncementBubbleHostFrameForUnit(bubbleState.unitToken) or nil
			if hostFrame and self:GetOption("showChatBubbles") then
				if hostFrame == self.announcementBubbleScreenHostFrame or (hostFrame.IsShown and hostFrame:IsShown()) then
					self:ShowAnnouncementBubbleOnNameplate(
						hostFrame,
						bubbleState.text,
						bubbleState.eventType,
						bubbleState.iconAsset,
						bubbleState.iconKind
					)
				else
					self:HideAnnouncementBubble(hostFrame)
				end
			elseif hostFrame then
				self:HideAnnouncementBubble(hostFrame)
			elseif unitFrame then
				ClearAnnouncementBubbleState(bubble)
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

	local namePlateFrameBase = self:GetAccessibleNameplateFrameForUnit(unitToken, true)
	if namePlateFrameBase then
		self:Debugf("bubble", "Resolved bubble host for unit=%s", SafeText(unitToken, ""))
		return namePlateFrameBase
	end
	self:Debugf("bubble", "No bubble host found for unit=%s", SafeText(unitToken, ""))
	return nil
end

function QuestTogether:TryShowAnnouncementBubbleOnUnitNameplate(unitToken, text, eventType, iconAsset, iconKind)
	local hostFrame = self:GetAnnouncementBubbleHostFrameForUnit(unitToken)
	if hostFrame then
		if not self:ShowAnnouncementBubbleOnNameplate(hostFrame, text, eventType, iconAsset, iconKind) then
			self:Debugf("bubble", "Failed to show bubble on host for unit=%s", SafeText(unitToken, ""))
			return false, "Unable to show a bubble on that nameplate."
		end
		local unitName = self.API.UnitName and self.API.UnitName(unitToken) or nil
		self:Debugf("bubble", "Showing bubble on unit=%s text=%s", SafeText(unitToken, ""), SafeText(text, ""))
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
	if not CanMutateFrame(namePlateFrameBase) or not CanMutateFrame(unitFrame) then
		return false
	end
	if self:IsNameplateAugmentationBlockedInCurrentContext() then
		self:Debug("Skipping announcement bubble in blocked nameplate context", "bubble")
		return false
	end

	local message = SafeTrimText(text)
	if message == "" then
		self:Debug("Skipping empty bubble message", "bubble")
		return false
	end

	local bubble = EnsureAnnouncementBubble(namePlateFrameBase)
	if not bubble or not bubble.String then
		self:Debug("Failed to create or resolve bubble frame", "bubble")
		return false
	end
	if IsFrameForbidden(bubble) or IsFrameForbidden(bubble.String) then
		return false
	end

	local bubbleUnitToken = nil
	if namePlateFrameBase == self.announcementBubbleScreenHostFrame then
		bubbleUnitToken = "player"
	else
		bubbleUnitToken = ResolveNameplateUnitToken(namePlateFrameBase, unitFrame)
	end
	if not IsNonEmptyString(bubbleUnitToken) then
		return false
	end
	SetAnnouncementBubbleState(bubble, {
		text = message,
		eventType = type(eventType) == "string" and eventType ~= "" and eventType or nil,
		iconAsset = type(iconAsset) == "string" and iconAsset ~= "" and iconAsset or nil,
		iconKind = type(iconKind) == "string" and iconKind ~= "" and iconKind or nil,
		unitToken = bubbleUnitToken,
	})

	local anchorFrame = unitFrame.HealthBarsContainer or unitFrame
	if IsFrameForbidden(anchorFrame) then
		anchorFrame = unitFrame
	end
	if IsFrameForbidden(anchorFrame) then
		return false
	end
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

	local measuredUnboundedWidth = nil
	if bubble.String.GetUnboundedStringWidth then
		local okWidth, widthValue = pcall(bubble.String.GetUnboundedStringWidth, bubble.String)
		if okWidth then
			measuredUnboundedWidth = SafeUiNumber(widthValue, nil)
		end
	end
	local unboundedWidth = measuredUnboundedWidth
		or EstimateBubbleTextWidth(message, fontSize, minTextWidth, maxTextWidth)
	local targetTextWidth = math.min(
		maxTextWidth,
		math.max(minTextWidth, unboundedWidth)
	)
	bubble.String:SetWidth(targetTextWidth)

	local measuredTextHeight = nil
	if bubble.String.GetStringHeight then
		local okHeight, textHeightValue = pcall(bubble.String.GetStringHeight, bubble.String)
		if okHeight then
			measuredTextHeight = SafeUiNumber(textHeightValue, nil)
		end
	end
	local textHeight = measuredTextHeight
		or EstimateBubbleTextHeight(message, targetTextWidth, fontSize)
	local contentHeight = math.max(iconSize, textHeight)
	local contentWidth = iconSize + iconGap + targetTextWidth
	local bubbleWidth = contentWidth + (inset * 2)
	local bubbleHeight = contentHeight + (inset * 2)
	self:Debugf(
		"bubble",
		"Render bubble host=%s width=%d height=%d font=%d duration=%.1f text=%s",
		SafeText(unitFrame.unit or unitFrame:GetName() or "<screen>", "<screen>"),
		bubbleWidth,
		bubbleHeight,
		fontSize,
		lifetimeSeconds,
		SafeText(message, "")
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
	if IsFrameForbidden(unitFrame) or IsFrameForbidden(unitFrame.healthBar) then
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
		if overlay.FillTexture.SetVertexColor and not IsFrameForbidden(overlay.FillTexture) then
			overlay.FillTexture:SetVertexColor(color.r, color.g, color.b, 1)
		end
		if not IsFrameForbidden(overlay.FillTexture) then
			overlay.FillTexture:Show()
		end
	end
	if overlay.Highlight and not IsFrameForbidden(overlay.Highlight) then
		overlay.Highlight:SetColorTexture(highlightRed, highlightGreen, highlightBlue, 0.14)
		overlay.Highlight:Show()
	end

	if healthBar and healthBar.GetAlpha then
		local alpha = healthBar:GetAlpha() or 1
		if overlay.FillTexture and overlay.FillTexture.SetAlpha and not IsFrameForbidden(overlay.FillTexture) then
			overlay.FillTexture:SetAlpha(alpha)
		end
		if overlay.Highlight and overlay.Highlight.SetAlpha and not IsFrameForbidden(overlay.Highlight) then
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
	if IsFrameForbidden(unitFrame) then
		return
	end

	local overlay = self.nameplateHealthOverlayByUnitFrame[unitFrame]
	if overlay then
		if overlay.FillTexture and overlay.FillTexture.Hide and not IsFrameForbidden(overlay.FillTexture) then
			overlay.FillTexture:Hide()
		end
		if overlay.Highlight and overlay.Highlight.Hide and not IsFrameForbidden(overlay.Highlight) then
			overlay.Highlight:Hide()
		end
	end
end

function QuestTogether:RefreshNameplateHealthTint(namePlateFrameBase, isQuestObjective)
	if not namePlateFrameBase or not namePlateFrameBase.UnitFrame then
		return
	end
	if IsFrameForbidden(namePlateFrameBase) or IsFrameForbidden(namePlateFrameBase.UnitFrame) then
		return
	end

	local unitFrame = namePlateFrameBase.UnitFrame
	local unitToken = ResolveNameplateUnitToken(namePlateFrameBase, unitFrame)
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

function QuestTogether:ScheduleNameplateHealthTintRefresh(unitToken, delaySeconds, preferCachedQuestState)
	if not self:IsNameplateUnitToken(unitToken) then
		return
	end
	if self.nameplateHealthTintRefreshPendingByUnitToken[unitToken] then
		return
	end

	self.nameplateHealthTintRefreshPendingByUnitToken[unitToken] = true
	self.API.Delay(delaySeconds or 0, function()
		self.nameplateHealthTintRefreshPendingByUnitToken[unitToken] = nil
		if not self.isEnabled or not self.API or type(self.API.GetNamePlateForUnit) ~= "function" then
			return
		end

		local namePlateFrameBase, unitFrame = self:GetAccessibleNameplateFrameForUnit(unitToken, true)
		if not namePlateFrameBase or not unitFrame then
			return
		end

			local liveUnitToken = ResolveNameplateUnitToken(namePlateFrameBase, unitFrame)
			if not liveUnitToken then
				self:ForgetResolvedNameplateQuestState(unitToken)
				self:RestoreNameplateHealthColor(unitFrame)
				return
			end

			if liveUnitToken ~= unitToken then
				self:ForgetResolvedNameplateQuestState(unitToken)
				self.nameplateHealthTintRetryCountByUnitToken[unitToken] = nil
			end

			local allowLiveScan = not self:IsWorldMapVisibleForNameplateRefresh()
			local hasResolvedQuestState, isQuestObjective = self:TryResolveNameplateQuestObjectiveState(
				liveUnitToken,
				unitFrame,
				allowLiveScan
			)
			if not hasResolvedQuestState then
				if not allowLiveScan then
					self:ScheduleDeferredNameplateQuestStateRefresh(
						"NameplateHealthTintRefreshWorldMapVisible",
						NAMEPLATE_WORLD_MAP_REFRESH_DELAY_SECONDS
					)
				else
					self:ForgetResolvedNameplateQuestState(liveUnitToken)
					self:RestoreNameplateHealthColor(unitFrame)
				end
				return
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

	local delayFn = self.API and self.API.Delay
	local generation = (self.nameplateRefreshGenerationByUnitToken[unitToken] or 0) + 1
	self.nameplateRefreshGenerationByUnitToken[unitToken] = generation
	self.nameplateRefreshPendingByUnitToken[unitToken] = true

	-- Mirrors Plater.ScheduleUpdateForNameplate() (local retail Plater.lua:1461-1481):
	-- schedule one update for the unit instead of retry-bursting tooltip refreshes.
	local function refreshScheduledNameplate()
		if self.nameplateRefreshGenerationByUnitToken[unitToken] ~= generation then
			return
		end
		self.nameplateRefreshPendingByUnitToken[unitToken] = nil
		if not self.isEnabled then
			return
		end

		local namePlateFrameBase = self:GetAccessibleNameplateFrameForUnit(unitToken, true)
		if not namePlateFrameBase then
			return
		end

		self:RefreshNameplateIcon(namePlateFrameBase)
	end

	if type(delayFn) ~= "function" then
		refreshScheduledNameplate()
		return
	end

	delayFn(0, function()
		refreshScheduledNameplate()
	end)
end

function QuestTogether:RefreshNameplateIcon(namePlateFrameBase)
	if not namePlateFrameBase or not namePlateFrameBase.UnitFrame then
		return
	end
	if IsFrameForbidden(namePlateFrameBase) or IsFrameForbidden(namePlateFrameBase.UnitFrame) then
		return
	end

	local unitFrame = namePlateFrameBase.UnitFrame
	local unitToken = ResolveNameplateUnitToken(namePlateFrameBase, unitFrame)
	local allowLiveScan = not self:IsWorldMapVisibleForNameplateRefresh()
	local hasResolvedQuestState, isQuestObjective = self:TryResolveNameplateQuestObjectiveState(
		unitToken,
		unitFrame,
		allowLiveScan
	)
	if not hasResolvedQuestState then
		if not allowLiveScan then
			self:ScheduleDeferredNameplateQuestStateRefresh(
				"RefreshNameplateIconWorldMapVisible",
				NAMEPLATE_WORLD_MAP_REFRESH_DELAY_SECONDS
			)
		else
			self:ForgetResolvedNameplateQuestState(unitToken)
			self:HideNameplateIcon(namePlateFrameBase)
		end
		return
	end

	self:ApplyResolvedQuestStateToNameplate(namePlateFrameBase, unitToken, unitFrame, isQuestObjective, true)
end

function QuestTogether:HideNameplateIcon(namePlateFrameBase)
	if not namePlateFrameBase or not namePlateFrameBase.UnitFrame then
		return
	end
	if IsFrameForbidden(namePlateFrameBase) or IsFrameForbidden(namePlateFrameBase.UnitFrame) then
		return
	end

	local icon = self.nameplateIconByUnitFrame[namePlateFrameBase.UnitFrame]
	if icon and not IsFrameForbidden(icon) then
		icon:Hide()
	end
	local bubble = self.nameplateBubbleByUnitFrame[namePlateFrameBase.UnitFrame]
	if bubble then
		ClearAnnouncementBubbleState(bubble)
	end
	self:HideAnnouncementBubble(namePlateFrameBase)
	self:RestoreNameplateHealthColor(namePlateFrameBase.UnitFrame)
end

function QuestTogether:ForEachVisibleNamePlate(callback)
	if type(callback) ~= "function" or not C_NamePlate or not C_NamePlate.GetNamePlates then
		return
	end

	local ok, nameplates = pcall(C_NamePlate.GetNamePlates, false)
	if not ok or type(nameplates) ~= "table" then
		return
	end

	for _, frame in pairs(nameplates) do
		if frame and not IsFrameForbidden(frame) then
			callback(frame)
		end
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
					fullUnitName = SafeText(unitName, "") .. "-" .. SafeText(realmName, "")
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
		SafeText(senderGUID, ""),
		SafeText(normalizedSenderName, ""),
		SafeText(matchedFrame ~= nil, "false")
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

	local unitGUID = nil
	if self.API.UnitGUID then
		local okGuid, guidValue = pcall(self.API.UnitGUID, unitToken)
		if okGuid and not self:IsSecretValue(guidValue) then
			unitGUID = guidValue
		end
	end
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
		fullUnitName = SafeText(unitName, "") .. "-" .. SafeText(realmName, "")
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
			self:Debugf("nameplate", "Nearby player unit token match sender=%s unit=%s", SafeText(senderName, ""), SafeText(unitToken, ""))
			return unitToken
		end
	end

	self:Debugf("nameplate", "No nearby unit token match sender=%s", SafeText(senderName, ""))
	return nil
end

function QuestTogether:RefreshNameplateAugmentation()
	if self:IsNameplateAugmentationBlockedInCurrentContext() then
		self:ClearNameplateQuestDetectionCache()
		wipe(self.nameplateQuestStateByUnitToken)
		wipe(self.nameplateQuestGuidByUnitToken)
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

-- Mirrors Plater.UpdateAllPlates() (Plater.lua:6681-6692): refresh all visible plates
-- against the current quest cache without rebuilding quest-log title inputs.
function QuestTogether:RefreshVisibleNameplates(reason)
	if self:IsWorldMapVisibleForNameplateRefresh() then
		self:ScheduleDeferredNameplateQuestStateRefresh(
			reason or "RefreshVisibleNameplatesWorldMapVisible",
			NAMEPLATE_WORLD_MAP_REFRESH_DELAY_SECONDS
		)
		return false
	end

	self:ClearNameplateResolvedQuestState()
	self:RefreshNameplateAugmentation()
	return true
end

function QuestTogether:RefreshNameplatesForQuestStateChange(reason)
	if self:IsWorldMapVisibleForNameplateRefresh() then
		local delayFn = self.API and self.API.Delay
		if type(delayFn) == "function" then
			self:ScheduleDeferredNameplateQuestStateRefresh(
				reason or "WorldMapVisible",
				NAMEPLATE_WORLD_MAP_REFRESH_DELAY_SECONDS
			)
		end
		return false
	end

	self:RebuildNameplateQuestTitleCache()
	self:ClearNameplateQuestDetectionCache()
	self:ClearNameplateResolvedQuestState()
	self:RefreshNameplateAugmentation()
	return true
end

function QuestTogether:ScheduleDeferredNameplateQuestStateRefresh(reason, delaySeconds)
	local delayFn = self.API and self.API.Delay
	if type(delayFn) ~= "function" then
		self.pendingDeferredNameplateQuestStateRefresh = false
		self:RefreshNameplatesForQuestStateChange(reason)
		return
	end

	self.deferredNameplateQuestStateRefreshGeneration = (self.deferredNameplateQuestStateRefreshGeneration or 0) + 1
	local generation = self.deferredNameplateQuestStateRefreshGeneration
	self.pendingDeferredNameplateQuestStateRefresh = true
	delayFn(delaySeconds or PLATER_QUEST_STATE_REFRESH_DELAY_SECONDS, function()
		if generation ~= QuestTogether.deferredNameplateQuestStateRefreshGeneration then
			return
		end
		QuestTogether.pendingDeferredNameplateQuestStateRefresh = false
		if not QuestTogether.isEnabled then
			return
		end
		QuestTogether:RefreshNameplatesForQuestStateChange(reason)
	end)
end

function QuestTogether:SchedulePlaterStartupNameplateRefreshes()
	if not self.API or type(self.API.Delay) ~= "function" then
		return false
	end

	-- Mirrors Plater startup bootstrap in local retail Plater.lua:6357-6362:
	-- queue QuestLogUpdated() after 4.1 seconds, which then waits the standard
	-- 1-second quest-cache throttle, and separately trigger FullRefreshAllPlates()
	-- at 5.1 seconds after initialization.
	self.API.Delay(PLATER_INITIAL_QUEST_LOG_UPDATED_DELAY_SECONDS, function()
		if not QuestTogether.isEnabled then
			return
		end
		QuestTogether:ScheduleDeferredNameplateQuestStateRefresh(
			"EnableNameplateAugmentationStartup",
			PLATER_QUEST_STATE_REFRESH_DELAY_SECONDS
		)
	end)
	self.API.Delay(PLATER_INITIAL_FULL_REFRESH_DELAY_SECONDS, function()
		if not QuestTogether.isEnabled then
			return
		end
		QuestTogether:FullRefreshVisibleNameplates("EnableNameplateAugmentationStartupFullRefresh")
	end)

	return true
end

-- Mirrors the per-plate pass in Plater.FullRefreshAllPlates()
-- (local retail Plater.lua:6697-6701) rather than routing through UpdateAllPlates().
function QuestTogether:FullRefreshVisibleNameplates(reason)
	if self:IsWorldMapVisibleForNameplateRefresh() then
		self:ScheduleDeferredNameplateQuestStateRefresh(
			reason or "FullRefreshVisibleNameplatesWorldMapVisible",
			NAMEPLATE_WORLD_MAP_REFRESH_DELAY_SECONDS
		)
		return false
	end

	if self:IsNameplateAugmentationBlockedInCurrentContext() then
		return self:RefreshVisibleNameplates(reason)
	end

	self:ClearNameplateResolvedQuestState()
	self:ForEachVisibleNamePlate(function(frame)
		if not frame or not frame.UnitFrame then
			return
		end

		self:RefreshNameplateIcon(frame)
	end)

	return true
end

function QuestTogether:ScheduleFullNameplateRefresh(delaySeconds)
	self.nameplateFullRefreshGeneration = (self.nameplateFullRefreshGeneration or 0) + 1
	local generation = self.nameplateFullRefreshGeneration
	local delayFn = self.API and self.API.Delay
	local scheduledDelay = SafeUiNumber(delaySeconds, 0) or 0
	if type(delayFn) ~= "function" then
		if self.isEnabled then
			self:RefreshVisibleNameplates("ScheduleFullNameplateRefresh")
		end
		return
	end

	if scheduledDelay <= 0 then
		if generation ~= self.nameplateFullRefreshGeneration then
			return
		end
		if not self.isEnabled then
			return
		end

		self:RefreshVisibleNameplates("ScheduleFullNameplateRefresh")
		return
	end

	delayFn(scheduledDelay, function()
		if generation ~= self.nameplateFullRefreshGeneration then
			return
		end
		if not self.isEnabled then
			return
		end

		self:RefreshVisibleNameplates("ScheduleFullNameplateRefresh")
	end)
end

function QuestTogether:OnNameplateAdded(unitToken)
	if not self.isEnabled then
		return
	end

	if not self:IsNameplateUnitToken(unitToken) then
		return
	end
	if self:IsNameplateAugmentationBlockedInCurrentContext() then
		self:ForgetResolvedNameplateQuestState(unitToken)
		self.nameplateHealthTintRetryCountByUnitToken[unitToken] = nil
		local namePlateFrameBase = self:GetAccessibleNameplateFrameForUnit(unitToken, false)
		if namePlateFrameBase then
			-- Nameplate frames are recycled across zone and instance transitions.
			-- In blocked contexts like arenas, clear any stale quest visuals immediately.
			self:HideNameplateIcon(namePlateFrameBase)
		end
		return
	end

	local namePlateFrameBase = self:GetAccessibleNameplateFrameForUnit(unitToken, false)

	self:ForgetResolvedNameplateQuestState(unitToken)
	self.nameplateHealthTintRetryCountByUnitToken[unitToken] = nil

	if namePlateFrameBase then
		-- Nameplate frames are recycled. Clear any stale icon/tint immediately so visuals
		-- from a previous unit cannot carry over before the live refresh resolves.
		self:HideNameplateIcon(namePlateFrameBase)
		self:RefreshNameplateIcon(namePlateFrameBase)
		return
	end

	self:ScheduleNameplateRefresh(unitToken)
end

function QuestTogether:OnNameplateRemoved(unitToken)
	if not self:IsNameplateUnitToken(unitToken) then
		return
	end

	self:ForgetResolvedNameplateQuestState(unitToken)
	self.nameplateRefreshPendingByUnitToken[unitToken] = nil
	self.nameplateRefreshGenerationByUnitToken[unitToken] = nil
	self.nameplateHealthTintRefreshPendingByUnitToken[unitToken] = nil
	self.nameplateHealthTintRetryCountByUnitToken[unitToken] = nil

	local namePlateFrameBase = self.API and self.API.GetNamePlateForUnit and self.API.GetNamePlateForUnit(unitToken) or nil
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

function QuestTogether:HandleNameplateEvent(eventName, ...)
	if eventName == "NAME_PLATE_UNIT_ADDED" then
		self:OnNameplateAdded(...)
	elseif eventName == "NAME_PLATE_UNIT_REMOVED" then
		self:OnNameplateRemoved(...)
	elseif eventName == "PLAYER_ENTERING_WORLD" then
		-- Plater routes PLAYER_ENTERING_WORLD through a delayed ZONE_CHANGED_NEW_AREA
		-- pass (local retail Plater.lua:2581-2586). Mirror that with a delayed
		-- visible-plate refresh instead of treating it as a quest-log event.
		local delayFn = self.API and self.API.Delay
		if type(delayFn) == "function" then
			delayFn(1, function()
				if QuestTogether.isEnabled then
					QuestTogether:ScheduleFullNameplateRefresh(0)
				end
			end)
		elseif self.isEnabled then
			self:ScheduleFullNameplateRefresh(0)
		end
	elseif
			eventName == "ZONE_CHANGED_NEW_AREA"
			or eventName == "ZONE_CHANGED_INDOORS"
			or eventName == "ZONE_CHANGED"
	then
		-- Plater refreshes all visible plates from ZONE_CHANGED_NEW_AREA and routes
		-- the other zone events into the same handler (local retail Plater.lua:2537-2578).
		if self.API and self.API.InCombatLockdown and self.API.InCombatLockdown() then
			local delayFn = self.API and self.API.Delay
			if type(delayFn) == "function" then
				delayFn(1, function()
					if QuestTogether.isEnabled then
						QuestTogether:ScheduleFullNameplateRefresh(0)
					end
				end)
				return
			end
		end
		self:ScheduleFullNameplateRefresh(0)
	elseif eventName == "PLAYER_REGEN_DISABLED" or eventName == "PLAYER_REGEN_ENABLED" then
		-- Plater refreshes visible plates on both combat enter and leave
		-- (Plater.lua:2319-2394). Mirror that instead of deferring combat updates.
		self:ScheduleFullNameplateRefresh(0)
	elseif
			eventName == "QUEST_LOG_UPDATE"
			or eventName == "QUEST_REMOVED"
			or eventName == "QUEST_ACCEPTED"
			or eventName == "QUEST_ACCEPT_CONFIRM"
			or eventName == "QUEST_COMPLETE"
			or eventName == "QUEST_POI_UPDATE"
			or eventName == "QUEST_QUERY_COMPLETE"
			or eventName == "QUEST_DETAIL"
			or eventName == "QUEST_FINISHED"
			or eventName == "QUEST_GREETING"
	then
		-- Mirrors Plater.QuestLogUpdated() (Plater.lua:2428-2469, 11423-11427):
		-- funnel quest-state events through a coalesced 1-second refresh so world-quest
		-- cache inputs have time to populate before visible plates are re-evaluated.
		self:ScheduleDeferredNameplateQuestStateRefresh(eventName, PLATER_QUEST_STATE_REFRESH_DELAY_SECONDS)
	elseif eventName == "DISPLAY_SIZE_CHANGED" then
		self:ScheduleFullNameplateRefresh(0.05)
	elseif eventName == "CVAR_UPDATE" then
		local cvarName = ...
		if SafeFindPlain(string.lower(SafeText(cvarName, "")), "nameplate") then
			self:Debugf("nameplate", "Refreshing nameplate augmentation after CVar change=%s", SafeText(cvarName, ""))
			self:ScheduleFullNameplateRefresh(0.05)
		end
	elseif
		eventName == "UNIT_HEALTH"
		or eventName == "UNIT_MAXHEALTH"
		or eventName == "UNIT_CONNECTION"
		or eventName == "UNIT_THREAT_LIST_UPDATE"
		or eventName == "UNIT_THREAT_SITUATION_UPDATE"
	then
		-- Combat threat styling can swap the live health-fill texture on Blizzard nameplates.
		-- Re-anchor our overlay on the same unit-token events so the tint survives combat.
		local unitToken = ...
		if self:IsNameplateUnitToken(unitToken) then
			self:ScheduleNameplateHealthTintRefresh(unitToken, nil, true)
		end
	elseif eventName == "UNIT_QUEST_LOG_CHANGED" then
		-- Plater feeds UNIT_QUEST_LOG_CHANGED through the same QuestLogUpdated() throttle
		-- without filtering the token argument (Plater.lua:2468-2470).
		self:ScheduleDeferredNameplateQuestStateRefresh(eventName, PLATER_QUEST_STATE_REFRESH_DELAY_SECONDS)
	end
end

function QuestTogether:EnableNameplateAugmentation()
	if not self.nameplateEventFrame then
		self.nameplateEventFrame = CreateFrame("Frame")
		self.nameplateRegisteredEvents = self.nameplateRegisteredEvents or {}
		self.nameplateEventFrame:SetScript("OnEvent", function(_, eventName, ...)
			self:HandleNameplateEvent(eventName, ...)
		end)
	end

	local function RegisterNameplateEvent(addon, eventName)
		-- Event availability differs by client build; keep registration best-effort.
		local ok = pcall(addon.nameplateEventFrame.RegisterEvent, addon.nameplateEventFrame, eventName)
		if ok then
			addon.nameplateRegisteredEvents[eventName] = true
			addon:Debugf("nameplate", "Registered augmentation event=%s", SafeText(eventName, ""))
		else
			addon.nameplateRegisteredEvents[eventName] = nil
			addon:Debugf("nameplate", "Failed to register augmentation event=%s", SafeText(eventName, ""))
		end
	end

	self:TryInstallNameplateHooks()
	self:Debug("Enabling nameplate augmentation events", "nameplate")
	RegisterNameplateEvent(self, "NAME_PLATE_UNIT_ADDED")
	RegisterNameplateEvent(self, "NAME_PLATE_UNIT_REMOVED")
	RegisterNameplateEvent(self, "QUEST_LOG_UPDATE")
	RegisterNameplateEvent(self, "QUEST_REMOVED")
	RegisterNameplateEvent(self, "QUEST_ACCEPTED")
	RegisterNameplateEvent(self, "QUEST_ACCEPT_CONFIRM")
	RegisterNameplateEvent(self, "QUEST_COMPLETE")
	RegisterNameplateEvent(self, "QUEST_POI_UPDATE")
	RegisterNameplateEvent(self, "QUEST_QUERY_COMPLETE")
	RegisterNameplateEvent(self, "QUEST_DETAIL")
	RegisterNameplateEvent(self, "QUEST_FINISHED")
	RegisterNameplateEvent(self, "QUEST_GREETING")
	RegisterNameplateEvent(self, "UNIT_QUEST_LOG_CHANGED")
	RegisterNameplateEvent(self, "UNIT_HEALTH")
	RegisterNameplateEvent(self, "UNIT_MAXHEALTH")
	RegisterNameplateEvent(self, "UNIT_CONNECTION")
	RegisterNameplateEvent(self, "UNIT_THREAT_LIST_UPDATE")
	RegisterNameplateEvent(self, "UNIT_THREAT_SITUATION_UPDATE")
	RegisterNameplateEvent(self, "PLAYER_ENTERING_WORLD")
	RegisterNameplateEvent(self, "ZONE_CHANGED_NEW_AREA")
	RegisterNameplateEvent(self, "ZONE_CHANGED_INDOORS")
	RegisterNameplateEvent(self, "ZONE_CHANGED")
	RegisterNameplateEvent(self, "PLAYER_REGEN_DISABLED")
	RegisterNameplateEvent(self, "PLAYER_REGEN_ENABLED")
	RegisterNameplateEvent(self, "DISPLAY_SIZE_CHANGED")
	RegisterNameplateEvent(self, "CVAR_UPDATE")
	self:ScheduleDeferredNameplateQuestStateRefresh(
		"EnableNameplateAugmentation",
		PLATER_QUEST_STATE_REFRESH_DELAY_SECONDS
	)
	self:SchedulePlaterStartupNameplateRefreshes()
end

function QuestTogether:DisableNameplateAugmentation()
	if not self.nameplateEventFrame then
		return
	end
	self:Debug("Disabling nameplate augmentation", "nameplate")

	for eventName in pairs(self.nameplateRegisteredEvents or {}) do
		-- Unregister should never break disable flow if an event was already invalidated.
		pcall(self.nameplateEventFrame.UnregisterEvent, self.nameplateEventFrame, eventName)
		self:Debugf("nameplate", "Unregistered augmentation event=%s", SafeText(eventName, ""))
	end
	if self.nameplateRegisteredEvents then
		wipe(self.nameplateRegisteredEvents)
	end

	-- Hide our icon overlays and clear cached quest objective state.
	self:ClearNameplateQuestDetectionCache()
	wipe(self.nameplateQuestStateByUnitToken)
	wipe(self.nameplateQuestGuidByUnitToken)
	wipe(self.nameplateRefreshPendingByUnitToken)
	wipe(self.nameplateRefreshGenerationByUnitToken)
	wipe(self.nameplateHealthTintRefreshPendingByUnitToken)
	self.pendingDeferredNameplateQuestStateRefresh = false
	self.deferredNameplateQuestStateRefreshGeneration = 0
	self:ForEachVisibleNamePlate(function(frame)
		self:HideNameplateIcon(frame)
	end)
	wipe(self.nameplateBubbleStateByFrame)
	wipe(self.nameplateHealthOverlayByUnitFrame)
end
