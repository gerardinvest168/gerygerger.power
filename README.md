# Asus Battery & Display

Battery, power and display control for the Omarchy bar, in one panel.

Plugin id: `gerygerger.power`

Asus Battery & Display Control by Gerygerger. A merge of Omarchy's stock `omarchy.power` widget with a
brightness control panel, so an Asus laptop gets one chip for the things you actually change during
the day: power profile, charge limit, screen brightness, auto-dim, and the idle timeouts.

## The chip

The icon tracks the charge level across ten steps and swaps between plain and charging glyphs as the
state changes. The chip hides itself entirely when there is no battery — a desktop, or a machine
running without the pack.

| Input | Action |
|---|---|
| Left click | Open the panel |
| Right click | Toggle the percentage in front of the icon |
| Scroll | Brightness in 5% steps, with the Omarchy OSD |

Turning the percentage on widens the chip to fit the text, and the choice is remembered: it is written
back to this widget's entry in `shell.json`.

## The panel

**Header and battery.** The battery icon, the percentage, and the plugin name sit at the top over a
progress bar that fills with the charge level and pulses gently while charging. Underneath:

| Field | Shows |
|---|---|
| Battery size | Pack design capacity |
| Charge cycles | Cycle count |
| Charge limit | The limit in force while holding one, otherwise Time left / Time to full |
| Battery state | Holding ✓ when the kernel agrees with the limit, Holding ⚠ when it does not, otherwise the charging or discharging rate |

**Brightness.** A 15–100% slider with a live readout. The 15% floor is deliberate: below that most
panels are unreadable, and the software dimming path has no range left to give.

**Auto-dim.** A toggle, a threshold (5m / 15m / 30m / 1 Hr / Off), and a target adjustable in 5%
steps. While enabled the panel checks idle time every 10 seconds, fades to the target once the
threshold passes, and restores the previous brightness as soon as you touch the keyboard or mouse.

**Power profile.** One button per profile reported by `omarchy-powerprofiles-list`, applied through
`omarchy-powerprofiles-set` against the current power source. Activating a profile works on battery
and on AC.

**Charge limit.** 50%, 80%, or Off (100%). Asus hardware only.

**Idle.** Screensaver and lock timeouts (5m / 15m / 30m / 1 Hr / Off) written straight into the
`idle` block of `~/.config/omarchy/shell.json`, so they stay in step with the shell.

Keyboard: arrow keys walk the profiles, or drive the brightness slider while it holds the cursor,
Enter activates, Escape closes, and Tab moves to the next panel.

## Auto-dim needs the tracker

`idle-check.sh` only reads a timestamp that `idle-tracker.sh` writes, so auto-dim does nothing until
that tracker is running. Add it to your Hyprland autostart:

```
exec-once = ~/.config/omarchy/plugins/gerygerger.power/idle-tracker.sh
```

The tracker watches `hyprctl monitor` for key, mouse and touch events and stamps
`~/.cache/auto-dim-last-activity`. Without it the check reports 0 seconds idle and the panel never
dims.

## How brightness is resolved

Per monitor, in order:

1. **Hardware** through `omarchy-brightness-display`. Internal panels (`eDP-*`, `LVDS-*`, `DSI-*`)
   fall back to `brightnessctl`; external monitors count only DDC/CI, because a laptop backlight
   drives `eDP-*` — on a lid-closed setup that is a dark panel, not the monitor in front of you.
2. **Software dimming** through the Omarchy-managed `hyprsunset` daemon via `hyprctl hyprsunset
   gamma`, for displays with no backlight channel. Hyprland permits a single CTM manager and that
   daemon owns it, so the daemon is the dimmer rather than a second instance. Gamma back at 100
   clears the dim and leaves the night-light temperature untouched; only `gamma` is touched.

That logic lives in `brightness.sh` so it can be called on its own, and it takes an optional monitor
name:

```bash
brightness.sh get                 # focused monitor
brightness.sh set 45
brightness.sh eDP-1 set 45
```

## Charge limit

Applying a limit runs `asusctl battery limit <percent>` and then writes the same value to
`/sys/class/power_supply/BAT0..2/charge_control_end_threshold`, so the Asus EC and the kernel agree
on one number. A timer re-applies it every 5 minutes whenever the pack is on AC and creeps above the
limit while charging. The Holding ✓ / ⚠ marker in the stats is a read-back of that kernel threshold
compared against what was set, so ⚠ means something else moved it.

## Settings

Read from this widget's entry in `~/.config/omarchy/shell.json`, and written back when you change
them from the panel:

| Key | Default | Meaning |
|---|---|---|
| `showPercentage` | `false` | Draw the percentage in front of the battery icon |
| `autoDimEnabled` | `false` | Start with auto-dim on |
| `autoDimThreshold` | `300` | Seconds of idle before dimming |
| `autoDimTarget` | `50` | Brightness percentage to dim to |

```json
{
  "id": "gerygerger.power",
  "showPercentage": true,
  "autoDimEnabled": true,
  "autoDimThreshold": 900,
  "autoDimTarget": 30
}
```

The Idle section is the exception: its source of truth is the `idle` block of `shell.json`, not this
entry, and the panel writes there directly.

## IPC

```bash
omarchy-shell omarchy.power toggle
omarchy-shell omarchy.power togglePercentage
```

`open`, `close`, `show` and `hide` are also available. Everything else is applied the moment you click
it, so nothing needs a restart.

## Files

| File | Role |
|---|---|
| `Panel.qml` | The widget: chip, panel, timers and all process wiring |
| `Model.js` | Battery icon and charge-threshold logic, profile and key/value parsing |
| `brightness.sh` | Brightness get/set with the hardware → software fallback |
| `idle-tracker.sh` | Stamps last-activity from `hyprctl monitor` |
| `idle-check.sh` | Prints seconds since last activity |
| `read-idle-config.sh` | Reads the `idle` block out of `shell.json` |
| `update-idle-config.sh` | Writes one `idle` key back to `shell.json` |

## Requirements

- Omarchy 4 (Quattro)
- Battery state from UPower. Without a battery the chip hides itself
- `asusctl` for the charge limit and for reading the configured one. Everything else in the panel
  works without it, but the Charge limit section will not do anything useful
- `brightnessctl` for internal panels when the Omarchy CLI cannot reach the backlight
- `python3` for the idle config scripts
- The Omarchy CLI: `omarchy-battery-status`, `omarchy-powerprofiles-list`,
  `omarchy-powerprofiles-set`, `omarchy-brightness-display`, `omarchy-hw-display`,
  `omarchy-hyprland-monitor-focused`
- `hyprctl` with the Omarchy-managed `hyprsunset` service for software dimming

## Install

```bash
omarchy plugin enable gerygerger.power
omarchy bar move gerygerger.power --section right
```

## Remove

```bash
omarchy plugin disable gerygerger.power
```

The idle scripts are read from the plugin directory by absolute path, so also drop the
`idle-tracker.sh` line from your Hyprland autostart if you added it.

## Credits

Built on Omarchy's own `omarchy.power` widget (`clonedFrom` in the manifest) with a brightness and
auto-dim panel folded in.
