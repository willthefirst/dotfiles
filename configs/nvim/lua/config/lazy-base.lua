-- =============================================================================
-- lazy-base.lua - Base lazy.nvim configuration (importable)
-- =============================================================================
-- This module exports the lazy.nvim config so it can be extended by overlays.
-- Usage: local base = require("config.lazy-base")
-- =============================================================================

local M = {}

-- Plugin spec
M.spec = {
  { "LazyVim/LazyVim", import = "lazyvim.plugins" },
  { import = "plugins" },
}

-- Lazy.nvim options
M.opts = {
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded.
    lazy = false,
    -- Use latest git commit (many plugins have outdated releases)
    version = false,
  },
  install = { colorscheme = { "tokyonight", "habamax" } },
  checker = {
    enabled = true, -- check for plugin updates periodically
    notify = false, -- notify on update
  },
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
}

-- Bootstrap lazy.nvim (shared by base and overlays)
function M.bootstrap()
  local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
  if not (vim.uv or vim.loop).fs_stat(lazypath) then
    local lazyrepo = "https://github.com/folke/lazy.nvim.git"
    local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
    if vim.v.shell_error ~= 0 then
      vim.api.nvim_echo({
        { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
        { out, "WarningMsg" },
        { "\nPress any key to exit..." },
      }, true, {})
      vim.fn.getchar()
      os.exit(1)
    end
  end
  vim.opt.rtp:prepend(lazypath)
end

-- =============================================================================
-- Extension API
-- =============================================================================
-- This provides a clean interface for overlay configs (like Stripe) to extend
-- the base configuration without needing to understand internal structure.

---Extend the base configuration with additional plugins and options
---@param options table Extension options
---  - extra_spec: table[] Additional plugin specs to add (e.g., { import = "plugins-work" })
---  - opts: table Additional options to deep merge with base opts
---@return table Extended configuration ready for require("lazy").setup()
function M.extend(options)
  options = options or {}

  -- Start with a copy of the base spec
  local spec = vim.deepcopy(M.spec)

  -- Add extra specs if provided
  if options.extra_spec then
    for _, entry in ipairs(options.extra_spec) do
      table.insert(spec, entry)
    end
  end

  -- Merge options with base
  local opts = vim.tbl_deep_extend("force", vim.deepcopy(M.opts), options.opts or {})

  return {
    spec = spec,
    defaults = opts.defaults,
    install = opts.install,
    checker = opts.checker,
    performance = opts.performance,
  }
end

---Setup lazy.nvim with the base configuration
---Convenience function for layers that don't need to extend
function M.setup()
  M.bootstrap()
  require("lazy").setup({
    spec = M.spec,
    defaults = M.opts.defaults,
    install = M.opts.install,
    checker = M.opts.checker,
    performance = M.opts.performance,
  })
end

return M
