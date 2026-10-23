# Deskpad

Two Noctalia desktop widgets over files other plugins already own:

| Widget | Reads | Written by |
| --- | --- | --- |
| `tim/deskpad:notes` | `~/Documents/Notes/*.md` | the `noctalia/notes` panel |
| `tim/deskpad:todo` | `~/Documents/Todo/todo.json` | the `nightwatch75/todo` panel |

Nothing here owns storage. A desktop widget is a background layer-shell surface
that takes clicks but never the keyboard, so writing and editing stay in the
panels; the cards show the current state and hand off with a click.

* **Notes** shows one note, rendered as markdown. Leave the `note_file` setting
  empty and the card follows whichever note was edited last; set it to a file
  name to pin one. Clicking the card opens the Notes panel.
* **To Do** lists the open tasks in the panel's own order, with the panel's
  priority colours. Clicking a row ticks or unticks it — the write is a fresh
  load, one flip, save, so it never carries a stale copy of the rest of the
  list. Clicking the header opens the To Do panel, which is where tasks are
  added, edited, reordered and prioritised.

Both cards poll: they stat the file every few seconds and only re-read when it
actually moved. `fileInfo.mtime` is a double built from a nanosecond timestamp
and jitters in the last ULP between two stats of an untouched file, so the
comparison uses a millisecond tolerance plus the file size, never equality.

## Installing

The plugin is served straight from this folder, no materialisation step:

```sh
noctalia msg plugins source add local path ~/.config/noctalia/local-plugins
noctalia msg plugins enable tim/deskpad
```

Editing a `.luau` file here reloads the widget in place; a change to
`plugin.toml` needs `noctalia msg config-reload`.

## Placing a card

`noctalia msg desktop-widgets-edit` opens the editor: drag, resize, change the
per-widget settings, then `noctalia msg desktop-widgets-exit`. The placements
live in `~/.local/state/noctalia/settings.toml` under `[desktop_widgets]`.
