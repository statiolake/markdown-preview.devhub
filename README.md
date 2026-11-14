# markdown-preview.devhub

A live preview of the Markdown you are editing, drawn by
[DevHub](https://github.com/statiolake/devhub) in a window beside it —
[markdown-preview.nvim](https://github.com/iamcco/markdown-preview.nvim)'s
commands, with no browser, no server and no network.

The preview is DevHub's own Markdown renderer, the one its conversations and
the Orchestrator draw with, so it reads like the rest of DevHub: GitHub's
tables and task lists, code in its language's colours, KaTeX math, Mermaid
diagrams, the same typesetting (the space between Japanese and Latin text
included), and a link's right-click menu. It follows you as you type and as
you scroll.

A DevHub extension (named `.devhub`, as Neovim plugins are `.nvim`): DevHub's
GUI is its engine, so it needs DevHub and devhub.nvim and is meant to be
loaded only there (the `cond` below).

## What it does

- **Live**: the buffer's text goes to the preview when typing pauses
  (`debounce`, 80 ms), in Normal and Insert mode alike.
- **Scroll sync, both ways**: the preview's top is the source line at the
  top of your window, and scrolling the preview (its keys, the wheel)
  scrolls your window to match. Every block of the drawing knows the source
  line it starts at and is measured where it is drawn, so a tall table,
  picture or diagram above does not throw it off; neither side echoes the
  other, so they settle together. Scrolling eases as DevHub's editor does.
- **Alt-click** in the preview takes your cursor to that place in the source
  (the line, and the column when the text clicked says it), in your window.
- **One preview per buffer**, closed when its buffer is wiped. With
  `follow = true` there is one preview, and it shows whichever Markdown
  buffer you go to.
- **Pictures** beside the file (`![](img/chart.png)`) are read where Neovim
  runs — on an SSH host too — relative to the file's folder. Pictures from
  the web are a placeholder naming their host unless you set
  `remote_images = true`: opening a file does not fetch what it names.
- **Links**: a URL opens in the browser (right-click: Open in Browser / Copy
  Link); a link to a file (`[design](design.md)`, `notes.md#L12`) opens in
  your window; `[top](#release-notes)` scrolls the preview to that heading.
- **Keys** — Neovim's, in the preview's window (`<C-w>l` into it):
  `j`/`k`, `<C-d>`/`<C-u>`, `<C-f>`/`<C-b>`, `<Space>`, `gg`/`G` scroll;
  `<Tab>`/`<S-Tab>` move between links and `<CR>` follows one; `<Esc>`
  goes back to your window; `q` closes it. `/` searches its text. The wheel
  scrolls it too; nothing needs the mouse.
- **Mouse**: drag to select the rendered text (double click a word, triple
  click a paragraph), ⌘C or the right-click menu to copy it.

## Requirements

- DevHub with `gui.document`: `a1081a36` ("gui.document: Markdown drawn by
  the conversation's renderer beside a window") added it; `48c1bb01` or
  later scrolls smoothly, syncs both ways, selects text and takes the
  Alt-click (before it, the preview follows the editor only), with Neovim as
  its editor.
- [devhub.nvim](https://github.com/statiolake/devhub.nvim) `239adf7`
  ("gui.document") or later.
- Neovim 0.10 or later (DevHub's own Neovim is 0.12).

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'statiolake/markdown-preview.devhub',
  cond = vim.env.DEVHUB_NEOVIM_GUI == '1',   -- only in DevHub's GUI
  dependencies = { 'statiolake/devhub.nvim' },
  ft = 'markdown',
  cmd = { 'MarkdownPreview', 'MarkdownPreviewStop', 'MarkdownPreviewToggle' },
  main = 'markdown-preview',
  opts = {},
}
```

Replacing markdown-preview.nvim, keep it for a terminal Neovim by giving it
the opposite `cond`; the commands have the same names.

## Commands

| Command                  | What it does                                  |
| ------------------------ | --------------------------------------------- |
| `:MarkdownPreview`       | Open the current buffer's preview beside it   |
| `:MarkdownPreviewStop`   | Close it                                      |
| `:MarkdownPreviewToggle` | Open it if it is closed, else close it        |

From Lua: `require('markdown-preview').open(buf)`, `.stop(buf)`,
`.toggle(buf)`, `.is_open(buf)` (`0`: the current buffer).

## Options

```lua
require('markdown-preview').setup {
  auto_open = false,       -- open a preview by itself for every Markdown buffer shown
  follow = false,          -- one preview that shows the Markdown buffer you go to
  split = 'right',         -- 'left' | 'below' | 'above'
  debounce = 80,           -- ms typing waits before the preview is drawn again
  sync = 'topline',        -- 'cursor': the cursor's line near the top; false: no sync
  remote_images = false,   -- draw pictures from the web
  filetypes = { 'markdown' },
  on_link = nil,           -- fn(link): a link to a file followed ({ path, line?, col? }); true if handled
  on_source_click = nil,   -- fn(pos, buf): an Alt-click in the preview ({ line, col? }); true if handled
}
```

## Not (yet) here

- The whole text is sent on each update (the renderer parses the whole
  document anyway; a diff would save little).
- `$$…$$` written on one line is drawn as inline math; put `$$` on lines of
  their own for a display block.
- A link to `other.md#heading` opens the file at its top.
- Raw HTML in the Markdown is not drawn (DevHub's renderer skips it).
- No PlantUML, no custom CSS, no export.

## Tests

```sh
nvim --headless --clean --cmd 'set rtp^=.' -l tests/spec.lua
```
