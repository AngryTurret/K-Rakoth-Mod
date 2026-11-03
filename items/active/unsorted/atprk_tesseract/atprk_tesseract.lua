function init()
end

function update(dt, fireMode, shiftHeld)
  if fireMode == "primary" and not self.active then
    self.active = true
    if player then
      local lastHeartbeat = player.getProperty("4dPulse", 0)
      if (os.time() - lastHeartbeat) >= 2 then
        player.interact("ScriptPane", "/interface/scripted/atprk_tesseract/atprk_tesseract.config")
      end
    end
  elseif fireMode == "none" then
    self.active = false
  end
end