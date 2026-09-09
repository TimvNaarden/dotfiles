-- Monitor wiki https://wiki.hypr.land/Configuring/Basics/Monitors/
--
-- Positions are not hardcoded here. lib/monitors.lua applies a layout for
-- whatever combination of displays is currently connected, remembered per
-- combination in monitor-profiles.lua.
--
--   SUPER + SHIFT + M   open wdisplays and drag the screens where you want them
--   hypr-monitors save  remember that arrangement for this combination
--   hypr-monitors       show the other commands

local monitors = require("lib.monitors")

-- Safety net for a display that no profile covers: light it up with its
-- preferred mode next to the others rather than leaving it black. More specific
-- rules applied at runtime take precedence over this one.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

-- Lets the lid handler address the built-in panel while it is disabled and so
-- missing from hl.get_monitors().
monitors.internal_output = MONITOR1

-- Re-layout on startup, on reload, and whenever a display comes or goes.
hl.on("hyprland.start", function()
	monitors.schedule(500)
end)

hl.on("config.reloaded", function()
	monitors.schedule(250)
end)

hl.on("monitor.added", function()
	monitors.schedule(250)
end)

hl.on("monitor.removed", function()
	monitors.schedule(250)
end)

-- A change that did not alter which displays are connected, which is what
-- dragging screens around in wdisplays produces. Only the workspace blocks are
-- re-checked here: re-applying a profile would undo the drag you just applied.
hl.on("monitor.layout_changed", function()
	monitors.schedule_workspaces(400)
end)

-- Lid switch. locked = true so it still fires while the session is locked.
-- The built-in panel is only dropped while an external display is connected.
hl.bind("switch:on:Lid Switch", function()
	monitors.lid_closed()
end, { locked = true, description = "Lid closed: disable built-in panel" })

hl.bind("switch:off:Lid Switch", function()
	monitors.lid_opened()
end, { locked = true, description = "Lid opened: enable built-in panel" })
