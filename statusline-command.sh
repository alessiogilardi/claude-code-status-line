#!/usr/bin/env bash
# Claude Code status line command (Bash)
# Displays: cwd | git branch | model | context used % | tokens in/out | session cost
#
# TOKEN SEMANTICS (as of Claude Code v2.1.132):
#   context_window.total_input_tokens  = tokens currently IN the context window
#                                        (= input_tokens + cache_creation + cache_read)
#                                        NOT a cumulative session total
#   context_window.total_output_tokens = output tokens of the LAST response only
#                                        NOT cumulative
#   context_window.used_percentage     = calculated from input tokens only (no output)
#
# COST: always use cost.total_cost_usd — Claude Code computes it correctly,
#       accounting for cache hit/miss pricing. The local pricing table below
#       is kept only as a last-resort fallback when cost.total_cost_usd is absent.

# ── Configuration ─────────────────────────────────────────────────────────────
# Ordered list of fields to display. Remove a name to hide it; reorder to change order.
# Available: "cwd"  "branch"  "model"  "tokens"  "cost"
STATUSLINE_TEMPLATE=("cwd" "branch" "model" "tokens" "cost")
STATUSLINE_SEPARATOR=" "

# Symbols — replace with ASCII alternatives if your terminal doesn't render Unicode
SYM_TOKENS_IN="↑"
SYM_TOKENS_OUT="↓"
SYM_COST="~"
# ──────────────────────────────────────────────────────────────────────────────

input=$(cat)

# ── Parse JSON ────────────────────────────────────────────────────────────────
if command -v jq >/dev/null 2>&1; then
    cwd=$(      echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
    model=$(    echo "$input" | jq -r '.model.display_name // ""')
    model_id=$( echo "$input" | jq -r '.model.id // ""')
    used=$(     echo "$input" | jq -r 'if .context_window.used_percentage      != null then (.context_window.used_percentage|tostring)      else "" end')
    total_in=$( echo "$input" | jq -r 'if .context_window.total_input_tokens   != null then (.context_window.total_input_tokens|tostring)   else "" end')
    total_out=$(echo "$input" | jq -r 'if .context_window.total_output_tokens  != null then (.context_window.total_output_tokens|tostring)  else "" end')
    cost_usd=$( echo "$input" | jq -r 'if .cost.total_cost_usd                 != null then (.cost.total_cost_usd|tostring)                 else "" end')
elif command -v python3 >/dev/null 2>&1; then
    eval "$(echo "$input" | python3 -c "
import json, sys, shlex
d = json.loads(sys.stdin.read())
ws = d.get('workspace') or {}
cw = d.get('context_window') or {}
mo = d.get('model') or {}
co = d.get('cost') or {}
for k, v in [
    ('cwd',       ws.get('current_dir') or d.get('cwd') or ''),
    ('model',     mo.get('display_name') or ''),
    ('model_id',  mo.get('id') or ''),
    ('used',      '' if cw.get('used_percentage')      is None else str(cw['used_percentage'])),
    ('total_in',  '' if cw.get('total_input_tokens')   is None else str(cw['total_input_tokens'])),
    ('total_out', '' if cw.get('total_output_tokens')  is None else str(cw['total_output_tokens'])),
    ('cost_usd',  '' if co.get('total_cost_usd')       is None else str(co['total_cost_usd'])),
]:
    print(f'{k}={shlex.quote(v)}')
")"
else
    exit 0
fi

# ── Shorten home directory to ~ ───────────────────────────────────────────────
short_cwd="${cwd/#$HOME/\~}"

# ── Git branch ────────────────────────────────────────────────────────────────
branch=""
if [ -n "$cwd" ] && git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || true)
fi

# ── Fallback pricing table (USD per 1M tokens, May 2026) ─────────────────────
# Used ONLY if cost.total_cost_usd is absent.
# WARNING: applies uniform input price to total_input_tokens, which includes
# cache reads (10x cheaper) — so the estimate will be higher than actual cost.
get_price() {
    case "$1" in
        *claude-opus-4*)    echo "5.0 25.0"  ;;
        *claude-sonnet-4*)  echo "3.0 15.0"  ;;
        *claude-haiku-4*)   echo "1.0 5.0"   ;;
        *claude-haiku-3*)   echo "0.25 1.25" ;;
        *claude-sonnet-3*)  echo "3.0 15.0"  ;;
        *claude-opus-3*)    echo "15.0 75.0" ;;
        *)                  echo "3.0 15.0"  ;;
    esac
}

# ── Helper: format token counts as k/M (awk uses C locale → always ".") ──────
format_tokens() {
    local n=$1
    if   [ "$n" -ge 1000000 ] 2>/dev/null; then awk "BEGIN { printf \"%.1fM\", $n/1000000 }"
    elif [ "$n" -ge 1000    ] 2>/dev/null; then awk "BEGIN { printf \"%.0fk\", $n/1000 }"
    else echo "$n"
    fi
}

# ── ANSI colors ───────────────────────────────────────────────────────────────
reset=$'\e[0m'
blue=$'\e[34m'
magenta=$'\e[35m'
orange=$'\e[38;5;214m'
yellow=$'\e[33m'
cyan=$'\e[36m'
green=$'\e[32m'

# ── Render each field ─────────────────────────────────────────────────────────
_f_cwd="${blue}${short_cwd}${reset}"

if [ -n "$branch" ]; then
    _f_branch="${magenta}(${branch})${reset}"
else
    _f_branch=""
fi

if [ -n "$model" ]; then
    _f_model="${orange}${model}${reset}"
else
    _f_model=""
fi

if [ -n "$total_in" ] && [ -n "$total_out" ]; then
    in_fmt=$(format_tokens "$total_in")
    out_fmt=$(format_tokens "$total_out")
    _f_tokens="${cyan}${SYM_TOKENS_IN}${in_fmt} ${SYM_TOKENS_OUT}${out_fmt}${reset}"
    if [ -n "$used" ]; then
        _f_tokens="${_f_tokens} ${yellow}(${used}%)${reset}"
    fi
else
    _f_tokens=""
fi

if [ -n "$cost_usd" ]; then
    cost_val="$cost_usd"
elif [ -n "$total_in" ] && [ -n "$total_out" ]; then
    read -r price_in price_out <<< "$(get_price "$model_id")"
    cost_val=$(awk "BEGIN { printf \"%.4f\", ($total_in/1000000)*$price_in + ($total_out/1000000)*$price_out }")
else
    cost_val=""
fi

if [ -n "$cost_val" ]; then
    _f_cost_str=$(awk -v v="$cost_val" 'BEGIN {
        if (v+0 < 0.01) printf "<$0.01"
        else            printf "$%.2f", v
    }')
    _f_cost="${green}${SYM_COST}${_f_cost_str}${reset}"
else
    _f_cost=""
fi

# ── Assemble in template order ────────────────────────────────────────────────
parts=()
for field in "${STATUSLINE_TEMPLATE[@]}"; do
    case "$field" in
        cwd)    val="$_f_cwd" ;;
        branch) val="$_f_branch" ;;
        model)  val="$_f_model" ;;
        tokens) val="$_f_tokens" ;;
        cost)   val="$_f_cost" ;;
        *)      val="" ;;
    esac
    [ -n "$val" ] && parts+=("$val")
done

output=""
for part in "${parts[@]}"; do
    if [ -z "$output" ]; then
        output="$part"
    else
        output="${output}${STATUSLINE_SEPARATOR}${part}"
    fi
done
printf '%s' "$output"
