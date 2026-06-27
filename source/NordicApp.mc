import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// The application object. For a watch face this is mostly a thin shell whose
// one important job is to hand back the initial view (the face itself).
class NordicApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    // Called once when the app starts up.
    function onStart(state as Dictionary?) as Void {
    }

    // Called once when the app is exiting.
    function onStop(state as Dictionary?) as Void {
    }

    // The first (and only) view shown: our watch face.
    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [ new NordicView() ];
    }

}

// Convenience accessor used elsewhere in larger apps.
function getApp() as NordicApp {
    return Application.getApp() as NordicApp;
}
