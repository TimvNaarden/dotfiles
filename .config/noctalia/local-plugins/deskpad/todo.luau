--!nonstrict
-- Deskpad / To Do - a desktop widget over the same todo.json that the
-- nightwatch75/todo bar widget and panel read and write.
--
-- The file is the contract, not a shared runtime: this widget re-reads it
-- whenever its mtime moves, and every tick goes load -> flip one task -> save,
-- so a write here never carries a stale copy of the rest of the list. Adding,
-- editing, reordering and priorities stay in the panel, which is the only
-- surface that can take the keyboard; a click on the header opens it.

local POLL_MS = 2500
local FILE_NAME = "todo.json"
local RANK = { important = 1, medium = 2, low = 3 }
-- Same three chips the nightwatch75/todo panel draws, so a task keeps its
-- colour between the panel and the desktop.
local COLORS = { important = "#e06c75", medium = "#e5c07b", low = "#98c379" }

local model = { tasks = {}, sort = "priority", hideCompleted = false, showCount = true }
local mtime = -1
local size = -1

-- fileInfo.mtime is a double built from a nanosecond timestamp, and two stats of
-- an untouched file can differ in the last ULP, so exact equality would reload on
-- every tick. A millisecond tolerance is far below any edit interval and far above
-- that jitter; the size catches a same-millisecond rewrite.
local function unchanged(newMtime, newSize)
  return newSize == size and math.abs(newMtime - mtime) < 0.002
end

local function cfg(key, fallback)
  local value = noctalia.getConfig(key)
  if value == nil or value == "" then
    return fallback
  end
  return value
end

local function filePath()
  local dir = noctalia.expandPath(cfg("todo_folder", "~/Documents/Todo"))
  return (dir:gsub("/+$", "")) .. "/" .. FILE_NAME
end

local function normalizePriority(value)
  return RANK[value] ~= nil and value or "medium"
end

-- Mirrors the reader in the todo plugin's storage.luau, including its tolerance
-- for a legacy plain-array file: a malformed or missing file reads as an empty
-- list rather than an error, because a desktop card has nowhere to report one.
local function parse(raw)
  local out = { tasks = {}, sort = "priority", hideCompleted = false, showCount = true }
  if raw == nil or raw == "" then
    return out
  end
  local decoded = noctalia.json.decode(raw)
  if type(decoded) ~= "table" then
    return out
  end

  local list = decoded
  if decoded.tasks ~= nil then
    if decoded.sort == "manual" or decoded.sort == "priority" then
      out.sort = decoded.sort
    end
    out.hideCompleted = decoded.hideCompleted == true
    out.showCount = decoded.showCount ~= false
    list = decoded.tasks
  end

  if type(list) == "table" then
    local nextId = 1
    for _, entry in ipairs(list) do
      if type(entry) == "table" then
        local id = tonumber(entry.id) or nextId
        table.insert(out.tasks, {
          id = id,
          text = type(entry.text) == "string" and entry.text or "",
          priority = normalizePriority(entry.priority),
          done = entry.done == true,
        })
        if id >= nextId then
          nextId = id + 1
        end
      end
    end
  end
  return out
end

local function readModel()
  return parse(noctalia.readFile(filePath()))
end

local function writeModel(data)
  local encoded = noctalia.json.encode({
    version = 2,
    sort = data.sort,
    hideCompleted = data.hideCompleted == true,
    showCount = data.showCount ~= false,
    tasks = data.tasks,
  }, true)
  if encoded == nil then
    return false
  end
  local ok = noctalia.writeFile(filePath(), encoded)
  return ok
end

-- Display order only; `model.tasks` always stays in the file's manual order so
-- a save from here cannot silently reorder the panel's list.
local function ordered()
  local view = {}
  for index, task in ipairs(model.tasks) do
    table.insert(view, { task = task, index = index })
  end
  if model.sort == "priority" then
    table.sort(view, function(a, b)
      local ra, rb = RANK[a.task.priority] or 2, RANK[b.task.priority] or 2
      if ra ~= rb then
        return ra < rb
      end
      return a.index < b.index
    end)
  end
  return view
end

local function openCount()
  local open = 0
  for _, task in ipairs(model.tasks) do
    if not task.done then
      open = open + 1
    end
  end
  return open
end

-- Labels have no line-through prop, so overlay U+0336 on every character.
-- utf8.codes throws on invalid UTF-8 and would re-raise on every frame until
-- the host disabled the plugin; utf8.len returns nil instead, so gate on it.
local function strike(text)
  if text == "" or utf8.len(text) == nil then
    return text
  end
  local out = {}
  for _, code in utf8.codes(text) do
    table.insert(out, utf8.char(code) .. "\u{0336}")
  end
  return table.concat(out)
end

local function reload(force)
  local info = noctalia.fileInfo(filePath())
  local newMtime = info ~= nil and info.mtime or -1
  local newSize = info ~= nil and info.size or -1
  if not force and unchanged(newMtime, newSize) then
    return false
  end
  mtime, size = newMtime, newSize
  model = readModel()
  return true
end

local render -- forward declaration: the row closures call it after a write

local function toggle(id)
  local fresh = readModel()
  local hit = false
  for _, task in ipairs(fresh.tasks) do
    if task.id == id then
      task.done = not task.done
      hit = true
      break
    end
  end
  if not hit then
    -- The panel deleted it since the last tick; just resync.
    reload(true)
    render()
    return
  end
  if writeModel(fresh) then
    model = fresh
    local info = noctalia.fileInfo(filePath())
    mtime = info ~= nil and info.mtime or -1
    size = info ~= nil and info.size or -1
  end
  render()
end

local function openPanel()
  noctalia.togglePanel("nightwatch75/todo:panel")
end

local function taskRow(task, fontSize)
  local done = task.done
  return ui.row({
    key = "task-" .. tostring(task.id),
    gap = 8,
    align = "center",
    paddingV = 2,
    onClick = function()
      toggle(task.id)
    end,
  }, {
    ui.glyph({
      name = done and "square-check" or "square",
      size = fontSize + 3,
      color = done and "on_surface_variant" or COLORS[task.priority],
    }),
    ui.label({
      text = done and strike(task.text) or task.text,
      fontSize = fontSize,
      color = done and "on_surface_variant" or "on_surface",
      maxLines = 2,
      flexGrow = 1,
    }),
  })
end

render = function()
  local width = tonumber(cfg("card_width", 320)) or 320
  local fontSize = tonumber(cfg("font_size", 13)) or 13
  local maxItems = tonumber(cfg("max_items", 8)) or 8
  local showDone = cfg("show_done", false) == true
  local alpha = (tonumber(cfg("background_opacity", 70)) or 70) / 100
  local children = {}

  if cfg("show_header", true) ~= false then
    table.insert(children, ui.row({ gap = 8, align = "center", onClick = openPanel }, {
      ui.glyph({ name = "checklist", size = fontSize + 4, color = "primary" }),
      ui.label({
        text = noctalia.tr("todo.title"),
        fontSize = fontSize + 1,
        fontWeight = "bold",
        color = "on_surface",
        flexGrow = 1,
      }),
      ui.label({
        text = tostring(openCount()),
        fontSize = fontSize,
        color = "on_surface_variant",
      }),
    }))
    table.insert(children, ui.separator({ color = "outline", thickness = 1, spacing = 2 }))
  end

  local shown, hidden = 0, 0
  for _, entry in ipairs(ordered()) do
    if showDone or not entry.task.done then
      if shown < maxItems then
        table.insert(children, taskRow(entry.task, fontSize))
        shown = shown + 1
      else
        hidden = hidden + 1
      end
    end
  end

  if shown == 0 then
    table.insert(children, ui.label({
      text = noctalia.tr("todo.empty"),
      fontSize = fontSize,
      color = "on_surface_variant",
    }))
  end

  if hidden > 0 then
    table.insert(children, ui.label({
      text = noctalia.trp("todo.more", hidden, { count = hidden }),
      fontSize = fontSize - 1,
      color = "on_surface_variant",
    }))
  end

  desktopWidget.render(ui.column({
    width = width,
    gap = 6,
    padding = 14,
    radius = 16,
    fill = "surface/" .. string.format("%.2f", alpha),
    border = "outline/0.45",
    borderWidth = 1,
  }, children))
end

function update()
  if reload(false) then
    render()
  end
end

noctalia.setUpdateInterval(POLL_MS)
reload(true)
render()
