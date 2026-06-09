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
    var sampleT;      // Array<Number>  - elapsed seconds at each sample
    var sampleHR;     // Array<Number or Null> - heart rate bpm
    var sampleTemp;   // Array<Float or Null>  - skin temp °C
    var samplePhase;  // Array<Number>  - 0 = heat, 1 = rest

    function initialize(dose, inZoneSec, rounds, acclGain, acclTotal,
                        sampleT, sampleHR, sampleTemp, samplePhase) {
        self.dose       = dose;
        self.inZoneSec  = inZoneSec;
        self.rounds     = rounds;
        self.acclGain   = acclGain;
        self.acclTotal  = acclTotal;
        self.sampleT    = sampleT;
        self.sampleHR   = sampleHR;
        self.sampleTemp = sampleTemp;
        self.samplePhase = samplePhase;
    }
}

// ---------------------------------------------------------------------------
// PostSessionDelegate: drives the 4-page post-session carousel.
//
//   Page 0 — SummaryView       (1 / 4)
//   Page 1 — AcclimationView   (2 / 4)
//   Page 2 — SessionGraphView  HR    (3 / 4)
//   Page 3 — SessionGraphView  temp  (4 / 4)
//
// UP → advance page (wraps); DOWN → retreat page (wraps).
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

    function onSelect() {
        var v = new HeatAccView();
        WatchUi.switchToView(v, new HeatAccDelegate(v), WatchUi.SLIDE_LEFT);
        return true;
    }

    function onKey(evt) {
        var k = evt.getKey();
        if (k == WatchUi.KEY_DOWN) {
            var next = (_page + 1) % 4;
            WatchUi.switchToView(makeView(next),
                new PostSessionDelegate(next, _data), WatchUi.SLIDE_UP);
            return true;
        } else if (k == WatchUi.KEY_UP) {
            var prev = (_page + 3) % 4;
            WatchUi.switchToView(makeView(prev),
                new PostSessionDelegate(prev, _data), WatchUi.SLIDE_DOWN);
            return true;
        }
        return false;
    }

    function onBack() { return false; }

    private function makeView(page) {
        if (page == 0) { return new SummaryView(_data); }
        if (page == 1) { return new AcclimationView(); }
        if (page == 2) { return new SessionGraphView(_data, true); }
        return new SessionGraphView(_data, false);
    }
}
