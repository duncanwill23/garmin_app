using Toybox.Graphics;
using Toybox.Math;

// ---------------------------------------------------------------------------
// WorkoutRing: draws a segmented ring showing workout structure.
//
// Ring geometry (resolution-relative):
//   ringR = min(w,h) * 0.38  (radius to arc centerline)
//   penW  = min(w,h) * 0.07  (arc stroke width)
// Starting at 12 o'clock (Garmin angle 90) sweeping clockwise.
//
// Public API:
//   drawPreview(dc, workout)                  — static preview + center headline
//   drawLive(dc, workout, elapsedInWorkout)   — preview + progress marker
//   drawSession(dc, data)                     — reconstructed from sample arrays
// ---------------------------------------------------------------------------
module WorkoutRing {

    const HEAT_COLOR = 0xE0392C;
    const REST_COLOR = 0x3E8FD0;
    const COOL_COLOR = 0x7d8088;

    // Static preview ring. Draws ring + center "N x H / min in heat / total" text.
    function drawPreview(dc, workout) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var g = _geo(w, h);
        var steps = workout.steps;
        if (!(steps has :size) || steps.size() == 0) { return; }
        var segs = _stepsToSegs(steps);
        if (segs.size() == 0) { return; }
        var totalSec = _segsTotalSec(segs);
        if (totalSec <= 0) { return; }
        _drawSegments(dc, segs, totalSec, g);
        _drawNotch(dc, g);

        var cx      = g[:cx];
        var cy      = g[:cy];
        var rounds  = workout.heatRounds();
        var heatMin = workout.totalHeatSec() / 60;
        var perRnd  = (rounds > 0) ? (heatMin / rounds) : heatMin;
        var totMin  = totalSec / 60;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - (h * 0.14).toNumber(),
            Graphics.FONT_NUMBER_MEDIUM,
            rounds + " x " + perRnd,
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + (h * 0.05).toNumber(),
            Graphics.FONT_XTINY, "min in heat",
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, cy + (h * 0.15).toNumber(),
            Graphics.FONT_XTINY, totMin + " min total",
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Live ring during a structured workout. elapsedInWorkout = sum of completed
    // step durations plus seconds elapsed in the current step.
    function drawLive(dc, workout, elapsedInWorkout) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var g = _geo(w, h);
        var steps = workout.steps;
        if (!(steps has :size) || steps.size() == 0) { return; }
        var segs = _stepsToSegs(steps);
        if (segs.size() == 0) { return; }
        var totalSec = _segsTotalSec(segs);
        if (totalSec <= 0) { return; }
        _drawSegments(dc, segs, totalSec, g);
        _drawNotch(dc, g);
        var elapsed = elapsedInWorkout.toFloat();
        if (elapsed > totalSec.toFloat()) { elapsed = totalSec.toFloat(); }
        var markerDeg = 90.0 - elapsed / totalSec.toFloat() * 360.0;
        _drawMarker(dc, g, markerDeg);
    }

    // Post-session ring reconstructed from sampleT / samplePhase arrays.
    // Marker placed at full-circle (100% completion).
    function drawSession(dc, data) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var g = _geo(w, h);
        var sT = data.sampleT;
        var sP = data.samplePhase;
        if (sT == null || !(sT has :size) || sT.size() == 0) {
            _drawFallback(dc, g); return;
        }
        var totalSec = sT[sT.size() - 1].toFloat();
        if (totalSec <= 0.0) { _drawFallback(dc, g); return; }
        var segs = _sampleSegs(sT, sP, totalSec);
        _drawSegments(dc, segs, totalSec.toNumber(), g);
        _drawNotch(dc, g);
        _drawMarker(dc, g, 90.0 - 360.0);
    }

    // ---- geometry -----------------------------------------------------------

    function _geo(w, h) {
        var minDim = (w < h) ? w : h;
        var ringR  = (minDim * 0.38).toNumber();
        var penW   = (minDim * 0.07).toNumber();
        if (penW < 4) { penW = 4; }
        return { :cx => w / 2, :cy => h / 2, :ringR => ringR, :penW => penW };
    }

    // ---- segment builders ---------------------------------------------------

    function _stepsToSegs(steps) {
        var segs = [];
        for (var i = 0; i < steps.size(); i++) {
            var s = steps[i];
            if (!(s instanceof WorkoutStep) || s.durationSec == null) { continue; }
            var color;
            if      (s.type == Config.STEP_HEAT) { color = HEAT_COLOR; }
            else if (s.type == Config.STEP_REST) { color = REST_COLOR; }
            else                                  { color = COOL_COLOR; }
            segs.add([color, s.durationSec]);
        }
        return segs;
    }

    function _sampleSegs(sT, sP, totalSec) {
        var segs  = [];
        var n     = sT.size();
        if (n == 0) { return segs; }
        var curPh = sP[0];
        var segT0 = 0.0;
        for (var i = 1; i < n; i++) {
            if (sP[i] != curPh) {
                var span = sT[i].toFloat() - segT0;
                if (span > 0.0) {
                    segs.add([(curPh == 0) ? HEAT_COLOR : REST_COLOR, span]);
                }
                segT0 = sT[i].toFloat();
                curPh = sP[i];
            }
        }
        var lastSpan = totalSec - segT0;
        if (lastSpan > 0.0) {
            segs.add([(curPh == 0) ? HEAT_COLOR : REST_COLOR, lastSpan]);
        }
        return segs;
    }

    function _segsTotalSec(segs) {
        var t = 0;
        for (var i = 0; i < segs.size(); i++) { t += segs[i][1]; }
        return t;
    }

    // ---- drawing primitives -------------------------------------------------

    function _drawSegments(dc, segs, totalSec, g) {
        var cx    = g[:cx];
        var cy    = g[:cy];
        var ringR = g[:ringR];
        var penW  = g[:penW];
        if (segs.size() == 0 || totalSec <= 0) { return; }
        dc.setPenWidth(penW);
        var cursor    = 90.0;
        var degPerSec = 360.0 / totalSec.toFloat();
        for (var i = 0; i < segs.size(); i++) {
            var color   = segs[i][0];
            var secSpan = segs[i][1].toFloat();
            var span    = secSpan * degPerSec;
            if (span < 4.0) { span = 4.0; }
            // Cap to 359° so _norm360 never produces start == end for drawArc.
            if (span > 359.0) { span = 359.0; }
            var endDeg  = cursor - span;
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, ringR, Graphics.ARC_CLOCKWISE,
                _norm360(cursor).toNumber(), _norm360(endDeg).toNumber());
            cursor = endDeg;   // keep un-normalized for the next segment
        }
        dc.setPenWidth(1);
    }

    // White triangle notch at 12 o'clock to mark the start of the ring.
    function _drawNotch(dc, g) {
        var cx   = g[:cx];
        var cy   = g[:cy];
        var tipY = cy - g[:ringR] - (g[:penW] / 2).toNumber() - 3;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[cx, tipY], [cx - 5, tipY + 8], [cx + 5, tipY + 8]]);
    }

    // White filled dot on the ring at the given Garmin angle (0=E, 90=top, CW = decreasing).
    function _drawMarker(dc, g, angleDeg) {
        var cx    = g[:cx];
        var cy    = g[:cy];
        var ringR = g[:ringR];
        var rad   = angleDeg.toFloat() * Math.PI / 180.0;
        var mx    = cx + (ringR.toFloat() * Math.cos(rad)).toNumber();
        var my    = cy - (ringR.toFloat() * Math.sin(rad)).toNumber();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(mx, my, 5);
    }

    function _drawFallback(dc, g) {
        dc.setPenWidth(g[:penW]);
        dc.setColor(HEAT_COLOR, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(g[:cx], g[:cy], g[:ringR], Graphics.ARC_CLOCKWISE,
            _norm360(90).toNumber(), _norm360(90 - 359).toNumber());
        dc.setPenWidth(1);
        _drawNotch(dc, g);
    }

    // Monkey C's % operator is integer-only; use loops for float normalization.
    function _norm360(deg) {
        var d = deg.toFloat();
        while (d < 0.0)    { d += 360.0; }
        while (d >= 360.0) { d -= 360.0; }
        return d;
    }
}
