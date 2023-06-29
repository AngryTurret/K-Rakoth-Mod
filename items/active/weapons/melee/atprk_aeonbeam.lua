require "/scripts/interp.lua"
require "/scripts/vec2.lua"
require "/scripts/util.lua"
require "/items/active/weapons/weapon.lua"

-- Credit to Apple and Nebulox

AeonBeam = WeaponAbility:new()

function AeonBeam:init()
  self.damageConfig.baseDamage = self.baseDps * self.fireTime

  self.weapon:setStance(self.stances.idle)

  self.cooldownTimer = self.fireTime
  self.impactSoundTimer = 0

  self.weapon.onLeaveAbility = function()
    self.weapon:setDamage()
    activeItem.setScriptedAnimationParameter("chains", {})
    animator.setParticleEmitterActive("beamCollision", false)
    animator.stopAllSounds("fireLoop")
    self.weapon:setStance(self.stances.idle)
  end
end

function AeonBeam:update(dt, fireMode, shiftHeld)
  WeaponAbility.update(self, dt, fireMode, shiftHeld)

  self.cooldownTimer = math.max(0, self.cooldownTimer - self.dt)
  self.impactSoundTimer = math.max(self.impactSoundTimer - self.dt, 0)

  if self.fireMode == (self.activatingFireMode or self.abilitySlot)
    and not self.weapon.currentAbility
    and not world.lineTileCollision(mcontroller.position(), self:firePosition())
    and self.cooldownTimer == 0
    and not status.resourceLocked("energy") then

    self:setState(self.fire)
  end
end

function AeonBeam:fire()
  self.weapon:setStance(self.stances.fire)

  animator.playSound("fireStart")
  animator.playSound("fireLoop", -1)

  local wasColliding = false
  local firingTime = 0
  while self.fireMode == (self.activatingFireMode or self.abilitySlot) and status.overConsumeResource("energy", (self.energyUsage or 0) * self.dt) do
    firingTime = firingTime + self.dt
    
    local beamStart = self:firePosition()
    local beamEnd = vec2.add(beamStart, vec2.mul(vec2.norm(self:aimVector(0)), self.beamLength))
    local beamLength = self.beamLength
	
    local damageEnd = vec2.mul(vec2.norm(self:localPosition()), beamLength + self:localPosition()[1])

    local collidePoint = world.lineCollision(beamStart, beamEnd)
    if collidePoint then
      beamEnd = collidePoint

      beamLength = world.magnitude(beamStart, beamEnd)
      damageEnd = vec2.mul(vec2.norm(self:localPosition()), beamLength + self:localPosition()[1])

      animator.setParticleEmitterActive("beamCollision", true)
      animator.resetTransformationGroup("beamEnd")
      animator.translateTransformationGroup("beamEnd", damageEnd)

      if self.impactSoundTimer == 0 then
        animator.setSoundPosition("beamImpact", damageEnd)
        animator.playSound("beamImpact")
        self.impactSoundTimer = self.fireTime
      end
    else
      animator.setParticleEmitterActive("beamCollision", false)
    end

    self.weapon:setDamage(self.damageConfig, {self:localPosition(), damageEnd}, self.fireTime)

    if firingTime > 0.1 then
      self:drawBeam(beamEnd, collidePoint)
    end

    coroutine.yield()
  end

  self:reset()
  animator.playSound("fireEnd")

  self.cooldownTimer = self.fireTime
  self:setState(self.cooldown)
end

function AeonBeam:drawBeam(endPos, didCollide)
  local newChain = copy(self.chain)
  newChain.startOffset = self:localPosition()
  newChain.endPosition = endPos

  if didCollide then
    newChain.endSegmentImage = nil
  end

  activeItem.setScriptedAnimationParameter("chains", {newChain})
end

function AeonBeam:cooldown()
  self.weapon:setStance(self.stances.cooldown)
  self.weapon:updateAim()

  util.wait(self.stances.cooldown.duration, function()

  end)
end

function AeonBeam:firePosition()
  return vec2.add(mcontroller.position(), activeItem.handPosition(self:localPosition()))
end

function AeonBeam:localPosition()
  --return vec2.rotate(vec2.add(self.weapon.muzzleOffset, (self.muzzleOffset or {1.75, -0.125})), -self.weapon.relativeArmRotation)
  return vec2.rotate(vec2.add(self.weapon.muzzleOffset, (self.muzzleOffset or {2.25, 0.05})), -self.weapon.relativeArmRotation)
end

function AeonBeam:aimVector(inaccuracy)
  local aimVector = vec2.rotate({1, 0}, self.weapon.aimAngle + sb.nrand(inaccuracy, 0))
  aimVector[1] = aimVector[1] * mcontroller.facingDirection()
  return aimVector
end

function AeonBeam:uninit()
  self:reset()
end

function AeonBeam:reset()
  self.weapon:setDamage()
  activeItem.setScriptedAnimationParameter("chains", {})
  animator.setParticleEmitterActive("beamCollision", false)
  animator.stopAllSounds("fireStart")
  animator.stopAllSounds("fireLoop")
end
