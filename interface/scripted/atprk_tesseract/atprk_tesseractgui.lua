function init()
  local lastHeartbeat = player.getProperty("4dPulse", 0)
  local now = os.time()

  if (now - lastHeartbeat) < 2 then
    pane.dismiss()
    return
  end

  player.setProperty("4dPulse", now)
  self.inventory = player.getProperty("4dInventory", {})
  refreshSlots()

  pane.playSound("/sfx/objects/mechbeacon_pulse2.ogg")
end

function update(dt)
  player.setProperty("4dPulse", os.time())
end

function uninit()
  player.setProperty("4dPulse", 0)

  pane.playSound("/sfx/objects/mechbeacon_pulse1.ogg")
end

function refreshSlots()
  for i = 1, 64 do
    local slotName = "slot" .. i
    local item = self.inventory[tostring(i)] or nil
    widget.setItemSlotItem(slotName, item)
  end
end

function slotClicked(widgetName)
  local slotIndex = string.sub(widgetName, 5)
  local currentSlotItem = self.inventory[slotIndex]
  
  local cursorItem = player.swapSlotItem()
  player.setSwapSlotItem(currentSlotItem)

  self.inventory[slotIndex] = cursorItem
  player.setProperty("4dInventory", self.inventory)

  widget.setItemSlotItem(widgetName, cursorItem)
end

function slotRightClicked(widgetName)
  slotClicked(widgetName)
end