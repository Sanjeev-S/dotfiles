#!/usr/bin/env bash
# Claude Code status line — reads JSON from stdin, outputs one-line status

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "--"')
pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | xargs printf '%.0f')
in_tok=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
out_tok=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')

fmt_tokens() {
  local n="$1"
  if [ "$n" -ge 1000000 ] 2>/dev/null; then
    printf '%.1fM' "$(echo "$n / 1000000" | bc -l)"
  elif [ "$n" -ge 1000 ] 2>/dev/null; then
    printf '%.1fk' "$(echo "$n / 1000" | bc -l)"
  else
    echo "$n"
  fi
}

echo "$model | ctx: ${pct}% | $(fmt_tokens "$in_tok") in / $(fmt_tokens "$out_tok") out"
