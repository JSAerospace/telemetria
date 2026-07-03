// --- GROUND TRACKING CAMERA SYSTEM (SURFACE-TO-AIR) ---
// Designed for stationary surface trackers to follow rockets/boosters

CLEARSCREEN.
PRINT "--- GROUND STATION: TRACKING CAMERA ---".

// --- 1. HARDWARE AUTO-SETUP ---
FUNCTION SetupCamera {
    HUDTEXT("INITIALIZING GROUND TRACKER HARDWARE...", 5, 2, 30, GREEN, FALSE).
    
    // Auto-extend everything for reliable comms/pointing
    FOR p IN SHIP:PARTS {
        IF p:HASMODULE("ModuleDeployableAntenna") {
            p:GETMODULE("ModuleDeployableAntenna"):DOEVENT("extend antenna").
        }
    }
    WAIT 1.0.
}

SetupCamera().

// --- 2. TARGET DETECTION & GUI ---
LOCAL trackingExit IS FALSE.
LOCAL trackingTarget IS 0.
LOCAL targetName IS "NONE".

LOCAL gStation IS GUI(220).
SET gStation:X TO 400. SET gStation:Y TO 250.
gStation:ADDLABEL("<b>GROUND TRACKING STATION</b>").
LOCAL lblTarget IS gStation:ADDLABEL("Target: NONE").
LOCAL btnRocket IS gStation:ADDBUTTON("TRACK MISSION ROCKET").
LOCAL btnBooster IS gStation:ADDBUTTON("TRACK ST1 BOOSTER").
LOCAL btnActive IS gStation:ADDBUTTON("TRACK ACTIVE TARGET").
LOCAL btnStop IS gStation:ADDBUTTON("STOP & RELEASE").

FUNCTION SeekTarget {
    PARAMETER namePart.
    LIST TARGETS IN tList.
    LOCAL found IS FALSE.
    FOR t IN tList {
        IF t:NAME:TOUPPER:CONTAINS(namePart:TOUPPER) {
            SET trackingTarget TO t.
            SET targetName TO t:NAME.
            SET found TO TRUE.
            BREAK.
        }
    }
    IF NOT found { HUDTEXT("TARGET '" + namePart + "' NOT FOUND IN RANGE", 3, 2, 25, RED, FALSE). }
}

SET btnRocket:ONCLICK TO { SeekTarget("Astro"). }. // Assuming "Astro" in ship names
SET btnBooster:ONCLICK TO { SeekTarget("Booster"). }.
SET btnActive:ONCLICK TO { 
    IF HASTARGET { SET trackingTarget TO TARGET. SET targetName TO TARGET:NAME. }
    ELSE { HUDTEXT("NO KSP TARGET SELECTED", 2, 2, 20, YELLOW, FALSE). }
}.

SET btnStop:ONCLICK TO { SET trackingExit TO TRUE. }.

gStation:SHOW().

// --- 3. TRACKING LOOP ---
UNTIL trackingExit {
    CLEARSCREEN.
    PRINT "--- GROUND STATION ACTIVE ---".
    PRINT "Current Tracking: " + targetName.
    SET lblTarget:TEXT TO "Target: " + targetName.
    
    IF trackingTarget <> 0 AND trackingTarget:ISTYPE("Vessel") {
        // Calculate relative vector from ground to target
        LOCAL relativePos IS trackingTarget:POSITION - SHIP:POSITION.
        
        // Point the tracker directly at the vessel
        LOCK STEERING TO LOOKDIRUP(relativePos, UP:VECTOR).
        
        PRINT "Range: " + ROUND(relativePos:MAG / 1000, 1) + " km".
        PRINT "Altitude: " + ROUND(trackingTarget:ALTITUDE / 1000, 1) + " km".
    } ELSE {
        UNLOCK STEERING.
        SAS ON.
        PRINT "Status: PARKED (Waiting for Target)".
    }
    
    WAIT 0.05. // Smooth tracking (20Hz)
}

gStation:HIDE(). gStation:DISPOSE().
UNLOCK STEERING.
PRINT "Ground Station Deactivated.".
