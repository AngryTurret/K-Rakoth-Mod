function init()
  script.setUpdateDelta(10)
  
  storage.groupId = storage.groupId or nil
  storage.groupLeader = storage.groupLeader or nil
  storage.canonicalMember = storage.canonicalMember or nil
  storage.canonicalInventory = storage.canonicalInventory or nil
  storage.lastMergedKey = storage.lastMergedKey or nil
  
  storage.members = storage.members or {}
  storage.active = false
  storage.isLeader = false
  storage.lastWired = false
  storage.awaitingMerge = false
  storage.memberInventoryKeys = {}
  storage.lastNeighborsKey = ""
  
  message.setHandler("getMembership", handleGetMembership)
  message.setHandler("getInventory", handleGetInventory)
  message.setHandler("syncInventory", handleSyncInventory)
  message.setHandler("getWiredNeighbors", handleGetWiredNeighbors)
end

function handleGetWiredNeighbors()
  return getConnectedNodeIds()
end

function handleGetMembership()
  return {
    groupId = storage.groupId,
    groupLeader = storage.groupLeader,
    members = storage.members,
    active = storage.active,
    isLeader = storage.isLeader,
    wiredNeighbors = getConnectedNodeIds()
  }
end

function collectNetworkMembers(initialNeighbors)
  local members = {}
  local memberMeta = {}
  local visited = {}
  local queue = {}

  visited[entity.id()] = true
  members[#members + 1] = entity.id()
  memberMeta[entity.id()] = { groupId = storage.groupId, groupLeader = storage.groupLeader, active = storage.active }

  for _, neighborId in ipairs(initialNeighbors) do
    if neighborId and world.entityExists(neighborId) and not visited[neighborId] then
      visited[neighborId] = true
      queue[#queue + 1] = neighborId
    end
  end

  while #queue > 0 do
    local currentId = table.remove(queue, 1)
    if currentId and world.entityExists(currentId) then
      local success, response = pcall(function()
        local promise = world.sendEntityMessage(currentId, "getMembership")
        return promise:result()
      end)
      
      if success and type(response) == "table" then
        members[#members + 1] = currentId
        memberMeta[currentId] = { groupId = response.groupId, groupLeader = response.groupLeader, active = response.active }

        local wireNeighbors = response.wiredNeighbors
        if type(wireNeighbors) == "table" then
          for _, neighborId in ipairs(wireNeighbors) do
            if neighborId and world.entityExists(neighborId) and not visited[neighborId] then
              visited[neighborId] = true
              queue[#queue + 1] = neighborId
            end
          end
        end
      end
    end
  end

  return uniqueIds(members), memberMeta
end

function update(dt)
  local wired = getConnectedNodeIds()
  local hasWired = (#wired > 0)
  
  if not hasWired then
    if storage.groupId then
      leaveGroup()
    end
    storage.lastNeighborsKey = ""
    return
  end

  local neighbors = uniqueIds(wired)
  table.sort(neighbors)
  local neighborsKey = table.concat(neighbors, ",")

  if not storage.isLeader and storage.groupLeader and world.entityExists(storage.groupLeader) then
    if neighborsKey == storage.lastNeighborsKey then
      return
    end
  end

  storage.lastNeighborsKey = neighborsKey
  storage.lastWired = true
  
  local allMembers, memberMeta = collectNetworkMembers(neighbors)
  local leader = chooseLeader(allMembers)
  
  storage.members = allMembers
  storage.active = true
  storage.isLeader = (entity.id() == leader)
  
  if not storage.isLeader then
    storage.groupLeader = leader
    return
  end

  local previousLeader = storage.canonicalMember or storage.groupLeader
  local oldLeaderUnwired = false

  if previousLeader and previousLeader ~= entity.id() then
    local oldLeaderInNetwork = false
    for _, memberId in ipairs(allMembers) do
      if memberId == previousLeader then
        oldLeaderInNetwork = true
        break
      end
    end

    if not oldLeaderInNetwork then
      if world.entityExists(previousLeader) then
        oldLeaderUnwired = true
        clearInventory()
        storage.canonicalInventory = {}
        storage.lastMergedKey = nil
        storage.groupId = generateGroupId()
      else
        storage.groupId = storage.groupId or generateGroupId()
      end
    end
  end

  storage.groupLeader = entity.id()
  storage.canonicalMember = entity.id()

  if not storage.groupId then
    storage.groupId = generateGroupId()
  end
  
  local result = attemptConsolidate(allMembers, memberMeta, oldLeaderUnwired)
  storage.awaitingMerge = not result
end

function die()
  local otherMembersExist = false
  
  if storage.groupId and storage.active and type(storage.members) == "table" then
    for _, memberId in ipairs(storage.members) do
      if memberId ~= entity.id() and world.entityExists(memberId) then
        otherMembersExist = true
        break
      end
    end
  end

  if otherMembersExist then
    clearInventory()
  end
end

function uninit()
end

function normalizeInventory(inventory)
  local normalized = {}
  for _, item in pairs(inventory) do
    if item and item.count and item.count > 0 then
      normalized[#normalized + 1] = item
    end
  end
  return normalized
end

function handleGetInventory()
  return normalizeInventory(world.containerItems(entity.id()) or {})
end

function getInventory()
  return handleGetInventory()
end

function handleSyncInventory(_, _, inventory, groupId, groupLeader, members)
  local wired = getConnectedNodeIds()
  if #wired == 0 then
    return
  end

  if not inventory or not groupId or not groupLeader or type(members) ~= "table" then
    return
  end
  
  local normalized = normalizeInventory(inventory)
  local newKey = inventoryGroupKey(normalized)

  storage.groupId = groupId
  storage.groupLeader = groupLeader
  storage.canonicalMember = groupLeader
  storage.members = uniqueIds(members)
  storage.active = true
  storage.isLeader = (entity.id() == groupLeader)
  storage.canonicalInventory = normalized
  storage.lastMergedKey = newKey

  applyInventory(entity.id(), normalized)
  storage.memberInventoryKeys[entity.id()] = newKey
end

function syncInventory(inventory, groupId, groupLeader, members)
  handleSyncInventory(nil, nil, inventory, groupId, groupLeader, members)
end

function attemptConsolidate(members, memberMeta, oldLeaderUnwired)
  members = uniqueIds(members)

  if oldLeaderUnwired then
    local emptyInventory = {}
    local finalKey = inventoryGroupKey(emptyInventory)
    storage.canonicalInventory = emptyInventory
    storage.lastMergedKey = finalKey
    storage.members = members
    storage.active = true
    
    storage.memberInventoryKeys = {}
    for _, memberId in ipairs(members) do
      storage.memberInventoryKeys[memberId] = finalKey
    end

    syncToAll(members, emptyInventory)
    return true
  end

  local allMembers = uniqueIds({entity.id()})
  for _, memberId in ipairs(members) do
    if memberId ~= entity.id() then
      allMembers[#allMembers + 1] = memberId
    end
  end
  allMembers = uniqueIds(allMembers)
  
  local allInventories = {}
  allInventories[entity.id()] = normalizeInventory(world.containerItems(entity.id()) or {})
  
  for _, neighborId in ipairs(allMembers) do
    if neighborId ~= entity.id() and world.entityExists(neighborId) then
      local success, response = pcall(function()
        local promise = world.sendEntityMessage(neighborId, "getInventory")
        return promise:result()
      end)
      if success and type(response) == "table" then
        allInventories[neighborId] = normalizeInventory(response)
      else
        allInventories[neighborId] = normalizeInventory(world.containerItems(neighborId) or {})
      end
    end
  end

  local inventoryKeys = {}
  local groupMembers = {}
  local joiners = {}

  for _, memberId in ipairs(allMembers) do
    local inv = allInventories[memberId] or {}
    inventoryKeys[memberId] = inventoryGroupKey(inv)
    
    local meta = memberMeta[memberId] or {}
    local isGroupMember = (memberId == entity.id()) or (storage.groupId ~= nil and meta.groupId ~= nil and meta.groupId == storage.groupId)
    
    if isGroupMember then
      groupMembers[#groupMembers + 1] = memberId
    else
      joiners[#joiners + 1] = memberId
    end
  end

  local baseInventory = nil
  local changedMembers = {}
  
  if storage.lastMergedKey then
    for _, gm in ipairs(groupMembers) do
      local currentKey = inventoryKeys[gm]
      if currentKey ~= storage.lastMergedKey then
        changedMembers[#changedMembers + 1] = gm
      end
    end
  end

  if #changedMembers > 0 then
    local changedId = changedMembers[1]
    for _, gm in ipairs(changedMembers) do
      if gm == entity.id() then
        changedId = gm
        break
      end
    end
    baseInventory = allInventories[changedId] or {}
  else
    baseInventory = storage.canonicalInventory or allInventories[entity.id()] or {}
  end

  local finalInventory = baseInventory

  if #joiners > 0 then
    local sourcesToMerge = { baseInventory }
    local seenGroups = {}
    
    for _, joinerId in ipairs(joiners) do
      local meta = memberMeta[joinerId] or {}
      local groupKey = meta.groupId or ("standalone_" .. tostring(joinerId))
      if not seenGroups[groupKey] then
        seenGroups[groupKey] = true
        sourcesToMerge[#sourcesToMerge + 1] = allInventories[joinerId] or {}
      end
    end
    
    finalInventory = mergeAllInventories(sourcesToMerge)
  end

  local slotCount = config.getParameter("slotCount") or 64
  local requiredSlots = countRequiredSlots(finalInventory)

  if requiredSlots > slotCount then
    storage.active = false
    return false
  end

  local finalKey = inventoryGroupKey(finalInventory)

  storage.canonicalInventory = finalInventory
  storage.lastMergedKey = finalKey
  storage.members = allMembers
  storage.active = true
  
  storage.memberInventoryKeys = {}
  for _, memberId in ipairs(allMembers) do
    storage.memberInventoryKeys[memberId] = finalKey
  end

  syncToAll(allMembers, finalInventory)
  return true
end

function countRequiredSlots(inventory)
  local groups = {}
  for _, item in pairs(inventory) do
    if item and item.count and item.count > 0 then
      local key = itemIdentityKey(item)
      groups[key] = groups[key] or { total = 0, item = item }
      groups[key].total = groups[key].total + item.count
    end
  end
  
  local slots = 0
  for _, group in pairs(groups) do
    local maxStack = getItemMaxStack(group.item)
    slots = slots + math.ceil(group.total / maxStack)
  end
  return slots
end

function inventoryGroupKey(inventory)
  local counts = {}
  for _, item in pairs(inventory) do
    if item and item.count and item.count > 0 then
      local key = itemIdentityKey(item)
      counts[key] = (counts[key] or 0) + item.count
    end
  end
  local keys = {}
  for key, total in pairs(counts) do
    keys[#keys + 1] = key .. ":" .. tostring(total)
  end
  table.sort(keys)
  return table.concat(keys, "|")
end

function uniqueIds(list)
  local seen = {}
  local result = {}
  for _, id in ipairs(list) do
    if id and not seen[id] then
      seen[id] = true
      result[#result + 1] = id
    end
  end
  return result
end

function chooseLeader(members)
  if #members == 0 then
    return entity.id()
  end
  local leader = members[1]
  for _, memberId in ipairs(members) do
    if memberId and memberId < leader then
      leader = memberId
    end
  end
  return leader
end

function itemIdentityKey(item)
  local key = item.name
  if item.parameters and type(item.parameters) == "table" and next(item.parameters) ~= nil then
    key = key .. ":" .. sb.print(item.parameters)
  end
  if item.durability then
    key = key .. ":dur=" .. tostring(item.durability)
  end
  if item.damage then
    key = key .. ":dmg=" .. tostring(item.damage)
  end
  return key
end

function getItemMaxStack(item)
  if not item or not item.name then
    return 1
  end
  local success, cfg = pcall(root.itemConfig, item)
  if success and cfg and cfg.config then
    return cfg.config.maxStack or cfg.config.stackSize or math.max(1, item.count or 1)
  end
  return math.max(1, item.count or 1)
end

function mergeAllInventories(allInventories)
  local grouped = {}
  for _, inv in pairs(allInventories) do
    if type(inv) == "table" then
      for _, item in pairs(inv) do
        if item and item.count and item.count > 0 then
          local key = itemIdentityKey(item)
          if not grouped[key] then
            grouped[key] = { item = item, totalCount = item.count }
          else
            grouped[key].totalCount = grouped[key].totalCount + item.count
          end
        end
      end
    end
  end
  
  local merged = {}
  for _, group in pairs(grouped) do
    local maxStack = getItemMaxStack(group.item)
    local remaining = group.totalCount
    while remaining > 0 do
      local count = math.min(remaining, maxStack)
      local stack = shallowCopy(group.item)
      stack.count = count
      merged[#merged + 1] = stack
      remaining = remaining - count
    end
  end
  return merged
end

function syncToAll(members, inventory)
  members = uniqueIds(members)
  for _, memberId in ipairs(members) do
    if world.entityExists(memberId) then
      if memberId == entity.id() then
        applyInventory(entity.id(), inventory)
        storage.memberInventoryKeys[entity.id()] = inventoryGroupKey(inventory)
      else
        pcall(function()
          world.sendEntityMessage(memberId, "syncInventory", inventory, storage.groupId, storage.groupLeader, members)
        end)
      end
    end
  end
end

function applyInventory(targetId, inventory)
  if not world.entityExists(targetId) then return end
  local current = normalizeInventory(world.containerItems(targetId) or {})
  if inventoryGroupKey(current) == inventoryGroupKey(inventory) then
    return
  end
  world.containerTakeAll(targetId)
  for _, item in pairs(inventory) do
    if item and item.count and item.count > 0 then
      world.containerAddItems(targetId, item)
    end
  end
end

function clearInventory()
  if world.entityExists(entity.id()) then
    world.containerTakeAll(entity.id())
  end
end

function leaveGroup()
  local keeper = storage.canonicalMember or storage.groupLeader
  local isLeader = storage.isLeader or (keeper == entity.id())

  if not isLeader then
    local keeperExists = keeper and world.entityExists(keeper)
    if keeper and keeperExists then
      clearInventory()
    end
  end

  storage.groupId = nil
  storage.groupLeader = nil
  storage.members = {}
  storage.canonicalMember = nil
  storage.active = false
  storage.isLeader = false
  storage.canonicalInventory = nil
  storage.lastMergedKey = nil
  storage.memberInventoryKeys = {}
  storage.lastNeighborsKey = ""
end

function getConnectedNodeIds()
  local ids = {}
  
  local function addNeighborsFromResult(result)
    if not result or type(result) ~= "table" then return end
    for key, value in pairs(result) do
      if type(key) == "number" and key ~= 0 then ids[#ids + 1] = key
      elseif type(value) == "number" and value ~= 0 then ids[#ids + 1] = value end
    end
  end

  if object.getInputNodeIds then
    for nodeIdx = 0, 4 do
      pcall(function() addNeighborsFromResult(object.getInputNodeIds(nodeIdx)) end)
    end
  end
  
  if object.getOutputNodeIds then
    for nodeIdx = 0, 4 do
      pcall(function() addNeighborsFromResult(object.getOutputNodeIds(nodeIdx)) end)
    end
  end
  
  return uniqueIds(ids)
end

function generateGroupId()
  return tostring(entity.id()) .. "_" .. tostring(math.random(100000, 999999))
end

function shallowCopy(t)
  local copy = {}
  for k, v in pairs(t) do copy[k] = v end
  return copy
end

function debug(fmt, ...) end