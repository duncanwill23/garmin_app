using Toybox.WatchUi;
using Toybox.Graphics;

// ---------------------------------------------------------------------------
// AcclimationView: shows the custom acclimation estimate (0-100 %).
// Reached by pressing UP on the IDLE screen.
//
// Displays:
//   - Large current % (decayed to now, read-only)
//   - "Acclimation - est." label
//   - Weekly delta (+N% this week)
//   - Sparkline of the last 30 history points
//   - Self-correction warning if acclimation is high but no HR drop detected
//
// Press BACK to return.
// ---------------------------------------------------------------------------
class AcclimationView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc) {
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var now    = TrendStore.nowEpoch();
        var accl   = TrendStore.currentAcclimation(now);
        var pctStr = accl.format("%.0f") + "%";

        // Title
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.04, Graphics.FONT_XTINY,
            "Acclimation - est.", Graphics.TEXT_JUSTIFY_CENTER);

        // Large % value
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.14, Graphics.FONT_NUMBER_MEDIUM,
            pctStr, Graphics.TEXT_JUSTIFY_CENTER);

        // Weekly delta
        var deltaStr = weeklyDeltaStr(now, accl);
        if (deltaStr != null) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.50, Graphics.FONT_XTINY,
                deltaStr, Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Sparkline
        drawSparkline(dc, w, h);

        // Self-correction warning (takes priority over page indicator)
        var warn = selfCorrectionWarning(accl);
        if (warn != null) {
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.82, Graphics.FONT_XTINY,
                warn, Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.90, Graphics.FONT_XTINY,
                "2 / 5", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // Return "+N% this week" delta string, or null if insufficient history.
    private function weeklyDeltaStr(nowEpoch, currentAccl) {
        var histT = TrendStore.getHistoryT();
        var histV = TrendStore.getHistoryV();
        if (histT == null || histV == null) { return null; }
        if (!(histT has :size)) { return null; }
        var sz = histT.size();
        if (sz < 2) { return null; }

        var weekAgoEpoch = nowEpoch - 7 * 86400;
        var baseVal = null;
        for (var i = sz - 1; i >= 0; i--) {
            if (histT[i] <= weekAgoEpoch) {
                baseVal = histV[i];
                break;
            }
        }
        if (baseVal == null) { return null; }

        var delta = currentAccl - baseVal.toFloat();
        var sign  = (delta >= 0.0) ? "+" : "";
        return sign + delta.format("%.0f") + "% this week";
    }

    // Draw a sparkline in the lower-middle band of the screen.
    private function drawSparkline(dc, w, h) {
        var histV = TrendStore.getHistoryV();
        if (histV == null || !(histV has :size)) { return; }
        var n = histV.size();
        if (n < 2) { return; }

        // Use up to the last 30 points.
        var start = (n > 30) ? n - 30 : 0;
        var count = n - start;
        if (count < 2) { return; }

        // Sparkline box.
        var boxX = (w * 0.08).toNumber();
        var boxW = (w * 0.84).toNumber();
        var boxY = (h * 0.56).toNumber();
        var boxH = (h * 0.22).toNumber();

        var prevX = -1;
        var prevY = -1;
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);

        for (var i = 0; i < count; i++) {
            var val = histV[start + i].toFloat();
            var px  = boxX + (boxW * i / (count - 1)).toNumber();
            var py  = boxY + boxH - (boxH * val / 100.0).toNumber();

            if (prevX >= 0) {
                dc.drawLine(prevX, prevY, px, py);
            }
            prevX = px;
            prevY = py;
        }

        // Mark the latest point with a filled circle.
        if (prevX >= 0) {
            var r = (w * 0.015).toNumber();
            if (r < 2) { r = 2; }
            dc.fillCircle(prevX, prevY, r);
        }
    }

    // Warn if model shows high acclimation (>60%) but measured HR hasn't dropped
    // after >=14 days in the program.
    private function selfCorrectionWarning(accl) {
        if (accl < 60.0) { return null; }
        if (TrendStore.daysIntoProgram() < Config.ADAPT_CHECK_DAY_LATE) { return null; }
        var delta = TrendStore.adaptationDeltaBpm(TrendStore.lastRefHr());
        if (delta == null) { return null; }
        // delta = currentRefHr - day1RefHr; negative means HR fell (good).
        if (delta < 0) { return null; }
        return "No HR drop - up the dose";
    }
}

// AcclimationDelegate is used by PostSessionDelegate when navigating to page 1
// (AcclimationView). No standalone usage currently.
class AcclimationDelegate extends WatchUi.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }
    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
