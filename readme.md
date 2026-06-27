# Nordic — monochrome Instinct 3 Solar watch face

A Connect IQ watch face (Monkey C) for the **Garmin Instinct 3 Solar**, designed for
its 1-bit **black-&-white** MIP display. Everything is white on black — no color, since
the panel only has two colors. Layout:

- **Heart rate** in the top-right circular sub-window (ring + heart glyph + bpm).
- **Left column** of two icon+value rows: **steps** (footprint) and **Body Battery** (figure).
- A large **split time** (`03  55` — hour and minute as two big numbers with a center gap),
  with the **date** (`SAT 27.06`) in a small font directly beneath it.
- A bottom **status-icon row**: watch battery (with a charge-level fill) is always shown;
  notifications, alarm, and Bluetooth icons appear only when active, centered as a group.
- Thin white lines separate the sections, with small accent ticks at 12 and 6 o'clock.

Built only for the **Instinct 3 Solar 45mm** (`instinct3solar45mm`, 176×176, semi-octagon).
That one product id also covers the 50mm hardware. Uses the Garmin SDK loaded via
`sdkmanager` — Connect IQ **9.2.0**, device API level **6.0**.

## Display constraints (why it looks the way it does)

The Instinct 3 Solar is a transflective MIP panel: **2-color (black + white) only**, no
grays, no anti-aliasing, no alpha blending, and no burn-in. So the face leans on bold
shapes, hand-drawn icons, and ≥2px strokes for legibility, and there's no separate
dimmed always-on mode (a MIP screen is always on and never burns in).

## Layout

```
manifest.xml              app declaration (id, type=watchface, product, permissions, min API)
monkey.jungle             build config (points at manifest.xml)
source/
  NordicApp.mc            Application.AppBase — returns the initial view
  NordicView.mc           WatchUi.WatchFace  — draws the whole face in onUpdate()
resources/
  layouts/layout.xml      empty (the face is drawn entirely in code)
  strings/strings.xml     app name ("Nordic")
  drawables/              launcher icon + drawables.xml
developer_key.der         personal signing key (generated, gitignored)
bin/                      build output (gitignored)
```

## How it works (the 30-second tour)

1. `manifest.xml` declares the app as a `watchface`, targets `instinct3solar45mm`, requests the
   `SensorHistory` permission (needed for Body Battery), and names the entry class (`NordicApp`).
2. `NordicApp.getInitialView()` returns a `NordicView`.
3. `NordicView` is a `WatchFace`. The system calls `onUpdate()` ~once a minute; it clears the
   screen and draws directly on the `Dc`:
   - time from `System.getClockTime()` and the date from `Time.Gregorian.info()`;
   - heart rate from `Activity.getActivityInfo()` (live) with an `ActivityMonitor` history
     fallback, placed in the sub-window via `WatchUi.getSubscreen()`;
   - steps from `ActivityMonitor` and Body Battery from `SensorHistory` (cached per minute);
   - watch battery from `System.getSystemStats()` and the status flags
     (notifications / alarms / phone connection) from `System.getDeviceSettings()`.
   - Icons are drawn from graphics primitives (circles, polygons, lines), all in white.
   Only Body Battery needs a permission (`SensorHistory`); everything else is permission-free.

## Build & run

Requires [Task](https://taskfile.dev). The first build auto-generates a signing key.

```sh
task key      # one-time: create developer_key.der
task build    # compile -> bin/Nordic.prg
task sim      # launch the Connect IQ simulator (leave it open)
task run      # push the app to the simulator
```

In the simulator, pick **Instinct 3 Solar 45mm**. To preview the bottom status icons, set
the relevant state in the sim (Settings → phone connection, notification count, alarm count).

## Next steps (intentionally not included yet)

- A custom **bitmap font** for an even larger time (the built-in number fonts top out ~41px).
- Complications, user settings, and a configurable metric layout.
