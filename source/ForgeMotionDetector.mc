using Toybox.Math;
using Toybox.Lang;

//! Pure gyro detector: a full outward-and-return arm cycle counts once.
//! Uncalibrated defaults, pending real FR255 wrist validation:
//! 12 deg/s motion threshold, 18 degree strokes, >=80% return,
//! >=450 ms cycle, 120 ms quiet finish, 8 s candidate timeout.
//! No raw samples retained; cadence uses at most six completion timestamps.
class ForgeMotionDetector {

    const MOTION_RATE = 12.0;
    const MIN_ANGLE = 18.0;
    const RETURN_FRACTION = 0.8;
    const MIN_CYCLE_MS = 450;
    const QUIET_MS = 120;
    const TIMEOUT_MS = 8000;
    const MAX_SAMPLE_MS = 200;
    const STALE_MS = 10000;
    const RECENT_LIMIT = 6;

    //! Diagnostic phase: 0 idle, 1 outward, 2 return.
    hidden var _phase = 0;
    hidden var _count = 0;
    hidden var _elapsedMs = 0.0;
    hidden var _recent as Lang.Array<Lang.Float> = [];
    hidden var _axisX = 0.0;
    hidden var _axisY = 0.0;
    hidden var _axisZ = 0.0;
    hidden var _candidateStart = 0.0;
    hidden var _outwardAngle = 0.0;
    hidden var _returnAngle = 0.0;
    hidden var _quietMs = 0;

    function initialize() {
        reset();
    }

    //! Gyro values in degrees/second; deltaMs is sample interval, not timer.
    //! Returns true only on the sample that finishes a complete cycle.
    function addSample(gx, gy, gz, deltaMs) {
        if (deltaMs == null || deltaMs <= 0) {
            clearCandidate();
            return false;
        }

        _elapsedMs += deltaMs;
        if (deltaMs > MAX_SAMPLE_MS || gx == null || gy == null || gz == null) {
            clearCandidate();
            return false;
        }

        if (_phase != 0 && _elapsedMs - _candidateStart >= TIMEOUT_MS) {
            clearCandidate();
            return false;
        }

        if (_phase == 0) {
            beginCandidate(gx, gy, gz, deltaMs);
            return false;
        }

        // Freeze the candidate's initial axis so other wrist axes cannot
        // masquerade as its return. Initial direction sets positive outward.
        var rate = gx * _axisX + gy * _axisY + gz * _axisZ;
        if (_phase == 1) {
            if (rate > MOTION_RATE) {
                _outwardAngle += rate * deltaMs / 1000.0;
            } else if (rate < -MOTION_RATE) {
                if (_outwardAngle < MIN_ANGLE) {
                    clearCandidate();
                } else {
                    _phase = 2;
                    _returnAngle = -rate * deltaMs / 1000.0;
                    _quietMs = 0;
                }
            }
            return false;
        }

        if (rate < -MOTION_RATE) {
            _returnAngle += -rate * deltaMs / 1000.0;
            _quietMs = 0;
            return false;
        }

        // A new outward stroke closes the prior cycle and is also the first
        // sample of the next one, allowing continuous strokes without rest.
        if (rate > MOTION_RATE) {
            var completed = finishCandidate();
            beginCandidate(gx, gy, gz, deltaMs);
            return completed;
        }

        _quietMs += deltaMs;
        if (_quietMs >= QUIET_MS) {
            return finishCandidate();
        }
        return false;
    }

    function reset() {
        _count = 0;
        _elapsedMs = 0.0;
        _recent = [];
        clearCandidate();
    }

    function getCount() { return _count; }

    //! Current full cycles/min; unavailable before two recent completions.
    //! Freshness advances with received sample intervals, including gaps.
    function getCadence() {
        var size = _recent.size();
        if (size < 2 || _elapsedMs - _recent[size - 1] >= STALE_MS) {
            return null;
        }
        var span = _recent[size - 1] - _recent[0];
        return span > 0 ? 60000.0 * (size - 1) / span : null;
    }

    function getPhase() { return _phase; }

    hidden function beginCandidate(gx, gy, gz, deltaMs) {
        var magnitude = Math.sqrt(gx * gx + gy * gy + gz * gz);
        if (magnitude <= MOTION_RATE) { return; }
        _axisX = gx / magnitude;
        _axisY = gy / magnitude;
        _axisZ = gz / magnitude;
        _candidateStart = _elapsedMs - deltaMs;
        _outwardAngle = magnitude * deltaMs / 1000.0;
        _phase = 1;
    }

    hidden function finishCandidate() {
        var completed = _returnAngle >= MIN_ANGLE &&
            _returnAngle >= _outwardAngle * RETURN_FRACTION &&
            _elapsedMs - _candidateStart >= MIN_CYCLE_MS;
        if (completed) {
            _count += 1;
            var size = _recent.size();
            // A long pause starts a fresh cadence window; old completions
            // remain reflected in total count, but not in current frequency.
            if (size > 0 && _elapsedMs - _recent[size - 1] >= STALE_MS) {
                _recent = [];
            }
            if (_recent.size() == RECENT_LIMIT) { _recent.remove(_recent[0]); }
            _recent.add(_elapsedMs);
        }
        clearCandidate();
        return completed;
    }

    hidden function clearCandidate() {
        _phase = 0;
        _axisX = 0.0;
        _axisY = 0.0;
        _axisZ = 0.0;
        _candidateStart = 0.0;
        _outwardAngle = 0.0;
        _returnAngle = 0.0;
        _quietMs = 0;
    }
}
