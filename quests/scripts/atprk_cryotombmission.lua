require "/scripts/util.lua"
require "/scripts/vec2.lua"
require "/quests/scripts/portraits.lua"
require "/quests/scripts/questutil.lua"

function init()
  setPortraits()

  storage.complete = storage.complete or false

  self.compassUpdate = config.getParameter("compassUpdate", 0.5)

  self.relicseekerUid = config.getParameter("relicseekerUid")
  self.goalUid = config.getParameter("goalUid")

  storage.stage = storage.stage or 1
  self.stages = {
    findTomb,
    turnIn
  }

  self.state = FSM:new()
  self.state:set(self.stages[storage.stage])
end

function questInteract(entityId)
  if self.onInteract then
    return self.onInteract(entityId)
  end
end

function questStart()
  player.enableMission(config.getParameter("associatedMission"))
  player.playCinematic(config.getParameter("missionUnlockedCinema"))
end

function update(dt)
  self.state:update(dt)

  if storage.complete then
    quest.setCanTurnIn(true)
  end
end

function questComplete()
  player.playCinematic(config.getParameter("shipUpgradeCinema"))

  setPortraits()
  questutil.questCompleteActions()
end


function findTomb()
  quest.setParameter("goal", {type = "entity", uniqueId = self.goalUid})
  quest.setIndicators({"goal"})

  quest.setObjectiveList({{config.getParameter("descriptions.findTomb"), false}})

  self.onInteract = function(entityId)
    if world.entityUniqueId(entityId) == self.goalUid then
      quest.setIndicators({})
      storage.stage = 2
      player.playCinematic(config.getParameter("cryotombFoundCinema"))

      self.onInteract = nil
      return false
    end
  end

  util.wait(3.0)
  player.radioMessage(config.getParameter("missionRadioMessage"))

  local findGoal = util.uniqueEntityTracker(self.goalUid, self.compassUpdate)
  while storage.stage == 1 do
    questutil.pointCompassAt(findGoal())
    coroutine.yield()
  end

  self.state:set(self.stages[storage.stage])
end

function turnIn()
  quest.setIndicators({})
  quest.setCompassDirection(nil)
  quest.setObjectiveList({{config.getParameter("descriptions.turnIn"), false}})
  quest.setCanTurnIn(true)

  local findRelicseeker = util.uniqueEntityTracker(self.relicseekerUid, self.compassUpdate)
  while storage.stage == 2 do
    questutil.pointCompassAt(findRelicseeker())
    coroutine.yield()
  end
end
