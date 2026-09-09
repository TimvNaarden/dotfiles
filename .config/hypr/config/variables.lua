-- Hyprland default apps

TERMINAL = "kitty"
FILE_MANAGER = "dolphin"
BROWSER = "firefox"
EDITOR = "gnome-text-editor --new-window"
CALCULATOR = "gnome-calculator"
DISPLAY_SETTINGS = "wdisplays"

-- Monitors
--
-- Identify external screens by desc: rather than by port. The description
-- carries the serial, so a screen keeps its workspaces and its place in the
-- layout even after you move its cable to a different port. Run
-- `hyprctl monitors` to read the description of a newly connected display.
MONITOR1 = "eDP-1"
MONITOR2 = "desc:Philips Consumer Electronics Company PHL24E1N1100A UHB2438031078"
MONITOR3 = "desc:Philips Consumer Electronics Company PHL24E1N1100A UHB2438030843"
PRIMARY_MONITOR = MONITOR1

-- Workspaces
NUM_WPM = 3 -- Number of workspaces per monitor (Max 10)

-- Workspace blocks are no longer listed here. Hardcoding them meant that at a
-- desk with different screens the blocks pointed at absent displays. See
-- config/workspaces.lua and lib/monitors.lua.

-- How many monitors the SUPER + CONTROL + <n> focus binds cover. Position 1 is
-- the built-in panel, then externals left to right.
MONITOR_BINDS = 4
