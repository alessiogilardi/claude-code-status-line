#!/usr/bin/env bash
# Claude Code status line command
# Displays: cwd (shortened) | git branch (if available) | model | context usage

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
model=$(echo "$input" | jq -r '.model.display_name // ""')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

# Shorten home directory to ~
home="$HOME"
short_cwd="${cwd/#$home/\~}"

# Get git branch, suppressing errors and skipping optional locks
branch=""
if git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
fi

# Build status parts
parts=()
parts+=("$(printf '\033[0;34m%s\033[0m' "$short_cwd")")

if [ -n "$branch" ]; then
  parts+=("$(printf '\033[0;35m(%s)\033[0m' "$branch")")
fi

if [ -n "$model" ]; then
  parts+=("$(printf '\033[0;36m%s\033[0m' "$model")")
fi

if [ -n "$remaining" ]; then
  parts+=("$(printf '\033[0;33mctx: %s%%\033[0m' "$remaining")")
fi

printf '%s' "${parts[*]}"
