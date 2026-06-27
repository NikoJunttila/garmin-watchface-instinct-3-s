import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Abbreviated day names, indexed by (day_of_week - 1). Gregorian.info() with
// FORMAT_SHORT returns day_of_week as 1=Sunday .. 7=Saturday. (We map it
// ourselves because FORMAT_MEDIUM/LONG only return abbreviations anyway, and a
// fixed table keeps the output deterministic and locale-independent.)
const DAY_NAMES = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"] as Array<String>;

// "Nordic": a monochrome data face for the Instinct 3 Solar (176x176, 1-bit
// black + white MIP, semi-octagon with a top-right circular sub-window).
//
// Layout, adapted from a Garmin reference to this hardware:
//   - Left column: three icon+value rows  (steps / body battery / distance)
//   - Top-right circular sub-window: heart rate  (heart glyph + bpm)
//   - Center-low: a big time  ("03:55") with the date beneath it  ("SAT 27.06")
//   - Bottom: a status-icon row  (battery, + notifications/alarm/bluetooth when active)
//   - Thin white lines separate the sections, with accent ticks at 12 & 6 o'clock.
class NordicView extends WatchUi.WatchFace {

    // SensorHistory (Body Battery) reads aren't free, and in high-power mode
    // onUpdate fires up to 60x/min. Cache the value and refresh it only when the
    // clock minute changes.
    private var mCacheMin as Number = -1;
    private var mBodyBattery as Number? = null;

    // Stat icons, loaded once from SVG drawables (see resources/drawables).
    private var mIconHeart as WatchUi.BitmapResource?;
    private var mIconSteps as WatchUi.BitmapResource?;
    private var mIconBody as WatchUi.BitmapResource?;
    private var mIconBell as WatchUi.BitmapResource?;
    private var mIconAlarm as WatchUi.BitmapResource?;
    private var mIconBt as WatchUi.BitmapResource?;
    private var mIconDistance as WatchUi.BitmapResource?;

    function initialize() {
        WatchFace.initialize();
    }

    // Load the (empty) layout and the icon bitmaps once.
    function onLayout(dc as Dc) as Void {
        setLayout(Rez.Layouts.WatchFace(dc));
        mIconHeart = WatchUi.loadResource(Rez.Drawables.IconHeart) as WatchUi.BitmapResource;
        mIconSteps = WatchUi.loadResource(Rez.Drawables.IconSteps) as WatchUi.BitmapResource;
        mIconBody = WatchUi.loadResource(Rez.Drawables.IconBody) as WatchUi.BitmapResource;
        mIconBell = WatchUi.loadResource(Rez.Drawables.IconBell) as WatchUi.BitmapResource;
        mIconAlarm = WatchUi.loadResource(Rez.Drawables.IconAlarm) as WatchUi.BitmapResource;
        mIconBt = WatchUi.loadResource(Rez.Drawables.IconBluetooth) as WatchUi.BitmapResource;
        mIconDistance = WatchUi.loadResource(Rez.Drawables.IconDistance) as WatchUi.BitmapResource;
    }

    function onShow() as Void {
    }

    // Draw the whole face. A MIP display has no burn-in, so there's no separate
    // dimmed always-on face — we always draw the full layout. With no seconds
    // shown, the system's once-per-minute updates in low power cover it.
    function onUpdate(dc as Dc) as Void {
        var width = dc.getWidth();
        var cx = width / 2;

        // Background.
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var clockTime = System.getClockTime();

        // Refresh the cached Body Battery read at most once per minute.
        if (clockTime.min != mCacheMin) {
            mCacheMin = clockTime.min;
            mBodyBattery = getBodyBattery();
        }

        var info = ActivityMonitor.getInfo();
        var settings = System.getDeviceSettings();

        // ----- Section dividers + 12/6 o'clock accent ticks. -----
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(cx, 2, cx, 8);        // top tick
        dc.drawLine(cx, 169, cx, 174);    // bottom tick
        dc.drawLine(12, 88, 164, 88);     // above the time
        dc.drawLine(12, 151, 164, 151);   // below the date
        dc.setPenWidth(1);

        drawHeartCircle(dc);
        drawLeftColumn(dc, info, settings);
        drawBigTime(dc, cx, clockTime);
        drawDateLine(dc, cx);
        drawStatusIcons(dc, cx, settings);
    }

    // Heart rate in the top-right circular sub-window: a white ring, a heart
    // glyph, and the bpm number (or "--"). Geometry comes from WatchUi.getSubscreen()
    // so it lands exactly in the hardware window; falls back to known coordinates.
    private function drawHeartCircle(dc as Dc) as Void {
        var sx; var sy; var sr;
        var sub = WatchUi.getSubscreen();
        if (sub != null) {
            sx = sub.x + sub.width / 2;
            sy = sub.y + sub.height / 2;
            sr = sub.width / 2;
        } else {
            sx = 144; sy = 31; sr = 31;
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(sx, sy, sr - 1);
        dc.setPenWidth(1);

        drawIcon(dc, mIconHeart, sx, sy - 9);
        var hr = getHeartRate();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(sx, sy + 8, Graphics.FONT_XTINY, (hr == null) ? "--" : hr.format("%d"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Left column: three rows, each an icon (left) + value (right): steps, Body
    // Battery, then distance. Each value shows "--" when unavailable.
    private function drawLeftColumn(dc as Dc, info as ActivityMonitor.Info?, settings as System.DeviceSettings) as Void {
        var xIcon = 22;
        var xVal = 38;

        // Steps.
        drawIcon(dc, mIconSteps, xIcon, 36);
        var s = (info == null) ? null : info.steps;
        drawValue(dc, xVal, 36, groupThousands((s == null) ? 0 : s));

        // Body Battery (cached).
        drawIcon(dc, mIconBody, xIcon, 57);
        var bb = mBodyBattery;
        drawValue(dc, xVal, 57, (bb == null) ? "--" : bb.format("%d"));

        // Distance today.
        drawIcon(dc, mIconDistance, xIcon, 78);
        var d = (info == null) ? null : info.distance;
        drawValue(dc, xVal, 78, formatDistance(d, settings));
    }

    private function drawValue(dc as Dc, x as Number, y as Number, text as String) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, text,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // The hero: a big HH:MM, centered low on the face (the number font includes
    // the ":" glyph).
    private function drawBigTime(dc as Dc, cx as Number, clockTime as System.ClockTime) as Void {
        var t = clockTime.hour.format("%02d") + ":" + clockTime.min.format("%02d");
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 110, Graphics.FONT_NUMBER_THAI_HOT, t,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // The date directly below the time, in a small font (e.g. "SAT 27.06").
    private function drawDateLine(dc as Dc, cx as Number) as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var text = DAY_NAMES[info.day_of_week - 1] + " "
            + Lang.format("$1$.$2$", [info.day.format("%02d"), info.month.format("%02d")]);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 140, Graphics.FONT_XTINY, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Bottom status row: the watch battery is always shown; notifications, alarm,
    // and Bluetooth appear only when active. The shown icons are centered together.
    private function drawStatusIcons(dc as Dc, cx as Number, settings as System.DeviceSettings) as Void {
        var icons = [:battery] as Array<Symbol>;

        var notif = settings.notificationCount;
        if (notif != null && notif > 0) {
            icons.add(:bell);
        }
        var alarms = settings.alarmCount;
        if (alarms != null && alarms > 0) {
            icons.add(:alarm);
        }
        if (settings.phoneConnected) {
            icons.add(:bluetooth);
        }

        var n = icons.size();
        var slot = 28;
        var startC = cx - (n - 1) * slot / 2;
        var y = 160;
        for (var i = 0; i < n; i += 1) {
            var xc = startC + i * slot;
            var k = icons[i];
            if (k == :battery) {
                drawBatteryIcon(dc, xc, y, System.getSystemStats().battery);
            } else if (k == :bell) {
                drawIcon(dc, mIconBell, xc, y);
            } else if (k == :alarm) {
                drawIcon(dc, mIconAlarm, xc, y);
            } else {
                drawIcon(dc, mIconBt, xc, y);
            }
        }
    }

    // ---- data getters (all null-safe) ----------------------------------------

    // Most recent heart rate in bpm, or null when no valid reading is available.
    // Prefers Activity.Info (live during an activity); otherwise falls back to
    // the newest all-day sample from ActivityMonitor's heart-rate history.
    private function getHeartRate() as Number? {
        var info = Activity.getActivityInfo();
        if (info != null && info.currentHeartRate != null) {
            return info.currentHeartRate;
        }
        var iterator = ActivityMonitor.getHeartRateHistory(1, true);
        if (iterator != null) {
            var sample = iterator.next();
            if (sample != null && sample.heartRate != null
                    && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                return sample.heartRate;
            }
        }
        return null;
    }

    // Newest Body Battery sample (0-100), or null. Requires the SensorHistory
    // permission; the `has` guards keep it safe if the device lacks the API.
    private function getBodyBattery() as Number? {
        if (!(Toybox has :SensorHistory) || !(SensorHistory has :getBodyBatteryHistory)) {
            return null;
        }
        var iterator = SensorHistory.getBodyBatteryHistory({ :period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST });
        if (iterator != null) {
            var sample = iterator.next();
            if (sample != null && sample.data != null) {
                return sample.data.toNumber();
            }
        }
        return null;
    }

    // ---- formatting ----------------------------------------------------------

    // Thousands-separated step count, e.g. 8431 -> "8,431".
    private function groupThousands(n as Number) as String {
        var s = n.format("%d");
        var out = "";
        var c = 0;
        for (var i = s.length() - 1; i >= 0; i -= 1) {
            out = s.substring(i, i + 1) + out;
            c += 1;
            if (c % 3 == 0 && i > 0) {
                out = "," + out;
            }
        }
        return out;
    }

    // Today's distance (input in centimeters) as km or mi with 2 decimals, per
    // the device's unit setting. "--" when unavailable.
    private function formatDistance(cm as Number?, settings as System.DeviceSettings) as String {
        if (cm == null) {
            return "--";
        }
        if (settings.distanceUnits == System.UNIT_STATUTE) {
            return (cm / 160934.4).format("%.2f");
        }
        return (cm / 100000.0).format("%.2f");
    }

    // ---- icons ---------------------------------------------------------------

    // Draw a bitmap icon centered at (cx, cy). No-op if it failed to load.
    private function drawIcon(dc as Dc, bmp as WatchUi.BitmapResource?, cx as Number, cy as Number) as Void {
        if (bmp != null) {
            dc.drawBitmap(cx - bmp.getWidth() / 2, cy - bmp.getHeight() / 2, bmp);
        }
    }

    // Watch battery: an outlined cell + terminal nub + a charge-level fill.
    private function drawBatteryIcon(dc as Dc, cx as Number, cy as Number, pct as Float) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawRectangle(cx - 8, cy - 4, 14, 8);   // body
        dc.fillRectangle(cx + 6, cy - 2, 2, 4);    // terminal nub
        var fillW = (10 * pct / 100.0).toNumber();
        if (fillW > 0) {
            dc.fillRectangle(cx - 6, cy - 2, fillW, 4);
        }
    }

    function onHide() as Void {
    }

    // A MIP display has no burn-in and this face shows no seconds, so the sleep
    // transitions need no special handling — the full face is always drawn.
    function onExitSleep() as Void {
    }

    function onEnterSleep() as Void {
    }

}
