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

// ---- Layout geometry (px on the 176x176 panel). Single source of truth — tune
//      here, not inside the draw methods. The face is deliberately minimal:
//      whitespace and alignment do the work, so there are no divider lines or
//      decorations to crowd the type. ----

// Left stat column: a small icon + its value, three rows in line (steps, body
// battery, distance), starting high enough that all three clear the hero time.
const STAT_X_ICON = 22;
const STAT_X_VAL = 42;
const STAT_Y_STEPS = 30;
const STAT_Y_BODY = 52;
const STAT_Y_DIST = 74;

// Hero time, date, and the bottom status row (all centered).
const TIME_Y = 108;
const DATE_Y = 146;
const STATUS_Y = 167;
const STATUS_SLOT = 28;

// "Nordic": a clean, minimal monochrome data face for the Instinct 3 Solar
// (176x176, 1-bit black + white MIP, semi-octagon with a top-right circular
// sub-window). Typography-led — a big custom-font time is the hero, with a couple
// of quiet stats and generous black space; no divider lines or accents.
//
// Layout:
//   - Top-left: two icon+value rows  (steps / body battery)
//   - Top-right circular sub-window: heart rate  (heart glyph + bpm)
//   - Center: a big time  ("16:26"), with the date beneath it  ("SAT 27.06")
//   - Bottom: a status-icon row  (battery, + notifications/alarm/bluetooth when active)
class NordicView extends WatchUi.WatchFace {

    // SensorHistory (Body Battery) reads aren't free, and in high-power mode
    // onUpdate fires up to 60x/min. Cache the value and refresh it only when the
    // clock minute changes.
    private var mCacheMin as Number = -1;
    private var mBodyBattery as Number? = null;

    // Stat / status icons, loaded once from SVG drawables (see resources/drawables).
    private var mIconHeart as WatchUi.BitmapResource?;
    private var mIconSteps as WatchUi.BitmapResource?;
    private var mIconBody as WatchUi.BitmapResource?;
    private var mIconBell as WatchUi.BitmapResource?;
    private var mIconAlarm as WatchUi.BitmapResource?;
    private var mIconBt as WatchUi.BitmapResource?;
    private var mIconDistance as WatchUi.BitmapResource?;

    // Custom 1-bit bitmap fonts (resources/fonts). If a load ever fails these stay
    // null and the heroFont()/labelFont() helpers fall back to the system fonts, so
    // the face always renders.
    private var mTimeFont as WatchUi.FontResource?;
    private var mLabelFont as WatchUi.FontResource?;

    function initialize() {
        WatchFace.initialize();
    }

    // Load the (empty) layout, the icon bitmaps, and the custom fonts once.
    function onLayout(dc as Dc) as Void {
        setLayout(Rez.Layouts.WatchFace(dc));
        mIconHeart = WatchUi.loadResource(Rez.Drawables.IconHeart) as WatchUi.BitmapResource;
        mIconSteps = WatchUi.loadResource(Rez.Drawables.IconSteps) as WatchUi.BitmapResource;
        mIconBody = WatchUi.loadResource(Rez.Drawables.IconBody) as WatchUi.BitmapResource;
        mIconBell = WatchUi.loadResource(Rez.Drawables.IconBell) as WatchUi.BitmapResource;
        mIconAlarm = WatchUi.loadResource(Rez.Drawables.IconAlarm) as WatchUi.BitmapResource;
        mIconBt = WatchUi.loadResource(Rez.Drawables.IconBluetooth) as WatchUi.BitmapResource;
        mIconDistance = WatchUi.loadResource(Rez.Drawables.IconDistance) as WatchUi.BitmapResource;
        mTimeFont = WatchUi.loadResource(Rez.Fonts.NordicHero) as WatchUi.FontResource;
        mLabelFont = WatchUi.loadResource(Rez.Fonts.NordicLabel) as WatchUi.FontResource;
    }

    function onShow() as Void {
    }

    // The custom hero font, or the system number font if it failed to load.
    private function heroFont() as Graphics.FontType {
        return (mTimeFont != null) ? mTimeFont : Graphics.FONT_NUMBER_THAI_HOT;
    }

    // The custom label font, or the system FONT_XTINY if it failed to load.
    private function labelFont() as Graphics.FontType {
        return (mLabelFont != null) ? mLabelFont : Graphics.FONT_XTINY;
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

        drawHeartCircle(dc);
        drawStats(dc, info, settings);
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
        dc.drawText(sx, sy + 8, labelFont(), (hr == null) ? "--" : hr.format("%d"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Left stat column: three icon + value rows in line — steps, Body Battery, and
    // distance. Each value shows "--" when unavailable.
    private function drawStats(dc as Dc, info as ActivityMonitor.Info?, settings as System.DeviceSettings) as Void {
        // Steps.
        drawIcon(dc, mIconSteps, STAT_X_ICON, STAT_Y_STEPS);
        var s = (info == null) ? null : info.steps;
        drawValue(dc, STAT_X_VAL, STAT_Y_STEPS, groupThousands((s == null) ? 0 : s));

        // Body Battery (cached), shown as a percentage.
        drawIcon(dc, mIconBody, STAT_X_ICON, STAT_Y_BODY);
        var bb = mBodyBattery;
        drawValue(dc, STAT_X_VAL, STAT_Y_BODY, (bb == null) ? "--" : (bb.format("%d") + "%"));

        // Distance today.
        drawIcon(dc, mIconDistance, STAT_X_ICON, STAT_Y_DIST);
        var d = (info == null) ? null : info.distance;
        drawValue(dc, STAT_X_VAL, STAT_Y_DIST, formatDistance(d, settings));
    }

    private function drawValue(dc as Dc, x as Number, y as Number, text as String) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, labelFont(), text,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // The hero: a big HH:MM, centered (the number font includes the ":" glyph).
    private function drawBigTime(dc as Dc, cx as Number, clockTime as System.ClockTime) as Void {
        var t = clockTime.hour.format("%02d") + ":" + clockTime.min.format("%02d");
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, TIME_Y, heroFont(), t,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // The date directly below the time, in a small font (e.g. "SAT 27.06").
    private function drawDateLine(dc as Dc, cx as Number) as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var text = DAY_NAMES[info.day_of_week - 1] + " "
            + Lang.format("$1$.$2$", [info.day.format("%02d"), info.month.format("%02d")]);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, DATE_Y, labelFont(), text,
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
        var startC = cx - (n - 1) * STATUS_SLOT / 2;
        for (var i = 0; i < n; i += 1) {
            var xc = startC + i * STATUS_SLOT;
            var k = icons[i];
            if (k == :battery) {
                drawBatteryIcon(dc, xc, STATUS_Y, System.getSystemStats().battery);
            } else if (k == :bell) {
                drawIcon(dc, mIconBell, xc, STATUS_Y);
            } else if (k == :alarm) {
                drawIcon(dc, mIconAlarm, xc, STATUS_Y);
            } else {
                drawIcon(dc, mIconBt, xc, STATUS_Y);
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

    // Today's distance (input in centimeters) as km or mi with 2 decimals, per the
    // device's unit setting. "--" when unavailable.
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
