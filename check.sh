#!/usr/bin/env bash
# Checks the two promises of Bar Peek against the running session:
#   1. windows never move  -> the bar reserves no desktop space
#   2. the bar is reachable -> an edge strip exists on the bar's own edge
# Plus the state the plugin itself reports, for good measure.
#
# Usage: ./check.sh   (run inside a Hyprland session with Bar Peek selected)

set -uo pipefail

fail=0
say() { printf '%s\n' "$*"; }
ok() { printf '  ok    %s\n' "$*"; }
bad() { printf '  FAIL  %s\n' "$*"; fail=1; }

need() {
  command -v "$1" >/dev/null 2>&1 || { say "missing dependency: $1"; exit 2; }
}
need hyprctl
need jq
need omarchy-shell

config="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json"
position="$(jq -r '.bar.position // "top"' "$config" 2>/dev/null)"
bar_id="$(jq -r '.bar.id // "omarchy.bar"' "$config" 2>/dev/null)"

say "bar id   : $bar_id"
say "position : $position"

[[ "$bar_id" == "shienze.bar-peek" ]] \
  && ok "bar option is shienze.bar-peek" \
  || bad "bar option is $bar_id, not shienze.bar-peek (omarchy bar use shienze.bar-peek)"

status="$(omarchy-shell bar-peek status 2>/dev/null)"
[[ -n "$status" ]] || { bad "bar-peek IPC answered nothing (is the plugin loaded?)"; }

if [[ -n "$status" ]]; then
  hidden="$(jq -r '.hidden' <<<"$status")"
  attached="$(jq -r '.attached' <<<"$status")"
  crashed="$(jq -r '.gaveUp' <<<"$status")"
  say "hidden   : $hidden"
  [[ "$attached" == "true" ]] && ok "bar windows found" || bad "no bar windows found"
  [[ "$crashed" == "true" ]] && bad "plugin gave up and left the bar visible"
  [[ "$attached" == "true" ]] && ok "status readable"
fi

# 1. No reserved space on any monitor that shows a bar.
reserved="$(hyprctl monitors -j | jq -c '[.[] | .reserved]')"
say "reserved : $reserved"
if [[ "$reserved" =~ ^\[\[0,0,0,0\](,\[0,0,0,0\])*\]$ ]]; then
  ok "no monitor reserves space for the bar"
else
  bad "a monitor reserves space (windows would move); set bar.peek.reserveSpace = false"
fi

# 2. The bar surface is parked or revealed, never in between.
mon="$(hyprctl monitors -j | jq -c '.[] | select(.focused == true)')"
mw="$(jq -r '.width' <<<"$mon")"
mh="$(jq -r '.height' <<<"$mon")"

bar_surface="$(hyprctl layers -j | jq -r --arg ns "omarchy-bar" '
  [.. | objects | select(.namespace? == $ns)] | first // empty')"

if [[ -z "$bar_surface" ]]; then
  bad "no omarchy-bar layer surface"
else
  ok "bar surface present"
  if [[ -n "$status" ]] && [[ "$(jq -r '.hidden' <<<"$status")" == "true" ]]; then
    offset="$(jq -r '.screens[0].offset' <<<"$status")"
    if [[ "$offset" == "0" ]]; then
      ok "bar is revealed (offset 0)"
    elif [[ "$offset" -lt 0 ]]; then
      ok "bar is parked off-screen (offset $offset) with a trigger strip to reveal it"
    else
      bad "unexpected offset $offset"
    fi
  fi
fi

# 3. The trigger strip sits on the bar's own edge, one strip thick.
case "$position" in
  top|bottom) want_var="w"; want_thickness="h" ;;
  *)          want_var="h"; want_thickness="w" ;;
esac

strip_geom="$(hyprctl layers -j | jq -r '
  [.. | objects | select(.namespace? == "omarchy-bar-peek-edge")]
  | first // empty | "\(.w) \(.h) \(.x) \(.y)"')"

if [[ -z "$strip_geom" ]]; then
  if [[ -n "$status" ]] && [[ "$(jq -r '.hidden' <<<"$status")" == "false" ]]; then
    ok "bar is pinned, so no trigger strip is expected"
  else
    bad "no omarchy-bar-peek-edge surface"
  fi
else
  read -r sw sh sx sy <<<"$strip_geom"
  case "$position" in
    top)    [[ "$sh" -le 4 && "$sy" -eq 0 ]] && ok "strip on top edge (${sw}x${sh})" || bad "strip misplaced: ${sw}x${sh} at ${sx},${sy}" ;;
    bottom) [[ "$sh" -le 4 && $((sy + sh)) -ge "$mh" ]] && ok "strip on bottom edge (${sw}x${sh})" || bad "strip misplaced: ${sw}x${sh} at ${sx},${sy}" ;;
    left)   [[ "$sw" -le 4 && "$sx" -eq 0 ]] && ok "strip on left edge (${sw}x${sh})" || bad "strip misplaced: ${sw}x${sh} at ${sx},${sy}" ;;
    right)  [[ "$sw" -le 4 && $((sx + sw)) -ge "$mw" ]] && ok "strip on right edge (${sw}x${sh})" || bad "strip misplaced: ${sw}x${sh} at ${sx},${sy}" ;;
  esac
fi

say ""
if [[ "$fail" -eq 0 ]]; then
  say "all checks passed"
else
  say "some checks failed"
fi
exit "$fail"
