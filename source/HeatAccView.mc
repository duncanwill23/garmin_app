using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Activity;
using Toybox.SensorHistory;
using Toybox.UserProfile;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Timer;
using Toybox.Application.Storage;

// ---------------------------------------------------------------------------
// HeatAccView: owns the 1 Hz sampling loop, DoseEngine, and ActivityRecording
// session. Implements the IDLE / HEAT / REST / PAUSED state machine.
//
// Dose accrues only during HEAT. Recording (FIT record fields) continues
// through REST so HR recovery is captured in the FIT file. Drift is computed
// per heat round so rest gaps cannot corrupt the regression slope.
// ---------------------------------------------------------------------------
class HeatAccView extends WatchUi.View {

    private var _timer;
    private var _dose;
    private var _session;
    private var _modality       = Config.MODALITY_DRY;
    private var _hrMax;
    private var _state          = Config.STATE_IDLE;
    private var _round          = 0;
    private var _pausedFrom     = Config.STATE_IDLE;
    private var _sessionElapsed = 0;  // total active seconds (HEAT + REST, not PAUSED)
    private var _phaseElapsed   = 0;  // seconds since last phase transition
    private var _restStartHr    = null;
    private var _roundRecovery  = null;  // bpm drop in first 60 s of rest

    // Per-session sample arrays (collected every 5 s, used for post-session graphs)
    private var _sampleT;
    private var _sampleHR;
    private var _sampleTemp;
    private var _samplePhase;

    function initialize() {
        View.initialize();
        _hrMax = resolveHrMax();
        var saved = Storage.getValue("last_modality");
        if (saved != null && (saved == Config.MODALITY_DRY || saved == Config.MODALITY_STEAM)) {
            _modality = saved;
        }
    }

    // --- HRmax: prefer user's configured zones, fall back to 220-age ---
    private function resolveHrMax() {
        var zones = null;
        try {
            zones = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_GENERIC);
        } catch (e) {
            zones = null;
        }
        if (zones != null && zones.size() > 0) {
            return zones[zones.size() - 1];
        }
        var profile = UserProfile.getProfile();
        if (profile != null && profile.birthYear != null) {
            var year = Gregorian.info(Time.now(), Time.FORMAT_SHORT).year;
            var age  = year - profile.birthYear;
            if (age > 0 && age < 120) { return Config.HR_MAX_AGE_BASE - age; }
        }
        return Config.HR_MAX_LAST_RESORT;
    }

    function setModality(m) {
        _modality = m;
        Storage.setValue("last_modality", m);
    }
    function modality()     { return _modality; }
    function getState()     { return _state; }

    // -----------------------------------------------------------------------
    // Session control (called by delegate and StopMenuDelegate)
    // -----------------------------------------------------------------------

    function startSession() {
        if (_state != Config.STATE_IDLE) { return; }
        TrendStore.startProgramIfNeeded();
        _dose    = new DoseEngine(_hrMax, _modality);
        _dose.startNewRound();
        _session = new SessionManager();
        _session.start(_modality);
        _sessionElapsed = 0;
        _phaseElapsed   = 0;
        _round          = 1;
        _restStartHr    = null;
        _roundRecovery  = null;
        _sampleT        = [];
        _sampleHR       = [];
        _sampleTemp     = [];
        _samplePhase    = [];
        _state = Config.STATE_HEAT;
        startTimer();
    }

    // Pause: stop the 1 Hz timer and push the stop menu. The FIT recording
    // keeps running — only scoring stops.
    function pauseSession() {
        if (_state != Config.STATE_HEAT && _state != Config.STATE_REST) { return; }
        stopTimer();
        _pausedFrom = _state;
        _state = Config.STATE_PAUSED;
        WatchUi.pushView(new StopMenu(), new StopMenuDelegate(self), WatchUi.SLIDE_UP);
    }

    // Resume: restart the 1 Hz timer from the phase we paused from.
    function resumeSession() {
        _state = _pausedFrom;
        startTimer();
        WatchUi.requestUpdate();
    }

    // Save: write the final FIT lap + session fields, then push SummaryView.
    function saveSession() {
        stopTimer();
        if (_pausedFrom == Config.STATE_HEAT) {
            _session.addLap(_dose.roundAvgHr(), _dose.roundMaxHr(),
                _dose.roundDose(), _dose.driftBpmPerMin(), null);
        } else {
            _session.addLap(null, null, null, null, _roundRecovery);
        }
        var now       = TrendStore.nowEpoch();
        var prevAccl  = TrendStore.currentAcclimation(now);
        var acclPct   = TrendStore.commitSession(now, _dose.doseUnits, _dose.refMarkHr);
        var acclGain  = acclPct - prevAccl;
        TrendStore.recordSessionEnd(_dose.refMarkHr);
        _session.finishAndSave(
            _dose.doseUnits, _dose.inZoneSec, _dose.driftBpmPerMin(), null, acclPct);

        var data = new SessionData(
            _dose.doseUnits, _dose.inZoneSec, _round,
            acclGain, acclPct,
            _sampleT, _sampleHR, _sampleTemp, _samplePhase);
        _state = Config.STATE_IDLE;
        WatchUi.switchToView(
            new SummaryView(data),
            new PostSessionDelegate(0, data),
            WatchUi.SLIDE_LEFT);
    }

    // Discard: drop the FIT file and return to IDLE.
    function discardSession() {
        stopTimer();
        _session.discard();
        _state          = Config.STATE_IDLE;
        _round          = 0;
        _sessionElapsed = 0;
        _phaseElapsed   = 0;
        _restStartHr    = null;
        _roundRecovery  = null;
        _dose           = null;
        _session        = null;
        _sampleT        = null;
        _sampleHR       = null;
        _sampleTemp     = null;
        _samplePhase    = null;
        WatchUi.requestUpdate();
    }

    // Lap button: toggle HEAT ↔ REST.
    // HEAT→REST: write heat-round FIT lap, capture rest-start HR.
    // REST→HEAT: write rest FIT lap (with recovery if available), start next round.
    function markLap() {
        if (_state == Config.STATE_HEAT) {
            _session.addLap(_dose.roundAvgHr(), _dose.roundMaxHr(),
                _dose.roundDose(), _dose.driftBpmPerMin(), null);
            var info     = Activity.getActivityInfo();
            _restStartHr   = (info != null && (info has :currentHeartRate))
                ? info.currentHeartRate : null;
            _roundRecovery = null;
            _phaseElapsed  = 0;
            _state = Config.STATE_REST;
        } else if (_state == Config.STATE_REST) {
            _session.addLap(null, null, null, null, _roundRecovery);
            _round++;
            _phaseElapsed  = 0;
            _restStartHr   = null;
            _roundRecovery = null;
            _dose.startNewRound();
            _state = Config.STATE_HEAT;
        }
        WatchUi.requestUpdate();
    }

    // -----------------------------------------------------------------------
    // 1 Hz timer
    // -----------------------------------------------------------------------
    private function startTimer() {
        _timer = new Timer.Timer();
        _timer.start(method(:onTick), 1000, true);
    }
    private function stopTimer() {
        if (_timer != null) { _timer.stop(); _timer = null; }
    }

    function onTick() as Void {
        var info = Activity.getActivityInfo();
        var hr   = (info != null && (info has :currentHeartRate))
            ? info.currentHeartRate : null;

        _sessionElapsed++;
        _phaseElapsed++;

        if (_state == Config.STATE_HEAT) {
            _dose.addSample(hr, _sessionElapsed);
            _session.onSecond(_dose.inBand(hr), _dose.pctHrMax(hr));
            if (SafetyGate.sessionAtCap(_sessionElapsed)) {
                // TODO: push a cap-warning dialog.
            }
        } else if (_state == Config.STATE_REST) {
            // Recording continues; no dose accrual.
            _session.onSecond(false, _dose.pctHrMax(hr));
            // Capture HR recovery at the 60-second mark.
            if (_roundRecovery == null && _phaseElapsed == 60
                    && _restStartHr != null && hr != null) {
                _roundRecovery = _restStartHr - hr;  // positive = HR dropped
            }
        }

        // Graph sample every 5 s during active phases.
        if ((_state == Config.STATE_HEAT || _state == Config.STATE_REST)
                && _sessionElapsed % 5 == 0
                && (_sampleT has :add)) {
            _sampleT.add(_sessionElapsed);
            _sampleHR.add(hr);
            _sampleTemp.add(currentSkinTempC());
            _samplePhase.add(_state == Config.STATE_HEAT ? 0 : 1);
        }
        WatchUi.requestUpdate();
    }

    // -----------------------------------------------------------------------
    // Rendering — all positions are fractions of screen size (see CLAUDE.md)
    // -----------------------------------------------------------------------
    function onUpdate(dc) {
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var info  = Activity.getActivityInfo();
        var hr    = (info != null && (info has :currentHeartRate))
            ? info.currentHeartRate : null;
        var hrStr = (hr == null) ? "--" : hr.toString();

        if (_state == Config.STATE_HEAT) {
            drawHeatScreen(dc, h, cx, hr, hrStr);
        } else if (_state == Config.STATE_REST) {
            drawRestScreen(dc, h, cx, hrStr);
        } else {
            drawIdleScreen(dc, h, cx);
        }
    }

    // Return current wrist skin temperature in °C, or null if unavailable.
    private function currentSkinTempC() {
        if (!(Toybox has :SensorHistory)) { return null; }
        if (!(SensorHistory has :getTemperatureHistory)) { return null; }
        var sample = SensorHistory.getTemperatureHistory(
            {:period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST}).next();
        if (sample == null || sample.data == null) { return null; }
        return sample.data;
    }

    // HEAT screen: round banner · HR · %HRmax (green when in zone) · time/dose · skin temp · proxy tag
    private function drawHeatScreen(dc, h, cx, hr, hrStr) {
        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.06, Graphics.FONT_XTINY,
            "HEAT  R" + _round, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.18, Graphics.FONT_NUMBER_MEDIUM,
            hrStr, Graphics.TEXT_JUSTIFY_CENTER);

        // %HRmax — green when in zone, gray otherwise
        var pct = _dose.pctHrMax(hr);
        var pctColor = _dose.inBand(hr) ? Graphics.COLOR_GREEN : Graphics.COLOR_LT_GRAY;
        dc.setColor(pctColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.52, Graphics.FONT_SMALL,
            pct + "%", Graphics.TEXT_JUSTIFY_CENTER);

        // Phase time · cumulative dose
        var pmm = (_phaseElapsed / 60).format("%02d");
        var pss = (_phaseElapsed % 60).format("%02d");
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.66, Graphics.FONT_XTINY,
            pmm + ":" + pss + "  " + _dose.doseUnits.format("%.0f") + " dose",
            Graphics.TEXT_JUSTIFY_CENTER);

        // Skin temperature (wrist sensor — not core temp)
        var tempC = currentSkinTempC();
        if (tempC != null) {
            var tempF = tempC.toFloat() * 9.0 / 5.0 + 32.0;
            dc.drawText(cx, h * 0.78, Graphics.FONT_XTINY,
                tempC.format("%.1f") + "\u00B0C  " + tempF.format("%.1f") + "\u00B0F  skin",
                Graphics.TEXT_JUSTIFY_CENTER);
        }

        // dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        // dc.drawText(cx, h * 0.90, Graphics.FONT_XTINY,
        //     "HR proxy", Graphics.TEXT_JUSTIFY_CENTER);
    }

    // REST screen: banner · HR · phase time · dose (frozen) · skin temp
    private function drawRestScreen(dc, h, cx, hrStr) {
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.06, Graphics.FONT_XTINY,
            "REST", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.18, Graphics.FONT_NUMBER_MEDIUM,
            hrStr, Graphics.TEXT_JUSTIFY_CENTER);

        var pmm = (_phaseElapsed / 60).format("%02d");
        var pss = (_phaseElapsed % 60).format("%02d");
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.52, Graphics.FONT_SMALL,
            pmm + ":" + pss, Graphics.TEXT_JUSTIFY_CENTER);

        // Dose frozen during rest — shown for reference
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.64, Graphics.FONT_XTINY,
            _dose.doseUnits.format("%.0f") + " dose", Graphics.TEXT_JUSTIFY_CENTER);

        // Skin temperature (wrist sensor — not core temp)
        var tempC = currentSkinTempC();
        if (tempC != null) {
            var tempF = tempC.toFloat() * 9.0 / 5.0 + 32.0;
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.76, Graphics.FONT_XTINY,
                tempC.format("%.1f") + "\u00B0C  " + tempF.format("%.1f") + "\u00B0F  skin",
                Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // IDLE screen: carousel modality toggle
    // Content block centered at h*0.50; chevrons equidistant above/below.
    // Layout fractions (of h): ▲ 0.24, glyph 0.38, name 0.48, descriptor 0.62, ▼ 0.77
    private function drawIdleScreen(dc, h, cx) {
        var isDry = (_modality == Config.MODALITY_DRY);

        var accentPrimary   = isDry ? Config.COLOR_DRY_PRIMARY   : Config.COLOR_STEAM_PRIMARY;
        var accentSecondary = isDry ? Config.COLOR_DRY_SECONDARY : Config.COLOR_STEAM_SECONDARY;

        var nameLabel = isDry ? "Sauna" : "Steam";
        var descLabel = isDry ? "dry heat" : "humid heat";

        // Up chevron
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        var upY = (h * 0.24).toNumber();
        dc.fillPolygon([[cx, upY - 8], [cx - 8, upY + 4], [cx + 8, upY + 4]]);

        // Heat-wave glyph
        drawHeatWave(dc, cx, (h * 0.38).toNumber(), accentPrimary, accentSecondary);

        // Selected modality name — white, prominent
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.48).toNumber(), Graphics.FONT_MEDIUM,
            nameLabel, Graphics.TEXT_JUSTIFY_CENTER);

        // Descriptor in accent color
        dc.setColor(accentPrimary, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.62).toNumber(), Graphics.FONT_XTINY,
            descLabel, Graphics.TEXT_JUSTIFY_CENTER);

        // Down chevron
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        var downY = (h * 0.77).toNumber();
        dc.fillPolygon([[cx, downY + 8], [cx - 8, downY - 4], [cx + 8, downY - 4]]);
    }

    // Three vertical heat-wave strokes centered at (cx, y).
    // Each stroke travels top→bottom, zigzagging left/right like rising heat.
    // Stroke colors: primary, secondary, primary (left to right).
    private function drawHeatWave(dc, cx, y, primary, secondary) {
        var strokeH = 22;  // vertical height of each wave stroke
        var amp     = 4;   // horizontal zigzag amplitude (pixels each side of center)
        var gap     = 10;  // horizontal gap between stroke centers
        var segs    = 4;   // zigzag segments per stroke

        var colors = [primary, secondary, primary];
        // Three stroke centers: cx-gap, cx, cx+gap
        var startCx = cx - gap;

        for (var w = 0; w < 3; w++) {
            dc.setColor(colors[w], Graphics.COLOR_TRANSPARENT);
            var scx  = startCx + w * gap;
            var segH = strokeH / segs;
            for (var s = 0; s < segs; s++) {
                var y1 = (y - strokeH / 2 + s * segH).toNumber();
                var y2 = (y - strokeH / 2 + (s + 1) * segH).toNumber();
                var x1 = (s % 2 == 0) ? scx - amp : scx + amp;
                var x2 = (s % 2 == 0) ? scx + amp : scx - amp;
                dc.drawLine(x1, y1, x2, y2);
            }
        }
    }

    function onHide() { stopTimer(); }
}
