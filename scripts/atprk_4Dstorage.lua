function init()
  script.setUpdateDelta(10)
  
  storage.groupId = storage.groupId or nil
  storage.groupLeader = storage.groupLeader or nil
  storage.members = storage.members or {}
  storage.knownMembers = storage.knownMembers or {}
  storage.canonicalMember = storage.canonicalMember or nil
  storage.active = storage.active or false
  storage.isLeader = storage.isLeader or false
  storage.lastWired = storage.lastWired or false
  storage.awaitingMerge = storage.awaitingMerge or false
  storage.lastMergedKey = storage.lastMergedKey or nil
  storage.memberInventoryKeys = storage.memberInventoryKeys or {}
  storage.debugLog = {}
  storage.containerTag = storage.containerTag or "atprk_4dcratemedium" or "atprk-4dcratesmall" or "atprk-4dcratetiny" or "atprk-4dcratetiniest"
  
  message.setHandler("getMembership", handleGetMembership)
  message.setHandler("getInventory", handleGetInventory)
  message.setHandler("syncInventory", handleSyncInventory)
  
end

function collectNetworkMembers(neighbors)
  local members = uniqueIds({entity.id()})
  local memberMeta = {}
  memberMeta[entity.id()] = {groupId = storage.groupId, groupLeader = storage.groupLeader, active = storage.active}

  for _, neighborId in ipairs(neighbors) do
    members[#members + 1] = neighborId
  end

  local seen = {}
  for _, memberId in ipairs(members) do
    seen[memberId] = true
  end
  local queue = {}
  for _, memberId in ipairs(members) do
    queue[#queue + 1] = memberId
  end

  while #queue > 0 do
    local memberId = table.remove(queue)
    if memberId and memberId ~= entity.id() and world.entityExists(memberId) then
      local success, response = pcall(function()
        local promise = world.sendEntityMessage(memberId, "getMembership")
        return promise:result()
      end)
      if success and type(response) == "table" and type(response.members) == "table" then
        memberMeta[memberId] = { groupId = response.groupId, groupLeader = response.groupLeader, active = response.active }
        for _, memberId2 in ipairs(response.members) do
          if memberId2 and not seen[memberId2] then
            local valid = true
            if memberId2 ~= entity.id() and memberId2 ~= memberId then
              local validateSuccess, validateResponse = pcall(function()
                local validatePromise = world.sendEntityMessage(memberId2, "getMembership")
                return validatePromise:result()
              end)
              if not validateSuccess or type(validateResponse) ~= "table" or type(validateResponse.members) ~= "table" then
                valid = false
              end
            end
            if valid then
              seen[memberId2] = true
              members[#members + 1] = memberId2
              queue[#queue + 1] = memberId2
            else
              debug("discarding unreachable member %s reported by %s", tostring(memberId2), tostring(memberId))
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
  
  debug("update: wired=%s, active=%s, groupId=%s", tostring(hasWired), tostring(storage.active), tostring(storage.groupId))
  
  if not hasWired then
    if storage.lastWired then
      debug("no wired neighbors this tick; delaying leave until next tick")
      storage.lastWired = false
      return
    end
    if storage.groupId then
      debug("unwired, leaving group")
      leaveGroup()
    end
    return
  end

  if not storage.lastWired then
    debug("network rewired; allowing consolidation on fresh wire event")
    storage.awaitingMerge = false
  end
  storage.lastWired = true
  
  local neighbors = uniqueIds(wired)
  debug("discovered %d neighbors", #neighbors)
  
  local allMembers, memberMeta = collectNetworkMembers(neighbors)
  debug("network membership=%s", sb.print(allMembers))
  local leader = chooseLeader(allMembers)
  debug("group leader=%s", tostring(leader))
  
  storage.members = allMembers
  storage.groupLeader = leader
  storage.active = true
  storage.isLeader = (entity.id() == leader)
  if not storage.isLeader then
    return
  end

  if storage.awaitingMerge then
    debug("overflow state active; skipping consolidation until rewired")
    return
  end
  
  if not storage.groupId then
    debug("no groupId yet, creating one")
    storage.groupId = generateGroupId()
  end
  
  local result = attemptConsolidate(allMembers, memberMeta)
  debug("consolidate result: %s", tostring(result))
  if result == false then
    storage.awaitingMerge = true
  else
    storage.awaitingMerge = false
  end
end

function die()
  debug("die() called, clearing inventory")
  clearInventory()
end

function uninit()
  debug("uninit() called, clearing inventory")
  clearInventory()
end


function handleGetMembership()
  debug("handleGetMembership - returning groupId=%s, active=%s, leader=%s", tostring(storage.groupId), tostring(storage.active), tostring(storage.groupLeader))
  return {
    groupId = storage.groupId,
    groupLeader = storage.groupLeader,
    members = storage.members,
    active = storage.active,
    isLeader = storage.isLeader
  }
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
  local inv = normalizeInventory(world.containerItems(entity.id()) or {})
  debug("handleGetInventory - returning %d items", #inv)
  return inv
end

function getInventory()
  return handleGetInventory()
end

function handleSyncInventory(_, _, inventory, groupId, groupLeader, members)
  if not inventory or not groupId or not groupLeader or type(members) ~= "table" then
    debug("handleSyncInventory - invalid params")
    return
  end
  
  local normalized = normalizeInventory(inventory)
  debug("handleSyncInventory - syncing %d items, groupId=%s, leader=%s, members=%s", #normalized, tostring(groupId), tostring(groupLeader), sb.print(members))
  storage.groupId = groupId
  storage.groupLeader = groupLeader
  storage.members = uniqueIds(members)
  storage.active = true
  storage.isLeader = false
  storage.canonicalMember = groupLeader
  storage.canonicalInventory = normalized
  storage.lastMergedKey = inventoryGroupKey(normalized)
  applyInventory(entity.id(), normalized)
  storage.memberInventoryKeys[entity.id()] = storage.lastMergedKey
end

function syncInventory(inventory, groupId, groupLeader, members)
  if not inventory or not groupId or not groupLeader or type(members) ~= "table" then
    debug("syncInventory - invalid params")
    return
  end
  
  local normalized = normalizeInventory(inventory)
  debug("syncInventory - syncing %d items, groupId=%s, leader=%s, members=%s", #normalized, tostring(groupId), tostring(groupLeader), sb.print(members))
  storage.groupId = groupId
  storage.groupLeader = groupLeader
  storage.members = uniqueIds(members)
  storage.active = true
  storage.isLeader = false
  storage.canonicalMember = groupLeader
  storage.canonicalInventory = normalized
  storage.lastMergedKey = inventoryGroupKey(normalized)
  applyInventory(entity.id(), normalized)
  storage.memberInventoryKeys[entity.id()] = storage.lastMergedKey
end


function attemptConsolidate(members, memberMeta)
  members = uniqueIds(members)
  local allMembers = uniqueIds({entity.id()})
  for _, memberId in ipairs(members) do
    if memberId ~= entity.id() then
      allMembers[#allMembers + 1] = memberId
    end
  end
  allMembers = uniqueIds(allMembers)
  local allInventories = {}
  
  allInventories[entity.id()] = normalizeInventory(world.containerItems(entity.id()) or {})
  debug("leader live inventory read (%d items)", #allInventories[entity.id()])
  
  local neighbors = {}
  for _, memberId in ipairs(allMembers) do
    if memberId ~= entity.id() then
      neighbors[#neighbors + 1] = memberId
    end
  end

  for _, neighborId in ipairs(neighbors) do
    if neighborId and world.entityExists(neighborId) then
      local success, response = pcall(function()
        local promise = world.sendEntityMessage(neighborId, "getInventory")
        return promise:result()
      end)
      if success then
        if type(response) == "table" then
          local normalized = normalizeInventory(response)
          allInventories[neighborId] = normalized
          debug("got inventory from neighbor %s via message call: %d items", neighborId, #normalized)
        else
          local fallback = normalizeInventory(world.containerItems(neighborId) or {})
          allInventories[neighborId] = fallback
          debug("getInventory response from neighbor %s was not a table (%s); fallback returned %d items", neighborId, type(response), #fallback)
        end
      else
        local fallback = normalizeInventory(world.containerItems(neighborId) or {})
        allInventories[neighborId] = fallback
        debug("failed message call on neighbor %s: %s; fallback returned %d items", neighborId, tostring(response), #fallback)
      end
      local inventoryDebug = sb.print(allInventories[neighborId])
      debug("neighbor %s inventory payload: %s", neighborId, inventoryDebug)
    end
  end
  
  allMembers = uniqueIds(allMembers)
  debug("gathered inventories from %d members", #allMembers)

  local inventoryKeys = {}
  local keyCounts = {}
  local groupMembers = {}
  local joiners = {}
  local groupAllSame = true
  local firstGroupKey = nil

  for _, memberId in ipairs(allMembers) do
    local inv = allInventories[memberId] or {}
    local key = inventoryGroupKey(inv)
    inventoryKeys[memberId] = key
    keyCounts[key] = (keyCounts[key] or 0) + 1

    local meta = memberMeta[memberId] or {}
    local isGroupMember = memberId == entity.id() or (meta.active and meta.groupLeader == storage.groupLeader)
    if isGroupMember then
      groupMembers[#groupMembers + 1] = memberId
      if not firstGroupKey then
        firstGroupKey = key
      elseif key ~= firstGroupKey then
        groupAllSame = false
      end
    else
      joiners[#joiners + 1] = memberId
    end
  end
  debug("membership classification: groupMembers=%s, joiners=%s", sb.print(groupMembers), sb.print(joiners))

  local chosenInventory = nil
  local chosenMember = nil
  local mergedKey = nil
  local slotCount = config.getParameter("slotCount") or 64

  local changedMembers = {}
  for _, gm in ipairs(groupMembers) do
    local prev = storage.memberInventoryKeys[gm]
    local now = inventoryKeys[gm]
    if prev and now and prev ~= now then
      changedMembers[#changedMembers + 1] = gm
    end
  end
  debug("changedMembers=%s, inventoryKeys=%s", sb.print(changedMembers), sb.print(inventoryKeys))

  if #changedMembers == 1 then
    local changedId = changedMembers[1]
    chosenInventory = allInventories[changedId] or {}
    mergedKey = inventoryKeys[changedId]
    chosenMember = changedId
    debug("single group member changed; using %s as canonical", tostring(changedId))
  else
    if #groupMembers == 0 then
      chosenInventory = allInventories[entity.id()] or {}
      mergedKey = inventoryKeys[entity.id()]
      chosenMember = entity.id()
      debug("no active group members found; using leader inventory as canonical")
    elseif groupAllSame then
      chosenInventory = allInventories[groupMembers[1]] or {}
      mergedKey = inventoryKeys[groupMembers[1]]
      chosenMember = groupMembers[1]
      debug("group members match; using first group member as canonical")
    else
      local mergedGroupInventories = {}
      local seenInvKeys = {}
      for _, memberId in ipairs(groupMembers) do
        local inv = allInventories[memberId] or {}
        local invKey = inventoryGroupKey(inv)
        if not seenInvKeys[invKey] then
          seenInvKeys[invKey] = true
          mergedGroupInventories[#mergedGroupInventories + 1] = inv
        end
      end
      if #mergedGroupInventories == 1 then
        chosenInventory = mergedGroupInventories[1]
      else
        chosenInventory = mergeAllInventories(mergedGroupInventories)
      end
      mergedKey = inventoryGroupKey(chosenInventory)
      debug("group inventories diverged; merged canonical inventory from active group members (deduped %d sources)", #mergedGroupInventories)
    end
  end

  local freshGroup = not storage.lastMergedKey or storage.groupLeader ~= storage.canonicalMember
  if #joiners > 0 then
    local canonicalKey = mergedKey
    local joinerMismatch = false
    for _, joinerId in ipairs(joiners) do
      local joinerKey = inventoryKeys[joinerId] or ""
      if joinerKey ~= "" and joinerKey ~= canonicalKey then
        joinerMismatch = true
        break
      end
    end

    if not groupAllSame or (#groupMembers == 1 and freshGroup) or joinerMismatch then
      local joinerSources = {}
      local seenGroups = {}
      for _, joinerId in ipairs(joiners) do
        local meta = memberMeta[joinerId] or {}
        local groupKey = tostring(joinerId)
        if meta.active and meta.groupLeader and meta.groupId then
          groupKey = tostring(meta.groupLeader) .. ":" .. tostring(meta.groupId)
        end
        if not seenGroups[groupKey] then
          seenGroups[groupKey] = true
          joinerSources[#joinerSources + 1] = allInventories[joinerId] or {}
        end
      end
      if #groupMembers > 0 then
        joinerSources[#joinerSources + 1] = chosenInventory
      end
      debug("joining inventories from unique external groups: %s", sb.print(seenGroups))
      chosenInventory = mergeAllInventories(joinerSources)
      mergedKey = inventoryGroupKey(chosenInventory)
      chosenMember = nil
      debug("joined inventories merged from unique sources")
    else
      debug("joiner(s) detected while active group is stable; syncing canonical inventory to joiners only")
      storage.canonicalInventory = chosenInventory
      storage.lastMergedKey = mergedKey
      storage.canonicalMember = storage.groupLeader
      storage.memberInventoryKeys = inventoryKeys
      storage.members = allMembers
      storage.active = true
      syncToAll(joiners, chosenInventory)
      return true
    end
  end

  if not chosenInventory then
    chosenInventory = allInventories[entity.id()] or {}
    mergedKey = inventoryKeys[entity.id()]
  end

  local requiredSlots = countRequiredSlots(chosenInventory)
  if chosenMember then
    debug("chosen canonical member %s, stack count %d, required slots %d", tostring(chosenMember), #chosenInventory, requiredSlots)
  else
    debug("chosen canonical merged inventory, stack count %d, required slots %d", #chosenInventory, requiredSlots)
  end

  if mergedKey == storage.lastMergedKey and groupAllSame and #joiners == 0 then
    storage.memberInventoryKeys = inventoryKeys
    storage.members = allMembers
    storage.canonicalMember = storage.canonicalMember or storage.groupLeader
    storage.active = true
    debug("chosen canonical inventory unchanged and known members in sync; skipping apply")
    return true
  end

  if requiredSlots <= slotCount then
    debug("consolidating chosen canonical inventory")
    storage.canonicalInventory = chosenInventory
    storage.lastMergedKey = mergedKey
    storage.canonicalMember = storage.groupLeader
    storage.memberInventoryKeys = inventoryKeys
    for _, memberId in ipairs(allMembers) do
      storage.knownMembers[memberId] = true
    end
    storage.members = allMembers
    storage.active = true
    syncToAll(allMembers, chosenInventory)
    return true
  else
    debug("chosen canonical inventory exceeds slot count %d", slotCount)
    storage.memberInventoryKeys = inventoryKeys
    for _, memberId in ipairs(allMembers) do
      storage.knownMembers[memberId] = true
    end
    storage.members = allMembers
    storage.active = false
    return false
  end
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

function countInventorySlots(inventory)
  local count = 0
  for _, item in pairs(inventory) do
    if item and item.count and item.count > 0 then
      count = count + 1
    end
  end
  return count
end

function inventoryCountsAndTemplates(inventory)
  local counts = {}
  local templates = {}
  for _, item in pairs(inventory) do
    if item and item.count and item.count > 0 then
      local key = itemIdentityKey(item)
      counts[key] = (counts[key] or 0) + item.count
      if not templates[key] then
        local template = shallowCopy(item)
        template.count = 0
        templates[key] = template
      end
    end
  end
  return counts, templates
end

function inventoryDelta(baseCounts, inventory)
  local invCounts, _ = inventoryCountsAndTemplates(inventory)
  local delta = {}
  for key, count in pairs(invCounts) do
    delta[key] = count - (baseCounts[key] or 0)
  end
  for key, baseCount in pairs(baseCounts) do
    if not invCounts[key] then
      delta[key] = (delta[key] or 0) - baseCount
    end
  end
  return delta
end

function addInventoryDeltas(totalDelta, delta)
  for key, change in pairs(delta) do
    totalDelta[key] = (totalDelta[key] or 0) + change
    if totalDelta[key] == 0 then
      totalDelta[key] = nil
    end
  end
end

function applyDeltaToCounts(baseCounts, delta)
  local result = {}
  for key, count in pairs(baseCounts) do
    result[key] = count
  end
  for key, change in pairs(delta) do
    result[key] = (result[key] or 0) + change
    if result[key] <= 0 then
      result[key] = nil
    end
  end
  return result
end

function countsEqual(a, b)
  for key, count in pairs(a) do
    if b[key] ~= count then
      return false
    end
  end
  for key, count in pairs(b) do
    if a[key] ~= count then
      return false
    end
  end
  return true
end

function countsToInventory(counts, templates)
  local inventory = {}
  for key, totalCount in pairs(counts) do
    local prototype = templates[key]
    if prototype then
      local maxStack = getItemMaxStack(prototype)
      local remaining = totalCount
      while remaining > 0 do
        local stack = shallowCopy(prototype)
        stack.count = math.min(remaining, maxStack)
        inventory[#inventory + 1] = stack
        remaining = remaining - stack.count
      end
    end
  end
  return inventory
end

function collectTemplates(allInventories)
  local templates = {}
  for _, inv in pairs(allInventories) do
    if type(inv) == "table" then
      for _, item in pairs(inv) do
        if item and item.count and item.count > 0 then
          local key = itemIdentityKey(item)
          if not templates[key] then
            local template = shallowCopy(item)
            template.count = 0
            templates[key] = template
          end
        end
      end
    end
  end
  return templates
end

function inventoryGroupKey(inventory)
  local counts, _ = inventoryCountsAndTemplates(inventory)
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
  if item.parameters then
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
  local config = root.itemConfig(item)
  if config and config.config then
    return config.config.maxStack or config.config.stackSize or math.max(1, item.count or 1)
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
  
  debug("merged inventory into %d stacks", #merged)
  return merged
end

function syncToAll(members, inventory)
  members = uniqueIds(members)
  debug("syncing inventory to %d members", #members)
  
  for _, memberId in ipairs(members) do
    if not world.entityExists(memberId) then
      debug("syncToAll skipping missing member %s", tostring(memberId))
    elseif memberId == entity.id() then
      applyInventory(entity.id(), inventory)
      storage.memberInventoryKeys[entity.id()] = inventoryGroupKey(inventory)
    else
      local success, response = pcall(function()
        local promise = world.sendEntityMessage(memberId, "syncInventory", inventory, storage.groupId, storage.groupLeader, members)
        return promise:result()
      end)
      if not success then
        debug("syncToAll failed for member %s: %s", tostring(memberId), tostring(response))
      else
        debug("syncToAll succeeded for member %s", tostring(memberId))
      end
    end
  end
end

function applyInventory(targetId, inventory)
  if not world.entityExists(targetId) then
    debug("applyInventory - target %s does not exist", targetId)
    return
  end
  
  world.containerTakeAll(targetId)
  
  local applied = 0
  for _, item in pairs(inventory) do
    if item and item.count and item.count > 0 then
      world.containerAddItems(targetId, item)
      applied = applied + 1
    end
  end
  
  debug("applied %d items to %s", applied, targetId)
end

function clearInventory()
  if world.entityExists(entity.id()) then
    world.containerTakeAll(entity.id())
    debug("cleared inventory")
  end
end

function leaveGroup()
  local keeper = storage.canonicalMember or storage.groupLeader
  if entity.id() ~= keeper then
    debug("leaveGroup() clearing inventory on non-canonical object %s", tostring(entity.id()))
    clearInventory()
  else
    debug("leaveGroup() preserving inventory on canonical object %s", tostring(entity.id()))
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
  debug("left group")
end


function getConnectedNodeIds()
  local ids = {}
  
  local inputIds = nil
  local outputIds = nil
  
  if object.getInputNodeIds then
    local success, result = pcall(object.getInputNodeIds, 0)
    if success then inputIds = result end
  end
  if object.getOutputNodeIds then
    local success, result = pcall(object.getOutputNodeIds, 0)
    if success then outputIds = result end
  end
  
  if (not inputIds or next(inputIds) == nil) and (not outputIds or next(outputIds) == nil) then
    debug("No node connections exposed by wiring API; using proximity container discovery")
    return findNearbyContainers()
  end
  
  local function addNeighborsFromResult(result)
    if not result or type(result) ~= "table" then
      return
    end
    for key, value in pairs(result) do
      if type(key) == "number" and key ~= 0 then
        ids[#ids + 1] = key
      elseif type(value) == "number" and value ~= 0 then
        ids[#ids + 1] = value
      end
    end
  end

  if object.getInputNodeIds then
    for nodeIdx = 0, 4 do
      local success, result = pcall(object.getInputNodeIds, nodeIdx)
      if success and result and type(result) == "table" then
        debug("getInputNodeIds(%d) returned %s", nodeIdx, sb.print(result))
        addNeighborsFromResult(result)
      end
    end
  end
  
  if object.getOutputNodeIds then
    for nodeIdx = 0, 4 do
      local success, result = pcall(object.getOutputNodeIds, nodeIdx)
      if success and result and type(result) == "table" then
        debug("getOutputNodeIds(%d) returned %s", nodeIdx, sb.print(result))
        addNeighborsFromResult(result)
      end
    end
  end
  
  if #ids == 0 then
    debug("Wiring API did not return connections. Falling back to proximity discovery.")
    ids = findNearbyContainers()
  end
  
  return ids
end

function findNearbyContainers()
  local myPos = entity.position()
  local searchRadius = 150
  local nearby = world.entityQuery(myPos, searchRadius, { includedTypes = { "object" } })
  local containers = {}
  
  for _, entityId in ipairs(nearby) do
    if entityId ~= entity.id() and world.entityExists(entityId) then
      local objectName = world.entityName(entityId)
      if objectName == storage.containerTag then
        debug("found nearby container by name: %s", entityId)
        containers[#containers + 1] = entityId
      end
    end
  end
  
  return containers
end


function generateGroupId()
  return tostring(entity.id()) .. "_" .. tostring(math.random(100000, 999999))
end

function shallowCopy(t)
  local copy = {}
  for k, v in pairs(t) do
    copy[k] = v
  end
  return copy
end

function debug(fmt, ...)
end