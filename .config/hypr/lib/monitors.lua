-- Hotplug monitor manager.
--
-- Layouts are remembered per monitor combination in monitor-profiles.lua, keyed
-- by the descriptions of the connected displays. Descriptions carry the serial,
-- so a screen keeps its place in the layout even after you move its cable to a
-- different port.
--
-- Arrange screens by dragging them in wdisplays (SUPER + SHIFT + M), then run
-- `hypr-monitors save` to remember that arrangement for this exact combination.

local M = {}

M.profile_path = os.getenv("HOME") .. "/.config/hypr/monitor-profiles.lua"
M.slot_path = os.getenv("HOME") .. "/.config/hypr/monitor-slots.lua"

-- Set from config/monitors.lua so the lid handler can still address the
-- built-in panel while it is disabled and therefore absent from get_monitors().
M.internal_output = nil

local function is_internal(mon)
	return mon.name:match("^eDP") ~= nil or mon.name:match("^LVDS") ~= nil or mon.name:match("^DSI") ~= nil
end

-- Hyprland matches desc: as a prefix, so an empty description would match every
-- screen and a description that is a prefix of another one would match both. In
-- either case every later spec lands on the wrong monitor, so fall back to the
-- output name when the description cannot single this screen out.
local function describe(mon)
	local desc = mon.description
	if desc == nil or desc:match("^%s*$") then
		return nil
	end
	return desc
end

local function id_of(mon, all)
	local desc = describe(mon)
	if not desc then
		return mon.name
	end
	for _, other in ipairs(all or {}) do
		local other_desc = describe(other)
		if other.name ~= mon.name and other_desc and other_desc:find(desc, 1, true) == 1 then
			return mon.name
		end
	end
	return "desc:" .. desc
end

local function split(mons)
	local externals, internals = {}, {}
	for _, mon in ipairs(mons) do
		table.insert(is_internal(mon) and internals or externals, mon)
	end
	table.sort(externals, function(a, b)
		return a.name < b.name
	end)
	return externals, internals
end

---------------------
---- MODE PICKER ----
---------------------

-- Highest resolution, then highest refresh rate at that resolution. Asking a
-- panel for a mode it cannot do leaves DRM retrying the modeset forever, so
-- never hand Hyprland a mode that is not in this list.
function M.best_mode(mon)
	local best
	for _, mode in ipairs(mon.available_modes or {}) do
		local bigger = best == nil or (mode.width * mode.height) > (best.width * best.height)
		local faster = best ~= nil
			and mode.width == best.width
			and mode.height == best.height
			and mode.refresh_rate > best.refresh_rate
		if bigger or faster then
			best = mode
		end
	end
	if not best then
		return "preferred", mon.width, mon.height
	end
	return string.format("%dx%d@%.3f", best.width, best.height, best.refresh_rate), best.width, best.height
end

---------------------
---- AUTO LAYOUT ----
---------------------

-- Fallback for a monitor combination that has not been saved yet: externals in
-- a row, built-in panel centred underneath them.
function M.auto_layout(mons)
	local externals, internals = split(mons)
	local specs, x, row_height = {}, 0, 0

	for _, mon in ipairs(externals) do
		local mode, width, height = M.best_mode(mon)
		specs[#specs + 1] = { output = id_of(mon, mons), mode = mode, position = x .. "x0", scale = 1 }
		x = x + width
		row_height = math.max(row_height, height)
	end

	for _, mon in ipairs(internals) do
		local mode, width = M.best_mode(mon)
		local pos_x = math.max(0, math.floor((x - width) / 2))
		specs[#specs + 1] = { output = id_of(mon, mons), mode = mode, position = pos_x .. "x" .. row_height, scale = 1 }
	end

	return specs
end

-----------------------
---- PROFILE STORE ----
-----------------------

function M.signature(mons)
	local names = {}
	for _, mon in ipairs(mons) do
		names[#names + 1] = describe(mon) or mon.name
	end
	table.sort(names)
	return table.concat(names, " + ")
end

local function read_profiles()
	local chunk = loadfile(M.profile_path)
	if not chunk then
		return {}
	end
	local ok, data = pcall(chunk)
	if ok and type(data) == "table" then
		return data
	end
	return {}
end

local function literal(value)
	if type(value) == "number" or type(value) == "boolean" then
		return tostring(value)
	end
	return string.format("%q", tostring(value))
end

local FIELDS = { "output", "mode", "position", "scale", "transform", "vrr", "mirror", "disabled" }

local function write_profiles(profiles)
	local keys = {}
	for key in pairs(profiles) do
		keys[#keys + 1] = key
	end
	table.sort(keys)

	local out = {
		"-- Written by `hypr-monitors save`. Hand-editing is fine.",
		"-- One entry per monitor combination, keyed by the connected displays.",
		"return {",
	}
	for _, key in ipairs(keys) do
		out[#out + 1] = string.format("\t[%q] = {", key)
		for _, spec in ipairs(profiles[key]) do
			local fields = {}
			for _, field in ipairs(FIELDS) do
				if spec[field] ~= nil then
					fields[#fields + 1] = field .. " = " .. literal(spec[field])
				end
			end
			out[#out + 1] = "\t\t{ " .. table.concat(fields, ", ") .. " },"
		end
		out[#out + 1] = "\t},"
	end
	out[#out + 1] = "}"

	local file, err = io.open(M.profile_path, "w")
	if not file then
		return false, err
	end
	file:write(table.concat(out, "\n") .. "\n")
	file:close()
	return true
end

function M.profiles()
	return read_profiles()
end

------------------------
---- APPLY AND SAVE ----
------------------------

function M.apply()
	local mons = hl.get_monitors()
	if #mons == 0 then
		return "no monitors connected"
	end

	for _, mon in ipairs(mons) do
		if is_internal(mon) then
			M.internal_output = id_of(mon, mons)
		end
	end

	local signature = M.signature(mons)
	local specs = read_profiles()[signature]
	local source = "saved"
	if not specs then
		specs = M.auto_layout(mons)
		source = "auto"
	end

	local hint = {}
	for _, spec in ipairs(specs) do
		hl.monitor(spec)
		local x, y = tostring(spec.position or ""):match("^(%-?%d+)x(%-?%d+)$")
		if x and not spec.disabled then
			hint[spec.output] = { x = tonumber(x), y = tonumber(y) }
		end
	end
	return source .. ": " .. signature, hint
end

function M.save()
	local mons = hl.get_monitors()
	if #mons == 0 then
		return "nothing to save, no monitors connected"
	end

	local specs = {}
	for _, mon in ipairs(mons) do
		specs[#specs + 1] = {
			output = id_of(mon, mons),
			mode = string.format("%dx%d@%.3f", mon.width, mon.height, mon.refresh_rate),
			position = string.format("%dx%d", mon.x, mon.y),
			scale = mon.scale,
			transform = mon.transform ~= 0 and mon.transform or nil,
		}
	end

	local profiles = read_profiles()
	local signature = M.signature(mons)
	profiles[signature] = specs

	local ok, err = write_profiles(profiles)
	if not ok then
		return "could not write " .. M.profile_path .. ": " .. tostring(err)
	end
	return "saved " .. #specs .. " display(s) for: " .. signature
end

function M.forget()
	local mons = hl.get_monitors()
	local signature = M.signature(mons)
	local profiles = read_profiles()
	if not profiles[signature] then
		return "no saved profile for: " .. signature
	end
	profiles[signature] = nil
	local ok, err = write_profiles(profiles)
	if not ok then
		return "could not write " .. M.profile_path .. ": " .. tostring(err)
	end
	return "forgot profile for: " .. signature
end

function M.status()
	local mons = hl.get_monitors()
	local signature = M.signature(mons)
	local lines = { "combination: " .. signature }
	lines[#lines + 1] = "profile:     " .. (read_profiles()[signature] and "saved" or "not saved (auto layout in use)")
	local per = tonumber(NUM_WPM) or 3
	local slots = M.slots()
	for _, mon in ipairs(M.monitor_order()) do
		local block = slots[id_of(mon, mons)]
		local ws = "unassigned"
		if block then
			ws = string.format("%d-%d", (block - 1) * per + 1, (block - 1) * per + per)
		end
		lines[#lines + 1] = string.format(
			"  %-10s %dx%d@%.2f  at %d,%d  scale %s  ws %-7s%s",
			mon.name,
			mon.width,
			mon.height,
			mon.refresh_rate,
			mon.x,
			mon.y,
			tostring(mon.scale),
			ws,
			is_internal(mon) and "  (built-in)" or ""
		)
	end
	return table.concat(lines, "\n")
end

-------------------------
---- WORKSPACE SLOTS ----
-------------------------

-- Display order: the built-in panel first, then externals left to right. The
-- panel is the one screen always present, so anchoring the lowest workspaces to
-- it keeps 1..NUM_WPM meaning the same thing whether you are docked or not.
-- `hint` maps a monitor id to the position it is being moved to. Ordering read
-- straight off hl.get_monitors() races the repositioning it is meant to follow,
-- and because blocks are remembered a single stale read sticks permanently, so
-- apply() passes the positions it is in the middle of setting.
function M.monitor_order(hint)
	local mons = hl.get_monitors()
	local externals, internals = {}, {}
	for _, mon in ipairs(mons) do
		table.insert(is_internal(mon) and internals or externals, mon)
	end

	local function pos(mon)
		local at = hint and hint[id_of(mon, mons)]
		if at then
			return at.x, at.y
		end
		return mon.x, mon.y
	end

	table.sort(externals, function(a, b)
		local ax, ay = pos(a)
		local bx, by = pos(b)
		if ax ~= bx then
			return ax < bx
		end
		return ay < by
	end)

	local ordered = {}
	for _, mon in ipairs(internals) do
		ordered[#ordered + 1] = mon
	end
	for _, mon in ipairs(externals) do
		ordered[#ordered + 1] = mon
	end
	return ordered, mons
end

local function read_slots()
	local chunk = loadfile(M.slot_path)
	if not chunk then
		return {}
	end
	local ok, data = pcall(chunk)
	if ok and type(data) == "table" then
		return data
	end
	return {}
end

local function write_slots(slots)
	local keys = {}
	for key in pairs(slots) do
		keys[#keys + 1] = key
	end
	table.sort(keys)

	local out = {
		"-- Written by lib/monitors.lua. Hand-editing is fine.",
		"-- Which block of workspaces each display owns: block 1 is workspaces",
		"-- 1..NUM_WPM, block 2 the next NUM_WPM, and so on. A display keeps its",
		"-- block once allocated, so numbering does not shuffle as you re-dock.",
		"return {",
	}
	for _, key in ipairs(keys) do
		out[#out + 1] = string.format("\t[%q] = %d,", key, slots[key])
	end
	out[#out + 1] = "}"

	local file, err = io.open(M.slot_path, "w")
	if not file then
		return false, err
	end
	file:write(table.concat(out, "\n") .. "\n")
	file:close()
	return true
end

function M.slots()
	return read_slots()
end

-- Gives every connected display exactly NUM_WPM workspaces of its own.
--
-- A display keeps whatever block it already owns, and only a display with no
-- block, or whose block is claimed by another screen that is also connected,
-- gets a new one. That stability is the point: compacting the numbering on
-- every change would drag windows between screens every time you dock.
function M.assign_workspaces(hint)
	local per = tonumber(NUM_WPM) or 3
	local ordered, mons = M.monitor_order(hint)
	if #ordered == 0 then
		return "no monitors connected"
	end

	local slots = read_slots()
	local taken, assigned, ids = {}, {}, {}

	for _, mon in ipairs(ordered) do
		ids[mon] = id_of(mon, mons)
	end

	-- Pass one: honour blocks already owned by a connected display.
	for _, mon in ipairs(ordered) do
		local block = slots[ids[mon]]
		if block and not taken[block] then
			taken[block] = true
			assigned[mon] = block
		end
	end

	-- Pass two: everything still unassigned takes the lowest free block, in
	-- display order. Blocks owned by disconnected screens are free, so a
	-- different desk numbers from 1 again rather than drifting upwards.
	for _, mon in ipairs(ordered) do
		if not assigned[mon] then
			local block = 1
			while taken[block] do
				block = block + 1
			end
			taken[block] = true
			assigned[mon] = block
			slots[ids[mon]] = block
		end
	end

	-- Rules decide where a workspace *opens*, so they are not enough on their
	-- own: workspaces that already exist have to be relocated explicitly or
	-- they stay wherever they were stranded when their old monitor vanished.
	local want_monitor = {}
	for _, mon in ipairs(ordered) do
		local first = (assigned[mon] - 1) * per + 1
		for k = 0, per - 1 do
			local id = first + k
			want_monitor[id] = mon.name
			hl.workspace_rule({
				workspace = tostring(id),
				monitor = ids[mon],
				persistent = true,
				default = k == 0,
			})
		end
	end

	local moved = 0
	for _, ws in ipairs(hl.get_workspaces()) do
		local want = want_monitor[ws.id]
		if want and ws.monitor and ws.monitor.name ~= want then
			hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(ws.id), monitor = want }))
			moved = moved + 1
		end
	end

	write_slots(slots)

	local summary = {}
	for _, mon in ipairs(ordered) do
		local first = (assigned[mon] - 1) * per + 1
		summary[#summary + 1] = string.format("%s=%d-%d", mon.name, first, first + per - 1)
	end
	return string.format("%d x %d workspaces (%s), %d moved", #ordered, per, table.concat(summary, " "), moved)
end

-----------------
---- HOTPLUG ----
-----------------

-- Plugging in a dock fires monitor.added once per screen, so collapse a burst
-- of events into a single layout pass.
local pending = false
local pending_ws = false

function M.schedule(delay)
	if pending then
		return
	end
	pending = true
	hl.timer(function()
		pending = false
		local _, hint = M.apply()
		-- Ordered by the positions apply() just set, not by live geometry,
		-- which may not have caught up yet.
		M.schedule_workspaces(200, hint)
	end, { timeout = delay or 250, type = "oneshot" })
end

-- Workspaces only, leaving the layout untouched. This is the path for a change
-- that did not alter which displays are connected, such as dragging screens
-- around in wdisplays: re-applying a profile there would undo the drag.
function M.schedule_workspaces(delay, hint)
	if pending_ws then
		return
	end
	pending_ws = true
	hl.timer(function()
		pending_ws = false
		M.assign_workspaces(hint)
	end, { timeout = delay or 250, type = "oneshot" })
end

-------------
---- LID ----
-------------

-- Closing the lid drops the built-in panel out of the layout, but only while an
-- external screen is connected, otherwise you would be left with no display.
function M.lid_closed()
	local externals = select(1, split(hl.get_monitors()))
	if #externals == 0 then
		return "lid closed, keeping built-in panel on (no external display)"
	end
	local output = M.internal_output
	if not output then
		return "lid closed, no built-in panel to disable"
	end
	hl.monitor({ output = output, disabled = true })
	return "lid closed, disabled " .. output
end

function M.lid_opened()
	local output = M.internal_output
	if not output then
		return "lid opened, no built-in panel known"
	end
	hl.monitor({ output = output, disabled = false })
	M.schedule(250)
	return "lid opened, enabled " .. output
end

return M
