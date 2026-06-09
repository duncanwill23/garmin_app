using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Application.Storage;

// ---------------------------------------------------------------------------
// CustomView: on-watch workout builder.
// A simple multi-step form: rounds → heat minutes → rest minutes → confirm.
// The built Workout is armed and the user returns to idle.
// ---------------------------------------------------------------------------

const CUSTOM_STEP_ROUNDS    = 0;
const CUSTOM_STEP_HEAT_MIN  = 1;
const CUSTOM_STEP_REST_MIN  = 2;
const CUSTOM_STEP_CONFIRM   = 3;

class CustomView extends WatchUi.View {

    private var _mainView;
    private var _step;
    private var _rounds;
    private var _heatMin;
    private var _restMin;

    function initialize(mainView) {
        View.initialize();
        _mainView = mainView;
        _step     = CUSTOM_STEP_ROUNDS;
        _rounds   = Config.PRESET_ROUNDS_DEFAULT;
        _heatMin  = Config.PRESET_HEAT_MIN_DEFAULT;
        _restMin  = Config.PRESET_REST_MIN_DEFAULT;
    }

    function increment() {
        if (_step == CUSTOM_STEP_ROUNDS)   { if (_rounds  < 5)  { _rounds++;  } }
        if (_step == CUSTOM_STEP_HEAT_MIN) { if (_heatMin < 20) { _heatMin++; } }
        if (_step == CUSTOM_STEP_REST_MIN) { if (_restMin < 10) { _restMin++; } }
        WatchUi.requestUpdate();
    }

    function decrement() {
        if (_step == CUSTOM_STEP_ROUNDS)   { if (_rounds  > 1) { _rounds--;  } }
        if (_step == CUSTOM_STEP_HEAT_MIN) { if (_heatMin > 5) { _heatMin--; } }
        if (_step == CUSTOM_STEP_REST_MIN) { if (_restMin > 1) { _restMin--; } }
        WatchUi.requestUpdate();
    }

    function confirm() {
        if (_step < CUSTOM_STEP_CONFIRM) {
            _step++;
            WatchUi.requestUpdate();
        } else {
            buildAndArm();
        }
    }

    private function buildAndArm() {
        var modality = _mainView.modality();
        var steps    = WorkoutSuggester.makeSets(
            _rounds, _heatMin * 60, _restMin * 60, modality);
        var dose     = WorkoutSuggester.estimateDose(steps, modality);
        var proj     = WorkoutSuggester.simulateGain(dose);
        var rat      = _rounds + " x " + _heatMin + " min · " + _restMin + " min rest";
        var workout  = new Workout("Custom", modality, steps,
            Config.WORKOUT_CUSTOM, Config.COPY_CALIBRATION, rat, proj);
        _mainView.armWorkout(workout);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function onUpdate(dc) {
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var label;
        var value;
        var hint;

        if (_step == CUSTOM_STEP_ROUNDS) {
            label = "Rounds";
            value = _rounds.toString();
            hint  = "1-5";
        } else if (_step == CUSTOM_STEP_HEAT_MIN) {
            label = "Heat (min)";
            value = _heatMin.toString();
            hint  = "5-20";
        } else if (_step == CUSTOM_STEP_REST_MIN) {
            label = "Rest (min)";
            value = _restMin.toString();
            hint  = "1-10";
        } else {
            label = "Custom";
            value = _rounds + "x" + _heatMin;
            hint  = _restMin + "m rest · START to arm";
        }

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.08).toNumber(), Graphics.FONT_XTINY,
            label, Graphics.TEXT_JUSTIFY_CENTER);

        // Up chevron
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        var upY = (h * 0.24).toNumber();
        dc.fillPolygon([[cx, upY - 8], [cx - 8, upY + 4], [cx + 8, upY + 4]]);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.35).toNumber(), Graphics.FONT_NUMBER_MEDIUM,
            value, Graphics.TEXT_JUSTIFY_CENTER);

        // Down chevron
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        var downY = (h * 0.70).toNumber();
        dc.fillPolygon([[cx, downY + 8], [cx - 8, downY - 4], [cx + 8, downY - 4]]);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.82).toNumber(), Graphics.FONT_XTINY,
            hint + "  ·  START = next",
            Graphics.TEXT_JUSTIFY_CENTER);

        // Step progress dots
        for (var i = 0; i <= CUSTOM_STEP_CONFIRM; i++) {
            var dotX = cx - 15 + i * 10;
            if (i == _step) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(dotX, (h * 0.92).toNumber(), 4);
            } else {
                dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(dotX, (h * 0.92).toNumber(), 3);
            }
        }
    }
}

class CustomDelegate extends WatchUi.BehaviorDelegate {
    function initialize(mainView) {
        BehaviorDelegate.initialize();
    }
    function onNextPage() {
        var v = WatchUi.getCurrentView()[0];
        if (v instanceof CustomView) { v.decrement(); }
        return true;
    }
    function onPreviousPage() {
        var v = WatchUi.getCurrentView()[0];
        if (v instanceof CustomView) { v.increment(); }
        return true;
    }
    function onSelect() {
        var v = WatchUi.getCurrentView()[0];
        if (v instanceof CustomView) { v.confirm(); }
        return true;
    }
    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
