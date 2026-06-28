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
// FORMAT_SHORT returns day_of_week as a number 1=Sunday .. 7=Saturday, which is
// guaranteed in range, so the -1 index is always safe. We keep a fixed English
// table (rather than FORMAT_MEDIUM's localized strings) to stay deterministic and
// locale-independent.
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

// Heart-rate sub-window. When WatchUi.getSubscreen() returns null we fall back to
// the known sub-window center on the Instinct 3 Solar; HR_DX nudges the heart + bpm
// right so they center in the physical window on the device (tune if needed).
const HR_FALLBACK_X = 144;
const HR_FALLBACK_Y = 31;
const HR_DX = 1;

// Hero time, date, and the bottom status row (all centered).
const TIME_Y = 108;
const DATE_Y = 146;
const STATUS_Y = 167;
// Bottom status row = battery cell + "NN%", then any active bell/alarm/bt icons,
// centered as a group by measured width.
const BATTERY_W = 16;        // total drawn width of the battery cell (body + nub)
const BATTERY_H = 8;         // height of the battery cell
const BATTERY_NUB_W = 2;     // terminal nub width (included in BATTERY_W)
const STATUS_GAP_PCT = 4;    // gap between the battery cell and its percentage
const STATUS_GAP_ICON = 10;  // gap before each trailing status icon
const STATUS_ICON_W = 18;    // width of a status icon

// "Nordic": a clean, minimal monochrome data face for the Instinct 3 Solar
// (176x176, 1-bit black + white MIP, semi-octagon with a top-right circular
// sub-window). Typography-led — a big custom-font time is the hero, with a couple
// of quiet stats and generous black space; no divider lines or accents.
//
// Layout:
//   - Top-left: three icon+value rows  (steps / body battery / distance)
//   - Top-right circular sub-window: heart rate  (heart glyph + bpm)
//   - Center: a big time  ("16:26"), with the date beneath it  ("SAT 27.06")
//   - Bottom: a status-icon row  (battery, + notifications/alarm/bluetooth when active)
class NordicView extends WatchUi.WatchFace {

    // ---- per-minute cache ----------------------------------------------------
    // The face shows no seconds, so every displayed value changes at most once a
    // minute. In high-power mode (after a wrist raise) onUpdate fires up to ~60x/min,
    // so we read sensors/settings and build every display string ONCE when the clock
    // minute changes (refreshCache), then the draw methods just blit the cached
    // strings. The only live read is the in-activity heart rate (see currentHeartRate).
    private var mCacheMin as Number = -1;

    private var mBodyBattery as Number? = null;  // newest Body Battery sample (cached)
    private var mHrHistory as Number? = null;     // newest all-day HR sample (cached fallback)

    private var mTimeText as String = "";
    private var mDateText as String = "";
    private var mStepsText as String = "";
    private var mBodyText as String = "";
    private var mDistText as String = "";

    private var mBattPct as Float = 0.0;
    private var mBattText as String = "";
    private var mBattTextW as Number = 0;

    private var mShowBell as Boolean = false;
    private var mShowAlarm as Boolean = false;
    private var mShowBt as Boolean = false;

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
    private var mSmallFont as WatchUi.FontResource?;

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
        mSmallFont = WatchUi.loadResource(Rez.Fonts.NordicSmall) as WatchUi.FontResource;
    }

    // Force a cache refresh on the next draw whenever the face becomes visible, so a
    // change made while we were hidden (e.g. the user toggling 12/24h in settings)
    // is picked up immediately rather than up to a minute later.
    function onShow() as Void {
        mCacheMin = -1;
    }

    // The custom hero font, or the system number font if it failed to load.
    private function heroFont() as Graphics.FontType {
        return (mTimeFont != null) ? mTimeFont : Graphics.FONT_NUMBER_THAI_HOT;
    }

    // The custom label font, or the system FONT_XTINY if it failed to load.
    private function labelFont() as Graphics.FontType {
        return (mLabelFont != null) ? mLabelFont : Graphics.FONT_XTINY;
    }

    // The small custom font (battery %), or the system FONT_XTINY if it failed.
    private function smallFont() as Graphics.FontType {
        return (mSmallFont != null) ? mSmallFont : Graphics.FONT_XTINY;
    }

    // Draw the whole face. A MIP display has no burn-in, so there's no separate
    // dimmed always-on face — we always draw the full layout. With no seconds shown,
    // the system's once-per-minute updates in low power cover it, and the per-minute
    // cache keeps the high-power burst cheap.
    function onUpdate(dc as Dc) as Void {
        var clockTime = System.getClockTime();

        // Rebuild every cached value/string only when the displayed minute changes.
        if (clockTime.min != mCacheMin) {
            mCacheMin = clockTime.min;
            refreshCache(dc, clockTime);
        }

        var cx = dc.getWidth() / 2;

        // Opaque black base for this frame.
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        // The whole face is white-on-transparent, and nothing changes the foreground
        // afterward, so set the pen once here instead of before every draw. (drawIcon
        // needs no color: drawBitmap renders from the bitmap's own palette.)
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        drawHeartRate(dc);
        drawStats(dc);
        drawBigTime(dc, cx);
        drawDateLine(dc, cx);
        drawStatusIcons(dc, cx);
    }

    // Read every sensor/setting and build every display string. Called once per clock
    // minute (and once on show) — never in the per-second high-power path.
    private function refreshCache(dc as Dc, clockTime as System.ClockTime) as Void {
        var info = ActivityMonitor.getInfo();
        var settings = System.getDeviceSettings();
        var stats = System.getSystemStats();

        mBodyBattery = getBodyBattery();
        mHrHistory = getHeartRateHistory();

        // Hero time, honoring the device 12/24h setting (leading zero kept either way).
        var h = clockTime.hour;
        if (!settings.is24Hour) {
            h = h % 12;
            if (h == 0) {
                h = 12;
            }
        }
        mTimeText = h.format("%02d") + ":" + clockTime.min.format("%02d");

        // Date line, e.g. "SAT 27.06".
        var di = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        mDateText = DAY_NAMES[di.day_of_week - 1] + " "
            + Lang.format("$1$.$2$", [di.day.format("%02d"), di.month.format("%02d")]);

        // Left-column stats. Each shows "--" when its source is unavailable.
        var s = (info == null) ? null : info.steps;
        mStepsText = (s == null) ? "--" : groupThousands(s);
        var bb = mBodyBattery;
        mBodyText = (bb == null) ? "--" : (bb.format("%d") + "%");
        var d = (info == null) ? null : info.distance;
        mDistText = formatDistance(d, settings);

        // Watch battery (cell + percentage), plus the measured width used to center
        // the bottom status group.
        mBattPct = stats.battery;
        mBattText = mBattPct.toNumber().format("%d") + "%";
        mBattTextW = dc.getTextWidthInPixels(mBattText, smallFont());

        // Bottom-row flags. notificationCount is Garmin's count of active notifications.
        var notif = settings.notificationCount;
        mShowBell = (notif != null && notif > 0);
        var alarms = settings.alarmCount;
        mShowAlarm = (alarms != null && alarms > 0);
        mShowBt = settings.phoneConnected;
    }

    // Heart rate in the top-right sub-window: a heart glyph + the bpm number (or
    // "--"). No drawn ring — the window's own hardware bezel frames it, so there's
    // nothing to misalign. Geometry comes from WatchUi.getSubscreen() (fallback to
    // known coordinates).
    private function drawHeartRate(dc as Dc) as Void {
        var sx; var sy;
        var sub = WatchUi.getSubscreen();
        if (sub != null) {
            sx = sub.x + sub.width / 2;
            sy = sub.y + sub.height / 2;
        } else {
            sx = HR_FALLBACK_X; sy = HR_FALLBACK_Y;
        }
        sx += HR_DX;  // nudge the heart+bpm to center them in the physical window

        drawIcon(dc, mIconHeart, sx, sy - 9);
        var hr = currentHeartRate();
        dc.drawText(sx, sy + 8, labelFont(), (hr == null) ? "--" : hr.format("%d"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Left stat column: three icon + value rows in line — steps, Body Battery, and
    // distance. Values are built once per minute in refreshCache.
    private function drawStats(dc as Dc) as Void {
        drawIcon(dc, mIconSteps, STAT_X_ICON, STAT_Y_STEPS);
        drawValue(dc, STAT_X_VAL, STAT_Y_STEPS, mStepsText);

        drawIcon(dc, mIconBody, STAT_X_ICON, STAT_Y_BODY);
        drawValue(dc, STAT_X_VAL, STAT_Y_BODY, mBodyText);

        drawIcon(dc, mIconDistance, STAT_X_ICON, STAT_Y_DIST);
        drawValue(dc, STAT_X_VAL, STAT_Y_DIST, mDistText);
    }

    private function drawValue(dc as Dc, x as Number, y as Number, text as String) as Void {
        dc.drawText(x, y, labelFont(), text,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // The hero: a big HH:MM, centered (the number font includes the ":" glyph).
    private function drawBigTime(dc as Dc, cx as Number) as Void {
        dc.drawText(cx, TIME_Y, heroFont(), mTimeText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // The date directly below the time, in a small font (e.g. "SAT 27.06").
    private function drawDateLine(dc as Dc, cx as Number) as Void {
        dc.drawText(cx, DATE_Y, labelFont(), mDateText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Bottom status row: the watch battery (cell + "NN%") is always shown;
    // notifications, alarm, and Bluetooth icons follow only when active. The whole
    // group is centered by its measured width so the battery percentage fits.
    private function drawStatusIcons(dc as Dc, cx as Number) as Void {
        var batteryW = BATTERY_W + STATUS_GAP_PCT + mBattTextW;
        var extras = (mShowBell ? 1 : 0) + (mShowAlarm ? 1 : 0) + (mShowBt ? 1 : 0);

        // Center the whole [battery + %] [icons...] group.
        var totalW = batteryW + extras * (STATUS_GAP_ICON + STATUS_ICON_W);
        var x = cx - totalW / 2;

        drawBatteryIcon(dc, x + BATTERY_W / 2, STATUS_Y, mBattPct);
        dc.drawText(x + BATTERY_W + STATUS_GAP_PCT, STATUS_Y, smallFont(), mBattText,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        x += batteryW;

        if (mShowBell) {
            x += STATUS_GAP_ICON;
            drawIcon(dc, mIconBell, x + STATUS_ICON_W / 2, STATUS_Y);
            x += STATUS_ICON_W;
        }
        if (mShowAlarm) {
            x += STATUS_GAP_ICON;
            drawIcon(dc, mIconAlarm, x + STATUS_ICON_W / 2, STATUS_Y);
            x += STATUS_ICON_W;
        }
        if (mShowBt) {
            x += STATUS_GAP_ICON;
            drawIcon(dc, mIconBt, x + STATUS_ICON_W / 2, STATUS_Y);
            x += STATUS_ICON_W;
        }
    }

    // ---- data getters (all null-safe) ----------------------------------------

    // Most recent heart rate in bpm, or null when none is available. The live
    // in-activity reading (Activity.Info) is checked every frame so HR feels current
    // during a workout; otherwise we use the all-day history sample cached per minute.
    private function currentHeartRate() as Number? {
        var info = Activity.getActivityInfo();
        if (info != null && info.currentHeartRate != null) {
            return info.currentHeartRate;
        }
        return mHrHistory;
    }

    // Newest all-day heart-rate sample in bpm, or null. Uses a history iterator, so
    // it is read once per minute (in refreshCache), not on every frame.
    private function getHeartRateHistory() as Number? {
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

    // Draw a bitmap icon centered at (cx, cy). No-op if it failed to load. No
    // setColor needed: drawBitmap renders from the bitmap's own (white) palette.
    private function drawIcon(dc as Dc, bmp as WatchUi.BitmapResource?, cx as Number, cy as Number) as Void {
        if (bmp != null) {
            dc.drawBitmap(cx - bmp.getWidth() / 2, cy - bmp.getHeight() / 2, bmp);
        }
    }

    // Watch battery: an outlined cell + terminal nub + a charge-level fill. All
    // horizontal sizes derive from BATTERY_W so the cell stays consistent with the
    // centering math in drawStatusIcons. cx is the cell center.
    private function drawBatteryIcon(dc as Dc, cx as Number, cy as Number, pct as Float) as Void {
        var left = cx - BATTERY_W / 2;          // body's left edge
        var bodyW = BATTERY_W - BATTERY_NUB_W;  // outlined body width (nub sits to its right)
        dc.setPenWidth(1);
        dc.drawRectangle(left, cy - BATTERY_H / 2, bodyW, BATTERY_H);  // body
        dc.fillRectangle(left + bodyW, cy - 2, BATTERY_NUB_W, 4);      // terminal nub
        // Interior cavity is bodyW-2 wide (inside the 1px walls), starting 1px in, so
        // a full charge fills it edge to edge.
        var fillW = ((bodyW - 2) * pct / 100.0).toNumber();
        if (fillW > 0) {
            dc.fillRectangle(left + 1, cy - 2, fillW, 4);
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
