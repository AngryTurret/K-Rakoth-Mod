-- param monsterType
-- param count
-- param distance
-- output projectors
function spawnProjectors(args, board)
  local projectors = {}
  local stepAngle = (math.pi * 2) / args.count
  for i = 1, args.count do
    local offset = vec2.rotate({1,0}, stepAngle * i)
    local projectorId = world.spawnMonster("atprk_computerbossprojector", vec2.add(mcontroller.position(), offset), { level = monster.level()})
    table.insert(projectors, projectorId)
  end

  setLeadProjector(projectors)

  return true, {projectors = projectors}
end

-- param projectorList
-- param count
-- output healthPercentage
function projectorHealthPercentage(args, board)
  local sum = 0
  for _,projectorId in ipairs(args.projectorList) do
    local health = world.entityHealth(projectorId)
    sum = sum + (health[1] / health[2])
  end

  return true, {healthPercentage = sum / args.count}
end

-- param projectorList
-- param speed
function updateProjectors(args, board)
  if args.projectorList == nil then return false end

  setLeadProjector(args.projectorList)
  return true
end

-- param projectorList
function setProjectorSpeeds(args, board)
  if args.projectorList == nil then return false end

  for _,projectorId in pairs(args.projectorList) do
    world.sendEntityMessage(projectorId, "setSpeed", args.speed)
  end
  return true
end

-- param projector
-- param power
function fireProjectorMissiles(args, board)
  if args.power == nil or args.target == nil then return false end

  local power = args.power * root.evalFunction("monsterLevelPowerMultiplier", monster.level())
  for _,projectorId in pairs(args.projectorList) do
    world.sendEntityMessage(projectorId, "fireMissiles", args.target, power)
  end
  return true
end

-- param launchGroups
-- param power
function launchEnergyFists(args, board)
  local group = math.random(1, args.launchGroups)
  local power = args.power * root.evalFunction("monsterLevelPowerMultiplier", monster.level())

  local launchers = world.entityQuery(mcontroller.position(), 50, { includedTypes = { "object" } })
  launchers = util.filter(launchers, function(v) return world.entityName(v) == "atprk_cryotombblaster" end)
  for _,launcherId in pairs(launchers) do
    world.sendEntityMessage(launcherId, "launchFist", group, power)
  end
  return true
end

-- param state
function setScreenStates(args, board)
  local screens = world.entityQuery(mcontroller.position(), 50, { includedTypes = { "object" } })
  screens = util.filter(screens, function(v) return world.entityName(v) == "atprk_cryotombscreen" end)
  for _,launcherId in pairs(screens) do
    world.sendEntityMessage(launcherId, "setState", args.state)
  end
  return true
end

-- Helpers
function setLeadProjector(projectors)
  local bossId = entity.id()
  local leadProjectorId = projectors[1]
  for i,entityId in ipairs(projectors) do
    world.sendEntityMessage(entityId, "setLeadProjector", bossId, leadProjectorId, i, #projectors)
  end
end
