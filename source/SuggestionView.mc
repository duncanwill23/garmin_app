using Toybox.WatchUi;
using Toybox.Graphics;

// ---------------------------------------------------------------------------
// SuggestionView: 3-screen pager presenting a suggested Workout.
//
// Page 1 — Ring: segmented arc ring (red HEAT / blue REST) + center headline.
// Page 2 — Explanation: scrollable copy text.
// Page 3 — Benefit: projected acclimation gain + "START to use" CTA.
//
// Navigation:
//   DOWN / UP   — page through (or scroll explanation text when on page 2)
//   SELECT      — arm the workout and jump directly to idle (switchToView)
//   BACK        — pop this view; returns to whatever pushed it (menu / chooser)
// ---------------------------------------------------------------------------
class SuggestionView extends WatchUi.View {

    private var _workout;
    private var _page;          // 0, 1, or 2
    private var _pageCount = 3;

    // Explanation scroll state (page 1 only)
    private var _explainLines = null;  // lazily built Array<String>
    private var _scrollLine   = 0;
    const EXPLAIN_VISIBLE = 7;         // lines visible at once

    function initialize(workout) {
        View.initialize();
        _workout = workout;
        _page    = 0;
    }

    function getPage() { return _page; }

    function nextPage() {
        _page = (_page + 1) % _pageCount;
        _scrollLine   = 0;
        _explainLines = null;
        WatchUi.requestUpdate();
    }

    function prevPage() {
        _page = (_page + _pageCount - 1) % _pageCount;
        _scrollLine   = 0;
        _explainLines = null;
        WatchUi.requestUpdate();
    }

    // Explanation scroll helpers
    function canScrollDown() {
        var lines = _getExplainLines();
        return _scrollLine + EXPLAIN_VISIBLE < lines.size();
    }
    function canScrollUp() { return _scrollLine > 0; }

    function scrollDown() {
        if (canScrollDown()) { _scrollLine++; WatchUi.requestUpdate(); }
    }
    function scrollUp() {
        if (canScrollUp()) { _scrollLine--; WatchUi.requestUpdate(); }
    }

    private function _getExplainLines() {
        if (_explainLines == null) {
            var text = WorkoutSuggester.buildExplanation(_workout);
            // fr955: round screen, text starts at h*0.10 (y≈26px).
            // At that y the chord is ~156px; FONT_XTINY ≈7px/char → 22-char limit.
            _explainLines = _wrapText(text, 22);
        }
        return _explainLines;
    }

    // Word-wrap: honours hard \n breaks, then splits long lines on spaces.
    // Monkey C's % is integer-only so we use string length, not pixel width.
    private function _wrapText(text, maxChars) {
        var result = [];
        var hardLines = _splitLines(text);
        for (var li = 0; li < hardLines.size(); li++) {
            var line = hardLines[li];
            if (line.length() <= maxChars) {
                result.add(line);
                continue;
            }
            // Tokenise on spaces
            var words = [];
            var wStart = 0;
            for (var j = 0; j < line.length(); j++) {
                if (line.substring(j, j + 1).equals(" ")) {
                    if (j > wStart) { words.add(line.substring(wStart, j)); }
                    wStart = j + 1;
                }
            }
            if (wStart < line.length()) {
                words.add(line.substring(wStart, line.length()));
            }
            // Pack words into lines ≤ maxChars
            var cur = "";
            for (var k = 0; k < words.size(); k++) {
                var word = words[k];
                if (cur.length() == 0) {
                    cur = word;
                } else if ((cur + " " + word).length() <= maxChars) {
                    cur = cur + " " + word;
                } else {
                    result.add(cur);
                    cur = word;
                }
            }
            if (cur.length() > 0) { result.add(cur); }
        }
        return result;
    }

    // -----------------------------------------------------------------------
    function onUpdate(dc) {
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        if (_page == 0) {
            drawRingPreview(dc, h, cx);
        } else if (_page == 1) {
            drawExplanation(dc, h, cx);
        } else {
            drawBenefit(dc, h, cx);
        }

        // Page indicator ("1/3" etc.) — hidden when explanation overflows (arrows
        // shown instead), but always shown on pages 0 and 2.
        if (_page != 1 || (!canScrollDown() && !canScrollUp())) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.94).toNumber(), Graphics.FONT_XTINY,
                (_page + 1) + "/" + _pageCount, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // --- Page 1: segmented ring preview ---
    private function drawRingPreview(dc, h, cx) {
        // Name + modality above the ring
        // var isDry  = (_workout.modality == Config.MODALITY_DRY);
        // var modStr = isDry ? "Dry Sauna" : "Steam · est.";
        // dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        // dc.drawText(cx, (h * 0.02).toNumber(), Graphics.FONT_XTINY,
        //     _workout.name + "  " + modStr, Graphics.TEXT_JUSTIFY_CENTER);

        // Ring + center headline (N x H / min in heat / total)
        WorkoutRing.drawPreview(dc, _workout);

        // Race badge below the total-time line (inside ring, safe area)
        if (_workout.kind == Config.WORKOUT_RACE) {
            var cy = dc.getHeight() / 2;
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + (h * 0.27).toNumber(), Graphics.FONT_XTINY,
                "Race prep", Graphics.TEXT_JUSTIFY_CENTER);
        }

        // HR target hint near bottom (below ring outer edge)
        // var loHr = (Config.TARGET_HR_LOW_PCT  * 100.0).toNumber();
        // var hiHr = (Config.TARGET_HR_HIGH_PCT * 100.0).toNumber();
        // dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        // dc.drawText(cx, (h * 0.87).toNumber(), Graphics.FONT_XTINY,
        //     loHr + "-" + hiHr + "% HRmax target", Graphics.TEXT_JUSTIFY_CENTER);
    }

    // --- Page 2: scrollable explanation ---
    private function drawExplanation(dc, h, cx) {
        var lines  = _getExplainLines();
        var lineH  = (h * 0.10).toNumber();   // ~45 px on fr955 — comfortable for FONT_XTINY
        var startY = (h * 0.10).toNumber();

        // Scroll-up arrow
        if (canScrollUp()) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[cx, (h * 0.02).toNumber()],
                            [cx - 7, (h * 0.06).toNumber()],
                            [cx + 7, (h * 0.06).toNumber()]]);
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        for (var i = _scrollLine; i < lines.size() && i < _scrollLine + EXPLAIN_VISIBLE; i++) {
            dc.drawText(cx, startY + (i - _scrollLine) * lineH, Graphics.FONT_XTINY,
                lines[i], Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Scroll-down arrow (doubles as page-forward cue when at bottom)
        if (canScrollDown()) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[cx, (h * 0.96).toNumber()],
                            [cx - 7, (h * 0.92).toNumber()],
                            [cx + 7, (h * 0.92).toNumber()]]);
        } else {
            // At the bottom — show page indicator so user knows they can page forward
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.94).toNumber(), Graphics.FONT_XTINY,
                "2/" + _pageCount, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // --- Page 3: expected benefit + CTA ---
    private function drawBenefit(dc, h, cx) {
        var gain = (_workout has :projectedGainPct) ? _workout.projectedGainPct : 0.0;
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.20).toNumber(), Graphics.FONT_NUMBER_MEDIUM,
            "+" + gain.format("%.0f") + "%",
            Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.52).toNumber(), Graphics.FONT_XTINY,
            "projected acclimation gain", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, (h * 0.60).toNumber(), Graphics.FONT_XTINY,
            "(full dose, in target HR band)", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.76).toNumber(), Graphics.FONT_SMALL,
            WatchUi.loadResource(Rez.Strings.UseThisWorkout),
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Split text on "\n" → Array<String>.
    private function _splitLines(text) {
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

// ---------------------------------------------------------------------------
class SuggestionDelegate extends WatchUi.BehaviorDelegate {
    private var _workout;
    private var _mainView;
    // Origin context — tells onBack() which screen to rebuild.
    private var _progWorkout;   // non-null only when arrived via the suggestion chooser
    private var _raceWorkout;
    private var _daysToRace;
    private var _fromCustom;    // true when arrived from CustomListMenu

    function initialize(workout, mainView, progWorkout, raceWorkout, daysToRace, fromCustom) {
        BehaviorDelegate.initialize();
        _workout     = workout;
        _mainView    = mainView;
        _progWorkout = progWorkout;
        _raceWorkout = raceWorkout;
        _daysToRace  = daysToRace;
        _fromCustom  = fromCustom;
    }

    function onTap(evt)  { return true; }
    function onHold(evt) { return true; }
    // onSwipe intentionally omitted — allows finger-scroll on explanation page

    // DOWN: scroll explanation text if overflowing, otherwise advance page.
    function onNextPage() {
        var view = WatchUi.getCurrentView()[0];
        if (view instanceof SuggestionView) {
            if (view.getPage() == 1 && view.canScrollDown()) {
                view.scrollDown();
            } else {
                view.nextPage();
            }
        }
        return true;
    }

    // UP: scroll explanation text back if scrolled, otherwise retreat page.
    function onPreviousPage() {
        var view = WatchUi.getCurrentView()[0];
        if (view instanceof SuggestionView) {
            if (view.getPage() == 1 && view.canScrollUp()) {
                view.scrollUp();
            } else {
                view.prevPage();
            }
        }
        return true;
    }

    // START physical button: arm workout and return to idle.
    function onKey(keyEvent) {
        var key = keyEvent.getKey();
        if (key == WatchUi.KEY_ENTER || key == WatchUi.KEY_START) {
            _mainView.armWorkout(_workout);
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            return true;
        }
        return false;
    }

    // BACK: rebuild whichever screen preceded this one.
    function onBack() {
        if (_progWorkout != null && _raceWorkout != null) {
            // Arrived via suggestion chooser — rebuild it.
            var menu = new WatchUi.Menu2({ :title => "Suggestion" });
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource(Rez.Strings.SuggestionProgression), null, :prog, null));
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource(Rez.Strings.SuggestionRace) + " · " + _daysToRace + "d",
                null, :race, null));
            WatchUi.switchToView(menu,
                new SuggestionChooserDelegate(_mainView, _progWorkout, _raceWorkout, _daysToRace),
                WatchUi.SLIDE_RIGHT);
        } else if (_fromCustom) {
            // Arrived from custom slot list — rebuild it.
            WatchUi.switchToView(new CustomListMenu(),
                new CustomListDelegate(_mainView), WatchUi.SLIDE_RIGHT);
        } else {
            // Arrived directly from IdleMenu — rebuild it.
            WatchUi.switchToView(new IdleMenu(_mainView), new IdleMenuDelegate(_mainView),
                WatchUi.SLIDE_RIGHT);
        }
        return true;
    }
}
