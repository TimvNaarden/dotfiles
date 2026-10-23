--!nonstrict
-- Deskpad / Notes - a desktop widget that shows one note from the folder the
-- noctalia/notes plugin writes to.
--
-- It owns no storage of its own on purpose: the panel is still the only place
-- that edits a note, and a desktop widget is a background layer-shell surface
-- that can never take keyboard focus, so a card that pretended to be editable
-- would be a lie. Clicking the card hands off to noctalia/notes:panel.
--
-- The tick only stats the file; the note is re-read when its mtime moves, so a
-- card left open all day costs one fileInfo call every few seconds.

local POLL_MS = 4000
local ELLIPSIS = "…"

local currentName = ""  -- file name inside the notes dir, "" when there is none
local currentMtime = -1
local currentSize = -1
local body = ""
local missing = true

-- fileInfo.mtime is a double built from a nanosecond timestamp, and two stats of
-- an untouched file can differ in the last ULP, so exact equality would report a
-- change on every tick. A millisecond tolerance is far below any edit interval
-- and far above that jitter; the size catches a same-millisecond rewrite.
local function unchanged(mtime, size)
  return size == currentSize and math.abs(mtime - currentMtime) < 0.002
end

local function cfg(key, fallback)
  local value = noctalia.getConfig(key)
  if value == nil or value == "" then
    return fallback
  end
  return value
end

local function notesDir()
  local dir = noctalia.expandPath(cfg("notes_dir", "~/Documents/Notes"))
  return (dir:gsub("/+$", ""))
end

local function suffix()
  local ext = noctalia.string.trim(tostring(cfg("extension", "md")))
  ext = ext:gsub("^%.", "")
  if ext == "" then
    ext = "md"
  end
  return "." .. ext
end

local function hasSuffix(name, sfx)
  return #name > #sfx and name:sub(-#sfx) == sfx
end

-- Which note this card shows. A configured name wins (with or without the
-- extension); otherwise the most recently touched note, so the card follows
-- whatever is being worked on.
local function pickNote()
  local sfx = suffix()
  local want = noctalia.string.trim(tostring(cfg("note_file", "")))
  if want ~= "" then
    if not hasSuffix(want, sfx) then
      want = want .. sfx
    end
    return want
  end

  local list = noctalia.listDir(notesDir())
  if list == nil then
    return ""
  end
  local best, bestMtime = "", -1
  for _, name in ipairs(list) do
    if hasSuffix(name, sfx) and name:sub(1, 1) ~= "." then
      local info = noctalia.fileInfo(notesDir() .. "/" .. name)
      if info ~= nil and not info.isDir and info.mtime > bestMtime then
        best, bestMtime = name, info.mtime
      end
    end
  end
  return best
end

local function titleOf(name)
  local sfx = suffix()
  if hasSuffix(name, sfx) then
    return name:sub(1, #name - #sfx)
  end
  return name
end

-- Keeps at most `max_lines` lines, dropping the leading blank ones so a note
-- that starts with an empty line does not waste half the card.
local function clamp(text, maxLines)
  local kept, count, truncated = {}, 0, false
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    if count > 0 or noctalia.string.trim(line) ~= "" then
      if count >= maxLines then
        truncated = true
        break
      end
      table.insert(kept, line)
      count = count + 1
    end
  end
  while #kept > 0 and noctalia.string.trim(kept[#kept]) == "" do
    table.remove(kept)
  end
  local out = table.concat(kept, "\n")
  if truncated then
    out = out .. "\n" .. ELLIPSIS
  end
  return out
end

local function reload(force)
  local name = pickNote()
  if name == "" then
    currentName, currentMtime, currentSize, body, missing = "", -1, -1, "", true
    return true
  end

  local path = notesDir() .. "/" .. name
  local info = noctalia.fileInfo(path)
  if info == nil then
    if not missing or currentName ~= name then
      currentName, currentMtime, currentSize, body, missing = name, -1, -1, "", true
      return true
    end
    return false
  end

  if not force and name == currentName and not missing and unchanged(info.mtime, info.size) then
    return false
  end

  local contents = noctalia.readFile(path)
  currentName = name
  currentMtime = info.mtime
  currentSize = info.size
  body = contents or ""
  missing = contents == nil
  return true
end

local function openPanel()
  noctalia.togglePanel("noctalia/notes:panel")
end

local function render()
  local width = tonumber(cfg("card_width", 360)) or 360
  local fontSize = tonumber(cfg("font_size", 13)) or 13
  local maxLines = tonumber(cfg("max_lines", 12)) or 12
  local alpha = (tonumber(cfg("background_opacity", 70)) or 70) / 100
  local children = {}

  if cfg("show_title", true) ~= false then
    table.insert(children, ui.row({ gap = 8, align = "center" }, {
      ui.glyph({ name = "notes", size = fontSize + 4, color = "primary" }),
      ui.label({
        text = currentName ~= "" and titleOf(currentName) or noctalia.tr("notes.title"),
        fontSize = fontSize + 1,
        fontWeight = "bold",
        color = "on_surface",
        maxLines = 1,
        flexGrow = 1,
      }),
    }))
    table.insert(children, ui.separator({ color = "outline", thickness = 1, spacing = 2 }))
  end

  local text = clamp(body, maxLines)
  if currentName == "" then
    table.insert(children, ui.label({
      text = noctalia.tr("notes.no_notes"),
      fontSize = fontSize,
      color = "on_surface_variant",
    }))
  elseif missing then
    table.insert(children, ui.label({
      text = noctalia.tr("notes.unreadable", { file = currentName }),
      fontSize = fontSize,
      color = "error",
      maxLines = 2,
    }))
  elseif noctalia.string.trim(text) == "" then
    table.insert(children, ui.label({
      text = noctalia.tr("notes.empty"),
      fontSize = fontSize,
      color = "on_surface_variant",
    }))
  elseif cfg("render_markdown", true) ~= false then
    table.insert(children, ui.markdown({ text = text }))
  else
    table.insert(children, ui.label({
      text = text,
      fontSize = fontSize,
      color = "on_surface",
      maxLines = maxLines,
    }))
  end

  desktopWidget.render(ui.column({
    width = width,
    gap = 8,
    padding = 14,
    radius = 16,
    fill = "surface/" .. string.format("%.2f", alpha),
    border = "outline/0.45",
    borderWidth = 1,
    onClick = openPanel,
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
