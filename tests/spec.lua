-- nvim --headless --clean --cmd 'set rtp^=.' -l tests/spec.lua
-- With devhub.nvim's gui stubbed: gui.document records what it is given.
-- The commands, the live update (debounced), the scroll sync, one preview
-- per buffer or one that follows, closing with the buffer, auto_open.
-- Leaves Neovim with an error on failure.
local failures = {}
local function check(ok, what)
  if not ok then
    table.insert(failures, what)
  end
end

vim.opt.rtp:prepend(vim.fn.getcwd())
vim.cmd 'runtime plugin/markdown-preview.lua'

local docs = {}
local has_document = true
package.loaded['devhub'] = {
  gui = {
    has_document = function()
      return has_document
    end,
    document = function(opts)
      local d = { opts = opts, text = opts.text, base = opts.base, updates = 0, scrolls = {}, open = true }
      function d:update(text, base)
        self.updates = self.updates + 1
        self.text, self.base = text, base or self.base
      end
      function d:scroll_to(line)
        table.insert(self.scrolls, line)
      end
      function d:is_open()
        return self.open
      end
      function d:close()
        self.open = false
        if opts.on_close then
          opts.on_close(self)
        end
      end
      table.insert(docs, d)
      return d
    end,
  },
}

local mp = require 'markdown-preview'
mp.setup { debounce = 20 }

check(vim.fn.exists ':MarkdownPreview' == 2, ':MarkdownPreview')
check(vim.fn.exists ':MarkdownPreviewStop' == 2, ':MarkdownPreviewStop')
check(vim.fn.exists ':MarkdownPreviewToggle' == 2, ':MarkdownPreviewToggle')

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, 'p')
local lines = { '# Title', '' }
for i = 1, 200 do
  table.insert(lines, 'line ' .. i)
end
vim.fn.writefile(lines, dir .. '/notes.md')
vim.fn.writefile({ '# Other' }, dir .. '/other.md')
vim.cmd.edit(dir .. '/notes.md')
local notes = vim.api.nvim_get_current_buf()
check(vim.bo.filetype == 'markdown', 'a markdown buffer')

-- Opened: the whole text, the file's folder, its name, beside the window.
vim.cmd 'MarkdownPreview'
local d = docs[1]
check(d ~= nil, 'a document opened')
check(d and d.text == table.concat(lines, '\n'), 'the buffer\'s text')
check(d and d.base == vim.fn.resolve(dir) or d and d.base == dir, 'the file\'s folder: ' .. tostring(d and d.base))
check(d and d.opts.title == 'notes.md' and d.opts.split == 'right' and d.opts.format == 'markdown', 'title, split, format')
check(d and d.opts.scroll.line == 1 and d.opts.remote_images == false, 'starts at the top; no pictures from the web')
check(mp.is_open(), 'is_open')
vim.cmd 'MarkdownPreview'
check(#docs == 1, 'asked again: the same preview')

-- Typing: the text again once it pauses, once.
vim.api.nvim_buf_set_lines(notes, 0, 1, false, { '# Changed' })
vim.api.nvim_exec_autocmds('TextChanged', { buffer = notes })
vim.api.nvim_buf_set_lines(notes, 1, 2, false, { 'more' })
vim.api.nvim_exec_autocmds('TextChanged', { buffer = notes })
check(d.updates == 0, 'debounced: not at once')
vim.wait(500, function()
  return d.updates > 0
end)
check(d.updates == 1 and d.text:sub(1, 15) == '# Changed\nmore\n', 'the edit, in one update')

-- Scrolling the editor: the preview's top follows its top line.
vim.o.lines = 30
vim.cmd 'normal! 100Gzt'
vim.api.nvim_exec_autocmds('WinScrolled', {})
check(d.scrolls[#d.scrolls] == 100, 'scroll synced to the top line: ' .. tostring(d.scrolls[#d.scrolls]))
local count = #d.scrolls
vim.api.nvim_exec_autocmds('CursorMoved', { buffer = notes })
check(#d.scrolls == count, 'no scroll when the top did not move')

-- Another buffer: a preview of its own (follow = false).
vim.cmd.edit(dir .. '/other.md')
local other = vim.api.nvim_get_current_buf()
vim.cmd 'MarkdownPreview'
check(#docs == 2 and docs[2].text == '# Other', 'one preview per buffer')
vim.cmd 'MarkdownPreviewToggle'
check(not docs[2].open and not mp.is_open(other), 'toggled closed')
vim.cmd 'MarkdownPreviewToggle'
check(#docs == 3 and docs[3].open, 'toggled open again')

-- q in the preview (it closed itself): forgotten, and opened anew after.
docs[3]:close()
check(not mp.is_open(other), 'closed from the preview: let go')

-- Its buffer wiped: the preview closes.
vim.cmd.buffer(notes)
check(mp.is_open(notes), 'the first preview still open')
vim.cmd('bwipeout! ' .. notes)
check(not d.open and not mp.is_open(notes), 'wiped: closed')

-- follow = true: one preview that goes to the Markdown buffer shown.
mp.setup { debounce = 20, follow = true }
vim.cmd.edit(dir .. '/notes.md')
notes = vim.api.nvim_get_current_buf()
vim.cmd 'MarkdownPreview'
local f = docs[#docs]
local before = #docs
vim.cmd.buffer(other)
vim.wait(200, function()
  return f.text == '# Other'
end)
check(#docs == before and f.text == '# Other' and mp.is_open(other), 'follow: the same preview shows the other buffer')
check(not mp.is_open(notes), 'follow: the first buffer has none now')
vim.cmd 'MarkdownPreviewStop'
check(not f.open, ':MarkdownPreviewStop')

-- auto_open: a Markdown buffer shown opens its preview.
mp.setup { debounce = 20, auto_open = true }
vim.cmd.edit(dir .. '/third.md')
local third = vim.api.nvim_get_current_buf()
vim.wait(200, function()
  return mp.is_open(third)
end)
check(mp.is_open(third), 'auto_open')
vim.cmd 'MarkdownPreviewStop'

-- Outside DevHub: said, and nothing opened.
mp.setup { debounce = 20 }
has_document = false
local warned
local notify = vim.notify
vim.notify = function(msg)
  warned = msg
end
local n = #docs
vim.cmd 'MarkdownPreview'
vim.notify = notify
check(#docs == n and warned and warned:find 'gui.document', 'without gui.document: a warning')

if #failures > 0 then
  io.stderr:write('FAIL\n  ' .. table.concat(failures, '\n  ') .. '\n')
  vim.cmd 'cquit 1'
end
io.stdout:write 'markdown-preview.devhub: ok\n'
vim.cmd 'qall!'
