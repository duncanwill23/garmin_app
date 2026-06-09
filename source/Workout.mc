// ---------------------------------------------------------------------------
// Workout data model.
// WorkoutStep: one timed block (heat / rest / cooldown).
// Workout: a named sequence of steps with metadata for the suggestion UI.
// ---------------------------------------------------------------------------

class WorkoutStep {
    var type;            // Config.STEP_HEAT / STEP_REST / STEP_COOLDOWN
    var durationSec;     // null = manual lap-driven (free mode)
    var targetHrLowPct;  // fraction of HRmax (e.g. 0.65)
    var targetHrHighPct; // fraction of HRmax (e.g. 0.80)

    function initialize(t, dur, lo, hi) {
        type            = t;
        durationSec     = dur;
        targetHrLowPct  = lo;
        targetHrHighPct = hi;
    }
}

class Workout {
    var name;              // display name
    var modality;          // Config.MODALITY_DRY / MODALITY_STEAM
    var steps;             // Array<WorkoutStep>
    var kind;              // Config.WORKOUT_PROGRESSION / WORKOUT_RACE / WORKOUT_CUSTOM
    var copyKey;           // Config.COPY_* — drives §11 explanation text
    var rationale;         // one-line hint shown on idle screen when armed
    var projectedGainPct;  // simulated leaky-integrator gain (never committed)

    function initialize(n, m, s, k, ck, rat, proj) {
        name             = n;
        modality         = m;
        steps            = s;
        kind             = k;
        copyKey          = ck;
        rationale        = rat;
        projectedGainPct = proj;
    }

    // Convenience: total heat seconds across all STEP_HEAT steps.
    function totalHeatSec() {
        if (!(steps has :size)) { return 0; }
        var t = 0;
        for (var i = 0; i < steps.size(); i++) {
            var s = steps[i];
            if (s instanceof WorkoutStep && s.type == Config.STEP_HEAT && s.durationSec != null) {
                t += s.durationSec;
            }
        }
        return t;
    }

    // Convenience: number of STEP_HEAT steps.
    function heatRounds() {
        if (!(steps has :size)) { return 0; }
        var n = 0;
        for (var i = 0; i < steps.size(); i++) {
            var s = steps[i];
            if (s instanceof WorkoutStep && s.type == Config.STEP_HEAT) { n++; }
        }
        return n;
    }
}
