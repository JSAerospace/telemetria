// ============================================================
// JS AEROSPACE — TOMCATHEAVY SHIP SOFTWARE v2.0
// Segunda Etapa: Ascenso, Circularización, Telemetría Pro
// Compatibilidad: RSS / KSRSS / Stock Kerbin
// ============================================================

// --- FÍSICA RANGE (Mantener contacto con booster) ---
// --- FÍSICA RANGE (Extensión para no perder el booster) ---
FUNCTION SetPhysicsRange {
    PARAMETER d.
    // Aplicar a la nave activa (Ship)
    SET SHIP:LOADDISTANCE:FLYING:UNLOAD TO d.
    SET SHIP:LOADDISTANCE:FLYING:LOAD TO d * 0.95.
    SET SHIP:LOADDISTANCE:FLYING:PACK TO d * 0.99.
    SET SHIP:LOADDISTANCE:FLYING:UNPACK TO d * 0.94.
    
    SET SHIP:LOADDISTANCE:SUBORBITAL:UNLOAD TO d.
    SET SHIP:LOADDISTANCE:SUBORBITAL:LOAD TO d * 0.95.
    SET SHIP:LOADDISTANCE:SUBORBITAL:PACK TO d * 0.99.
    SET SHIP:LOADDISTANCE:SUBORBITAL:UNPACK TO d * 0.94.

    SET SHIP:LOADDISTANCE:ORBIT:UNLOAD TO d.
    SET SHIP:LOADDISTANCE:ORBIT:LOAD TO d * 0.95.
    SET SHIP:LOADDISTANCE:ORBIT:PACK TO d * 0.99.
    SET SHIP:LOADDISTANCE:ORBIT:UNPACK TO d * 0.94.

    // Aplicar a los valores globales del universo de KSP
    SET KUNIVERSE:DEFAULTLOADDISTANCE:FLYING:UNLOAD TO d.
    SET KUNIVERSE:DEFAULTLOADDISTANCE:FLYING:LOAD TO d * 0.95.
    SET KUNIVERSE:DEFAULTLOADDISTANCE:SUBORBITAL:UNLOAD TO d.
    SET KUNIVERSE:DEFAULTLOADDISTANCE:SUBORBITAL:LOAD TO d * 0.95.
    SET KUNIVERSE:DEFAULTLOADDISTANCE:ORBIT:UNLOAD TO d.
    SET KUNIVERSE:DEFAULTLOADDISTANCE:ORBIT:LOAD TO d * 0.95.

    WAIT 0.1.
    PRINT "PHYSICS BUBBLE EXTENDED TO " + (d/1000) + "KM" AT (0, 1).
}
SetPhysicsRange(2500000).
SAS OFF.

// ============================================================
// === 1. DETECCIÓN DE ENTORNO (RSS / KSRSS / STOCK) ===
// ============================================================
GLOBAL RSS IS (BODY:RADIUS > 3000000).
GLOBAL KSRSS IS (BODY:RADIUS > 1000000 AND NOT RSS).
GLOBAL STOCK IS (NOT RSS AND NOT KSRSS).

// Parámetros según entorno
GLOBAL AtmoLimit IS 0.
GLOBAL PitchStartAlt IS 0.
GLOBAL PitchEndAlt IS 0.
GLOBAL TargetApoDefault IS 0.

IF RSS {
    SET AtmoLimit TO 140000.
    SET PitchStartAlt TO 20000.
    SET PitchEndAlt TO 120000.
    SET TargetApoDefault TO 230000.
    HUDTEXT("ENV: RSS/RO Detected", 5, 2, 20, YELLOW, FALSE).
} ELSE IF KSRSS {
    SET AtmoLimit TO 100000.
    SET PitchStartAlt TO 10000.
    SET PitchEndAlt TO 80000.
    SET TargetApoDefault TO 130000.
    HUDTEXT("ENV: KSRSS Detected", 5, 2, 20, YELLOW, FALSE).
} ELSE {
    SET AtmoLimit TO 70000.
    SET PitchStartAlt TO 8000.
    SET PitchEndAlt TO 60000.
    SET TargetApoDefault TO 100000.
    HUDTEXT("ENV: Stock Kerbin Detected", 5, 2, 20, CYAN, FALSE).
}

// ============================================================
// === 2. STEERING MANAGER PRO (Starship Style) ===
// ============================================================
SET STEERINGMANAGER:MAXSTOPPINGTIME TO 5.0.
SET STEERINGMANAGER:PITCHPID:KD TO 2.0.
SET STEERINGMANAGER:YAWPID:KD TO 2.0.
SET STEERINGMANAGER:ROLLPID:KD TO 1.5.
SET STEERINGMANAGER:PITCHTORQUEFACTOR TO 0.75.
SET STEERINGMANAGER:YAWTORQUEFACTOR TO 0.75.
SET STEERINGMANAGER:ROLLTORQUEFACTOR TO 0.75.

// ============================================================
// === 3. VARIABLES DE MISIÓN ===
// ============================================================
GLOBAL targetApo IS TargetApoDefault.
GLOBAL targetHeading IS 90.
GLOBAL initialParts IS SHIP:PARTS:LENGTH.
GLOBAL fairingTriggered IS FALSE.
GLOBAL fairingTime IS 0.
GLOBAL missionPhase IS "STARTUP".

// --- GUI GLOBALS ---
GLOBAL guiObj IS 0.
GLOBAL guiOpen IS FALSE.
GLOBAL mission_status IS "COASTING".

// ============================================================
// === 4. TELEMETRÍA PRO — Función LogS2 ===
// ============================================================
GLOBAL ship_telemetry_toggle IS TRUE.

FUNCTION LogS2 {
    PARAMETER phase.
    LOCAL fuelAct IS 0. LOCAL fuelCap IS 1.
    FOR p IN SHIP:PARTS {
        FOR r IN p:RESOURCES {
            SET fuelAct TO fuelAct + r:AMOUNT.
            SET fuelCap TO fuelCap + r:CAPACITY.
        }
    }
    LOCAL fuelPct IS ROUND((fuelAct / MAX(1, fuelCap)) * 100, 1).

    LOCAL engStates IS LEXICON().
    FOR tag IN LIST("S1","S2") {
        LOCAL foundOn IS FALSE.
        FOR e IN SHIP:ENGINES {
            IF e:TAG:TOUPPER = tag AND e:IGNITION AND THROTTLE > 0 { SET foundOn TO TRUE. }
        }
        engStates:ADD(tag, 1 IF foundOn ELSE 0).
    }

    LOCAL data IS LEXICON(
        "status", phase,
        "alt", ROUND(SHIP:ALTITUDE, 0),
        "apo", ROUND(SHIP:APOAPSIS, 0),
        "peri", ROUND(SHIP:PERIAPSIS, 0),
        "vs", ROUND(SHIP:VERTICALSPEED, 1),
        "spd", ROUND(SHIP:VELOCITY:SURFACE:MAG, 1),
        "fuel", fuelPct,
        "throttle", ROUND(THROTTLE * 100, 0),
        "twr", ROUND(SHIP:MAXTHRUST / MAX(0.1, SHIP:MASS * 9.805), 2),
        "missiontime", ROUND(MISSIONTIME, 0),
        "time", ROUND(MISSIONTIME, 0),
        "engStates", engStates
    ).
    IF ship_telemetry_toggle {
        WRITEJSON(data, "0:/telemetry_ship_A.json").
    } ELSE {
        WRITEJSON(data, "0:/telemetry_ship_B.json").
    }
    SET ship_telemetry_toggle TO NOT ship_telemetry_toggle.
    SET missionPhase TO phase.
}

// ============================================================
// === 5. ESPERAR CONFIG DEL BOOSTER ===
// ============================================================
PRINT "Sincronizando con Booster...".
WAIT UNTIL EXISTS("0:/tomcat_config.json").
LOCAL mConfig IS READJSON("0:/tomcat_config.json").
SET targetApo TO mConfig["apo"].
IF targetApo < 10000 { SET targetApo TO targetApo * 1000. }
SET targetHeading TO mConfig["head"].
PRINT "Config OK: Apo=" + ROUND(targetApo/1000, 1) + "km | Head=" + targetHeading.
HUDTEXT("S2 CONFIG OK: " + ROUND(targetApo/1000) + "km x " + targetHeading + "deg", 5, 2, 25, GREEN, FALSE).

// ============================================================
// === 6. COLD STAGING (Cold Edition) ===
// ============================================================
PRINT "Esperando Separacion de Etapas (AG7)...".
LogS2("STAGING STANDBY").
WAIT UNTIL AG7.

HUDTEXT("SEPARACION INICIADA — ESPERANDO 3s PARA IGNICION S2", 5, 2, 30, YELLOW, FALSE).
PRINT "Separacion iniciada. Esperando 3 segundos...".
LogS2("COLD STAGING WAIT").

// Esperar 3 segundos para que el booster se aleje de forma segura
WAIT 3.0.

HUDTEXT("IGNICION SEGUNDA ETAPA", 5, 2, 30, GREEN, FALSE).
PRINT "Encendiendo motores S2...".
LogS2("ASCENT").

// Ignición
AG1 ON.
LOCK THROTTLE TO 1.0.
FOR e IN SHIP:ENGINES {
    IF e:TAG:TOUPPER = "S1" OR e:TAG:TOUPPER = "S2" {
        e:ACTIVATE().
    }
}
WAIT 0.5.

// ============================================================
// === 7. ASCENSO AUTÓNOMO (Curva de Gravedad Dinámica Pro) ===
// ============================================================
LOCAL ascentDone IS FALSE.

UNTIL ascentDone {
    LogS2("ASCENT").

    // --- Curva de Gravedad Dinámica ---
    // Basada en altitud: pitch de 90° (vertical) a 0° (horizontal)
    LOCAL targetPitch IS 90.
    IF SHIP:ALTITUDE > PitchStartAlt AND SHIP:ALTITUDE < PitchEndAlt {
        // Curva suavizada (coseno) para transición más natural
        LOCAL t IS (SHIP:ALTITUDE - PitchStartAlt) / (PitchEndAlt - PitchStartAlt).
        SET targetPitch TO 90 * (1 - t)^0.7.
    } ELSE IF SHIP:ALTITUDE >= PitchEndAlt {
        SET targetPitch TO 0.
    }

    // Ajuste fino: reducir pitch aún más si ya estamos cerca del apoapsis objetivo
    IF SHIP:APOAPSIS > targetApo * 0.8 AND SHIP:ALTITUDE > PitchStartAlt {
        SET targetPitch TO MIN(targetPitch, 5).
    }

    LOCK STEERING TO HEADING(targetHeading, targetPitch, 0).
    LOCK THROTTLE TO 1.0.

    // --- TRIGGER DE COFIA ---
    IF NOT fairingTriggered AND SHIP:ALTITUDE > (AtmoLimit * 0.93) {
        SET fairingTriggered TO TRUE.
        AG3 ON.
        WAIT 0.1.
        AG1 ON. // Escudo de re-ignición
        SET fairingTime TO TIME:SECONDS.
        HUDTEXT("FAIRING SEPARATION", 5, 2, 30, GREEN, FALSE).
        PRINT "COFIA SEPARADA.".
        LogS2("FAIRING SEP").
    }

    // --- CORTE DE MOTOR (10km antes del apo) ---
    LOCAL stabilityCheck IS (NOT fairingTriggered OR TIME:SECONDS > fairingTime + 2).
    IF SHIP:APOAPSIS >= (targetApo - 10000) AND stabilityCheck {
        SET ascentDone TO TRUE.
    }

    // Telemetría en terminal cada 5s
    IF MOD(ROUND(TIME:SECONDS), 5) = 0 {
        PRINT ("Apo: " + ROUND(SHIP:APOAPSIS/1000,1) + "km | Alt: " + ROUND(SHIP:ALTITUDE/1000,1) +
               "km | Pitch: " + ROUND(targetPitch,1) + "deg | Thr: " + ROUND(THROTTLE*100) + "%    ") AT (0, 14).
    }

    SetPhysicsRange(2500000). // Mantener cargado el booster durante el ascenso
    WAIT 0.1.
}

// ============================================================
// === 8. MECO (Corte de Motor — Main Engine Cut-Off) ===
// ============================================================
LOCK THROTTLE TO 0.
AG4 ON.
FOR e IN SHIP:ENGINES { e:SHUTDOWN(). }
HUDTEXT("MECO — COASTING TO APOAPSIS", 5, 2, 30, RED, FALSE).
PRINT "MECO. Costa hacia Apoapsis.".
LogS2("MECO").

WAIT 1.
AG4 OFF.

// ============================================================
// === 9. COSTA HASTA APOAPSIS ===
// ============================================================
// Esperar a salir de la atmósfera
UNTIL SHIP:ALTITUDE > AtmoLimit {
    SetPhysicsRange(2500000).
    WAIT 1.
}
PRINT "Fuera de atmosfera. Preparando circularizacion.".
HUDTEXT("EXOATMOSPHERIC — CIRCULARIZATION PREP", 5, 2, 25, YELLOW, FALSE).
LogS2("COAST").

// ============================================================
// === 10. CIRCULARIZACIÓN PRO ===
// ============================================================
// ============================================================
// === 10. CIRCULARIZACIÓN PROFESIONAL (Fix: BurnTime & Precision) ===
// ============================================================
LOCAL mu IS BODY:MU.
LOCAL orbitR IS BODY:RADIUS + SHIP:APOAPSIS.
LOCAL v_circ IS SQRT(mu / orbitR).
LOCAL v_apo IS SQRT(mu * (2/orbitR - 1/SHIP:ORBIT:SEMIMAJORAXIS)).
LOCAL dv_req IS MAX(0, v_circ - v_apo).

// FIX: Calcular empuje potencial (aunque estén apagados)
LOCAL potThrust IS 0.
FOR e IN SHIP:ENGINES { SET potThrust TO potThrust + e:POSSIBLETHRUST. }
IF potThrust < 1 { SET potThrust TO 1000. } // Fallback de seguridad

LOCAL maxAcc IS potThrust / SHIP:MASS.
LOCAL burnTime IS dv_req / maxAcc.

PRINT "DV Circ: " + ROUND(dv_req, 1) + " m/s | BurnTime: " + ROUND(burnTime, 1) + " s".

// Orientar con rampa suave hacia progrado
WAIT UNTIL ETA:APOAPSIS < (burnTime / 2) + 30.
PRINT "Orientando a PROGRADO...".
LOCK STEERING TO PROGRADE.
HUDTEXT("ORIENTING TO PROGRADE", 3, 2, 20, CYAN, FALSE).

// Cuenta atrás centrada
UNTIL ETA:APOAPSIS <= (burnTime / 2) {
    SetPhysicsRange(2500000).
    LOCAL ct IS ETA:APOAPSIS - (burnTime / 2).
    PRINT ("T-minus Burn: " + ROUND(ct, 1) + "s    ") AT (0, 22).
    IF ct <= 10 AND ct > 0 {
        HUDTEXT("T-" + ROUND(ct, 0), 1, 2, 30, YELLOW, FALSE).
    }
    WAIT 0.1.
}

HUDTEXT("IGNITION: CIRCULARIZATION", 5, 2, 30, GREEN, FALSE).
PRINT "Ignicion de circularizacion.".
LogS2("CIRC BURN").

// Activar motores para la quemada
AG1 ON.
FOR e IN SHIP:ENGINES {
    IF NOT e:IGNITION AND (e:TAG:TOUPPER = "S1" OR e:TAG:TOUPPER = "S2") {
        e:ACTIVATE().
    }
}
AG4 OFF.

// Quemada con precisión final (Basado en Launch.ks)
LOCAL targetOrbVel IS SQRT(mu / (SHIP:BODY:RADIUS + SHIP:ALTITUDE)).
UNTIL SHIP:PERIAPSIS > (targetApo - 1000) OR SHIP:OBT:ECCENTRICITY < 0.005 {
    LOCAL currentVel IS SHIP:VELOCITY:ORBIT:MAG.
    LOCAL velError IS targetOrbVel - currentVel.
    
    // Control de potencia para precision final
    IF velError < 15 { LOCK THROTTLE TO 0.15. }
    ELSE { LOCK THROTTLE TO 1.0. }
    
    LOCK STEERING TO PROGRADE.
    LogS2("CIRC BURN").
    
    PRINT "Periapsis: " + ROUND(SHIP:PERIAPSIS/1000, 2) + " km    " AT(0, 23).
    PRINT "Eccentricity: " + ROUND(SHIP:OBT:ECCENTRICITY, 5) + "    " AT(0, 24).
    
    // Aborto preventivo si nos pasamos (seguridad)
    IF ETA:PERIAPSIS < 10 AND ETA:APOAPSIS > 30 { BREAK. }
    WAIT 0.05.
}

// ============================================================
// === 11. SHUTDOWN FINAL ===
// ============================================================
LOCK THROTTLE TO 0.
AG4 ON.
FOR e IN SHIP:ENGINES { e:SHUTDOWN(). }
UNLOCK STEERING.
LogS2("ORBIT ACHIEVED").

// ============================================================
// === 11. SISTEMA DE INTERFAZ ESTILO STARSHIP ===
// ============================================================

FUNCTION CrearMenuOrbital {
    IF guiOpen { guiObj:HIDE(). SET guiOpen TO FALSE. }
    
    SET guiObj TO GUI(250).
    SET guiObj:X TO 100. SET guiObj:Y TO 100.
    SET guiObj:STYLE:BG TO "starship_img/starship_main_square_bg". // Intento de skin
    
    guiObj:ADDLABEL("<size=18><b> TOMCAT SHIP CONTROL </b></size>").
    guiObj:ADDSPACING(10).
    
    LOCAL labelStatus IS guiObj:ADDLABEL("ESTADO: <b>" + mission_status + "</b>").
    LOCAL labelApo IS guiObj:ADDLABEL("APOAPSIS: " + ROUND(SHIP:APOAPSIS/1000, 1) + " km").
    LOCAL labelPer IS guiObj:ADDLABEL("PERIAPSIS: " + ROUND(SHIP:PERIAPSIS/1000, 1) + " km").
    
    guiObj:ADDSPACING(10).
    LOCAL btnCirc IS guiObj:ADDBUTTON("EJECUTAR CIRCULARIZACION").
    LOCAL btnTrans IS guiObj:ADDBUTTON("TRANSFERENCIA HOHMANN").
    LOCAL btnReentry IS guiObj:ADDBUTTON("INICIAR REENTRADA").
    LOCAL btnPayload IS guiObj:ADDBUTTON("DESPLEGAR CARGA").
    
    SET btnCirc:ONCLICK TO {
        SET mission_status TO "CIRCULARIZANDO".
        guiObj:HIDE(). SET guiOpen TO FALSE.
    }.
    
    SET btnTrans:ONCLICK TO {
        LOCAL newAlt IS 200. // Default
        HUDTEXT("USE LA TERMINAL PARA INGRESAR ALTITUD", 5, 2, 25, YELLOW, FALSE).
        // Aquí podrías añadir un campo de texto en la GUI si prefieres
    }.
    
    SET btnReentry:ONCLICK TO {
        SET mission_status TO "REENTRADA".
        guiObj:HIDE(). SET guiOpen TO FALSE.
    }.
    
    SET btnPayload:ONCLICK TO {
        AG5 ON.
        HUDTEXT("PAYLOAD DEPLOYED", 5, 2, 30, GREEN, FALSE).
    }.

    guiObj:SHOW().
    SET guiOpen TO TRUE.
    
    RETURN guiObj.
}

// Bucle final con GUI activa
SET mission_status TO "ORBITA ESTABLECIDA".
CrearMenuOrbital().

UNTIL mission_status = "EXIT" {
    IF mission_status = "CIRCULARIZANDO" {
        // La lógica de circularización ya está arriba, 
        // pero podemos moverla aquí o llamarla.
        SET mission_status TO "ORBITA ESTABLECIDA".
        CrearMenuOrbital().
    }
    
    IF mission_status = "REENTRADA" {
        HUDTEXT("INICIANDO MANIOBRA DE DEORBITA", 5, 2, 35, RED, TRUE).
        LOCK STEERING TO RETROGRADE.
        WAIT 5.
        LOCK THROTTLE TO 1.0.
        WAIT UNTIL SHIP:PERIAPSIS < 30000.
        LOCK THROTTLE TO 0.
        SET mission_status TO "DESCENSO".
    }
    
    LogS2(mission_status).
    WAIT 0.5.
}
