// --- CONFIGURACIÓN DE DISTANCIA DE CARGA (RSS - ROBUSTO) ---
// Copiado y adaptado de booster.ks para máxima fiabilidad
FUNCTION SetPhysicsRange {
    PARAMETER d.
    // Configuración para la nave actual
    SET SHIP:LOADDISTANCE:FLYING:UNLOAD TO d. SET SHIP:LOADDISTANCE:FLYING:LOAD TO d*0.95.
    WAIT 0.001. SET SHIP:LOADDISTANCE:FLYING:PACK TO d*0.98. SET SHIP:LOADDISTANCE:FLYING:UNPACK TO d*0.94.
    WAIT 0.01.
    SET SHIP:LOADDISTANCE:SUBORBITAL:UNLOAD TO d. SET SHIP:LOADDISTANCE:SUBORBITAL:LOAD TO d*0.95.
    WAIT 0.001. SET SHIP:LOADDISTANCE:SUBORBITAL:PACK TO d*0.98. SET SHIP:LOADDISTANCE:SUBORBITAL:UNPACK TO d*0.94.
    WAIT 0.01.
    SET SHIP:LOADDISTANCE:ORBIT:UNLOAD TO d. SET SHIP:LOADDISTANCE:ORBIT:LOAD TO d*0.95.
    WAIT 0.001. SET SHIP:LOADDISTANCE:ORBIT:PACK TO d*0.98. SET SHIP:LOADDISTANCE:ORBIT:UNPACK TO d*0.94.
    WAIT 0.01.
    SET SHIP:LOADDISTANCE:LANDED:UNLOAD TO d. SET SHIP:LOADDISTANCE:LANDED:LOAD TO d*0.95.
    WAIT 0.001. SET SHIP:LOADDISTANCE:LANDED:PACK TO d*0.98. SET SHIP:LOADDISTANCE:LANDED:UNPACK TO d*0.94.
    WAIT 0.01.
    
    // Configuración GLOBAL (KUNIVERSE) para asegurar que aplica a todo
    SET KUNIVERSE:DEFAULTLOADDISTANCE:FLYING:UNLOAD TO d.
    SET KUNIVERSE:DEFAULTLOADDISTANCE:FLYING:LOAD TO d*0.95.
    SET KUNIVERSE:DEFAULTLOADDISTANCE:FLYING:PACK TO d*0.98.
    SET KUNIVERSE:DEFAULTLOADDISTANCE:FLYING:UNPACK TO d*0.94.
    
    SET KUNIVERSE:DEFAULTLOADDISTANCE:SUBORBITAL:UNLOAD TO d.
    SET KUNIVERSE:DEFAULTLOADDISTANCE:SUBORBITAL:LOAD TO d*0.95.
    SET KUNIVERSE:DEFAULTLOADDISTANCE:SUBORBITAL:PACK TO d*0.98.
    SET KUNIVERSE:DEFAULTLOADDISTANCE:SUBORBITAL:UNPACK TO d*0.94.
    
    SET KUNIVERSE:DEFAULTLOADDISTANCE:ORBIT:UNLOAD TO d.
    SET KUNIVERSE:DEFAULTLOADDISTANCE:ORBIT:LOAD TO d*0.95.
    SET KUNIVERSE:DEFAULTLOADDISTANCE:ORBIT:PACK TO d*0.98.
    SET KUNIVERSE:DEFAULTLOADDISTANCE:ORBIT:UNPACK TO d*0.94.
    
    WAIT 0.1.
    HUDTEXT("SISTEMA DE CARGA RSS: ACTIVADO (" + (d/1000) + "km)", 5, 2, 30, GREEN, FALSE).
}
SetPhysicsRange(2500000).

// --- STEERING STABILIZATION (PROFESSIONAL CONTROL) ---
SET STEERINGMANAGER:MAXSTOPPINGTIME TO 3.0. // Damping increase (default 2.0)
SET STEERINGMANAGER:PITCHPID:KD TO 1.5.     // Derivative gain for stability
SET STEERINGMANAGER:YAWPID:KD TO 1.5.
SET STEERINGMANAGER:ROLLPID:KD TO 1.5.
SET STEERINGMANAGER:PITCHPID:KP TO 0.6.     // Slightly lower proportional for smoothness
SET STEERINGMANAGER:YAWPID:KP TO 0.6.

CLEARSCREEN.
PRINT "--- BOOSTER RECOVERY SYSTEM (UPDATED) ---".

GLOBAL abort_water_target IS LATLNG(5.260, -62.590).
GLOBAL abort_mode_active IS FALSE.

ON ABORT {
    SET abort_mode_active TO TRUE.
    HUDTEXT("!!! ABORT ACTIVADO - AMARIZAJE DE EMERGENCIA !!!", 10, 2, 40, RED, TRUE).
    SET manualGeoOverride TO abort_water_target.
    RETURN FALSE.
}

WHEN TERMINAL:INPUT:HASCHAR THEN {
    IF TERMINAL:INPUT:GETCHAR() = "1" {
        SET abort_mode_active TO TRUE.
        HUDTEXT("!!! ABORT DE TERMINAL - AMARIZAJE !!!", 10, 2, 40, RED, TRUE).
        SET manualGeoOverride TO abort_water_target.
    }
    RETURN TRUE.
}

// --- TELEMETRY & SYNC ---
LOCAL initialBoosterParts TO SHIP:PARTSTAGGED("BOOSTER"):LENGTH.
LOCAL initialSeparaParts TO SHIP:PARTSTAGGED("SEPARA"):LENGTH.

PRINT "Syncing with Ship...".
PRINT "Parts (BOOSTER): " + initialBoosterParts.
PRINT "Parts (SEPARA): " + initialSeparaParts.
// --- TELEMETRY SYNC ---
LOCAL fileA TO "0:/telemetry_booster_A.json".
LOCAL fileB TO "0:/telemetry_booster_B.json".
LOCAL useA TO TRUE.
LOCAL lastLog IS -1.

FUNCTION GetTotalFuel {
    LOCAL totalCur IS 0.
    FOR res IN SHIP:RESOURCES {
        IF res:NAME <> "ElectricCharge" AND res:NAME <> "Monopropellant" AND res:NAME <> "Oxygen" AND res:NAME <> "Water" AND res:NAME <> "Food" {
            SET totalCur TO totalCur + res:AMOUNT.
        }
    }
    RETURN ROUND(totalCur).
}

FUNCTION GetFuelPctByTag {
    PARAMETER tagName.
    LOCAL totalCap IS 0.0001.
    LOCAL totalCur IS 0.
    LOCAL parts IS SHIP:PARTSTAGGED(tagName).
    IF parts:LENGTH = 0 { RETURN 0. }
    FOR p IN parts {
        FOR res IN p:RESOURCES {
            IF res:NAME <> "ElectricCharge" AND res:NAME <> "Monopropellant" {
                SET totalCap TO totalCap + res:CAPACITY.
                SET totalCur TO totalCur + res:AMOUNT.
            }
        }
    }
    RETURN ROUND((totalCur / totalCap) * 100, 1).
}

FUNCTION updateTelemetry {
    PARAMETER statusText.
    IF TIME:SECONDS > lastLog + 0.5 {
        LOCAL tFile TO fileB.
        IF useA { SET tFile TO fileA. }
        SET useA TO NOT useA.
        LOCAL engDict IS LEX().
        LIST ENGINES IN engList.
        LOCAL foundTags IS "".
        FOR e IN engList {
            LOCAL t IS e:TAG:TOUPPER:TRIM.
            IF t:LENGTH > 0 AND (t:FIND("C") = 0 OR t:FIND("R") = 0) { 
                LOCAL is_on IS 0.
                IF e:IGNITION AND (e:THRUST / MAX(0.1, e:POSSIBLETHRUST) >= 0.01) { SET is_on TO 1. }
                SET engDict[t] TO is_on.
                SET foundTags TO foundTags + t + " ".
            }
        }

        IF MOD(ROUND(TIME:SECONDS), 5) = 0 { PRINT "TAGS: " + foundTags AT (0, 24). }

        // Actualizar objetivo de forma segura (Sin escanear waypoints)
        SET targetGeo TO GetCurrentTarget().

        LOCAL accuracy IS (targetGeo:POSITION - SHIP:POSITION):MAG.
        IF (targetGeo:POSITION:MAG > 1000000) { SET accuracy TO 0. } // Ignorar si es basura

        LOCAL gVal IS 0.
        LIST SENSORS IN S_LIST.
        FOR S IN S_LIST { IF S:TYPE = "ACC" AND S:ACTIVE { SET gVal TO ROUND(S:MAG / 9.80665, 2). } }

        LOCAL data IS LEX(
            "time", ROUND(TIME:SECONDS, 1),
            "met", MISSIONTIME,
            "alt", ROUND(SHIP:ALTITUDE),
            "vel", ROUND(SHIP:AIRSPEED),
            "vs", ROUND(SHIP:VERTICALSPEED, 1),
            "apo", ROUND(SHIP:APOAPSIS),
            "per", ROUND(SHIP:PERIAPSIS),
            "g", gVal,
            "q", ROUND(SHIP:Q * 100, 1),
            "fuel", GetTotalFuel(),
            "fuelPct", GetFuelPctByTag("BOOSTER"),
            "dist", ROUND(SHIP:GEOPOSITION:DISTANCE / 1000, 1), // Downrange
            "acc", ROUND(accuracy), // Accuracy to target (meters)
            "hdist", ROUND(accuracy, 1), // Real Horizontal distance
            "thr", ROUND(THROTTLE * 100, 1), // Real-time Power %
            "engStates", engDict,
            "status", statusText,
            "version", "2.1-FIX"
        ).
        
        IF HOMECONNECTION:ISCONNECTED {
             WAIT 0.2. // Constant jitter
             WRITEJSON(data, tFile).
        }
        SET lastLog TO TIME:SECONDS.
    }
}

// --- TRAJECTORIES SAFE-WRAPPER ---
// Evita el crash "You may only call addons:tr:SETTARGET from the active vessel"
FUNCTION SafeSetTRTarget {
    PARAMETER geo.
    IF ADDONS:TR:AVAILABLE AND KUNIVERSE:ACTIVEVESSEL = SHIP {
        ADDONS:TR:SETTARGET(geo).
        RETURN TRUE.
    }
    RETURN FALSE.
}

// --- DYNAMIC TARGETING SYSTEM ---
GLOBAL lastTargetName IS "NONE".
GLOBAL targetGeo IS SHIP:GEOPOSITION. 
GLOBAL savedGeoCache IS SHIP:GEOPOSITION.
GLOBAL activeWPGeo IS 0.
GLOBAL manualGeoOverride IS 0.
GLOBAL isLZ IS FALSE. // Default to Barge (Aggressive)

// Esta función es rápida y segura, se puede llamar en el loop
FUNCTION GetCurrentTarget {
    LOCAL rawT IS 0.
    // 1. PRIORITY: Manual Override via GUI
    IF manualGeoOverride <> 0 AND manualGeoOverride:HASSUFFIX("LAT") {
        SET lastTargetName TO "MANUAL (GUI)".
        RETURN manualGeoOverride.
    }

    // 2. PRIORITY: Active Waypoint (Selected by user)
    IF activeWPGeo <> 0 AND activeWPGeo:HASSUFFIX("LAT") {
        SET lastTargetName TO "WAYPOINT (ACTIVE)".
        RETURN activeWPGeo.
    }

    // 3. PRIORITY: Saved Config (RTLS/ASDS)
    IF savedGeoCache <> SHIP:GEOPOSITION AND savedGeoCache:HASSUFFIX("LAT") {
        SET lastTargetName TO "CONFIG (SAVED)".
        RETURN savedGeoCache.
    }

    // 4. PRIORITY: Active Vessel/Part Target
    IF HASTARGET {
        LOCAL t TO TARGET.
        IF t:ISTYPE("Vessel") OR t:ISTYPE("Part") {
            SET lastTargetName TO t:NAME.
            SET rawT TO t.
        }
    }
    
    // Fallback search for Barge vessel
    IF rawT = 0 {
        LIST TARGETS IN tL.
        FOR t IN tL { IF t:NAME:TOUPPER:CONTAINS("BARGE") OR t:NAME:TOUPPER:CONTAINS("SHIP") { SET rawT TO t. SET lastTargetName TO t:NAME. BREAK. } }
    }

    // APPLY LEAD: Lead tiempo ultra-bajo para evitar inestabilidad (0.2s)
    IF rawT <> 0 AND rawT:ISTYPE("Vessel") {
        LOCAL leadTime IS 0.2. 
        RETURN BODY:GEOPOSITIONOF(rawT:POSITION + rawT:VELOCITY:SURFACE * leadTime).
    }

    // 3. FALLBACK: Waypoint recientemente detectado
    IF activeWPGeo <> 0 AND activeWPGeo:HASSUFFIX("LAT") {
        RETURN activeWPGeo.
    }
    
    // 4. FALLBACK: Saved Config (RTLS)
    IF savedGeoCache <> SHIP:GEOPOSITION AND savedGeoCache:HASSUFFIX("LAT") {
        SET lastTargetName TO "RTLS (Saved)".
        RETURN savedGeoCache.
    }
    
    // 5. LAST RESORT: Current Position
    SET lastTargetName TO "Current Geo".
    RETURN SHIP:GEOPOSITION.
}

// Carga de configuración (Cacheamos el archivo para no leer disco en vuelo)
FUNCTION LoadLandingConfig {
    IF EXISTS("1:/landing_config.json") {
        LOCAL data IS READJSON("1:/landing_config.json").
        GLOBAL savedGeoCache IS LATLNG(data["lat"], data["lng"]).
        IF data:HASKEY("isLZ") { SET isLZ TO data["isLZ"]. }
        IF NOT (DEFINED LandedAlt) OR LandedAlt = 0 { GLOBAL LandedAlt IS data["alt"]. }
    }
}

// Escaneo de Waypoints (Usa ALLWAYPOINTS para mayor estabilidad)
FUNCTION ScanWaypoints {
    HUDTEXT("Buscando Waypoints...", 2, 2, 20, WHITE, FALSE).
    LOCAL wps IS ALLWAYPOINTS().
    FOR wp IN wps {
        IF wp:ISSELECTED {
            SET activeWPGeo TO wp:GEOPOSITION.
            SET lastTargetName TO wp:NAME.
            HUDTEXT("Objetivo fijado: " + wp:NAME, 3, 2, 25, GREEN, FALSE).
            RETURN.
        }
    }
    HUDTEXT("Sin marcador activo seleccionado.", 2, 2, 20, RED, FALSE).
}

// --- INITIALIZATION ---
LoadLandingConfig().
updateTelemetry("PRELAUNCH").

// --- PERSISTENT LANDING MENU ---
GLOBAL gLand IS GUI(250).
SET gLand:X TO 510. SET gLand:Y TO 100.
gLand:ADDLABEL("<b>MENÚ DE ATERRIZAJE (HASTA SEP)</b>").
LOCAL latField IS gLand:ADDTEXTFIELD("" + ROUND(targetGeo:LAT, 6)).
LOCAL lngField IS gLand:ADDTEXTFIELD("" + ROUND(targetGeo:LNG, 6)).

LOCAL btnScanW IS gLand:ADDBUTTON("ESCANEAR WAYPOINTS").
SET btnScanW:ONCLICK TO { 
    ScanWaypoints(). 
    IF activeWPGeo <> 0 {
        SET latField:TEXT TO "" + ROUND(activeWPGeo:LAT, 6). 
        SET lngField:TEXT TO "" + ROUND(activeWPGeo:LNG, 6). 
    }
}.

LOCAL btnVessel IS gLand:ADDBUTTON("USAR OBJETIVO KSP").
SET btnVessel:ONCLICK TO { 
    IF HASTARGET AND TARGET:HASSUFFIX("GEOPOSITION") {
        SET latField:TEXT TO "" + ROUND(TARGET:GEOPOSITION:LAT, 6).
        SET lngField:TEXT TO "" + ROUND(TARGET:GEOPOSITION:LNG, 6).
        HUDTEXT("Objetivo KSP capturado.", 2, 2, 20, GREEN, FALSE).
    } ELSE { HUDTEXT("Sin objetivo seleccionado.", 2, 2, 20, RED, FALSE). }
}.

LOCAL btnManual IS gLand:ADDBUTTON("USAR COORDENADAS GUI").
SET btnManual:ONCLICK TO {
    SET manualGeoOverride TO LATLNG(latField:TEXT:TONUMBER(), lngField:TEXT:TONUMBER()).
    WRITEJSON(LEX("lat", manualGeoOverride:LAT, "lng", manualGeoOverride:LNG, "alt", LandedAlt), "1:/landing_config.json"). 
    HUDTEXT("BLOQUEADO A COORDENADAS MANUALES", 3, 2, 25, CYAN, FALSE).
}.

LOCAL btnAuto IS gLand:ADDBUTTON("VOLVER A AUTO-DETECT").
SET btnAuto:ONCLICK TO { SET manualGeoOverride TO 0. HUDTEXT("MODO AUTOMÁTICO ACTIVADO", 2, 2, 20, WHITE, FALSE). }.

gLand:ADDLABEL("--- PERFIL DE VUELO ---").
LOCAL bargeBtn IS gLand:ADDBUTTON("MODO BARGE (AGRESIVO)").
LOCAL lzBtn IS gLand:ADDBUTTON("MODO LANDING ZONE (PRECISO)").

SET bargeBtn:ONCLICK TO {
    SET isLZ TO FALSE.
    HUDTEXT("PERFIL SELECCIONADO: BARGE (ASDS)", 3, 2, 25, CYAN, FALSE).
    WRITEJSON(LEX("lat", targetGeo:LAT, "lng", targetGeo:LNG, "alt", LandedAlt, "isLZ", FALSE), "1:/landing_config.json"). 
}.
SET lzBtn:ONCLICK TO {
    SET isLZ TO TRUE.
    HUDTEXT("MODO: LANDING ZONE (PERFIL PRECISIÓN)", 3, 2, 25, YELLOW, FALSE).
    // NO forzamos coordenadas, usamos el objetivo que el usuario tenga seleccionado
    WRITEJSON(LEX("lat", targetGeo:LAT, "lng", targetGeo:LNG, "alt", LandedAlt, "isLZ", TRUE), "1:/landing_config.json"). 
}.

gLand:SHOW().
// CALIBRACIÓN DE ALTURA DE ATERRIZAJE: 
// Crucial para detectar el contacto con la barcaza/suelo.
IF SHIP:STATUS = "PRELAUNCH" OR SHIP:STATUS = "LANDED" { 
    SET LandedAlt TO ALT:RADAR. 
    PRINT "LandedAlt Calibrated: " + ROUND(LandedAlt, 2) + "m".
} ELSE IF NOT (DEFINED LandedAlt) OR LandedAlt = 0 {
    // Failsafe: Si no hay dato, asumir 0 (nivel del mar) o buscar en config
    SET LandedAlt TO 0.
    PRINT "WARNING: LandedAlt not calibrated. Assuming 0m.".
}


LOCAL landAlt IS 70.
GLOBAL targetDetermined IS TRUE.

// --- ADVANCED GUIDANCE CONSTANTS ---
GLOBAL BoosterHeight IS 70.
GLOBAL LandingBurnAlt IS 1200.
GLOBAL EngineSwitchSpeed IS 60. // m/s to switch to 1 engine
// --- RECOVERY PARAMS ---
GLOBAL HoverTargetVS IS -2.0.   // Touchdown speed
GLOBAL HoverMode IS FALSE.

// PID para Throttle en Hover (Surgical Resolution)
GLOBAL HoverPID IS PIDLOOP(0.4, 0.1, 0.8, -0.4, 0.4). // Resolution output +/- 40% over baseline
SET HoverPID:SETPOINT TO HoverTargetVS.

// PIDs de Dirección (Ported from LZ - Professional Series)
GLOBAL LngCtrlPID IS PIDLOOP(0.35, 0.3, 0.25, -20, 20). 
GLOBAL LatCtrlPID IS PIDLOOP(0.25, 0.2, 0.1, -10, 10).
GLOBAL PIDFactor IS 50. // Suavizado para RSS

GLOBAL PositionError IS V(0,0,0).
GLOBAL FinalVec IS UP:VECTOR.
GLOBAL LandingBurnStarted IS FALSE.

// Check mission profile from launch script
GLOBAL isExpendable TO FALSE.
IF EXISTS("1:/ascent_config.json") {
    LOCAL ascConf IS READJSON("1:/ascent_config.json").
    IF ascConf:HASKEY("profile") AND ascConf["profile"] = "DESECHABLE" { 
        SET isExpendable TO TRUE. 
        PRINT "--- MISIÓN DESECHABLE DETECTADA ---".
        PRINT "El booster solo enviará telemetría.".
    }
}

IF SHIP:STATUS = "PRELAUNCH" {
    PRINT "Waiting for liftoff...".
    UNTIL SHIP:ALTITUDE > 1000 { updateTelemetry("WAITING"). WAIT 0.5. }
}

PRINT "Monitoring for Separation (Total Part Sync)...".
LOCAL initialTotalParts TO SHIP:PARTS:LENGTH.
LOCAL separated IS FALSE.
LOCAL sepStartTime TO TIME:SECONDS.

UNTIL separated {
    // 1. PRIMARY: Total part count decrease (with altitude guard for Max-Q)
    IF SHIP:ALTITUDE > 20000 AND SHIP:PARTS:LENGTH < initialTotalParts {
        SET separated TO TRUE. PRINT "Separation Detected (Parts Count)!".
    }
    
    // 2. SECONDARY: MECO/Thrust fallback
    IF SHIP:ALTITUDE > 5000 AND SHIP:VERTICALSPEED < 150 {
         IF SHIP:AVAILABLETHRUST = 0 { SET separated TO TRUE. PRINT "Separation Detected (MECO fallback).". }
    }
    
    // 3. TERTIARY: Action Group 8 Check (User manual separation)
    IF AG8 { SET separated TO TRUE. PRINT "Separation Detected (AG8 manual).". }

    updateTelemetry("ATTACHED").
    IF separated { BREAK. }
    WAIT 0.5.
}

// Cerrar GUI al separarse
gLand:HIDE(). gLand:DISPOSE().
PRINT "--- GUI CERRADA (Separación Detectada) ---".

// CONFIGURAR TRAJECTORIES CON TARGET
LoadLandingConfig(). // RE-CARGAR CONFIGURACIÓN PARA ASEGURAR TARGET (ASDS/RTLS)
SET targetGeo TO GetCurrentTarget().

IF SafeSetTRTarget(targetGeo) {
    PRINT "Trajectories configurado con target: " + lastTargetName.
} ELSE {
    PRINT "Aviso: Trajectories no configurado (No es nave activa). Usando Fallback.".
}
HUDTEXT("BOOSTER ACTIVE - TARGET: " + lastTargetName, 5, 2, 30, GREEN, FALSE).


// --- POST-SEPARATION ACTIONS ---
IF isExpendable {
    PRINT "Modo Desechable: Solo telemetría activa.".
    UNTIL SHIP:ALTITUDE < 50 { updateTelemetry("FALLING"). WAIT 2. }
    WAIT UNTIL FALSE. // Stay here until destroyed
}

RCS ON.
BRAKES ON.
// --- GUIADO POST-SEPARACIÓN ---
GLOBAL guidanceSteer IS UP:VECTOR. 
LOCK STEERING TO guidanceSteer.

PRINT "Waiting for 1.5km Clearance...".
LOCAL clearanceReached IS FALSE.
LOCAL clearanceTimeout IS TIME:SECONDS + 15.

UNTIL clearanceReached OR TIME:SECONDS > clearanceTimeout {
    LOCAL nearestDist IS 10000.
    LIST TARGETS IN tList.
    FOR t IN tList { IF t:DISTANCE < nearestDist { SET nearestDist TO t:DISTANCE. } }
    IF nearestDist = 10000 { SET nearestDist TO 2000. }
    
    IF nearestDist > 1500 { SET clearanceReached TO TRUE. }
    
    // Mantener orientación segura durante separación
    SET guidanceSteer TO LOOKDIRUP(UP:VECTOR, SHIP:NORTH:VECTOR).
    
    updateTelemetry("CLEARANCE").
    PRINT "Range to Nearest: " + ROUND(nearestDist) + "m   " AT (0, 26).
    IF clearanceReached { BREAK. }
    WAIT 0.5.
}

PRINT "Range Safely Clear (or Timeout). Preparing Boostback Burn...".
WAIT 1.

// DEBUG: Verificar motores encontrados
PRINT "--- DIAGNÓSTICO DE MOTORES ---".
LIST ENGINES IN allEngs.
LOCAL enginesFound IS 0.
FOR e IN allEngs {
    PRINT "Motor encontrado. Tag: '" + e:TAG + "' Ignition: " + e:IGNITION.
    LOCAL t IS e:TAG:TOUPPER.
    // Soporte para tags "C1"-"C3" (Original) y "1"-"3" (Friend's Style)
    IF t = "C1" OR t = "C2" OR t = "C3" OR t = "1" OR t = "2" OR t = "3" {
        e:ACTIVATE().
        SET enginesFound TO enginesFound + 1.
    } ELSE {
        e:SHUTDOWN().
    }
}

IF enginesFound = 0 {
    PRINT "!!! ALERTA: NO SE ENCONTRARON MOTORES CON TAGS VALIDOS !!!".
    PRINT "Tags esperados: 'C1', 'C2', 'C3'  O  '1', '2', '3'".
    HUDTEXT("ERROR: NO HY MOTORES VALIDOS (TAGS)", 10, 2, 30, RED, TRUE).
    WAIT 5.
} ELSE {
    PRINT "Motores activos: " + enginesFound.
}


AG7 ON. 
PRINT "Action: Triple Central Engines Active (AG7).".
WAIT 0.5.

// CRITICAL: Re-activate engines after AG7 (in case AG7 toggles them)
PRINT "Verifying engine ignition...".
LOCAL ignitionVerified IS FALSE.
LOCAL verifyAttempts IS 0.
UNTIL ignitionVerified OR verifyAttempts > 3 {
    SET ignitionVerified TO TRUE.
    FOR e IN SHIP:ENGINES {
        LOCAL t IS e:TAG:TOUPPER.
        IF t = "C1" OR t = "C2" OR t = "C3" OR t = "1" OR t = "2" OR t = "3" {
            IF NOT e:IGNITION {
                e:ACTIVATE().
                SET ignitionVerified TO FALSE.
            }
        }
    }
    IF NOT ignitionVerified {
        PRINT "Re-activating engines (Attempt " + verifyAttempts + ")...".
        WAIT 0.5.
    }
    SET verifyAttempts TO verifyAttempts + 1.
}

IF ignitionVerified {
    PRINT "All engines IGNITED and ready.".
} ELSE {
    PRINT "WARNING: Some engines may not be ignited!".
    HUDTEXT("ENGINE IGNITION WARNING", 5, 2, 30, YELLOW, FALSE).
}

// Ajuste de Steering Manager para estabilidad en Boostback (Dampening)
SET steeringManager:maxStoppingTime TO 3.0. 
SET steeringManager:pitchTS TO 1.5. // Más responsivo para el giro inicial
SET steeringManager:yawTS TO 1.5.

WAIT 2. // ESTABILIZACIÓN POST-SEP: Dejar que el RCS absorba vibraciones
PRINT "Esperando alineación (Vector Guidance)...".
LOCAL alignStart IS TIME:SECONDS.
UNTIL FALSE {
    IF DEFINED abort_mode_active AND abort_mode_active { BREAK. }
    // MOD: Guía vectorial directa al objetivo (evita el bug de :HEADING)
    LOCAL targetVec IS VXCL(UP:VECTOR, targetGeo:POSITION):NORMALIZED.
    SET guidanceSteer TO LOOKDIRUP(targetVec + UP:VECTOR * 0.08, SHIP:NORTH:VECTOR).
    
    LOCAL angErr IS VANG(SHIP:FACING:VECTOR, targetVec + UP:VECTOR * 0.08).
    PRINT "Angle Error: " + ROUND(angErr, 1) + " deg   " AT(0, 30).
    
    IF angErr < 10 { BREAK. }
    IF TIME:SECONDS > alignStart + 20 { BREAK. }
    updateTelemetry("ALIGNING").
    WAIT 0.1.
}

PRINT "Ejecutando Boostback (Guidance: Vector)...".
PRINT "Target: " + ROUND(targetGeo:LAT, 4) + ", " + ROUND(targetGeo:LNG, 4).

LOCK guiDist TO VXCL(UP:VECTOR, targetGeo:POSITION):MAG. // Track horizontal distance for GUI/logic
LOCAL burnStartTime IS TIME:SECONDS.
LOCK THROTTLE TO 1.
LOCAL bestAccuracy IS 9999999.
LOCAL distIncreasingCount IS 0.

// MODO DE PRECISIÓN (ASDS): Solo para GUI o Objetivos de KSP (No para Waypoints)
LOCAL isASDS IS (lastTargetName = "MANUAL (GUI)" OR HASTARGET).
IF isASDS { HUDTEXT("ASDS PRECISION MODE: ACTIVE", 5, 2, 30, CYAN, FALSE). }
UNTIL FALSE {
    IF DEFINED abort_mode_active AND abort_mode_active { PRINT "ABORT: CUTTING BOOSTBACK". BREAK. }
    // DYNAMIC TARGET (Trajectories-Enhanced)
    SET targetGeo TO GetCurrentTarget().
    LOCAL bargeRelPos IS targetGeo:POSITION.
    LOCAL vesselDir IS VXCL(UP:VECTOR, bargeRelPos):NORMALIZED. 
    LOCAL boostedTargetPos IS bargeRelPos. 

    // 1. DETERMINAR PRECISIÓN ACTUAL
    LOCAL hasTR IS (ADDONS:TR:AVAILABLE AND ADDONS:TR:HASIMPACT).
    LOCAL currentAccuracy IS (boostedTargetPos):MAG.
    LOCAL impactPos IS 0.
    IF hasTR { SET impactPos TO ADDONS:TR:IMPACTPOS. }
    
    // Calcula Error Longitudinal (Positivo = Pasado el objetivo)
    LOCAL LngErr IS 0.
    IF hasTR { 
        LOCAL ImpactVec TO impactPos:POSITION.
        // Dot product with target direction to see if we reached the overshoot point
        SET LngErr TO VDOT(vesselDir, ImpactVec - boostedTargetPos).
        SET currentAccuracy TO (ImpactVec - boostedTargetPos):MAG.
    }
    
    // 2. FAILSAFE: OVERSHOOT PROTECTION (Accuracy Minimization)
    // Solo empezamos a vigilar el overshoot tras 2 segundos de quemado
    IF TIME:SECONDS > burnStartTime + 2 {
        IF currentAccuracy < bestAccuracy {
            SET bestAccuracy TO currentAccuracy.
            SET distIncreasingCount TO 0.
        } ELSE IF currentAccuracy > bestAccuracy + 100 {
            SET distIncreasingCount TO distIncreasingCount + 1.
        }
    }

    // THROTTLE TAPER: Bajar potencia gradualmente cuando nos acercamos
    // Ajustado para ser más agresivo en boostback
    IF currentAccuracy < 1000 OR guiDist < 1000 { LOCK THROTTLE TO 0.3. }  // 30% mínimo a 1km
    ELSE IF currentAccuracy < 3000 OR guiDist < 3000 { LOCK THROTTLE TO 0.6. }  // 60% a 3km
    ELSE { LOCK THROTTLE TO 1. }  // 100% cuando lejos
    
    // 3. STEERING & TRAJECTORIES CHECK
    IF hasTR {
        SafeSetTRTarget(targetGeo). // SYNC: Mantener Trajectories en el punto correcto

        // CORTE POR ENERGÍA: Si el impacto ya está tras el punto de overshoot (1.5km tras la barca para RSS)
        IF LngErr > 1500 { 
            PRINT "Trajectory Overshoot Reached (1.5km Buffer).".
            BREAK. 
        }
        
        // Cortar si estamos muy cerca del punto boosted (Failsafe)
        IF currentAccuracy < 50 { 
            PRINT "Target Accuracy Reached!". 
            BREAK. 
        }
        
        // DIVERGENCIA: Si el error empieza a subir (Signo claro de que hemos pasado el objetivo)
        IF (bestAccuracy < 5000 OR isASDS) AND currentAccuracy > bestAccuracy + 1000 {
            PRINT "TR DIVERGENCE DETECTED (" + ROUND(currentAccuracy - bestAccuracy) + "m). CUTTING!". 
            BREAK.
        }

        // Ajuste dinámico de dirección durante el quemado (Gains aumentados para RSS)
        LOCAL impactErrVec IS VXCL(UP:VECTOR, impactPos:POSITION - targetGeo:POSITION).
        LOCAL steerVec TO (targetGeo:POSITION:NORMALIZED + UP:VECTOR * 0.35 - impactErrVec * 0.06):NORMALIZED.
        SET guidanceSteer TO LOOKDIRUP(steerVec, SHIP:NORTH:VECTOR).
    } ELSE {
        // PD Guidance Fallback (Solo usa distancias horizontales)
        LOCAL HorizError IS VXCL(UP:VECTOR, targetGeo:POSITION).
        LOCAL CurrentHVel IS VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE).
        LOCAL GuidanceErr IS (HorizError * 0.005) - (CurrentHVel * 0.01). 
        
        // MOD: Aseguramos que el vector de empuje apunte AL objetivo
        LOCAL steerVec TO (targetGeo:POSITION:NORMALIZED + UP:VECTOR * 0.25 + GuidanceErr):NORMALIZED.
        SET guidanceSteer TO LOOKDIRUP(steerVec, SHIP:NORTH:VECTOR).
    }
    
    // VERIFICACIÓN DE DIRECCIÓN (Anti-Reversa) - Threshold aumentado para RSS
    IF TIME:SECONDS > burnStartTime + 5 AND distIncreasingCount > 15 {
        HUDTEXT("!!! DIRECTION ERROR DETECTED - FLIPPING !!!", 5, 2, 35, RED, TRUE).
        // Si nos alejamos, el vector de empuje está invertido
        SET steerVec TO (targetGeo:POSITION:NORMALIZED * -1 + UP:VECTOR * 0.25):NORMALIZED.
        SET guidanceSteer TO LOOKDIRUP(steerVec, SHIP:NORTH:VECTOR).
    }

    // 4. AGGRESSIVE OVERSHOOT CUTOFF
    IF distIncreasingCount > 20 AND (guiDist < 100000 OR isASDS) {
        PRINT "PINPOINT OVERSHOOT CONFIRMED (" + distIncreasingCount + " cycles). CUTTING!".
        BREAK.
    }
    
    // Failsafe: Si la altitud baja demasiado, abortar Boostback para ir a Reentry
    IF SHIP:ALTITUDE < 23000 {
        PRINT "ALTITUDE FLOOR REACHED (23km). TRANSITIONING TO REENTRY!".
        BREAK.
    }

    // Failsafe: Si la velocidad horizontal apunta hacia afuera del target
    // Grace period: 15s para permitir que el cohete revierta su trayectoria
    LOCAL hVel IS VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE).
    LOCAL dot TO VDOT(hVel, targetGeo:POSITION).
    IF dot < 0 AND guiDist < 50000 AND TIME:SECONDS > burnStartTime + 15 {
        PRINT "VELOCITY DIRECTION ERROR. CUTTING!".
        BREAK.
    }
    
    // FAILSAFE: Corte basado en distancia horizontal (cuando Trajectories no disponible)
    // Reducido de 5km a 2km para permitir acercamiento más agresivo
    IF NOT hasTR AND guiDist < 2000 {
        PRINT "HORIZONTAL DISTANCE < 2km (No Trajectories). CUTTING!".
        BREAK.
    }
    
    // FAILSAFE: Timeout absoluto (60 segundos máximo de boostback)
    IF TIME:SECONDS > burnStartTime + 60 {
        PRINT "BOOSTBACK TIMEOUT (60s). CUTTING!".
        BREAK.
    }

    updateTelemetry("BOOSTBACK").
    IF SHIP:AVAILABLETHRUST < 1 { PRINT "Flameout! Ending Burn.". BREAK. } 
    WAIT 0.1.
}

// Restaurar Steering Manager para vuelo normal
SET steeringManager:maxStoppingTime TO 0.5.
SET steeringManager:pitchTS TO 2.0.
SET steeringManager:yawTS TO 2.0.

LOCK THROTTLE TO 0.

PRINT "Re-entry coast (Target: 23km)...".
SET guidanceSteer TO SRFRETROGRADE.
BRAKES ON.
UNTIL SHIP:ALTITUDE < 23000 {
    // Si estamos en atmósfera, aplicamos un guiado PD suave (Body Lift)
    IF SHIP:ALTITUDE < 50000 AND SHIP:ALTITUDE > 23000 {
        LOCAL HorizError IS VXCL(UP:VECTOR, targetGeo:POSITION).
        LOCAL CurrentHVel IS VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE).
        LOCAL GuidanceErr IS (HorizError * 0.0001) - (CurrentHVel * 0.0003). 
        
        // Limitar corrección a 1.5 grados para seguridad
        IF GuidanceErr:MAG > 0.026 { SET GuidanceErr TO GuidanceErr:NORMALIZED * 0.026. }

        SET guidanceSteer TO LOOKDIRUP(SRFRETROGRADE:VECTOR + GuidanceErr, SHIP:NORTH:VECTOR).
    } ELSE {
        SET guidanceSteer TO SRFRETROGRADE.
    }
    updateTelemetry("COASTING").
    WAIT 0.5.
}

PRINT "Executing Entry Burn (Triple Engine)...".
// Safety: ensure central engines (C1, C2, C3) are active
LIST ENGINES IN entryEngs.
FOR e IN entryEngs { 
    LOCAL t IS e:TAG:TOUPPER.
    IF t = "C1" OR t = "C2" OR t = "C3" OR t = "1" OR t = "2" OR t = "3" { e:ACTIVATE(). } 
}
LOCK THROTTLE TO 1.
// === CONFIG PIDs REFERENCIA (FRIEND'S CODE) ===
SET PIDFactor TO 10.
SET LngCtrlPID TO PIDLOOP(0.35, 0.3, 0.25, -15, 15). // Authority 15 deg
SET LatCtrlPID TO PIDLOOP(0.25, 0.2, 0.1, -5, 5).


// === LOGICA DE REF (FRIEND'S CODE) ===
// Target: Slow down to 450 m/s with Professional Guidance (Failsafe for Range)
UNTIL SHIP:AIRSPEED < 450 {
    SET targetGeo TO GetCurrentTarget(). // DYNAMIC TRACKING
    SET targetPos TO targetGeo:POSITION.
    LOCAL ApproachUPVector IS (targetPos - BODY:POSITION):NORMALIZED.
    
    // SAFE NORMALIZATION
    LOCAL rawAppVec IS VXCL(UP:VECTOR, targetPos - SHIP:POSITION).
    LOCAL ApproachVector IS SHIP:NORTH:VECTOR.
    IF rawAppVec:MAG > 0.1 { SET ApproachVector TO rawAppVec:NORMALIZED. }
    
    LOCAL ErrorVector IS V(0,0,0).
    IF ADDONS:TR:AVAILABLE AND ADDONS:TR:HASIMPACT {
        SafeSetTRTarget(targetGeo).
        // CORRECTED: Target - Impact (Proven LandingLZ math)
        SET ErrorVector TO targetPos - ADDONS:TR:IMPACTPOS:POSITION.
    } ELSE {
        SET ErrorVector TO VXCL(UP:VECTOR, targetPos - SHIP:POSITION).
    }

    LOCAL LatError IS VDOT(ANGLEAXIS(-90, ApproachUPVector) * ApproachVector, ErrorVector).
    LOCAL LngError IS VDOT(ApproachVector, ErrorVector).

    // --- LONGITUDINAL BURN (MASSIVE OVERREACH BUFFER) ---
    // Buffer de 7.5 km para asegurar que el cohete "vuela" hasta el centro en RSS
    // Ajustado para evitar sobre-alcance excesivo (Overshoot)
    LOCAL TargetLongError IS LngError - 7500. 
    LOCAL throttleVal IS MAX(MIN(-TargetLongError / 6000 + 0.1, 1.0), 0.1).
    LOCK THROTTLE TO throttleVal.

    // PID Updates (Authority 15 deg)
    SET LngCtrlPID:MAXOUTPUT TO MAX(MIN(ABS(LngError) / PIDFactor, 15), 1.0).
    SET LngCtrlPID:MINOUTPUT TO -LngCtrlPID:MAXOUTPUT.
    
    LOCAL LngCtrl IS -LngCtrlPID:UPDATE(TIME:SECONDS, LngError).
    LOCAL LatCtrl IS -LatCtrlPID:UPDATE(TIME:SECONDS, LatError).
    
    // Rotation logic
    LOCAL BaseDir IS -SHIP:VELOCITY:SURFACE.
    LOCAL BaseSteeringVec IS BaseDir * ANGLEAXIS(-LngCtrl, LOOKDIRUP(BaseDir, UP:VECTOR):STARVECTOR) * ANGLEAXIS(LatCtrl, UP:VECTOR).
    
    SET guidanceSteer TO LOOKDIRUP(BaseSteeringVec, SHIP:NORTH:VECTOR).
    
    updateTelemetry("ENTRY BURN").
    PRINT "EB-STEER: LErr=" + ROUND(LngError) + " LCtrl=" + ROUND(LngCtrl,1) + "    " AT (0, 31).
    WAIT 0.1.
}
LOCK THROTTLE TO 0.

PRINT "Atmospheric Descent...".
UNTIL SHIP:ALTITUDE < 8000 {
    SET targetGeo TO GetCurrentTarget(). // DYNAMIC TRACKING
    SET targetPos TO targetGeo:POSITION. 
    SafeSetTRTarget(targetGeo).
    
    LOCAL ApproachUPVector IS (targetPos - BODY:POSITION):NORMALIZED.
    
    // SAFE NORMALIZATION
    LOCAL rawAppVec IS VXCL(UP:VECTOR, targetPos - SHIP:POSITION).
    LOCAL ApproachVector IS SHIP:NORTH:VECTOR.
    IF rawAppVec:MAG > 0.1 { SET ApproachVector TO rawAppVec:NORMALIZED. }
    
    LOCAL ErrorVector IS V(0,0,0).
    IF ADDONS:TR:AVAILABLE AND ADDONS:TR:HASIMPACT {
        // CORRECTED: Target - Impact to pull trajectory centerside
        SET ErrorVector TO targetPos - ADDONS:TR:IMPACTPOS:POSITION.
    } ELSE {
        SET ErrorVector TO VXCL(UP:VECTOR, targetPos - SHIP:POSITION).
    }

    LOCAL LatError IS VDOT(ANGLEAXIS(-90, ApproachUPVector) * ApproachVector, ErrorVector).
    LOCAL LngError IS VDOT(ApproachVector, ErrorVector).

    // PID Updates (Authority 12 deg for aerodynamic tracking)
    SET LngCtrlPID:MAXOUTPUT TO MAX(MIN(ABS(LngError) / PIDFactor, 12), 0.5).
    SET LngCtrlPID:MINOUTPUT TO -LngCtrlPID:MAXOUTPUT.
    
    LOCAL LngCtrl IS -LngCtrlPID:UPDATE(TIME:SECONDS, LngError).
    LOCAL LatCtrl IS -LatCtrlPID:UPDATE(TIME:SECONDS, LatError).
    
    // Rotation logic
    LOCAL BaseDir IS -SHIP:VELOCITY:SURFACE.
    LOCAL BaseSteeringVec IS BaseDir * ANGLEAXIS(-LngCtrl, LOOKDIRUP(BaseDir, UP:VECTOR):STARVECTOR) * ANGLEAXIS(LatCtrl, UP:VECTOR).
    
    // Retrograde mixing: Allow more authority for barge precision
    LOCAL mixRetro IS MAX(0, MIN(1, 1 - (ABS(LngError)/5000))). 
    LOCAL FinalSteerVec IS BaseSteeringVec:NORMALIZED * (1 - mixRetro) + SRFRETROGRADE:VECTOR * mixRetro.
    
    SET guidanceSteer TO LOOKDIRUP(FinalSteerVec, SHIP:NORTH:VECTOR).
    
    updateTelemetry("DESCENT").
    PRINT "DES-STEER: LErr=" + ROUND(LngError) + " LCtrl=" + ROUND(LngCtrl,1) + "    " AT (0, 31).
    WAIT 0.05. // Higher frequency
}

PRINT "Powered Landing...".
// PROFESIONAL CONTROL: Lock to guidance variable immediately
LOCK STEERING TO guidanceSteer.

// Configurar Trajectories para landing
IF ADDONS:TR:AVAILABLE { 
    ADDONS:TR:SETTARGET(targetGeo). 
    PRINT "Trajectories target set for landing: " + lastTargetName.
}

UNTIL SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED" {
    // CALCULO DATOS DE VUELO (Requerido para Steering)
    SET PositionError TO targetGeo:POSITION. 
    LOCAL HorizError IS VXCL(UP:VECTOR, PositionError).
    LOCAL currentHVel IS VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE).
    
    // ESCALADO DINÁMICO DE AUTORIDAD (Ahorro de Combustible + Reach)
    LOCAL thrustRatio IS SHIP:THRUST / MAX(0.1, SHIP:AVAILABLETHRUST).
    LOCAL dynamicTiltMult IS 0.4 + (0.6 * thrustRatio).
    IF isLZ { SET dynamicTiltMult TO 1.0. } // MODO LZ: Autoridad total siempre para buscar el pad
    
    // 3. Gestión de Zonas y Hover
    // MOD: Inicio de Quemado de Aterrizaje a 5500m (1000m más arriba por petición)
    IF NOT LandingBurnStarted AND ALT:RADAR < 5500 {
        SET LandingBurnStarted TO TRUE.
        SET GuidanceStartTime TO TIME:SECONDS.
        HUDTEXT("LANDING BURN START - BLOCK 2 FEED-FORWARD", 5, 2, 45, YELLOW, FALSE).
        
        // REACCION FIRME: Estandarizamos para evitar el efecto péndulo
        SET steeringManager:maxStoppingTime TO 3.0.
        SET steeringManager:pitchTS TO 1.5.
        SET steeringManager:yawTS TO 1.5.
        
        // Actuamos C1/2/3 con Gimbal Limitado (40%) para estabilidad
        FOR e IN SHIP:ENGINES {
            LOCAL t IS e:TAG:TOUPPER.
            IF t = "C1" OR t = "C2" OR t = "C3" OR t = "1" OR t = "2" OR t = "3" { 
                e:ACTIVATE(). 
                IF e:HASGIMBAL { SET e:GIMBAL:LIMIT TO 40. }
            }
        }
        // Inicializamos HoverPID con ganancias suavizadas para evitar oscilaciones (BLOCK 2.1)
        SET HoverPID:KP TO 0.3.   
        SET HoverPID:KI TO 0.1.  
        SET HoverPID:KD TO 0.2.   
        SET HoverPID:MAXOUTPUT TO 0.5. 
        SET HoverPID:MINOUTPUT TO -0.5. 
        
        SET HighHoverDone TO FALSE.
    }

    IF LandingBurnStarted {
        SetPhysicsRange(2500000). // CRITICO: Mantener carga RSS en landing
        
        // Actualizar target en Trajectories de forma segura
        SafeSetTRTarget(targetGeo).
        
        LOCAL modeText IS "BARGE (ASDS)".
        IF isLZ { SET modeText TO "LANDING ZONE (RTLS)". }
        PRINT "Landing Mode: " + modeText + "      " AT (0, 28).
        
        // --- SURGICAL BULLSEYE STRATEGY ---
        SET targetGeo TO GetCurrentTarget().
        LOCAL targetPos IS targetGeo:POSITION. 

        LOCAL base_alt IS MAX(0, ALT:RADAR - LandedAlt). 

        // 1. PREDICCIÓN DE IMPACTO GLOBAL (Disponible para Throttle y Steering)
        LOCAL impactPoint IS V(0,0,0).
        IF ADDONS:TR:AVAILABLE AND ADDONS:TR:HASIMPACT {
            SET impactPoint TO ADDONS:TR:IMPACTPOS:POSITION.
        }
        // impactErr: Vector desde el Objetivo al punto de Impacto (Predicción)
        LOCAL impactErr IS VXCL(UP:VECTOR, impactPoint - targetPos).
        LOCAL hDistReal IS HorizError:MAG. // DISTANCIA REAL ACTUAL A LA BARCAZA (BLOCK 5)
        // DYNAMIC TARGET VS PROFILE (Curva suave para dar tiempo al centrado lateral)
        LOCAL targetVS IS -1 * (SQRT(base_alt) * 1.5 + 1.2). 
        
        // Touchdown speed caps (Soft Landing)
        IF base_alt < 40 { SET targetVS TO -2.0. }
        IF base_alt < 20 { SET targetVS TO -1.2. }
        IF base_alt < 10 { SET targetVS TO -0.8. }
        IF base_alt < 4  { SET targetVS TO -0.5. } // Toque quirúrgico tipo pluma
        
        // --- PRIORIDAD DE CENTRADO (Ventana: 1000m a 600m) ---
        // Se detiene ESTRICTAMENTE si hDistReal <= 15m
        IF base_alt < 1000 AND base_alt > 600 AND (hDistReal > 15.0) {
            SET targetVS TO -1.2. // Descenso fluido para dar tiempo al centrado
            HUDTEXT("PRECISION ALIGNMENT: Dist: " + ROUND(hDistReal,1) + "m (Holding for 15m limit...)", 1, 2, 20, CYAN, FALSE).
        }
        
        // BRAKE DE DESCENSO FINAL: Solo si estamos REALMENTE desviados a baja altura
        LOCAL hSpeed IS currentHVel:MAG.
        IF base_alt < 50 AND hSpeed > 5.0 AND hDistReal > 8 {
            SET targetVS TO -0.8. 
            HUDTEXT("FINAL CORRECTION: Slowing descent to center...", 1, 2, 20, YELLOW, FALSE).
        }

        // MODO LANDING (<60m): Direct Bullseye Authority
        IF ALT:RADAR < 60 { 
            IF NOT HoverMode { 
                SET HoverMode TO TRUE. 
                // Engines are ALREADY active from 8000m. No redundant switching.
            }
            // NO DESCENT FLOOR: Target VS goes all the way to touchdown
        }
        
        SET HoverPID:SETPOINT TO targetVS.
        
        // === FEED-FORWARD THROTTLE (The BLOCK2 Secret Sauce) ===
        LOCAL GRAV IS BODY:MU / (SHIP:BODY:POSITION:MAG ^ 2).
        LOCAL TWR IS SHIP:AVAILABLETHRUST / (SHIP:MASS * GRAV).
        LOCAL HoverBaseline IS 1 / MAX(0.1, TWR). 
        
        // TILT COMPENSATION & THROTTLE SAFETY
        LOCAL tiltAngle IS VANG(UP:VECTOR, SHIP:FACING:VECTOR).
        LOCAL cosTilt IS MAX(0.85, COS(tiltAngle)). 
        SET HoverBaseline TO (HoverBaseline / cosTilt). // Sin offset de seguridad para mayor precisión
        
        LOCAL pidMod IS HoverPID:UPDATE(TIME:SECONDS, SHIP:VERTICALSPEED).
        
        // El throttle puede bajar a 0.01 si el cohete asciende por error, pero NO se apaga
        LOCK THROTTLE TO MAX(0.01, MIN(1.0, HoverBaseline + pidMod)).

        // 2. STEERING: High-Authority PD Guidance (Barge Hunter)
        // INICIO: Ahora la guía de precisión empieza en cuanto arranca el motor (5500m)
        IF LandingBurnStarted { 
            LOCAL currentTiltLimit IS 18.0. // Reducido para estabilidad (BLOCK 4 - Damped)
            IF ALT:RADAR < 1000 { SET currentTiltLimit TO 12.0. }
            IF ALT:RADAR < 60   { SET currentTiltLimit TO 6.0. } 

            SET steeringManager:maxStoppingTime TO 3.5. // Amortiguación majestuosa para evitar oscilaciones

            // Target Horizontal Velocity: Stronger pull to center
            // Escalamos velocidad horizontal permitida con la altura
            LOCAL maxH IS MIN(35, 6 + (ALT:RADAR / 200)). 
            LOCAL targetHVel IS (HorizError * 0.45). // Ganancia moderada para evitar bandazos
            IF targetHVel:MAG > maxH { SET targetHVel TO targetHVel:NORMALIZED * maxH. }
            
            // Nudge Calculation: Balanced Velocity Matching
            LOCAL nudge IS (targetHVel - currentHVel) * 0.35.
            
            // Final Steering with hard Tilt Cap
            LOCAL RawSteer IS UP:VECTOR + nudge.
            IF VANG(UP:VECTOR, RawSteer) > currentTiltLimit {
                SET RawSteer TO UP:VECTOR + VXCL(UP:VECTOR, RawSteer):NORMALIZED * TAN(currentTiltLimit).
            }
            
            SET guidanceSteer TO LOOKDIRUP(RawSteer, SHIP:NORTH:VECTOR).
            PRINT "MODE: ULTRA-SMOOTH PD (Dist: " + ROUND(hDistReal) + "m)       " AT (0, 31).
        }
        ELSE {
            // HIGH ALTITUDE / COAST ZONE (Aero-Glide with Trajectories)
            LOCAL horizDist IS HorizError:MAG.
            IF horizDist > 2500 {
                SET currentTiltLimit TO 30.0.  
            } ELSE {
                SET currentTiltLimit TO 15.0. 
            }
            
            // Use Trajectories only for extreme high-altitude/aero phase
            LOCAL impactPoint IS V(0,0,0).
            IF ADDONS:TR:AVAILABLE AND ADDONS:TR:HASIMPACT {
                SET impactPoint TO ADDONS:TR:IMPACTPOS:POSITION.
            }
            LOCAL impactErr IS VXCL(UP:VECTOR, impactPoint - targetPos).

            LOCAL timeToLand IS MAX(2.0, ABS(base_alt / MAX(1.0, ABS(SHIP:VERTICALSPEED)))).
            // Target: Llegar AL CENTRO (no solo al impacto)
            LOCAL targetHVel_Impact IS (impactErr * -0.75) / timeToLand. 
            LOCAL targetHVel_Pos IS (HorizError * 0.35). // Nudge mucho más fuerte hacia la posición real
            
            LOCAL targetHVel IS targetHVel_Impact + targetHVel_Pos.
            
            IF targetHVel:MAG > 50 { SET targetHVel TO targetHVel:NORMALIZED * 50. }

            LOCAL fadeMult IS MIN(1.0, (TIME:SECONDS - GuidanceStartTime) / 4).
            LOCAL nudge IS (targetHVel - currentHVel) * (0.18 * fadeMult).
            
            IF nudge:MAG > TAN(currentTiltLimit) { SET nudge TO nudge:NORMALIZED * TAN(currentTiltLimit). }
            
            // USE SRFRETROGRADE as base for aero phase - Utilizing Body Lift
            SET guidanceSteer TO LOOKDIRUP(SRFRETROGRADE:VECTOR + nudge, SHIP:NORTH:VECTOR).
            PRINT "MODE: AERO-GLIDE (TR-Enhanced Retro)     " AT (0, 31).
        }
        
        // HUD Diagnostics
        IF MOD(ROUND(TIME:SECONDS*10), 10) = 0 {
            LOCAL hDist IS HorizError:MAG.
            PRINT "Target: " + lastTargetName + " (" + ROUND(hDist,1) + "m)       " AT(0, 29).
            PRINT "Descent: " + ROUND(ALT:RADAR) + "m  HVel: " + ROUND(currentHVel:MAG,1) + "m/s TgtVS: " + ROUND(HoverPID:SETPOINT, 1) + "  " AT(0, 30).
        }
    }

    IF ALT:RADAR < 500 AND NOT GEAR { 
        GEAR ON. 
        PRINT "Landing Gear Deployed! Reducing Gimbal for stability.".
        // Suavizamos gimbal en TODOS los motores activos al desplegar patas
        FOR e IN SHIP:ENGINES { 
            IF e:HASGIMBAL { SET e:GIMBAL:LIMIT TO 15. } 
        }
    }
    
    updateTelemetry("LANDING").
    
    // DETECCION DE ATERRIZAJE ROBUSTA (KILL SWITCH)
    // 1. Status oficial "LANDED" o "SPLASHED"
    // 2. Altura de Calibración: Si estamos a menos de 0.3m del suelo (reducido de 0.5 para precisión)
    // 3. Velocidad Vertical Positiva (Bounce) cerca del suelo
    
    LOCAL isGrounded IS (SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED").
    LOCAL isAtLandedAlt IS (ALT:RADAR < LandedAlt + 0.3).
    LOCAL isBouncing IS (ALT:RADAR < LandedAlt + 10 AND SHIP:VERTICALSPEED > 0.1).

    IF isGrounded OR isAtLandedAlt OR isBouncing { 
        PRINT "TOUCHDOWN/BOUNCE DETECTED. HARD SHUTDOWN.".
        
        // KILL SWITCH INSTANTÁNEO
        LOCK THROTTLE TO 0. 
        SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
        UNLOCK THROTTLE. 
        UNLOCK STEERING.
        
        FOR eng IN SHIP:ENGINES { eng:SHUTDOWN(). }
        
        PRINT "Status: " + SHIP:STATUS.
        BREAK. 
    }

    // SEGURIDAD ADICIONAL: Cortar throttle si estamos a punto de tocar (0.5m)
    // Ya no se requiere aqui porque lo gestionamos arriba con mas control
    // IF ALT:RADAR < LandedAlt + 0.5 { LOCK THROTTLE TO 0. }
    WAIT 0.05.
}

PRINT "LANDED!".
updateTelemetry("LANDED").
UNLOCK STEERING. SAS ON.
WAIT 5.
// Safe shutdown for central engine(s) tagged '1'
FOR p IN SHIP:PARTSTAGGED("1") { 
    FOR m IN p:MODULES {
        IF m = "ModuleEngines" OR m = "ModuleEnginesRF" { p:GETMODULE(m):DOEVENT("shutdown"). }
    }
}
PRINT "Misión Finalizada. Booster Recuperado.".

// --- TELEMETRY KEEP-ALIVE (INFINITE) ---
UNTIL FALSE {
    updateTelemetry("LANDED").
    WAIT 1.0.
}
