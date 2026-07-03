    // --- TRACKING CAMERA EXPANSION ---
// Provides full hardware expansion and object tracking

CLEARSCREEN.
PRINT "--- PAYLOAD EXPANSION: TRACKING CAMERA ---".

// --- 1. HARDWARE DEPLOYMENT ---
FUNCTION ExpandHardware {
    HUDTEXT("EXPANDING TRACKING CAMERA HARDWARE...", 5, 2, 30, CYAN, FALSE).
    
    // Antennas
    FOR p IN SHIP:PARTS {
        IF p:HASMODULE("ModuleDeployableAntenna") {
            p:GETMODULE("ModuleDeployableAntenna"):DOEVENT("extend antenna").
        }
    }
    
    // Fairings / Covers (Action Group 5 is usually for secondary deployment)
    AG5 ON.
    
    // Robotics (Unfolding)
    FOR p IN SHIP:PARTS {
        IF p:TAG:TOUPPER:CONTAINS("CAMERA") OR p:TAG:TOUPPER:CONTAINS("UNFOLD") {
            FOR mName IN p:MODULES {
                LOCAL m IS p:GETMODULE(mName).
                IF m:HASEVENT("extend") { m:DOEVENT("extend"). }
                IF m:HASEVENT("deploy") { m:DOEVENT("deploy"). }
            }
        }
    }
    
    WAIT 2.0.
    PRINT "Hardware Expansion Complete.".
}

ExpandHardware().

// --- 2. TRACKING SYSTEM ---
LOCAL trackingExit IS FALSE.
LOCAL trackingTarget IS 0.
LOCAL targetName IS "NONE".

LOCAL gCam IS GUI(200).
SET gCam:X TO 300. SET gCam:Y TO 200.
gCam:ADDLABEL("<b>CAMERA TRACKING CONTROL</b>").
LOCAL lblTarget IS gCam:ADDLABEL("Target: NONE").
LOCAL btnBooster IS gCam:ADDBUTTON("TRACK BOOSTER").
LOCAL btnBarge IS gCam:ADDBUTTON("TRACK BARGE").
LOCAL btnManual IS gCam:ADDBUTTON("TRACK ACTIVE TARGET").
LOCAL btnStop IS gCam:ADDBUTTON("EXIT TRACKING").

SET btnBooster:ONCLICK TO { 
    LIST TARGETS IN tList.
    FOR t IN tList { IF t:NAME:TOUPPER:CONTAINS("BOOSTER") { SET trackingTarget TO t. SET targetName TO t:NAME. } }
    HIDETARGETS().
}.

SET btnBarge:ONCLICK TO { 
    LIST TARGETS IN tList.
    FOR t IN tList { IF t:NAME:TOUPPER:CONTAINS("BARGE") OR t:NAME:TOUPPER:CONTAINS("SHIP") { SET trackingTarget TO t. SET targetName TO t:NAME. } }
    HIDETARGETS().
}.

SET btnManual:ONCLICK TO { 
    IF HASTARGET { SET trackingTarget TO TARGET. SET targetName TO TARGET:NAME. }
    ELSE { HUDTEXT("NO ACTIVE TARGET SELECTED", 2, 2, 20, RED, FALSE). }
}.

SET btnStop:ONCLICK TO { SET trackingExit TO TRUE. }.

gCam:SHOW().

UNTIL trackingExit {
    CLEARSCREEN.
    PRINT "--- CAMERA TRACKING ACTIVE ---".
    PRINT "Current Target: " + targetName.
    SET lblTarget:TEXT TO "Target: " + targetName.
    
    IF trackingTarget <> 0 AND trackingTarget:ISTYPE("Vessel") {
        LOCK STEERING TO LOOKDIRUP(trackingTarget:POSITION - SHIP:POSITION, SHIP:NORTH:VECTOR).
        PRINT "Distance: " + ROUND(trackingTarget:DISTANCE / 1000, 1) + " km".
    } ELSE {
        UNLOCK STEERING.
        PRINT "Waiting for target selection...".
    }
    
    // TELEMETRY KEEP-ALIVE
    IF DEFINED logTelemetry { logTelemetry(SHIP:STATUS). }
    
    WAIT 0.1.
}

gCam:HIDE(). gCam:DISPOSE().
UNLOCK STEERING.
PRINT "Camera Tracking Terminated.".
