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
