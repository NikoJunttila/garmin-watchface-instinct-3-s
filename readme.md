# Hello Garmin — minimal Instinct 3 AMOLED watch face

A bare-bones Connect IQ watch face (Monkey C) that displays the current time
(`HH:MM`, centered, blue). Built for the **Garmin Instinct 3 AMOLED** (45mm + 50mm).

Uses the Garmin SDK loaded via `sdkmanager` — Connect IQ **9.2.0**, device API level **6.0**.

## Layout

```
manifest.xml              app declaration (id, type=watchface, products, min API)
monkey.jungle             build config (points at manifest.xml)
source/
  HelloGarminApp.mc       Application.AppBase — returns the initial view
  HelloGarminView.mc      WatchUi.WatchFace  — draws the time in onUpdate()
resources/
  layouts/layout.xml      centered TimeLabel
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
   it formats `System.getClockTime()` into `HH:MM` and draws it via the layout.

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
- Date, battery, steps, complications, custom fonts, user settings.
