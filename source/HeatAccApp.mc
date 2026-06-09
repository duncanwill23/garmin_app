using Toybox.Application;
using Toybox.WatchUi;

class HeatAccApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        // Safety gate first: no session until the contraindication screen is done.
        if (!SafetyGate.screeningComplete()) {
            var sv = new ScreeningView();
            return [sv, new ScreeningDelegate(sv)];
        }
        var view = new HeatAccView();
        return [view, new HeatAccDelegate(view)];
    }
}
