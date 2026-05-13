# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Is

Two shell scripts that act as Claude Code **status line commands** — hooks that Claude Code invokes at the end of each turn and whose stdout is rendered in the terminal status bar.

- `statusline-command.sh` — Bash (Linux/macOS): shows cwd, git branch, model, context remaining %
- `statusline-command.ps1` — PowerShell (Windows): shows cwd, git branch, model, token counts (↓in ↑out), context used %, and session cost

## How to Wire Them Up

In Claude Code's `settings.json`, set `statusCommand` to the appropriate script. The script receives the turn's JSON payload on stdin and must write the rendered status string to stdout (no trailing newline).

## Input JSON Schema

Claude Code pipes a JSON object to stdin. The fields used by these scripts:

| Field | Type | Meaning |
|---|---|---|
| `workspace.current_dir` | string | Current working directory |
| `model.display_name` | string | Human-readable model name |
| `model.id` | string | Model ID used for pricing lookup |
| `context_window.used_percentage` | number | % of context window consumed (input only) |
| `context_window.total_input_tokens` | number | Tokens currently in context (not cumulative) |
| `context_window.total_output_tokens` | number | Last-response output tokens (not cumulative) |
| `context_window.remaining_percentage` | number | Remaining context % (used by the `.sh` script) |
| `cost.total_cost_usd` | number | Cumulative session cost; preferred over local estimate |

## Token Semantics (Critical)

`total_input_tokens` = tokens currently in the context window (input + cache_creation + cache_read). It is **not** a cumulative session total.  
`total_output_tokens` = output tokens of the **last response only**, not cumulative.  
`used_percentage` is calculated from input tokens only (output not counted).

## Cost Calculation

The `.ps1` script uses a two-path approach:
1. **Primary**: `cost.total_cost_usd` from Claude Code — accurate, accounts for cache hit/miss pricing
2. **Fallback**: local pricing table × token counts — a rough upper-bound estimate because it applies uniform input pricing to tokens that may include cheaper cache reads

The fallback pricing table in the `.ps1` script must be kept in sync with Anthropic's published prices when models or tiers change.

## Output Format

Both scripts output ANSI-coloured text with no trailing newline. Fields are space-separated. The `.ps1` script uses `Write-Host … -NoNewline`; the `.sh` script uses `printf '%s'`.

Colour assignments (`.ps1`): blue = cwd, magenta = branch, orange = model, cyan = tokens, yellow = ctx %, green = cost.
