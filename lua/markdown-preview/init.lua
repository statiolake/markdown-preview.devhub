-- markdown-preview.devhub: a live preview of the Markdown being edited,
-- drawn by DevHub beside the window — markdown-preview.nvim's commands,
-- with no browser and no server.
--
-- DevHub renders it (devhub.nvim's gui.document: the renderer of DevHub's
-- own conversations, its tables, task lists, code colouring, math and
-- Mermaid); this plugin only decides what to show and when. It sends the
-- buffer's text when it changes (debounced), keeps the preview's top at the
-- source line the editor's window has at its top (each block of the drawing
-- knows the source line it starts at), and closes the preview with its
-- buffer. Pictures and linked files are found relative to the file, on the
-- machine Neovim runs on (an SSH host's too), and nothing is fetched.
--
-- A DevHub extension: it needs DevHub's GUI and devhub.nvim, and is loaded
-- only there.

local M = {}

---@class markdown_preview.Config
local defaults = {
  -- Open a preview by itself for every Markdown buffer shown.
  auto_open = false,
  -- One preview that goes with you: shown another Markdown buffer, it
  -- shows that one (else each buffer keeps its own preview).
  follow = false,
  -- Where the preview opens: 'right' | 'left' | 'below' | 'above'.
  split = 'right',
  -- How long typing waits before the preview is drawn again, in ms.
  debounce = 80,
  -- 'topline': the preview's top follows the window's top line; 'cursor':
  -- it keeps the cursor's line a few lines from its top; false: it stays.
  sync = 'topline',
  -- Draw pictures from the web (default: a placeholder; a local file is
  -- always drawn).
  remote_images = false,
  -- The filetypes that are Markdown.
  filetypes = { 'markdown' },
  -- fn(link): a link to a file followed in the preview (link = { path,
  -- line?, col? }); return true when you handled it. Default: the file
  -- opens in the window the preview was opened from.
  on_link = nil,
}

M.config = vim.deepcopy(defaults)

-- The open previews, by source buffer: { doc, buf, group, timer, line }.
local previews = {}
M._previews = previews

local function gui()
  local ok, devhub = pcall(require, 'devhub')
  return ok and devhub.gui or nil
end

local function is_markdown(buf)
  return vim.api.nvim_buf_is_valid(buf) and vim.tbl_contains(M.config.filetypes, vim.bo[buf].filetype)
end

local function text_of(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
end

local function base_of(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == '' then
    return vim.fn.getcwd()
  end
  return vim.fn.fnamemodify(name, ':p:h')
end

local function title_of(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  return name == '' and 'preview' or vim.fn.fnamemodify(name, ':t')
end

local function open_preview(p)
  return p and p.doc and p.doc:is_open() ~= false
end

--- The source line the preview should have at its top, for buf's window.
local function wanted_line(buf)
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) ~= buf then
    win = vim.fn.win_findbuf(buf)[1]
  end
  if not win then
    return nil
  end
  if M.config.sync == 'cursor' then
    return math.max(1, vim.api.nvim_win_get_cursor(win)[1] - 3)
  end
  return vim.fn.line('w0', win)
end

local function sync(p)
  if not M.config.sync or not open_preview(p) then
    return
  end
  local line = wanted_line(p.buf)
  if line and line ~= p.line then
    p.line = line
    p.doc:scroll_to(line)
  end
end

local function stop_timer(p)
  if p.timer then
    p.timer:stop()
    p.timer:close()
    p.timer = nil
  end
end

-- The text again, once typing has paused for config.debounce ms.
local function schedule_update(p)
  if not p.timer then
    p.timer = vim.uv.new_timer()
  end
  p.timer:stop()
  p.timer:start(
    M.config.debounce,
    0,
    vim.schedule_wrap(function()
      if previews[p.buf] ~= p or not open_preview(p) or not vim.api.nvim_buf_is_valid(p.buf) then
        return
      end
      local tick = vim.b[p.buf].changedtick
      if tick == p.tick then
        return
      end
      p.tick = tick
      p.doc:update(text_of(p.buf), base_of(p.buf))
      sync(p)
    end)
  )
end

local forget

-- The autocmds that tie a preview to its source buffer.
local function watch(p)
  p.group = vim.api.nvim_create_augroup('markdown_preview_' .. p.buf, { clear = true })
  local buf = p.buf
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'TextChangedP' }, {
    group = p.group,
    buffer = buf,
    callback = function()
      schedule_update(p)
    end,
  })
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'WinScrolled' }, {
    group = p.group,
    callback = function(ev)
      if ev.event == 'WinScrolled' or ev.buf == buf then
        sync(p)
      end
    end,
  })
  vim.api.nvim_create_autocmd('BufFilePost', {
    group = p.group,
    buffer = buf,
    callback = function()
      p.doc:update(text_of(buf), base_of(buf))
    end,
  })
  vim.api.nvim_create_autocmd({ 'BufWipeout', 'BufDelete' }, {
    group = p.group,
    buffer = buf,
    callback = function()
      M.stop(buf)
    end,
  })
end

forget = function(p)
  stop_timer(p)
  if p.group then
    pcall(vim.api.nvim_del_augroup_by_id, p.group)
    p.group = nil
  end
  if previews[p.buf] == p then
    previews[p.buf] = nil
  end
end

--- The preview that follows (config.follow): there is at most one.
local function following()
  for _, p in pairs(previews) do
    if open_preview(p) then
      return p
    end
  end
end

--- Point the following preview at buf.
local function retarget(p, buf)
  forget(p)
  p.buf, p.tick, p.line = buf, vim.b[buf].changedtick, nil
  previews[buf] = p
  watch(p)
  p.doc:update(text_of(buf), base_of(buf))
  sync(p)
end

--- Open the preview of buf (0: the current one), or bring it up to date.
function M.open(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local g = gui()
  if not g or not g.document or not (g.has_document and g.has_document()) then
    vim.notify('markdown-preview.devhub: needs DevHub\'s GUI with gui.document (devhub.nvim)', vim.log.levels.WARN)
    return nil
  end
  local p = previews[buf]
  if open_preview(p) then
    sync(p)
    return p.doc
  end
  if p then
    forget(p)
  end
  if M.config.follow then
    local other = following()
    if other then
      retarget(other, buf)
      return other.doc
    end
  end
  p = { buf = buf, tick = vim.b[buf].changedtick }
  p.doc = g.document {
    text = text_of(buf),
    format = 'markdown',
    base = base_of(buf),
    title = title_of(buf),
    split = M.config.split,
    remote_images = M.config.remote_images,
    on_link = M.config.on_link,
    scroll = { line = wanted_line(buf) or 1 },
    on_close = function()
      -- q, :close: let go of it (not when it was this plugin's own stop).
      if previews[p.buf] == p then
        forget(p)
      end
    end,
  }
  if not p.doc then
    return nil
  end
  p.line = wanted_line(buf)
  previews[buf] = p
  watch(p)
  return p.doc
end

--- Close the preview of buf (0: the current one).
function M.stop(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local p = previews[buf]
  if not p then
    return
  end
  forget(p)
  if p.doc and p.doc:is_open() ~= false then
    p.doc:close()
  end
end

--- Open it if it is not open, else close it.
function M.toggle(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  if open_preview(previews[buf]) then
    M.stop(buf)
  else
    M.open(buf)
  end
end

--- Whether buf (0: the current one) has its preview open.
function M.is_open(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  return open_preview(previews[buf]) == true
end

local setup_group

---@param opts? markdown_preview.Config
function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
  setup_group = vim.api.nvim_create_augroup('markdown_preview', { clear = true })
  -- Shown another Markdown buffer: the following preview shows it, and
  -- auto_open opens one for a buffer that has none.
  vim.api.nvim_create_autocmd({ 'BufWinEnter', 'BufEnter', 'FileType' }, {
    group = setup_group,
    callback = function(ev)
      local buf = ev.buf
      if not is_markdown(buf) or vim.bo[buf].buftype ~= '' then
        return
      end
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_get_current_buf() ~= buf then
          return
        end
        if open_preview(previews[buf]) then
          return
        end
        local other = M.config.follow and following()
        if other then
          retarget(other, buf)
        elseif M.config.auto_open then
          M.open(buf)
        end
      end)
    end,
  })
  if M.config.auto_open then
    local buf = vim.api.nvim_get_current_buf()
    if is_markdown(buf) and vim.bo[buf].buftype == '' then
      vim.schedule(function()
        M.open(buf)
      end)
    end
  end
end

return M
