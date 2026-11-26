# Bar Peek

The stock Omarchy bar, popped out **over** your windows from whichever screen
edge it sits on — top, bottom, left or right — without ever moving a window.

```bash
omarchy plugin add https://github.com/77-223255/omarchy-bar-peek --enable
```

Press `Super + Shift + Space` once (Omarchy's own hide-bar toggle) to put the bar
into peek mode. After that: touch the screen edge the bar lives on and it slides
in over everything; move the pointer away and it slides back out in `40 ms` +
`80 ms`.

## Why this exists

Every Omarchy bar autohide plugin does one of these, and each costs you
something:

| Plugin | Reveal | Windows |
| --- | --- | --- |
| `ericvrp/omarchy-bar-autohide` | clears the hidden flag | **move**: the host bar reserves its space again while revealed |
| `WhiteHades/omarchy-topbar-peek` | over the windows | move not at all, but **top edge only**, and it no longer loads on shells after `omacom/omarchy#17229` (the `ScreenMoveRemap` type it names was removed) |
| `Ynnad242/omarchy-autohide-bar`, `radyalz/omarchy-bar-control`, `priyeshbhawsar15/omarchy-per-monitor-bar` | full copies of `Bar.qml` | reserve space in some modes, and drift from the host bar as Omarchy changes it |
| **Bar Peek** | margin animation only | **never move, on any edge** |

Bar Peek inherits the installed bar instead of copying it, so widgets, theme,
popouts, the tray drawer, drag-to-rearrange, the bar-off state and every widget
you install later stay Omarchy's. The only thing it owns is where the bar's layer
surface sits.

## Requirements

- Omarchy 4 (Quattro), where the bar is a Quickshell plugin (`qs.plugins.bar`)
- Hyprland (any version: Bar Peek names no version-specific QML type)
- `jq` for `check.sh` only

Tested on Omarchy `4.0.0.r8379` (omarchy-dev) with Hyprland `0.57.2`, on a
2560×1440 output at 1.25 scale.

## How it works

- While the bar is hidden, the host bar parks itself off-screen with
  `ExclusionMode.Ignore`, so windows own the whole screen. Bar Peek keeps that
  hidden state for the whole reveal and animates **only the park margin**, then
  puts the surface on the overlay layer. Nothing is re-tiled, nothing remaps, so
  the reveal is instant and the layout never breathes.
- With `reserveSpace: false` (the default) the bar also reserves no space when
  you show it with the hotkey: it simply floats over the windows.
- A `2 px` overlay strip along the bar's own edge catches the pointer. A second
  hover observer on the bar's content item holds it open while you use it, and
  keeps it open for an open popout or a widget mid-drag.
- **Over a fullscreen window** the host bar deliberately drops its input region
  to nothing, so clicks reach the fullscreen app. That would leave a revealed
  bar visible but dead, so Bar Peek takes the bar strip back as its input region
  for as long as the bar is out, and hands the stock region back when it slides
  away.
- It reaches the host's per-screen panel windows by scanning the inherited item
  tree for the bar's `Variants`. That is host-internal, so it is guarded: if the
  windows cannot be found within ~5 s, the plugin refuses to park anything and
  leaves the bar visible instead of stranding you with an unreachable bar.

## Tuning

At the top of `Bar.qml`:

| Property | Default | Meaning |
| --- | --- | --- |
| `hideDelayMs` | `40` | how long the pointer may leave the bar before it hides |
| `slideMs` | `80` | slide duration in and out |
| `triggerThickness` | `2` | thickness of the edge strip that catches the pointer |
| `reserveSpace` | `false` | `true` makes a hotkey-shown bar reserve space like stock |
| `aboveFullscreen` | `true` | the reveal also works over a fullscreen app |

`40 ms` + `80 ms` is deliberately fast: the reveal should read as a pop. Raise
them if your pointer is twitchy.

Edits to an installed checkout survive `omarchy plugin update` only if they are
in the repo. To keep local tweaks, either set the values in a fork, or clone the
plugin into your own id:

```bash
omarchy plugin clone shienze.bar-peek      # -> ~/.config/omarchy/plugins/<you>.bar-peek
```

## Verify

```bash
./check.sh                               # windows not moved, trigger strip on the bar's edge
omarchy-shell bar-peek status            # JSON: position, hidden, per-screen reveal state
omarchy-shell bar-peek reveal            # slide the bar out and hold it (no pointer needed)
omarchy-shell bar-peek hide              # let it go again
hyprctl monitors -j | jq '.[0].reserved' # [0,0,0,0] whenever Bar Peek is active
```

`status` reports, per screen, `revealed`, `held`, `offset`, the host
`exclusion` mode, and `input` — `bar` while the bar's own strip owns the pointer,
`host` while the stock region is back.

`check.sh` asserts the two promises: no monitor reserves space, and the trigger
strip sits on the bar's own edge with the right thickness. Hover itself cannot be
checked from the shell, because a compositor pointer warp does not deliver a
pointer enter to a layer surface — test that by hand.

## Revert

```bash
omarchy bar use omarchy.bar              # stock bar, keeps the plugin installed
omarchy plugin remove shienze.bar-peek   # drop it for good
```

The bar-off state is Omarchy's, not ours: `Super + Shift + Space` still toggles
the bar, and a bar you show that way is left alone by Bar Peek.

## Known limits

- Bar Peek reads host internals (`BarPanel`'s `Variants`) to find the panel
  windows. If Omarchy restructures them, the plugin loads but stops animating —
  and, thanks to the fail-safe, hands you a visible bar rather than a hole.
- Only the pointer triggers the reveal; there is no keyboard reveal. Omarchy's
  panels already have hotkeys (`Super + Ctrl + A/N/B/D/P`, `Super + Ctrl + 1-9`).
- The bar keeps the host's widgets, so a widget that assumes it may reserve space
  (one that opens a growing popout) still behaves exactly as it does in the host
  bar.

## Credits

The margin animation, the hover observer and the overlay-layer trick come from
[WhiteHades/omarchy-topbar-peek](https://github.com/WhiteHades/omarchy-topbar-peek)
(MIT). Bar Peek generalises it to every edge, drops the removed
`ScreenMoveRemap` dependency (`omacom/omarchy#17229`, Hyprland 0.57 moves layer
surfaces with their monitor by itself), adds the no-reserved-space mode, the
fail-safe and the check script.

MIT licensed; see [LICENSE](LICENSE).
