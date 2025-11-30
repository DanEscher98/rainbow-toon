--- Token counter module for rainbow-toon
--- Displays token count in a floating window at the bottom-right corner
--- Uses gpt-tokenizer (npm package) for accurate GPT token counting

local M = {}

--- State for the token counter
M.state = {
  enabled = false,
  win_id = nil,
  buf_id = nil,
  timer = nil,
  last_count = nil,
  job_id = nil,
}

--- Configuration (set by setup)
M.config = {
  -- Enable token counter display
  enabled = false,
  -- Debounce delay in ms before recounting tokens
  debounce_ms = 500,
  -- Window blend (transparency) 0=opaque, 100=fully transparent
  winblend = 30,
  -- Border style: "none", "single", "double", "rounded", "solid", "shadow"
  border = 'rounded',
  -- Highlight group for the token count text
  highlight = 'Comment',
  -- Highlight group for the window border
  border_highlight = 'FloatBorder',
  -- Format string for display (use %d for token count)
  format = ' %d tokens ',
}

--- Get the path to the token counter script
---@return string|nil
local function get_script_path()
  -- Find the plugin directory
  local source = debug.getinfo(1, 'S').source:sub(2)
  local plugin_dir = vim.fn.fnamemodify(source, ':h:h:h')
  local script_path = plugin_dir .. '/scripts/count-tokens.mjs'

  if vim.fn.filereadable(script_path) == 1 then
    return script_path
  end

  return nil
end

--- Create the floating window
---@param bufnr number The buffer to attach to
---@return number|nil win_id
local function create_window(bufnr)
  -- Create a scratch buffer for the floating window
  local float_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('buftype', 'nofile', { buf = float_buf })
  vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = float_buf })

  -- Calculate position (bottom-right of current window)
  local win_width = vim.api.nvim_win_get_width(0)
  local win_height = vim.api.nvim_win_get_height(0)

  local float_width = 16 -- Enough for " 99999 tokens "
  local float_height = 1

  local opts = {
    relative = 'win',
    win = vim.api.nvim_get_current_win(),
    width = float_width,
    height = float_height,
    row = win_height - 2, -- Above the statusline
    col = win_width - float_width - 1,
    style = 'minimal',
    border = M.config.border,
    focusable = false,
    zindex = 50,
  }

  local win_id = vim.api.nvim_open_win(float_buf, false, opts)

  -- Set window options
  vim.api.nvim_set_option_value('winblend', M.config.winblend, { win = win_id })
  vim.api.nvim_set_option_value('winhighlight', 'Normal:' .. M.config.highlight .. ',FloatBorder:' .. M.config.border_highlight, { win = win_id })

  M.state.buf_id = float_buf
  M.state.win_id = win_id

  return win_id
end

--- Update the floating window content
---@param count number Token count to display
local function update_display(count)
  if not M.state.win_id or not vim.api.nvim_win_is_valid(M.state.win_id) then
    return
  end

  if not M.state.buf_id or not vim.api.nvim_buf_is_valid(M.state.buf_id) then
    return
  end

  local text = string.format(M.config.format, count)
  vim.api.nvim_buf_set_lines(M.state.buf_id, 0, -1, false, { text })
  M.state.last_count = count
end

--- Count tokens asynchronously
---@param bufnr number Buffer to count tokens for
local function count_tokens_async(bufnr)
  local script_path = get_script_path()
  if not script_path then
    vim.notify('rainbow-toon: Token counter script not found', vim.log.levels.WARN)
    return
  end

  -- Cancel any pending job
  if M.state.job_id and vim.fn.jobwait({ M.state.job_id }, 0)[1] == -1 then
    vim.fn.jobstop(M.state.job_id)
  end

  -- Get buffer content
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, '\n')

  local stdout_data = ''

  M.state.job_id = vim.fn.jobstart({ 'node', script_path }, {
    stdin = 'pipe',
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        stdout_data = table.concat(data, '')
      end
    end,
    on_exit = function(_, exit_code)
      if exit_code == 0 and stdout_data ~= '' then
        local count = tonumber(stdout_data)
        if count then
          vim.schedule(function()
            update_display(count)
          end)
        end
      end
      M.state.job_id = nil
    end,
  })

  if M.state.job_id > 0 then
    vim.fn.chansend(M.state.job_id, content)
    vim.fn.chanclose(M.state.job_id, 'stdin')
  end
end

--- Schedule a debounced token count
---@param bufnr number Buffer to count tokens for
local function schedule_count(bufnr)
  -- Cancel existing timer
  if M.state.timer then
    vim.fn.timer_stop(M.state.timer)
  end

  M.state.timer = vim.fn.timer_start(M.config.debounce_ms, function()
    count_tokens_async(bufnr)
  end)
end

--- Close the floating window
local function close_window()
  if M.state.win_id and vim.api.nvim_win_is_valid(M.state.win_id) then
    vim.api.nvim_win_close(M.state.win_id, true)
  end

  if M.state.timer then
    vim.fn.timer_stop(M.state.timer)
  end

  if M.state.job_id and vim.fn.jobwait({ M.state.job_id }, 0)[1] == -1 then
    vim.fn.jobstop(M.state.job_id)
  end

  M.state.win_id = nil
  M.state.buf_id = nil
  M.state.timer = nil
  M.state.job_id = nil
end

--- Reposition the floating window (e.g., after window resize)
local function reposition_window()
  if not M.state.win_id or not vim.api.nvim_win_is_valid(M.state.win_id) then
    return
  end

  local win_width = vim.api.nvim_win_get_width(0)
  local win_height = vim.api.nvim_win_get_height(0)

  local float_width = 16

  local opts = {
    relative = 'win',
    win = vim.api.nvim_get_current_win(),
    row = win_height - 2,
    col = win_width - float_width - 1,
  }

  vim.api.nvim_win_set_config(M.state.win_id, opts)
end

--- Check if gpt-tokenizer is available
---@return boolean
local function check_gpt_tokenizer()
  -- Check if node is available
  if vim.fn.executable('node') ~= 1 then
    return false
  end

  -- Check if gpt-tokenizer is installed globally
  local npm_root = vim.fn.system('npm root -g 2>/dev/null'):gsub('%s+$', '')
  if vim.v.shell_error ~= 0 or npm_root == '' then
    return false
  end

  local tokenizer_path = npm_root .. '/gpt-tokenizer'
  return vim.fn.isdirectory(tokenizer_path) == 1
end

--- Enable token counter for a buffer
---@param bufnr number|nil Buffer number (default: current buffer)
function M.enable(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Check if node is available
  if vim.fn.executable('node') ~= 1 then
    vim.schedule(function()
      vim.notify('rainbow-toon: Node.js is required for token counting', vim.log.levels.WARN)
    end)
    return
  end

  -- Check if gpt-tokenizer is installed
  if not check_gpt_tokenizer() then
    vim.schedule(function()
      vim.notify('rainbow-toon: gpt-tokenizer not found. Run: npm install -g gpt-tokenizer', vim.log.levels.WARN)
    end)
    return
  end

  M.state.enabled = true

  -- Create floating window
  create_window(bufnr)

  -- Initial count
  count_tokens_async(bufnr)

  -- Set up autocmds for this buffer
  local augroup = vim.api.nvim_create_augroup('RainbowToonTokenCounter', { clear = true })

  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    group = augroup,
    buffer = bufnr,
    callback = function()
      if M.state.enabled then
        schedule_count(bufnr)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ 'WinResized', 'VimResized' }, {
    group = augroup,
    callback = function()
      if M.state.enabled then
        reposition_window()
      end
    end,
  })

  vim.api.nvim_create_autocmd('BufLeave', {
    group = augroup,
    buffer = bufnr,
    callback = function()
      close_window()
    end,
  })

  vim.api.nvim_create_autocmd('BufEnter', {
    group = augroup,
    buffer = bufnr,
    callback = function()
      if M.state.enabled and not M.state.win_id then
        create_window(bufnr)
        if M.state.last_count then
          update_display(M.state.last_count)
        else
          count_tokens_async(bufnr)
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd('BufDelete', {
    group = augroup,
    buffer = bufnr,
    callback = function()
      M.disable()
    end,
  })
end

--- Disable token counter
function M.disable()
  M.state.enabled = false
  close_window()
  vim.api.nvim_create_augroup('RainbowToonTokenCounter', { clear = true })
end

--- Toggle token counter
---@param bufnr number|nil Buffer number (default: current buffer)
function M.toggle(bufnr)
  if M.state.enabled then
    M.disable()
  else
    M.enable(bufnr)
  end
end

--- Setup the token counter with configuration
---@param opts table|nil Configuration options
function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
end

return M
