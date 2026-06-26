# Hello Garmin — minimal Instinct 3 AMOLED watch face

A small Connect IQ watch face (Monkey C) that displays the current time
(`HH:MM`, large, white) with the day name and date (`FRI 26.06.26`) beneath it —
day name in green, date in gray — and a bottom row of live metrics: heart rate
(red, with a heart icon), steps (blue), and battery (a charge-level battery icon
plus a percentage colored green/yellow/red by level). All on black. Built for the
**Garmin Instinct 3 AMOLED** (45mm + 50mm).

Uses the Garmin SDK loaded via `sdkmanager` — Connect IQ **9.2.0**, device API level **6.0**.

## Layout

```
manifest.xml              app declaration (id, type=watchface, products, min API)
monkey.jungle             build config (points at manifest.xml)
source/
  HelloGarminApp.mc       Application.AppBase — returns the initial view
  HelloGarminView.mc      WatchUi.WatchFace  — draws the time in onUpdate()
resources/
  layouts/layout.xml      empty (the face is drawn entirely in code)
  strings/strings.xml     app name ("Hello Garmin")
  drawables/              launcher icon + drawables.xml
developer_key.der         personal signing key (generated, gitignored)
bin/                      build output (gitignored)
```

## How it works (the 30-second tour)

1. `manifest.xml` declares the app as a `watchface`, lists the target devices, and names
   the entry class (`HelloGarminApp`).
2. `HelloGarminApp.getInitialView()` returns a `HelloGarminView`.
3. `HelloGarminView` is a `WatchFace`. The system calls `onUpdate()` ~once a minute;
   it draws directly on the `Dc`: the time from `System.getClockTime()`, the day name
   and `dd.mm.yy` date from `Time.Gregorian.info()`, and a metrics row built from
   `ActivityMonitor` (steps + heart-rate history), `Activity.getActivityInfo()`
   (live HR during activities), and `System.getSystemStats()` (battery). Drawing in
   code (rather than layout labels) lets each element use its own colors and icons,
   centered as a unit. None of these data sources need manifest permissions.

## Build & run

Requires [Task](https://taskfile.dev). The first build auto-generates a signing key.

```sh
task key      # one-time: create developer_key.der
task build    # compile -> bin/HelloGarmin.prg
task sim      # launch the Connect IQ simulator (leave it open)
task run      # push the app to the simulator
```

Switch watch size by overriding the device, e.g.:

```sh
task run DEVICE=instinct3amoled50mm
```

## Next steps (intentionally not included yet)

- **Always-on display (AOD) / burn-in protection** — required to publish an AMOLED face
  to the Connect IQ Store. The empty `onEnterSleep`/`onExitSleep` in the view are the hooks.
- Complications, custom fonts, user settings, configurable metric layout.
