# Nordic — monochrome Instinct 3 Solar watch face

A Connect IQ watch face (Monkey C) for the **Garmin Instinct 3 Solar**, designed for
its 1-bit **black-&-white** MIP display. Everything is white on black — no color, since
the panel only has two colors. Layout:

Built only for the **Instinct 3 Solar 45mm** (`instinct3solar45mm`, 176×176, semi-octagon).
That one product id also covers the 50mm hardware. Uses the Garmin SDK loaded via
`sdkmanager` — Connect IQ **9.2.0**, device API level **6.0**.

## Display constraints (why it looks the way it does)

The Instinct 3 Solar is a transflective MIP panel: **2-color (black + white) only**, no
grays, no anti-aliasing, no alpha blending, and no burn-in. So the face leans on bold
shapes, hand-drawn icons, and ≥2px strokes for legibility, and there's no separate
dimmed always-on mode (a MIP screen is always on and never burns in).

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
