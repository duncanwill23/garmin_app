using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Application.Storage;

// ---------------------------------------------------------------------------
// RaceDateView: UP/DOWN picker for days-to-race (1–RACE_WINDOW_DAYS).
// START saves. If no race is set, shows the picker starting at 14 days.
// Stored as a future epoch: now + days * 86400.
// ---------------------------------------------------------------------------
class RaceDateView extends WatchUi.View {

    private var _mainView;
    private var _days;

    const KEY_RACE_DATE = "race_date_epoch";

    function initialize(mainView) {
        View.initialize();
        _mainView = mainView;
        // Load existing saved days-to-race, or default to 14
        var saved = Storage.getValue(KEY_RACE_DATE);
        if (saved != null) {
            var diff = (saved - TrendStore.nowEpoch()) / 86400;
            _days = (diff > 0 && diff <= MAX_ENTRY_DAYS) ? diff : 14;
        } else {
            _days = 14;
        }
    }

    const MAX_ENTRY_DAYS = 90;  // allow entry up to ~3 months; race plan activates inside RACE_WINDOW_DAYS

    function increment() { if (_days < MAX_ENTRY_DAYS) { _days++; WatchUi.requestUpdate(); } }
    function decrement() { if (_days > 1)               { _days--; WatchUi.requestUpdate(); } }

    function save() {
        var epoch = TrendStore.nowEpoch() + _days * 86400;
        Storage.setValue(KEY_RACE_DATE, epoch);
        // Navigation is handled by RaceDateDelegate (switchToView → idle)
    }

    function onUpdate(dc) {
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.08).toNumber(), Graphics.FONT_XTINY,
            "Days to Race", Graphics.TEXT_JUSTIFY_CENTER);

        // Up chevron
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        var upY = (h * 0.24).toNumber();
        dc.fillPolygon([[cx, upY - 8], [cx - 8, upY + 4], [cx + 8, upY + 4]]);

        // Days count — large
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.35).toNumber(), Graphics.FONT_NUMBER_MEDIUM,
            _days.toString(), Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.58).toNumber(), Graphics.FONT_XTINY,
            "days", Graphics.TEXT_JUSTIFY_CENTER);

        // Down chevron
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        var downY = (h * 0.70).toNumber();
        dc.fillPolygon([[cx, downY + 8], [cx - 8, downY - 4], [cx + 8, downY - 4]]);

        // Activation note: tells the user when the race suggestion will appear
        var activationNote;
        if (_days > Config.RACE_WINDOW_DAYS) {
            var daysUntilActive = _days - Config.RACE_WINDOW_DAYS;
            activationNote = "plan active in " + daysUntilActive + "d";
        } else {
            activationNote = "race plan active now";
        }
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.78).toNumber(), Graphics.FONT_XTINY,
            activationNote, Graphics.TEXT_JUSTIFY_CENTER);

        // Range note
        dc.drawText(cx, (h * 0.88).toNumber(), Graphics.FONT_XTINY,
            "1-90  ·  START to save",
            Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class RaceDateDelegate extends WatchUi.BehaviorDelegate {
    private var _mainView;

    function initialize(mainView) {
        BehaviorDelegate.initialize();
        _mainView = mainView;
    }

    function onNextPage() {
        var v = WatchUi.getCurrentView()[0];
        if (v instanceof RaceDateView) { v.decrement(); }
        return true;
    }
    function onPreviousPage() {
        var v = WatchUi.getCurrentView()[0];
        if (v instanceof RaceDateView) { v.increment(); }
        return true;
    }
    function onSelect() {
        var v = WatchUi.getCurrentView()[0];
        if (v instanceof RaceDateView) {
            v.save();
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
        return true;
    }
    function onBack() {
        WatchUi.switchToView(new IdleMenu(_mainView), new IdleMenuDelegate(_mainView),
            WatchUi.SLIDE_RIGHT);
        return true;
    }
}
