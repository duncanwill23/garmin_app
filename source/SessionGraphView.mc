using Toybox.WatchUi;
using Toybox.Graphics;

// ---------------------------------------------------------------------------
// SessionGraphView: post-session time-series graph with axes and stats.
//
// hrMode = true  → page 3/4, Heart Rate (bpm)
// hrMode = false → page 4/4, Skin Temp (°C / °F)
// Both: red segments = heat rounds, blue = rest.
//
// Layout (fractions of screen h/w):
//   0.02        title
//   0.09        avg label (center)
//   0.15        graph top
//   0.15–0.81   graph area   (boxY to boxY+boxH)
//   0.84        x-axis labels
//   0.93        page indicator
//
// Left margin (w * 0.22) holds Y-axis labels (right-aligned).
// Right margin (w * 0.06) gives room for last x-label.
// ---------------------------------------------------------------------------
class SessionGraphView extends WatchUi.View {

    private var _data;
    private var _hrMode;

    function initialize(data, hrMode) {
        View.initialize();
        _data   = data;
        _hrMode = hrMode;
    }

    function onUpdate(dc) {
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var title   = _hrMode ? "Heart Rate" : "Skin Temp";
        var pageStr = _hrMode ? "3 / 4" : "4 / 4";

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.02, Graphics.FONT_XTINY,
            title, Graphics.TEXT_JUSTIFY_CENTER);

        var samples = _hrMode ? _data.sampleHR : _data.sampleTemp;
        var hasData = (samples != null) && (samples has :size) && (samples.size() >= 2);

        if (hasData) {
            drawGraph(dc, w, h, cx, samples);
        } else {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.50, Graphics.FONT_XTINY,
                "No data", Graphics.TEXT_JUSTIFY_CENTER);
        }

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.93, Graphics.FONT_XTINY,
            pageStr, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawGraph(dc, w, h, cx, samples) {
        var phases  = _data.samplePhase;
        var timesT  = _data.sampleT;
        var n       = samples.size();

        // --- First pass: range, average, count ---
        var dataMin =  999999.0;
        var dataMax = -999999.0;
        var sum     = 0.0;
        var count   = 0;
        for (var i = 0; i < n; i++) {
            var v = samples[i];
            if (v != null) {
                var vf = v.toFloat();
                if (vf < dataMin) { dataMin = vf; }
                if (vf > dataMax) { dataMax = vf; }
                sum   = sum + vf;
                count = count + 1;
            }
        }
        if (count == 0) { return; }
        var avg = sum / count;

        // Y range with 10 % padding
        var pad = (dataMax - dataMin) * 0.10;
        if (pad < 0.5) { pad = 0.5; }
        var yMin   = dataMin - pad;
        var yMax   = dataMax + pad;
        var yRange = yMax - yMin;

        // --- Avg label at top ---
        var avgLabel;
        if (_hrMode) {
            avgLabel = "Avg " + avg.format("%.0f") + " bpm";
        } else {
            var avgF = avg * 9.0 / 5.0 + 32.0;
            avgLabel = "Avg " + avg.format("%.1f") + "\u00B0C / " + avgF.format("%.0f") + "\u00B0F";
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.09, Graphics.FONT_XTINY,
            avgLabel, Graphics.TEXT_JUSTIFY_CENTER);

        // --- Graph box ---
        var boxX = (w * 0.22).toNumber();
        var boxW = (w * 0.72).toNumber();
        var boxY = (h * 0.18).toNumber();
        var boxH = (h * 0.60).toNumber();

        // --- Y-axis labels (3 ticks: top, mid, bottom) ---
        var labelX = boxX - 4;
        var yLabelTop = yMax;
        var yLabelMid = (yMax + yMin) / 2.0;
        var yLabelBot = yMin;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        if (_hrMode) {
            dc.drawText(labelX, boxY - 7,
                Graphics.FONT_XTINY, yLabelTop.format("%.0f"),
                Graphics.TEXT_JUSTIFY_RIGHT);
            dc.drawText(labelX, boxY + boxH / 2 - 7,
                Graphics.FONT_XTINY, yLabelMid.format("%.0f"),
                Graphics.TEXT_JUSTIFY_RIGHT);
            dc.drawText(labelX, boxY + boxH - 7,
                Graphics.FONT_XTINY, yLabelBot.format("%.0f"),
                Graphics.TEXT_JUSTIFY_RIGHT);
        } else {
            dc.drawText(labelX, boxY - 7,
                Graphics.FONT_XTINY, yLabelTop.format("%.1f"),
                Graphics.TEXT_JUSTIFY_RIGHT);
            dc.drawText(labelX, boxY + boxH / 2 - 7,
                Graphics.FONT_XTINY, yLabelMid.format("%.1f"),
                Graphics.TEXT_JUSTIFY_RIGHT);
            dc.drawText(labelX, boxY + boxH - 7,
                Graphics.FONT_XTINY, yLabelBot.format("%.1f"),
                Graphics.TEXT_JUSTIFY_RIGHT);
        }

        // Horizontal grid lines at the 3 Y tick positions
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(boxX, boxY,             boxX + boxW, boxY);
        dc.drawLine(boxX, boxY + boxH / 2,  boxX + boxW, boxY + boxH / 2);
        dc.drawLine(boxX, boxY + boxH,       boxX + boxW, boxY + boxH);

        // Vertical axis line
        dc.drawLine(boxX, boxY, boxX, boxY + boxH);

        // Average horizontal line (subtle, slightly brighter than grid)
        var avgPy = boxY + boxH - (boxH.toFloat() * (avg - yMin) / yRange).toNumber();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var dashStep = (w * 0.04).toNumber();
        var dashX    = boxX;
        while (dashX < boxX + boxW) {
            var dashEnd = dashX + dashStep / 2;
            if (dashEnd > boxX + boxW) { dashEnd = boxX + boxW; }
            dc.drawLine(dashX, avgPy, dashEnd, avgPy);
            dashX = dashX + dashStep;
        }

        // --- Second pass: draw segments + track peak ---
        var prevX   = -1;
        var prevY   = -1;
        var peakVal = -999999.0;
        var peakX   = -1;
        var peakY   = -1;

        for (var i = 0; i < n; i++) {
            var v = samples[i];
            if (v == null) { prevX = -1; continue; }
            var vf    = v.toFloat();
            var px    = boxX + (boxW.toFloat() * i / (n - 1)).toNumber();
            var py    = boxY + boxH - (boxH.toFloat() * (vf - yMin) / yRange).toNumber();
            var phase = 0;
            if ((phases has :size) && i < phases.size()) { phase = phases[i]; }
            var color = (phase == 0) ? Graphics.COLOR_RED : Graphics.COLOR_BLUE;

            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            if (prevX >= 0) {
                dc.drawLine(prevX, prevY, px, py);
            } else {
                dc.fillCircle(px, py, 2);
            }

            if (vf > peakVal) {
                peakVal = vf;
                peakX   = px;
                peakY   = py;
            }
            prevX = px;
            prevY = py;
        }

        // Peak dot
        if (peakX >= 0) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(peakX, peakY, 3);
        }

        // --- X-axis labels (start, mid, end) ---
        var xLabelY = boxY + boxH + (h * 0.03).toNumber();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);

        if ((timesT has :size) && timesT.size() >= 2) {
            var tStart = timesT[0];
            var tEnd   = timesT[timesT.size() - 1];
            var tMid   = timesT[timesT.size() / 2];

            dc.drawText(boxX,           xLabelY, Graphics.FONT_XTINY,
                formatElapsed(tStart), Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(boxX + boxW / 2, xLabelY, Graphics.FONT_XTINY,
                formatElapsed(tMid),   Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(boxX + boxW,    xLabelY, Graphics.FONT_XTINY,
                formatElapsed(tEnd),   Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // Format elapsed seconds as "Mm Ss" → "0m", "14m", "28m 30s"
    private function formatElapsed(secs) {
        var m = secs / 60;
        var s = secs % 60;
        if (m == 0) { return s + "s"; }
        if (s == 0) { return m + "m"; }
        return m + "m" + s + "s";
    }
}
