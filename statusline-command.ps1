# Claude Code status line command (PowerShell)
# Displays: cwd | git branch | model | context used % | tokens in/out | session cost
#
# TOKEN SEMANTICS (as of Claude Code v2.1.132):
#   context_window.total_input_tokens  = token currently IN the context window
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
$STATUSLINE_TEMPLATE  = @("cwd", "branch", "model", "tokens", "cost")
$STATUSLINE_SEPARATOR = " "

# Symbols — replace with ASCII alternatives if your terminal doesn't render Unicode
$SYM_TOKENS_IN  = [char]0x2191   # ↑  (tokens in context window)
$SYM_TOKENS_OUT = [char]0x2193   # ↓  (last-response output tokens)
$SYM_COST       = "~"            # cost prefix
# ──────────────────────────────────────────────────────────────────────────────

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$input_data = $input | Out-String
$json = $input_data | ConvertFrom-Json

$cwd      = if ($json.workspace.current_dir) { $json.workspace.current_dir } elseif ($json.cwd) { $json.cwd } else { "" }
$model    = if ($json.model.display_name)    { $json.model.display_name }    else { "" }
$model_id = if ($json.model.id)              { $json.model.id }              else { "" }
$used     = if ($null -ne $json.context_window.used_percentage) { $json.context_window.used_percentage } else { $null }
$total_in  = if ($null -ne $json.context_window.total_input_tokens)  { $json.context_window.total_input_tokens }  else { $null }
$total_out = if ($null -ne $json.context_window.total_output_tokens) { $json.context_window.total_output_tokens } else { $null }

# Primary cost source: provided by Claude Code (correct, accounts for cache pricing)
$cost_usd = if ($null -ne $json.cost.total_cost_usd) { [double]$json.cost.total_cost_usd } else { $null }

# Shorten home directory to ~
$home_dir  = $env:USERPROFILE
$short_cwd = $cwd -replace [regex]::Escape($home_dir), "~"

# ANSI escape codes
$esc     = [char]27
$reset   = "$esc[0m"
$blue    = "$esc[34m"
$magenta = "$esc[35m"
$orange  = "$esc[38;5;214m"
$yellow  = "$esc[33m"
$cyan    = "$esc[36m"
$green   = "$esc[32m"

# ── Fallback pricing table (USD per 1M tokens, May 2026) ────────────────────
# Used ONLY if cost.total_cost_usd is absent.
# WARNING: applies uniform input price to total_input_tokens, which includes
# cache reads (10x cheaper) — so the estimate will be higher than actual cost.
# Prefer cost.total_cost_usd whenever available.
#
# Current generation
#   claude-opus-4-*   $5.00 / $25.00
#   claude-sonnet-4-* $3.00 / $15.00
#   claude-haiku-4-5  $1.00 / $5.00
# Legacy
#   claude-haiku-3-*  $0.25 / $1.25
#   claude-sonnet-3-* $3.00 / $15.00   (3.5 / 3.7 — Sonnet tier unchanged)
#   claude-opus-3-*   $15.00 / $75.00  (Opus 3 legacy)
# ────────────────────────────────────────────────────────────────────────────
$pricing = @{
    "claude-opus-4"    = @{ input = 5.0;   output = 25.0  }
    "claude-sonnet-4"  = @{ input = 3.0;   output = 15.0  }
    "claude-haiku-4"   = @{ input = 1.0;   output = 5.0   }
    "claude-haiku-3"   = @{ input = 0.25;  output = 1.25  }
    "claude-sonnet-3"  = @{ input = 3.0;   output = 15.0  }
    "claude-opus-3"    = @{ input = 15.0;  output = 75.0  }
}

# Match model_id prefix against pricing table (longest match wins)
$price_in  = $null
$price_out = $null
$best_key  = ""
foreach ($key in $pricing.Keys) {
    if (($model_id -like "*$key*") -and ($key.Length -gt $best_key.Length)) {
        $best_key  = $key
        $price_in  = $pricing[$key].input
        $price_out = $pricing[$key].output
    }
}
# Default fallback: Sonnet 4 pricing
if ($null -eq $price_in) {
    $price_in  = 3.0
    $price_out = 15.0
}

# Get git branch, suppressing errors
$branch = ""
try {
    $gitOutput = & git --no-optional-locks -C $cwd symbolic-ref --short HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $gitOutput) {
        $branch = $gitOutput.Trim()
    }
} catch {}

# Helper: format large token counts as k/M (invariant culture — always uses ".")
function Format-Tokens([long]$n) {
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($n -ge 1000000) { return ($n / 1000000).ToString("F1", $inv) + "M" }
    if ($n -ge 1000)    { return ($n / 1000).ToString("F0", $inv) + "k" }
    return "$n"
}

# ── Render each field ─────────────────────────────────────────────────────────
$fields = @{}

$fields["cwd"] = "${blue}${short_cwd}${reset}"

$fields["branch"] = if ($branch) { "${magenta}(${branch})${reset}" } else { $null }

$fields["model"] = if ($model) { "${orange}${model}${reset}" } else { $null }

if ($null -ne $total_in -and $null -ne $total_out) {
    $in_fmt    = Format-Tokens $total_in
    $out_fmt   = Format-Tokens $total_out
    $token_str = "${cyan}${SYM_TOKENS_IN} ${in_fmt} ${SYM_TOKENS_OUT} ${out_fmt}${reset}"
    if ($null -ne $used) { $token_str += " ${yellow}(${used}%)${reset}" }
    $fields["tokens"] = $token_str
} else {
    $fields["tokens"] = $null
}

if ($null -ne $cost_usd) {
    $cost_val = $cost_usd
} elseif ($null -ne $total_in -and $null -ne $total_out) {
    $cost_val = ($total_in / 1000000) * $price_in + ($total_out / 1000000) * $price_out
} else {
    $cost_val = $null
}
if ($null -ne $cost_val) {
    $inv      = [System.Globalization.CultureInfo]::InvariantCulture
    $cost_str = if ($cost_val -lt 0.01) { "<`$0.01" } else { "`$" + $cost_val.ToString("F2", $inv) }
    $fields["cost"] = "${green}${SYM_COST}${cost_str}${reset}"
} else {
    $fields["cost"] = $null
}

# ── Assemble in template order ────────────────────────────────────────────────
$parts = @(foreach ($f in $STATUSLINE_TEMPLATE) {
    if ($fields.ContainsKey($f) -and $null -ne $fields[$f]) { $fields[$f] }
})

Write-Host ($parts -join $STATUSLINE_SEPARATOR) -NoNewline
