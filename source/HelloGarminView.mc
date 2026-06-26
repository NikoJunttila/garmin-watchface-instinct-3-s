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

    // Draw the face. In high-power mode we draw the full layout; in low-power
    // (always-on) mode we draw a reduced, dimmed version to limit lit pixels and
    // avoid per-second updates (AMOLED burn-in protection).
    function onUpdate(dc as Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;

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
            drawLowPower(dc, centerX, width, height, clockTime);
            return;
        }

        // ----- Weather + next sun event, top-center on one row. -----
        drawWeatherSunRow(dc, centerX, (height * 0.16).toNumber());

        // ----- Time — large, white, slightly above the vertical center. -----
        var timeString = Lang.format("$1$:$2$", [clockTime.hour, clockTime.min.format("%02d")]);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            (height * 0.38).toNumber(),
            Graphics.FONT_NUMBER_MEDIUM,
            timeString,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );

        // ----- Day name + date, e.g. "FRI 26.06.26". -----
        drawDayDate(dc, centerX, (height * 0.55).toNumber());

        // ----- Body Battery. -----
        drawBodyBatteryRow(dc, centerX, (height * 0.70).toNumber());

        // ----- Heart rate · steps · battery. -----
        drawMetricsRow(dc, centerX, (height * 0.84).toNumber());
    }

    // Reduced always-on face: time + day/date + two slow, dimmed stats. No live
    // heart rate, no filled icons, dark gray accents — keeps lit pixels low.
    private function drawLowPower(dc as Dc, centerX as Number, width as Number, height as Number, clockTime as System.ClockTime) as Void {
        var timeString = Lang.format("$1$:$2$", [clockTime.hour, clockTime.min.format("%02d")]);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            (height * 0.42).toNumber(),
            Graphics.FONT_NUMBER_MEDIUM,
            timeString,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );

        // Day + date, dimmed.
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var dateString = DAY_NAMES[info.day_of_week - 1] + " " + Lang.format("$1$.$2$.$3$", [
            info.day.format("%02d"), info.month.format("%02d"), (info.year % 100).format("%02d")
        ]);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, (height * 0.62).toNumber(), Graphics.FONT_SMALL, dateString,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Two slow stats: Body Battery + steps, dimmed, no icons.
        var bbVal = mBodyBattery;
        var bb = (bbVal == null) ? "--" : bbVal.format("%d");
        var steps = stepsValue();
        var low = "BB " + bb + "   " + steps.format("%d");
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, (height * 0.76).toNumber(), Graphics.FONT_TINY, low,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Day name (green accent) + date (dim gray), centered as one row at rowY.
    private function drawDayDate(dc as Dc, centerX as Number, rowY as Number) as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var dayString = DAY_NAMES[info.day_of_week - 1];
        var dateString = Lang.format("$1$.$2$.$3$", [
            info.day.format("%02d"),
            info.month.format("%02d"),
            (info.year % 100).format("%02d")
        ]);

        var rowFont = Graphics.FONT_SMALL;
        var dayWidth = dc.getTextWidthInPixels(dayString, rowFont);
        var sepWidth = dc.getTextWidthInPixels(" ", rowFont);
        var dateWidth = dc.getTextWidthInPixels(dateString, rowFont);
        var startX = centerX - (dayWidth + sepWidth + dateWidth) / 2;

        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX, rowY, rowFont, dayString, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX + dayWidth + sepWidth, rowY, rowFont, dateString, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Weather (condition icon + temperature) and the next sun event (sunrise or
    // sunset icon + time), centered together as one row at rowY. Each part falls
    // back gracefully: temperature shows a dim "--°" before weather has synced,
    // and the sun event is simply omitted when there is no location to compute it.
    private function drawWeatherSunRow(dc as Dc, centerX as Number, rowY as Number) as Void {
        var font = Graphics.FONT_TINY;
        var sunFont = Graphics.FONT_XTINY;
        var cond = mWeather;

        // --- Weather part ---
        var temp = (cond == null) ? null : cond.temperature;
        var hasWx = (temp != null);
        var wxIconW = 18;
        var wxGap = 6;
        var tempText = hasWx ? (formatTemperature(temp) + "°") : "--°";
        var wxW = dc.getTextWidthInPixels(tempText, font) + (hasWx ? wxIconW + wxGap : 0);

        // --- Sun part (next upcoming event) ---
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
                sunMoment = sunrise; isRise = true; // both past today — show today's sunrise as a stand-in
            }
        }
        var sunIconW = 14;
        var sunGap = 5;
        var sunText = null;
        var sunW = 0;
        if (sunMoment != null) {
            var t = Gregorian.info(sunMoment, Time.FORMAT_SHORT);
            sunText = Lang.format("$1$:$2$", [t.hour, t.min.format("%02d")]);
            sunW = sunIconW + sunGap + dc.getTextWidthInPixels(sunText, sunFont);
        }

        // --- Center the whole group, then lay parts out left to right. ---
        var sepGap = 20;
        var total = wxW + ((sunText != null) ? sepGap + sunW : 0);
        var x = centerX - total / 2;

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
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + sunIconW + sunGap, rowY, sunFont, sunText, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // Body Battery, centered as one row at rowY: a dim "BB" tag + a fuel-gauge
    // colored value. Shows "--" before any sample is available.
    private function drawBodyBatteryRow(dc as Dc, centerX as Number, rowY as Number) as Void {
        var font = Graphics.FONT_TINY;
        var tagFont = Graphics.FONT_XTINY;
        var tagGap = 3;

        var bbVal = mBodyBattery;
        var bbText = (bbVal == null) ? "--" : bbVal.format("%d");
        var bbColor = (bbVal == null) ? Graphics.COLOR_LT_GRAY : levelColor(bbVal);

        var x = centerX - cellWidth(dc, "BB", bbText, tagFont, font, tagGap) / 2;
        drawTaggedCell(dc, x, rowY, "BB", bbText, tagFont, font, tagGap, bbColor);
    }

    // Draws the heart-rate, steps and battery metrics, centered as one row at
    // rowY. Each metric is a small icon (drawn battery / heart) or a label-less
    // color-coded value: heart rate red, steps blue, battery colored by charge.
    private function drawMetricsRow(dc as Dc, centerX as Number, rowY as Number) as Void {
        var font = Graphics.FONT_TINY;
        var iconGap = 4;   // space between an icon and its value
        var cellGap = 18;  // space between metrics

        // Heart rate — latest reading, or "--" when none is available.
        var hr = getHeartRate();
        var hrColor = (hr == null) ? Graphics.COLOR_LT_GRAY : Graphics.COLOR_RED;
        var hrText = (hr == null) ? "--" : hr.format("%d");
        var heartW = 14;
        var hrCellW = heartW + iconGap + dc.getTextWidthInPixels(hrText, font);

        // Steps since midnight.
        var steps = stepsValue();
        var stepsText = steps.format("%d");
        var stepsColor = 0x55AAFF;
        var stepsCellW = dc.getTextWidthInPixels(stepsText, font);

        // Battery percentage, colored by charge level.
        var battery = System.getSystemStats().battery;
        var batText = (battery + 0.5).toNumber().format("%d") + "%";
        var batColor = (battery <= 15) ? Graphics.COLOR_RED
                     : (battery <= 35) ? Graphics.COLOR_YELLOW
                     : Graphics.COLOR_GREEN;
        var batBodyW = 20;
        var batIconW = batBodyW + 3; // body + terminal nub
        var batCellW = batIconW + iconGap + dc.getTextWidthInPixels(batText, font);

        // Center the three cells as one group, then lay them out left to right.
        var x = centerX - (hrCellW + cellGap + stepsCellW + cellGap + batCellW) / 2;

        drawHeart(dc, x + heartW / 2, rowY, hrColor);
        dc.setColor(hrColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + heartW + iconGap, rowY, font, hrText, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        x += hrCellW + cellGap;

        dc.setColor(stepsColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, rowY, font, stepsText, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        x += stepsCellW + cellGap;

        drawBatteryIcon(dc, x, rowY, batBodyW, 11, battery, batColor);
        dc.setColor(batColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + batIconW + iconGap, rowY, font, batText, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
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

    // Weather temperatures come from the API in Celsius; convert to the device's
    // configured unit before display.
    private function formatTemperature(tempC as Number) as String {
        if (System.getDeviceSettings().temperatureUnits == System.UNIT_STATUTE) {
            return ((tempC * 9.0 / 5.0) + 32.0 + 0.5).toNumber().format("%d");
        }
        return tempC.format("%d");
    }

    // Fuel-gauge coloring (Body Battery): high = green, low = red.
    private function levelColor(level as Number) as Number {
        return (level <= 25) ? Graphics.COLOR_RED
             : (level <= 50) ? Graphics.COLOR_YELLOW
             : Graphics.COLOR_GREEN;
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

    // ---- small primitives ----------------------------------------------------

    // Width of a "tag + value" cell (used to center a row before drawing it).
    private function cellWidth(dc as Dc, tag as String, value as String, tagFont as Graphics.FontDefinition, valFont as Graphics.FontDefinition, gap as Number) as Number {
        return dc.getTextWidthInPixels(tag, tagFont) + gap + dc.getTextWidthInPixels(value, valFont);
    }

    // Draws a dim tag + colored value at x; returns the x just past the value.
    private function drawTaggedCell(dc as Dc, x as Number, rowY as Number, tag as String, value as String, tagFont as Graphics.FontDefinition, valFont as Graphics.FontDefinition, gap as Number, valColor as Number) as Number {
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, rowY, tagFont, tag, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        var tagW = dc.getTextWidthInPixels(tag, tagFont);
        dc.setColor(valColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + tagW + gap, rowY, valFont, value, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        return x + tagW + gap + dc.getTextWidthInPixels(value, valFont);
    }

    // A small filled heart centered at (cx, cy): two top lobes + a point.
    private function drawHeart(dc as Dc, cx as Number, cy as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx - 3, cy - 1, 4);
        dc.fillCircle(cx + 3, cy - 1, 4);
        dc.fillPolygon([
            [cx - 6, cy],
            [cx + 6, cy],
            [cx, cy + 7]
        ] as Array<Graphics.Point2D>);
    }

    // A small battery glyph: outline body + terminal nub + a charge-level fill.
    // x is the body's left edge; cy is its vertical center.
    private function drawBatteryIcon(dc as Dc, x as Number, cy as Number, bodyW as Number, bodyH as Number, pct as Float, color as Number) as Void {
        var top = cy - bodyH / 2;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawRectangle(x, top, bodyW, bodyH);
        // Terminal nub on the right.
        var nubH = bodyH / 2;
        dc.fillRectangle(x + bodyW, cy - nubH / 2, 2, nubH);
        // Charge-level fill.
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
            dc.fillCircle(cx, cy, 5);
            dc.setPenWidth(1);
            for (var i = 0; i < 8; i += 1) {
                var a = i * Math.PI / 4.0;
                var x1 = cx + (7 * Math.cos(a)).toNumber();
                var y1 = cy + (7 * Math.sin(a)).toNumber();
                var x2 = cx + (9 * Math.cos(a)).toNumber();
                var y2 = cy + (9 * Math.sin(a)).toNumber();
                dc.drawLine(x1, y1, x2, y2);
            }
            return;
        }
        // Cloud body, shared by cloud/rain/snow.
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx - 4, cy, 4);
        dc.fillCircle(cx + 2, cy - 2, 5);
        dc.fillCircle(cx + 5, cy + 1, 4);
        dc.fillRectangle(cx - 4, cy + 1, 11, 4);
        if (cat == WX_RAIN) {
            dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
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
        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, 3);
        dc.setPenWidth(1);
        dc.drawLine(cx - 7, cy + 4, cx + 7, cy + 4); // horizon
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
