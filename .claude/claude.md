## Layout

```
manifest.xml              app declaration (id, type=watchface, product, permissions, min API)
monkey.jungle             build config (points at manifest.xml)
taskfile.yml              build/run tasks (key, build, sim, run, font)
source/
  NordicApp.mc            Application.AppBase — returns the initial view
  NordicView.mc           WatchUi.WatchFace  — draws the whole face in onUpdate()
resources/
  layouts/layout.xml      empty (the face is drawn entirely in code)
  strings/strings.xml     app name ("Nordic")
  drawables/              launcher icon + 7 monochrome SVG stat/status icons + drawables.xml
  fonts/                  3 custom 1-bit bitmap fonts (NordicHero/Label/Small), regen via `task font`
tools/
  genfont.py              renders the bitmap fonts from TTFs (needs Pillow)
  preview_face.py         static layout preview -> /tmp/nordic_preview.png
developer_key.der         personal signing key (generated, gitignored)
bin/                      build output (gitignored)
```

## How it works (the 30-second tour)

1. `manifest.xml` declares the app as a `watchface`, targets `instinct3solar45mm`, requests the
   `SensorHistory` permission (needed for Body Battery), and names the entry class (`NordicApp`).
2. `NordicApp.getInitialView()` returns a `NordicView`.
3. `NordicView` is a `WatchFace`. The system calls `onUpdate()` once a minute in low power, but
   up to ~once a second during the brief high-power window after a wrist raise. To keep that burst
   cheap it reads sensors/settings and builds every display string once per clock minute
   (`refreshCache`); the draw methods then just blit the cached strings on the `Dc`:
   - time from `System.getClockTime()` (honoring the device 12/24-hour setting) and the date
     from `Time.Gregorian.info()`;
   - heart rate from `Activity.getActivityInfo()` (live, read every frame) with an
     `ActivityMonitor` history fallback (cached), placed via `WatchUi.getSubscreen()`;
   - steps from `ActivityMonitor` and Body Battery from `SensorHistory`;
   - watch battery from `System.getSystemStats()` and the status flags
     (notifications / alarms / phone connection) from `System.getDeviceSettings()`.
   - Stat/status icons are monochrome SVG drawables, rasterized to 1-bit bitmaps and loaded once
     in `onLayout` (only the watch-battery cell is drawn from primitives).
   Only Body Battery needs a permission (`SensorHistory`); everything else is permission-free.
