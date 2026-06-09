using Toybox.SensorHistory;
using Toybox.ActivityMonitor;
using Toybox.Application.Storage;

// ---------------------------------------------------------------------------
// Readiness: reads Body Battery, Stress, and today's activity intensity to
// produce a readiness band and reason string.
//
// All sensor reads are null-safe — they routinely return null in the simulator
// and on watches that don't support the metric.
//
// Readiness only scales a suggestion DOWN, never UP.
// ---------------------------------------------------------------------------
module Readiness {

    const KEY_MANUAL_LOW = "manual_low_readiness";

    // Returns a Dictionary:
    //   { :band => Config.READINESS_*, :reason => String, :bodyBattery => Number or null }
    function assess() {
        var bb      = bodyBattery();
        var stress  = stressLevel();
        var intMin  = intensityMinutesToday();
        var manual  = Storage.getValue(KEY_MANUAL_LOW) == true;

        // Base band from Body Battery (null → neutral = TRIM)
        var band;
        var bbReason;
        if (bb == null) {
            band     = Config.READINESS_TRIM;
            bbReason = "no BB data";
        } else if (bb >= 70) {
            band     = Config.READINESS_FULL;
            bbReason = "BB " + bb;
        } else if (bb >= 40) {
            band     = Config.READINESS_TRIM;
            bbReason = "BB " + bb;
        } else if (bb >= 20) {
            band     = Config.READINESS_SHORT;
            bbReason = "BB " + bb + " low";
        } else {
            band     = Config.READINESS_REST;
            bbReason = "BB " + bb + " very low";
        }

        // Knockdowns
        var reason = bbReason;
        if (stress != null && stress >= 70) {
            band   = bandDown(band);
            reason = reason + " · high stress";
        }
        if (intMin != null && intMin > 60) {
            band   = bandDown(band);
            reason = reason + " · heavy activity";
        }
        if (manual) {
            band   = bandDown(band);
            reason = reason + " · feeling run down";
        }

        return { :band => band, :reason => reason, :bodyBattery => bb };
    }

    // Increment band toward REST, capped at REST.
    function bandDown(b) {
        return (b < Config.READINESS_REST) ? b + 1 : Config.READINESS_REST;
    }

    // Body Battery: newest sample from SensorHistory. Null-safe.
    function bodyBattery() {
        if (!(Toybox has :SensorHistory)) { return null; }
        if (!(SensorHistory has :getBodyBatteryHistory)) { return null; }
        var iter = SensorHistory.getBodyBatteryHistory(
            { :period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST });
        var sample = iter.next();
        if (sample == null || sample.data == null) { return null; }
        return sample.data;
    }

    // Stress level 0–100: newest sample. Null-safe.
    function stressLevel() {
        if (!(Toybox has :SensorHistory)) { return null; }
        if (!(SensorHistory has :getStressHistory)) { return null; }
        var iter = SensorHistory.getStressHistory(
            { :period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST });
        var sample = iter.next();
        if (sample == null || sample.data == null) { return null; }
        return sample.data;
    }

    // Today's moderate + vigorous intensity minutes from ActivityMonitor. Null-safe.
    function intensityMinutesToday() {
        if (!(Toybox has :ActivityMonitor)) { return null; }
        var info = ActivityMonitor.getInfo();
        var mod  = (info has :moderateIntensityMinutes) ? info.moderateIntensityMinutes : null;
        var vig  = (info has :vigorousIntensityMinutes) ? info.vigorousIntensityMinutes : null;
        if (mod == null && vig == null) { return null; }
        return (mod != null ? mod : 0) + (vig != null ? vig : 0);
    }
}
