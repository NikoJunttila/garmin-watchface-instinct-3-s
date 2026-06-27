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

// A monochrome "data face" for the Instinct 3 Solar: a 176x176, 1-bit (black +
// white only) MIP, semi-octagon display with the iconic top-right circular
// sub-window. Everything is white on black — there is no grey or accent color
// available, so layout and clear shapes carry the design, not color.
//
// Layout (HH:MM is the hero; HR lives in the sub-window; stats sit in a row):
//   GARMIN                (brand, top center)
//   SAT 27.06     (HR)    (date top-left; heart-rate inside the sub-window)
//        8:25             (big time, center)
//   STEPS  BODY  BATT     (a divided 3-column stat row)
//   8,431   62    87%
class NordicView extends WatchUi.WatchFace {

    // SensorHistory (Body Battery) reads aren't free, and in high-power mode
    // onUpdate fires up to 60x/min. Cache the value and refresh it only when the
    // clock minute changes.
    private var mCacheMin as Number = -1;
    private var mBodyBattery as Number? = null;

    function initialize() {
        WatchFace.initialize();
    }

    // Load the (empty) layout once; the face is drawn entirely in onUpdate.
    function onLayout(dc as Dc) as Void {
        setLayout(Rez.Layouts.WatchFace(dc));
    }

    function onShow() as Void {
    }

    // Draw the whole face. A MIP display has no burn-in, so there's no separate
    // dimmed always-on face — we always draw the full layout. With no seconds
    // shown, the system's once-per-minute updates in low power cover it.
    function onUpdate(dc as Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
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

        // ----- Date, top-left (e.g. "SAT 27.06"). -----
        drawDate(dc);

        // ----- Heart rate, inside the top-right circular sub-window. -----
        drawHeartRate(dc, width, height);

        // ----- Time — the dominant element, centered. -----
        var timeString = Lang.format("$1$:$2$", [clockTime.hour, clockTime.min.format("%02d")]);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 84, Graphics.FONT_NUMBER_THAI_HOT, timeString,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ----- Bottom stat row: steps | body battery | battery %. -----
        drawStatRow(dc, info);
    }

    // Date as "DAY DD.MM", left-justified just below the top-left chamfer.
    private function drawDate(dc as Dc) as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var dateString = DAY_NAMES[info.day_of_week - 1] + " "
            + Lang.format("$1$.$2$", [info.day.format("%02d"), info.month.format("%02d")]);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(16, 40, Graphics.FONT_SMALL, dateString,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Heart rate in the round sub-window: a white ring, a small heart glyph, and
    // the bpm number (or "--"). Geometry comes from WatchUi.getSubscreen() so it
    // lands exactly in the hardware sub-window; falls back to known coordinates.
    private function drawHeartRate(dc as Dc, width as Number, height as Number) as Void {
        var sx; var sy; var sr;
        var sub = WatchUi.getSubscreen();
        if (sub != null) {
            sx = sub.x + sub.width / 2;
            sy = sub.y + sub.height / 2;
            sr = sub.width / 2;
        } else {
            sx = 144; sy = 31; sr = 31;
        }

        // Ring (kept 1px inside the window so the 2px stroke doesn't clip).
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(sx, sy, sr - 1);
        dc.setPenWidth(1);

        // Heart glyph above center.
        drawHeart(dc, sx, sy - 10, 1.0, Graphics.COLOR_WHITE);

        // bpm number below center.
        var hr = getHeartRate();
        var hrText = (hr == null) ? "--" : hr.format("%d");
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(sx, sy + 8, Graphics.FONT_XTINY, hrText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // The bottom stat bar: a top divider line, two vertical separators, and three
    // columns (steps / body battery / battery %), each an icon over a value.
    private function drawStatRow(dc as Dc, info as ActivityMonitor.Info?) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(16, 114, 160, 114);   // top divider
        dc.drawLine(64, 118, 64, 150);    // separator 1
        dc.drawLine(112, 118, 112, 150);  // separator 2
        dc.setPenWidth(1);

        // Steps.
        var s = (info == null) ? null : info.steps;
        var stepsText = groupThousands((s == null) ? 0 : s);

        // Body Battery (cached).
        var bb = mBodyBattery;
        var bodyText = (bb == null) ? "--" : bb.format("%d");

        // Watch battery.
        var battery = System.getSystemStats().battery;
        var battText = (battery + 0.5).toNumber().format("%d") + "%";

        var iconY = 125;
        drawStepsIcon(dc, 40, iconY);
        drawBodyIcon(dc, 88, iconY);
        drawBatteryIcon(dc, 136, iconY, battery);

        var valueY = 143;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(40, valueY, Graphics.FONT_XTINY, stepsText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(88, valueY, Graphics.FONT_XTINY, bodyText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(136, valueY, Graphics.FONT_XTINY, battText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ---- stat icons (all white, centered at (cx, cy), ~16px tall) -------------

    // Steps: a single footprint — toe dots above a ball + heel sole.
    private function drawStepsIcon(dc as Dc, cx as Number, cy as Number) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx - 3, cy - 6, 1);
        dc.fillCircle(cx - 1, cy - 7, 1);
        dc.fillCircle(cx + 1, cy - 7, 1);
        dc.fillCircle(cx + 3, cy - 6, 1);
        dc.fillCircle(cx, cy - 1, 4);          // ball of the foot
        dc.fillCircle(cx - 1, cy + 5, 3);      // heel
        dc.fillPolygon([
            [cx - 4, cy - 1],
            [cx + 4, cy - 1],
            [cx + 2, cy + 5],
            [cx - 4, cy + 5]
        ] as Array<Graphics.Point2D>);         // arch joining ball to heel
    }

    // Body Battery: a person silhouette (head + torso) — "your body's" energy.
    private function drawBodyIcon(dc as Dc, cx as Number, cy as Number) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy - 5, 3);          // head
        dc.fillPolygon([
            [cx - 5, cy + 6],
            [cx + 5, cy + 6],
            [cx + 3, cy - 2],
            [cx - 3, cy - 2]
        ] as Array<Graphics.Point2D>);         // shoulders / torso
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

    // ---- formatting / drawing helpers ----------------------------------------

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

    // A filled heart centered at (cx, cy): two top lobes + a point. `s` scales it
    // (1.0 ~= a small ~12px glyph).
    private function drawHeart(dc as Dc, cx as Number, cy as Number, s as Float, color as Number) as Void {
        var lobeR = (4 * s).toNumber();
        var dx = (3 * s).toNumber();
        var dy = (1 * s).toNumber();
        var pw = (6 * s).toNumber();
        var ph = (7 * s).toNumber();
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx - dx, cy - dy, lobeR);
        dc.fillCircle(cx + dx, cy - dy, lobeR);
        dc.fillPolygon([
            [cx - pw, cy],
            [cx + pw, cy],
            [cx, cy + ph]
        ] as Array<Graphics.Point2D>);
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
