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
local ENABLE_TOOLTIP_QUEST_SCAN_FALLBACK = true
local QUEST_SCAN_TOOLTIP_FRAME_NAME = "QuestTogetherQuestScanTooltip"
local QUEST_SCAN_TOOLTIP_OWNER_FRAME_NAME = "QuestTogetherQuestScanTooltipOwner"
local ANNOUNCEMENT_BUBBLE_Y_OFFSET = 22
local ANNOUNCEMENT_BUBBLE_FADE_IN_SECONDS = 0.2
local ANNOUNCEMENT_BUBBLE_FADE_OUT_SECONDS = 0.4
local PERSONAL_BUBBLE_SETTINGS_DIALOG_WIDTH = 380
local PERSONAL_BUBBLE_SETTINGS_DIALOG_HEIGHT = 220
local ApplyQuestIconVisual
local SafeUiNumber
local questScanTooltipFrame = nil
local questScanTooltipOwnerFrame = nil

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
QuestTogether.nameplateQuestObjectiveCache = QuestTogether.nameplateQuestObjectiveCache or {}
QuestTogether.nameplateQuestStateByUnitToken = QuestTogether.nameplateQuestStateByUnitToken or {}
QuestTogether.nameplateTooltipGuidByUnitToken = QuestTogether.nameplateTooltipGuidByUnitToken or {}
QuestTogether.nameplateIconByUnitFrame = QuestTogether.nameplateIconByUnitFrame
	or setmetatable({}, { __mode = "k" })
QuestTogether.nameplateHealthOverlayByUnitFrame = QuestTogether.nameplateHealthOverlayByUnitFrame
	or setmetatable({}, { __mode = "k" })
QuestTogether.nameplateBubbleByUnitFrame = QuestTogether.nameplateBubbleByUnitFrame
	or setmetatable({}, { __mode = "k" })
QuestTogether.personalBubbleSliderHandlesByFrame = QuestTogether.personalBubbleSliderHandlesByFrame
	or setmetatable({}, { __mode = "k" })
QuestTogether.nameplateRefreshPendingByUnitToken = QuestTogether.nameplateRefreshPendingByUnitToken or {}
QuestTogether.nameplateRefreshGenerationByUnitToken = QuestTogether.nameplateRefreshGenerationByUnitToken or {}
QuestTogether.nameplateHealthTintRefreshPendingByUnitToken =
	QuestTogether.nameplateHealthTintRefreshPendingByUnitToken or {}
QuestTogether.nameplateHealthTintRetryCountByUnitToken = QuestTogether.nameplateHealthTintRetryCountByUnitToken or {}
QuestTogether.nameplateFullRefreshGeneration = QuestTogether.nameplateFullRefreshGeneration or 0
QuestTogether.pendingNameplateRefreshAfterCombat = QuestTogether.pendingNameplateRefreshAfterCombat or false

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

local function ScaleBubbleMetric(baseValue, sizeScale, minimumValue)
	local scaledValue = math.floor((baseValue * sizeScale) + 0.5)
	if minimumValue then
		return math.max(minimumValue, scaledValue)
	end
	return scaledValue
end

local function GetQuestScanTooltipFrame()
	if questScanTooltipFrame and not IsFrameForbidden(questScanTooltipFrame) then
		return questScanTooltipFrame
	end

	local existingTooltip = _G[QUEST_SCAN_TOOLTIP_FRAME_NAME]
	if existingTooltip and not IsFrameForbidden(existingTooltip) then
		questScanTooltipFrame = existingTooltip
		return questScanTooltipFrame
	end

	if type(CreateFrame) ~= "function" then
		return nil
	end

	local tooltipFrame = CreateFrame("GameTooltip", QUEST_SCAN_TOOLTIP_FRAME_NAME, nil, "GameTooltipTemplate")
	if not tooltipFrame or IsFrameForbidden(tooltipFrame) then
		return nil
	end

	questScanTooltipFrame = tooltipFrame
	return questScanTooltipFrame
end

local function GetQuestScanTooltipOwnerFrame()
	if questScanTooltipOwnerFrame and not IsFrameForbidden(questScanTooltipOwnerFrame) then
		return questScanTooltipOwnerFrame
	end

	local existingOwner = _G[QUEST_SCAN_TOOLTIP_OWNER_FRAME_NAME]
	if existingOwner and not IsFrameForbidden(existingOwner) then
		questScanTooltipOwnerFrame = existingOwner
		return questScanTooltipOwnerFrame
	end

	if type(CreateFrame) ~= "function" then
		return nil
	end

	local parentFrame = UIParent or nil
	local ownerFrame = CreateFrame("Frame", QUEST_SCAN_TOOLTIP_OWNER_FRAME_NAME, parentFrame)
	if not ownerFrame or IsFrameForbidden(ownerFrame) then
		return nil
	end

	ownerFrame:Hide()
	questScanTooltipOwnerFrame = ownerFrame
	return questScanTooltipOwnerFrame
end

local function BuildPseudoTooltipLinesFromHiddenTooltip(tooltipFrame)
	if
		not tooltipFrame
		or IsFrameForbidden(tooltipFrame)
		or not tooltipFrame.GetName
		or not tooltipFrame.NumLines
	then
		return {}
	end

	local tooltipName = tooltipFrame:GetName()
	if type(tooltipName) ~= "string" or tooltipName == "" then
		return {}
	end

	local lineCount = SafeUiNumber(tooltipFrame:NumLines(), 0) or 0
	local pseudoLines = {}
	for lineIndex = 1, lineCount do
		local leftRegion = _G[tooltipName .. "TextLeft" .. tostring(lineIndex)]
		local rightRegion = _G[tooltipName .. "TextRight" .. tostring(lineIndex)]
		local leftText = leftRegion and leftRegion.GetText and leftRegion:GetText() or nil
		local rightText = rightRegion and rightRegion.GetText and rightRegion:GetText() or nil
		if type(leftText) == "string" or type(rightText) == "string" then
			pseudoLines[#pseudoLines + 1] = {
				-- Hidden tooltip scans do not expose structured line types; map them into the
				-- objective parser as generic quest-objective candidates.
				type = "QuestObjective",
				leftText = leftText,
				rightText = rightText,
				text = leftText,
			}
		end
	end

	return pseudoLines
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

function QuestTogether:GetNameplateNowSeconds()
	return self.API.GetTime()
end

function QuestTogether:DoesNameplateUnitExist(unitToken)
	if self.API and self.API.UnitExists then
		return self.API.UnitExists(unitToken)
	end
	local ok, exists = pcall(UnitExists, unitToken)
	return ok and exists and true or false
end

function QuestTogether:GetNameplateUnitGuid(unitToken)
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
	local ok, isQuestBoss = pcall(UnitIsQuestBoss, unitToken)
	return ok and isQuestBoss and true or false
end

function QuestTogether:CanPlayerAttackNameplateUnit(unitToken)
	local ok, canAttack = pcall(UnitCanAttack, "player", unitToken)
	return ok and canAttack and true or false
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

	local percentText = SafeMatch(text, "(%d+%.?%d*)%%")
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

local function LooksLikeProgressText(text)
	if type(text) ~= "string" or text == "" then
		return false
	end
	if SafeMatch(text, "(%d+)%s*/%s*(%d+)") then
		return true
	end
	if SafeMatch(text, "(%d+%.?%d*)%%") then
		return true
	end
	return false
end

local function IsKnownQuestTitleLine(text)
	local trimmedText = SafeTrimText(text)
	if trimmedText == "" then
		return false
	end
	return QuestTogether and QuestTogether.nameplateQuestTitleCache and QuestTogether.nameplateQuestTitleCache[trimmedText]
		or false
end

local function NormalizeObjectiveTextForCompare(addon, text)
	local normalizedText = SafeTrimText(text)
	if normalizedText == "" then
		return ""
	end

	if addon and addon.StripTrailingParentheticalPercent then
		normalizedText = addon:StripTrailingParentheticalPercent(normalizedText)
	end
	return SafeTrimText(normalizedText)
end

function QuestTogether:IsTooltipObjectiveTextFromTrackedQuest(candidateText)
	local normalizedCandidateText = NormalizeObjectiveTextForCompare(self, candidateText)
	if normalizedCandidateText == "" then
		return false
	end
	if IsKnownQuestTitleLine(normalizedCandidateText) then
		return false
	end

	local tracker = self.GetPlayerTracker and self:GetPlayerTracker() or nil
	if type(tracker) ~= "table" then
		return false
	end

	for _, questData in pairs(tracker) do
		local objectives = questData and questData.objectives or nil
		if type(objectives) == "table" then
			for _, objectiveText in pairs(objectives) do
				local normalizedObjectiveText = NormalizeObjectiveTextForCompare(self, objectiveText)
				if normalizedObjectiveText ~= "" and normalizedObjectiveText == normalizedCandidateText then
					return true
				end
			end
		end
	end

	return false
end

local function IsTooltipObjectiveOrPlayerLineType(lineType)
	if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(lineType) then
		return false
	end

	if Enum and Enum.TooltipDataLineType then
		return lineType == Enum.TooltipDataLineType.QuestObjective or lineType == Enum.TooltipDataLineType.QuestPlayer
	end

	local normalizedType = SafeText(lineType, "")
	return normalizedType == "QuestObjective" or normalizedType == "QuestPlayer"
end

function QuestTogether:EvaluateTooltipQuestObjectiveLines(tooltipLines)
	if type(tooltipLines) ~= "table" then
		return false
	end

	for _, lineData in ipairs(tooltipLines) do
		if self:IsSecretValue(lineData) then
			break
		end

		local lineType = lineData and lineData.type
		if self:IsSecretValue(lineType) then
			break
		end

		if IsTooltipObjectiveOrPlayerLineType(lineType) then
			local leftText = lineData and lineData.leftText or nil
			local rightText = lineData and lineData.rightText or nil
			local centerText = lineData and lineData.text or nil
			if self:IsSecretValue(leftText) then
				leftText = nil
			end
			if self:IsSecretValue(rightText) then
				rightText = nil
			end
			if self:IsSecretValue(centerText) then
				centerText = nil
			end

			if type(leftText) ~= "string" then
				leftText = nil
			end
			if type(rightText) ~= "string" then
				rightText = nil
			end
			if type(centerText) ~= "string" then
				centerText = nil
			end

			local textCandidates = {
				SafeTrimText(rightText),
				SafeTrimText(leftText),
				SafeTrimText(centerText),
			}
			local lineTypeIsPlayer = (Enum and Enum.TooltipDataLineType and lineType == Enum.TooltipDataLineType.QuestPlayer)
				or SafeText(lineType, "") == "QuestPlayer"

				for candidateIndex = 1, #textCandidates do
					local candidateText = textCandidates[candidateIndex]
					if candidateText ~= "" then
						local progressState = GetObjectiveProgressState(candidateText)
						if progressState == "unfinished" then
							return true
						end
						if progressState == "unknown" then
							if lineTypeIsPlayer and LooksLikeProgressText(candidateText) then
								return true
							end
							-- For non-player objective lines without explicit progress numbers, require the
							-- text to match an active tracked objective to avoid broad false positives.
							if not lineTypeIsPlayer and self:IsTooltipObjectiveTextFromTrackedQuest(candidateText) then
								return true
							end
						end
					end
				end
		end
	end

	return false
end

function QuestTogether:ClearNameplateQuestObjectiveCache()
	wipe(self.nameplateQuestObjectiveCache)
	wipe(self.nameplateQuestStateByUnitToken)
end

function QuestTogether:RebuildNameplateQuestTitleCache()
	wipe(self.nameplateQuestTitleCache)

	if not self.API or not self.API.GetNumQuestLogEntries or not self.API.GetQuestLogInfo then
		return
	end

	local totalEntries = SafeUiNumber(self.API.GetNumQuestLogEntries(), 0) or 0
	for entryIndex = 1, totalEntries do
		local questDetails = self.API.GetQuestLogInfo(entryIndex)
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

	-- Merge tracker titles as a fallback cache source without touching shared map-task tables.
	-- Reading C_TaskQuest map task arrays taints Blizzard map pins in combat.
	for _, trackedQuest in pairs(self:GetPlayerTracker() or {}) do
		local trackedTitle = trackedQuest and trackedQuest.title or nil
		if type(trackedTitle) == "string" and trackedTitle ~= "" then
			self.nameplateQuestTitleCache[trackedTitle] = true
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
	if IsFrameForbidden(unitFrame) then
		unitFrame = nil
	end

	local plateFrame = unitFrame and unitFrame.PlateFrame or nil
	if IsFrameForbidden(plateFrame) then
		plateFrame = nil
	end
	local candidateGuids = {
		unitFrame and unitFrame.namePlateUnitGUID or nil,
		plateFrame and plateFrame.namePlateUnitGUID or nil,
	}

	for index = 1, #candidateGuids do
		local candidateGuid = candidateGuids[index]
		if self:IsSecretValue(candidateGuid) then
			candidateGuid = nil
		end
		if IsNonEmptyString(candidateGuid) then
			if type(unitToken) == "string" and unitToken ~= "" then
				self.nameplateTooltipGuidByUnitToken[unitToken] = candidateGuid
			end
			return candidateGuid
		end
	end

	local liveGuid = self:GetNameplateUnitGuid(unitToken)
	if IsNonEmptyString(liveGuid) then
		if type(unitToken) == "string" and unitToken ~= "" then
			self.nameplateTooltipGuidByUnitToken[unitToken] = liveGuid
		end
		return liveGuid
	end

	local cachedGuidByToken = type(unitToken) == "string" and self.nameplateTooltipGuidByUnitToken[unitToken] or nil
	if self:IsSecretValue(cachedGuidByToken) then
		cachedGuidByToken = nil
	end
	if IsNonEmptyString(cachedGuidByToken) then
		return cachedGuidByToken
	end

	return nil
end

function QuestTogether:IsQuestObjectiveViaTooltip(unitToken, unitFrame)
	if not ENABLE_TOOLTIP_QUEST_SCAN_FALLBACK then
		return false
	end

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
	if self:IsSecretValue(unitGuid) then
		return false
	end
	if not IsNonEmptyString(unitGuid) then
		return false
	end

	local cachedValue = self:GetCachedQuestObjectiveResult(unitGuid)
	if cachedValue ~= nil then
		return cachedValue
	end

	local scanTooltip = GetQuestScanTooltipFrame()
	if not scanTooltip then
		self:SetCachedQuestObjectiveResult(unitGuid, false)
		return false
	end
	local tooltipOwner = GetQuestScanTooltipOwnerFrame()

	local okScan = pcall(function()
		if scanTooltip.ClearLines then
			scanTooltip:ClearLines()
		end
		if scanTooltip.SetOwner then
			scanTooltip:SetOwner(tooltipOwner or UIParent, "ANCHOR_NONE")
		end
		scanTooltip:SetHyperlink("unit:" .. unitGuid)
	end)
	if not okScan then
		self:SetCachedQuestObjectiveResult(unitGuid, false)
		return false
	end

	local tooltipLines = BuildPseudoTooltipLinesFromHiddenTooltip(scanTooltip)
	if scanTooltip.Hide then
		pcall(scanTooltip.Hide, scanTooltip)
	end

	-- Consider any unfinished quest objective text (including party-progress style lines)
	-- as objective evidence while avoiding direct interaction with structured tooltip tables.
	local result = self:EvaluateTooltipQuestObjectiveLines(tooltipLines)
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
	if IsFrameForbidden(unitFrame) then
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
	if IsFrameForbidden(frame) then
		return false
	end

	if not self:IsNameplateUnitToken(frame.unit) then
		return false
	end

	if not frame.healthBar then
		return false
	end
	if IsFrameForbidden(frame.healthBar) then
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
	if unitFrame.healthBar and not IsFrameForbidden(unitFrame.healthBar) then
		return unitFrame.healthBar
	end
	if unitFrame.HealthBarsContainer and not IsFrameForbidden(unitFrame.HealthBarsContainer) then
		return unitFrame.HealthBarsContainer
	end
	return unitFrame
end

local function ResolveNameplateUnitToken(namePlateFrameBase, unitFrame)
	local candidateTokens = {
		namePlateFrameBase and not IsFrameForbidden(namePlateFrameBase) and namePlateFrameBase.GetUnit and namePlateFrameBase:GetUnit()
			or nil,
		unitFrame and unitFrame.unit or nil,
		unitFrame and unitFrame.displayedUnit or nil,
	}

	for index = 1, #candidateTokens do
		local candidateToken = candidateTokens[index]
		if QuestTogether:IsNameplateUnitToken(candidateToken) then
			return candidateToken
		end
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
		local nameText = unitFrame.name
		if IsFrameForbidden(nameText) then
			nameText = nil
		end
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
	if icon and icon.SetAllPoints then
		icon:SetAllPoints(iconFrame)
	end
end

local function EnsureQuestIcon(unitFrame)
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

	local namePlateFrameBase = nil
	if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
		-- Nameplate retrieval can fail in secure contexts; treat as "not visible".
		local ok, frameOrNil = pcall(C_NamePlate.GetNamePlateForUnit, unitToken, false)
		if ok then
			namePlateFrameBase = frameOrNil
		end
	end
	if
		namePlateFrameBase
		and namePlateFrameBase.UnitFrame
		and not IsFrameForbidden(namePlateFrameBase)
		and not IsFrameForbidden(namePlateFrameBase.UnitFrame)
		and namePlateFrameBase:IsShown()
	then
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
	bubble.qtCurrentText = message
	bubble.qtCurrentEventType = eventType
	bubble.qtCurrentIconAsset = iconAsset
	bubble.qtCurrentIconKind = iconKind
	bubble.qtHostFrame = namePlateFrameBase

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

		local okFrame, namePlateFrameBase = pcall(C_NamePlate.GetNamePlateForUnit, unitToken, false)
		if not okFrame then
			return
		end
		if
			not namePlateFrameBase
			or not namePlateFrameBase.UnitFrame
			or IsFrameForbidden(namePlateFrameBase)
			or IsFrameForbidden(namePlateFrameBase.UnitFrame)
			or not namePlateFrameBase:IsShown()
		then
			return
		end

		local unitFrame = namePlateFrameBase.UnitFrame
		local liveUnitToken = ResolveNameplateUnitToken(namePlateFrameBase, unitFrame)
		if not liveUnitToken then
			self.nameplateQuestStateByUnitToken[unitToken] = nil
			self:RestoreNameplateHealthColor(unitFrame)
			return
		end

		if liveUnitToken ~= unitToken then
			self.nameplateQuestStateByUnitToken[unitToken] = nil
			self.nameplateHealthTintRetryCountByUnitToken[unitToken] = nil
		end

		local isQuestObjective = self:IsQuestObjectiveNameplate(liveUnitToken, unitFrame)
		self.nameplateQuestStateByUnitToken[liveUnitToken] = isQuestObjective and true or false

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

	local generation = (self.nameplateRefreshGenerationByUnitToken[unitToken] or 0) + 1
	self.nameplateRefreshGenerationByUnitToken[unitToken] = generation
	self.nameplateRefreshPendingByUnitToken[unitToken] = true

	-- Quest-related tooltip/API flags on fresh nameplates can lag behind the add event.
	-- Run a short refresh burst so objective markers resolve once data catches up.
	local refreshDelays = {
		0,
		0.05,
		0.15,
		0.35,
		0.70,
	}
	local lastRefreshIndex = #refreshDelays

	for refreshIndex = 1, lastRefreshIndex do
		local refreshDelay = refreshDelays[refreshIndex]
		self.API.Delay(refreshDelay, function()
			if self.nameplateRefreshGenerationByUnitToken[unitToken] ~= generation then
				return
			end
			if refreshIndex == lastRefreshIndex then
				self.nameplateRefreshPendingByUnitToken[unitToken] = nil
			end
			if not self.isEnabled or not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then
				return
			end

			local okFrame, namePlateFrameBase = pcall(C_NamePlate.GetNamePlateForUnit, unitToken, false)
			if not okFrame then
				return
			end
			if
				not namePlateFrameBase
				or not namePlateFrameBase.UnitFrame
				or IsFrameForbidden(namePlateFrameBase)
				or IsFrameForbidden(namePlateFrameBase.UnitFrame)
				or not namePlateFrameBase:IsShown()
			then
				return
			end

			self:RefreshNameplateIcon(namePlateFrameBase)
		end)
	end
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
		if not IsFrameForbidden(icon) then
			icon:Show()
		end
	elseif icon then
		if not IsFrameForbidden(icon) then
			icon:Hide()
		end
	end
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

function QuestTogether:RefreshNameplatesForQuestStateChange(reason)
	if self.API and self.API.InCombatLockdown and self.API.InCombatLockdown() then
		self.pendingNameplateRefreshAfterCombat = true
		self:Debugf("nameplate", "Deferring nameplate refresh during combat reason=%s", SafeText(reason, ""))
		return false
	end

	self.pendingNameplateRefreshAfterCombat = false
	self:RebuildNameplateQuestTitleCache()
	self:ClearNameplateQuestObjectiveCache()
	self:RefreshNameplateAugmentation()
	return true
end

function QuestTogether:ScheduleFullNameplateRefresh(delaySeconds)
	if self.API and self.API.InCombatLockdown and self.API.InCombatLockdown() then
		self.pendingNameplateRefreshAfterCombat = true
		self:Debug("Deferring full nameplate refresh scheduling during combat", "nameplate")
		return
	end

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
			if self.API and self.API.InCombatLockdown and self.API.InCombatLockdown() then
				self.pendingNameplateRefreshAfterCombat = true
				self:Debug("Deferring scheduled full nameplate refresh during combat", "nameplate")
				return
			end

			self:RefreshNameplatesForQuestStateChange("ScheduleFullNameplateRefresh")
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
		self.nameplateTooltipGuidByUnitToken[unitToken] = nil
		return
	end

	self.nameplateQuestStateByUnitToken[unitToken] = nil
	self.nameplateTooltipGuidByUnitToken[unitToken] = nil
	self.nameplateHealthTintRetryCountByUnitToken[unitToken] = nil

	if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
		local okFrame, namePlateFrameBase = pcall(C_NamePlate.GetNamePlateForUnit, unitToken, false)
		if okFrame and namePlateFrameBase then
			-- Nameplate frames are recycled. Clear any stale icon/tint immediately so visuals
			-- from a previous unit cannot carry over while the deferred refresh resolves.
			self:HideNameplateIcon(namePlateFrameBase)
		end
	end

	self:ScheduleNameplateRefresh(unitToken)
end

function QuestTogether:OnNameplateRemoved(unitToken)
	if not self:IsNameplateUnitToken(unitToken) then
		return
	end

	self.nameplateQuestStateByUnitToken[unitToken] = nil
	self.nameplateTooltipGuidByUnitToken[unitToken] = nil
	self.nameplateRefreshPendingByUnitToken[unitToken] = nil
	self.nameplateRefreshGenerationByUnitToken[unitToken] = nil
	self.nameplateHealthTintRefreshPendingByUnitToken[unitToken] = nil
	self.nameplateHealthTintRetryCountByUnitToken[unitToken] = nil

	local namePlateFrameBase = nil
	if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
		local okFrame, frameOrNil = pcall(C_NamePlate.GetNamePlateForUnit, unitToken, false)
		if okFrame then
			namePlateFrameBase = frameOrNil
		end
	end
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
			elseif eventName == "PLAYER_REGEN_ENABLED" then
				if self.pendingNameplateRefreshAfterCombat then
					self:Debug("Resuming deferred nameplate refresh after combat", "nameplate")
					self.pendingNameplateRefreshAfterCombat = false
					self:ScheduleFullNameplateRefresh(0.05)
				end
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
				self:RefreshNameplatesForQuestStateChange(eventName)
			elseif eventName == "DISPLAY_SIZE_CHANGED" then
				self:ScheduleFullNameplateRefresh(0.05)
			elseif eventName == "CVAR_UPDATE" then
				local cvarName = ...
				if SafeFindPlain(string.lower(SafeText(cvarName, "")), "nameplate") then
					self:Debugf("nameplate", "Refreshing nameplate augmentation after CVar change=%s", SafeText(cvarName, ""))
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
					self:RefreshNameplatesForQuestStateChange(eventName)
				end
			end
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
	RegisterNameplateEvent(self, "QUEST_DETAIL")
	RegisterNameplateEvent(self, "QUEST_FINISHED")
	RegisterNameplateEvent(self, "QUEST_GREETING")
	RegisterNameplateEvent(self, "UNIT_QUEST_LOG_CHANGED")
	RegisterNameplateEvent(self, "UNIT_HEALTH")
	RegisterNameplateEvent(self, "UNIT_MAXHEALTH")
	RegisterNameplateEvent(self, "UNIT_CONNECTION")
	RegisterNameplateEvent(self, "PLAYER_ENTERING_WORLD")
	RegisterNameplateEvent(self, "PLAYER_REGEN_ENABLED")
	RegisterNameplateEvent(self, "DISPLAY_SIZE_CHANGED")
	RegisterNameplateEvent(self, "CVAR_UPDATE")
	self:RefreshNameplatesForQuestStateChange("EnableNameplateAugmentation")
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
	wipe(self.nameplateQuestStateByUnitToken)
	wipe(self.nameplateTooltipGuidByUnitToken)
	wipe(self.nameplateRefreshPendingByUnitToken)
	wipe(self.nameplateRefreshGenerationByUnitToken)
	wipe(self.nameplateHealthTintRefreshPendingByUnitToken)
	self.pendingNameplateRefreshAfterCombat = false
	self:ForEachVisibleNamePlate(function(frame)
		self:HideNameplateIcon(frame)
	end)
	wipe(self.nameplateHealthOverlayByUnitFrame)
end
