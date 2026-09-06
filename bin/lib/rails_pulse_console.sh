#!/usr/bin/env bash

# Terminal styling shared by the release scripts (bin/release and friends).
# Mirrors test/support/rails_pulse_console.rb: a heavy-rule heading/footer in
# brand yellow, bracket status tags for individual lines.
#
#   rp_rule "RELEASE" "v0.4.0"
#     ━━ RELEASE ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ v0.4.0 ━━
#
#   rp_line ok "commits pushed"
#     [ok]  commits pushed
#
# Falls back to plain ASCII when stdout is not a TTY, NO_COLOR is set, or
# TERM is dumb, so CI logs and redirected output stay readable. Functions are
# prefixed rp_ (Rails Pulse) rather than spelled out, since these scripts
# call them on nearly every line.

rp_fancy() {
  [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != "dumb" ] && [ -t 1 ]
}

if rp_fancy; then
  RP_BOLD=$'\033[1m'
  RP_DIM=$'\033[2m'
  RP_RESET=$'\033[0m'
  if [[ "${COLORTERM:-}" =~ truecolor|24bit ]]; then
    RP_YELLOW=$'\033[38;2;234;179;8m'
    RP_GREEN=$'\033[38;2;34;197;94m'
    RP_RED=$'\033[38;2;239;68;68m'
  else
    RP_YELLOW=$'\033[33m'
    RP_GREEN=$'\033[32m'
    RP_RED=$'\033[31m'
  fi
  RP_RULE_CHAR="━"
else
  RP_BOLD=""; RP_DIM=""; RP_RESET=""; RP_YELLOW=""; RP_GREEN=""; RP_RED=""
  RP_RULE_CHAR="="
fi

rp_strip_ansi() {
  printf '%s' "$1" | sed -E $'s/\x1b\\[[0-9;]*m//g'
}

rp_visible_length() {
  local stripped
  stripped=$(rp_strip_ansi "$1")
  echo "${#stripped}"
}

# `tr` is byte-oriented and mangles a multi-byte fill character like ━, so
# repeat it with a plain loop instead.
rp_repeat() {
  local char="$1" count="$2" result="" i
  for ((i = 0; i < count; i++)); do
    result+="$char"
  done
  echo "$result"
}

rp_width() {
  local cols
  cols=$(tput cols 2>/dev/null || echo 0)
  [ "$cols" -gt 0 ] 2>/dev/null || cols="${COLUMNS:-80}"
  [ "$cols" -ge 60 ] 2>/dev/null || cols=60
  if [ "$cols" -gt 120 ] 2>/dev/null; then cols=120; fi
  echo "$cols"
}

# rp_rule TITLE [DETAIL] [COLOR]  (COLOR defaults to $RP_YELLOW)
rp_rule() {
  local title="$1" detail="${2:-}" color="${3:-$RP_YELLOW}"
  local width head tail fill fillstr head_len tail_len

  width=$(rp_width)
  head="${color}${RP_RULE_CHAR}${RP_RULE_CHAR}${RP_RESET} ${RP_BOLD}${color}${title}${RP_RESET} "
  head_len=$(( ${#title} + 5 ))

  if [ -n "$detail" ]; then
    tail=" ${detail} ${color}${RP_RULE_CHAR}${RP_RULE_CHAR}${RP_RESET}"
    tail_len=$(( $(rp_visible_length "$detail") + 5 ))
  else
    tail="${color}${RP_RULE_CHAR}${RP_RULE_CHAR}${RP_RESET}"
    tail_len=2
  fi

  fill=$(( width - 2 - head_len - tail_len ))
  [ "$fill" -ge 4 ] || fill=4
  fillstr=$(rp_repeat "$RP_RULE_CHAR" "$fill")

  echo "  ${head}${color}${fillstr}${RP_RESET}${tail}"
}

# rp_tag ok|fail|warn|info
rp_tag() {
  case "$1" in
    ok)   echo "${RP_GREEN}[ok]${RP_RESET}" ;;
    fail) echo "${RP_RED}[!!]${RP_RESET}" ;;
    warn) echo "${RP_YELLOW}[ !]${RP_RESET}" ;;
    *)    echo "${RP_YELLOW}[..]${RP_RESET}" ;;
  esac
}

# rp_line ok|fail|warn|info "message"
rp_line() {
  echo "  $(rp_tag "$1")  $2"
}

rp_ok()   { rp_line ok "$1"; }
rp_fail() { rp_line fail "$1"; }
rp_warn() { rp_line warn "$1"; }

rp_bold() { echo "${RP_BOLD}$1${RP_RESET}"; }
rp_dim()  { echo "${RP_DIM}$1${RP_RESET}"; }
