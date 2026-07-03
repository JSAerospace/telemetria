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

FUNCTION GetFuelPercent {
    LOCAL totalCap IS 0.001. 
    LOCAL totalCur IS 0.
    
    // Support for LqdMethane (RSS) or LiquidFuel (Stock)
    FOR res IN SHIP:RESOURCES {
        IF res:NAME = "LqdMethane" OR res:NAME = "LiquidFuel" OR res:NAME = "Oxidizer" {
            SET totalCap TO totalCap + res:CAPACITY.
            SET totalCur TO totalCur + res:AMOUNT.
        }
    }
    
    RETURN (totalCur / totalCap) * 100.
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
            "alt", ROUND(SHIP:ALTITUDE),
            "vel", ROUND(SHIP:AIRSPEED),
            "vs", ROUND(SHIP:VERTICALSPEED, 1),
            "apo", ROUND(SHIP:APOAPSIS),
            "per", ROUND(SHIP:PERIAPSIS),
            "g", gVal,
            "q", ROUND(SHIP:Q * 100, 1),
            "fuel", ROUND(GetFuelPercent(), 1),
            "dist", ROUND(SHIP:GEOPOSITION:DISTANCE / 1000, 1), // Downrange
            "acc", ROUND(accuracy), // Accuracy to target (meters)
            "engStates", engDict,
            "status", statusText
        ).
        
        IF HOMECONNECTION:ISCONNECTED {
             WAIT 0.2. // Constant jitter
             WRITEJSON(data, tFile).
        }
        SET lastLog TO TIME:SECONDS.
    }
}

// --- DYNAMIC TARGETING SYSTEM ---
GLOBAL lastTargetName IS "NONE".
GLOBAL targetGeo IS SHIP:GEOPOSITION. 
GLOBAL savedGeoCache IS SHIP:GEOPOSITION.
GLOBAL activeWPGeo IS 0.
GLOBAL manualGeoOverride IS 0.

// Esta función es rápida y segura, se puede llamar en el loop
FUNCTION GetCurrentTarget {
    // 1. PRIORITY: Manual Override via GUI
    IF manualGeoOverride <> 0 AND manualGeoOverride:HASSUFFIX("LAT") {
        SET lastTargetName TO "MANUAL (GUI)".
        RETURN manualGeoOverride.
    }

    // 2. PRIORITY: Active Vessel/Part Target (Muy rápido)
    IF HASTARGET {
        LOCAL t TO TARGET.
        IF t:ISTYPE("Vessel") OR t:ISTYPE("Part") {
            SET lastTargetName TO t:NAME.
            RETURN t:GEOPOSITION.
        }
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

// --- TARGETING UTILITIES ---
FUNCTION SafeSetTRTarget {
    PARAMETER geo.
    IF ADDONS:TR:AVAILABLE {
        IF ADDONS:TR:HASIMPACT {
            ADDONS:TR:SETTARGET(geo).
        }
    }
}

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

gLand:SHOW().
IF SHIP:STATUS = "PRELAUNCH" OR SHIP:STATUS = "LANDED" { SET LandedAlt TO ALT:RADAR. }


LOCAL landAlt IS 70.
GLOBAL targetDetermined IS TRUE.

// --- ADVANCED GUIDANCE CONSTANTS ---
GLOBAL BoosterHeight IS 70.
GLOBAL LandingBurnAlt IS 1200.
GLOBAL EngineSwitchSpeed IS 60. // m/s to switch to 1 engine
// --- RECOVERY PARAMS ---
GLOBAL HoverTargetVS IS -2.0.   // Touchdown speed
GLOBAL HoverMode IS FALSE.

// PID para Throttle en Hover
GLOBAL HoverPID IS PIDLOOP(0.5, 0.2, 0.15, 0, 1). // Kp, Ki, Kd, Min, Max
SET HoverPID:SETPOINT TO HoverTargetVS.

// PIDs de Dirección (Ported from LZ - Professional Series)
GLOBAL LngCtrlPID IS PIDLOOP(0.35, 0.3, 0.25, -15, 15). 
GLOBAL LatCtrlPID IS PIDLOOP(0.25, 0.2, 0.1, -5, 5).
GLOBAL PIDFactor IS 10.

GLOBAL PositionError IS V(0,0,0).
GLOBAL FinalVec IS UP:VECTOR.
GLOBAL LandingBurnStarted IS FALSE.
GLOBAL HighHoverDone IS FALSE. 

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
SET steeringManager:maxStoppingTime TO 2.5. // Más lento/fluido
SET steeringManager:pitchTS TO 2.5.
SET steeringManager:yawTS TO 2.5.

PRINT "Esperando alineación (VANG < 10)...".
LOCAL alignStart IS TIME:SECONDS.
UNTIL FALSE {
    IF DEFINED abort_mode_active AND abort_mode_active { BREAK. }
    LOCAL boostVec IS (targetGeo:POSITION:NORMALIZED + UP:VECTOR * 0.27).
    SET guidanceSteer TO LOOKDIRUP(boostVec, SHIP:NORTH:VECTOR).
    LOCAL angErr IS VANG(SHIP:FACING:VECTOR, boostVec).
    
    PRINT "Angle Error: " + ROUND(angErr, 1) + " deg   " AT(0, 30).
    
    IF angErr < 10 { BREAK. }
    IF TIME:SECONDS > alignStart + 20 { BREAK. }
    updateTelemetry("ALIGNING").
    WAIT 0.1.
}

PRINT "Ejecutando Boostback (Guidance: Vector)...".
PRINT "Target: " + ROUND(targetGeo:LAT, 4) + ", " + ROUND(targetGeo:LNG, 4).

UNTIL FALSE {
    IF DEFINED abort_mode_active AND abort_mode_active { PRINT "ABORT: CUTTING BOOSTBACK". BREAK. }
    // 0. ACTUALIZAR OBJETIVO DINÁMICAMENTE (Seguimiento de Barcaza)
    SET targetGeo TO GetCurrentTarget().
    LOCAL horizDist TO VXCL(UP:VECTOR, targetGeo:POSITION):MAG.
    SET targetPos TO targetGeo:POSITION.

    // 1. DETERMINAR PRECISIÓN ACTUAL (Impacto vs Distancia)
    LOCAL currentAccuracy IS horizDist.
    LOCAL hasTR IS (ADDONS:TR:AVAILABLE AND ADDONS:TR:HASIMPACT).
    
    IF hasTR { SET currentAccuracy TO (ADDONS:TR:IMPACTPOS:POSITION - targetPos):MAG. }
    
    // 2. FAILSAFE: OVERSHOOT PROTECTION
    IF TIME:SECONDS > burnStartTime + 2 {
        IF currentAccuracy < bestAccuracy {
            SET bestAccuracy TO currentAccuracy.
            SET distIncreasingCount TO 0.
        } ELSE IF currentAccuracy > bestAccuracy + 100 {
            SET distIncreasingCount TO distIncreasingCount + 1.
        }
    }

    // THROTTLE TAPER: Bajar potencia si error es bajo o distancia corta
    IF currentAccuracy < 3000 OR horizDist < 3000 { LOCK THROTTLE TO 0.05. }
    ELSE IF currentAccuracy < 7000 OR horizDist < 7000 { LOCK THROTTLE TO 0.2. }
    ELSE { LOCK THROTTLE TO 1. }
    
    // 3. STEERING & TRAJECTORIES CHECK (ADVANCED ROTATION PIDs)
    LOCAL ApproachUPVector IS (targetPos - BODY:POSITION):NORMALIZED.
    LOCAL rawAppVec IS VXCL(UP:VECTOR, targetPos - SHIP:POSITION).
    LOCAL ApproachVector IS SHIP:NORTH:VECTOR.
    IF rawAppVec:MAG > 0.1 { SET ApproachVector TO rawAppVec:NORMALIZED. }

    LOCAL ErrorVector IS V(0,0,0).
    IF hasTR {
        PRINT "TR Accuracy: " + ROUND(currentAccuracy/1000, 1) + "km   " AT(0, 31).
        IF currentAccuracy < 300 { PRINT "Precision Impact Locked!". BREAK. }
        IF (bestAccuracy < 5000 OR isASDS) AND currentAccuracy > bestAccuracy + 200 {
            PRINT "TR DIVERGENCE DETECTED. CUTTING!". BREAK.
        }
        // Correct Sign: Use (Target - Impact) for rotation error
        SET ErrorVector TO targetPos - ADDONS:TR:IMPACTPOS:POSITION.
    } ELSE {
        SET ErrorVector TO VXCL(UP:VECTOR, targetPos - SHIP:POSITION).
    }

    LOCAL LatError IS VDOT(ANGLEAXIS(-90, ApproachUPVector) * ApproachVector, ErrorVector).
    LOCAL LngError IS VDOT(ApproachVector, ErrorVector).

    // PID Updates (Boostback Authority 20 deg)
    SET LngCtrlPID:MAXOUTPUT TO MAX(MIN(ABS(LngError) / 100, 20), 1).
    SET LngCtrlPID:MINOUTPUT TO -LngCtrlPID:MAXOUTPUT.
    LOCAL LngCtrl IS -LngCtrlPID:UPDATE(TIME:SECONDS, LngError).
    LOCAL LatCtrl IS -LatCtrlPID:UPDATE(TIME:SECONDS, LatError).

    // Apply Boostback Guidance (Rotation from Target Vector + Pitch Offset)
    LOCAL BaseDir IS (targetPos:NORMALIZED + UP:VECTOR * 0.27). 
    LOCAL steerVec IS BaseDir * ANGLEAXIS(-LngCtrl, LOOKDIRUP(BaseDir, UP:VECTOR):STARVECTOR) * ANGLEAXIS(LatCtrl, UP:VECTOR).
    SET guidanceSteer TO LOOKDIRUP(steerVec, SHIP:NORTH:VECTOR).

    // 4. AGGRESSIVE OVERSHOOT CUTOFF
    // ASDS: Ignoramos el límite de 100km si es un objetivo manual/vessel
    IF distIncreasingCount > 5 AND (horizDist < 100000 OR isASDS) {
        PRINT "PINPOINT OVERSHOOT CONFIRMED. CUTTING!".
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
    IF NOT hasTR AND guiDist < 5000 {
        PRINT "HORIZONTAL DISTANCE < 5km. CUTTING!".
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

// Target: Slow down to 350 m/s con GUIADO PROFESIONAL (Rotation PIDs)
UNTIL SHIP:AIRSPEED < 350 {
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
        // FINAL FIX: Use Impact - Target for corrective direction
        SET ErrorVector TO ADDONS:TR:IMPACTPOS:POSITION - targetPos.
    } ELSE {
        SET ErrorVector TO VXCL(UP:VECTOR, targetPos - SHIP:POSITION).
    }

    LOCAL LatError IS VDOT(ANGLEAXIS(-90, ApproachUPVector) * ApproachVector, ErrorVector).
    LOCAL LngError IS VDOT(ApproachVector, ErrorVector).

    // PID Updates
    SET LngCtrlPID:MAXOUTPUT TO MAX(MIN(ABS(LngError) / 50, 15), 1.0).
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
    SET targetGeo TO GetCurrentTarget(). // DYNAMIC TRACKING (Barge Hunter)
    SET targetPos TO targetGeo:POSITION. 
    SafeSetTRTarget(targetGeo).
    
    LOCAL ApproachUPVector IS (targetPos - BODY:POSITION):NORMALIZED.
    
    // SAFE NORMALIZATION
    LOCAL rawAppVec IS VXCL(UP:VECTOR, targetPos - SHIP:POSITION).
    LOCAL ApproachVector IS SHIP:NORTH:VECTOR.
    IF rawAppVec:MAG > 0.1 { SET ApproachVector TO rawAppVec:NORMALIZED. }
    
    LOCAL ErrorVector IS V(0,0,0).
    IF ADDONS:TR:AVAILABLE AND ADDONS:TR:HASIMPACT {
        // FINAL FIX: Use Impact - Target to pull nose towards error
        SET ErrorVector TO ADDONS:TR:IMPACTPOS:POSITION - targetPos.
    } ELSE {
        SET ErrorVector TO VXCL(UP:VECTOR, targetPos - SHIP:POSITION).
    }

    LOCAL LatError IS VDOT(ANGLEAXIS(-90, ApproachUPVector) * ApproachVector, ErrorVector).
    LOCAL LngError IS VDOT(ApproachVector, ErrorVector).

    // PID Updates (Authority 12 deg for aero-barge tracking)
    SET LngCtrlPID:MAXOUTPUT TO MAX(MIN(ABS(LngError) / 50, 12), 0.5).
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
    WAIT 0.05. 
}

PRINT "Powered Landing...".
// PROFESIONAL CONTROL: Lock to guidance variable immediately
LOCK STEERING TO guidanceSteer. 
UNTIL SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED" {
    // CALCULO DATOS DE VUELO (Requerido para Steering)
    SET PositionError TO targetGeo:POSITION - SHIP:POSITION.
    LOCAL CurrentHVel IS VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE).
    
    // 3. Gestión de Zonas y Hover
    // MOD: Inicio de Quemado de Aterrizaje a 6000m (Petición de Usuario)
    IF NOT LandingBurnStarted AND ALT:RADAR < 6000 {
        SET LandingBurnStarted TO TRUE.
        PRINT "Start Landing Profile (6km) - Engines Active.".
        // Actuamos C1/2/3
        // Actuamos C1/2/3 con Gimbal Limitado (40%) para estabilidad
        FOR e IN SHIP:ENGINES {
            LOCAL t IS e:TAG:TOUPPER.
            IF t = "C1" OR t = "C2" OR t = "C3" OR t = "1" OR t = "2" OR t = "3" { 
                e:ACTIVATE(). 
                IF e:HASGIMBAL { SET e:GIMBAL:LIMIT TO 40. }
            }
        }
        // Inicializamos HoverPID con GANANCIAS PROFESIONALES (Optimizado para 3 MOTORES)
        SET HoverPID:KP TO 0.6.   
        SET HoverPID:KI TO 0.3.  
        SET HoverPID:KD TO 0.8.   
        SET HoverPID:MAXOUTPUT TO 1.0.
        SET HoverPID:MINOUTPUT TO 0.0. 
    }

        // ZONA DE HOVER/FRENADO FINAL (<50m)
        // Reducido a 50m ahora que tenemos 3 motores activos
            // --- LOGICA DE DESCENTE Y HOVER (Ultra-Slow for Barge) ---
            SET targetGeo TO GetCurrentTarget(). // TRACKING
            SET targetPos TO targetGeo:POSITION.
            
            LOCAL base_alt IS MAX(0, ALT:RADAR - 4). 
            LOCAL targetVS IS -1 * (SQRT(base_alt) * 1.4 + 1.0). // Target 1m/s at deck
            
            // Overrides
            IF ALT:RADAR > 1500 { SET targetVS TO MAX(targetVS, -80). }

            IF ALT:RADAR < 2500 AND ALT:RADAR > 1500 AND NOT HighHoverDone {
                // HOVER DE ALINEACIÓN (2000m)
                LOCAL HorizError IS VXCL(UP:VECTOR, targetGeo:POSITION - SHIP:POSITION).
                IF HorizError:MAG < 10 AND SHIP:GROUNDSPEED < 2 {
                    SET HighHoverDone TO TRUE.
                    HUDTEXT("ALIGNMENT COMPLETE - RESUMING DESCENT", 5, 2, 30, GREEN, FALSE).
                } ELSE {
                    SET targetVS TO 0.0.
                    HUDTEXT("ALIGNMENT HOVER ACTIVE (" + ROUND(HorizError:MAG, 1) + "m)", 1, 2, 30, YELLOW, FALSE).
                }
            }
            
            // Touchdown logic
            IF ALT:RADAR < 50 {
                IF NOT HoverMode { 
                    PRINT "Hover Mode Active (<50m) - Target: -2 m/s".
                    SET HoverMode TO TRUE. 
                }
                SET targetVS TO -2.0.
            } 
            
            SET HoverPID:SETPOINT TO targetVS.
            LOCAL pidThrottle IS HoverPID:UPDATE(TIME:SECONDS, SHIP:VERTICALSPEED).
            LOCK THROTTLE TO MAX(0.01, pidThrottle).

            // 2. STEERING: Guía de Ultra-Precisión (Velocity-Limited Approach)
            LOCAL HorizError IS VXCL(UP:VECTOR, targetPos).
            LOCAL CurrentHVel IS VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE).
            LOCAL currentTiltLimit IS 12.0. 

            // Escalado dinámico de autoridad (Ahorro de combustible + Suavidad)
            LOCAL thrustRatio IS SHIP:THRUST / MAX(1.0, SHIP:AVAILABLETHRUST).
            LOCAL dynamicTiltMult IS 0.35 + (0.65 * thrustRatio).
            
            // --- ESTABILIZACIÓN FINAL ---
            IF ALT:RADAR < 60 { SET steeringManager:maxStoppingTime TO 1.5. }

            IF ALT:RADAR < 25 OR SHIP:AIRSPEED < 2.5 {
                 // ZONA FINAL: KILL LATERAL DRIFT (Crucial para Barcaza)
                 // Ignorar posición progresivamente para asegurar verticalidad total
                 LOCAL nudge IS -1 * (CurrentHVel * 0.45). 
                 IF nudge:MAG > TAN(4) { SET nudge TO nudge:NORMALIZED * TAN(4). } 
                 
                 IF ALT:RADAR < 5 { SET steeringManager:maxStoppingTime TO 0.6. SET guidanceSteer TO UP. }
                 ELSE { SET guidanceSteer TO LOOKDIRUP(UP:VECTOR + nudge, SHIP:NORTH:VECTOR). }
            } 
            ELSE {
                // ZONA DE APROXIMACIÓN (Velocity Limited)
                IF NOT HighHoverDone AND ALT:RADAR > 1500 { SET currentTiltLimit TO 25.0. }
                SET currentTiltLimit TO currentTiltLimit * dynamicTiltMult.

                // VELOCITY CAPPING: Target horizontal speed based on error
                LOCAL targetHVel_Mag IS MIN(8.0, HorizError:MAG * 0.12).
                LOCAL targetHVel IS HorizError:NORMALIZED * targetHVel_Mag.
                
                // Nudge points towards the target velocity
                LOCAL nudge IS (targetHVel - CurrentHVel) * 0.20. 
                
                IF nudge:MAG > TAN(currentTiltLimit) { SET nudge TO nudge:NORMALIZED * TAN(currentTiltLimit). }
                SET guidanceSteer TO LOOKDIRUP(UP:VECTOR + nudge, SHIP:NORTH:VECTOR).
            }

            // HUD Diagnostics (Precision Monitor)
            IF MOD(ROUND(TIME:SECONDS*10), 10) = 0 {
                LOCAL horizDist IS HorizError:MAG.
                PRINT "Target: " + lastTargetName + " (" + ROUND(horizDist,1) + "m)       " AT(0, 29).
                PRINT "Descent: " + ROUND(ALT:RADAR) + "m  HVel: " + ROUND(CurrentHVel:MAG,1) + "m/s TgtVS: " + ROUND(HoverPID:SETPOINT, 1) + "  " AT(0, 30).
            }
        }

    IF ALT:RADAR < 200 AND NOT GEAR { GEAR ON. PRINT "Landing Gear Deployed!". }
    
    updateTelemetry("LANDING").
    
    // DETECCION DE ATERRIZAJE ROBUSTA (KILL SWITCH)
    // 1. Status oficial "LANDED" o "SPLASHED"
    // 2. Altura de Calibración: Si estamos a menos de 1 metro de la altura donde sabemos que tocamos suelo.
    
    IF SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED" OR (ALT:RADAR < LandedAlt + 0.5) { 
        PRINT "TOUCHDOWN CONFIRMED. HARD SHUTDOWN.".
        LOCK THROTTLE TO 0. 
        FOR eng IN SHIP:ENGINES { eng:SHUTDOWN(). }
        BREAK. 
    }

    // ANTI-BOUNCE: Solo si subimos lo mas mínimo MUY cerca del suelo
    IF ALT:RADAR < LandedAlt + 3 AND SHIP:VERTICALSPEED > 0.5 {
        PRINT "BOUNCE DETECTED. KILL ENGINES.".
        LOCK THROTTLE TO 0. FOR eng IN SHIP:ENGINES { eng:SHUTDOWN(). } BREAK.
    }
    WAIT 0.05.
}

PRINT "LANDED!".
updateTelemetry("LANDED").
UNLOCK STEERING. SAS ON.
PRINT "Misión de Aterrizaje Finalizada.".
UNTIL FALSE {
    updateTelemetry("LANDED").
    WAIT 1.0.
}
