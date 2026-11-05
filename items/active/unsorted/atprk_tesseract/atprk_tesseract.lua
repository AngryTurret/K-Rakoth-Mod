function init()
end

function update(dt, fireMode, shiftHeld)
  if player then
    player.setProperty("4dShiftHeld", shiftHeld)

    if fireMode == "primary" and not self.active then
      self.active = true
      local lastHeartbeat = player.getProperty("4dPulse", 0)
      if (os.time() - lastHeartbeat) >= 2 then
        player.interact("ScriptPane", "/interface/scripted/atprk_tesseract/atprk_tesseract.config")
      end
    elseif fireMode == "none" then
      self.active = false
    end
  end
end