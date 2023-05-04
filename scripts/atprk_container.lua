--By Silver Sokolova#3576
function sb_itemexists(a) return root.itemConfig(a)~=nil end
function init()
  local modded = false
  if sb_itemexists("enhancedstoragematerial") then
    modded = true
    init = nil
    require("/scripts/enhancedstorage.lua")
    object.setConfigParameter("smashOnBreak",true)
    object.setConfigParameter("scripts",{"/scripts/enhancedstorage.lua"})
    init()
    return
  end
  if root.assetJson("/interface/chests/chest9.config").gui.icRenameButton then
    modded = true
    init = nil
    require("/scripts/v6/improvedcontainer.lua")
    object.setConfigParameter("smashOnBreak",true)
    object.setConfigParameter("uiConfig","/interface/chests/chest<slots>.config")
    init()
  end
  object.setConfigParameter("smashOnBreak",modded)
end