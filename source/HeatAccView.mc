using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Activity;
using Toybox.Attention;
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

    // Silence / vibration toggle (persisted across sessions)
    private var _silent = false;

    // HR alert state (advisory only — never blocks dose)
    private var _sustainedHighSec = 0;
    private var _highVibrated     = false;
    private var _alertBanner      = null;  // null = no alert

    // Armed workout (set by IdleMenuDelegate, consumed by startSession)
    private var _armedWorkout    = null;

    // Workout execution mode (§12)
    private var _workout         = null;
    private var _originalWorkout = null;  // kept for SessionData after _workout is cleared
    private var _stepIndex       = 0;
    private var _workoutMode     = false;
    private var _totalSteps      = 0;

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
        var savedSilent = Storage.getValue(Config.STORAGE_KEY_SILENT);
        if (savedSilent != null) { _silent = savedSilent; }
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
    function modality()       { return _modality; }
    function getState()       { return _state; }
    function armedWorkout()   { return _armedWorkout; }
    function isSilent()       { return _silent; }
    function setSilent(val)   { _silent = val; }

    function armWorkout(w) {
        _armedWorkout = w;
        if (w != null && (w has :modality)) { _modality = w.modality; }
        WatchUi.requestUpdate();
    }

    function cancelWorkout() {
        _armedWorkout = null;
        WatchUi.requestUpdate();
    }

    // -----------------------------------------------------------------------
    // Session control (called by delegate and StopMenuDelegate)
    // -----------------------------------------------------------------------

    function startSession() {
        if (_state != Config.STATE_IDLE) { return; }
        TrendStore.startProgramIfNeeded();

        // Consume armed workout (null = free session)
        _workout         = _armedWorkout;
        _originalWorkout = _armedWorkout;
        _armedWorkout    = null;
        if (_workout != null && (_workout has :modality)) {
            _modality = _workout.modality;
        }
        _workoutMode = (_workout != null);
        _stepIndex   = 0;
        _totalSteps  = (_workout != null && (_workout.steps has :size))
            ? _workout.steps.size() : 0;

        _dose    = new DoseEngine(_hrMax, _modality);
        _dose.startNewRound();
        _session = new SessionManager();
        _session.start(_modality);
        _sessionElapsed = 0;
        _phaseElapsed   = 0;
        _round          = 1;
        _restStartHr    = null;
        _roundRecovery  = null;
        _sampleT           = [];
        _sampleHR          = [];
        _sampleTemp        = [];
        _samplePhase       = [];
        _sustainedHighSec  = 0;
        _highVibrated      = false;
        _alertBanner       = null;
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
            _sampleT, _sampleHR, _sampleTemp, _samplePhase, _modality, _originalWorkout);
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
        _dose            = null;
        _session         = null;
        _sampleT         = null;
        _sampleHR        = null;
        _sampleTemp      = null;
        _samplePhase     = null;
        _originalWorkout = null;
        WatchUi.requestUpdate();
    }

    // Lap button: toggle HEAT ↔ REST (free) or skip current step (workout mode).
    function markLap() {
        if (_workoutMode) {
            advanceStep();
            return;
        }
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

    // Advance to the next workout step (or fall through to free mode on last step).
    private function advanceStep() {
        // Write FIT lap for the completed step
        if (_state == Config.STATE_HEAT) {
            _session.addLap(_dose.roundAvgHr(), _dose.roundMaxHr(),
                _dose.roundDose(), _dose.driftBpmPerMin(), null);
        } else {
            _session.addLap(null, null, null, null, _roundRecovery);
        }

        _stepIndex++;
        if (_stepIndex >= _totalSteps) {
            // Last step done — fall through to free count-up mode
            _workoutMode = false;
            _workout     = null;
            _alertBanner = "Done · free mode";
            vibrateOnce();
            WatchUi.requestUpdate();
            return;
        }

        // Load next step
        var nextStep = _workout.steps[_stepIndex];
        if (nextStep instanceof WorkoutStep && nextStep.type == Config.STEP_HEAT) {
            _round++;
            _phaseElapsed  = 0;
            _restStartHr   = null;
            _roundRecovery = null;
            _dose.startNewRound();
            _state = Config.STATE_HEAT;
            _alertBanner = "Round " + _round;
        } else {
            var info = Activity.getActivityInfo();
            _restStartHr   = (info != null && (info has :currentHeartRate))
                ? info.currentHeartRate : null;
            _roundRecovery = null;
            _phaseElapsed  = 0;
            _state = Config.STATE_REST;
            _alertBanner = "Rest";
        }
        vibrateOnce();
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
            checkHrAlerts(hr);
        } else if (_state == Config.STATE_REST) {
            // Recording continues; no dose accrual.
            _session.onSecond(false, _dose.pctHrMax(hr));
            // Capture HR recovery at the 60-second mark.
            if (_roundRecovery == null && _phaseElapsed == 60
                    && _restStartHr != null && hr != null) {
                _roundRecovery = _restStartHr - hr;  // positive = HR dropped
            }
        }

        // Workout mode: auto-advance when step duration elapses.
        if (_workoutMode && _workout != null && _stepIndex < _totalSteps) {
            var curStep = _workout.steps[_stepIndex];
            if (curStep instanceof WorkoutStep && curStep.durationSec != null
                    && _phaseElapsed >= curStep.durationSec) {
                advanceStep();
                return;  // advanceStep calls requestUpdate
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
        // Steam "est." honesty tag (CLAUDE.md hard rule)
        // if (_modality == Config.MODALITY_STEAM) {
        //     dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        //     dc.drawText(cx, h * 0.02, Graphics.FONT_XTINY,
        //         "steam", Graphics.TEXT_JUSTIFY_CENTER);
        // }

        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        var heatHeader = _workoutMode
            ? "R" + _round + "/" + _workout.heatRounds() + "  HEAT"
            : "HEAT  R" + _round;
        dc.drawText(cx, h * 0.06, Graphics.FONT_XTINY,
            heatHeader, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.18, Graphics.FONT_NUMBER_MEDIUM,
            hrStr, Graphics.TEXT_JUSTIFY_CENTER);

        // %HRmax — green when in zone, gray otherwise
        var pct = _dose.pctHrMax(hr);
        var pctColor = _dose.inBand(hr) ? Graphics.COLOR_GREEN : Graphics.COLOR_LT_GRAY;
        dc.setColor(pctColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.52, Graphics.FONT_SMALL,
            pct + "%", Graphics.TEXT_JUSTIFY_CENTER);

        // Phase time (countdown in workout mode, count-up in free mode) · dose
        var timeStr;
        if (_workoutMode && _workout != null && _stepIndex < _totalSteps) {
            var curStep = _workout.steps[_stepIndex];
            if (curStep instanceof WorkoutStep && curStep.durationSec != null) {
                var rem = curStep.durationSec - _phaseElapsed;
                if (rem < 0) { rem = 0; }
                timeStr = (rem / 60).format("%02d") + ":" + (rem % 60).format("%02d");
            } else {
                timeStr = (_phaseElapsed / 60).format("%02d") + ":" + (_phaseElapsed % 60).format("%02d");
            }
        } else {
            timeStr = (_phaseElapsed / 60).format("%02d") + ":" + (_phaseElapsed % 60).format("%02d");
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.66, Graphics.FONT_XTINY,
            timeStr + "  " + _dose.doseUnits.format("%.0f") + " dose",
            Graphics.TEXT_JUSTIFY_CENTER);

        // Skin temperature (wrist sensor — not core temp)
        var tempC = currentSkinTempC();
        if (tempC != null) {
            var tempF = tempC.toFloat() * 9.0 / 5.0 + 32.0;
            dc.drawText(cx, h * 0.78, Graphics.FONT_XTINY,
                tempC.format("%.1f") + "\u00B0C  " + tempF.format("%.1f") + "\u00B0F  skin",
                Graphics.TEXT_JUSTIFY_CENTER);
        }

        // HR alert banner (advisory — appears above ProxyNote)
        if (_alertBanner != null) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.84, Graphics.FONT_XTINY,
                _alertBanner, Graphics.TEXT_JUSTIFY_CENTER);
        }

        // dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        // dc.drawText(cx, h * 0.92, Graphics.FONT_XTINY,
        //     WatchUi.loadResource(Rez.Strings.ProxyNote), Graphics.TEXT_JUSTIFY_CENTER);
    }

    // REST screen: banner · HR · phase time · dose (frozen) · skin temp
    private function drawRestScreen(dc, h, cx, hrStr) {
        // Steam "est." honesty tag
        // if (_modality == Config.MODALITY_STEAM) {
        //     dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        //     dc.drawText(cx, h * 0.02, Graphics.FONT_XTINY,
        //         "steam", Graphics.TEXT_JUSTIFY_CENTER);
        // }

        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.06, Graphics.FONT_XTINY,
            "REST", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.18, Graphics.FONT_NUMBER_MEDIUM,
            hrStr, Graphics.TEXT_JUSTIFY_CENTER);

        var restTimeStr;
        if (_workoutMode && _workout != null && _stepIndex < _totalSteps) {
            var curStep = _workout.steps[_stepIndex];
            if (curStep instanceof WorkoutStep && curStep.durationSec != null) {
                var rem = curStep.durationSec - _phaseElapsed;
                if (rem < 0) { rem = 0; }
                restTimeStr = (rem / 60).format("%02d") + ":" + (rem % 60).format("%02d");
            } else {
                restTimeStr = (_phaseElapsed / 60).format("%02d") + ":" + (_phaseElapsed % 60).format("%02d");
            }
        } else {
            restTimeStr = (_phaseElapsed / 60).format("%02d") + ":" + (_phaseElapsed % 60).format("%02d");
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.52, Graphics.FONT_SMALL,
            restTimeStr, Graphics.TEXT_JUSTIFY_CENTER);

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

        // dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        // dc.drawText(cx, h * 0.90, Graphics.FONT_XTINY,
        //     WatchUi.loadResource(Rez.Strings.ProxyNote), Graphics.TEXT_JUSTIFY_CENTER);
    }

    // IDLE screen: carousel modality toggle (or armed workout display).
    // Three dots at top hint at the long-press OPTIONS menu.
    // Bottom lines: calibration progress or acclimation %, and decay hint.
    private function drawIdleScreen(dc, h, cx) {
        var isDry = (_modality == Config.MODALITY_DRY);
        var accentPrimary   = isDry ? Config.COLOR_DRY_PRIMARY   : Config.COLOR_STEAM_PRIMARY;
        var accentSecondary = isDry ? Config.COLOR_DRY_SECONDARY : Config.COLOR_STEAM_SECONDARY;

        // Three-dot menu hint — left edge, vertically stacked, level with the
        // physical UP button so users discover the long-press gesture.
        // cx = w/2, so left-edge 7% = cx * 0.14
        var dotX = (cx * 0.14).toNumber();
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(dotX, (h * 0.43).toNumber(), 3);
        dc.fillCircle(dotX, (h * 0.50).toNumber(), 3);
        dc.fillCircle(dotX, (h * 0.57).toNumber(), 3);

        if (_armedWorkout != null) {
            // --- Armed workout display ---
            var wName = (_armedWorkout has :name) ? _armedWorkout.name : "Workout";
            var wRat  = (_armedWorkout has :rationale) ? _armedWorkout.rationale : "";
            var wMod  = (_armedWorkout has :modality) ? _armedWorkout.modality : _modality;
            var modStr = (wMod == Config.MODALITY_STEAM) ? "Steam" : "Dry Sauna";

            dc.setColor(accentPrimary, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.24).toNumber(), Graphics.FONT_XTINY,
                modStr, Graphics.TEXT_JUSTIFY_CENTER);

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.34).toNumber(), Graphics.FONT_MEDIUM,
                wName, Graphics.TEXT_JUSTIFY_CENTER);

            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.52).toNumber(), Graphics.FONT_XTINY,
                wRat, Graphics.TEXT_JUSTIFY_CENTER);

            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.64).toNumber(), Graphics.FONT_XTINY,
                WatchUi.loadResource(Rez.Strings.UseThisWorkout),
                Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            // --- Free-mode carousel ---
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

        // --- Bottom info lines ---
        var n = TrendStore.sessionCount();
        if (n < Config.CALIBRATION_SESSIONS) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.85).toNumber(), Graphics.FONT_XTINY,
                WatchUi.loadResource(Rez.Strings.BuildingBaseline) + " (" + n + "/5)",
                Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            var acclPct = TrendStore.currentAcclimation(TrendStore.nowEpoch());
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.85).toNumber(), Graphics.FONT_XTINY,
                "~" + acclPct.format("%.0f") + "% acclimated",
                Graphics.TEXT_JUSTIFY_CENTER);
        }

        var days = TrendStore.daysSinceLastNum();
        if (days > 3) {
            var decayPct = (days * Config.DECAY_PCT_PER_DAY * 100.0).toNumber();
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.93).toNumber(), Graphics.FONT_XTINY,
                "~" + decayPct + "% decayed",
                Graphics.TEXT_JUSTIFY_CENTER);
        }
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

    // -----------------------------------------------------------------------
    // HR alert logic (advisory only — dose keeps accruing)
    // -----------------------------------------------------------------------
    private function checkHrAlerts(hr) {
        if (hr == null) { return; }
        var pct = _dose.pctHrMax(hr);
        var highThresh      = (Config.HR_HIGH_PCT      * 100).toNumber();
        var sustainedThresh = (Config.HR_SUSTAINED_PCT * 100).toNumber();

        if (pct >= highThresh) {
            _sustainedHighSec = 0;
            if (!_highVibrated) {
                _highVibrated = true;
                _alertBanner  = "HR very high";
                vibrateOnce();
            }
        } else if (pct >= sustainedThresh) {
            _highVibrated = false;
            _sustainedHighSec++;
            if (_sustainedHighSec >= Config.HR_SUSTAINED_SEC) {
                _alertBanner = "high HR · cool down";
                vibrateOnce();
                _sustainedHighSec = 0;  // re-arm after next threshold crossing
            }
        } else {
            _sustainedHighSec = 0;
            _highVibrated     = false;
            _alertBanner      = null;
        }
    }

    private function vibrateOnce() {
        if (_silent) { return; }
        if (!(Toybox has :Attention)) { return; }
        if (!(Attention has :vibrate)) { return; }
        Attention.vibrate([new Attention.VibeProfile(50, 300)]);
    }

    function onHide() { stopTimer(); }
}
