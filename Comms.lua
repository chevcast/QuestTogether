--- Send/Receive Methods ---

function QuestTogether:Broadcast(cmd, ...)
	local serializedData = self:Serialize(...)
	-- self:Debug("Broadcast(" .. cmd .. ", " .. serializedData .. ")")
	if UnitInParty("player") then
		self:SendCommMessage("QuestTogether", cmd .. " " .. serializedData, "PARTY")
	end
	-- self:SendCommMessage("QuestTogether", cmd .. " " .. serializedData, "WHISPER", UnitName("player"))
end

function QuestTogether:OnCommReceived(prefix, message, channel, sender)
	-- Ignore messages from other addons and messages from the player.
	if prefix ~= "QuestTogether" or sender == UnitName("player") then
		return
	end
	self:Debug("OnCommReceived(" .. prefix .. ", " .. message .. ", " .. channel .. ", " .. sender .. ")")
	local cmd, serializedData = self:GetArgs(message, 2)
	self[cmd](self, serializedData, sender)
end

--- Comm Event Handlers ---

function QuestTogether:CMD(serializedData, sender)
	local success, text = QuestTogether:Deserialize(serializedData)
	self:Debug("CMD(" .. text .. ")")
	DEFAULT_CHAT_FRAME.editBox:SetText(text)
	ChatEdit_SendText(DEFAULT_CHAT_FRAME.editBox, 0)
	DEFAULT_CHAT_FRAME.editBox:SetText("")
end

function QuestTogether:EMOTE(serializedData, sender)
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

function QuestTogether:UPDATE_QUEST_TRACKER(serializedData, sender)
	local success, data = self:Deserialize(serializedData)
	self.db.global.questTrackers[sender] = data
end

function QuestTogether:SUPER_TRACK(serializedData, sender)
	self:Debug("Not Implemented")
	-- self:Debug("SUPER_TRACK(" .. serializedData .. ", " .. sender .. ")")
	-- local success, questId, questTitle = self:Deserialize(serializedData)
	-- local questTracker = self.db.global.questTrackers[UnitName("player")]
	-- if questTracker[questId] then
	-- 	C_SuperTrack.SetSuperTrackedQuestID(questId)
	-- 	self:Announce(sender .. ' changed tracked quest to "' .. questTitle .. '"')
	-- else
	-- 	self:Announce("Can't track " .. sender .. "'s quest \"" .. questTitle .. "\" because I don't have it.")
	-- end
end
