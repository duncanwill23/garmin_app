// ---------------------------------------------------------------------------
// DoseEngine: the core proxy model.
// Dose = modality-weighted seconds spent at/above the target HR band, during
// HEAT phases only. HR drift is tracked per heat round (not session-long) so
// rest gaps do not corrupt the regression slope.
//
// Call startNewRound() at the start of each heat round. Session totals
// (doseUnits, inZoneSec) keep accumulating across rounds; drift accumulators
// and per-round stats reset.
//
// This is a PROXY for core-temperature-time, never a temperature measurement.
// ---------------------------------------------------------------------------
class DoseEngine {

    private var _hrMax;
    private var _bandLow;
    private var _bandHigh;
    private var _modalityMult;

    // Session totals (accumulate across all heat rounds)
    public var inZoneSec = 0;
    public var doseUnits = 0.0;

    // HR at the adaptation reference mark (session-wide; captured once)
    public var refMarkHr = null;

    // Per-round drift accumulators (reset by startNewRound())
    // t-axis is _roundElapsed so rest gaps never enter the regression.
    private var _sumT         = 0.0;
    private var _sumHr        = 0.0;
    private var _sumTT        = 0.0;
    private var _sumTHr       = 0.0;
    private var _roundSamples = 0;
    private var _roundElapsed = 0;

    // Per-round stats for lap FIT fields (reset by startNewRound())
    private var _roundStartDose   = 0.0;
    private var _roundStartInZone = 0;
    private var _roundHrSum       = 0.0;
    private var _roundHrCount     = 0;
    private var _roundHrMax       = 0;

    function initialize(hrMax, modality) {
        _hrMax        = hrMax;
        _bandLow      = (hrMax * Config.TARGET_HR_LOW_PCT).toNumber();
        _bandHigh     = (hrMax * Config.TARGET_HR_HIGH_PCT).toNumber();
        _modalityMult = (modality == Config.MODALITY_STEAM)
            ? Config.DOSE_MULT_STEAM : Config.DOSE_MULT_DRY;
    }

    // Call at the start of each heat round. Resets per-round drift and stats
    // while session totals continue accumulating.
    function startNewRound() {
        _sumT = 0.0; _sumHr = 0.0; _sumTT = 0.0; _sumTHr = 0.0;
        _roundSamples     = 0;
        _roundElapsed     = 0;
        _roundStartDose   = doseUnits;
        _roundStartInZone = inZoneSec;
        _roundHrSum       = 0.0;
        _roundHrCount     = 0;
        _roundHrMax       = 0;
    }

    // Call once per second during HEAT only. hr may be null.
    // sessionElapsed = total session time (HEAT + REST); used only for
    // refMarkHr capture so the reference mark stays at the right absolute time.
    function addSample(hr, sessionElapsed) {
        if (hr == null) { return; }
        _roundSamples++;
        _roundElapsed++;

        if (hr >= _bandLow) {
            inZoneSec++;
            doseUnits += _modalityMult;
        }

        if (refMarkHr == null && sessionElapsed >= Config.ADAPT_REF_MARK_SEC) {
            refMarkHr = hr;
        }

        // Drift uses per-round elapsed time so rest gaps cannot corrupt the slope.
        var t = _roundElapsed.toFloat();
        var h = hr.toFloat();
        _sumT   += t;
        _sumHr  += h;
        _sumTT  += t * t;
        _sumTHr += t * h;

        _roundHrSum += h;
        _roundHrCount++;
        if (hr > _roundHrMax) { _roundHrMax = hr; }
    }

    // HR drift for the current round (bpm/min). Positive = rising.
    function driftBpmPerMin() {
        if (_roundSamples < 2) { return 0.0; }
        var n     = _roundSamples.toFloat();
        var denom = (n * _sumTT) - (_sumT * _sumT);
        if (denom == 0.0) { return 0.0; }
        return ((n * _sumTHr) - (_sumT * _sumHr)) / denom * 60.0;
    }

    // Per-round stats since last startNewRound() — for lap FIT fields.
    function roundDose()      { return doseUnits - _roundStartDose; }
    function roundInZoneSec() { return inZoneSec - _roundStartInZone; }
    function roundAvgHr() {
        if (_roundHrCount == 0) { return 0; }
        return (_roundHrSum / _roundHrCount).toNumber();
    }
    function roundMaxHr() { return _roundHrMax; }

    function pctHrMax(hr) {
        if (hr == null || _hrMax == 0) { return 0; }
        return ((hr.toFloat() / _hrMax.toFloat()) * 100.0).toNumber();
    }

    function inBand(hr) { return hr != null && hr >= _bandLow; }
    function bandLow()  { return _bandLow; }
    function bandHigh() { return _bandHigh; }
}
