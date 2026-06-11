using Toybox.Activity;

// ---------------------------------------------------------------------------
// Config: every tunable constant lives here so it can be adjusted against
// EVIDENCE_BASE.md without hunting through logic (see CLAUDE.md).
// All physiology numbers trace back to the evidence base; verify there.
// ---------------------------------------------------------------------------
module Config {

    // --- Target HR band (proxy for the adaptive thermal zone) ---
    // Research: ~65-80% HRmax, i.e. the moderate-to-vigorous band seen in
    // sauna studies (~100-140+ bpm). At/above the low edge we accrue strain.
    const TARGET_HR_LOW_PCT  = 0.65;
    const TARGET_HR_HIGH_PCT = 0.80;

    // Fallback HRmax estimate (220 - age) when zones/profile are unavailable.
    const HR_MAX_AGE_BASE = 220;
    const HR_MAX_LAST_RESORT = 185;  // if even age is unknown

    // --- Modality multipliers (applied to in-band seconds) ---
    // DRY is the reference. STEAM is EXTRAPOLATED from acute physiology
    // (Pilch 2014), NOT acclimation-outcome data. Keep conservative + labeled.
    enum {
        MODALITY_DRY   = 0,
        MODALITY_STEAM = 1
    }
    const DOSE_MULT_DRY   = 1.0;
    const DOSE_MULT_STEAM = 1.25;   // EXTRAPOLATED - do not inflate.

    // --- Session guidance (seconds) ---
    const SESSION_TARGET_SEC   = 30 * 60;  // ~30 min target / to tolerance
    const SESSION_HARD_CAP_SEC = 45 * 60;  // absolute ceiling for trained users
    const SESSION_NOVICE_CAP_SEC = 10 * 60;// novices start 5-10 min, build up

    // --- Program staging ---
    const INDUCTION_SESSIONS_PER_WEEK_MIN = 3;
    const INDUCTION_SESSIONS_PER_WEEK_MAX = 5;
    const MAINTENANCE_SESSIONS_PER_WEEK   = 3;
    const RACE_WEEK_SESSION_CAP           = 2;
    const INDUCTION_STABILIZE_DAYS        = 14; // switch to maintenance after ~10-14 d

    // --- Decay model ---
    const DECAY_PCT_PER_DAY = 0.025;            // ~2.5%/day lost without exposure
    const FINISH_HARD_HEAT_DAYS_PRE_RACE = 7;   // last hard heat work ~7 d out

    // --- Adaptation "is it working?" check window ---
    const ADAPT_CHECK_DAY_EARLY = 1;
    const ADAPT_CHECK_DAY_LATE  = 12;
    // Reference timestamp within a session at which we sample HR for the
    // day-1-vs-day-12 comparison (e.g. HR at the 10-minute mark).
    const ADAPT_REF_MARK_SEC = 10 * 60;

    // --- Hydration (informational; surfaced as prompts) ---
    const REHYDRATE_PCT_OF_LOSS = 1.50;  // 150% of measured loss; never aim 100% replacement

    // --- Recording sport ---
    // NO native sauna sport exists. TODO: verify these enums compile against the
    // installed SDK; SPORT_TRAINING + a cardio sub-sport is a reasonable home.
    const REC_SPORT     = Activity.SPORT_TRAINING;
    const REC_SUB_SPORT = Activity.SUB_SPORT_CARDIO_TRAINING;

    // --- Acclimation score model (leaky integrator) ---
    // TUNABLE starting values — see todo.txt for calibration target.
    // Starting from 0 at ~4-5 sessions/week, should reach mid-80s% over ~3 weeks.
    const ACCL_REFERENCE_DOSE   = 1800.0;  // dose units for a ~30 min full dry session
    const ACCL_GAIN_PER_SESSION = 14.0;    // max % gain at acclimation=0 with full dose

    // --- Session state machine ---
    enum {
        STATE_IDLE   = 0,
        STATE_HEAT   = 1,
        STATE_REST   = 2,
        STATE_PAUSED = 3
    }

    // --- Rest phase guidance ---
    const REST_TARGET_SEC = 3 * 60;  // suggested rest between rounds (~3 min)

    // --- Workout step types ---
    enum { STEP_HEAT=0, STEP_REST=1, STEP_COOLDOWN=2 }

    // --- Workout kinds ---
    enum { WORKOUT_PROGRESSION=0, WORKOUT_RACE=1, WORKOUT_CUSTOM=2 }

    // --- Explanation copy keys (§11) ---
    enum { COPY_CALIBRATION=0, COPY_INDUCTION_BUILD=1, COPY_INDUCTION_FULL=2,
           COPY_MAINTENANCE=3, COPY_POST_GAP=4, COPY_READINESS_TRIM=5,
           COPY_READINESS_REST=6, COPY_RACE_BUILD=7, COPY_RACE_TAPER=8,
           COPY_RACE_INSUFFICIENT=9 }

    // --- Readiness bands ---
    enum { READINESS_FULL=0, READINESS_TRIM=1, READINESS_SHORT=2, READINESS_REST=3 }

    // --- Workout defaults ---
    const PRESET_ROUNDS_DEFAULT   = 3;
    const PRESET_HEAT_MIN_DEFAULT = 12;
    const PRESET_REST_MIN_DEFAULT = 3;
    const CALIBRATION_SESSIONS    = 5;

    // --- Race periodization ---
    const RACE_WINDOW_DAYS  = 35;   // race suggestion appears within ~5 weeks
    const RACE_TAPER_DAYS   = 7;    // final week = taper
    const RACE_TARGET_ACCL  = 80.0; // % to peak at by race day

    // --- Acute HR alerts (advisory only — never block dose) ---
    const HR_HIGH_PCT      = 0.92;   // momentary spike → one-shot warning
    const HR_SUSTAINED_PCT = 0.85;   // sustained elevation threshold
    const HR_SUSTAINED_SEC = 12 * 60; // 12 continuous min above sustained threshold

    // --- Silence / vibration toggle ---
    const STORAGE_KEY_SILENT = "silentMode";

    // --- Race date storage key ---
    const KEY_RACE_DATE = "race_date_epoch";

    // --- Modality accent colors (IDLE screen carousel) ---
    // Sauna (dry) — warm
    const COLOR_DRY_PRIMARY   = 0xF2A623;  // amber
    const COLOR_DRY_SECONDARY = 0xE85D24;  // orange
    // Steam (humid) — cool
    const COLOR_STEAM_PRIMARY   = 0x5AA9E6;  // blue
    const COLOR_STEAM_SECONDARY = 0x378ADD;  // deeper blue
}
