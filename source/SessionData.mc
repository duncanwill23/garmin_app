using Toybox.WatchUi;

// ---------------------------------------------------------------------------
// SessionData: immutable snapshot of a completed session passed to all
// post-session views and delegates.
// ---------------------------------------------------------------------------
class SessionData {
    var dose;
    var inZoneSec;
    var rounds;
    var acclGain;
    var acclTotal;
    var modality;     // Config.MODALITY_DRY / MODALITY_STEAM
    var sampleT;      // Array<Number>  - elapsed seconds at each sample
    var sampleHR;     // Array<Number or Null> - heart rate bpm
    var sampleTemp;   // Array<Float or Null>  - skin temp °C
    var samplePhase;  // Array<Number>  - 0 = heat, 1 = rest
    var workout;      // Workout or null (null for free sessions)

    function initialize(dose, inZoneSec, rounds, acclGain, acclTotal,
                        sampleT, sampleHR, sampleTemp, samplePhase, modality, workout) {
        self.dose        = dose;
        self.inZoneSec   = inZoneSec;
        self.rounds      = rounds;
        self.acclGain    = acclGain;
        self.acclTotal   = acclTotal;
        self.modality    = modality;
        self.sampleT     = sampleT;
        self.sampleHR    = sampleHR;
        self.sampleTemp  = sampleTemp;
        self.samplePhase = samplePhase;
        self.workout     = workout;
    }
}

// ---------------------------------------------------------------------------
// PostSessionDelegate: drives the 5-page post-session carousel.
//
//   Page 0 — SummaryView        (1 / 5)
//   Page 1 — AcclimationView    (2 / 5)
//   Page 2 — SessionGraphView   HR    (3 / 5)
//   Page 3 — SessionGraphView   temp  (4 / 5)
//   Page 4 — WorkoutRingView    session pattern ring (5 / 5)
//
// DOWN → advance page (wraps); UP → retreat page (wraps).
// START → new session.   BACK → exit app.
// ---------------------------------------------------------------------------
class PostSessionDelegate extends WatchUi.BehaviorDelegate {

    private var _page;
    private var _data;

    function initialize(page, data) {
        BehaviorDelegate.initialize();
        _page = page;
        _data = data;
    }

    function onTap(evt)   { return true; }
    function onHold(evt)  { return true; }
    function onSwipe(evt) { return true; }

    function onSelect() {
        var v = new HeatAccView();
        WatchUi.switchToView(v, new HeatAccDelegate(v), WatchUi.SLIDE_LEFT);
        return true;
    }

    function onKey(evt) {
        var k = evt.getKey();
        if (k == WatchUi.KEY_DOWN) {
            var next = (_page + 1) % 5;
            WatchUi.switchToView(makeView(next),
                new PostSessionDelegate(next, _data), WatchUi.SLIDE_UP);
            return true;
        } else if (k == WatchUi.KEY_UP) {
            var prev = (_page + 4) % 5;
            WatchUi.switchToView(makeView(prev),
                new PostSessionDelegate(prev, _data), WatchUi.SLIDE_DOWN);
            return true;
        }
        return false;
    }

    function onBack() {
        // switchToView clears stale menu/suggestion views from the stack
        // that may have been pushed before the session started.
        var v = new HeatAccView();
        WatchUi.switchToView(v, new HeatAccDelegate(v), WatchUi.SLIDE_RIGHT);
        return true;
    }

    private function makeView(page) {
        if (page == 0) { return new SummaryView(_data); }
        if (page == 1) { return new AcclimationView(); }
        if (page == 2) { return new SessionGraphView(_data, true); }
        if (page == 3) { return new SessionGraphView(_data, false); }
        return new WorkoutRingView(_data);
    }
}

// ---------------------------------------------------------------------------
// WorkoutRingView: page 5 / 5 of the post-session carousel.
// Shows the session pattern as a segmented ring reconstructed from sample
// arrays, with workout name (if structured) and key time stats in the center.
// ---------------------------------------------------------------------------
class WorkoutRingView extends WatchUi.View {

    private var _data;

    function initialize(data) {
        View.initialize();
        _data = data;
    }

    function onUpdate(dc) {
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        // Header: workout name or "Session"
        var title = "Session";
        if (_data.workout != null && (_data.workout has :name)) {
            title = _data.workout.name;
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.02).toNumber(), Graphics.FONT_XTINY,
            title, Graphics.TEXT_JUSTIFY_CENTER);

        // Session pattern ring
        WorkoutRing.drawSession(dc, _data);

        // Center: total elapsed time
        var totalSec = 0;
        if (_data.sampleT != null && (_data.sampleT has :size) && _data.sampleT.size() > 0) {
            totalSec = _data.sampleT[_data.sampleT.size() - 1];
        }
        var totMin = totalSec / 60;
        var totS   = totalSec % 60;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - (h * 0.06).toNumber(),
            Graphics.FONT_MEDIUM,
            totMin + "m " + totS + "s",
            Graphics.TEXT_JUSTIFY_CENTER);

        // In-zone time
        var inZoneMin = (_data.inZoneSec / 60).format("%.0f");
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + (h * 0.10).toNumber(), Graphics.FONT_XTINY,
            inZoneMin + " min in zone", Graphics.TEXT_JUSTIFY_CENTER);

        // Page indicator
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.94).toNumber(), Graphics.FONT_XTINY,
            "5 / 5", Graphics.TEXT_JUSTIFY_CENTER);
    }
}
