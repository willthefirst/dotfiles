# Helper Libraries

Source these with: `source "$DOTFILES_DIR/lib/helpers/<file>.sh"`

## log.sh
Logging utilities. Functions are prefixed with `log_`:
- `log_section "msg"` - Major section header
- `log_step "msg"` - Action in progress
- `log_detail "msg"` - Subordinate info (dim)
- `log_ok "msg"` - Success
- `log_warn "msg"` - Warning (stderr)
- `log_error "msg"` - Error (stderr)

## json-merge.sh
Requires `jq`. Sources log.sh automatically.
- `json_deep_merge output.json input1.json input2.json ...`
- `json_validate file.json` - Returns 0 if valid
- `json_get file.json ".path.to.key"`

## symlink-factory.sh
Sources log.sh and utils.sh automatically.
- `symlink_with_backup source target`
- `create_layer_symlinks target_dir "*.pattern" layer1 layer2 ...`
- `symlink_directory source target`

## extension-installer.sh
VS Code extension management. Sources log.sh automatically.
- `vscode_available` - Returns 0 if VS Code CLI found
- `vscode_install_extension "extension.id"`
- `vscode_install_extensions_from_file extensions.txt`
