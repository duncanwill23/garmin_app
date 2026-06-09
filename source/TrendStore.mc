using Toybox.Application.Storage;
using Toybox.Lang;
using Toybox.Time;
using Toybox.Math;

// ---------------------------------------------------------------------------
// TrendStore: longitudinal state persisted between sessions (Application.Storage).
// Drives staging, decay model, adaptation check, and the custom acclimation
// score (a leaky integrator — separate from Garmin's built-in metric).
//
// History is stored as two parallel Number arrays (timestamps + values) to
// stay type-safe across the Monkey C Gradual type checker.
// ---------------------------------------------------------------------------
module TrendStore {

    // --- Existing keys ---
    const KEY_PROGRAM_START   = "prog_start_epoch";
    const KEY_LAST_SESSION    = "last_session_epoch";
    const KEY_DAY1_REF_HR     = "day1_ref_hr";
    const KEY_RESTING_HR_BASE = "rhr_base";
    const KEY_WEEK_SESSIONS   = "week_sessions";

    // --- Acclimation score keys ---
    const KEY_ACCL_VALUE       = "accl_value";       // Float 0–100
    const KEY_ACCL_LAST_UPDATE = "accl_last_update"; // epoch Number
    const KEY_ACCL_HIST_T      = "accl_hist_t";      // Array of epoch Numbers
    const KEY_ACCL_HIST_V      = "accl_hist_v";      // Array of Float values
    const KEY_LAST_REF_HR      = "last_ref_hr";      // most recent refMarkHr

    function nowEpoch() {
        return Time.now().value();
    }

    function programStarted() {
        return Storage.getValue(KEY_PROGRAM_START) != null;
    }

    function startProgramIfNeeded() {
        if (!programStarted()) {
            Storage.setValue(KEY_PROGRAM_START, nowEpoch());
        }
    }

    // Record session metadata (last session time, day-1 HR ref, weekly count).
    function recordSessionEnd(refMarkHr) {
        var now = nowEpoch();
        startProgramIfNeeded();
        Storage.setValue(KEY_LAST_SESSION, now);
        if (Storage.getValue(KEY_DAY1_REF_HR) == null && refMarkHr != null) {
            Storage.setValue(KEY_DAY1_REF_HR, refMarkHr);
        }
        var c = Storage.getValue(KEY_WEEK_SESSIONS);
        Storage.setValue(KEY_WEEK_SESSIONS, (c == null ? 0 : c) + 1);
    }

    function daysSinceLast() {
        var last = Storage.getValue(KEY_LAST_SESSION);
        if (last == null) { return null; }
        return (nowEpoch() - last) / 86400;
    }

    function daysIntoProgram() {
        var start = Storage.getValue(KEY_PROGRAM_START);
        if (start == null) { return 0; }
        return (nowEpoch() - start) / 86400;
    }

    function estimatedDecayPct() {
        var d = daysSinceLast();
        if (d == null) { return 0.0; }
        var pct = d * Config.DECAY_PCT_PER_DAY;
        return pct > 1.0 ? 1.0 : pct;
    }

    // Adaptation signal: negative = HR dropped = improving. Null if no data.
    function adaptationDeltaBpm(currentRefHr) {
        var day1 = Storage.getValue(KEY_DAY1_REF_HR);
        if (day1 == null || currentRefHr == null) { return null; }
        return currentRefHr - day1;
    }

    function inMaintenancePhase() {
        return daysIntoProgram() >= Config.INDUCTION_STABILIZE_DAYS;
    }

    // -----------------------------------------------------------------------
    // Acclimation score (leaky integrator)
    // -----------------------------------------------------------------------

    // Read current acclimation, decayed to nowEpochVal. Does NOT commit.
    function currentAcclimation(nowEpochVal) {
        var value = Storage.getValue(KEY_ACCL_VALUE);
        if (value == null) { return 0.0; }
        var lastUpdate = Storage.getValue(KEY_ACCL_LAST_UPDATE);
        if (lastUpdate == null) { return value.toFloat(); }
        var days = (nowEpochVal - lastUpdate).toFloat() / 86400.0;
        if (days <= 0.0) { return value.toFloat(); }
        var decayed = value.toFloat() *
            Math.pow(1.0 - Config.DECAY_PCT_PER_DAY, days).toFloat();
        return (decayed < 0.0) ? 0.0 : decayed;
    }

    // Return the stored history timestamp array, or null.
    function getHistoryT() { return Storage.getValue(KEY_ACCL_HIST_T); }

    // Return the stored history value array, or null.
    function getHistoryV() { return Storage.getValue(KEY_ACCL_HIST_V); }

    // Last session's adaptation reference HR (for self-correction check).
    function lastRefHr() { return Storage.getValue(KEY_LAST_REF_HR); }

    // Apply decay + dose gain for a completed session. Commits to storage.
    // Returns the new acclimation value (0–100).
    function commitSession(nowEpochVal, sessionDose, refHr) {
        var decayed = currentAcclimation(nowEpochVal);

        // Dose-proportional gain with diminishing returns near ceiling.
        var normDose = sessionDose.toFloat() / Config.ACCL_REFERENCE_DOSE;
        var gain     = Config.ACCL_GAIN_PER_SESSION * normDose *
                       (1.0 - decayed / 100.0);
        var newValue = decayed + gain;
        if (newValue > 100.0) { newValue = 100.0; }
        if (newValue <   0.0) { newValue =   0.0; }

        Storage.setValue(KEY_ACCL_VALUE,       newValue);
        Storage.setValue(KEY_ACCL_LAST_UPDATE, nowEpochVal);
        if (refHr != null) { Storage.setValue(KEY_LAST_REF_HR, refHr); }

        // Append to history (two parallel Number arrays — type-safe in Monkey C).
        var rawT = Storage.getValue(KEY_ACCL_HIST_T);
        var rawV = Storage.getValue(KEY_ACCL_HIST_V);
        if (rawT == null || rawV == null) {
            Storage.setValue(KEY_ACCL_HIST_T, [nowEpochVal]);
            Storage.setValue(KEY_ACCL_HIST_V, [newValue]);
        } else if ((rawT has :add) && (rawV has :add) && (rawT has :size) && (rawT has :slice)) {
            rawT.add(nowEpochVal);
            rawV.add(newValue);
            if (rawT.size() > 90) {
                var drop = rawT.size() - 90;
                rawT = rawT.slice(drop, null);
                rawV = rawV.slice(drop, null);
            }
            Storage.setValue(KEY_ACCL_HIST_T, rawT);
            Storage.setValue(KEY_ACCL_HIST_V, rawV);
        }

        return newValue;
    }
}
