using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Application.Storage;

// ---------------------------------------------------------------------------
// RaceDateMenu: Menu2 entry point for race-date management.
// Shows a dynamic title ("Race in Nd" or "Set race date") and offers
// Set/Change and Clear items depending on whether a date is saved.
// ---------------------------------------------------------------------------
class RaceDateMenu extends WatchUi.Menu2 {
    function initialize(view) {
        var saved = Storage.getValue(Config.KEY_RACE_DATE);
        var days  = null;
        if (saved != null) {
            var d = (saved - TrendStore.nowEpoch()) / 86400;
            if (d > 0) { days = d; }
        }

        var title = (days != null)
            ? "Race in " + days + "d"
            : WatchUi.loadResource(Rez.Strings.MenuRaceDate);
        Menu2.initialize({ :title => title });

        if (days != null) {
            addItem(new WatchUi.MenuItem(
                WatchUi.loadResource(Rez.Strings.RaceChange), null, :change, null));
            addItem(new WatchUi.MenuItem(
                WatchUi.loadResource(Rez.Strings.RaceClear), null, :clear, null));
        } else {
            addItem(new WatchUi.MenuItem(
                WatchUi.loadResource(Rez.Strings.RaceSet), null, :change, null));
        }
    }
}

class RaceDateMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _mainView;
    function initialize(mainView) {
        Menu2InputDelegate.initialize();
        _mainView = mainView;
    }
    function onTap(evt)   { return true; }
    function onHold(evt)  { return true; }
    function onSwipe(evt) { return true; }

    function onSelect(item) {
        var id = item.getId();
        if (id == :change) {
            WatchUi.switchToView(new RaceDatePicker(_mainView),
                new RaceDatePickerDelegate(_mainView), WatchUi.SLIDE_LEFT);
        } else if (id == :clear) {
            Storage.deleteValue(Config.KEY_RACE_DATE);
            WatchUi.switchToView(new IdleMenu(_mainView),
                new IdleMenuDelegate(_mainView), WatchUi.SLIDE_RIGHT);
        }
    }
    function onBack() {
        WatchUi.switchToView(new IdleMenu(_mainView),
            new IdleMenuDelegate(_mainView), WatchUi.SLIDE_RIGHT);
    }
}

// ---------------------------------------------------------------------------
// RaceDatePicker: UP/DOWN picker for days-to-race (1–90).
// START saves and returns to idle. BACK cancels and returns to RaceDateMenu.
// ---------------------------------------------------------------------------
class RaceDatePicker extends WatchUi.View {

    private var _days;

    const MAX_ENTRY_DAYS = 90;

    function initialize(mainView) {
        View.initialize();
        var saved = Storage.getValue(Config.KEY_RACE_DATE);
        if (saved != null) {
            var diff = (saved - TrendStore.nowEpoch()) / 86400;
            _days = (diff > 0 && diff <= MAX_ENTRY_DAYS) ? diff : 14;
        } else {
            _days = 14;
        }
    }

    function increment() { if (_days < MAX_ENTRY_DAYS) { _days++; WatchUi.requestUpdate(); } }
    function decrement() { if (_days > 1)               { _days--; WatchUi.requestUpdate(); } }

    function save() {
        var epoch = TrendStore.nowEpoch() + _days * 86400;
        Storage.setValue(Config.KEY_RACE_DATE, epoch);
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

        // Activation note
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

        dc.drawText(cx, (h * 0.88).toNumber(), Graphics.FONT_XTINY,
            "UP/DOWN adjust · START save", Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class RaceDatePickerDelegate extends WatchUi.BehaviorDelegate {
    private var _mainView;

    function initialize(mainView) {
        BehaviorDelegate.initialize();
        _mainView = mainView;
    }

    function onTap(evt)   { return true; }
    function onHold(evt)  { return true; }
    function onSwipe(evt) { return true; }

    function onNextPage() {
        var v = WatchUi.getCurrentView()[0];
        if (v instanceof RaceDatePicker) { v.decrement(); }
        return true;
    }
    function onPreviousPage() {
        var v = WatchUi.getCurrentView()[0];
        if (v instanceof RaceDatePicker) { v.increment(); }
        return true;
    }
    function onKey(keyEvent) {
        var key = keyEvent.getKey();
        if (key == WatchUi.KEY_ENTER || key == WatchUi.KEY_START) {
            var v = WatchUi.getCurrentView()[0];
            if (v instanceof RaceDatePicker) { v.save(); }
            WatchUi.switchToView(_mainView,
                new HeatAccDelegate(_mainView), WatchUi.SLIDE_RIGHT);
            return true;
        }
        return false;
    }
    function onBack() {
        WatchUi.switchToView(new RaceDateMenu(_mainView),
            new RaceDateMenuDelegate(_mainView), WatchUi.SLIDE_RIGHT);
        return true;
    }
}
