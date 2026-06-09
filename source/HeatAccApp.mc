using Toybox.Application;
using Toybox.WatchUi;

class HeatAccApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        var view = new HeatAccView();
        return [view, new HeatAccDelegate(view)];
    }
}
