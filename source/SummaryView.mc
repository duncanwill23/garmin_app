using Toybox.WatchUi;
using Toybox.Graphics;

// ---------------------------------------------------------------------------
// SummaryView: page 1 / 4 of the post-session carousel.
// Takes a SessionData object shared across all 4 pages.
// Navigation is handled by PostSessionDelegate (SessionData.mc).
// ---------------------------------------------------------------------------
class SummaryView extends WatchUi.View {

    private var _data;

    function initialize(data) {
        View.initialize();
        _data = data;
    }

    function onUpdate(dc) {
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        // "SAVED"
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.04, Graphics.FONT_XTINY,
            "SAVED", Graphics.TEXT_JUSTIFY_CENTER);

        // Large dose number
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.14, Graphics.FONT_NUMBER_MEDIUM,
            _data.dose.format("%.0f"), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.48, Graphics.FONT_XTINY,
            "dose", Graphics.TEXT_JUSTIFY_CENTER);

        // Acclimation gain this session
        var gainSign = (_data.acclGain >= 0.0) ? "+" : "";
        var gainStr  = gainSign + _data.acclGain.format("%.1f") + "% acclimation";
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.58, Graphics.FONT_XTINY,
            gainStr, Graphics.TEXT_JUSTIFY_CENTER);

        // Total acclimation
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.68, Graphics.FONT_XTINY,
            "total " + _data.acclTotal.format("%.0f") + "%  est.",
            Graphics.TEXT_JUSTIFY_CENTER);

        // In-zone time + rounds
        var inZoneMin = (_data.inZoneSec / 60).format("%.0f");
        var roundStr  = (_data.rounds == 1) ? "1 round" : (_data.rounds + " rounds");
        dc.drawText(cx, h * 0.78, Graphics.FONT_XTINY,
            inZoneMin + " min  " + roundStr, Graphics.TEXT_JUSTIFY_CENTER);

        // Page indicator
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.90, Graphics.FONT_XTINY,
            "1 / 4", Graphics.TEXT_JUSTIFY_CENTER);
    }
}
