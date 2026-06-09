using Toybox.Application.Storage;

// ---------------------------------------------------------------------------
// SafetyGate: safety sits IN FRONT of the dose engine (see CLAUDE.md).
// If a gate trips, scoring is reduced/blocked and the user is warned.
//
// Notes:
//  - Heat-illness red flags (dizziness, nausea, confusion, no sweating) cannot
//    be sensed; they are surfaced as a user-triggered EXIT path in the UI.
//  - Beta-blockers don't just warrant a warning: they blunt HR and INVALIDATE
//    the HR proxy. Flag such users explicitly; do not silently score them.
// ---------------------------------------------------------------------------
module SafetyGate {

    const KEY_SCREEN_DONE   = "ci_screen_done";
    const KEY_NOVICE        = "novice";
    const KEY_BETA_BLOCKER  = "beta_blocker";

    function screeningComplete() {
        return Storage.getValue(KEY_SCREEN_DONE) == true;
    }

    // Called when the user completes the one-time contraindication screen.
    function markScreeningComplete(isNovice, onBetaBlockers) {
        Storage.setValue(KEY_SCREEN_DONE, true);
        Storage.setValue(KEY_NOVICE, isNovice);
        Storage.setValue(KEY_BETA_BLOCKER, onBetaBlockers);
    }

    function isNovice() {
        return Storage.getValue(KEY_NOVICE) == true;
    }

    // If true, the HR-based dose is NOT a valid proxy -> UI must say so.
    function hrProxyInvalid() {
        return Storage.getValue(KEY_BETA_BLOCKER) == true;
    }

    // Per-session duration ceiling.
    function sessionCapSec() {
        return isNovice() ? Config.SESSION_NOVICE_CAP_SEC : Config.SESSION_HARD_CAP_SEC;
    }

    // Weekly frequency ceiling, tightened during race week.
    function weeklyCap(isRaceWeek) {
        return isRaceWeek ? Config.RACE_WEEK_SESSION_CAP
                          : Config.INDUCTION_SESSIONS_PER_WEEK_MAX;
    }

    // True once a session has hit its duration ceiling (caller should prompt exit).
    function sessionAtCap(elapsedSec) {
        return elapsedSec >= sessionCapSec();
    }
}
