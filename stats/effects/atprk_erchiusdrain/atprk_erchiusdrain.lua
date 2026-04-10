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
  self.healRatio = config.getParameter("healRatio", 1.0)

  self.saturation = 0
  self.dps = 0
end

function update(dt)
  local spookId = findNearbySpook()
  if spookId then
    local spookPosition = world.entityPosition(spookId)
    local distance = world.distance(spookPosition, mcontroller.position())
    local distanceMag = vec2.mag(distance)

    animator.resetTransformationGroup("smoke")
    animator.rotateTransformationGroup("smoke", vec2.angle(distance))

    local damageDistanceRatio = 1 - math.min(1.0, math.max(0.0, distanceMag / self.damageDistance))
    self.dps = damageDistanceRatio * self.maxDps

    local effectDistance = self.effectDistance
    if type(effectDistance) == "table" then
      effectDistance = effectDistance[2] or effectDistance[1]
    end
    effectDistance = effectDistance or self.damageDistance

    local effectDistanceRatio = 1 - math.min(1.0, math.max(0.0, distanceMag / effectDistance))
    animator.setParticleEmitterEmissionRate("smoke", self.emissionRate * effectDistanceRatio)
    animator.setParticleEmitterActive("smoke", effectDistanceRatio > 0)

    self.saturation = math.floor(-self.desaturateAmount * effectDistanceRatio)

    local damageAmount = self.dps * dt
    status.modifyResource("health", -damageAmount)

    local healAmount = damageAmount * self.healRatio
    if healAmount > 0 then
      world.sendEntityMessage(spookId, "healFromEffect", healAmount)
    end
  else
    self.saturation = 0
    self.dps = 0
    animator.setParticleEmitterActive("smoke", false)
    animator.setLightActive("glow", false)
  end

  animator.setLightColor("glow", {self.light[1], self.light[2], self.light[3]})
  animator.setLightActive("glow", spookId ~= nil)

  local multiply = {
    255 + self.multiply[1],
    255 + self.multiply[2],
    255 + self.multiply[3]
  }
  local multiplyHex = string.format("%s%s%s", toHex(multiply[1]), toHex(multiply[2]), toHex(multiply[3]))
  effect.setParentDirectives(string.format("?saturation=%d?multiply=%s", self.saturation, multiplyHex))
end

function findNearbySpook()
  local searchRadius = self.damageDistance
  if type(self.effectDistance) == "table" then
    searchRadius = math.max(searchRadius, self.effectDistance[2] or self.effectDistance[1] or 0)
  elseif type(self.effectDistance) == "number" then
    searchRadius = math.max(searchRadius, self.effectDistance)
  end

  local entityIds = world.entityQuery(mcontroller.position(), searchRadius, {
    includedTypes = {"monster"},
    withoutEntityId = entity.id()
  })
  if not entityIds then
    return nil
  end

  for _, entityId in ipairs(entityIds) do
    if world.entityName(entityId) == "atprk_erchiusspook" then
      return entityId
    end
  end

  return nil
end

function toHex(num)
  local hex = string.format("%X", math.floor(num + 0.5))
  if num < 16 then
    hex = "0" .. hex
  end
  return hex
end

function uninit()
end
