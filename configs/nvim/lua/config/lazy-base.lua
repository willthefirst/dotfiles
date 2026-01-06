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

return M
