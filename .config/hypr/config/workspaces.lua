-- Workspace rules wiki https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
--
-- There are deliberately no numbered rules here. They used to be generated from
-- a hardcoded list of monitors, which meant that at a desk with different
-- screens the blocks pointed at displays that were not connected: their
-- workspaces piled onto whichever monitor was left, and the new screens got one
-- ad hoc workspace each.
--
-- lib/monitors.lua now hands out NUM_WPM workspaces to every display that is
-- actually connected, on startup, on hotplug, and after a wdisplays change. Run
-- `hypr-monitors status` to see which block each screen owns, or
-- `hypr-monitors workspaces` to hand them out again by hand.
--
-- Blocks are remembered per display in monitor-slots.lua, so a screen keeps its
-- numbers across re-docking instead of dragging windows to another monitor.

hl.workspace_rule({ workspace = "name:gaming", monitor = PRIMARY_MONITOR, default = true })
