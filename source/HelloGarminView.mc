import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Abbreviated day names, indexed by (day_of_week - 1). Gregorian.info() with
// FORMAT_SHORT returns day_of_week as 1=Sunday .. 7=Saturday. (We map it
// ourselves because FORMAT_MEDIUM/LONG only return abbreviations anyway, and a
// fixed table keeps the output deterministic and locale-independent.)
const DAY_NAMES = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"] as Array<String>;

// The watch face itself. The system calls onUpdate roughly once per minute
// (and more often while you're actively looking at the watch).
class HelloGarminView extends WatchUi.WatchFace {

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

    // Draw the face: a large white time, with a green day name + gray date
    // ("FRI 26.06.26") centered as one row beneath it, on a black background.
    // We draw directly with the Dc (instead of layout labels) so the day-name
    // and date can use different colors on the same line and stay centered as a
    // unit across the 45mm/50mm screen sizes.
    function onUpdate(dc as Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;

        // Background.
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        // Time — large, white, slightly above the vertical center.
        var clockTime = System.getClockTime();
        var timeString = Lang.format("$1$:$2$", [clockTime.hour, clockTime.min.format("%02d")]);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            (height * 0.38).toNumber(),
            Graphics.FONT_NUMBER_MEDIUM,
            timeString,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );

        // Day name + date, e.g. "FRI 26.06.26".
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var dayString = DAY_NAMES[info.day_of_week - 1];
        var dateString = Lang.format("$1$.$2$.$3$", [
            info.day.format("%02d"),
            info.month.format("%02d"),
            (info.year % 100).format("%02d")
        ]);

        // Measure the parts so the whole row is centered as one unit, then draw
        // the day name (green accent) and the date (dim gray) side by side.
        var rowFont = Graphics.FONT_SMALL;
        var rowY = (height * 0.60).toNumber();
        var dayWidth = dc.getTextWidthInPixels(dayString, rowFont);
        var sepWidth = dc.getTextWidthInPixels(" ", rowFont);
        var dateWidth = dc.getTextWidthInPixels(dateString, rowFont);
        var startX = centerX - (dayWidth + sepWidth + dateWidth) / 2;

        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX, rowY, rowFont, dayString, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX + dayWidth + sepWidth, rowY, rowFont, dateString, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // Heart rate / steps / battery, centered as one row near the bottom.
        drawMetricsRow(dc, centerX, (height * 0.82).toNumber());
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
        var steps = 0;
        var amInfo = ActivityMonitor.getInfo();
        if (amInfo != null && amInfo.steps != null) {
            steps = amInfo.steps;
        }
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

    // Removed from the screen.
    function onHide() as Void {
    }

    // The user just looked at the watch — full-power updates resume.
    function onExitSleep() as Void {
    }

    // The watch went to low-power (always-on) mode. Stop timers/animations here.
    // (A dedicated low-power layout for AMOLED burn-in protection would go here later.)
    function onEnterSleep() as Void {
    }

}
