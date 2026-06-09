using Toybox.WatchUi;
using Toybox.Graphics;

// ---------------------------------------------------------------------------
// Screening: one-time contraindication gate shown before any session.
// STUB: this currently confirms with safe defaults (not novice, no beta-blocker).
// TODO: build the real multi-question flow:
//   - cardiac conditions / recent MI / unstable angina / heart failure
//   - pregnancy (esp. first trimester)
//   - acute illness / fever
//   - alcohol
//   - thermoregulation-impairing meds (beta-blockers, diuretics, psychiatric)
//   - novice vs trained (sets the session duration cap)
// Capture beta-blocker = true so the UI flags the HR proxy as invalid.
// ---------------------------------------------------------------------------
class ScreeningView extends WatchUi.View {
    function initialize() { View.initialize(); }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        dc.drawText(cx, h * 0.12, Graphics.FONT_SMALL,
            WatchUi.loadResource(Rez.Strings.ScreenTitle), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, h * 0.28, Graphics.FONT_XTINY,
            WatchUi.loadResource(Rez.Strings.ScreenBody),
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, h * 0.80, Graphics.FONT_TINY,
            WatchUi.loadResource(Rez.Strings.ScreenConfirm), Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class ScreeningDelegate extends WatchUi.BehaviorDelegate {
    private var _view;
    function initialize(view) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSelect() {
        // STUB defaults. Replace with answers gathered from the real flow.
        var isNovice = false;
        var onBetaBlockers = false;
        SafetyGate.markScreeningComplete(isNovice, onBetaBlockers);

        var v = new HeatAccView();
        WatchUi.switchToView(v, new HeatAccDelegate(v), WatchUi.SLIDE_IMMEDIATE);
        return true;
    }
}
