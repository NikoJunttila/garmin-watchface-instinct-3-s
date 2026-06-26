import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;
import Toybox.Weather;

// Abbreviated day names, indexed by (day_of_week - 1). Gregorian.info() with
// FORMAT_SHORT returns day_of_week as 1=Sunday .. 7=Saturday. (We map it
// ourselves because FORMAT_MEDIUM/LONG only return abbreviations anyway, and a
// fixed table keeps the output deterministic and locale-independent.)
const DAY_NAMES = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"] as Array<String>;

// Weather-icon categories (see weatherCategory()).
const WX_SUN = 0;
const WX_CLOUD = 1;
const WX_RAIN = 2;
const WX_SNOW = 3;

// ---- Palette -----------------------------------------------------------------
// A single signature accent (teal) ties the face together: it fills the goal
// arcs and highlights the key values. Everything else is white / gray on black.
// Heart rate is the one "vital" exception — it gets a bold red glow so it pops.
const ACCENT = 0x16D6C4 as Number;       // teal signature accent
const ACCENT_TRACK = 0x103A37 as Number; // dim teal, for the unfilled arc track
const HR_CORE = 0xFF4438 as Number;      // bright red heart-rate value
const HR_GLOW = 0x5A0E0A as Number;      // dim red bloom drawn behind the value

// The watch face itself. The system calls onUpdate roughly once per minute in
// always-on (low-power) mode, and up to once per second while you're actively
// looking at the watch (high-power mode).
class HelloGarminView extends WatchUi.WatchFace {

    // True while the watch is in always-on / low-power mode. On this AMOLED
    // device (requiresBurnInProtection) we draw a reduced, dimmed face then.
    private var mLowPower as Boolean = false;

    // Weather.getCurrentConditions() and the SensorHistory iterator are not free,
    // and in high-power mode onUpdate fires up to 60x/min. So we cache their
    // results and only refresh when the clock minute changes (mCacheMin).
    private var mCacheMin as Number = -1;
    private var mWeather as Weather.CurrentConditions? = null;
    private var mBodyBattery as Number? = null;

    function initialize() {
        WatchFace.initialize();
    }

    // Load the layout (defined in resources/layouts/layout.xml) once.
    function onLayout(dc as Dc) as Void {
        setLayout(Rez.Layouts.WatchFace(dc));
    }

    // Brought to the foreground.
    function onShow() as Void {
    }

    // Draw the face. High-power mode gets the full arc-gauge layout; low-power
    // (always-on) mode gets a reduced, dimmed version to limit lit pixels and
    // avoid per-second updates (AMOLED burn-in protection).
    function onUpdate(dc as Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var cx = width / 2;
        var cy = height / 2;

        // Background — black is effectively "off" on AMOLED, so it costs no power.
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var clockTime = System.getClockTime();

        // Refresh the expensive cached reads at most once per minute.
        if (clockTime.min != mCacheMin) {
            mCacheMin = clockTime.min;
            mWeather = Weather.getCurrentConditions();
            mBodyBattery = getBodyBattery();
        }

        if (mLowPower) {
            drawLowPower(dc, cx, height, clockTime);
            return;
        }

        var info = ActivityMonitor.getInfo();

        // ----- Goal arcs hugging the bezel: steps (top), Body Battery (bottom). -----
        var arcR = cx - 8;
        drawStepsArc(dc, cx, cy, arcR, info);
        drawBodyBatteryArc(dc, cx, cy, arcR);

        // ----- Weather + next sun event, just inside the top arc. -----
        drawWeatherSunRow(dc, cx, (height * 0.205).toNumber());

        // ----- Steps count, in the accent color, beneath the weather row. -----
        drawSteps(dc, cx, (height * 0.305).toNumber(), info);

        // ----- Time — the dominant element, white, near center. -----
        var timeString = Lang.format("$1$:$2$", [clockTime.hour, clockTime.min.format("%02d")]);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (height * 0.43).toNumber(), Graphics.FONT_NUMBER_MEDIUM, timeString,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ----- Day name (accent) + date (gray). -----
        drawDayDate(dc, cx, (height * 0.565).toNumber());

        // ----- Heart-rate hero: bold red value with a soft glow + heart icon. -----
        drawHeartRateHero(dc, cx, (height * 0.70).toNumber());

        // ----- Body Battery value (accent) + battery, just inside the bottom arc. -----
        drawBodyBatteryValue(dc, cx, (height * 0.815).toNumber());
        drawBattery(dc, cx, (height * 0.895).toNumber());
    }

    // Reduced always-on face: time + day/date + two slow, dimmed stats. No live
    // heart rate, no arcs or filled icons, dark gray accents — keeps lit pixels low.
    private function drawLowPower(dc as Dc, cx as Number, height as Number, clockTime as System.ClockTime) as Void {
        var timeString = Lang.format("$1$:$2$", [clockTime.hour, clockTime.min.format("%02d")]);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (height * 0.42).toNumber(), Graphics.FONT_NUMBER_MEDIUM, timeString,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var dateString = DAY_NAMES[info.day_of_week - 1] + " " + Lang.format("$1$.$2$.$3$", [
            info.day.format("%02d"), info.month.format("%02d"), (info.year % 100).format("%02d")
        ]);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (height * 0.62).toNumber(), Graphics.FONT_SMALL, dateString,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var bbVal = mBodyBattery;
        var bb = (bbVal == null) ? "--" : bbVal.format("%d");
        var low = "BB " + bb + "   " + stepsValue().format("%d");
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (height * 0.76).toNumber(), Graphics.FONT_TINY, low,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ---- arcs ----------------------------------------------------------------

    // Top goal arc: steps toward the daily goal. Fills clockwise across the top
    // (left to right) from 160 deg to 20 deg as you approach your goal.
    private function drawStepsArc(dc as Dc, cx as Number, cy as Number, r as Number, info as ActivityMonitor.Info?) as Void {
        var frac = 0.0;
        var steps = (info == null) ? null : info.steps;
        var goal = (info == null) ? null : info.stepGoal;
        if (steps != null && goal != null && goal > 0) {
            frac = steps.toFloat() / goal.toFloat();
        }
        drawGaugeArc(dc, cx, cy, r, 160, 20, true, frac);
    }

    // Bottom goal arc: Body Battery (0-100). Fills counter-clockwise across the
    // bottom (left to right) from 200 deg to 340 deg.
    private function drawBodyBatteryArc(dc as Dc, cx as Number, cy as Number, r as Number) as Void {
        var frac = 0.0;
        var bb = mBodyBattery;
        if (bb != null) {
            frac = bb / 100.0;
        }
        drawGaugeArc(dc, cx, cy, r, 200, 340, false, frac);
    }

    // Draws a goal gauge: a faint full-span track plus an accent-colored fill
    // covering `frac` (0..1) of the span. `cw` = sweep clockwise (degrees count
    // down from start) vs counter-clockwise (degrees count up).
    private function drawGaugeArc(dc as Dc, cx as Number, cy as Number, r as Number, startDeg as Number, endDeg as Number, cw as Boolean, frac as Float) as Void {
        if (frac < 0.0) { frac = 0.0; }
        if (frac > 1.0) { frac = 1.0; }
        var dir = cw ? Graphics.ARC_CLOCKWISE : Graphics.ARC_COUNTER_CLOCKWISE;
        var span = cw ? (startDeg - endDeg) : (endDeg - startDeg);

        dc.setPenWidth(9);
        dc.setColor(ACCENT_TRACK, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, r, dir, startDeg, endDeg);

        if (frac > 0.01) {
            var fillEnd = cw ? (startDeg - frac * span) : (startDeg + frac * span);
            dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, r, dir, startDeg, fillEnd.toNumber());
        }
        dc.setPenWidth(1);
    }

    // ---- center / text fields ------------------------------------------------

    // Day name (accent) + date (dim gray), centered as one row at rowY.
    private function drawDayDate(dc as Dc, cx as Number, rowY as Number) as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var dayString = DAY_NAMES[info.day_of_week - 1];
        var dateString = Lang.format("$1$.$2$.$3$", [
            info.day.format("%02d"), info.month.format("%02d"), (info.year % 100).format("%02d")
        ]);

        var rowFont = Graphics.FONT_SMALL;
        var dayWidth = dc.getTextWidthInPixels(dayString, rowFont);
        var sepWidth = dc.getTextWidthInPixels(" ", rowFont);
        var dateWidth = dc.getTextWidthInPixels(dateString, rowFont);
        var startX = cx - (dayWidth + sepWidth + dateWidth) / 2;

        dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX, rowY, rowFont, dayString, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX + dayWidth + sepWidth, rowY, rowFont, dateString, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Steps count (accent), centered. The top arc shows progress toward the goal.
    private function drawSteps(dc as Dc, cx as Number, rowY as Number, info as ActivityMonitor.Info?) as Void {
        var s = (info == null) ? null : info.steps;
        var steps = (s == null) ? 0 : s;
        dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, rowY, Graphics.FONT_TINY, groupThousands(steps),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Body Battery value (accent), centered. The bottom arc shows the level.
    private function drawBodyBatteryValue(dc as Dc, cx as Number, rowY as Number) as Void {
        var bbVal = mBodyBattery;
        var bbText = (bbVal == null) ? "BODY --" : "BODY " + bbVal.format("%d");
        dc.setColor((bbVal == null) ? Graphics.COLOR_DK_GRAY : ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, rowY, Graphics.FONT_TINY, bbText, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Weather (condition icon + temperature) and the next sun event (icon + time),
    // centered together as one row. Each part degrades gracefully when unavailable.
    private function drawWeatherSunRow(dc as Dc, cx as Number, rowY as Number) as Void {
        var font = Graphics.FONT_XTINY;
        var cond = mWeather;

        var temp = (cond == null) ? null : cond.temperature;
        var hasWx = (temp != null);
        var wxIconW = 16;
        var wxGap = 5;
        var tempText = (temp != null) ? (formatTemperature(temp) + "°") : "--°";
        var wxW = dc.getTextWidthInPixels(tempText, font) + (hasWx ? wxIconW + wxGap : 0);

        var sunMoment = null;
        var isRise = true;
        var loc = (cond == null) ? null : cond.observationLocationPosition;
        if (loc != null) {
            var now = Time.now();
            var nowSec = now.value();
            var sunrise = Weather.getSunrise(loc, now);
            var sunset = Weather.getSunset(loc, now);
            if (sunrise != null && nowSec < sunrise.value()) {
                sunMoment = sunrise; isRise = true;
            } else if (sunset != null && nowSec < sunset.value()) {
                sunMoment = sunset; isRise = false;
            } else if (sunrise != null) {
                sunMoment = sunrise; isRise = true;
            }
        }
        var sunIconW = 13;
        var sunGap = 4;
        var sunText = null;
        var sunW = 0;
        if (sunMoment != null) {
            var t = Gregorian.info(sunMoment, Time.FORMAT_SHORT);
            sunText = Lang.format("$1$:$2$", [t.hour, t.min.format("%02d")]);
            sunW = sunIconW + sunGap + dc.getTextWidthInPixels(sunText, font);
        }

        var sepGap = 18;
        var total = wxW + ((sunText != null) ? sepGap + sunW : 0);
        var x = cx - total / 2;

        if (hasWx) {
            drawWeatherIcon(dc, x + wxIconW / 2, rowY, weatherCategory(cond.condition));
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + wxIconW + wxGap, rowY, font, tempText, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, rowY, font, tempText, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        x += wxW;

        if (sunText != null) {
            x += sepGap;
            drawSunIcon(dc, x + sunIconW / 2, rowY, isRise);
            dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + sunIconW + sunGap, rowY, font, sunText, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // Heart-rate hero: a heart icon + an oversized bold value with a soft red
    // glow halo, centered as one group. Shows a dim "--" when no reading exists.
    private function drawHeartRateHero(dc as Dc, cx as Number, cy as Number) as Void {
        var hr = getHeartRate();
        var font = Graphics.FONT_NUMBER_MILD;

        if (hr == null) {
            drawHeart(dc, cx - 18, cy, 1.4, Graphics.COLOR_DK_GRAY);
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx + 6, cy, font, "--", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var text = hr.format("%d");
        var numW = dc.getTextWidthInPixels(text, font);
        var heartW = 22;
        var gap = 10;
        var groupW = heartW + gap + numW;
        var startX = cx - groupW / 2;
        var heartCx = startX + heartW / 2;
        var numCx = startX + heartW + gap + numW / 2;

        drawHeart(dc, heartCx, cy, 1.7, HR_CORE);
        drawGlowText(dc, numCx, cy, font, text, HR_GLOW, HR_CORE);
    }

    // Battery: a glyph + percentage, centered. Accent normally; red when critically
    // low (the one place we break the single-accent rule, as a safety signal).
    private function drawBattery(dc as Dc, cx as Number, cy as Number) as Void {
        var battery = System.getSystemStats().battery;
        var batText = (battery + 0.5).toNumber().format("%d") + "%";
        var color = (battery <= 15) ? Graphics.COLOR_RED : ACCENT;
        var font = Graphics.FONT_XTINY;
        var bodyW = 18;
        var iconW = bodyW + 3;
        var gap = 5;
        var total = iconW + gap + dc.getTextWidthInPixels(batText, font);
        var x = cx - total / 2;

        drawBatteryIcon(dc, x, cy, bodyW, 10, battery, color);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + iconW + gap, cy, font, batText, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
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

    // Steps since midnight (0 when unavailable).
    private function stepsValue() as Number {
        var info = ActivityMonitor.getInfo();
        if (info != null && info.steps != null) {
            return info.steps;
        }
        return 0;
    }

    // ---- formatting / color helpers ------------------------------------------

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

    // Weather temperatures come from the API in Celsius; convert to the device's
    // configured unit before display.
    private function formatTemperature(tempC as Number) as String {
        if (System.getDeviceSettings().temperatureUnits == System.UNIT_STATUTE) {
            return ((tempC * 9.0 / 5.0) + 32.0 + 0.5).toNumber().format("%d");
        }
        return tempC.format("%d");
    }

    // Bucket a Weather.CONDITION_* value into one of our four drawable icons.
    private function weatherCategory(condition as Number?) as Number {
        if (condition == null) {
            return WX_CLOUD;
        }
        switch (condition) {
            case Weather.CONDITION_CLEAR:
            case Weather.CONDITION_FAIR:
            case Weather.CONDITION_MOSTLY_CLEAR:
            case Weather.CONDITION_PARTLY_CLEAR:
                return WX_SUN;
            case Weather.CONDITION_RAIN:
            case Weather.CONDITION_LIGHT_RAIN:
            case Weather.CONDITION_HEAVY_RAIN:
            case Weather.CONDITION_DRIZZLE:
            case Weather.CONDITION_SHOWERS:
            case Weather.CONDITION_LIGHT_SHOWERS:
            case Weather.CONDITION_HEAVY_SHOWERS:
            case Weather.CONDITION_SCATTERED_SHOWERS:
            case Weather.CONDITION_CHANCE_OF_SHOWERS:
            case Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN:
            case Weather.CONDITION_THUNDERSTORMS:
            case Weather.CONDITION_SCATTERED_THUNDERSTORMS:
            case Weather.CONDITION_CHANCE_OF_THUNDERSTORMS:
            case Weather.CONDITION_FREEZING_RAIN:
                return WX_RAIN;
            case Weather.CONDITION_SNOW:
            case Weather.CONDITION_LIGHT_SNOW:
            case Weather.CONDITION_HEAVY_SNOW:
            case Weather.CONDITION_FLURRIES:
            case Weather.CONDITION_CHANCE_OF_SNOW:
            case Weather.CONDITION_CLOUDY_CHANCE_OF_SNOW:
            case Weather.CONDITION_RAIN_SNOW:
            case Weather.CONDITION_WINTRY_MIX:
            case Weather.CONDITION_SLEET:
            case Weather.CONDITION_HAIL:
            case Weather.CONDITION_ICE:
            case Weather.CONDITION_ICE_SNOW:
                return WX_SNOW;
            default:
                return WX_CLOUD; // cloudy, fog, haze, wind, etc.
        }
    }

    // ---- drawing primitives --------------------------------------------------

    // Draws `text` with a soft glow: several dim passes offset around the center
    // build a bloom, then the bright core is drawn on top. Approximates a glow
    // without alpha blending (which the Dc text API doesn't offer).
    private function drawGlowText(dc as Dc, cx as Number, cy as Number, font as Graphics.FontDefinition, text as String, glow as Number, core as Number) as Void {
        var offsets = [
            [-2, 0], [2, 0], [0, -2], [0, 2],
            [-2, -2], [2, -2], [-2, 2], [2, 2],
            [-3, 0], [3, 0], [0, -3], [0, 3]
        ];
        dc.setColor(glow, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < offsets.size(); i += 1) {
            dc.drawText(cx + offsets[i][0], cy + offsets[i][1], font, text,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        dc.setColor(core, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, font, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // A filled heart centered at (cx, cy): two top lobes + a point. `s` scales it
    // (1.0 ~= the original small glyph).
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

    // A small battery glyph: outline body + terminal nub + a charge-level fill.
    // x is the body's left edge; cy is its vertical center.
    private function drawBatteryIcon(dc as Dc, x as Number, cy as Number, bodyW as Number, bodyH as Number, pct as Float, color as Number) as Void {
        var top = cy - bodyH / 2;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawRectangle(x, top, bodyW, bodyH);
        var nubH = bodyH / 2;
        dc.fillRectangle(x + bodyW, cy - nubH / 2, 2, nubH);
        var pad = 2;
        var fillW = ((bodyW - 2 * pad) * pct / 100.0).toNumber();
        if (fillW > 0) {
            dc.fillRectangle(x + pad, top + pad, fillW, bodyH - 2 * pad);
        }
    }

    // A compact weather glyph centered at (cx, cy) for one of the WX_* categories.
    private function drawWeatherIcon(dc as Dc, cx as Number, cy as Number, cat as Number) as Void {
        if (cat == WX_SUN) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx, cy, 4);
            dc.setPenWidth(1);
            for (var i = 0; i < 8; i += 1) {
                var a = i * Math.PI / 4.0;
                var x1 = cx + (6 * Math.cos(a)).toNumber();
                var y1 = cy + (6 * Math.sin(a)).toNumber();
                var x2 = cx + (8 * Math.cos(a)).toNumber();
                var y2 = cy + (8 * Math.sin(a)).toNumber();
                dc.drawLine(x1, y1, x2, y2);
            }
            return;
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx - 4, cy, 4);
        dc.fillCircle(cx + 2, cy - 2, 5);
        dc.fillCircle(cx + 5, cy + 1, 4);
        dc.fillRectangle(cx - 4, cy + 1, 11, 4);
        if (cat == WX_RAIN) {
            dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(cx - 3, cy + 6, 1, 3);
            dc.fillRectangle(cx + 1, cy + 6, 1, 3);
            dc.fillRectangle(cx + 5, cy + 6, 1, 3);
        } else if (cat == WX_SNOW) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx - 3, cy + 7, 1);
            dc.fillCircle(cx + 1, cy + 7, 1);
            dc.fillCircle(cx + 5, cy + 7, 1);
        }
    }

    // A small sun-on-horizon glyph with an up (sunrise) or down (sunset) arrow.
    private function drawSunIcon(dc as Dc, cx as Number, cy as Number, isRise as Boolean) as Void {
        dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, 3);
        dc.setPenWidth(1);
        dc.drawLine(cx - 7, cy + 4, cx + 7, cy + 4);
        if (isRise) {
            dc.fillPolygon([[cx, cy - 8], [cx - 3, cy - 4], [cx + 3, cy - 4]] as Array<Graphics.Point2D>);
        } else {
            dc.fillPolygon([[cx, cy + 1], [cx - 3, cy - 3], [cx + 3, cy - 3]] as Array<Graphics.Point2D>);
        }
    }

    // Removed from the screen.
    function onHide() as Void {
    }

    // The user just looked at the watch — full-power updates resume.
    function onExitSleep() as Void {
        mLowPower = false;
        WatchUi.requestUpdate();
    }

    // The watch went to low-power (always-on) mode. We switch to the reduced,
    // dimmed face (drawn in onUpdate via mLowPower) for AMOLED burn-in safety.
    function onEnterSleep() as Void {
        mLowPower = true;
        WatchUi.requestUpdate();
    }

}
