using Toybox.WatchUi;
using Toybox.System;
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

    // Touch (fr955 has a touchscreen): top third → toggle, bottom third → toggle,
    // center third → start session. Buttons are primary; touch is a convenience add-on.
    function onTap(evt) {
        if (_view.getState() != Config.STATE_IDLE) { return false; }
        var coords = evt.getCoordinates();
        var h      = System.getDeviceSettings().screenHeight;
        var tapY   = coords[1];
        if (tapY < h / 3) {
            // Top third: toggle modality
            var next = (_view.modality() == Config.MODALITY_STEAM)
                ? Config.MODALITY_DRY : Config.MODALITY_STEAM;
            _view.setModality(next);
            WatchUi.requestUpdate();
            return true;
        } else if (tapY > h * 2 / 3) {
            // Bottom third: toggle modality
            var next = (_view.modality() == Config.MODALITY_STEAM)
                ? Config.MODALITY_DRY : Config.MODALITY_STEAM;
            _view.setModality(next);
            WatchUi.requestUpdate();
            return true;
        } else {
            // Center third: start session
            _view.startSession();
            return true;
        }
    }

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

    function onSelect(item) {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        var id = item.getId();
        if (id == :suggestion) {
            pushSuggestionChooser();
        } else if (id == :custom) {
            WatchUi.pushView(new CustomView(_view), new CustomDelegate(_view), WatchUi.SLIDE_LEFT);
        } else if (id == :race_date) {
            WatchUi.pushView(new RaceDateView(_view), new RaceDateDelegate(_view), WatchUi.SLIDE_LEFT);
        } else if (id == :cancel) {
            _view.cancelWorkout();
        }
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    // Build and push the suggestion chooser (or direct to the only available suggestion).
    private function pushSuggestionChooser() {
        var readiness = Readiness.assess();
        var modality  = _view.modality();
        var daysToRace = daysToRaceNum();

        var progWorkout = WorkoutSuggester.suggestProgression(modality, readiness);
        var raceWorkout = (daysToRace != null && daysToRace > 0 && daysToRace <= Config.RACE_WINDOW_DAYS)
            ? WorkoutSuggester.suggestRace(modality, readiness, daysToRace) : null;

        if (raceWorkout != null && progWorkout != null) {
            // Offer both; build a chooser menu
            var menu = new WatchUi.Menu2({ :title => "Suggestion" });
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource(Rez.Strings.SuggestionProgression), null, :prog, null));
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource(Rez.Strings.SuggestionRace) + " · " + daysToRace + "d",
                null, :race, null));
            WatchUi.pushView(menu,
                new SuggestionChooserDelegate(_view, progWorkout, raceWorkout),
                WatchUi.SLIDE_LEFT);
        } else if (raceWorkout != null) {
            WatchUi.pushView(new SuggestionView(raceWorkout, _view),
                new SuggestionDelegate(raceWorkout, _view), WatchUi.SLIDE_LEFT);
        } else if (progWorkout != null) {
            WatchUi.pushView(new SuggestionView(progWorkout, _view),
                new SuggestionDelegate(progWorkout, _view), WatchUi.SLIDE_LEFT);
        }
        // If both null (READINESS_REST), do nothing — stay on idle
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
    function initialize(view, prog, race) {
        Menu2InputDelegate.initialize();
        _view = view;
        _prog = prog;
        _race = race;
    }
    function onSelect(item) {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        var workout = (item.getId() == :race) ? _race : _prog;
        WatchUi.pushView(new SuggestionView(workout),
            new SuggestionDelegate(workout, _view), WatchUi.SLIDE_LEFT);
    }
    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
