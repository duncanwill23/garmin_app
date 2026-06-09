using Toybox.Application.Storage;

// ---------------------------------------------------------------------------
// WorkoutSuggester: builds Workout objects from program state + readiness.
//
// suggestProgression() — standard induction / maintenance ladder.
// suggestRace()        — race-phase build or taper.
// simulateGain()       — leaky-integrator preview; never commits to Storage.
// buildExplanation()   — human-readable copy for SuggestionView screen 2.
// ---------------------------------------------------------------------------
module WorkoutSuggester {

    // Progression rungs (ordered easy → hard; used as integer indices)
    const RUNG_CALIBRATION = 0;
    const RUNG_BUILD       = 1;
    const RUNG_FULL        = 2;
    const RUNG_MAINTENANCE = 3;

    // Returns a Workout, or null if band == READINESS_REST.
    function suggestProgression(modality, readiness) {
        if (readiness[:band] == Config.READINESS_REST) { return null; }

        var n    = TrendStore.sessionCount();
        var rung = progressionRung(n);
        var days = TrendStore.daysSinceLastNum();

        // Gap knockdown (> 3 days without a session)
        if (days > 3 && rung > RUNG_CALIBRATION) {
            rung = rung - 1;
        }

        // Readiness knockdowns
        if (readiness[:band] == Config.READINESS_TRIM && rung > RUNG_CALIBRATION) {
            rung = rung - 1;
        } else if (readiness[:band] == Config.READINESS_SHORT) {
            rung = (rung > RUNG_BUILD) ? rung - 2 : RUNG_CALIBRATION;
        }
        if (rung < RUNG_CALIBRATION) { rung = RUNG_CALIBRATION; }

        return buildProgressionWorkout(modality, rung, readiness, n);
    }

    // Returns a Workout tuned for race periodization, or null if READINESS_REST.
    function suggestRace(modality, readiness, daysToRace) {
        if (readiness[:band] == Config.READINESS_REST) { return null; }

        var isTaper = (daysToRace <= Config.RACE_TAPER_DAYS);
        var steps;
        var copyKey;
        var name;
        var rationale;

        if (isTaper) {
            steps    = makeSets(1, 8 * 60, 3 * 60, modality);
            copyKey  = Config.COPY_RACE_TAPER;
            name     = "Race Taper";
            rationale = "1 x 8 min — maintain without fatigue";
        } else {
            steps    = makeSets(3, 12 * 60, 3 * 60, modality);
            copyKey  = Config.COPY_RACE_BUILD;
            name     = "Race Build";
            rationale = "3 x 12 min — peak acclimation";
        }

        // Readiness trim applies even in race phase
        if (readiness[:band] == Config.READINESS_TRIM && !isTaper) {
            steps = makeSets(2, 10 * 60, 3 * 60, modality);
        } else if (readiness[:band] == Config.READINESS_SHORT) {
            steps = makeSets(1, 8 * 60, 3 * 60, modality);
        }

        var dose = estimateDose(steps, modality);
        var proj = simulateGain(dose);

        // Insufficient acclimation flag
        if (TrendStore.currentAcclimation(TrendStore.nowEpoch()) < 40.0 && daysToRace < 14) {
            copyKey  = Config.COPY_RACE_INSUFFICIENT;
            rationale = rationale + " · limited time to build";
        }

        return new Workout(name, modality, steps,
            Config.WORKOUT_RACE, copyKey, rationale, proj);
    }

    // Preview gain without committing to Storage. Returns the gain delta (not new total).
    function simulateGain(dose) {
        var decayed  = TrendStore.currentAcclimation(TrendStore.nowEpoch());
        var normDose = dose.toFloat() / Config.ACCL_REFERENCE_DOSE;
        var gain     = Config.ACCL_GAIN_PER_SESSION * normDose * (1.0 - decayed / 100.0);
        var newValue = decayed + gain;
        if (newValue > 100.0) { newValue = 100.0; }
        return newValue - decayed;
    }

    // Returns an explanation String for SuggestionView screen 2.
    function buildExplanation(workout) {
        var rounds  = workout.heatRounds();
        var heatSec = 0;
        var restSec = 3 * 60;
        if (workout.steps has :size) {
            for (var i = 0; i < workout.steps.size(); i++) {
                var s = workout.steps[i];
                if (s instanceof WorkoutStep &&
                    s.type == Config.STEP_HEAT && s.durationSec != null) {
                    heatSec = s.durationSec;
                    break;
                }
            }
            for (var i = 0; i < workout.steps.size(); i++) {
                var s = workout.steps[i];
                if (s instanceof WorkoutStep && s.type == Config.STEP_REST && s.durationSec != null) {
                    restSec = s.durationSec;
                    break;
                }
            }
        }
        var heatMin  = heatSec / 60;
        var totalSec = rounds * heatSec + (rounds > 1 ? (rounds - 1) * restSec : 0);
        var totalMin = totalSec / 60;
        var loHr     = (Config.TARGET_HR_LOW_PCT  * 100.0).toNumber();
        var hiHr     = (Config.TARGET_HR_HIGH_PCT * 100.0).toNumber();
        var days     = TrendStore.daysSinceLastNum();
        var decayPct = (days * Config.DECAY_PCT_PER_DAY * 100.0).toNumber();

        var ck = workout.copyKey;
        if (ck == Config.COPY_CALIBRATION) {
            return "Sessions 1-5 establish your baseline.\n" +
                   rounds + " x " + heatMin + " min heat · 3 min rest.\n" +
                   "Target: " + loHr + "-" + hiHr + "% HRmax.\n" +
                   "Light exposure lets your body adapt safely.";
        } else if (ck == Config.COPY_INDUCTION_BUILD) {
            return "Early induction: building heat tolerance.\n" +
                   rounds + " x " + heatMin + " min heat · 3 min rest.\n" +
                   "~" + totalMin + " min total · " + loHr + "-" + hiHr + "% HRmax.";
        } else if (ck == Config.COPY_INDUCTION_FULL) {
            return "Full induction dose for rapid adaptation.\n" +
                   rounds + " x " + heatMin + " min heat · 3 min rest.\n" +
                   "~" + totalMin + " min total · " + loHr + "-" + hiHr + "% HRmax.";
        } else if (ck == Config.COPY_MAINTENANCE) {
            return "Maintenance phase: hold your adaptation.\n" +
                   rounds + " x " + heatMin + " min heat · 3 min rest.\n" +
                   "3 sessions/week keeps acclimation stable.";
        } else if (ck == Config.COPY_POST_GAP) {
            return "Gap detected — easing back in.\n" +
                   "~" + decayPct + "% lost · " + days + " days since last session.\n" +
                   rounds + " x " + heatMin + " min heat · " + loHr + "-" + hiHr + "% HRmax.";
        } else if (ck == Config.COPY_READINESS_TRIM) {
            return "Readiness is lower today — dose trimmed.\n" +
                   rounds + " x " + heatMin + " min heat.\n" +
                   "Still earns adaptation; just less load.";
        } else if (ck == Config.COPY_READINESS_REST) {
            return "Rest recommended today.\n" +
                   "Body Battery or stress is elevated.\n" +
                   "Recover first; adaptation holds for ~3 days.";
        } else if (ck == Config.COPY_RACE_BUILD) {
            return "Race-phase build: peaking acclimation.\n" +
                   rounds + " x " + heatMin + " min heat.\n" +
                   "Finish heavy heat work ~7 days before race.";
        } else if (ck == Config.COPY_RACE_TAPER) {
            return "Race week taper: maintain without fatigue.\n" +
                   "1 x " + heatMin + " min — light exposure only.\n" +
                   "No new heat load in the final week.";
        } else if (ck == Config.COPY_RACE_INSUFFICIENT) {
            return "Limited time to build full acclimation.\n" +
                   "Even partial adaptation helps performance.\n" +
                   "Consistent sessions now are the priority.";
        }
        return workout.rationale;
    }

    // --- Private helpers ---

    function progressionRung(n) {
        if (n < Config.CALIBRATION_SESSIONS) { return RUNG_CALIBRATION; }
        if (TrendStore.inMaintenancePhase())  { return RUNG_MAINTENANCE; }
        if (n < 8)                            { return RUNG_BUILD; }
        return RUNG_FULL;
    }

    function buildProgressionWorkout(modality, rung, readiness, sessionCount) {
        var steps;
        var copyKey;
        var name;
        var rationale;
        var days = TrendStore.daysSinceLastNum();

        if (rung == RUNG_CALIBRATION) {
            steps    = makeSets(2, 8 * 60, 3 * 60, modality);
            copyKey  = Config.COPY_CALIBRATION;
            name     = "Calibration";
            rationale = "2 x 8 min — baseline (" + (sessionCount + 1) + "/5)";
        } else if (rung == RUNG_BUILD) {
            steps    = makeSets(2, 10 * 60, 3 * 60, modality);
            copyKey  = Config.COPY_INDUCTION_BUILD;
            name     = "Induction";
            rationale = "2 x 10 min — early induction";
        } else if (rung == RUNG_MAINTENANCE) {
            steps    = makeSets(2, 10 * 60, 3 * 60, modality);
            copyKey  = Config.COPY_MAINTENANCE;
            name     = "Maintenance";
            rationale = "2 x 10 min — maintain adaptation";
        } else {
            steps    = makeSets(3, 12 * 60, 3 * 60, modality);
            copyKey  = Config.COPY_INDUCTION_FULL;
            name     = "Full Induction";
            rationale = "3 x 12 min — full dose";
        }

        // Override copy key for gap or low readiness
        if (days > 3) {
            copyKey  = Config.COPY_POST_GAP;
            rationale = rationale + " · " + days + "d gap";
        } else if (readiness[:band] == Config.READINESS_TRIM ||
                   readiness[:band] == Config.READINESS_SHORT) {
            copyKey  = Config.COPY_READINESS_TRIM;
            rationale = rationale + " · trimmed for readiness";
        }

        var dose = estimateDose(steps, modality);
        var proj = simulateGain(dose);

        return new Workout(name, modality, steps,
            Config.WORKOUT_PROGRESSION, copyKey, rationale, proj);
    }

    // Build alternating HEAT + REST steps for N rounds (no trailing REST).
    function makeSets(rounds, heatSec, restSec, modality) {
        var arr = [];
        for (var i = 0; i < rounds; i++) {
            arr.add(new WorkoutStep(Config.STEP_HEAT, heatSec,
                Config.TARGET_HR_LOW_PCT, Config.TARGET_HR_HIGH_PCT));
            if (i < rounds - 1) {
                arr.add(new WorkoutStep(Config.STEP_REST, restSec, 0.0, 0.0));
            }
        }
        return arr;
    }

    // Estimate full-zone dose for a step list (optimistic; used for projections only).
    function estimateDose(steps, modality) {
        var mult    = (modality == Config.MODALITY_STEAM)
            ? Config.DOSE_MULT_STEAM : Config.DOSE_MULT_DRY;
        var heatSec = 0;
        if (steps has :size) {
            for (var i = 0; i < steps.size(); i++) {
                var s = steps[i];
                if (s instanceof WorkoutStep &&
                    s.type == Config.STEP_HEAT && s.durationSec != null) {
                    heatSec += s.durationSec;
                }
            }
        }
        return heatSec.toFloat() * mult;
    }
}
