// --- PHYSICS RANGE BLINDADO (RSS SCALE) ---
// Configurado según el patrón de booster.ks para máxima estabilidad
FUNCTION SetPhysicsRange {
    PARAMETER d.
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
    SET KUNIVERSE:DEFAULTLOADDISTANCE:FLYING:UNLOAD TO d.
    SET KUNIVERSE:DEFAULTLOADDISTANCE:SUBORBITAL:UNLOAD TO d.
    SET KUNIVERSE:DEFAULTLOADDISTANCE:ORBIT:UNLOAD TO d.
    WAIT 0.1.
}
SetPhysicsRange(2500000).
GLOBAL initialParts IS SHIP:PARTS:LENGTH.
GLOBAL runmode IS 0.
IF SHIP:STATUS <> "PRELAUNCH" { SET runmode TO 1. }

LOCAL manualStaging IS FALSE.
LOCAL stage1Separated IS FALSE.
LOCAL fileA TO "0:/telemetry_ship_A.json".
LOCAL fileB TO "0:/telemetry_ship_B.json".
LOCAL useA TO TRUE.
LOCAL lastLog IS -1. 
LOCAL currentStageDV IS 0.
LOCAL targetApo IS 100000.
GLOBAL tgtHeading IS 90.
GLOBAL ag4FairingTriggered IS FALSE.

FUNCTION CortarComunicacion {
    // DESACTIVADO TEMPORALMENTE PARA EVITAR QUE LA 2ª ETAPA DESCARGUE AL BOOSTER
    PRINT "LIMPIEZA DE FISICA POSPUESTA PARA SEGURIDAD DEL BOOSTER.".
}

CLEARSCREEN.
PRINT "--- MISSION CONTROL: ASCENT SYSTEM ---".

// --- GUI CONFIGURATION ---
LOCAL g IS GUI(200).
SET g:X TO 300. SET g:Y TO 100.
g:ADDLABEL("<b>LAUNCH CONFIG</b>").
g:ADDLABEL("Apoapsis (km):").
LOCAL altField IS g:ADDTEXTFIELD("100").
g:ADDLABEL("Heading (0=Norte/Polar, 90=Este/Ecuatorial):").
LOCAL incField IS g:ADDTEXTFIELD("90").
LOCAL missionToggle IS g:ADDCHECKBOX("BOOSTER RECUPERABLE", TRUE).
LOCAL qLimitField IS g:ADDTEXTFIELD("20000").
g:ADDLABEL("MAX Q LIMIT (Pa)").
LOCAL launchBtn IS g:ADDBUTTON("LAUNCH!").
LOCAL startLaunch IS FALSE.
SET launchBtn:ONCLICK TO { SET startLaunch TO TRUE. }.
g:SHOW().

GLOBAL missionProfile IS "RECUPERABLE".

// --- PRE-LAUNCH TELEMETRY & WAIT ---
IF SHIP:STATUS = "PRELAUNCH" {
    UNTIL startLaunch {
        logTelemetry("WAITING GUI").
        drawUI("WAITING GUI", 90, 0).
        WAIT 0.5.
    }
    SET targetApo TO altField:TEXT:TONUMBER() * 1000.
    SET tgtHeading TO incField:TEXT:TONUMBER().
    GLOBAL maxQLimit IS qLimitField:TEXT:TONUMBER(20000).
    IF missionToggle:PRESSED { SET missionProfile TO "RECUPERABLE". } ELSE { SET missionProfile TO "DESECHABLE". }
    WRITEJSON(LEX("apo", targetApo, "inc", tgtHeading, "profile", missionProfile, "maxQ", maxQLimit), "1:/ascent_config.json").
    g:HIDE(). g:DISPOSE().

    PRINT "Ignition!".
    SET runmode TO 1.
    LOCK THROTTLE TO 1.0. LOCK STEERING TO UP.
    
    // Steering config (RSS Aerodynamics & CoG Offset Optimization)
    SET STEERINGMANAGER:MAXSTOPPINGTIME TO 2.5. 
    SET STEERINGMANAGER:PITCHPID:KP TO 1.0.     // Improved authority
    SET STEERINGMANAGER:PITCHPID:KI TO 0.02.    // Counteracts CoG offset (Anti-Torque)
    SET STEERINGMANAGER:PITCHPID:KD TO 1.5.     
    SET STEERINGMANAGER:YAWPID:KP TO 1.0.
    SET STEERINGMANAGER:YAWPID:KI TO 0.02.     
    SET STEERINGMANAGER:YAWPID:KD TO 1.5.
    SET STEERINGMANAGER:ROLLPID:KD TO 1.5.

    // Release Clamps (Action Group 9)
    PRINT "Releasing Launch Clamps (AG9)...".
    AG9 ON.
    STAGE. 
    
    // Liftoff Monitoring (RSS COMPATIBLE - Using ALT:RADAR and STATUS)
    UNTIL ALT:RADAR > 5 OR SHIP:STATUS = "FLYING" {
        logTelemetry("IGNITION").
        drawUI("IGNITION", 90, 1.0).
        WAIT 0.1.
    }
    AG9 ON. PRINT "LIFTOFF!".
} ELSE {
    g:HIDE(). g:DISPOSE().
    IF EXISTS("1:/ascent_config.json") {
        LOCAL ascentConfig IS READJSON("1:/ascent_config.json").
        SET targetApo TO ascentConfig["apo"].
        SET tgtHeading TO ascentConfig["inc"].
        IF ascentConfig:HASKEY("profile") { SET missionProfile TO ascentConfig["profile"]. }
        IF ascentConfig:HASKEY("maxQ") { GLOBAL maxQLimit IS ascentConfig["maxQ"]. } ELSE { GLOBAL maxQLimit IS 20000. }
    }
    PRINT "Reconnecting (" + missionProfile + ") Tgt: " + (targetApo/1000) + "km...".
}

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

WAIT UNTIL ALT:RADAR > 100 OR SHIP:STATUS = "FLYING".
IF (SHIP:STATUS = "FLYING" OR SHIP:STATUS = "SUB_ORBITAL") AND SHIP:VERTICALSPEED > 0 {
    HUDTEXT("ASCENT HEADING: " + tgtHeading + " deg", 5, 2, 30, CYAN, FALSE).
    LOCK STEERING TO HEADING(tgtHeading, 90).
}

// El runmode se gestiona por sensores en el bucle principal.

FUNCTION logTelemetry {
    SET currentStageDV TO SHIP:STAGEDELTAV(STAGE:NUMBER):VACUUM.
    PARAMETER statusMsg.
    
    // Aumento frecuencia a 10Hz (0.1s)
    IF TIME:SECONDS > lastLog + 0.1 {
        LOCAL tFile TO fileB.
        IF useA { SET tFile TO fileA. }
        SET useA TO NOT useA.
        LOCAL engDict IS LEX().
        LIST ENGINES IN eList.
        LOCAL foundTags IS "".
        FOR e IN eList {
            LOCAL t IS e:TAG:TOUPPER:TRIM.
            IF t:LENGTH > 0 AND (t = "S1" OR t:CONTAINS("SEC")) { 
                // Consider engine active (1) only if ignited AND power >= 1%
                LOCAL is_on IS 0.
                IF e:IGNITION AND (e:THRUST / MAX(0.1, e:POSSIBLETHRUST) >= 0.01) { SET is_on TO 1. }
                SET engDict[t] TO is_on.
                SET foundTags TO foundTags + t + " ".
            }
        }
        
        IF MOD(ROUND(TIME:SECONDS), 5) = 0 { PRINT "TAGS: " + foundTags AT (0, 24). }

        LOCAL gVal IS 0.
        LIST SENSORS IN S_LIST.
        FOR S IN S_LIST { IF S:TYPE = "ACC" AND S:ACTIVE { SET gVal TO ROUND(S:MAG / 9.80665, 2). } }

        LOCAL data IS LEX(
            "time", ROUND(TIME:SECONDS, 1),
            "met", MISSIONTIME,
            "mode", runmode,
            "alt", ROUND(SHIP:ALTITUDE),
            "apo", ROUND(SHIP:APOAPSIS),
            "per", ROUND(SHIP:PERIAPSIS),
            "vel", ROUND(SHIP:AIRSPEED),
            "vs", ROUND(SHIP:VERTICALSPEED, 1),
            "dv", ROUND(currentStageDV),
            "g", gVal,
            "q", ROUND(SHIP:Q * 100, 1), // Dynamic Pressure in kPa (relative)
            "twr", ROUND(SHIP:AVAILABLETHRUST / MAX(0.1, SHIP:MASS * 9.80665), 2),
            "hdist", ROUND(SHIP:GEOPOSITION:DISTANCE / 1000, 1),
            "thr", ROUND(THROTTLE * 100, 1),
            "fuel", GetTotalFuel(),
            "fuelPct", GetFuelPctByTag("SHIP"),
            "engStates", engDict,
            "status", statusMsg,
            "version", "2.1-FIX"
        ).
        
        IF CORE:CURRENTVOLUME:NAME = "0" OR HOMECONNECTION:ISCONNECTED {
             WAIT 0.1 + (MOD(ROUND(SHIP:ALTITUDE), 10)/100). // Stagger write jitter
             WRITEJSON(data, tFile).
        }
        SET lastLog TO TIME:SECONDS.
    }
}

FUNCTION GetInputWithTelemetry {
    UNTIL TERMINAL:INPUT:HASCHAR {
        logTelemetry(SHIP:STATUS).
        WAIT 0.2.
    }
    RETURN TERMINAL:INPUT:GETCHAR().
}

// --- CORE UTILITIES ---
DECLARE FUNCTION EjecutarNodo {
    PARAMETER nd.
    HUDTEXT("ORIENTING TO NODE...", 5, 2, 30, YELLOW, FALSE).
    LOCK STEERING TO nd:DELTAV.
    WAIT UNTIL nd:ETA < 30.
    
    // Warp to node safely
    IF nd:ETA > 60 { KUNIVERSE:TIMEWARP:WARPTO(TIME:SECONDS + nd:ETA - 45). }
    
    WAIT UNTIL nd:ETA < (nd:DELTAV:MAG / (SHIP:AVAILABLETHRUST / SHIP:MASS) / 2) + 2.
    
    HUDTEXT("BURN START!", 5, 2, 30, GREEN, FALSE).
    SET STEERINGMANAGER:MAXSTOPPINGTIME TO 2. // Regresar a respuesta rápida para la quemada
    LOCK THROTTLE TO 1.0.
    LOCAL initialDv IS nd:DELTAV:MAG.
    LOCAL done IS FALSE.
    
    // Capturar dirección bloqueada para el final
    LOCAL finalDir IS nd:DELTAV.
    
    UNTIL done {
        LOCAL dV_mag IS nd:DELTAV:MAG.
        
        // --- CONTROL DE PRECISIÓN ANTI-SPIN ---
        IF dV_mag < 10.0 {
            // A 10 m/s ya bloqueamos la dirección para que no dé vueltas
            LOCK STEERING TO finalDir.
            
            // A 2 m/s bajamos potencia al mínimo para precisión quirúrgica
            IF dV_mag < 2.0 { LOCK THROTTLE TO 0.05. }
            ELSE { LOCK THROTTLE TO 0.2. }
        } ELSE {
            // Fase normal: seguir el vector
            SET finalDir TO nd:DELTAV.
            LOCK STEERING TO finalDir.
        }
        
        // Condición de corte: dV insignificante o nos hemos pasado (VDOT negativo)
        IF dV_mag < 0.05 OR VDOT(nd:DELTAV, finalDir) < 0 {
            SET done TO TRUE.
        }
        
        logTelemetry("NODE BURN").
        drawUI("NODE BURN", 0, THROTTLE).
        WAIT 0.01.
    }
    LOCK THROTTLE TO 0.
    REMOVE nd.
    UNLOCK STEERING.
    HUDTEXT("NODE COMPLETE", 5, 2, 30, GREEN, FALSE).
}

DECLARE FUNCTION TransferenciaHohmann {
    PARAMETER targetAlt.
    HUDTEXT("CALCULATING HOΗMANN TO " + ROUND(targetAlt/1000) + "KM", 5, 2, 30, YELLOW, FALSE).
    LOCAL rad1 IS SHIP:BODY:RADIUS + SHIP:PERIAPSIS.
    LOCAL rad2 IS SHIP:BODY:RADIUS + targetAlt.
    LOCAL sma2 TO (rad1 + rad2) / 2.
    LOCAL v1 TO SQRT(SHIP:BODY:MU * (2/rad1 - 1/SHIP:ORBIT:SEMIMAJORAXIS)).
    LOCAL v2 TO SQRT(SHIP:BODY:MU * (2/rad1 - 1/sma2)).
    ADD NODE(TIME:SECONDS + ETA:PERIAPSIS, 0, 0, v2 - v1).
    EjecutarNodo(NEXTNODE).
    WAIT 1.
    LOCAL rad3 IS SHIP:BODY:RADIUS + SHIP:APOAPSIS.
    LOCAL v3 TO SQRT(SHIP:BODY:MU * (2/rad3 - 1/SHIP:ORBIT:SEMIMAJORAXIS)).
    LOCAL vCirc TO SQRT(SHIP:BODY:MU / rad3).
    ADD NODE(TIME:SECONDS + ETA:APOAPSIS, 0, 0, vCirc - v3).
    EjecutarNodo(NEXTNODE).
}

DECLARE FUNCTION UniversalTrigger {
    PARAMETER p.
    LOCAL moved TO FALSE.
    LOCAL possibleEvents IS LIST("decouple", "separate", "release", "disperse", "undock").
    FOR mName IN p:MODULES {
        LOCAL mRef TO p:GETMODULE(mName).
        FOR eName IN possibleEvents {
            IF mRef:HASEVENT(eName) {
                mRef:DOEVENT(eName).
                SET moved TO TRUE.
            }
        }
    }
    RETURN moved.
}

DECLARE FUNCTION TransferenciaHohmann {
    PARAMETER targetAlt.
    
    CLEARSCREEN.
    PRINT "=== TRANSFERENCIA HOHMANN ===".
    PRINT "Objetivo: " + ROUND(targetAlt/1000) + " km".
    PRINT "Órbita actual: " + ROUND(SHIP:APOAPSIS/1000) + "x" + ROUND(SHIP:PERIAPSIS/1000) + " km".
    PRINT " ".
    
    // Calculate Hohmann transfer
    LOCAL mu IS BODY:MU.
    LOCAL r1 IS SHIP:APOAPSIS + BODY:RADIUS.
    LOCAL r2 IS targetAlt + BODY:RADIUS.
    
    // Delta-V for apoapsis raise at periapsis
    LOCAL v1 IS SQRT(mu / r1).
    LOCAL vTransfer IS SQRT(mu * (2/r1 - 1/((r1+r2)/2))).
    LOCAL dv1 IS vTransfer - v1.
    
    PRINT "Calculando nodo en apoapsis...".
    PRINT "Delta-V requerido: " + ROUND(dv1, 1) + " m/s".
    
    // Create node at next apoapsis
    LOCAL nd IS NODE(TIME:SECONDS + ETA:APOAPSIS, 0, 0, dv1).
    ADD nd.
    
    PRINT "Nodo creado. Ejecutando...".
    WAIT 2.
    
    EjecutarNodo(nd).  
    PRINT "Transferencia completada!".
    PRINT "Nueva órbita: " + ROUND(SHIP:APOAPSIS/1000) + "x" + ROUND(SHIP:PERIAPSIS/1000) + " km".
    WAIT 3.
}

DECLARE FUNCTION PlanificadorInterplanetario {
    CLEARSCREEN.
    PRINT "=== PLANIFICADOR INTERPLANETARIO ===".
    PRINT " ".
    
    // Validate TARGET
    IF NOT HASTARGET {
        PRINT "ERROR: No hay objetivo seleccionado.".
        PRINT "Seleccione un planeta/luna en el mapa primero.".
        PRINT " ".
        PRINT "Presione cualquier tecla para volver...".
        GetInputWithTelemetry().
        RETURN.
    }
    
    IF NOT TARGET:ISTYPE("Body") {
        PRINT "ERROR: El objetivo debe ser un cuerpo celeste.".
        PRINT "Objetivo actual: " + TARGET:NAME + " (" + TARGET:TYPENAME + ")".
        PRINT " ".
        PRINT "Presione cualquier tecla para volver...".
        GetInputWithTelemetry().
        RETURN.
    }
    
    LOCAL targetBody IS TARGET.
    PRINT "Destino: " + targetBody:NAME.
    PRINT "Distancia: " + ROUND(targetBody:DISTANCE/1000000, 1) + "M km".
    
    // Check if we're already in the target's SOI
    IF SHIP:BODY = targetBody {
        PRINT "ERROR: Ya estás en órbita de " + targetBody:NAME + ".".
        PRINT "Usa las transferencias Hohmann locales.".
        PRINT " ".
        PRINT "Presione cualquier tecla para volver...".
        GetInputWithTelemetry().
        RETURN.
    }
    
    PRINT " ".
    PRINT "--- CONFIGURACIÓN DE MISIÓN ---".
    PRINT " ".
    
    // Get periapsis altitude (above surface)
    PRINT "Altitud de periapsis SOBRE LA SUPERFICIE (km) y presione ENTER:".
    LOCAL inputStr IS "".
    LOCAL done IS FALSE.
    UNTIL done {
        LOCAL ch IS GetInputWithTelemetry().
        IF ch = CHAR(13) { SET done TO TRUE. }
        ELSE IF ch = CHAR(8) {
            IF inputStr:LENGTH > 0 {
                SET inputStr TO inputStr:SUBSTRING(0, inputStr:LENGTH - 1).
            }
        } ELSE IF ch:TONUMBER(-1) >= 0 AND ch:TONUMBER(-1) <= 9 {
            SET inputStr TO inputStr + ch.
        }
        PRINT "Periapsis: " + inputStr + " km      " AT (0, 12).
    }
    LOCAL periapsisAlt IS inputStr:TONUMBER(100) * 1000.
    
    // Validate periapsis (must be positive, above surface)
    IF periapsisAlt < 0 {
        PRINT " ".
        PRINT "ERROR: Altitud debe ser positiva!".
        PRINT " ".
        PRINT "Presione cualquier tecla para volver...".
        GetInputWithTelemetry().
        RETURN.
    }
    
    PRINT " ".
    PRINT "Tipo de misión:".
    PRINT "[F] Flyby (solo eyección)".
    PRINT "[O] Órbita (eyección + captura)".
    PRINT "[0] Cancelar".
    PRINT " ".
    
    LOCAL missionType IS GetInputWithTelemetry():TOUPPER().
    IF missionType = "0" { RETURN. }
    IF missionType <> "F" AND missionType <> "O" {
        PRINT "Opción inválida. Cancelando...".
        WAIT 2.
        RETURN.
    }
    
    // Calculate and execute transfer
    CLEARSCREEN.
    PRINT "=== CALCULANDO TRANSFERENCIA ===".
    PRINT "Destino: " + targetBody:NAME.
    PRINT "Periapsis: " + ROUND(periapsisAlt/1000) + " km".
    LOCAL modoTexto IS "Flyby".
    IF missionType = "O" { SET modoTexto TO "Órbita". }
    PRINT "Modo: " + modoTexto.
    PRINT " ".
    
    EjecutarTransferenciaInterplanetaria(targetBody, periapsisAlt, missionType).
}

DECLARE FUNCTION EjecutarTransferenciaInterplanetaria {
    PARAMETER targetBody, periapsisAlt, missionType.
    
    // Determine the correct parent body for the transfer
    LOCAL parentBody IS SHIP:BODY.
    LOCAL isLocalTransfer IS FALSE.
    
    IF targetBody:ORBIT:HASSUFFIX("BODY") {
        IF targetBody:ORBIT:BODY = SHIP:BODY {
            SET isLocalTransfer TO TRUE.
            SET parentBody TO SHIP:BODY.
        } ELSE {
            SET parentBody TO SHIP:BODY:BODY.
            IF NOT parentBody:HASSUFFIX("BODY") { SET parentBody TO SUN. }
        }
    }
    
    LOCAL tipoTransferencia IS "Interplanetaria".
    IF isLocalTransfer { SET tipoTransferencia TO "Local (Luna)". }
    PRINT "Tipo de transferencia: " + tipoTransferencia.
    PRINT " ".
    
    // For local transfers (moons), use a simpler approach
    // Calculate the required velocity to reach the target's orbital altitude
    LOCAL mu IS parentBody:MU.
    LOCAL r1 IS SHIP:ORBIT:SEMIMAJORAXIS.
    LOCAL r2 IS targetBody:ORBIT:SEMIMAJORAXIS.
    
    // Hohmann transfer Delta-V
    LOCAL v1 IS SQRT(mu / r1).
    LOCAL vTransfer IS SQRT(mu * (2/r1 - 2/(r1 + r2))).
    LOCAL dvRequired IS ABS(vTransfer - v1).
    
    PRINT "Delta-V estimado: " + ROUND(dvRequired, 1) + " m/s".
    PRINT " ".
    
    // Check if we have enough Delta-V (current stage only, since we're in orbit post-separation)
    LOCAL dvAvailable IS SHIP:DELTAV:CURRENT.
    LOCAL dvTotal IS SHIP:DELTAV:VACUUM.
    
    PRINT "Delta-V disponible (etapa actual): " + ROUND(dvAvailable, 1) + " m/s".
    IF dvTotal > dvAvailable {
        PRINT "Delta-V total (todas las etapas): " + ROUND(dvTotal, 1) + " m/s".
    }
    PRINT " ".
    
    IF dvAvailable < dvRequired {
        PRINT "ADVERTENCIA: Delta-V insuficiente en etapa actual!".
        PRINT "Requerido: " + ROUND(dvRequired, 1) + " m/s".
        PRINT " ".
        PRINT "¿Continuar de todos modos? [S/N]".
        LOCAL confirm IS GetInputWithTelemetry():TOUPPER().
        IF confirm <> "S" {
            PRINT "Transferencia cancelada.".
            WAIT 2.
            RETURN.
        }
    }
    
    // Calculate phase angle
    LOCAL shipPos IS SHIP:POSITION - parentBody:POSITION.
    LOCAL targetPos IS targetBody:POSITION - parentBody:POSITION.
    LOCAL phaseAngle IS VANG(shipPos, targetPos).
    
    // Calculate transfer time (Hohmann)
    LOCAL transferTime IS CONSTANT:PI * SQRT((r1 + r2)^3 / (8 * mu)).
    
    // Calculate where target will be when we arrive
    LOCAL targetAngularVel IS SQRT(mu / r2^3).
    LOCAL targetTravelAngle IS targetAngularVel * transferTime * CONSTANT:RADTODEG.
    
    // Optimal phase angle: where target needs to be NOW for us to intercept it
    LOCAL optimalPhase IS 180 - targetTravelAngle.
    
    PRINT "Ángulo de fase actual: " + ROUND(phaseAngle, 1) + "°".
    PRINT "Ángulo de fase óptimo: " + ROUND(optimalPhase, 1) + "°".
    PRINT "Diferencia: " + ROUND(ABS(phaseAngle - optimalPhase), 1) + "°".
    PRINT " ".
    
    // MechJeb-style: Create Hohmann transfer at optimum time
    // The optimum time is when the phase angle is correct for intercept
    
    // Calculate optimal phase angle (where target should be NOW for us to intercept)
    LOCAL transferTime IS CONSTANT:PI * SQRT((r1 + r2)^3 / (8 * mu)).
    LOCAL targetAngularVel IS SQRT(mu / r2^3) * CONSTANT:RADTODEG.
    LOCAL targetTravelAngle IS targetAngularVel * transferTime.
    LOCAL optimalPhaseAngle IS 180 - targetTravelAngle.
    
    PRINT "Ángulo de fase actual: " + ROUND(phaseAngle, 1) + "°".
    PRINT "Ángulo de fase óptimo: " + ROUND(optimalPhaseAngle, 1) + "°".
    PRINT " ".
    
    // Calculate time until optimum window
    LOCAL shipAngularVel IS SQRT(mu / r1^3) * CONSTANT:RADTODEG.
    LOCAL relativeAngularVel IS shipAngularVel - targetAngularVel.
    LOCAL phaseError IS optimalPhaseAngle - phaseAngle.
    IF phaseError < 0 { SET phaseError TO phaseError + 360. }
    IF phaseError > 180 { SET phaseError TO phaseError - 360. }
    
    LOCAL timeToOptimum IS ABS(phaseError) / ABS(relativeAngularVel).
    
    // Check if we're at optimum time (within 5 degrees)
    IF ABS(phaseAngle - optimalPhaseAngle) > 5 {
        PRINT "Esperando momento óptimo...".
        PRINT "Tiempo hasta ventana: " + ROUND(timeToOptimum/60, 1) + " min".
        PRINT " ".
        
        IF timeToOptimum > 300 {
            PRINT "[1] Auto-warp (" + ROUND(timeToOptimum/3600, 1) + " horas)".
            PRINT "[2] Crear nodo ahora (puede fallar)".
            PRINT "[0] Cancelar".
            PRINT " ".
            
            LOCAL choice IS GetInputWithTelemetry().
            IF choice = "0" {
                PRINT "Cancelado.".
                WAIT 2.
                RETURN.
            } ELSE IF choice = "1" {
                PRINT "Warping...".
                KUNIVERSE:TIMEWARP:WARPTO(TIME:SECONDS + timeToOptimum - 30).
                WAIT UNTIL KUNIVERSE:TIMEWARP:ISSETTLED.
                PRINT "Warp completado.".
            }
        } ELSE {
            PRINT "Esperando " + ROUND(timeToOptimum, 0) + " segundos...".
            PRINT "Esperando " + ROUND(timeToOptimum, 0) + " segundos...".
            LOCAL waitEnd IS TIME:SECONDS + timeToOptimum.
            UNTIL TIME:SECONDS >= waitEnd {
                logTelemetry(SHIP:STATUS).
                WAIT 1.
            }
        }
    } ELSE {
        PRINT "¡EN MOMENTO ÓPTIMO!".
    }
    
    // Create simple Hohmann transfer node NOW (at current position + small delay)
    PRINT " ".
    PRINT "Creando nodo de transferencia Hohmann...".
    
    LOCAL nd IS NODE(TIME:SECONDS + 10, 0, 0, dvRequired).
    ADD nd.
    
    PRINT "Nodo creado (+10s)".
    PRINT "Delta-V: " + ROUND(dvRequired, 1) + " m/s".
    PRINT " ".
    PRINT "VERIFICA EL ENCUENTRO EN EL MAPA.".
    PRINT "Si no hay encuentro, ajusta manualmente el nodo.".
    PRINT " ".
    
    // For orbit mode, calculate capture burn
    IF missionType = "O" {
        // Velocity at target periapsis (hyperbolic approach)
        LOCAL vInfinity IS ABS(vTransfer - SQRT(mu / r2)).
        LOCAL vArrival IS SQRT(vInfinity^2 + 2*targetBody:MU/(periapsisAlt + targetBody:RADIUS)).
        LOCAL vOrbit IS SQRT(targetBody:MU / (periapsisAlt + targetBody:RADIUS)).
        LOCAL dvCapture IS vArrival - vOrbit.
        
        PRINT "--- CAPTURA ORBITAL ---".
        PRINT "Delta-V de captura: " + ROUND(dvCapture, 1) + " m/s".
        PRINT "(Ejecutar en periapsis al llegar)".
        PRINT " ".
    }
    
    PRINT "Presione cualquier tecla para ejecutar...".
    GetInputWithTelemetry().
    
    EjecutarNodo(nd).
    
    PRINT " ".
    PRINT "¡Transferencia iniciada!".
    PRINT "Verifica el encuentro en el mapa.".
    PRINT "Si no hay encuentro, ajusta manualmente el nodo.".
    WAIT 3.
}

// --- BOXED TELEMETRY UI (PREMIUM) ---
FUNCTION drawUI {
    PARAMETER statusText, currentPitch, throttleSetting.
    
    SET apoHeight TO SHIP:APOAPSIS.
    SET periHeight TO SHIP:PERIAPSIS.
    SET vSpeed TO SHIP:VERTICALSPEED.
    SET currentDV TO SHIP:STAGEDELTAV(STAGE:NUMBER):VACUUM.
    LOCAL gForce IS 0.
    LIST SENSORS IN sensList.
    FOR s IN sensList { IF s:TYPE = "ACC" AND s:ACTIVE { SET gForce TO s:MAG / 9.80665. } }
    
    // Barrita de empuje ASCII
    LOCAL barLen IS 20.
    LOCAL fillNum IS ROUND(throttleSetting * barLen).
    LOCAL emptyNum IS barLen - fillNum.
    LOCAL barTxt IS "[".
    FROM {LOCAL i IS 0.} UNTIL i >= fillNum STEP {SET i TO i + 1.} DO { SET barTxt TO barTxt + "#". }
    FROM {LOCAL i IS 0.} UNTIL i >= emptyNum STEP {SET i TO i + 1.} DO { SET barTxt TO barTxt + "-". }
    SET barTxt TO barTxt + "]".

    PRINT "╔═════════════════════════════════════╗" AT (0, 1).
    PRINT "║        ASTRO CONSOLE - S2           ║" AT (0, 2).
    PRINT "╠═════════════════════════════════════╣" AT (0, 3).
    PRINT "║ STATUS:  " + (statusText + "                    "):SUBSTRING(0, 18) + "         ║" AT (0, 4).
    PRINT "║ MODE:    " + (runmode + "                      "):SUBSTRING(0, 18) + "         ║" AT (0, 5).
    PRINT "║ G-LOAD:  " + ROUND(gForce, 2) + " G                  ║" AT (0, 6).
    PRINT "╠═════════════════════════════════════╣" AT (0, 7).
    PRINT "║ Altitud:    " + ROUND(SHIP:ALTITUDE/1000, 2) + " km       " AT (0, 8).
    PRINT "║ Apoapsis:   " + ROUND(apoHeight/1000, 2) + " km       " AT (0, 9).
    PRINT "║ ETA Apo:    " + ROUND(ETA:APOAPSIS) + " s             " AT (0, 10).
    PRINT "║ Periapsis:  " + ROUND(periHeight/1000, 2) + " km       " AT (0, 11).
    PRINT "║ V.Vertical: " + ROUND(vSpeed, 1) + " m/s       " AT (0, 12).
    PRINT "║ Stage dV:   " + ROUND(currentDV, 0) + " m/s       " AT (0, 13).
    PRINT "╠═════════════════════════════════════╣" AT (0, 14).
    PRINT "║ Pitch:      " + ROUND(currentPitch, 1) + " deg       " AT (0, 15).
    PRINT "║ Power:  " + barTxt + " " + ROUND(throttleSetting * 100) + "%  " AT (0, 16).
    PRINT "╚═════════════════════════════════════╝" AT (0, 17).
}

logTelemetry("PRELAUNCH").
drawUI("PRELAUNCH", 90, 0).

UNTIL runmode = 0 {
    // --- TRIGGER DE COFIA (65KM) ---
    IF NOT ag4FairingTriggered AND SHIP:ALTITUDE > 65000 {
        SET ag4FairingTriggered TO TRUE.
        AG4 ON.
        HUDTEXT("Fairing Separation", 5, 2, 30, YELLOW, FALSE).
    }

    SET currentStageDV TO SHIP:STAGEDELTAV(STAGE:NUMBER):VACUUM.
    
    // 1. Flameout check (Safe check)
    LIST ENGINES IN engTest.
    LOCAL hasActiveEngines IS FALSE.
    FOR e IN engTest { IF e:IGNITION AND NOT e:FLAMEOUT { SET hasActiveEngines TO TRUE. BREAK. } }

    // --- UNIVERSAL SEPARATION MONITOR ---
    IF NOT stage1Separated AND runmode < 3 {
        LOCAL isSeparated IS FALSE.
        // TRIGGER 1: Delta-V threshold (800 m/s) - Only for REUSABLE profile
        IF missionProfile = "RECUPERABLE" AND SHIP:ALTITUDE > 20000 AND currentStageDV < 800 { SET isSeparated TO TRUE. }
        // TRIGGER 2: Flameout / Empty Tank - For EXPENDABLE (or fallback)
        IF NOT hasActiveEngines AND SHIP:ALTITUDE > 20000 AND NOT manualStaging { SET isSeparated TO TRUE. }
        
        if isSeparated {
            HUDTEXT("MECO - SHUTTING DOWN BOOSTER", 5, 2, 30, YELLOW, FALSE).
            LOCK THROTTLE TO 0.
            SET manualStaging TO TRUE.
            RCS ON.
            
            // 1. MECO: Apagar motores de la 1ª etapa (Booster)
            FOR e IN SHIP:ENGINES {
                LOCAL t IS e:TAG:TOUPPER.
                IF t:CONTAINS("C") OR t:CONTAINS("R") { e:SHUTDOWN(). }
            }
            WAIT 1.0. 
            
            // 2. SEPARACIÓN
            HUDTEXT("STAGING - SEPARATION", 5, 2, 30, YELLOW, FALSE).
            AG5 ON. // Move AG5 here for early support
            AG6 ON. 
            
            // 3. ESPERA DE 2 SEGUNDOS
            WAIT 2.0.
            
            // 4. ENCENDER MOTOR DE SEGUNDA ETAPA (Detección Robusta)
            HUDTEXT("S2 ACTIVATION: DIAGNOSTIC MODE", 5, 2, 30, GREEN, FALSE).
            
            // Refine steering for S2 (lighter, more sensitive)
            SET STEERINGMANAGER:MAXSTOPPINGTIME TO 7. 
            SET STEERINGMANAGER:PITCHPID:KD TO 2.0.   
            SET STEERINGMANAGER:YAWPID:KD TO 2.0.
            
            LOCAL startIgnition TO TIME:SECONDS.
            LOCK THROTTLE TO 1.0. 
            
            LOCAL s2Thrust IS 0.
            LOCAL diagTicker IS 0.

            UNTIL (TIME:SECONDS - startIgnition) > 15 OR s2Thrust > 0.1 {
                SET s2Thrust TO 0.
                FOR e IN SHIP:ENGINES {
                    LOCAL t IS e:TAG:TOUPPER:TRIM. 
                    IF t = "S1" OR t = "S2" OR t:CONTAINS("SEC") OR t:CONTAINS("VAC") { 
                        // DIAGNOSTIC PRINT
                        IF MOD(diagTicker, 5) = 0 {
                            PRINT "ENG " + t + ": IGN=" + e:IGNITION + " THR=" + ROUND(e:THRUST) AT (0, 31).
                            IF e:FLAMEOUT { PRINT "!!! FLAMEOUT !!!" AT (18, 31). }
                        }
                        
                        IF NOT e:IGNITION OR (s2Thrust < 0.1 AND (TIME:SECONDS - startIgnition) > 5) { 
                            IF NOT e:IGNITION { PRINT ">>> ACTIVATE: " + t. }
                            ELSE { PRINT ">>> RESET (THRUST 0): " + t. e:SHUTDOWN(). }
                            e:ACTIVATE(). 
                        }
                        SET e:THRUSTLIMIT TO 100.
                        SET s2Thrust TO s2Thrust + e:THRUST.
                    }
                }
                LOCK THROTTLE TO 1.0.
                SET diagTicker TO diagTicker + 1.
                PRINT "WAITING S2 THRUST: " + ROUND(s2Thrust, 1) + " N    " AT (0, 30).
                WAIT 0.4.
            }

            IF s2Thrust < 0.1 {
                PRINT "CRITICAL: S2 ENGINES FAILED TO IGNITE!".
                HUDTEXT("IGNITION FAILED - CHECK FUEL/TAGS", 5, 2, 30, RED, FALSE).
                
                // Fallback: activate ANY engine that isn't ignited
                PRINT "Trying fallback: Activate all...".
                FOR e IN SHIP:ENGINES { IF NOT e:IGNITION { e:ACTIVATE(). } }
            }
            
            RCS OFF. SET manualStaging TO FALSE. SET stage1Separated TO TRUE.
        }
    }

    IF runmode = 1 {
        drawUI("LAUNCH", 90, THROTTLE).
        IF SHIP:ALTITUDE > 15000 { SET runmode TO 2. HUDTEXT("GRAVITY TURN START", 5, 2, 30, GREEN, FALSE). }
        IF SHIP:ALTITUDE > 30000 { SET runmode TO 2. }
    }


    // 4. Steering / Mission Pulse
    IF runmode = 2 {
        // Gravity Turn: 15km to 70km (Full Tilt reached by 70km)
        LOCAL turnStart IS 15000.
        LOCAL turnEnd IS 95000. // Cambiado de 70km a 95km para RSS
        LOCAL targetPitch TO 90.
        
        IF SHIP:ALTITUDE > turnStart {
            SET targetPitch TO MAX(5, 90 * (1 - (SHIP:ALTITUDE - turnStart)/(turnEnd - turnStart))).
        }
        
        // Remove brusque snap after separation - keep following the curve or stay at current
        // === THROTTLE GOVERNOR (MAX Q LIMIT) ===
        LOCAL currentQPa IS SHIP:DYNAMICPRESSURE * 101325.
        LOCAL qThrottle IS 1.0.
        
        // Empezar a reducir throttle si estamos al 80% del límite
        IF currentQPa > (maxQLimit * 0.8) {
            // Proporcional: baja a 0.2 si llegamos al 110% del límite
            SET qThrottle TO MAX(0.2, 1 - (currentQPa - (maxQLimit * 0.8)) / (maxQLimit * 0.3)).
        }
        
        LOCK THROTTLE TO qThrottle.
        
        LOCK STEERING TO HEADING(tgtHeading, targetPitch).
        drawUI("ASCENT (Q-LIM: " + ROUND(currentQPa) + ")", targetPitch, THROTTLE).
        IF SHIP:APOAPSIS > targetApo { 
            LOCK THROTTLE TO 0.
            SET runmode TO 3. 
        }
    }

    IF runmode = 3 {
        HUDTEXT("SISTEMA DE CIRCULACION DIRECTA ACTIVADO (NO-NODE)", 5, 2, 30, YELLOW, FALSE).
        PRINT "Modo: Quemado Directo (Bypassing Node System)".
        
        // Calcular Delta-V requerido para circularizar
        LOCAL mu IS SHIP:BODY:MU.
        LOCAL radApo IS SHIP:BODY:RADIUS + SHIP:APOAPSIS.
        LOCAL v_circ IS SQRT(mu / radApo).
        LOCAL v1 IS SQRT(mu * (2/radApo - 1/SHIP:ORBIT:SEMIMAJORAXIS)).
        LOCAL dv IS v_circ - v1.
        
        // Estimar tiempo de quemado
        LOCAL f IS SHIP:AVAILABLETHRUST.
        IF f = 0 { SET f TO 0.001. } // Evitar division por cero
        LOCAL m IS SHIP:MASS.
        LOCAL e IS CONSTANT:E.
        LOCAL isp IS 0.
        LIST ENGINES IN myEngs.
        FOR eng IN myEngs { IF eng:IGNITION { SET isp TO eng:ISP. BREAK. } }
        IF isp = 0 { SET isp TO 340. } // Fallback
        
        LOCAL burnTime IS mass * (1 - e^(-dv / (9.81 * isp))) / (f / (9.81 * isp)).
        
        PRINT "Delta-V Req: " + ROUND(dv, 1) + " m/s".
        PRINT "Burn Time:   " + ROUND(burnTime, 1) + " s".
        
        // Esperar al momento justo (Apoapsis - burnTime/2)
        PRINT "Esperando Apoapsis...".
        SAS OFF.
        LOCK STEERING TO PROGRADE.
        
        UNTIL ETA:APOAPSIS <= (burnTime / 2) + 2 {
            PRINT "T-Minus Burn: " + ROUND(ETA:APOAPSIS - burnTime/2, 1) + " s    " AT(0, 30).
            logTelemetry("COAST TO APO").
            WAIT 0.1.
        }
        
        PRINT "IGNICIÓN DE ORBITALIZACIÓN!".
        LOCK THROTTLE TO 1.
        
        // Quemar hasta que el Periapsis sea > 100km (o lo que sea el Apoapsis aprox)
        // Ojo: Si nos pasamos de potencia, el Apoapsis subirá infinito.
        // Mejor control: Quemar hasta que la excentricidad sea < 0.01 o dv gastado
        
        LOCAL targetOrbVel IS SQRT(mu / (SHIP:BODY:RADIUS + SHIP:ALTITUDE)).
        
        UNTIL SHIP:PERIAPSIS > (targetApo - 2000) OR SHIP:OBT:ECCENTRICITY < 0.005 {
            // Control básico de throttle para precisión final
            LOCAL vel IS SHIP:VELOCITY:ORBIT:MAG.
            LOCAL error IS targetOrbVel - vel.
            
            IF error < 10 { LOCK THROTTLE TO 0.1. }
            ELSE { LOCK THROTTLE TO 1. }
            
            PRINT "Periapsis: " + ROUND(SHIP:PERIAPSIS, 0) + " m" AT(0, 31).
            PRINT "Eccentric: " + ROUND(SHIP:OBT:ECCENTRICITY, 4) + "  " AT(0, 32).
            logTelemetry("CIRC BURN").
            WAIT 0.05.
        }
        
        LOCK THROTTLE TO 0.
        HUDTEXT("ORBIT ESTABLISHED (Direct Mode)", 5, 2, 35, GREEN, FALSE).
        PRINT "Circularización Completada.".
        
        WAIT 3.
        SET runmode TO 0.
    }
    
    logTelemetry(SHIP:STATUS).
    IF runmode <> 0 { WAIT 0.1. }
}

// --- MENU ORBITAL PROFESIONAL ---
LOCAL salirMenu IS FALSE.
UNTIL salirMenu {
    CLEARSCREEN.
    PRINT "=================================".
    PRINT "     MENÚ DE MISIÓN ORBITAL".
    PRINT "=================================".
    PRINT "Órbita: " + ROUND(SHIP:APOAPSIS/1000) + "x" + ROUND(SHIP:PERIAPSIS/1000) + " km".
    PRINT " ".
    PRINT "[1] Transferencia a 200km".
    PRINT "[2] Transferencia a 800km".
    PRINT "[3] Transferencia PERSONALIZADA".
    PRINT "[4] Desplegar Satélites (SEPARA1..10)".
    PRINT "[5] REENTRADA (Deorbita a 30km)".
    PRINT "[6] Salir y Cortar Comunicación".
    PRINT "[7] TRANSFERENCIA INTERPLANETARIA".
    PRINT "[8] EXPANSION CARGA: TRACKING CAMERA".
    PRINT " ".
    PRINT "Presiona tecla...".
    
    SET menuInput TO GetInputWithTelemetry().
    IF menuInput = "1" { TransferenciaHohmann(200000). }
    ELSE IF menuInput = "2" { TransferenciaHohmann(800000). }
    ELSE IF menuInput = "3" {
        CLEARSCREEN.
        PRINT "=== TRANSFERENCIA PERSONALIZADA ===".
        PRINT "Ingrese altitud objetivo (km) y presione ENTER:".
        PRINT " ".
        
        // Multi-digit input builder
        LOCAL inputStr IS "".
        LOCAL done IS FALSE.
        UNTIL done {
            LOCAL ch IS GetInputWithTelemetry().
            IF ch = CHAR(13) { // ENTER key
                SET done TO TRUE.
            } ELSE IF ch = CHAR(8) { // BACKSPACE
                IF inputStr:LENGTH > 0 {
                    SET inputStr TO inputStr:SUBSTRING(0, inputStr:LENGTH - 1).
                }
            } ELSE IF ch:TONUMBER(-1) >= 0 AND ch:TONUMBER(-1) <= 9 {
                SET inputStr TO inputStr + ch.
            }
            PRINT "Altitud: " + inputStr + "      " AT (0, 5).
        }
        
        LOCAL altKm IS inputStr:TONUMBER(300).
        PRINT " ".
        PRINT "Ejecutando transferencia a " + altKm + " km...".
        TransferenciaHohmann(altKm * 1000).
    }
    ELSE IF menuInput = "4" {
        LOCAL subSalir IS FALSE.
        UNTIL subSalir {
            CLEARSCREEN.
            PRINT "=================================".
            PRINT "    CONTROL DE CARGA ÚTIL".
            PRINT "=================================".
            
            // Scan for tags
            LOCAL tagList IS LIST().
            FOR p IN SHIP:PARTS {
                IF p:TAG:TOUPPER:CONTAINS("SEPARA") {
                    IF NOT tagList:CONTAINS(p:TAG) { tagList:ADD(p:TAG). }
                }
            }
            
            IF tagList:LENGTH = 0 {
                PRINT "No se encontraron piezas 'SEPARA'.".
                PRINT " ".
                PRINT "[0] Volver".
            } ELSE {
                LOCAL idx IS 1.
                FOR t IN tagList {
                    PRINT "[" + idx + "] Desplegar: " + t.
                    SET idx TO idx + 1.
                }
                PRINT "[A] Desplegar TODO".
                PRINT "[0] Volver".
            }
            
            SET subInput TO GetInputWithTelemetry():TOUPPER().
            IF subInput = "0" { SET subSalir TO TRUE. }
            ELSE IF subInput = "A" {
                FOR t IN tagList {
                    FOR p IN SHIP:PARTSTAGGED(t) { UniversalTrigger(p). }
                }
                WAIT 1.
            } ELSE {
                LOCAL selIdx IS subInput:TONUMBER(-1).
                IF selIdx > 0 AND selIdx <= tagList:LENGTH {
                    LOCAL targetTag IS tagList[selIdx - 1].
                    PRINT "Desplegando " + targetTag + "...".
                    FOR p IN SHIP:PARTSTAGGED(targetTag) { UniversalTrigger(p). }
                    WAIT 1.
                }
            }
        }
    }
    ELSE IF menuInput = "5" {
        PRINT "AVISO: Iniciando Reentrada...".
        LOCK STEERING TO RETROGRADE.
        WAIT 5.
        LOCK THROTTLE TO 1.0.
        WAIT UNTIL SHIP:PERIAPSIS < 30000.
        LOCK THROTTLE TO 0.
        PRINT "Periapsis de reentrada alcanzado. ¡Suerte!".
        SET salirMenu TO TRUE.
    }
    ELSE IF menuInput = "6" { SET salirMenu TO TRUE. }
    ELSE IF menuInput = "7" { PlanificadorInterplanetario(). }
    ELSE IF menuInput = "8" { IF EXISTS("1:/payload_camera.ks") { RUNPATH("1:/payload_camera.ks"). } ELSE { PRINT "Error: payload_camera.ks no existe.". WAIT 2. } }
}

UNLOCK STEERING. UNLOCK THROTTLE.
PRINT "Misión Finalizada. Control Manual.".
CortarComunicacion().
UNTIL FALSE {
    logTelemetry("COMPLETE").
    WAIT 1.0.
}
