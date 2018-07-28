QuestTogether = {
  questTracker = {},
  DEBUG = {
    messages = false,
    questLogUpdate = false,
    events = false
  },
  showDebugInfo = false
};

local questTogetherFrame = CreateFrame("FRAME", "QuestTogetherFrame");
local characterName = string.lower(UnitName("player"));
local faction = string.lower(UnitFactionGroup("player"));

C_ChatInfo.RegisterAddonMessagePrefix("QuestTogether");

questTogetherFrame:RegisterEvent("QUEST_ACCEPTED");
questTogetherFrame:RegisterEvent("QUEST_ACCEPT_CONFIRM");
questTogetherFrame:RegisterEvent("QUEST_AUTOCOMPLETE");
questTogetherFrame:RegisterEvent("QUEST_COMPLETE");
questTogetherFrame:RegisterEvent("QUEST_POI_UPDATE");
questTogetherFrame:RegisterEvent("QUEST_DETAIL");
questTogetherFrame:RegisterEvent("QUEST_FINISHED");
questTogetherFrame:RegisterEvent("QUEST_GREETING");
questTogetherFrame:RegisterEvent("QUEST_ITEM_UPDATE");
questTogetherFrame:RegisterEvent("QUEST_LOG_UPDATE");
questTogetherFrame:RegisterEvent("QUEST_PROGRESS");
questTogetherFrame:RegisterEvent("QUEST_REMOVED");
questTogetherFrame:RegisterEvent("QUEST_TURNED_IN");
questTogetherFrame:RegisterEvent("QUEST_WATCH_UPDATE");
questTogetherFrame:RegisterEvent("QUEST_WATCH_LIST_CHANGED");
questTogetherFrame:RegisterEvent("QUEST_LOG_CRITERIA_UPDATE");
questTogetherFrame:RegisterEvent("UNIT_QUEST_LOG_CHANGED");
questTogetherFrame:RegisterEvent("PARTY_MEMBER_ENABLE");
questTogetherFrame:RegisterEvent("PARTY_MEMBER_DISABLE");
questTogetherFrame:RegisterEvent("GROUP_ROSTER_UPDATE");
questTogetherFrame:RegisterEvent("AJ_QUEST_LOG_OPEN");
questTogetherFrame:RegisterEvent("QUEST_TURNED_IN");
questTogetherFrame:RegisterEvent("ADVENTURE_MAP_QUEST_UPDATE");
questTogetherFrame:RegisterEvent("SUPER_TRACKED_QUEST_CHANGED");
questTogetherFrame:RegisterEvent("QUESTLINE_UPDATE");
questTogetherFrame:RegisterEvent("SUPER_TRACKED_QUEST_CHANGED");
questTogetherFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
questTogetherFrame:RegisterEvent("CHAT_MSG_ADDON");

local onQuestLogUpdate = {};
local questsTurnedIn = {};

local sendDebugInfo = function(msg)
    C_ChatInfo.SendAddonMessage("QuestTogether", msg, "PARTY");
end;

local reportInfo = function(msg)
  if (UnitInParty("player")) then
    SendChatMessage(msg, "PARTY");
  elseif (QuestTogether.DEBUG.messages) then
    SendChatMessage(msg, "SAY");
  end
  if (QuestTogether.DEBUG.messages) then
    sendDebugInfo("[messages]: "..msg);
  end
end;

local watchQuest = function(questId)
  local questLogIndex = GetQuestLogIndexByID(questId);
  local questTitle = GetQuestLogTitle(questLogIndex);
  local numObjectives = GetNumQuestLeaderBoards(questLogIndex);
  QuestTogether.questTracker[questId] = {
    title = questTitle,
    objectives = {}
  };
  for objectiveIndex=1, numObjectives do
    local objectiveText, type = GetQuestObjectiveInfo(questId, objectiveIndex, false);
    if (type == "progressbar") then
      local progress = GetQuestProgressBarPercent(questId);
      objectiveText = progress.."% "..objectiveText;
    end
    QuestTogether.questTracker[questId].objectives[objectiveIndex] = objectiveText;
  end
end;

local EventHandlers = {

  CHAT_MSG_ADDON = function (prefix, message, type, sender)
    if (prefix == "QuestTogether" and QuestTogether.showDebugInfo) then
      sender = string.match(sender, "^([a-zA-Z]+)-");
      print("<"..sender..">:"..message);
    end
  end,

  -- Upon entering world scan quest log for quests to track.
  PLAYER_ENTERING_WORLD = function ()
    QuestTogether.questTracker = {};
    local numQuestLogEntries = GetNumQuestLogEntries();
    local questsTracked = 0;
    for questLogIndex=1, numQuestLogEntries do
      local questTitle, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequencey, questId = GetQuestLogTitle(questLogIndex);
      if (isHeader == false) then
        watchQuest(questId);
        questsTracked = questsTracked + 1;
      end
    end
    print(questsTracked.." quests are being monitored by QuestTogether.");
  end,

  -- Track newly accepted quests.
  QUEST_ACCEPTED = function (questLogIndex, questId)
    table.insert(onQuestLogUpdate, function ()
      if (QuestTogether.questTracker[questId] == nil) then
        local questLogIndex = GetQuestLogIndexByID(questId);
        local questTitle = GetQuestLogTitle(questLogIndex);
        reportInfo("Picked Up: "..questTitle);
        watchQuest(questId);
      end
    end);
  end,

  -- Track if quest was turned in rather than abandoned.
  QUEST_TURNED_IN = function (questId)
    questsTurnedIn[questId] = true;
  end,

  -- Unwatch quest and report completed or removed.
  QUEST_REMOVED = function (questId)
    table.insert(onQuestLogUpdate, function ()
      C_Timer.After(0.5, function()
        if (QuestTogether.questTracker[questId]) then
          local questTitle = QuestTogether.questTracker[questId].title;
          if (questsTurnedIn[questId]) then
            reportInfo("Completed: "..questTitle);
            questsTurnedIn[questId] = nil;
          else
            reportInfo("Removed: "..questTitle);
          end
          QuestTogether.questTracker[questId] = nil;
        end
      end);
    end);
  end,

  -- Look for objective updates to tracked quests.
  UNIT_QUEST_LOG_CHANGED = function (unit)
    if (unit == "player") then
      table.insert(onQuestLogUpdate, function()
        for questId, quest in pairs(QuestTogether.questTracker) do
          local questLogIndex = GetQuestLogIndexByID(questId);
          local numObjectives = GetNumQuestLeaderBoards(questLogIndex);
          for objectiveIndex=1, numObjectives do
            local objectiveText, type, complete, currentValue, maxValue = GetQuestObjectiveInfo(questId, objectiveIndex, false);
            if (type=="progressbar") then
              local progress = GetQuestProgressBarPercent(questId);
              objectiveText = progress.."% "..objectiveText;
              currentValue = progress;
            end
            if (QuestTogether.questTracker[questId].objectives[objectiveIndex] ~= objectiveText) then
              if (currentValue > 0) then
                reportInfo(objectiveText);
              end
              QuestTogether.questTracker[questId].objectives[objectiveIndex] = objectiveText;
            end
          end
        end
      end);
    end
  end,

  -- Run all scheduled tasks after QUEST_LOG_UPDATE.
  QUEST_LOG_UPDATE = function()
    local hasUpdates = false;
    if (QuestTogether.DEBUG.questLogUpdate and #onQuestLogUpdate > 0) then
      sendDebugInfo("[questLogUpdate]: "..#onQuestLogUpdate.." scheduled tasks detected.");
      hasUpdates = true;
    end
    local numTasks = #onQuestLogUpdate;
    for index = 1, numTasks, 1 do
      onQuestLogUpdate[index]();
      table.remove(onQuestLogUpdate, index);
    end
    if (QuestTogether.DEBUG.questLogUpdate and hasUpdates) then
      if (#onQuestLogUpdate == 0) then
        sendDebugInfo("[questLogUpdate]: All tasks completed.");
      else
        sendDebugInfo("[questLogUpdate]: Somehow tasks are not zero...");
      end
      hasUpdates = false;
    end
  end

};

local function eventHandler(self, event, ...)
  if (EventHandlers[event] ~= nil) then
    EventHandlers[event](...);
  end
  if (QuestTogether.DEBUG.events and (event ~= "QUEST_LOG_UPDATE" or QuestTogether.DEBUG.questLogUpdate)) then
    sendDebugInfo("[events]: -------------------------------");
    sendDebugInfo("[events]: Event fired: " .. event);
		-- UIParentLoadAddOn("Blizzard_DebugTools");
    -- DevTools_Dump({ n = select("#", ...); ... });
  end
end
questTogetherFrame:SetScript("OnEvent", eventHandler);