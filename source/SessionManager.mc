using Toybox.ActivityRecording;
using Toybox.FitContributor;

// ---------------------------------------------------------------------------
// SessionManager: owns the native Garmin activity so sessions sync to Connect.
// Writes derived metrics as custom FIT fields:
//   record-level (per second): in_zone flag, %HRmax
//   lap-level (per round):     hr_avg, hr_max, dose, drift, recovery
//   session-level (on save):   total dose, in-zone seconds, drift, modality,
//                              fluid loss (optional)
// ---------------------------------------------------------------------------
class SessionManager {

    private var _session = null;

    // Record-level fields (per second)
    private var _fInZone;     // UINT8 0/1
    private var _fPctHrMax;   // UINT8 %

    // Lap-level fields (written before each addLap())
    private var _lHrAvg;      // UINT8 bpm
    private var _lHrMax;      // UINT8 bpm
    private var _lDose;       // FLOAT dose units
    private var _lDrift;      // FLOAT bpm/min
    private var _lRecovery;   // SINT8 bpm drop (signed; positive = HR fell)

    // Session-level fields (written at finish)
    private var _sDose;       // FLOAT
    private var _sInZoneSec;  // UINT16 seconds
    private var _sDrift;      // FLOAT bpm/min
    private var _sModality;   // UINT8 (0 dry / 1 steam)
    private var _sFluidMl;    // UINT16 estimated fluid loss (optional weigh-in)
    private var _sAcclPct;    // FLOAT 0–100 acclimation estimate

    function start(modality, silent) {
        _session = ActivityRecording.createSession({
            :name         => "Heat Acclimation",
            :sport        => Config.REC_SPORT,
            :subSport     => Config.REC_SUB_SPORT,
            :enableAlerts => !silent
        });

        // Record-level (IDs 0–1)
        _fInZone   = _session.createField("in_zone", 0, FitContributor.DATA_TYPE_UINT8,
            { :mesgType => FitContributor.MESG_TYPE_RECORD });
        _fPctHrMax = _session.createField("pct_hrmax", 1, FitContributor.DATA_TYPE_UINT8,
            { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "%" });

        // Lap-level (IDs 20–24)
        _lHrAvg    = _session.createField("lap_hr_avg",  20, FitContributor.DATA_TYPE_UINT8,
            { :mesgType => FitContributor.MESG_TYPE_LAP, :units => "bpm" });
        _lHrMax    = _session.createField("lap_hr_max",  21, FitContributor.DATA_TYPE_UINT8,
            { :mesgType => FitContributor.MESG_TYPE_LAP, :units => "bpm" });
        _lDose     = _session.createField("lap_dose",    22, FitContributor.DATA_TYPE_FLOAT,
            { :mesgType => FitContributor.MESG_TYPE_LAP });
        _lDrift    = _session.createField("lap_drift",   23, FitContributor.DATA_TYPE_FLOAT,
            { :mesgType => FitContributor.MESG_TYPE_LAP, :units => "bpm/min" });
        _lRecovery = _session.createField("lap_recovery",24, FitContributor.DATA_TYPE_SINT8,
            { :mesgType => FitContributor.MESG_TYPE_LAP, :units => "bpm" });

        // Session-level (IDs 10–14)
        _sDose      = _session.createField("ha_dose",      10, FitContributor.DATA_TYPE_FLOAT,
            { :mesgType => FitContributor.MESG_TYPE_SESSION });
        _sInZoneSec = _session.createField("in_zone_sec",  11, FitContributor.DATA_TYPE_UINT16,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "s" });
        _sDrift     = _session.createField("hr_drift",     12, FitContributor.DATA_TYPE_FLOAT,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "bpm/min" });
        _sModality  = _session.createField("modality",     13, FitContributor.DATA_TYPE_UINT8,
            { :mesgType => FitContributor.MESG_TYPE_SESSION });
        _sFluidMl   = _session.createField("fluid_loss_ml",14, FitContributor.DATA_TYPE_UINT16,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "mL" });
        _sAcclPct   = _session.createField("accl_pct",     15, FitContributor.DATA_TYPE_FLOAT,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "%" });

        _session.start();
        _sModality.setData(modality);
    }

    // Per-second record write (called during HEAT and REST).
    function onSecond(inZone, pctHrMax) {
        if (_fInZone   != null) { _fInZone.setData(inZone ? 1 : 0); }
        if (_fPctHrMax != null) { _fPctHrMax.setData(pctHrMax); }
    }

    // Write lap fields then close the current FIT lap.
    // All params are nullable — only non-null values are written.
    // Call this for both HEAT laps (avgHr/maxHr/dose/drift) and REST laps
    // (recovery only). The FIT lap record is closed by session.addLap().
    function addLap(avgHr, maxHr, dose, drift, recovery) {
        if (_session == null) { return; }
        if (avgHr    != null && _lHrAvg    != null) { _lHrAvg.setData(avgHr); }
        if (maxHr    != null && _lHrMax    != null) { _lHrMax.setData(maxHr); }
        if (dose     != null && _lDose     != null) { _lDose.setData(dose.toFloat()); }
        if (drift    != null && _lDrift    != null) { _lDrift.setData(drift); }
        if (recovery != null && _lRecovery != null) { _lRecovery.setData(recovery); }
        _session.addLap();
    }

    function finishAndSave(dose, inZoneSec, driftBpmMin, fluidMl, acclPct) {
        if (_session == null) { return; }
        if (_sDose      != null) { _sDose.setData(dose); }
        if (_sInZoneSec != null) { _sInZoneSec.setData(inZoneSec); }
        if (_sDrift     != null) { _sDrift.setData(driftBpmMin); }
        if (_sFluidMl   != null && fluidMl  != null) { _sFluidMl.setData(fluidMl); }
        if (_sAcclPct   != null && acclPct  != null) { _sAcclPct.setData(acclPct.toFloat()); }
        _session.stop();
        _session.save();
        _session = null;
    }

    function discard() {
        if (_session != null) { _session.discard(); _session = null; }
    }

    function isRecording() {
        return _session != null && _session.isRecording();
    }
}
