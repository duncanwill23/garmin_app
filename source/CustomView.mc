using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Application;
using Toybox.Application.Storage;

// ---------------------------------------------------------------------------
// CustomListMenu: shows the 3 phone-settings slots + "Build new".
//
// Slot configuration is set via Garmin Connect Mobile (settings.xml /
// properties.xml). Selecting a slot previews it in SuggestionView;
// "Build new" opens the on-watch CustomView builder.
// ---------------------------------------------------------------------------
class CustomListMenu extends WatchUi.Menu2 {

    function initialize() {
        Menu2.initialize({ :title => "Custom" });
        _addSlotItem("Custom A", "slot1", 0);
        _addSlotItem("Custom B", "slot2", 1);
        _addSlotItem("Custom C", "slot3", 2);
        addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.MenuCustomBuild), null, :build, null));
    }

    private function _addSlotItem(label, prefix, idx) {
        var rounds  = Application.Properties.getValue(prefix + "Rounds");
        var heatMin = Application.Properties.getValue(prefix + "HeatMin");
        var mod     = Application.Properties.getValue(prefix + "Modality");
        var sub;
        if (rounds != null && heatMin != null) {
            var mStr = (mod != null && mod.toNumber() == Config.MODALITY_STEAM)
                ? "Steam" : "Dry";
            sub = rounds.toString() + "x" + heatMin.toString() + "min · " + mStr;
        } else {
            sub = "not configured";
        }
        addItem(new WatchUi.MenuItem(label, sub, idx, null));
    }
}

class CustomListDelegate extends WatchUi.Menu2InputDelegate {

    private var _mainView;

    function initialize(mainView) {
        Menu2InputDelegate.initialize();
        _mainView = mainView;
    }

    function onTap(evt)   { return true; }
    function onHold(evt)  { return true; }
    function onSwipe(evt) { return true; }

    function onSelect(item) {
        var id = item.getId();
        if (id == :build) {
            WatchUi.switchToView(new CustomView(_mainView),
                new CustomDelegate(_mainView), WatchUi.SLIDE_LEFT);
        } else {
            // id is 0, 1, or 2 — map to slot prefix
            var prefix;
            if      (id == 0) { prefix = "slot1"; }
            else if (id == 1) { prefix = "slot2"; }
            else              { prefix = "slot3"; }
            var workout  = _buildSlotWorkout(prefix);
            if (workout != null) {
                WatchUi.switchToView(new SuggestionView(workout),
                    new SuggestionDelegate(workout, _mainView, null, null, null, true), WatchUi.SLIDE_LEFT);
            }
        }
    }

    function onBack() {
        WatchUi.switchToView(new IdleMenu(_mainView), new IdleMenuDelegate(_mainView),
            WatchUi.SLIDE_RIGHT);
    }

    private function _buildSlotWorkout(prefix) {
        var rounds  = Application.Properties.getValue(prefix + "Rounds");
        var heatMin = Application.Properties.getValue(prefix + "HeatMin");
        var restMin = Application.Properties.getValue(prefix + "RestMin");
        var mod     = Application.Properties.getValue(prefix + "Modality");
        if (rounds == null || heatMin == null || restMin == null) { return null; }
        var n  = rounds.toNumber();
        var hm = heatMin.toNumber();
        var rm = restMin.toNumber();
        var ml = (mod != null && mod.toNumber() == Config.MODALITY_STEAM)
            ? Config.MODALITY_STEAM : Config.MODALITY_DRY;
        if (n < 1 || hm < 1 || rm < 1) { return null; }
        var steps = WorkoutSuggester.makeSets(n, hm * 60, rm * 60, ml);
        var dose  = WorkoutSuggester.estimateDose(steps, ml);
        var proj  = WorkoutSuggester.simulateGain(dose);
        var rat   = n + " x " + hm + " min · " + rm + " min rest";
        return new Workout("Custom", ml, steps,
            Config.WORKOUT_CUSTOM, Config.COPY_CALIBRATION, rat, proj);
    }
}

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

        if (_step == CUSTOM_STEP_CONFIRM) {
            _drawConfirmRing(dc, h, cx);
        } else {
            _drawStepSpinner(dc, h, cx);
        }

        // Step progress dots (all steps)
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

    private function _drawConfirmRing(dc, h, cx) {
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.02).toNumber(), Graphics.FONT_XTINY,
            "Custom", Graphics.TEXT_JUSTIFY_CENTER);
        var preview = _buildPreviewWorkout();
        if (preview != null) {
            WorkoutRing.drawPreview(dc, preview);
        }
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.85).toNumber(), Graphics.FONT_XTINY,
            WatchUi.loadResource(Rez.Strings.UseThisWorkout),
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function _drawStepSpinner(dc, h, cx) {
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
        } else {
            label = "Rest (min)";
            value = _restMin.toString();
            hint  = "1-10";
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
    }

    private function _buildPreviewWorkout() {
        var modality = _mainView.modality();
        var steps = WorkoutSuggester.makeSets(
            _rounds, _heatMin * 60, _restMin * 60, modality);
        if (steps == null || steps.size() == 0) { return null; }
        var dose = WorkoutSuggester.estimateDose(steps, modality);
        var proj = WorkoutSuggester.simulateGain(dose);
        var rat  = _rounds + " x " + _heatMin + " min";
        return new Workout("Custom", modality, steps,
            Config.WORKOUT_CUSTOM, Config.COPY_CALIBRATION, rat, proj);
    }
}

class CustomDelegate extends WatchUi.BehaviorDelegate {
    private var _mainView;
    function initialize(mainView) {
        BehaviorDelegate.initialize();
        _mainView = mainView;
    }
    function onTap(evt)   { return true; }
    function onHold(evt)  { return true; }
    function onSwipe(evt) { return true; }
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
        WatchUi.switchToView(new CustomListMenu(), new CustomListDelegate(_mainView),
            WatchUi.SLIDE_RIGHT);
        return true;
    }
}
