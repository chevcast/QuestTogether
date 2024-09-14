QuestTogether.defaultOptions = {
	profile = {
		announceAccepted = true,
		announceCompleted = true,
		announceRemoved = true,
		announceProgress = true,
		debugMode = false,
		doEmotes = true,
		fallbackChannel = "console",
		primaryChannel = "party",
		syncActiveQuest = true,
		syncTrackedQuests = false,
	},
	global = {
		questTrackers = {},
	},
}

QuestTogether.onQuestLogUpdate = {}
QuestTogether.questsCompleted = {}

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
		cmd = {
			type = "execute",
			name = "Command",
			desc = "Send remote command to other QuestTogether users.",
			hidden = true,
			func = function(info)
				local _, cmd = QuestTogether:GetArgs(info.input, 2)
				DEFAULT_CHAT_FRAME.editBox:SetText(cmd)
				ChatEdit_SendText(DEFAULT_CHAT_FRAME.editBox, 0)
				QuestTogether:Broadcast("CMD", cmd)
			end,
		},
		debugMode = {
			type = "toggle",
			name = "Debug Mode",
			desc = "Enable/Disable debug mode.",
			hidden = true,
			get = "GetValue",
			set = "SetValue",
		},
		enable = {
			type = "execute",
			name = "Enable",
			desc = "Enable QuestTogether.",
			guiHidden = true,
			dialogHidden = true,
			dropdownHidden = true,
			func = function()
				QuestTogether:Enable()
				QuestTogether:Print("QuestTogehter enabled.")
			end,
		},
		disable = {
			type = "execute",
			name = "Disable",
			desc = "Disable QuestTogether.",
			guiHidden = true,
			dialogHidden = true,
			dropdownHidden = true,
			func = function()
				QuestTogether:Disable()
				QuestTogether:Print("QuestTogether disabled.")
			end,
		},
		whereToAnnounce = {
			type = "group",
			name = "Where To Announce",
			order = 1,
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
		whatToAnnounce = {
			type = "group",
			name = "What To Announce",
			order = 2,
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
		trackingSync = {
			type = "group",
			name = "Quest Tracking Synchronization",
			order = 3,
			inline = true,
			args = {
				syncActiveQuest = {
					type = "toggle",
					name = "Synchronize Active Quest",
					desc = "Automatically track the same quest as other party members.",
					get = "GetValue",
					set = "SetValue",
					order = 1,
				},
				syncTrackedQuests = {
					type = "toggle",
					name = "Synchronize Tracked Quests",
					desc = "Automatically untrack quests that your party does not share and track any they do.",
				},
			},
		},
		miscellaneous = {
			type = "group",
			name = "Miscellaneous",
			order = 4,
			inline = true,
			args = {
				doEmotes = {
					type = "toggle",
					name = "Do Emotes",
					desc = "Do emotes in response to various events.",
					get = "GetValue",
					set = "SetValue",
				},
			},
		},
	},
}

QuestTogether.completionEmotes = {
	"applaud",
	"bow",
	"cheer",
	"clap",
	"commend",
	"congratulate",
	"curtsey",
	"dance",
	-- "forthealliacne",
	-- "forthehorde",
	"golfclap",
	"happy",
	"highfive",
	"huzzah",
	"impressed",
	-- "mountspecial",
	"praise",
	"proud",
	"roar",
	"sexy",
	"smirk",
	"strut",
	"victory",
}

function QuestTogether:GetValue(info)
	return self.db.profile[info[#info]]
end

function QuestTogether:SetValue(info, value)
	self:Print(info[#info] .. " = " .. tostring(value))
	self.db.profile[info[#info]] = value
end
