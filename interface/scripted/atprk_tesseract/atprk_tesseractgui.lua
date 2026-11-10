local RARITY_MAP = {
  essential = 5,
  legendary = 4,
  rare = 3,
  uncommon = 2,
  common = 1
}

function init()
  local lastHeartbeat = player.getProperty("4dPulse", 0)
  local now = os.time()

  if (now - lastHeartbeat) < 2 then
    pane.dismiss()
    return
  end

  player.setProperty("4dPulse", now)
  self.inventory = player.getProperty("4dInventory", {})
  normalizeInventory()
  
  self.lastSeenCursorItem = player.swapSlotItem()
  self.guiClickedThisFrame = false
  
  refreshSlots()

  pane.playSound("/sfx/objects/mechbeacon_pulse2.ogg")
end

function update(dt)
  player.setProperty("4dPulse", os.time())

  local currentCursorItem = player.swapSlotItem()
  local shiftHeld = player.getProperty("4dShiftHeld", false)

  if not self.guiClickedThisFrame then
    if shiftHeld and currentCursorItem then
      local itemIsNew = false
      if not self.lastSeenCursorItem then
        itemIsNew = true
      elseif not itemsMatch(self.lastSeenCursorItem, currentCursorItem) then
        itemIsNew = true
      elseif currentCursorItem.count > self.lastSeenCursorItem.count then
        itemIsNew = true
      end

      if itemIsNew then
        local remaining = autoDepositItem(currentCursorItem)
        player.setSwapSlotItem(remaining)
        saveInventory()
        refreshSlots()
        currentCursorItem = remaining
      end
    end
  end

  self.lastSeenCursorItem = currentCursorItem
  self.guiClickedThisFrame = false
end

function uninit()
  player.setProperty("4dPulse", 0)

  pane.playSound("/sfx/objects/mechbeacon_pulse1.ogg")
end

function normalizeInventory()
  local normalized = {}
  if type(self.inventory) == "table" then
    for k, v in pairs(self.inventory) do
      normalized[tostring(k)] = v
    end
  end
  self.inventory = normalized
end

function getSlotItem(index)
  if not self.inventory then return nil end
  local keyStr = tostring(index)
  local keyNum = tonumber(index)
  return self.inventory[keyStr] or (keyNum and self.inventory[keyNum]) or nil
end

function refreshSlots()
  for i = 1, 64 do
    local slotName = "slot" .. i
    local item = getSlotItem(i)
    widget.setItemSlotItem(slotName, item)
  end
end

function saveInventory()
  normalizeInventory()
  player.setProperty("4dInventory", self.inventory)
end

function takeAll()
  self.guiClickedThisFrame = true
  for i = 1, 64 do
    local key = tostring(i)
    local slotItem = getSlotItem(i)
    if slotItem then
      local remaining = player.giveItem(slotItem)
      if remaining and remaining.count > 0 then
        self.inventory[key] = remaining
      else
        self.inventory[key] = nil
      end
    end
  end
  saveInventory()
  refreshSlots()
end

function sort()
  self.guiClickedThisFrame = true

  local rawItems = {}
  for i = 1, 64 do
    local item = getSlotItem(i)
    if item then
      table.insert(rawItems, copyItem(item))
    end
  end

  local consolidated = {}
  for _, item in ipairs(rawItems) do
    local maxStack = getItemMaxStack(item)
    for _, existing in ipairs(consolidated) do
      if itemsMatch(existing, item) and existing.count < maxStack then
        local space = maxStack - existing.count
        local transfer = math.min(item.count, space)
        existing.count = existing.count + transfer
        item.count = item.count - transfer
        if item.count <= 0 then break end
      end
    end
    if item.count > 0 then
      table.insert(consolidated, item)
    end
  end

  local metaCache = {}
  for _, item in ipairs(consolidated) do
    local conf = root.itemConfig(item)
    local cfg = (conf and conf.config) or {}
    
    local rarity = string.lower(type(cfg.rarity) == "string" and cfg.rarity or "common")
    local category = string.lower(type(cfg.category) == "string" and cfg.category or "")
    local shortdesc = type(cfg.shortdescription) == "string" and cfg.shortdescription or (type(item) == "table" and item.name or tostring(item))
    shortdesc = string.lower(shortdesc)

    metaCache[item] = {
      rarityWeight = RARITY_MAP[rarity] or 1,
      category = category,
      shortdescription = shortdesc,
      name = type(item) == "table" and (item.name or "") or tostring(item)
    }
  end

  table.sort(consolidated, function(a, b)
    local mA = metaCache[a]
    local mB = metaCache[b]

    if mA.rarityWeight ~= mB.rarityWeight then
      return mA.rarityWeight > mB.rarityWeight
    end
    if mA.category ~= mB.category then
      return mA.category < mB.category
    end
    if mA.shortdescription ~= mB.shortdescription then
      return mA.shortdescription < mB.shortdescription
    end
    if a.count ~= b.count then
      return a.count > b.count
    end
    return mA.name < mB.name
  end)

  self.inventory = {}
  for i = 1, 64 do
    if consolidated[i] then
      self.inventory[tostring(i)] = consolidated[i]
    end
  end

  saveInventory()
  refreshSlots()
end

function getItemMaxStack(item)
  if not item then return 1000 end
  local conf = root.itemConfig(item)
  if conf and conf.config and conf.config.maxStack then
    return conf.config.maxStack
  end
  return 1000
end

function itemsMatch(item1, item2)
  if not item1 or not item2 then return false end
  return root.itemDescriptorsMatch(item1, item2, true)
end

function copyItem(item, count)
  if not item then return nil end
  local newItem = sb.jsonMerge({}, item)
  if count ~= nil then
    newItem.count = count
  end
  return newItem
end

function autoDepositItem(item)
  if not item or item.count <= 0 then return nil end
  local maxStack = getItemMaxStack(item)

  for i = 1, 64 do
    local key = tostring(i)
    local slotItem = getSlotItem(i)
    if slotItem and itemsMatch(slotItem, item) then
      local space = maxStack - slotItem.count
      if space > 0 then
        local transfer = math.min(item.count, space)
        slotItem.count = slotItem.count + transfer
        item.count = item.count - transfer
        self.inventory[key] = slotItem
        if item.count <= 0 then return nil end
      end
    end
  end

  for i = 1, 64 do
    local key = tostring(i)
    local slotItem = getSlotItem(i)
    if slotItem == nil then
      local transfer = math.min(item.count, maxStack)
      self.inventory[key] = copyItem(item, transfer)
      item.count = item.count - transfer
      if item.count <= 0 then return nil end
    end
  end

  return item
end

function slotClicked(widgetName)
  self.guiClickedThisFrame = true
  local slotIndex = string.sub(widgetName, 5)
  local slotItem = getSlotItem(slotIndex)
  local cursorItem = player.swapSlotItem()
  local shiftHeld = player.getProperty("4dShiftHeld", false)

  if shiftHeld then
    if cursorItem == nil then
      if slotItem ~= nil then
        player.giveItem(slotItem)
        self.inventory[tostring(slotIndex)] = nil
        saveInventory()
        widget.setItemSlotItem(widgetName, nil)
      end
    else
      handleLeftClickPlacement(widgetName, slotIndex, slotItem, cursorItem)
    end
  else
    if cursorItem == nil then
      if slotItem ~= nil then
        player.setSwapSlotItem(slotItem)
        self.inventory[tostring(slotIndex)] = nil
        saveInventory()
        widget.setItemSlotItem(widgetName, nil)
      end
    else
      handleLeftClickPlacement(widgetName, slotIndex, slotItem, cursorItem)
    end
  end
end

function handleLeftClickPlacement(widgetName, slotIndex, slotItem, cursorItem)
  local key = tostring(slotIndex)
  if slotItem == nil then
    self.inventory[key] = cursorItem
    player.setSwapSlotItem(nil)
    saveInventory()
    widget.setItemSlotItem(widgetName, cursorItem)
  elseif itemsMatch(cursorItem, slotItem) then
    local maxStack = getItemMaxStack(slotItem)
    local space = maxStack - slotItem.count
    if space > 0 then
      local transferCount = math.min(cursorItem.count, space)
      slotItem.count = slotItem.count + transferCount
      cursorItem.count = cursorItem.count - transferCount
      
      self.inventory[key] = slotItem
      if cursorItem.count <= 0 then
        player.setSwapSlotItem(nil)
      else
        player.setSwapSlotItem(cursorItem)
      end
      saveInventory()
      widget.setItemSlotItem(widgetName, slotItem)
    else
      self.inventory[key] = cursorItem
      player.setSwapSlotItem(slotItem)
      saveInventory()
      widget.setItemSlotItem(widgetName, cursorItem)
    end
  else
    self.inventory[key] = cursorItem
    player.setSwapSlotItem(slotItem)
    saveInventory()
    widget.setItemSlotItem(widgetName, cursorItem)
  end
end

function slotRightClicked(widgetName)
  self.guiClickedThisFrame = true
  local slotIndex = string.sub(widgetName, 5)
  local slotItem = getSlotItem(slotIndex)
  local cursorItem = player.swapSlotItem()
  local shiftHeld = player.getProperty("4dShiftHeld", false)
  local key = tostring(slotIndex)

  if shiftHeld then
    if slotItem ~= nil then
      local takeCount = math.max(1, math.floor(slotItem.count / 2))
      
      if cursorItem == nil then
        local newCursorItem = copyItem(slotItem, takeCount)
        local remaining = slotItem.count - takeCount
        if remaining > 0 then
          slotItem.count = remaining
          self.inventory[key] = slotItem
        else
          self.inventory[key] = nil
        end
        player.setSwapSlotItem(newCursorItem)
        saveInventory()
        widget.setItemSlotItem(widgetName, self.inventory[key])
      elseif itemsMatch(cursorItem, slotItem) then
        local maxStack = getItemMaxStack(cursorItem)
        local space = maxStack - cursorItem.count
        if space > 0 then
          local transferCount = math.min(takeCount, space)
          cursorItem.count = cursorItem.count + transferCount
          local remaining = slotItem.count - transferCount
          if remaining > 0 then
            slotItem.count = remaining
            self.inventory[key] = slotItem
          else
            self.inventory[key] = nil
          end
          player.setSwapSlotItem(cursorItem)
          saveInventory()
          widget.setItemSlotItem(widgetName, self.inventory[key])
        end
      end
    end
  else
    if cursorItem == nil then
      if slotItem ~= nil then
        local newCursorItem = copyItem(slotItem, 1)
        if slotItem.count > 1 then
          slotItem.count = slotItem.count - 1
          self.inventory[key] = slotItem
        else
          self.inventory[key] = nil
        end
        player.setSwapSlotItem(newCursorItem)
        saveInventory()
        widget.setItemSlotItem(widgetName, self.inventory[key])
      end
    elseif slotItem ~= nil and itemsMatch(cursorItem, slotItem) then
      local maxStack = getItemMaxStack(cursorItem)
      if cursorItem.count < maxStack then
        cursorItem.count = cursorItem.count + 1
        if slotItem.count > 1 then
          slotItem.count = slotItem.count - 1
          self.inventory[key] = slotItem
        else
          self.inventory[key] = nil
        end
        player.setSwapSlotItem(cursorItem)
        saveInventory()
        widget.setItemSlotItem(widgetName, self.inventory[key])
      end
    end
  end
end