using Toybox.Sensor;
using Toybox.System;
using Toybox.Lang;

//! Bounded streaming adapter. Native gyro is degrees/s; accel is milli-g.
//! Status: idle/waiting/active/stale/unsupported/error/stopped.
//! Count stays null until a valid gyro triple, including stationary zero.
class ForgeMotion {
    const STALE_CALLBACK_MS = 2500;
    hidden var _detector;
    hidden var _running = false;
    hidden var _registered = false;
    hidden var _seen = false;
    hidden var _status = "idle";
    hidden var _intervalMs = 20.0;
    hidden var _lastCallback = null;
    hidden var _lastValid = null;
    hidden var _generation = 0;
    hidden var _listener = null;
    hidden var _onUpdate = null;
    hidden var _frozenCadence = null;
    hidden var _timestampsSupported = false;
    hidden var _lastSampleTime = null;
    hidden var _usingTimestamps = false;
    hidden var _accelSupported = false;
    hidden var _accelStatus = "waiting";
    hidden var _lastAccelCallback = null;

    function initialize() { _detector = new ForgeMotionDetector(); }

    function start(onUpdate) {
        stop();
        reset();
        _onUpdate = onUpdate;
        _generation += 1;
        try {
            var gyroRate = Sensor.getMaxSampleRateForSensorType(:gyroscope);
            if (gyroRate == null || gyroRate <= 0) { _status = "unsupported"; return; }
            if (gyroRate > 50) { gyroRate = 50; }
            var accelRate = 0;
            _accelSupported = false;
            _accelStatus = "unsupported";
            try {
                accelRate = Sensor.getMaxSampleRateForSensorType(:accelerometer);
                _accelSupported = accelRate != null && accelRate > 0;
                _accelStatus = _accelSupported ? "waiting" : "unsupported";
            } catch (e) {
                _accelStatus = "error";
                System.println("[FORGE-MOTION] accelerometer unavailable");
            }
            var options = { :period => 1, :synchronous => true,
                :gyroscope => { :enabled => true, :sampleRate => gyroRate } };
            if (accelRate != null && accelRate > 0) {
                if (accelRate > 50) { accelRate = 50; }
                options[:accelerometer] = { :enabled => true, :sampleRate => accelRate };
            }
            var version = System.getDeviceSettings().monkeyVersion as Lang.Array<Lang.Number>;
            _timestampsSupported = version[0] > 5 || (version[0] == 5 &&
                (version[1] > 1 || (version[1] == 1 && version[2] >= 1)));
            if (_timestampsSupported) {
                var gyroOptions = options[:gyroscope] as Lang.Dictionary;
                gyroOptions[:includeTimestamps] = true;
            }
            _intervalMs = 1000.0 / gyroRate;
            _listener = new ForgeMotionListener(self, _generation);
            _running = true;
            _status = "waiting";
            Sensor.registerSensorDataListener(_listener.method(:onData), options);
            _registered = true;
        } catch (e) {
            _running = false;
            _listener = null;
            _status = "error";
            if (_accelSupported) { _accelStatus = "error"; }
            System.println("[FORGE-MOTION] registration unavailable");
        }
    }

    function stop() {
        if (!_running && !_registered) { return; }
        _frozenCadence = getCadence();
        _accelStatus = getAccelStatus();
        _running = false;
        _generation += 1;
        if (_registered) {
            try { Sensor.unregisterSensorDataListener(); } catch (e) { System.println("[FORGE-MOTION] unregister unavailable"); }
        }
        _registered = false;
        _listener = null;
        _onUpdate = null;
        _status = "stopped";
    }

    function reset() {
        _detector.reset();
        _seen = false;
        _lastCallback = null;
        _lastSampleTime = null;
        _usingTimestamps = false;
        _lastAccelCallback = null;
        _accelStatus = "waiting";
        _lastValid = null;
        _frozenCadence = null;
        _status = _running ? "waiting" : "idle";
    }

    //! Listener generation rejects late callbacks after stop or a fresh start.
    function onSensorData(data, generation) {
        if (!_running || generation != _generation) { return; }
        var now = System.getTimer();
        updateAccelStatus(data, now);
        try {
            if (data == null || !(data has :gyroscopeData) || data.gyroscopeData == null) {
                rejectBatch(now); return;
            }
            var gyro = data.gyroscopeData;
            if (!(gyro has :x) || !(gyro has :y) || !(gyro has :z)) { rejectBatch(now); return; }
            var x = gyro.x; var y = gyro.y; var z = gyro.z;
            if (!(x instanceof Lang.Array) || !(y instanceof Lang.Array) || !(z instanceof Lang.Array)) { rejectBatch(now); return; }
            var size = x.size();
            if (size == 0 || y.size() != size || z.size() != size) { rejectBatch(now); return; }
            // Without API 5.1.1 timestamps, nominal batched sample intervals are
            // anchored to real callback gaps. Missing time breaks a candidate.
            var timestamps = null;
            if (_timestampsSupported && (gyro has :timestamp)) { timestamps = gyro.timestamp; }
            if (timestamps != null && (!(timestamps instanceof Lang.Array) || timestamps.size() != size)) { rejectBatch(now); return; }
            var useTimestamps = timestamps != null;
            if (useTimestamps != _usingTimestamps && _seen) {
                _detector.addSample(null, null, null, 201);
                _lastSampleTime = null;
            }
            _usingTimestamps = useTimestamps;
            if (!useTimestamps && _lastCallback != null) {
                var gap = now - _lastCallback - size * _intervalMs;
                if (gap > 200 || now - _lastCallback < 0) {
                    _detector.addSample(null, null, null, gap > 200 ? gap : 201);
                }
            }
            _lastCallback = now;
            for (var i = 0; i < size; i += 1) {
                var delta = _intervalMs;
                if (useTimestamps) {
                    if (!(timestamps[i] instanceof Lang.Number)) { rejectBatch(now); return; }
                    if (_lastSampleTime != null) { delta = timestamps[i] - _lastSampleTime; }
                    _lastSampleTime = timestamps[i];
                } else { _lastSampleTime = null; }
                if (!validNumber(x[i]) || !validNumber(y[i]) || !validNumber(z[i])) {
                    _detector.addSample(null, null, null, _intervalMs);
                    continue;
                }
                _detector.addSample(x[i], y[i], z[i], delta);
                _seen = true;
                _lastValid = now;
                _status = "active";
            }
            if (_onUpdate != null) { _onUpdate.invoke(); }
        } catch (e) {
            rejectBatch(now);
        }
    }

    //! Accel only reports sensor availability, never contributes to cycle count.
    hidden function updateAccelStatus(data, now) {
        if (!_accelSupported) { return; }
        _lastAccelCallback = now;
        _accelStatus = "missing";
        try {
            if (data == null || !(data has :accelerometerData) || data.accelerometerData == null) { return; }
            var accel = data.accelerometerData;
            if (!(accel has :x) || !(accel has :y) || !(accel has :z)) { return; }
            var x = accel.x; var y = accel.y; var z = accel.z;
            if (!(x instanceof Lang.Array) || !(y instanceof Lang.Array) || !(z instanceof Lang.Array)) { return; }
            var size = x.size();
            if (size == 0 || y.size() != size || z.size() != size) { return; }
            for (var i = 0; i < size; i += 1) {
                if (!validNumber(x[i]) || !validNumber(y[i]) || !validNumber(z[i])) { return; }
            }
            _accelStatus = "active";
        } catch (e) { }
    }

    function getAccelStatus() {
        if (_running && _lastAccelCallback != null) {
            var elapsed = System.getTimer() - _lastAccelCallback;
            if (elapsed < 0 || elapsed >= STALE_CALLBACK_MS) { return "stale"; }
        }
        return _accelStatus;
    }

    hidden function validNumber(value) {
        return (value instanceof Lang.Number || value instanceof Lang.Float ||
            value instanceof Lang.Long || value instanceof Lang.Double) &&
            value == value && value >= -1000000 && value <= 1000000;
    }

    hidden function rejectBatch(now) {
        _lastSampleTime = null;
        var gap = _lastCallback != null ? now - _lastCallback : 201;
        _detector.addSample(null, null, null, gap > 0 ? gap : 201);
        _lastCallback = now;
    }

    function getCount() { return _seen ? _detector.getCount() : null; }
    function getCadence() {
        if (!_running) { return _frozenCadence; }
        return getStatus().equals("stale") ? null : _detector.getCadence();
    }
    function getPhase() { return _detector.getPhase(); }
    function getStatus() {
        if (_running && _lastValid != null) {
            var elapsed = System.getTimer() - _lastValid;
            if (elapsed < 0 || elapsed >= STALE_CALLBACK_MS) { return "stale"; }
        }
        return _status;
    }
}

class ForgeMotionListener {
    hidden var _owner; hidden var _generation;
    function initialize(owner, generation) { _owner = owner; _generation = generation; }
    function onData(data as Sensor.SensorData) as Void { _owner.onSensorData(data, _generation); }
}
