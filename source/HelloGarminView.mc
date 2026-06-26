import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

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

    // Draw the face: build an "HH:MM" string and push it into the layout's label.
    function onUpdate(dc as Dc) as Void {
        var clockTime = System.getClockTime();
        var timeString = Lang.format("$1$:$2$", [clockTime.hour, clockTime.min.format("%02d")]);

        var view = View.findDrawableById("TimeLabel") as Text;
        view.setText(timeString);

        // Let the parent draw the layout (background + the label we just set).
        View.onUpdate(dc);
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
