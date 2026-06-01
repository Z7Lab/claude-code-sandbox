#!/bin/sh
# Symlink .claude.json from inside .claude/ to home directory.
# This avoids Docker EBUSY errors that occur when bind-mounting
# individual files (Claude Code does atomic rename-writes on .claude.json).
ln -sf "$HOME/.claude/.claude.json" "$HOME/.claude.json" 2>/dev/null
exec "$@"
