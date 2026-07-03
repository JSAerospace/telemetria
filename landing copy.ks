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

// PID para Throttle en Hover
GLOBAL HoverPID IS PIDLOOP(0.5, 0.2, 0.15, 0, 1). // Kp, Ki, Kd, Min, Max
SET HoverPID:SETPOINT TO HoverTargetVS.

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
SET steeringManager:maxStoppingTime TO 2.5. // Más lento/fluido
SET steeringManager:pitchTS TO 2.5.
SET steeringManager:yawTS TO 2.5.

PRINT "Esperando alineación (HEADING)...".
LOCAL alignStart IS TIME:SECONDS.
UNTIL FALSE {
    // MOD: Usamos HEADING para un giro más estable y directo al objetivo
    LOCAL targetH IS targetGeo:HEADING.
    SET guidanceSteer TO LOOKDIRUP(HEADING(targetH, 5):VECTOR, SHIP:NORTH:VECTOR).
    
    LOCAL angErr IS VANG(SHIP:FACING:VECTOR, HEADING(targetH, 5):VECTOR).
    PRINT "Angle Error: " + ROUND(angErr, 1) + " deg   " AT(0, 30).
    
    IF angErr < 10 { BREAK. }
    IF TIME:SECONDS > alignStart + 15 { BREAK. }
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
    SetPhysicsRange(2500000). // CRITICO: Mantener carga RSS en boostback
    
    // Actualizar target en Trajectories de forma segura
    SafeSetTRTarget(targetGeo).
    
    // 1. DETERMINAR PRECISIÓN ACTUAL (Impacto vs Distancia)
    LOCAL currentAccuracy IS guiDist.
    LOCAL hasTR IS (ADDONS:TR:AVAILABLE AND ADDONS:TR:HASIMPACT).
    
    IF hasTR { SET currentAccuracy TO (ADDONS:TR:IMPACTPOS:POSITION - targetGeo:POSITION):MAG. }
    
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
        LOCAL impactPos IS ADDONS:TR:IMPACTPOS.
        PRINT "TR Accuracy: " + ROUND(currentAccuracy/1000, 1) + "km   " AT(0, 31).
        
        // Cortar si estamos muy cerca - Ajustado para RTLS y LZ Precision
        LOCAL cutoffDist IS 100.  
        IF isLZ { SET cutoffDist TO 30. } // MODO LZ: Queremos trayectoria casi perfecta antes de apagar
        ELSE IF isASDS { SET cutoffDist TO 50. }  
        IF currentAccuracy < cutoffDist { 
            PRINT "Precision Impact Locked (" + ROUND(cutoffDist) + "m)!". 
            BREAK. 
        }
        
        // DIVERGENCIA: Si el error empieza a subir (Signo claro de que hemos pasado el objetivo)
        // Aumentado tolerancia de 150m a 500m para evitar cortes prematuros
        IF (bestAccuracy < 5000 OR isASDS) AND currentAccuracy > bestAccuracy + 500 {
            PRINT "TR DIVERGENCE DETECTED (" + ROUND(currentAccuracy - bestAccuracy) + "m). CUTTING!". 
            BREAK.
        }

        // Ajuste dinámico de dirección durante el quemado
        LOCAL impactErrVec IS VXCL(UP:VECTOR, impactPos:POSITION - targetGeo:POSITION).
        LOCAL steerVec TO (targetGeo:POSITION:NORMALIZED + UP:VECTOR * 0.27 - impactErrVec * 0.03):NORMALIZED.
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
    
    // VERIFICACIÓN DE DIRECCIÓN (Anti-Reversa)
    IF TIME:SECONDS > burnStartTime + 5 AND distIncreasingCount > 5 {
        HUDTEXT("!!! DIRECTION ERROR DETECTED - FLIPPING !!!", 5, 2, 35, RED, TRUE).
        // Si nos alejamos, el vector de empuje está invertido
        SET steerVec TO (targetGeo:POSITION:NORMALIZED * -1 + UP:VECTOR * 0.25):NORMALIZED.
        SET guidanceSteer TO LOOKDIRUP(steerVec, SHIP:NORTH:VECTOR).
    }

    // 4. AGGRESSIVE OVERSHOOT CUTOFF
    // Aumentado de 5 a 10 ciclos para evitar falsos positivos
    // ASDS: Ignoramos el límite de 100km si es un objetivo manual/vessel
    IF distIncreasingCount > 10 AND (guiDist < 100000 OR isASDS) {
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

// Target: Slow down to 100 m/s con GUIADO POR IMPACTO (BALANCEADO)
UNTIL SHIP:AIRSPEED < 100 {
    // Errores de navegación basados en IMPACTO
    LOCAL HorizError IS VXCL(UP:VECTOR, targetGeo:POSITION).
    LOCAL CurrentHVel IS VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE).
    
    // Calcular error de impacto real
    LOCAL ErrorVector IS HorizError.
    IF ADDONS:TR:AVAILABLE {
        SafeSetTRTarget(targetGeo).
        IF ADDONS:TR:HASIMPACT {
            SET ErrorVector TO VXCL(UP:VECTOR, ADDONS:TR:IMPACTPOS:POSITION - targetGeo:POSITION).
        }
    }
    
    // Guiado PD durante Entry Burn (Ganancias Balanceadas v2.0)
    LOCAL GuidanceErr IS (ErrorVector * 0.008) - (CurrentHVel * 0.025).
    
    // Vector de dirección final
    LOCAL FinalSteer IS SRFRETROGRADE:VECTOR:NORMALIZED + GuidanceErr. 
    
    // Limitar inclinación a 15 grados para mayor alcance
    IF VANG(SRFRETROGRADE:VECTOR, FinalSteer) > 15 {
        SET FinalSteer TO SRFRETROGRADE:VECTOR:NORMALIZED + VXCL(SRFRETROGRADE:VECTOR, FinalSteer):NORMALIZED * TAN(15).
    }

    SET guidanceSteer TO LOOKDIRUP(FinalSteer, SHIP:NORTH:VECTOR).
    
    updateTelemetry("ENTRY BURN").
    WAIT 0.1.
}
LOCK THROTTLE TO 0.

PRINT "Atmospheric Descent...".
UNTIL SHIP:ALTITUDE < 8000 {
    SetPhysicsRange(2500000). // CRITICO: Mantener carga RSS en descenso
    
    // Actualizar target en Trajectories de forma segura
    SafeSetTRTarget(targetGeo).
    
    LOCAL HorizError IS VXCL(UP:VECTOR, targetGeo:POSITION).
    LOCAL CurrentHVel IS VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE).
    
    // Calcular error de impacto real para rejillas (BALANCEADO v2.0)
    LOCAL ErrorVector IS HorizError.
    IF ADDONS:TR:AVAILABLE {
        ADDONS:TR:SETTARGET(targetGeo).
        IF ADDONS:TR:HASIMPACT {
            SET ErrorVector TO VXCL(UP:VECTOR, ADDONS:TR:IMPACTPOS:POSITION - targetGeo:POSITION).
        }
    }

    // MEZCLA CON RETROGRADE: A medida que el error baja de 500m, forzar retrograde
    // Esto reduce el ángulo de ataque final y evita oscilaciones de corrección
    LOCAL mixRetro IS MAX(0, MIN(1, 1 - (ErrorVector:MAG / 500))).
    
    // Guiado PD con mezcla progresiva a retrograde (Gains Balanceados)
    LOCAL GuidanceErr IS (ErrorVector * 0.012) - (CurrentHVel * 0.035).
    
    // Cap de 15 grados para mayor autoridad
    IF GuidanceErr:MAG > TAN(15) { SET GuidanceErr TO GuidanceErr:NORMALIZED * TAN(15). }
    
    // Vector base con corrección
    // FIX DIRECCIÓN: Signo cambiado de - a + para apuntar correctamente
    LOCAL BaseSteerVec IS SRFRETROGRADE:VECTOR + GuidanceErr.
    
    // Interpolar: De corrección a Retrograde puro cuando cerca del target
    LOCAL FinalSteerVec IS BaseSteerVec:NORMALIZED * (1 - mixRetro) + SRFRETROGRADE:VECTOR:NORMALIZED * mixRetro.
    
    SET guidanceSteer TO LOOKDIRUP(FinalSteerVec, SHIP:NORTH:VECTOR).
    
    updateTelemetry("DESCENT").
    WAIT 1.0.
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
    SET PositionError TO targetGeo:POSITION - SHIP:POSITION.
    LOCAL CurrentHVel IS VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE).
    
    // ESCALADO DINÁMICO DE AUTORIDAD (Ahorro de Combustible + Reach)
    LOCAL thrustRatio IS SHIP:THRUST / MAX(0.1, SHIP:AVAILABLETHRUST).
    LOCAL dynamicTiltMult IS 0.4 + (0.6 * thrustRatio).
    IF isLZ { SET dynamicTiltMult TO 1.0. } // MODO LZ: Autoridad total siempre para buscar el pad
    
    // 3. Gestión de Zonas y Hover
    // MOD: Inicio de Quemado de Aterrizaje a 6000m (Petición de Usuario)
    IF NOT LandingBurnStarted AND ALT:RADAR < 6000 {
        SET LandingBurnStarted TO TRUE.
        PRINT "Start Landing Profile (6km) - Engines Active.".
        // Actuamos C1/2/3 con Gimbal Limitado (40%) para estabilidad
        FOR e IN SHIP:ENGINES {
            LOCAL t IS e:TAG:TOUPPER.
            IF t = "C1" OR t = "C2" OR t = "C3" OR t = "1" OR t = "2" OR t = "3" { 
                e:ACTIVATE(). 
                IF e:HASGIMBAL { SET e:GIMBAL:LIMIT TO 40. }
            }
        }
        // Inicializamos HoverPID con GANANCIAS AGRESIVAS
        SET HoverPID:KP TO 0.8.   
        SET HoverPID:KI TO 0.25.  
        SET HoverPID:KD TO 0.5.   
        SET HoverPID:MAXOUTPUT TO 1.0.
        SET HoverPID:MINOUTPUT TO 0.0. 
    }

    IF LandingBurnStarted {
        SetPhysicsRange(2500000). // CRITICO: Mantener carga RSS en landing
        
        // Actualizar target en Trajectories de forma segura
        SafeSetTRTarget(targetGeo).
        
        LOCAL modeText IS "BARGE (ASDS)".
        IF isLZ { SET modeText TO "LANDING ZONE (RTLS)". }
        PRINT "Landing Mode: " + modeText + "      " AT (0, 28).
        
        // --- CALCULO DE ERROR DE IMPACTO (MOVIDO AL INICIO PARA LOGICA DE HOVER) ---
        LOCAL HorizError IS VXCL(UP:VECTOR, targetGeo:POSITION).
        LOCAL currentHVel IS VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE).
        LOCAL ImpactOffset IS HorizError:MAG.
        IF ADDONS:TR:AVAILABLE AND ADDONS:TR:HASIMPACT {
            LOCAL ImpactPos IS ADDONS:TR:IMPACTPOS:POSITION.
            LOCAL ImpactVec IS VXCL(UP:VECTOR, ImpactPos - targetGeo:POSITION).
            SET ImpactOffset TO ImpactVec:MAG.
        }
        
            // 1. THROTTLE: Gestión de Hover y Descenso Vertical
            LOCAL pidThrottle IS HoverPID:UPDATE(TIME:SECONDS, SHIP:VERTICALSPEED).
            
            IF ALT:RADAR < 50 {
                IF NOT HoverMode { 
                    PRINT "Hover Mode Active (<50m) - Target: -2 m/s".
                    SET HoverMode TO TRUE. 
                    SET HoverPID:SETPOINT TO -2.0. // Target Base: 2 m/s
                }
                
                // --- LOGICA DE HOVER DE PRECISIÓN (SALTO FINAL & RECUPERACIÓN) ---
                // REGLA DE ORO: No hover por debajo de 15m para evitar "volver a despegar" o quedarse colgado
                // MOD: Si estamos por debajo de 15m, forzamos el aterrizaje
                IF ALT:RADAR < 15 {
                    SET HoverPID:SETPOINT TO -2.0.
                }
                // MOD: El rango de hover de recuperación ahora es de 150m a 15m (500m para LZ)
                 LOCAL hoverFloor IS 150.
                 IF isLZ { SET hoverFloor TO 500. }
                 
                 IF ALT:RADAR < hoverFloor AND ALT:RADAR >= 15 {
                    LOCAL hoverTrigger IS 5.0.
                    IF ALT:RADAR > 40 { SET hoverTrigger TO 12.0. } 
                    
                    LOCAL errorToUse IS ImpactOffset.
                    IF isLZ { SET errorToUse TO HorizError:MAG. } // LZ prioritiza DISTANCIA REAL
                    
                    IF errorToUse > hoverTrigger {
                        // BRANCH: Perfil de velocidad en hover según el modo
                        LOCAL recoveryVS IS -0.8. // Antes -1.5 (Barge) - Suavizado para dar tiempo
                        IF isLZ { SET recoveryVS TO 0.0. } // LZ: Hover puro (0m/s)
                        
                        IF HoverPID:SETPOINT <> recoveryVS {
                            SET HoverPID:SETPOINT TO recoveryVS.
                            LOCAL msg IS "RECOVERY DESCENT (-0.8m/s)".
                            IF isLZ { SET msg TO "RECOVERY HOVER (0m/s)". }
                            HUDTEXT(msg + " | OFFSET " + ROUND(errorToUse, 1) + "m", 2, 2, 20, CYAN, FALSE).
                        }
                    } ELSE {
                        LOCAL centerThreshold IS 3.0.
                        IF isLZ { SET centerThreshold TO 0.5. } // LZ: No bajar hasta estar a <0.5m
                        
                        IF errorToUse < centerThreshold {
                            LOCAL descentVS IS -2.5.
                            IF isLZ { SET descentVS TO -2.0. }
                            
                            IF HoverPID:SETPOINT <> descentVS {
                                SET HoverPID:SETPOINT TO descentVS. 
                                HUDTEXT("CENTERED - RESUMING DESCENT (" + descentVS + "m/s)", 2, 2, 20, GREEN, FALSE).
                            }
                        }
                    }
                } 
                ELSE IF ALT:RADAR < 15 {
                    // Refuerzo de seguridad para descenso final
                    SET HoverPID:SETPOINT TO -2.0.
                }
                
                // --- CORTE ABSOLUTO FINAL (<2m) ---
                // Previene que el PID intente compensar el peso al tocar
                IF ALT:RADAR < LandedAlt + 2 {
                    LOCK THROTTLE TO 0.
                } ELSE {
                    LOCK THROTTLE TO pidThrottle.
                }
            } 
            ELSE {
                // BRANCH: Perfil de velocidad vertical según el modo
                LOCAL vsRatio IS 15.
                LOCAL vsFloor IS 3.
                IF isLZ { SET vsRatio TO 16. SET vsFloor TO 2.8. } // Ajustado LZ para mayor precisión
                
                LOCAL targetVS IS -1 * (ALT:RADAR / vsRatio + vsFloor).
                SET HoverPID:SETPOINT TO targetVS.
                LOCK THROTTLE TO MAX(0.01, pidThrottle).
            }

            // 2. STEERING: Guía de Precisión (4 Etapas) - Ejecuta SIEMPRE hasta 10m
            LOCAL currentTiltLimit IS 0.

             IF ALT:RADAR < 10 {
                 // ZONA 4: ATERRIZAJE VERTICAL FINAL (<10m) - ACTIVAMENTE CANCELANDO VELOCIDAD LATERAL
                 IF steeringManager:maxStoppingTime <> 0.9 {
                     HUDTEXT("10m - BULLSEYE LOCK (ACTIVE HVEL CANCEL)", 2, 2, 20, YELLOW, FALSE).
                     SET steeringManager:maxStoppingTime TO 0.9. 
                 }
                 
                  // En lugar de UP puro, cancelamos activamente la velocidad horizontal remanente
                  // MOD: Damping aumentado a -0.8 para asegurar aterrizaje vertical
                  LOCAL nudge IS (currentHVel * -0.8). 
                  
                  // LZ: Añadir corrección al pad incluso en el tramo final
                  IF isLZ AND HorizError:MAG > 0.5 {
                      LOCAL padPull IS VXCL(UP:VECTOR, targetGeo:POSITION - SHIP:POSITION):NORMALIZED * 0.5.
                      SET nudge TO nudge + padPull.
                  }
                  
                  // Límite de 5 grados para centrado final (Barge), 12 grados para LZ
                  LOCAL finalLimit IS 5.
                  IF isLZ { SET finalLimit TO 12. }
                  IF nudge:MAG > TAN(finalLimit) { SET nudge TO nudge:NORMALIZED * TAN(finalLimit). }
                  
                  SET guidanceSteer TO LOOKDIRUP(UP:VECTOR + nudge, HEADING(90,0):VECTOR).
             } 
             ELSE IF ALT:RADAR < 60 {
                 // ZONA 3: BULLSEYE PUSH (10m - 60m)
                 SET currentTiltLimit TO 12.0. 
                 IF isLZ { SET currentTiltLimit TO 18.0. } // MODO LZ: Más autoridad
                 
                 LOCAL TargetDir IS VXCL(UP:VECTOR, targetGeo:POSITION - SHIP:POSITION):NORMALIZED.
                 LOCAL HSpeed IS currentHVel:MAG.
                 
                 LOCAL DesiredVel IS V(0,0,0).
                 
                 // Si el error es grande, corregir con potencia
                 LOCAL errorToUse IS ImpactOffset.
                 IF isLZ { SET errorToUse TO HorizError:MAG. } // LZ prioritiza DISTANCIA REAL
                 
                 IF errorToUse > 10 {
                     LOCAL corrSpeed IS MAX(1.0, errorToUse * 0.15). 
                     LOCAL maxCorr IS 6.0.
                     IF isLZ { SET maxCorr TO 10.0. } // Mayor alcance lateral para LZ
                     SET corrSpeed TO MIN(corrSpeed, maxCorr). 
                     SET DesiredVel TO TargetDir * corrSpeed.
                 } ELSE {
                     SET DesiredVel TO V(0,0,0).
                 }
                 
                 LOCAL VelError IS DesiredVel - CurrentHVel.
                 
                 // Ganancia moderada para cerrar el gap
                 LOCAL corrGain IS 0.25.
                 IF isLZ { SET corrGain TO 0.4. } // LZ: Reacción más rápida
                 IF HSpeed > 10 { SET corrGain TO 0.5. }
                 
                 LOCAL CorrectionVec IS VelError * corrGain.
                 LOCAL RawSteering IS UP:VECTOR + CorrectionVec.
                 
                 IF VANG(UP:VECTOR, RawSteering) > currentTiltLimit {
                     LOCAL HorizPart IS VXCL(UP:VECTOR, RawSteering):NORMALIZED.
                     SET RawSteering TO UP:VECTOR + HorizPart * TAN(currentTiltLimit).
                 }
                 
                 SET guidanceSteer TO LOOKDIRUP(RawSteering, HEADING(90,0):VECTOR).
                 
                 IF steeringManager:maxStoppingTime <> 1.5 {
                    HUDTEXT("60m - PRECISION REACH", 2, 2, 20, WHITE, FALSE).
                    SET steeringManager:maxStoppingTime TO 1.5.
                 }
             }
            ELSE IF ALT:RADAR < 250 {
                 // ZONA 2: PRECISIÓN FINAL (60m - 250m)
                 SET currentTiltLimit TO 15.0 * dynamicTiltMult. 
                 IF isLZ { SET currentTiltLimit TO 18.0. } // LZ: Sin limitador dinámico
                 
                 IF steeringManager:maxStoppingTime <> 0.8 {
                    HUDTEXT("250m - WAYPOINT PRECISION", 2, 2, 20, GREEN, FALSE).
                    SET steeringManager:maxStoppingTime TO 0.8.
                 }
                 
                 // Usar punto de impacto si disponible
                 LOCAL TargetDir IS VXCL(UP:VECTOR, targetGeo:POSITION - SHIP:POSITION):NORMALIZED.
                 LOCAL DesiredVel IS V(0,0,0).
                 
                 LOCAL errorToUse IS ImpactOffset.
                 IF isLZ { SET errorToUse TO HorizError:MAG. } // LZ prioritiza DISTANCIA REAL
                 
                 IF errorToUse > 10 {
                     LOCAL maxSpeed IS MIN(10.0, errorToUse * 0.2).
                     SET DesiredVel TO TargetDir * maxSpeed.
                 }
                 
                 LOCAL VelError IS DesiredVel - CurrentHVel.
                 LOCAL nudgeGain IS 0.4.
                 IF isLZ { SET nudgeGain TO 0.7. } // BULLSEYE LOCK LZ
                 LOCAL nudge IS VelError * nudgeGain. 
                 
                 IF nudge:MAG > TAN(currentTiltLimit) { SET nudge TO nudge:NORMALIZED * TAN(currentTiltLimit). }
                 SET guidanceSteer TO LOOKDIRUP(UP:VECTOR + nudge, SHIP:NORTH:VECTOR).
            }
            ELSE {
                // ZONA 1: CENTRADO INICIAL (>250m)
                // EFICIENCIA/ALCANCE: Inclinación adaptativa según altura
                IF ALT:RADAR > 1000 { 
                    SET currentTiltLimit TO 10.0. // Aumentado para corregir desde lejos
                } ELSE { 
                    SET currentTiltLimit TO 12.0. // Aumentado de 8.0
                }
                
                // MOD: Si estamos en RECOVERY HOVER (VS ~ 0), permitimos más autoridad para llegar
                IF ABS(SHIP:VERTICALSPEED) < 0.5 AND ImpactOffset > 10 {
                    SET currentTiltLimit TO 12.0.
                    HUDTEXT("EMERGENCY RECOVERY: MAX AUTHORITY (12°)", 1, 2, 30, YELLOW, FALSE).
                }

                // Aplicar multiplicador dinámico por empuje
                SET currentTiltLimit TO currentTiltLimit * dynamicTiltMult.

                // Ganancias suavizadas para evitar maniobras bruscas e ineficientes
                LOCAL nudge IS (HorizError * 0.015) - (CurrentHVel * 0.1).
                IF nudge:MAG > TAN(currentTiltLimit) { SET nudge TO nudge:NORMALIZED * TAN(currentTiltLimit). }
                
                // --- IGNITION SAFEGUARD (6km) ---
                // MOD: No permitimos inclinación hasta que los motores tengan empuje real (>10%)
                // Esto evita que el cohete "caiga" de lado durante el spool-up de RSS
                IF SHIP:THRUST < (SHIP:AVAILABLETHRUST * 0.1) {
                    SET guidanceSteer TO LOOKDIRUP(SRFRETROGRADE:VECTOR, SHIP:NORTH:VECTOR).
                    HUDTEXT("WAITING FOR THRUST (VERTICAL LOCK)", 1, 2, 20, YELLOW, FALSE).
                } ELSE {
                    SET guidanceSteer TO LOOKDIRUP(UP:VECTOR + nudge, SHIP:NORTH:VECTOR).
                }
            }
            
            // Telemetría de precisión en HUD cada segundo
            IF MOD(ROUND(TIME:SECONDS*10), 10) = 0 {
                LOCAL horizDist IS VXCL(UP:VECTOR, targetGeo:POSITION):MAG.
                PRINT "Target: " + lastTargetName + "                    " AT(0, 29).
                PRINT "Descent: " + ROUND(ALT:RADAR) + "m  Dist: " + ROUND(horizDist) + "m  ImpOff: " + ROUND(ImpactOffset, 1) + "m  " AT(0, 30).
            }
        }

    IF ALT:RADAR < 200 AND NOT GEAR { GEAR ON. PRINT "Landing Gear Deployed!". }
    
    updateTelemetry("LANDING").
    
    // DETECCION DE ATERRIZAJE ROBUSTA (KILL SWITCH)
    // 1. Status oficial "LANDED" o "SPLASHED"
    // 2. Altura de Calibración: Si estamos a menos de 0.3m del suelo (reducido de 0.5 para precisión)
    // 3. Velocidad Vertical Positiva (Bounce) cerca del suelo
    
    LOCAL isGrounded IS (SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED").
    LOCAL isAtLandedAlt IS (ALT:RADAR < LandedAlt + 0.3).
    LOCAL isBouncing IS (ALT:RADAR < LandedAlt + 2 AND SHIP:VERTICALSPEED > 0.2).

    IF isGrounded OR isAtLandedAlt OR isBouncing { 
        PRINT "TOUCHDOWN/BOUNCE DETECTED. HARD SHUTDOWN.".
        IF isGrounded { PRINT "Status: LANDED". }
        IF isAtLandedAlt { PRINT "Radar: AT TARGET ALT". }
        IF isBouncing { PRINT "Velocity: BOUNCE DETECTED (" + ROUND(SHIP:VERTICALSPEED, 2) + ")". }
        
        LOCK THROTTLE TO 0. 
        SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
        FOR eng IN SHIP:ENGINES { eng:SHUTDOWN(). }
        WAIT 0.1.
        UNLOCK THROTTLE. // Liberar control para KSP oficial
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
FOR eng IN SHIP:PARTSTAGGED("1") { eng:SHUTDOWN(). }
PRINT "Motor Central Apagado. Fin de Misión.".
