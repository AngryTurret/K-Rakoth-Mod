function init()
  object.setInteractive(true)
end

function onInteraction(interactSource)
  world.sendEntityMessage(interactSource.sourceId, "deployMech")
end