-- =============================================================================
-- lazy.lua - Lazy.nvim setup (uses base config)
-- =============================================================================
-- Bootstraps lazy.nvim and loads plugins from config.lazy-base
-- Overlays can replace this file to extend the base spec.
-- =============================================================================

local base = require("config.lazy-base")

-- Bootstrap lazy.nvim
base.bootstrap()

-- Setup with base spec and options
require("lazy").setup({
  spec = base.spec,
  defaults = base.opts.defaults,
  install = base.opts.install,
  checker = base.opts.checker,
  performance = base.opts.performance,
})
