// Script de Segunda Etapa - Inserción Orbital
// Motores: S1-S4 (Sólidos/Iniciales) y SEC1-SEC2 (Secundarios)
// Objetivo: Órbita 200km x 200km

// --- CONFIGURACIÓN DE DISTANCIA DE CARGA (RSS) ---
// DEBE SER LO PRIMERO - Garantizar comunicación con booster desde la plataforma
WAIT 0.01.
// Configuración para la nave actual
SET SHIP:LOADDISTANCE:FLYING:UNLOAD TO 2500000.
SET SHIP:LOADDISTANCE:FLYING:LOAD TO 2400000.
WAIT 0.001.
SET SHIP:LOADDISTANCE:FLYING:PACK TO 2450000.
SET SHIP:LOADDISTANCE:FLYING:UNPACK TO 2350000.
WAIT 0.01.
SET SHIP:LOADDISTANCE:SUBORBITAL:UNLOAD TO 2500000.
SET SHIP:LOADDISTANCE:SUBORBITAL:LOAD TO 2400000.
WAIT 0.001.
SET SHIP:LOADDISTANCE:SUBORBITAL:PACK TO 2450000.
SET SHIP:LOADDISTANCE:SUBORBITAL:UNPACK TO 2350000.
WAIT 0.01.
SET SHIP:LOADDISTANCE:ORBIT:UNLOAD TO 2500000.
SET SHIP:LOADDISTANCE:ORBIT:LOAD TO 2400000.
WAIT 0.001.
SET SHIP:LOADDISTANCE:ORBIT:PACK TO 2450000.
SET SHIP:LOADDISTANCE:ORBIT:UNPACK TO 2350000.
WAIT 0.01.
// Configuración GLOBAL (KUNIVERSE) para asegurar que aplica a todo
SET KUNIVERSE:DEFAULTLOADDISTANCE:FLYING:UNLOAD TO 2500000.
SET KUNIVERSE:DEFAULTLOADDISTANCE:FLYING:LOAD TO 2400000.
SET KUNIVERSE:DEFAULTLOADDISTANCE:FLYING:PACK TO 2450000.
SET KUNIVERSE:DEFAULTLOADDISTANCE:FLYING:UNPACK TO 2350000.
SET KUNIVERSE:DEFAULTLOADDISTANCE:SUBORBITAL:UNLOAD TO 2500000.
SET KUNIVERSE:DEFAULTLOADDISTANCE:SUBORBITAL:LOAD TO 2400000.
SET KUNIVERSE:DEFAULTLOADDISTANCE:SUBORBITAL:PACK TO 2450000.
SET KUNIVERSE:DEFAULTLOADDISTANCE:SUBORBITAL:UNPACK TO 2350000.
SET KUNIVERSE:DEFAULTLOADDISTANCE:ORBIT:UNLOAD TO 2500000.
SET KUNIVERSE:DEFAULTLOADDISTANCE:ORBIT:LOAD TO 2400000.
SET KUNIVERSE:DEFAULTLOADDISTANCE:ORBIT:PACK TO 2450000.
SET KUNIVERSE:DEFAULTLOADDISTANCE:ORBIT:UNPACK TO 2350000.

HUDTEXT("SEGUNDA ETAPA: SISTEMA DE CARGA RSS ACTIVADO (2500km)", 5, 2, 30, GREEN, FALSE).

// Verificar si la nave ya está en órbita (evitar re-ejecución del ascenso)
SET skipAscent TO FALSE.
IF SHIP:STATUS = "ORBITING" {
    SET skipAscent TO TRUE.
    PRINT "Vessel already in orbit, skipping ascent sequence and opening orbital menu.".
}

CLEARSCREEN.

// --- IDENTIFICACIÓN DE MOTORES ---
// DEBE ESTAR ANTES DEL CHECK DE ÓRBITA para que esté disponible en el menú orbital
PRINT "Buscando motores...".

SET motoresS TO LIST().
SET motoresSEC TO LIST().

LIST ENGINES IN allEngines.
FOR eng IN allEngines {
    // Motores S1, S2, S3, S4
    IF eng:TAG = "S1" OR eng:TAG = "S2" OR eng:TAG = "S3" OR eng:TAG = "S4" {
        motoresS:ADD(eng).
        PRINT "Motor S encontrado: " + eng:NAME + " (" + eng:TAG + ")".
    }
    // Motores SEC1, SEC2
    IF eng:TAG = "SEC1" OR eng:TAG = "SEC2" {
        motoresSEC:ADD(eng).
        PRINT "Motor SEC encontrado: " + eng:NAME + " (" + eng:TAG + ")".
    }
}

PRINT " ".
PRINT "Motores SEC encontrados: " + motoresSEC:LENGTH.
PRINT " ".

// --- TELEMETRIA SHIP ---
GLOBAL TELEMETRY_S_A IS "0:/telemetry_ship_A.json".
GLOBAL TELEMETRY_S_B IS "0:/telemetry_ship_B.json".
GLOBAL TELEMETRY_S_TOGGLE IS TRUE.

FUNCTION LogTelemetryShip {
    PARAMETER statusText.
    
    // Eng States (Single S1)
    LOCAL engStates IS LEXICON().
    LOCAL s1Key IS "S1".
    LOCAL st IS 0.
    FOR p IN SHIP:PARTSTAGGED(s1Key) {
            IF p:IGNITION { SET st TO 1. }
    }
    engStates:ADD(s1Key, st).
    
    // Fuel (Generic)
    LOCAL curr IS 0.
    LOCAL cap IS 0.
    FOR res IN SHIP:RESOURCES {
        // Sumar todo lo liquido
        IF res:NAME:CONTAINS("Lqd") OR res:NAME:CONTAINS("Fuel") OR res:NAME:CONTAINS("Ox") {
            SET curr TO curr + res:AMOUNT.
            SET cap TO cap + res:CAPACITY.
        }
    }
    LOCAL fuelPct IS 0.
    IF cap > 0 { SET fuelPct TO (curr / cap) * 100. }

    // Data
    LOCAL data IS LEXICON(
        "status", statusText,
        "alt", ROUND(SHIP:ALTITUDE, 0),
        "vel", ROUND(SHIP:VELOCITY:ORBIT:MAG, 0),
        "apo", ROUND(SHIP:APOAPSIS, 0),
        "per", ROUND(SHIP:PERIAPSIS, 0),
        "inc", ROUND(SHIP:OBT:INCLINATION, 1),
        "inc", ROUND(SHIP:OBT:INCLINATION, 1),
        "dv", ROUND(SHIP:DELTAV:VACUUM, 0),
        "fuel", ROUND(curr, 0),
        "fuelPct", ROUND(fuelPct, 1),
        "thr", ROUND(THROTTLE * 100, 0),
        "engStates", engStates
    ).
    
    IF TELEMETRY_S_TOGGLE { WRITEJSON(data, TELEMETRY_S_A). } 
    ELSE { WRITEJSON(data, TELEMETRY_S_B). }
    SET TELEMETRY_S_TOGGLE TO NOT TELEMETRY_S_TOGGLE.
}

IF NOT skipAscent {

// --- DESPLIEGUE DE ANTENAS ---
PRINT "Desplegando antenas...".
FOR part IN SHIP:PARTS {
    IF part:HASMODULE("ModuleDeployableAntenna") {
        part:GETMODULE("ModuleDeployableAntenna"):DOEVENT("extend antenna").
    }
    IF part:HASMODULE("ModuleRTAntenna") {
        part:GETMODULE("ModuleRTAntenna"):DOACTION("activate", true).
    }
}

PRINT "=== SEGUNDA ETAPA ===".
PRINT "Sistema en espera...".
PRINT "Configuración RSS LoadDistance: ACTIVA (2500km)".
PRINT "Detectando separación (Tags: SEPARA o BOOSTER)...".
PRINT " ".

// Contar partes iniciales
SET initialSeparaParts TO 0.
FOR part IN SHIP:PARTS {
    IF part:TAG = "SEPARA" {
        SET initialSeparaParts TO initialSeparaParts + 1.
    }
}
SET initialBoosterParts TO SHIP:PARTSTAGGED("BOOSTER"):LENGTH.

PRINT "Partes SEPARA:  " + initialSeparaParts.
PRINT "Partes BOOSTER: " + initialBoosterParts.
PRINT "Esperando separación...".
PRINT " ".

// Esperar hasta que las partes desaparezcan
UNTIL FALSE {
    SET currentSeparaParts TO 0.
    FOR part IN SHIP:PARTS {
        IF part:TAG = "SEPARA" {
            SET currentSeparaParts TO currentSeparaParts + 1.
        }
    }
    SET currentBoosterParts TO SHIP:PARTSTAGGED("BOOSTER"):LENGTH.
    
    // Condición 1: Menos partes SEPARA
    // Condición 2: No hay partes BOOSTER (Tanque principal)
    // Condición 3: Altura > 140km (Backup de seguridad)
    
    IF currentSeparaParts < initialSeparaParts OR currentBoosterParts < initialBoosterParts OR (initialBoosterParts > 0 AND currentBoosterParts = 0) {
        PRINT "¡SEPARACIÓN DETECTADA (Por Partes)!".
        BREAK.
    }
    
    IF SHIP:ALTITUDE > 140000 AND SHIP:VERTICALSPEED > 0 {
        PRINT "¡SEPARACIÓN DETECTADA (Por Altitud > 140km)!".
        BREAK.
    }
    
    WAIT 0.1.
    LogTelemetryShip("ASCENT F1").
}

PRINT "Esperando 1 segundo post-separación...".
WAIT 1.

// --- SECUENCIA DE ENCENDIDO ---


PRINT ">>> ENCENDIENDO MOTORES S (S1-S4) <<<".
FOR eng IN motoresS {
    eng:ACTIVATE.
    SET eng:THRUSTLIMIT TO 100.
}

PRINT "Esperando 3 segundos para SEC...".
WAIT 3.

PRINT ">>> ENCENDIENDO MOTORES SEC (SEC1-SEC2) <<<".
FOR eng IN motoresSEC {
    eng:ACTIVATE.
    SET eng:THRUSTLIMIT TO 100.
}

WAIT 1.

PRINT " ".
PRINT "¡Todos los motores activos! Iniciando ascenso orbital...".
PRINT " ".

PRINT "Iniciando aceleración progresiva (10% a 60% en 5s)...".
SET throttleVal TO 0.1. // Iniciar al 10%
LOCK THROTTLE TO throttleVal.

SET rampStartTime TO TIME:SECONDS.
UNTIL (TIME:SECONDS - rampStartTime) >= 5 {
    SET elapsed TO TIME:SECONDS - rampStartTime.
    SET throttleVal TO 0.1 + (0.5 * (elapsed / 5)). // Rampa a 60%
    WAIT 0.01.
}
SET throttleVal TO 0.6. // LIMITADO A 60%
PRINT "Potencia al 60% (LIMITADA).".

// Parámetros orbitales objetivo (200km)
SET targetApoapsis TO 200000. 
SET targetPeriapsis TO 200000.

PRINT "════════════════════════════════════════".
PRINT "    OBJETIVO: ÓRBITA 200km x 200km".
PRINT "════════════════════════════════════════".
PRINT " ".

PRINT "FASE 1: Elevando apoapsis a 200km...".
PRINT "Pitch fijo en 15° hasta alcanzar 200km de apoapsis".
PRINT " ".

// FASE 1: Pitch fijo de 15 grados
SET currentPitch TO 15.
LOCK STEERING TO HEADING(90, 15).

// Quemar hasta alcanzar apoapsis de 200km
UNTIL SHIP:APOAPSIS > targetApoapsis {
    
    LOCK STEERING TO HEADING(90, 15).
    
    SET apoHeight TO SHIP:APOAPSIS.
    SET vSpeed TO SHIP:VERTICALSPEED.
    
    LOCK THROTTLE TO 0.6. // LIMITADO A 60%
    
    SET apoaDiff TO targetApoapsis - apoHeight.
    
    // Telemetría Fase 1
    PRINT "┌─────────────────────────────────────┐" AT (0, 18).
    PRINT "│    FASE 1: ELEVANDO APOAPSIS        │" AT (0, 19).
    PRINT "│    (Pitch fijo: 15°)                │" AT (0, 20).
    PRINT "├─────────────────────────────────────┤" AT (0, 21).
    PRINT "│ Altitud:    " + ROUND(SHIP:ALTITUDE/1000, 2) + " km       " AT (0, 22).
    PRINT "│ Apoapsis:   " + ROUND(apoHeight/1000, 2) + " km       " AT (0, 23).
    PRINT "│ Objetivo:   200.0 km                │" AT (0, 24).
    PRINT "│ Falta:      " + ROUND(apoaDiff/1000, 2) + " km       " AT (0, 25).
    PRINT "│ Periapsis:  " + ROUND(SHIP:PERIAPSIS/1000, 2) + " km       " AT (0, 26).
    PRINT "│ V.Vertical: " + ROUND(vSpeed, 1) + " m/s       " AT (0, 27).
    PRINT "│ Velocidad:  " + ROUND(SHIP:VELOCITY:ORBIT:MAG, 1) + " m/s       " AT (0, 28).
    PRINT "│ Pitch:      15°                     │" AT (0, 29).
    PRINT "│ Throttle:   " + ROUND(THROTTLE * 100, 0) + "%       " AT (0, 30).
    PRINT "└─────────────────────────────────────┘" AT (0, 31).
    
    WAIT 0.1.
    LogTelemetryShip("ASCENT F1").
}

PRINT " ".
PRINT "✓ Apoapsis de 200km ALCANZADO!".
PRINT " ".
PRINT "FASE 2: Circularizando órbita...".
PRINT "Cambiando a control manual de PITCH".
PRINT " ".

// FASE 2: Cambiar a heading con pitch 0 para circularizar
SET currentPitch TO 0.
LOCK STEERING TO HEADING(90, currentPitch).

// Esperar 2 segundos para estabilizar orientación
WAIT 2.

PRINT "Quemando en horizontal para elevar periapsis...".
PRINT " ".

// Quemar horizontalmente hasta periapsis de 200km
// SISTEMA MEJORADO: SIN COASTING, THROTTLE SIEMPRE ACTIVO
UNTIL SHIP:PERIAPSIS > targetPeriapsis {
    
    SET vSpeed TO SHIP:VERTICALSPEED.
    SET periHeight TO SHIP:PERIAPSIS.
    SET periDiff TO targetPeriapsis - periHeight.
    SET apoHeight TO SHIP:APOAPSIS.
    
    // === SISTEMA DE CONTROL DE PITCH MEJORADO V2 ===
    // Prioridad 1: Si apoapsis > objetivo, NO subir más (pitch bajo)
    // Prioridad 2: Mantener velocidad vertical segura
    // Prioridad 3: Circularizar eficientemente
    
    // Calcular exceso de apoapsis
    SET apoExcess TO apoHeight - targetApoapsis.
    
    // === MODO APOAPSIS EXCEDIDO ===
    IF apoExcess > 0 {
        // Apoapsis ya pasó el objetivo - PITCH BAJO para no subirlo más
        
        IF apoExcess > 50000 {
            // Muy por encima (>50km extra): Pitch negativo para bajar apoapsis
            SET currentPitch TO -5.
            SET statusText TO "BAJANDO APO (Pitch -5)".
        } ELSE IF apoExcess > 20000 {
            // Bastante por encima (20-50km extra): Pitch casi horizontal
            SET currentPitch TO 0.
            SET statusText TO "APO ALTO (Pitch 0)".
        } ELSE {
            // Poco por encima (<20km extra): Pitch mínimo
            SET currentPitch TO 2.
            SET statusText TO "APO OK (Pitch 2)".
        }
        
        // SEGURIDAD: Si caemos muy rápido, subir pitch un poco
        IF vSpeed < -30 {
            SET currentPitch TO MAX(currentPitch, 10).
            SET statusText TO "CORRIGIENDO CAIDA".
        }
        IF vSpeed < -60 {
            SET currentPitch TO 25. // Emergencia
            SET statusText TO "EMERGENCIA VS".
            HUDTEXT("EMERGENCIA: Velocidad vertical critica!", 1, 2, 25, RED, FALSE).
        }
        
    } ELSE {
        // === MODO NORMAL: Apoapsis aún no alcanza objetivo ===
        // Usar sistema proporcional original
        
        SET targetVSpeed TO 5. // Mantener +5 m/s vertical
        
        IF vSpeed < -20 {
            SET targetVSpeed TO 15. // Subir pitch agresivamente
        }
        
        SET pitchError TO targetVSpeed - vSpeed.
        SET kp TO 1.5.
        SET currentPitch TO pitchError * kp.
        
        // Límites
        IF currentPitch < 5 { SET currentPitch TO 5. }
        IF currentPitch > 45 { SET currentPitch TO 45. }
        
        SET statusText TO "ELEVANDO APO".
        
        // Emergencia
        IF vSpeed < -50 {
            SET currentPitch TO 60.
            SET statusText TO "EMERGENCIA".
            HUDTEXT("EMERGENCIA: Velocidad vertical critica!", 1, 2, 25, RED, FALSE).
        }
    }
    
    LOCK STEERING TO HEADING(90, currentPitch).
    
    // === THROTTLE LIMITADO A 60% ===
    // Empuje reducido para evitar sobrepaso de apoapsis
    SET throttleSetting TO 0.6. // LIMITADO A 60%
    SET statusText TO "QUEMANDO 60%".
    
    // Reducir más si el apoapsis se dispara demasiado
    IF apoExcess > 50000 {
        SET throttleSetting TO 0.4. // Reducir a 40%
        SET statusText TO "THROTTLE 40% (Apo muy alto)".
    } ELSE IF apoExcess > 20000 {
        SET throttleSetting TO 0.5. // Reducir a 50%
        SET statusText TO "THROTTLE 50% (Apo alto)".
    }
    
    LOCK THROTTLE TO throttleSetting.
    
    // Telemetría Fase 2 MEJORADA
    PRINT "┌─────────────────────────────────────┐" AT (0, 18).
    PRINT "│  FASE 2: CIRCULARIZACIÓN            │" AT (0, 19).
    PRINT "│  (MODO CONTINUO - SIN COASTING)     │" AT (0, 20).
    PRINT "├─────────────────────────────────────┤" AT (0, 21).
    PRINT "│ Altitud:    " + ROUND(SHIP:ALTITUDE/1000, 2) + " km       " AT (0, 22).
    PRINT "│ Apoapsis:   " + ROUND(apoHeight/1000, 2) + " km       " AT (0, 23).
    PRINT "│ Periapsis:  " + ROUND(periHeight/1000, 2) + " km       " AT (0, 24).
    PRINT "│ Objetivo:   200.0 km                │" AT (0, 25).
    PRINT "│ Falta:      " + ROUND(periDiff/1000, 2) + " km       " AT (0, 26).
    PRINT "│ V.Vertical: " + ROUND(vSpeed, 1) + " m/s       " AT (0, 27).
    PRINT "│ Velocidad:  " + ROUND(SHIP:VELOCITY:ORBIT:MAG, 1) + " m/s       " AT (0, 28).
    PRINT "│ Pitch:      " + ROUND(currentPitch, 1) + "°       " AT (0, 29).
    PRINT "│ Throttle:   " + ROUND(throttleSetting * 100, 0) + "% [" + statusText + "]" AT (0, 30).
    PRINT "└─────────────────────────────────────┘" AT (0, 31).
    
    WAIT 0.1.
    LogTelemetryShip("ASCENT F2 (CIRC)").
}

// Apagar motores al completar
FOR eng IN motoresS {
    eng:SHUTDOWN.
}
FOR eng IN motoresSEC {
    eng:SHUTDOWN.
}

    LOCK THROTTLE TO 0.
    
    // Cortar comunicación INMEDIATAMENTE al apagar motores
    CortarComunicacion().

    PRINT " ".
PRINT "════════════════════════════════════════".
PRINT "      ✓ ÓRBITA ESTABLECIDA ✓".
PRINT "════════════════════════════════════════".
PRINT " ".
PRINT "Parámetros orbitales finales:".
PRINT "  • Apoapsis:  " + ROUND(SHIP:APOAPSIS/1000, 2) + " km".
PRINT "  • Periapsis: " + ROUND(SHIP:PERIAPSIS/1000, 2) + " km".
PRINT "  • Altitud:   " + ROUND(SHIP:ALTITUDE/1000, 2) + " km".
PRINT "  • Velocidad: " + ROUND(SHIP:VELOCITY:ORBIT:MAG, 1) + " m/s".
PRINT " ".
PRINT "════════════════════════════════════════".
PRINT "      ✓✓ MISIÓN COMPLETADA ✓✓".
PRINT "════════════════════════════════════════".
PRINT " ".

} // End of IF NOT skipAscent block


// --- FUNCIONES DE MANIOBRA ---

DECLARE FUNCTION EjecutarManiobraOrbital {
    PARAMETER targetAlt. // Altura objetivo en metros
    
    PRINT " ".
    PRINT "════════════════════════════════════════".
    PRINT "  INICIANDO CAMBIO DE ÓRBITA".
    PRINT "  Objetivo: " + ROUND(targetAlt/1000, 0) + " km".
    PRINT "════════════════════════════════════════".
    PRINT " ".

    // 1. Chequear Apoapsis actual vs Objetivo
    // Si la diferencia es mayor a 1km, corregir Apoapsis
    IF ABS(SHIP:APOAPSIS - targetAlt) > 1000 {
        PRINT ">> FASE 1: Ajustando Apoapsis...".
        
        // Decidir dónde quemar: 
        // Si queremos SUBIR el Apoapsis, quemamos en Periapsis.
        // Si queremos BAJAR el Apoapsis, quemamos en Periapsis.
        // PERO esto solo es eficiente si estamos en el punto opuesto.
        // Simplificación: Hohmann Transfer siempre inicia en el punto opuesto al que queremos cambiar.
        // Para cambiar Apoapsis -> Quemar en Periapsis.
        
        PRINT "Calculando maniobra en PERIAPSIS...".
        
        SET r1 TO SHIP:BODY:RADIUS + SHIP:PERIAPSIS.
        SET r2 TO SHIP:BODY:RADIUS + targetAlt.
        SET mu TO SHIP:BODY:MU.
        
        // V actual en Periapsis
        SET v1 TO SQRT(mu * (2/r1 - 1/(SHIP:ORBIT:SEMIMAJORAXIS))).
        // V necesaria para llegar a r2 (nuevo apoapsis)
        // El nuevo eje semimayor será (r1 + r2) / 2
        SET sma2 TO (r1 + r2) / 2.
        SET v2 TO SQRT(mu * (2/r1 - 1/sma2)).
        
        SET deltaV TO v2 - v1.
        
        PRINT "Delta-V: " + ROUND(deltaV, 1) + " m/s".
        
        // Nodo en Periapsis
        SET nd TO NODE(TIME:SECONDS + ETA:PERIAPSIS, 0, 0, deltaV).
        ADD nd.
        EjecutarNodo(nd).
    } ELSE {
        PRINT "Apoapsis ya está en objetivo (OK).".
    }
    
    // 2. Circularizar en Apoapsis (que ahora debería ser targetAlt, o cerca)
    // El Apoapsis actual debería ser aprox targetAlt.
    // Ahora queremos que el Periapsis TAMBIÉN sea targetAlt.
    // Para cambiar Periapsis -> Quemar en Apoapsis.
    
    WAIT 1.
    PRINT " ".
    PRINT ">> FASE 2: Circularizando (Ajustando Periapsis)...".
    
    // Recalcular por si hubo errores
    IF ABS(SHIP:PERIAPSIS - targetAlt) > 1000 {
        PRINT "Calculando maniobra en APOAPSIS...".
        
        SET r1 TO SHIP:BODY:RADIUS + SHIP:APOAPSIS. // Estamos o vamos al apoapsis
        SET r2 TO SHIP:BODY:RADIUS + targetAlt.     // Queremos que el otro lado sea targetAlt
        
        // V actual en Apoapsis
        SET v1 TO SQRT(mu * (2/r1 - 1/(SHIP:ORBIT:SEMIMAJORAXIS))).
        // V necesaria para orbita circular en r1 (que es aprox targetAlt)
        // Si ya estamos en Apo ~ Target, queremos circularizar AQUI.
        // Pero cuidado: Si venimos de una órbita MAYOR, r1 es el punto bajo? No, Apoapsis es el alto.
        // Siempre circularizamos al final de Hohmann.
        
        SET vCircular TO SQRT(mu / r1). 
        SET deltaV TO vCircular - v1.
        
        PRINT "Delta-V: " + ROUND(deltaV, 1) + " m/s".
        
        // Nodo en Apoapsis
        SET nd TO NODE(TIME:SECONDS + ETA:APOAPSIS, 0, 0, deltaV).
        ADD nd.
        EjecutarNodo(nd).
    } ELSE {
        PRINT "Periapsis ya está en objetivo (OK).".
    }
    
    PRINT " ".
    PRINT "✓ MANIOBRA COMPLETADA".
    PRINT "  Órbita actual: " + ROUND(SHIP:APOAPSIS/1000, 0) + "x" + ROUND(SHIP:PERIAPSIS/1000, 0) + " km".
    WAIT 3.
}

DECLARE FUNCTION EjecutarReentrada {
    PRINT " ".
    PRINT "════════════════════════════════════════".
    PRINT "  INICIANDO SECUENCIA DE REENTRADA".
    PRINT "════════════════════════════════════════".
    PRINT " ".
    
    PRINT "1. Orientando a RETROGRADE...".
    LOCK STEERING TO RETROGRADE.
    WAIT 10. // Esperar giro
    
    PRINT "2. Quemando para bajar Periapsis a 30km...".
    
    // Quemamos hasta que PE < 30000
    LOCK THROTTLE TO 1.0.
    
    UNTIL SHIP:PERIAPSIS < 30000 {
        PRINT "Periapsis: " + ROUND(SHIP:PERIAPSIS/1000, 1) + " km    " AT(0, 30).
        WAIT 0.1.
        LogTelemetryShip("REENTRY BURN").
    }
    
    LOCK THROTTLE TO 0.
    PRINT " ".
    PRINT "3. Periapsis de reentrada alcanzado.".
    PRINT "   Desacoplando módulo de servicio (si existe) y preparando para el infierno.".
    
    // Opcional: Desacoplar algo si fuera necesario, o simplemente orientar
    // Asumimos reentrada balística o controlada por aerodinámica
    
    UNLOCK STEERING.
    SAS ON.
    WAIT 1.
    SET SASMODE TO "RETROGRADE".
    
    PRINT " ".
    PRINT "¡BUENA SUERTE!".
    WAIT 3.
}

DECLARE FUNCTION EjecutarNodo {
    PARAMETER nd.
    
    PRINT "Ejecutando nodo en T-" + ROUND(nd:ETA, 0) + "s".
    LOCK STEERING TO nd:DELTAV.
    
    // Esperar hasta quemado
    WAIT UNTIL nd:ETA < 10. // Esperar cerca
    PRINT "Encendiendo motores...".
    
    // Encender SEC
    FOR eng IN motoresSEC { eng:ACTIVATE. }
    
    LOCK THROTTLE TO 1.0.
    
    SET done TO FALSE.
    SET initialDv TO nd:DELTAV.
    
    UNTIL done {
        SET currentDv TO nd:DELTAV.
        // Si el vector deltaV empieza a crecer (o se invierte el producto punto), paramos
        IF VDOT(initialDv, currentDv) < 0.5 {
            SET done TO TRUE.
        }
        // O si ya es muy pequeño
        IF currentDv:MAG < 0.2 {
            SET done TO TRUE.
        }
        
        PRINT "dV restante: " + ROUND(currentDv:MAG, 1) + " m/s   " AT(0, 31).
        WAIT 0.01.
        LogTelemetryShip("MANEUVER").
    }
    
    LOCK THROTTLE TO 0.
    FOR eng IN motoresSEC { eng:SHUTDOWN. }
    UNLOCK STEERING.
    REMOVE nd.
    PRINT "Quermado finalizado.".
    WAIT 1.
}


// --- MENÚ ORBITAL PRINCIPAL ---
SET menuExit TO FALSE.

UNTIL menuExit {
    CLEARSCREEN.
    PRINT "════════════════════════════════════════".
    PRINT "         MENÚ ORBITAL AVANZADO".
    PRINT "════════════════════════════════════════".
    PRINT "Estado: EN ÓRBITA".
    PRINT "Altitud: " + ROUND(SHIP:ALTITUDE/1000, 1) + " km".
    PRINT "Apo/Peri: " + ROUND(SHIP:APOAPSIS/1000, 0) + " / " + ROUND(SHIP:PERIAPSIS/1000, 0) + " km".
    PRINT " ".
    PRINT "SELECCIONA UNA OPCIÓN:".
    PRINT "  [1] Ir a Órbita 200km x 200km".
    PRINT "  [2] Ir a Órbita 800km x 800km".
    PRINT "  [3] REENTRAR (Deorbit)".
    PRINT "  [4] Dispensar Satélites".
    PRINT "  [5] Salir / Terminar Script".
    PRINT " ".
    PRINT "Comando > ".
    
    SET input TO TERMINAL:INPUT:GETCHAR().
    
    IF input = "1" {
        EjecutarManiobraOrbital(200000).
    } 
    ELSE IF input = "2" {
        EjecutarManiobraOrbital(800000).
    }
    ELSE IF input = "3" {
        PRINT "¡ADVERTENCIA! ¿SOLICITASTE REENTRADA? (S/N)".
        SET confirm TO TERMINAL:INPUT:GETCHAR().
        IF confirm = "s" OR confirm = "S" {
            EjecutarReentrada().
            SET menuExit TO TRUE. // Salir después de reentrar
        }
    }
    ELSE IF input = "4" {
        // Lógica de satélites existente
        PRINT "Buscando satélites...".
        // (Reutilizando la lógica simple de tags)
        SET satellitesList TO LIST().
        FROM {LOCAL i IS 1.} UNTIL i > 10 STEP {SET i TO i + 1.} DO {
            SET tagName TO "SEPARA" + i.
            IF SHIP:PARTSTAGGED(tagName):LENGTH > 0 satellitesList:ADD(tagName).
        }
        
        IF satellitesList:LENGTH > 0 {
            FOR satTag IN satellitesList {
                PRINT "Dispensando " + satTag + "...".
                FOR part IN SHIP:PARTSTAGGED(satTag) {
                    IF part:HASMODULE("ModuleDecouple") part:GETMODULE("ModuleDecouple"):DOEVENT("decouple").
                }
                WAIT 1.
            }
            PRINT "Satélites dispensados.".
        } ELSE {
            PRINT "No se encontraron satélites (Tags SEPARA1..10).".
        }
        WAIT 2.
    }
    ELSE IF input = "5" {
        SET menuExit TO TRUE.
    }
}

PRINT "Script finalizado. Control manual.".

DECLARE FUNCTION CortarComunicacion {
    PRINT " ".
    PRINT "════════════════════════════════════════".
    PRINT "   CORTANDO COMUNICACIÓN CON 1ª ETAPA".
    PRINT "════════════════════════════════════════".
    
    // Reducir distancia de carga para descargar la primera etapa
    SET SHIP:LOADDISTANCE:ORBIT:UNLOAD TO 10000.
    SET SHIP:LOADDISTANCE:ORBIT:LOAD TO 9000.
    
    // Y la global por si acaso
    SET KUNIVERSE:DEFAULTLOADDISTANCE:ORBIT:UNLOAD TO 10000.
    SET KUNIVERSE:DEFAULTLOADDISTANCE:ORBIT:LOAD TO 9000.
    
    HUDTEXT("COMUNICACIÓN CORTADA - ESPERANDO CONTROL MANUAL", 10, 2, 30, YELLOW, FALSE).
    PRINT "Distancia de carga reducida a 10km.".
    PRINT " ".
}

