using Toybox.FitContributor;
using Toybox.System;

//! Session-only fields are created only when the source metric is available.
//! Any contributor failure disables further writes for this activity; base FIT
//! recording and save continue. Release handles after save/discard.
class ForgeMotionFit {
    hidden var _countField = null;
    hidden var _averageField = null;
    hidden var _failed = false;

    function initialize() {}
    function update(session, count, average) {
        if (_failed || session == null || count == null) { return; }
        try {
            if (_countField == null) {
                _countField = session.createField("Forge Cycles", 0, FitContributor.DATA_TYPE_UINT32,
                    { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "cycles" });
            }
            _countField.setData(count);
            if (average != null) {
                if (_averageField == null) {
                    _averageField = session.createField("Forge Avg Cadence", 1, FitContributor.DATA_TYPE_FLOAT,
                        { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "cycles/min" });
                }
                _averageField.setData(average);
            }
        } catch (e) {
            _failed = true;
            System.println("[FORGE-MOTION] FIT contribution unavailable");
        }
    }
    function release() { _countField = null; _averageField = null; }
}
