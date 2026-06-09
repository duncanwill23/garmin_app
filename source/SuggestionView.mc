using Toybox.WatchUi;
using Toybox.Graphics;

// ---------------------------------------------------------------------------
// SuggestionView: 3-screen pager presenting a suggested Workout.
//
// Page 1 — Bar chart: alternating HEAT (orange) / REST (blue) blocks.
// Page 2 — Explanation: copy text from WorkoutSuggester.buildExplanation().
// Page 3 — Benefit: projected acclimation gain + "START to use" CTA.
//
// UP/DOWN page through; SELECT on page 3 (or anywhere) arms the workout.
// ---------------------------------------------------------------------------
class SuggestionView extends WatchUi.View {

    private var _workout;
    private var _page;      // 0, 1, or 2
    private var _pageCount = 3;

    function initialize(workout) {
        View.initialize();
        _workout = workout;
        _page    = 0;
    }

    function getPage()  { return _page; }
    function nextPage() { _page = (_page + 1) % _pageCount; WatchUi.requestUpdate(); }
    function prevPage() { _page = (_page + _pageCount - 1) % _pageCount; WatchUi.requestUpdate(); }

    function onUpdate(dc) {
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        if (_page == 0) {
            drawBarChart(dc, w, h, cx);
        } else if (_page == 1) {
            drawExplanation(dc, h, cx);
        } else {
            drawBenefit(dc, h, cx);
        }

        // Page indicator (e.g. "1/3")
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.94).toNumber(), Graphics.FONT_XTINY,
            (_page + 1) + "/" + _pageCount, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // --- Page 1: bar chart of workout steps ---
    private function drawBarChart(dc, w, h, cx) {
        var steps = _workout.steps;
        if (!(steps has :size) || steps.size() == 0) { return; }

        // Header
        var isDry = (_workout.modality == Config.MODALITY_DRY);
        var modStr = isDry ? "Dry Sauna" : "Steam · est.";
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.03).toNumber(), Graphics.FONT_XTINY,
            _workout.name + "  " + modStr, Graphics.TEXT_JUSTIFY_CENTER);

        // Compute total duration for proportional widths
        var totalSec = 0;
        for (var i = 0; i < steps.size(); i++) {
            var s = steps[i];
            if (s instanceof WorkoutStep && s.durationSec != null) {
                totalSec += s.durationSec;
            }
        }
        if (totalSec == 0) { return; }

        var barAreaW = (w * 0.80).toNumber();
        var barX0    = ((w - barAreaW) / 2).toNumber();
        var barY     = (h * 0.20).toNumber();
        var barH     = (h * 0.30).toNumber();
        var labelY   = (h * 0.52).toNumber();

        var x = barX0;
        for (var i = 0; i < steps.size(); i++) {
            var s = steps[i];
            if (!(s instanceof WorkoutStep) || s.durationSec == null) { continue; }
            var bw = (s.durationSec.toFloat() / totalSec.toFloat() * barAreaW).toNumber();
            if (s.type == Config.STEP_HEAT) {
                dc.setColor(0xF2A623, Graphics.COLOR_TRANSPARENT); // amber
            } else {
                dc.setColor(0x5AA9E6, Graphics.COLOR_TRANSPARENT); // blue
            }
            dc.fillRectangle(x, barY, bw - 1, barH);

            // Time label centered under each block
            var minLabel = (s.durationSec / 60).toString() + "m";
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + bw / 2, labelY, Graphics.FONT_XTINY,
                minLabel, Graphics.TEXT_JUSTIFY_CENTER);
            x += bw;
        }

        // Summary line
        var rounds  = _workout.heatRounds();
        var heatMin = _workout.totalHeatSec() / 60;
        var totalMin = totalSec / 60;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.62).toNumber(), Graphics.FONT_XTINY,
            rounds + " x " + (heatMin / rounds) + " min · " + totalMin + " min total",
            Graphics.TEXT_JUSTIFY_CENTER);

        // HR range
        var loHr = (Config.TARGET_HR_LOW_PCT  * 100.0).toNumber();
        var hiHr = (Config.TARGET_HR_HIGH_PCT * 100.0).toNumber();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.72).toNumber(), Graphics.FONT_XTINY,
            loHr + "-" + hiHr + "% HRmax target",
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    // --- Page 2: explanation text ---
    private function drawExplanation(dc, h, cx) {
        var text = WorkoutSuggester.buildExplanation(_workout);
        // Split on "\n" and draw line by line
        var lines = splitLines(text);
        var startY = (h * 0.08).toNumber();
        var lineH  = (h * 0.13).toNumber();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < lines.size() && i < 6; i++) {
            dc.drawText(cx, startY + i * lineH, Graphics.FONT_XTINY,
                lines[i], Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // --- Page 3: expected benefit + CTA ---
    private function drawBenefit(dc, h, cx) {
        var gain = (_workout has :projectedGainPct) ? _workout.projectedGainPct : 0.0;
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.20).toNumber(), Graphics.FONT_MEDIUM,
            "+" + gain.format("%.0f") + "%",
            Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.40).toNumber(), Graphics.FONT_XTINY,
            "projected acclimation gain",
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, (h * 0.50).toNumber(), Graphics.FONT_XTINY,
            "(estimate — based on full dose)",
            Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.70).toNumber(), Graphics.FONT_XTINY,
            WatchUi.loadResource(Rez.Strings.UseThisWorkout),
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Minimal "\n" line splitter — returns Array of Strings.
    private function splitLines(text) {
        var result = [];
        var start  = 0;
        for (var i = 0; i < text.length(); i++) {
            if (text.substring(i, i + 1).equals("\n")) {
                result.add(text.substring(start, i));
                start = i + 1;
            }
        }
        if (start < text.length()) {
            result.add(text.substring(start, text.length()));
        }
        return result;
    }
}

class SuggestionDelegate extends WatchUi.BehaviorDelegate {
    private var _workout;
    private var _mainView;

    function initialize(workout, mainView) {
        BehaviorDelegate.initialize();
        _workout  = workout;
        _mainView = mainView;
    }

    // DOWN = next page
    function onNextPage() {
        var view = WatchUi.getCurrentView()[0];
        if (view instanceof SuggestionView) { view.nextPage(); }
        return true;
    }

    // UP = previous page
    function onPreviousPage() {
        var view = WatchUi.getCurrentView()[0];
        if (view instanceof SuggestionView) { view.prevPage(); }
        return true;
    }

    // SELECT: arm the workout and return to idle
    function onSelect() {
        _mainView.armWorkout(_workout);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
