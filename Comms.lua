--- Send/Receive Methods ---

function QuestTogether:Broadcast(cmd, ...)
	self:Debug("Broadcast(" .. cmd .. ", " .. ... .. ")")
	local serializedData = self:Serialize(...)
	-- if UnitInParty("player") then
	-- 	self:SendCommMessage("QuestTogether", cmd .. " " .. serializedData, "PARTY")
	-- end
	self:SendCommMessage("QuestTogether", cmd .. " " .. serializedData, "WHISPER", "Stamets")
end

function QuestTogether:OnCommReceived(prefix, message, channel, sender)
	-- Ignore messages from other addons and messages from the player.
	-- if prefix ~= "QuestTogether" or sender == UnitName("player") then
	-- 	return
	-- end
	self:Debug("OnCommReceived(" .. prefix .. ", " .. message .. ", " .. channel .. ", " .. sender .. ")")
	local cmd, serializedData = self:GetArgs(message, 2)
	self:Debug("cmd: " .. cmd .. ", serializedData: " .. serializedData)
	self[cmd](self, serializedData)
end

--- Comm Event Handlers ---

function QuestTogether:CMD(serializedData)
	local success, text = QuestTogether:Deserialize(serializedData)
	self:Debug("CMD(" .. text .. ")")
	DEFAULT_CHAT_FRAME.editBox:SetText(text)
	ChatEdit_SendText(DEFAULT_CHAT_FRAME.editBox, 0)
end

function QuestTogether:EMOTE(serializedData)
	local faction, _ = UnitFactionGroup("player")
	local success, randomEmote = self:Deserialize(serializedData)

	if IsMounted() and randomEmote == "mountspecial" then
		DoEmote("mountspecial")
	elseif randomEmote == "forthealliance" or randomEmote == "forthehorde" then
		if faction == "Alliance" then
			DoEmote("forthealliance", sender)
		elseif faction == "Horde" then
			DoEmote("forthehorde", sender)
		end
	else
		-- If the player is not mounted or the emote is not for their faction, roll for a different emote.
		if randomEmote == "mountspecial" or randomEmote == "forthealliance" or randomEmote == "forthehorde" then
			repeat
				randomEmote = self.completionEmotes[math.random(#self.completionEmotes)]
			until randomEmote ~= "mountspecial"
				and randomEmote ~= "forthealliance"
				and randomEmote ~= "forthehorde"
		end
		DoEmote(randomEmote, sender)
	end
end

function QuestTogether:UPDATE_QUEST_TRACKER(serializedData)
	local success, data = self:Deserialize(serializedData)
	self.db.global.questTrackers[sender] = data
end
