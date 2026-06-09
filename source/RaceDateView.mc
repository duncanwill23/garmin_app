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
            _days = (diff > 0 && diff <= Config.RACE_WINDOW_DAYS) ? diff : 14;
        } else {
            _days = 14;
        }
    }

    function increment() { if (_days < Config.RACE_WINDOW_DAYS) { _days++; WatchUi.requestUpdate(); } }
    function decrement() { if (_days > 1)                        { _days--; WatchUi.requestUpdate(); } }

    function save() {
        var epoch = TrendStore.nowEpoch() + _days * 86400;
        Storage.setValue(KEY_RACE_DATE, epoch);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
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

        // Range note
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.82).toNumber(), Graphics.FONT_XTINY,
            "1-" + Config.RACE_WINDOW_DAYS + "  ·  START to save",
            Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class RaceDateDelegate extends WatchUi.BehaviorDelegate {
    function initialize(mainView) {
        BehaviorDelegate.initialize();
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
        if (v instanceof RaceDateView) { v.save(); }
        return true;
    }
    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
