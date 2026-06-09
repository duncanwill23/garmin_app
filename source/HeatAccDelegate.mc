using Toybox.WatchUi;
using Toybox.System;

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
