using Toybox.WatchUi;
using Toybox.Graphics;

class RestDayView extends WatchUi.View {
    private var _reason;
    function initialize(reason) { View.initialize(); _reason = reason; }
    function onUpdate(dc) {
        var w = dc.getWidth(); var h = dc.getHeight(); var cx = w / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK); dc.clear();
        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.28).toNumber(), Graphics.FONT_MEDIUM,
            "Rest today", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.48).toNumber(), Graphics.FONT_XTINY,
            "Recovery beats heat on a", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, (h * 0.56).toNumber(), Graphics.FONT_XTINY,
            "depleted day.", Graphics.TEXT_JUSTIFY_CENTER);
        if (_reason != null) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.70).toNumber(), Graphics.FONT_XTINY,
                _reason, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}

class RestDayDelegate extends WatchUi.BehaviorDelegate {
    private var _mainView;
    function initialize(mainView) { BehaviorDelegate.initialize(); _mainView = mainView; }
    function onBack()   { _goBack(); return true; }
    function onSelect() { _goBack(); return true; }
    private function _goBack() {
        WatchUi.switchToView(new IdleMenu(_mainView), new IdleMenuDelegate(_mainView),
            WatchUi.SLIDE_RIGHT);
    }
}
