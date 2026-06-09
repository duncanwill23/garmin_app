using Toybox.WatchUi;

// ---------------------------------------------------------------------------
// Stop menu: shown when the user pauses a session (stop button or BACK).
// Built with WatchUi.Menu2 so it matches native Garmin menus.
//
// Resume → pop menu, return to paused phase.
// Save   → write FIT data, push SummaryView.
// Discard→ drop the FIT file, return to IDLE.
// BACK   → treated as Resume.
// ---------------------------------------------------------------------------
class StopMenu extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({ :title => Rez.Strings.MenuPaused });
        addItem(new WatchUi.MenuItem(Rez.Strings.MenuResume,  null, :resume,  null));
        addItem(new WatchUi.MenuItem(Rez.Strings.MenuSave,    null, :save,    null));
        addItem(new WatchUi.MenuItem(Rez.Strings.MenuDiscard, null, :discard, null));
    }
}

class StopMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _view;

    function initialize(view) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item) {
        var id = item.getId();
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        if (id == :resume)       { _view.resumeSession();  }
        else if (id == :save)    { _view.saveSession();    }
        else if (id == :discard) { _view.discardSession(); }
    }

    // Back from the menu = Resume (same as native Garmin convention).
    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        _view.resumeSession();
    }
}
