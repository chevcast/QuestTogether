QuestTogether.defaultOptions = {
	profile = {
		debugMode = false,
		showNearby = false,
		primaryChannel = "party",
		fallbackChannel = "console",
		announceAccepted = true,
		announceCompleted = true,
		announceRemoved = true,
		announceProgress = true,
	},
	char = {
		questTracker = {},
		onQuestLogUpdate = {},
		questsCompleted = {},
	},
}

QuestTogether.channels = {
	none = "|cff777777None|r",
	console = "|cffffff00Console|r",
	guild = "|cff40ff40Guild|r",
	-- instance = "|cffee7700Instance|r",
	party = "|cffaaaaffParty|r",
	raid = "|cffff7f00Raid|r",
	-- say = "|cffffffffSay|r",
	-- yell = "|cffff4040Yell|r",
}

QuestTogether.options = {
	type = "group",
	childGroups = "tab",
	name = "QuestTogether",
	handler = QuestTogether,
	args = {
		whatToAnnounce = {
			type = "group",
			name = "What To Announce",
			order = 1,
			inline = true,
			args = {
				announceAccepted = {
					type = "toggle",
					order = 1,
					width = "full",
					name = "Announce Quest Acceptance",
					desc = "Announce when you accept a quest.",
					get = "GetValue",
					set = "SetValue",
				},
				announceCompleted = {
					type = "toggle",
					order = 2,
					width = "full",
					name = "Announce Quest Completion",
					desc = "Announce when you complete a quest.",
					get = "GetValue",
					set = "SetValue",
				},
				announceRemoved = {
					type = "toggle",
					order = 3,
					width = "full",
					name = "Announce Quest Removal",
					desc = "Announce when you remove a quest.",
					get = "GetValue",
					set = "SetValue",
				},
				announceProgress = {
					type = "toggle",
					order = 4,
					width = "full",
					name = "Announce Quest Progress",
					desc = "Announce quest progress updates.",
					get = "GetValue",
					set = "SetValue",
				},
			},
		},
		whereToAnnounce = {
			type = "group",
			name = "Where To Announce",
			order = 2,
			inline = true,
			args = {
				primaryChannel = {
					type = "select",
					order = 1,
					name = "Primary Chat Channel",
					desc = "Send quest progress messages to this channel.",
					values = QuestTogether.channels,
					get = "GetValue",
					set = "SetValue",
				},
				fallbackChannel = {
					type = "select",
					order = 2,
					name = "Fallback Chat Channel",
					desc = "Send quest progress messages to this channel if the primary chat channel is unavailable.",
					hidden = function()
						local primaryChannel = QuestTogether.db.profile.primaryChannel
						local allowedFallbacks = {
							guild = true,
							instance = true,
							party = true,
							raid = true,
						}
						if allowedFallbacks[primaryChannel] then
							return false
						end
						return true
					end,
					values = function()
						local fallbackChannels = {}
						local primaryChannel = QuestTogether.db.profile.primaryChannel
						for key, value in pairs(QuestTogether.channels) do
							if key ~= primaryChannel then
								fallbackChannels[key] = value
							end
						end

						return fallbackChannels
					end,
					get = "GetValue",
					set = "SetValue",
				},
			},
		},
	},
}

function QuestTogether:GetValue(info)
	return self.db.profile[info[#info]]
end

function QuestTogether:SetValue(info, value)
	self.db.profile[info[#info]] = value
end
