local fn = vim.fn
local api = vim.api

local M = {}
local NS = api.nvim_create_namespace('jump')
local CR = api.nvim_replace_termcodes('<Cr>', true, true, true)
local BS = api.nvim_replace_termcodes('<Bs>', true, true, true)
local CTRL_H = api.nvim_replace_termcodes('<C-h>', true, true, true)
local ESC = api.nvim_replace_termcodes('<Esc>', true, true, true)
local LABELS = {}
local CONFIG = {
  -- The labels that may be used, in order of their preference.
  labels = 'fdsaghjklrewqtyuiopvcxzbnm',

  -- The highlight group to use for match highlights.
  search = 'Search',

  -- The highlight group to use for labels.
  label = 'FlashLabel',

  -- Automatically jump if there is only a single match.
  auto_jump = false,
}

local function search(pattern, window, matches)
  local lines = window.lines
  local start_line = window.top
  local lower = pattern == pattern:lower()

  for idx, line in ipairs(lines) do
    local lnum = start_line + idx - 1
    line = lower and line:lower() or line

    if #line > 0 then
      local col = 1

      while true do
        local start, stop = line:find(pattern, col, true)

        if not start then
          break
        end

        col = stop + 1
        table.insert(matches, {
          win = window.win,
          buf = window.buf,
          line = lnum - 1,
          start_col = start - 1,
          end_col = stop,
          line_index = idx,
          line_text = lines[idx],
        })
      end
    end
  end
end

local function available_labels(matches)
  local avail = {}

  for _, char in ipairs(LABELS) do
    avail[char] = true
  end

  -- Disable all the labels that conflict with any of the characters that may be
  -- matched by the next input.
  for _, match in ipairs(matches) do
    local next_col = match.end_col + 1
    local next_char = match.line_text:sub(next_col, next_col):lower()

    avail[next_char] = false
  end

  return avail
end

local function get_windows()
  local windows = {}
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    local info = fn.getwininfo(win)[1]
    -- Skip invalid windows
    if info then
      local buf = api.nvim_win_get_buf(win)
      windows[#windows + 1] = {
        win = win,
        buf = buf,
        top = info.topline,
        bot = info.botline,
        lines = api.nvim_buf_get_lines(
          buf,
          info.topline - 1,
          info.botline,
          true
        ),
      }
    end
  end
  return windows
end

function M.start()
  local windows = get_windows()
  local chars = ''
  local matches = {}
  local active = {}

  while true do
    api.nvim_echo({ { '/' .. chars, '' } }, false, {})

    local char = fn.getcharstr(-1)
    local jump_to = active[char]

    if char == ESC then
      break
    elseif char == CR then
      for _, label in ipairs(LABELS) do
        jump_to = active[label]
        if jump_to then
          break
        end
      end

      if jump_to then
        vim.cmd("normal! m'")
        api.nvim_set_current_win(jump_to.win)
        api.nvim_win_set_cursor(jump_to.win, jump_to.pos)
      end

      break
    elseif char == BS or char == CTRL_H then
      chars = chars:sub(1, #chars - 1)
    elseif jump_to then
      vim.cmd("normal! m'")
      api.nvim_set_current_win(jump_to.win)
      api.nvim_win_set_cursor(jump_to.win, jump_to.pos)
      break
    else
      chars = chars .. char
    end

    matches = {}
    active = {}
    for _, window in ipairs(windows) do
      api.nvim_buf_clear_namespace(window.buf, NS, 0, -1)
    end

    if #chars > 0 then
      for _, window in ipairs(windows) do
        search(chars, window, matches)
      end

      if CONFIG.auto_jump and #matches == 1 then
        vim.cmd("normal! m'")
        api.nvim_win_set_cursor(matches[1].win, {
          matches[1].line + 1,
          matches[1].start_col,
        })
        break
      end

      local avail = available_labels(matches)

      for _, match in ipairs(matches) do
        local label = nil

        for _, cur in ipairs(LABELS) do
          if avail[cur] then
            label = cur
            avail[cur] = false
            break
          end
        end

        vim.hl.range(
          match.buf,
          NS,
          CONFIG.search,
          { match.line, match.start_col },
          { match.line, match.end_col },
          { priority = 200 }
        )

        if label then
          active[label] = {
            win = match.win,
            pos = { match.line + 1, match.start_col },
          }
          api.nvim_buf_set_extmark(match.buf, NS, match.line, match.start_col, {
            virt_text = { { label, CONFIG.label } },
            virt_text_pos = 'overlay',
            priority = 201,
          })
        end
      end
    end

    vim.cmd.redraw()
  end

  for _, window in ipairs(windows) do
    api.nvim_buf_clear_namespace(window.buf, NS, 0, -1)
  end
  api.nvim_echo({ { '', '' } }, false, {})
  vim.cmd.redraw()
end

function M.setup(opts)
  if opts then
    CONFIG = vim.tbl_extend('force', CONFIG, opts)
  end

  LABELS = fn.split(CONFIG.labels, '\\zs')
end

M.setup()

return M
