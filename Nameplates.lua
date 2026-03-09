--[[
QuestTogether Nameplate Augmentation

Purpose:
- Add a quest icon on Blizzard default nameplates for quest-objective units.
- Optionally tint quest-objective nameplate health bars to a burnt orange color.

Design constraints:
- Keep the implementation minimal and non-invasive.
- Do not replace Blizzard templates or secure handlers.
- Hook post-update paths so Blizzard remains source-of-truth for baseline behavior.
]]

local QuestTogether = _G.QuestTogether
local QUEST_SCAN_CACHE_TTL_SECONDS = 0.5
local PROTOTYPE_BUBBLE_Y_OFFSET = 22
local PROTOTYPE_BUBBLE_FADE_IN_SECONDS = 0.2
local PROTOTYPE_BUBBLE_FADE_OUT_SECONDS = 0.4
local PERSONAL_BUBBLE_ANCHOR_EDIT_WIDTH = 220
local PERSONAL_BUBBLE_ANCHOR_EDIT_HEIGHT = 40
local ApplyQuestIconVisual

local CHAT_BUBBLE_SIZE_CONFIGS = {
	small = {
		fontSize = 14,
		iconSize = 18,
		iconGap = 8,
		minTextWidth = 48,
		maxTextWidth = 220,
		inset = 16,
	},
	medium = {
		fontSize = 17,
		iconSize = 22,
		iconGap = 10,
		minTextWidth = 60,
		maxTextWidth = 260,
		inset = 18,
	},
	large = {
		fontSize = 20,
		iconSize = 26,
		iconGap = 12,
		minTextWidth = 72,
		maxTextWidth = 300,
		inset = 20,
	},
}

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

local function IsSecretValue(value)
	if type(issecretvalue) ~= "function" then
		return false
	end
	local ok, result = pcall(issecretvalue, value)
	return ok and result and true or false
end

QuestTogether.nameplateQuestTitleCache = QuestTogether.nameplateQuestTitleCache or {}
QuestTogether.nameplateQuestObjectiveCache = QuestTogether.nameplateQuestObjectiveCache or {}
QuestTogether.nameplateQuestStateByUnitToken = QuestTogether.nameplateQuestStateByUnitToken or {}
QuestTogether.nameplateIconByUnitFrame = QuestTogether.nameplateIconByUnitFrame
	or setmetatable({}, { __mode = "k" })
QuestTogether.nameplateBaseHealthColorByUnitFrame = QuestTogether.nameplateBaseHealthColorByUnitFrame
	or setmetatable({}, { __mode = "k" })
QuestTogether.nameplateBubbleByUnitFrame = QuestTogether.nameplateBubbleByUnitFrame
	or setmetatable({}, { __mode = "k" })

local function GetPrototypeBubbleLifetimeSeconds()
	local configuredDuration = tonumber(QuestTogether:GetOption("chatBubbleDuration"))
	if not configuredDuration or configuredDuration <= 0 then
		configuredDuration = QuestTogether.DEFAULTS.profile.chatBubbleDuration
	end
	return configuredDuration
end

local function GetPrototypeBubbleUnitFrame(hostFrame)
	if not hostFrame then
		return nil
	end
	return hostFrame.UnitFrame or hostFrame
end

local function GetPrototypeBubbleVisualConfig()
	local configuredSize = QuestTogether:GetOption("chatBubbleSize")
	return CHAT_BUBBLE_SIZE_CONFIGS[configuredSize] or CHAT_BUBBLE_SIZE_CONFIGS.medium
end

local function GetPrototypeBubbleScreenHostFrame()
	if QuestTogether.prototypeBubbleScreenHostFrame then
		return QuestTogether.prototypeBubbleScreenHostFrame
	end

	local parentFrame = UIParent or (C_UI and C_UI.GetUIParent and C_UI.GetUIParent()) or nil
	if not parentFrame then
		return nil
	end

	local hostFrame = CreateFrame("Frame", "QuestTogetherPersonalBubbleAnchor", parentFrame)
	hostFrame:SetSize(1, 1)
	hostFrame:SetFrameStrata("HIGH")
	hostFrame:SetFrameLevel(parentFrame:GetFrameLevel() + 50)
	hostFrame:SetClampedToScreen(true)
	hostFrame:SetMovable(true)
	hostFrame:RegisterForDrag("LeftButton")
	hostFrame:EnableMouse(false)

	local background = hostFrame:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0.05, 0.05, 0.05, 0.7)
	background:Hide()
	hostFrame.EditBackground = background

	local borderTop = hostFrame:CreateTexture(nil, "BORDER")
	borderTop:SetColorTexture(1, 0.82, 0, 0.95)
	borderTop:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", 0, 0)
	borderTop:SetPoint("TOPRIGHT", hostFrame, "TOPRIGHT", 0, 0)
	borderTop:SetHeight(1)
	borderTop:Hide()
	hostFrame.EditBorderTop = borderTop

	local borderBottom = hostFrame:CreateTexture(nil, "BORDER")
	borderBottom:SetColorTexture(1, 0.82, 0, 0.95)
	borderBottom:SetPoint("BOTTOMLEFT", hostFrame, "BOTTOMLEFT", 0, 0)
	borderBottom:SetPoint("BOTTOMRIGHT", hostFrame, "BOTTOMRIGHT", 0, 0)
	borderBottom:SetHeight(1)
	borderBottom:Hide()
	hostFrame.EditBorderBottom = borderBottom

	local borderLeft = hostFrame:CreateTexture(nil, "BORDER")
	borderLeft:SetColorTexture(1, 0.82, 0, 0.95)
	borderLeft:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", 0, 0)
	borderLeft:SetPoint("BOTTOMLEFT", hostFrame, "BOTTOMLEFT", 0, 0)
	borderLeft:SetWidth(1)
	borderLeft:Hide()
	hostFrame.EditBorderLeft = borderLeft

	local borderRight = hostFrame:CreateTexture(nil, "BORDER")
	borderRight:SetColorTexture(1, 0.82, 0, 0.95)
	borderRight:SetPoint("TOPRIGHT", hostFrame, "TOPRIGHT", 0, 0)
	borderRight:SetPoint("BOTTOMRIGHT", hostFrame, "BOTTOMRIGHT", 0, 0)
	borderRight:SetWidth(1)
	borderRight:Hide()
	hostFrame.EditBorderRight = borderRight

	local icon = hostFrame:CreateTexture(nil, "ARTWORK")
	icon:SetSize(16, 16)
	icon:SetPoint("LEFT", hostFrame, "LEFT", 8, 0)
	ApplyQuestIconVisual(icon)
	icon:Hide()
	hostFrame.EditIcon = icon

	local label = hostFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	label:SetJustifyH("LEFT")
	label:SetText("QuestTogether Bubble")
	label:Hide()
	hostFrame.EditLabel = label

	hostFrame:SetScript("OnDragStart", function(frame)
		if not QuestTogether:IsPersonalBubbleAnchorInEditMode() then
			return
		end
		frame:StartMoving()
	end)
	hostFrame:SetScript("OnDragStop", function(frame)
		frame:StopMovingOrSizing()
		QuestTogether:SavePersonalBubbleAnchorFromFrame(frame)
	end)

	QuestTogether.prototypeBubbleScreenHostFrame = hostFrame
	QuestTogether:ApplySavedPersonalBubbleAnchor()
	QuestTogether:RefreshPersonalBubbleAnchorVisualState()
	hostFrame:Show()

	return hostFrame
end

function QuestTogether:IsPersonalBubbleAnchorInEditMode()
	return self.isEnabled and EditModeManagerFrame and EditModeManagerFrame:IsShown() and self:GetOption("showChatBubbles")
end

function QuestTogether:ApplySavedPersonalBubbleAnchor()
	local hostFrame = self.prototypeBubbleScreenHostFrame
	if not hostFrame then
		return
	end

	local parentFrame = hostFrame:GetParent() or UIParent
	local anchor = self:GetPersonalBubbleAnchor()
	hostFrame:ClearAllPoints()
	hostFrame:SetPoint(anchor.point, parentFrame, anchor.relativePoint, anchor.x, anchor.y)
end

local function RoundOffset(value)
	local numberValue = tonumber(value) or 0
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

	return self:SetPersonalBubbleAnchor(point, relativePoint, RoundOffset(offsetX), RoundOffset(offsetY))
end

function QuestTogether:RefreshPersonalBubbleAnchorVisualState()
	local hostFrame = self.prototypeBubbleScreenHostFrame
	if not hostFrame then
		return
	end

	local editModeActive = self:IsPersonalBubbleAnchorInEditMode()
	if editModeActive then
		hostFrame:SetSize(PERSONAL_BUBBLE_ANCHOR_EDIT_WIDTH, PERSONAL_BUBBLE_ANCHOR_EDIT_HEIGHT)
	else
		hostFrame:SetSize(1, 1)
	end
	hostFrame:EnableMouse(editModeActive)

	local visibleFields = {
		hostFrame.EditBackground,
		hostFrame.EditBorderTop,
		hostFrame.EditBorderBottom,
		hostFrame.EditBorderLeft,
		hostFrame.EditBorderRight,
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

	hostFrame:Show()
end

function QuestTogether:TryInstallPersonalBubbleEditModeHooks()
	if self.personalBubbleEditModeHooksInstalled then
		return
	end

	if not EditModeManagerFrame or not EditModeManagerFrame.HookScript then
		return
	end

	GetPrototypeBubbleScreenHostFrame()

	EditModeManagerFrame:HookScript("OnShow", function()
		QuestTogether:RefreshPersonalBubbleAnchorVisualState()
	end)
	EditModeManagerFrame:HookScript("OnHide", function()
		QuestTogether:RefreshPersonalBubbleAnchorVisualState()
	end)

	self.personalBubbleEditModeHooksInstalled = true
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
	local unitGuid = UnitGUID(unitToken)
	if not unitGuid or IsSecretValue(unitGuid) then
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
	local ok, isRelated = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unitToken)
	return ok and isRelated and true or false
end

function QuestTogether:IsNameplateUnitOnQuest(unitToken, questId)
	if not C_QuestLog or not C_QuestLog.IsUnitOnQuest then
		return false
	end
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

	local amountCurrent, amountTotal = text:match("(%d+)%s*/%s*(%d+)")
	if amountCurrent and amountTotal then
		if tonumber(amountCurrent) < tonumber(amountTotal) then
			return "unfinished"
		end
		return "complete"
	end

	local percentText = text:match("(%d+)%%")
	if percentText then
		if tonumber(percentText) < 100 then
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

function QuestTogether:IsQuestObjectiveViaTooltip(unitToken)
	if not unitToken or not self:DoesNameplateUnitExist(unitToken) then
		return false
	end

	local unitGuid = self:GetNameplateUnitGuid(unitToken)
	if not unitGuid or unitGuid == "" then
		return false
	end
	if issecretvalue and issecretvalue(unitGuid) then
		return false
	end

	local cachedValue = self:GetCachedQuestObjectiveResult(unitGuid)
	if cachedValue ~= nil then
		return cachedValue
	end

	if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink and Enum and Enum.TooltipDataLineType) then
		self:SetCachedQuestObjectiveResult(unitGuid, false)
		return false
	end

	local tooltipData = C_TooltipInfo.GetHyperlink("unit:" .. unitGuid)
	if not tooltipData or type(tooltipData.lines) ~= "table" then
		self:SetCachedQuestObjectiveResult(unitGuid, false)
		return false
	end

	local scanLines = {}
	for _, lineData in ipairs(tooltipData.lines) do
		local lineType = lineData and lineData.type
		if
			lineType == Enum.TooltipDataLineType.QuestObjective
			or lineType == Enum.TooltipDataLineType.QuestTitle
			or lineType == Enum.TooltipDataLineType.QuestPlayer
		then
			scanLines[#scanLines + 1] = lineData.leftText or ""
		end
	end

	if #scanLines == 0 then
		self:SetCachedQuestObjectiveResult(unitGuid, false)
		return false
	end

	if not next(self.nameplateQuestTitleCache) then
		self:RebuildNameplateQuestTitleCache()
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
	if directFlag ~= nil then
		return directFlag
	end

	local alternateFlag = GetBooleanFieldIfPresent(unitFrame, "isQuestObjective")
	if alternateFlag ~= nil then
		return alternateFlag
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

	-- Plater-style fallback: parse unit tooltip quest lines for unfinished objectives.
	if self:IsQuestObjectiveViaTooltip(unitToken) then
		return true
	end

	return self:IsNameplateUnitQuestBoss(unitToken)
end

function QuestTogether:ShouldShowQuestNameplateIcon(unitToken, unitFrame)
	if not self:GetOption("nameplateQuestIconEnabled") then
		return false
	end
	return self:IsQuestObjectiveNameplate(unitToken, unitFrame)
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
function QuestTogether:ShouldApplyQuestHealthTint(frame)
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

	return self:IsQuestObjectiveUnit(frame.unit, frame)
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

function QuestTogether:ApplyNameplateQuestIconStyle(icon, unitFrame)
	if not icon or not unitFrame then
		return
	end

	local style = self:GetNameplateQuestIconStyle()
	local width = self.NAMEPLATE_QUEST_ICON_WIDTH
	local height = self.NAMEPLATE_QUEST_ICON_HEIGHT

	icon:ClearAllPoints()

	if style == "left" then
		local barAnchor = GetIconBarAnchor(unitFrame)
		icon:SetPoint("RIGHT", barAnchor, "LEFT", -1, 0)
	elseif style == "right" then
		local barAnchor = GetIconBarAnchor(unitFrame)
		icon:SetPoint("LEFT", barAnchor, "RIGHT", 1, 0)
	elseif style == "prefix" then
		local nameText = unitFrame.name
		if nameText then
			-- Prefix places the icon directly against the unit name text.
			width = math.max(7, math.floor(width * 0.75 + 0.5))
			height = math.max(10, math.floor(height * 0.75 + 0.5))
			icon:SetPoint("RIGHT", nameText, "LEFT", 0, 0)
		elseif unitFrame.HealthBarsContainer then
			icon:SetPoint("BOTTOM", unitFrame.HealthBarsContainer, "TOP", 0, 11)
		else
			icon:SetPoint("TOP", unitFrame, "TOP", 0, 7)
		end
	else
		if unitFrame.HealthBarsContainer then
			icon:SetPoint("BOTTOM", unitFrame.HealthBarsContainer, "TOP", 0, 11)
		else
			icon:SetPoint("TOP", unitFrame, "TOP", 0, 7)
		end
	end

	icon:SetSize(width, height)
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

	local icon = unitFrame:CreateTexture(nil, "OVERLAY", nil, 2)
	QuestTogether.nameplateIconByUnitFrame[unitFrame] = icon

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
	QuestTogether:ApplyNameplateQuestIconStyle(icon, unitFrame)

	icon:Hide()
	return icon
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

local function CreatePrototypeBubbleFrame(parentFrame)
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
	ApplyQuestIconVisual(icon)

	return fallbackBubble
end

local function EnsurePrototypeBubble(hostFrame)
	local unitFrame = GetPrototypeBubbleUnitFrame(hostFrame)
	if not hostFrame or not unitFrame then
		return nil
	end

	local existingBubble = QuestTogether.nameplateBubbleByUnitFrame[unitFrame]
	if existingBubble then
		return existingBubble
	end

	local bubble = CreatePrototypeBubbleFrame(hostFrame)
	if not bubble or not bubble.String then
		return nil
	end

	bubble:SetFrameStrata(hostFrame:GetFrameStrata())
	bubble:SetFrameLevel(unitFrame:GetFrameLevel() + 20)
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
	ApplyQuestIconVisual(bubble.Icon)

	if bubble.Tail then
		bubble.Tail:ClearAllPoints()
		bubble.Tail:SetPoint("TOP", bubble, "BOTTOM", 0, 6)
	end

	local animationGroup = bubble:CreateAnimationGroup()
	local fadeIn = animationGroup:CreateAnimation("Alpha")
	fadeIn:SetOrder(1)
	fadeIn:SetDuration(PROTOTYPE_BUBBLE_FADE_IN_SECONDS)
	fadeIn:SetFromAlpha(0)
	fadeIn:SetToAlpha(1)

	local hold = animationGroup:CreateAnimation("Alpha")
	hold:SetOrder(2)
	hold:SetDuration(math.max(0, GetPrototypeBubbleLifetimeSeconds() - PROTOTYPE_BUBBLE_FADE_IN_SECONDS - PROTOTYPE_BUBBLE_FADE_OUT_SECONDS))
	hold:SetFromAlpha(1)
	hold:SetToAlpha(1)

	local fadeOut = animationGroup:CreateAnimation("Alpha")
	fadeOut:SetOrder(3)
	fadeOut:SetDuration(PROTOTYPE_BUBBLE_FADE_OUT_SECONDS)
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

function QuestTogether:HidePrototypeBubble(hostFrame)
	local unitFrame = GetPrototypeBubbleUnitFrame(hostFrame)
	if not hostFrame or not unitFrame then
		return
	end

	local bubble = self.nameplateBubbleByUnitFrame[unitFrame]
	if not bubble then
		return
	end

	if bubble.animationGroup and bubble.animationGroup:IsPlaying() then
		bubble.animationGroup:Stop()
	else
		bubble:SetAlpha(0)
		bubble:Hide()
	end
end

function QuestTogether:GetPrototypeBubbleHostFrameForUnit(unitToken)
	if unitToken == "player" then
		return GetPrototypeBubbleScreenHostFrame()
	end

	local namePlateFrameBase = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unitToken, false)
	if namePlateFrameBase and namePlateFrameBase.UnitFrame and namePlateFrameBase:IsShown() then
		return namePlateFrameBase
	end
	return nil
end

function QuestTogether:TryShowPrototypeBubbleOnUnitNameplate(unitToken, text)
	local hostFrame = self:GetPrototypeBubbleHostFrameForUnit(unitToken)
	if hostFrame then
		if not self:ShowPrototypeBubbleOnNameplate(hostFrame, text) then
			return false, "Unable to show a bubble on that nameplate."
		end
		local unitName = self.API.UnitName and self.API.UnitName(unitToken) or nil
		return true, unitName or unitToken
	end

	if unitToken ~= "player" then
		return false, "No visible nameplate found for that unit."
	end
	return false, "Your personal bubble anchor is unavailable."
end

function QuestTogether:ShowPrototypeBubbleOnNameplate(namePlateFrameBase, text)
	local unitFrame = GetPrototypeBubbleUnitFrame(namePlateFrameBase)
	if not namePlateFrameBase or not unitFrame then
		return false
	end

	local message = tostring(text or "")
	message = string.gsub(message, "^%s+", "")
	message = string.gsub(message, "%s+$", "")
	if message == "" then
		return false
	end

	local bubble = EnsurePrototypeBubble(namePlateFrameBase)
	if not bubble or not bubble.String then
		return false
	end

	local anchorFrame = unitFrame.HealthBarsContainer or unitFrame
	local visualConfig = GetPrototypeBubbleVisualConfig()
	local inset = visualConfig.inset or 16

	if bubble.animationGroup and bubble.animationGroup:IsPlaying() then
		bubble.animationGroup:Stop()
	end

	if bubble.holdAnimation then
		local holdSeconds = math.max(
			0,
			GetPrototypeBubbleLifetimeSeconds() - PROTOTYPE_BUBBLE_FADE_IN_SECONDS - PROTOTYPE_BUBBLE_FADE_OUT_SECONDS
		)
		bubble.holdAnimation:SetDuration(holdSeconds)
	end

	local fontPath, _, fontFlags = bubble.String:GetFont()
	if fontPath and bubble.String.SetFont then
		bubble.String:SetFont(fontPath, visualConfig.fontSize, fontFlags)
	end

	bubble.String:SetWidth(visualConfig.maxTextWidth)
	bubble.String:SetText(message)

	local unboundedWidth = visualConfig.minTextWidth
	if bubble.String.GetUnboundedStringWidth then
		unboundedWidth = bubble.String:GetUnboundedStringWidth() or visualConfig.minTextWidth
	end
	local targetTextWidth = math.min(
		visualConfig.maxTextWidth,
		math.max(visualConfig.minTextWidth, unboundedWidth)
	)
	bubble.String:SetWidth(targetTextWidth)

	local textHeight = bubble.String:GetStringHeight() or 0
	local contentHeight = math.max(visualConfig.iconSize, textHeight)
	local contentWidth = visualConfig.iconSize + visualConfig.iconGap + targetTextWidth
	local bubbleWidth = contentWidth + (inset * 2)
	local bubbleHeight = contentHeight + (inset * 2)

	bubble:ClearAllPoints()
	bubble:SetPoint("BOTTOM", anchorFrame, "TOP", 0, PROTOTYPE_BUBBLE_Y_OFFSET)
	bubble:SetSize(bubbleWidth, bubbleHeight)

	if bubble.Icon then
		bubble.Icon:ClearAllPoints()
		bubble.Icon:SetSize(visualConfig.iconSize, visualConfig.iconSize)
		bubble.Icon:SetPoint("CENTER", bubble, "CENTER", -((visualConfig.iconGap + targetTextWidth) / 2), 0)
		bubble.Icon:Show()
	end

	bubble.String:ClearAllPoints()
	bubble.String:SetWidth(targetTextWidth)
	bubble.String:SetPoint("CENTER", bubble, "CENTER", ((visualConfig.iconSize + visualConfig.iconGap) / 2), 0)

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

function QuestTogether:ShowPrototypeBubbleOnUnitNameplate(unitToken, text)
	if type(unitToken) ~= "string" or unitToken == "" then
		return false, "No unit token was provided."
	end

	if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then
		if unitToken ~= "player" then
			return false, "Nameplates are unavailable."
		end
	end

	return self:TryShowPrototypeBubbleOnUnitNameplate(unitToken, text)
end

function QuestTogether:ShowPrototypeBubbleOnRandomVisiblePlayer(text)
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
	if not self:ShowPrototypeBubbleOnNameplate(namePlateFrameBase, text) then
		return false, "Unable to show a bubble on the selected nameplate."
	end

	local unitToken = (namePlateFrameBase.GetUnit and namePlateFrameBase:GetUnit()) or nil
	local unitName = unitToken and self.API.UnitName(unitToken) or nil
	return true, unitName or "Unknown"
end

function QuestTogether:RememberNameplateBaseHealthColor(unitFrame)
	if not unitFrame or not unitFrame.healthBar then
		return
	end

	local unitGuid = nil
	if unitFrame.unit then
		local resolvedGuid = self:GetNameplateUnitGuid(unitFrame.unit)
		if type(resolvedGuid) == "string" and resolvedGuid ~= "" then
			unitGuid = resolvedGuid
		end
	end

	local cachedBase = self.nameplateBaseHealthColorByUnitFrame[unitFrame]
	if cachedBase then
		-- If we cannot currently resolve identity, preserve the first captured baseline.
		if not unitGuid then
			return
		end
		if cachedBase.unitGuid == unitGuid then
			return
		end
	end

	local red, green, blue = unitFrame.healthBar:GetStatusBarColor()
	if type(red) ~= "number" or type(green) ~= "number" or type(blue) ~= "number" then
		return
	end

	self.nameplateBaseHealthColorByUnitFrame[unitFrame] = {
		r = red,
		g = green,
		b = blue,
		unitGuid = unitGuid,
	}
end

function QuestTogether:ApplyQuestTintToNameplate(unitFrame)
	if not unitFrame or not unitFrame.healthBar then
		return
	end

	self:RememberNameplateBaseHealthColor(unitFrame)

	local color = self:GetNameplateQuestHealthColor()
	unitFrame.healthBar:SetStatusBarColor(color.r, color.g, color.b)
end

function QuestTogether:RestoreNameplateHealthColor(unitFrame)
	if not unitFrame or not unitFrame.healthBar then
		return
	end

	local cachedBase = self.nameplateBaseHealthColorByUnitFrame[unitFrame]
	if not cachedBase then
		return
	end

	if cachedBase.unitGuid then
		local currentGuid = nil
		if unitFrame.unit then
			local resolvedGuid = self:GetNameplateUnitGuid(unitFrame.unit)
			if type(resolvedGuid) == "string" and resolvedGuid ~= "" then
				currentGuid = resolvedGuid
			end
		end
		if cachedBase.unitGuid ~= currentGuid then
			-- Frame got reused for a different unit; never restore stale color onto it.
			self.nameplateBaseHealthColorByUnitFrame[unitFrame] = nil
			return
		end
	end

	if type(cachedBase.r) ~= "number" or type(cachedBase.g) ~= "number" or type(cachedBase.b) ~= "number" then
		-- Defensive guard for malformed cache entries.
		self.nameplateBaseHealthColorByUnitFrame[unitFrame] = nil
		return
	end

	unitFrame.healthBar:SetStatusBarColor(cachedBase.r, cachedBase.g, cachedBase.b)
	self.nameplateBaseHealthColorByUnitFrame[unitFrame] = nil
end

function QuestTogether:RefreshNameplateHealthTint(namePlateFrameBase, isQuestObjective)
	if not namePlateFrameBase or not namePlateFrameBase.UnitFrame then
		return
	end

	local unitFrame = namePlateFrameBase.UnitFrame
	local shouldTint = self.isEnabled and self:GetOption("nameplateQuestHealthColorEnabled") and isQuestObjective
	if shouldTint then
		self:ApplyQuestTintToNameplate(unitFrame)
	else
		self:RestoreNameplateHealthColor(unitFrame)
	end
end

function QuestTogether:RefreshNameplateIcon(namePlateFrameBase)
	if not namePlateFrameBase or not namePlateFrameBase.UnitFrame then
		return
	end

	local unitToken = (namePlateFrameBase.GetUnit and namePlateFrameBase:GetUnit()) or nil
	local unitFrame = namePlateFrameBase.UnitFrame
	local icon = EnsureQuestIcon(unitFrame)

	if not icon then
		return
	end

	local isQuestObjective = self:IsQuestObjectiveNameplate(unitToken, unitFrame)
	local shouldShow = self:GetOption("nameplateQuestIconEnabled") and isQuestObjective
	if unitToken then
		self.nameplateQuestStateByUnitToken[unitToken] = isQuestObjective and true or false
	end
	self:RefreshNameplateHealthTint(namePlateFrameBase, isQuestObjective)

	if shouldShow then
		icon:Show()
	else
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
	self:HidePrototypeBubble(namePlateFrameBase)
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
				fullUnitName = tostring(unitName) .. "-" .. tostring((unitRealm or self.API.GetRealmName() or ""):gsub("%s+", ""))
			else
				fullUnitName = self:NormalizeMemberName(self.API.UnitName(unitToken))
			end
			if fullUnitName and self:NormalizeMemberName(fullUnitName) == normalizedSenderName then
				matchedFrame = frame
			end
		end
	end)

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
		fullUnitName = tostring(unitName) .. "-" .. tostring((unitRealm or self.API.GetRealmName() or ""):gsub("%s+", ""))
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
			return unitToken
		end
	end

	return nil
end

function QuestTogether:RefreshNameplateAugmentation()
	if self:IsNameplateAugmentationBlockedInCurrentContext() then
		wipe(self.nameplateQuestStateByUnitToken)
		self:ForEachVisibleNamePlate(function(frame)
			self:HideNameplateIcon(frame)
		end)
		return
	end

	self:ForEachVisibleNamePlate(function(frame)
		self:RefreshNameplateIcon(frame)
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
		local blockedFrame = C_NamePlate
			and C_NamePlate.GetNamePlateForUnit
			and C_NamePlate.GetNamePlateForUnit(unitToken, false)
		if blockedFrame then
			self:HideNameplateIcon(blockedFrame)
		end
		return
	end

	local unitGuid = self:GetNameplateUnitGuid(unitToken)
	if unitGuid and self.nameplateQuestObjectiveCache[unitGuid] then
		self.nameplateQuestObjectiveCache[unitGuid] = nil
	end
	self.nameplateQuestStateByUnitToken[unitToken] = nil

	local namePlateFrameBase = C_NamePlate.GetNamePlateForUnit(unitToken, false)
	if namePlateFrameBase then
		self:RefreshNameplateIcon(namePlateFrameBase)
	end
end

function QuestTogether:OnNameplateRemoved(unitToken)
	if not self:IsNameplateUnitToken(unitToken) then
		return
	end

	local unitGuid = self:GetNameplateUnitGuid(unitToken)
	if unitGuid and self.nameplateQuestObjectiveCache[unitGuid] then
		self.nameplateQuestObjectiveCache[unitGuid] = nil
	end
	self.nameplateQuestStateByUnitToken[unitToken] = nil

	local namePlateFrameBase = C_NamePlate.GetNamePlateForUnit(unitToken, false)
	if namePlateFrameBase then
		self:HideNameplateIcon(namePlateFrameBase)
	end
end

function QuestTogether:TryInstallNameplateHooks()
	if self.nameplateHooksInstalled then
		return
	end

	if type(hooksecurefunc) ~= "function" then
		return
	end

	if
		not self.nameplateDriverHookInstalled
		and type(NamePlateDriverMixin) == "table"
		and type(NamePlateDriverMixin.OnNamePlateAdded) == "function"
	then
		hooksecurefunc(NamePlateDriverMixin, "OnNamePlateAdded", function(_, unitToken)
			QuestTogether:OnNameplateAdded(unitToken)
		end)
		hooksecurefunc(NamePlateDriverMixin, "OnNamePlateRemoved", function(_, unitToken)
			QuestTogether:OnNameplateRemoved(unitToken)
		end)
		self.nameplateDriverHookInstalled = true
	end

	if not self.nameplateHealthColorHookInstalled and type(CompactUnitFrame_UpdateHealthColor) == "function" then
		hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(frame)
			if not frame or type(frame.unit) ~= "string" then
				return
			end
			if not QuestTogether:IsNameplateUnitToken(frame.unit) then
				return
			end

			local isQuestObjective = QuestTogether.nameplateQuestStateByUnitToken[frame.unit]
			if isQuestObjective == nil then
				isQuestObjective = QuestTogether:IsQuestObjectiveNameplate(frame.unit, frame)
				QuestTogether.nameplateQuestStateByUnitToken[frame.unit] = isQuestObjective and true or false
			end

			local shouldTint = QuestTogether.isEnabled
				and not QuestTogether:IsNameplateAugmentationBlockedInCurrentContext()
				and QuestTogether:GetOption("nameplateQuestHealthColorEnabled")
				and isQuestObjective
			if shouldTint then
				QuestTogether:ApplyQuestTintToNameplate(frame)
			else
				QuestTogether:RestoreNameplateHealthColor(frame)
			end
		end)
		self.nameplateHealthColorHookInstalled = true
	end

	self.nameplateHooksInstalled = self.nameplateDriverHookInstalled and self.nameplateHealthColorHookInstalled
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
		local ok = pcall(addon.nameplateEventFrame.RegisterEvent, addon.nameplateEventFrame, eventName)
		if ok then
			addon.nameplateRegisteredEvents[eventName] = true
		else
			addon.nameplateRegisteredEvents[eventName] = nil
		end
	end

	self:TryInstallNameplateHooks()
	self:RebuildNameplateQuestTitleCache()
	self:ClearNameplateQuestObjectiveCache()
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
	RegisterNameplateEvent(self, "PLAYER_ENTERING_WORLD")
	self:RefreshNameplateAugmentation()
end

function QuestTogether:DisableNameplateAugmentation()
	if not self.nameplateEventFrame then
		return
	end

	for eventName in pairs(self.nameplateRegisteredEvents or {}) do
		pcall(self.nameplateEventFrame.UnregisterEvent, self.nameplateEventFrame, eventName)
	end
	if self.nameplateRegisteredEvents then
		wipe(self.nameplateRegisteredEvents)
	end

	-- Hide our icon overlays and clear cached quest objective state.
	wipe(self.nameplateQuestStateByUnitToken)
	self:ForEachVisibleNamePlate(function(frame)
		self:HideNameplateIcon(frame)
	end)
	wipe(self.nameplateBaseHealthColorByUnitFrame)
end
