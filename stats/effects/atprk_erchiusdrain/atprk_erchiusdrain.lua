require "/scripts/vec2.lua"
require "/scripts/util.lua"
require "/scripts/interp.lua"

function init()
  self.effectDistance = config.getParameter("effectDistance")
  self.emissionRate = config.getParameter("emissionRate")
  self.desaturateAmount = config.getParameter("desaturateAmount")
  self.light = config.getParameter("lightColor")
  self.multiply = config.getParameter("multiplyColor")

  self.maxDps = config.getParameter("maxDps")
  self.damageDistance = config.getParameter("damageDistance")

  self.saturation = 0
  self.dps = 0
end

function update(dt)
  status.modifyResource("health", -self.dps * dt)

  local closestMonster = findClosestErchiusspook()
  if closestMonster then
    local monsterPosition = world.entityPosition(closestMonster)
    local distance = world.distance(monsterPosition, mcontroller.position())
    animator.resetTransformationGroup("smoke")
    animator.rotateTransformationGroup("smoke", vec2.angle(distance))

    local damageDistanceRatio = 1 - math.min(1.0, math.max(0.0, vec2.mag(distance) / self.damageDistance))
    self.dps = damageDistanceRatio * self.maxDps

    local effectDistanceRatio = 1 - math.min(1.0, math.max(0.0, vec2.mag(distance) / self.effectDistance))
    animator.setParticleEmitterEmissionRate("smoke", self.emissionRate * effectDistanceRatio)
    animator.setParticleEmitterActive("smoke", effectDistanceRatio > 0)

    self.saturation = math.floor(-self.desaturateAmount * effectDistanceRatio)

    world.sendEntityMessage(closestMonster, "modifyResource", "health", self.dps * dt)

    animator.setLightColor("glow", {self.light[1] * effectDistanceRatio, self.light[2] * effectDistanceRatio, self.light[3] * effectDistanceRatio})
    animator.setLightActive("glow", true)

    local multiply = {255 + self.multiply[1] * effectDistanceRatio, 255 + self.multiply[2] * effectDistanceRatio, 255 + self.multiply[3] * effectDistanceRatio}
    local multiplyHex = string.format("%s%s%s", toHex(multiply[1]), toHex(multiply[2]), toHex(multiply[3]))
    effect.setParentDirectives(string.format("?saturation=%d?multiply=%s", self.saturation, multiplyHex))
  else
    self.saturation = 0
    animator.setLightActive("glow", false)
    animator.setParticleEmitterActive("smoke", false)
    self.dps = 0
  end
end

function findClosestErchiusspook()
  local monsters = world.entityQuery(mcontroller.position(), 100, {includedTypes = {"monster"}})
  local closestMonster = nil
  local minDist = math.huge
  for _, id in ipairs(monsters) do
    if world.monsterType(id) == "atprk_erchiusspook" then
      local dist = world.magnitude(world.distance(world.entityPosition(id), mcontroller.position()))
      if dist < minDist then
        minDist = dist
        closestMonster = id
      end
    end
  end
  return closestMonster
end

function toHex(num)
  local hex = string.format("%X", math.floor(num + 0.5))
  if num < 16 then hex = "0"..hex end
  return hex
end

function uninit()
end