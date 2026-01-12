# Claude Code Guidelines

Before implementing: **read existing code first**. Plans may have wrong function names, variable names, or paths. Verify assumptions by reading the actual files you'll interact with.

When creating new files, find a similar existing file and use it as your template.

## Safe File Operations

All file writes must use safe-write helpers to ensure backups:

- `safe_write_file "$target" "content"` - write with backup
- `safe_write_heredoc "$target" <<EOF` - heredoc with backup
- `safe_append_file "$target" "content"` - append with backup on first use
- `safe_jq_write "$target" [flags] 'filter' inputs...` - jq output with backup

Never use `cat >`, `echo >`, or `jq ... >` directly in tool scripts.

**Before committing** changes to `tools/` or `lib/`, run:
```bash
./scripts/lint-safe-writes.sh                # Check for unsafe write patterns
./lib/dotfiles-system/test/run_tests.sh      # Run all tests
```
Both must pass before committing.
