using Toybox.WatchUi;
using Toybox.Application.Storage;

// ---------------------------------------------------------------------------
// HeatAccDelegate: maps the fr955's physical buttons to session control.
//
// On the fr955:
//   START/STOP (top right)  → onSelect()
//   LAP/BACK   (bottom right) → onBack()
//
// SELECT (START/STOP):
//   IDLE      → startSession
//   HEAT/REST → pauseSession (open stop menu)
//
// BACK/LAP:
//   HEAT/REST → markLap (toggle HEAT ↔ REST)
//   IDLE      → return false (allow normal app exit)
//
// UP / DOWN (left side):
//   IDLE only → toggle modality (dry ↔ steam)
//
// After saving, all post-session pages are reached via PostSessionDelegate.
// ---------------------------------------------------------------------------
class HeatAccDelegate extends WatchUi.BehaviorDelegate {

    private var _view;

    function initialize(view) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    // START/STOP: start from idle, open pause menu during session.
    function onSelect() {
        var state = _view.getState();
        if (state == Config.STATE_IDLE) {
            _view.startSession();
        } else if (state == Config.STATE_HEAT || state == Config.STATE_REST) {
            _view.pauseSession();
        }
        return true;
    }

    // BehaviorDelegate routes the UP key to onPreviousPage() and the DOWN key
    // to onNextPage() before onKey() is called, so we override those directly.
    function onNextPage() {
        if (_view.getState() == Config.STATE_IDLE) {
            var next = (_view.modality() == Config.MODALITY_STEAM)
                ? Config.MODALITY_DRY : Config.MODALITY_STEAM;
            _view.setModality(next);
            WatchUi.requestUpdate();
            return true;
        }
        return false;
    }

    function onPreviousPage() {
        if (_view.getState() == Config.STATE_IDLE) {
            var next = (_view.modality() == Config.MODALITY_STEAM)
                ? Config.MODALITY_DRY : Config.MODALITY_STEAM;
            _view.setModality(next);
            WatchUi.requestUpdate();
            return true;
        }
        return false;
    }

    // Block all touch input — BehaviorDelegate maps tap/swipe to onSelect/onNextPage/
    // onPreviousPage, so consuming here prevents accidental touch-driven navigation.
    function onTap(evt)   { return true; }
    function onHold(evt)  { return true; }
    function onSwipe(evt) { return true; }

    // MENU (long-press UP on fr955): open Options menu when idle.
    function onMenu() {
        if (_view.getState() != Config.STATE_IDLE) { return false; }
        WatchUi.pushView(new IdleMenu(_view), new IdleMenuDelegate(_view), WatchUi.SLIDE_UP);
        return true;
    }

    // LAP/BACK: mark lap during session, allow exit from idle.
    function onBack() {
        var state = _view.getState();
        if (state == Config.STATE_HEAT || state == Config.STATE_REST) {
            _view.markLap();
            return true;
        }
        return false;
    }
}

// ---------------------------------------------------------------------------
// IdleMenu: long-press OPTIONS menu shown from IDLE screen.
// ---------------------------------------------------------------------------
class IdleMenu extends WatchUi.Menu2 {
    function initialize(view) {
        Menu2.initialize({ :title => WatchUi.loadResource(Rez.Strings.MenuOptions) });
        addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.MenuSuggestion), null, :suggestion, null));
        addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.MenuCustom), null, :custom, null));
        addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.MenuRaceDate), null, :race_date, null));
        var isRunDown = Readiness.getManualLow();
        addItem(new WatchUi.ToggleMenuItem(
            WatchUi.loadResource(Rez.Strings.MenuRunDown), null, :rundown, isRunDown, null));
        addItem(new WatchUi.ToggleMenuItem(
            WatchUi.loadResource(Rez.Strings.MenuSilent), null, :silent, view.isSilent(), null));
        if (view.armedWorkout() != null) {
            addItem(new WatchUi.MenuItem(
                WatchUi.loadResource(Rez.Strings.MenuCancelWorkout), null, :cancel, null));
        }
    }
}

class IdleMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _view;
    function initialize(view) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onTap(evt)   { return true; }
    function onHold(evt)  { return true; }
    function onSwipe(evt) { return true; }

    function onSelect(item) {
        // Do NOT pop the menu before navigating. Keep it in the stack so that
        // pressing BACK in any sub-view returns here rather than jumping to idle.
        // "Done" actions (arm workout, save race date) use switchToView to jump
        // all the way back to the idle screen in one step.
        var id = item.getId();
        if (id == :suggestion) {
            pushSuggestionChooser();
        } else if (id == :custom) {
            WatchUi.switchToView(new CustomListMenu(), new CustomListDelegate(_view), WatchUi.SLIDE_LEFT);
        } else if (id == :race_date) {
            WatchUi.switchToView(new RaceDateView(_view), new RaceDateDelegate(_view), WatchUi.SLIDE_LEFT);
        } else if (id == :rundown) {
            // ToggleMenuItem handles its own visual state; we just persist the value.
            Readiness.setManualLow(!Readiness.getManualLow());
        } else if (id == :silent) {
            var val = !_view.isSilent();
            _view.setSilent(val);
            Storage.setValue(Config.STORAGE_KEY_SILENT, val);
        } else if (id == :cancel) {
            _view.cancelWorkout();
            WatchUi.popView(WatchUi.SLIDE_DOWN);  // close menu, return to idle
        }
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    // Build and push the suggestion chooser (or direct to the only available suggestion).
    // All transitions use switchToView so the stack stays at depth 2 (IdleMenu replaced).
    // That means armWorkout + a single popView always returns cleanly to idle.
    // Back-navigation is handled by rebuilding the previous screen via switchToView.
    private function pushSuggestionChooser() {
        var readiness = Readiness.assess();
        var modality  = _view.modality();
        var daysToRace = daysToRaceNum();

        var progWorkout = WorkoutSuggester.suggestProgression(modality, readiness);
        var raceWorkout = (daysToRace != null && daysToRace > 0 && daysToRace <= Config.RACE_WINDOW_DAYS)
            ? WorkoutSuggester.suggestRace(modality, readiness, daysToRace) : null;

        if (raceWorkout != null && progWorkout != null) {
            var menu = new WatchUi.Menu2({ :title => "Suggestion" });
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource(Rez.Strings.SuggestionProgression), null, :prog, null));
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource(Rez.Strings.SuggestionRace) + " · " + daysToRace + "d",
                null, :race, null));
            WatchUi.switchToView(menu,
                new SuggestionChooserDelegate(_view, progWorkout, raceWorkout, daysToRace),
                WatchUi.SLIDE_LEFT);
        } else if (raceWorkout != null) {
            WatchUi.switchToView(new SuggestionView(raceWorkout),
                new SuggestionDelegate(raceWorkout, _view, null, null, null, false),
                WatchUi.SLIDE_LEFT);
        } else if (progWorkout != null) {
            WatchUi.switchToView(new SuggestionView(progWorkout),
                new SuggestionDelegate(progWorkout, _view, null, null, null, false),
                WatchUi.SLIDE_LEFT);
        } else {
            WatchUi.switchToView(new RestDayView(readiness[:reason]),
                new RestDayDelegate(_view), WatchUi.SLIDE_LEFT);
        }
    }

    private function daysToRaceNum() {
        var rd = Storage.getValue("race_date_epoch");
        if (rd == null) { return null; }
        var diff = (rd - TrendStore.nowEpoch()) / 86400;
        return (diff < 0) ? null : diff;
    }
}

// Chooser between progression and race suggestions.
class SuggestionChooserDelegate extends WatchUi.Menu2InputDelegate {
    private var _view;
    private var _prog;
    private var _race;
    private var _daysToRace;
    function initialize(view, prog, race, daysToRace) {
        Menu2InputDelegate.initialize();
        _view       = view;
        _prog       = prog;
        _race       = race;
        _daysToRace = daysToRace;
    }
    function onTap(evt)   { return true; }
    function onHold(evt)  { return true; }
    function onSwipe(evt) { return true; }
    function onSelect(item) {
        var workout = (item.getId() == :race) ? _race : _prog;
        // Pass the chooser context so SuggestionDelegate can rebuild this screen on BACK.
        WatchUi.switchToView(new SuggestionView(workout),
            new SuggestionDelegate(workout, _view, _prog, _race, _daysToRace, false),
            WatchUi.SLIDE_LEFT);
    }
    function onBack() {
        // Rebuild IdleMenu — stack stays at depth 2 so popView from IdleMenu returns to idle.
        WatchUi.switchToView(new IdleMenu(_view), new IdleMenuDelegate(_view),
            WatchUi.SLIDE_RIGHT);
    }
}
