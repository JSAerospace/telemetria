// NEW-GLENN-2ETAPA.KS
// Script de la 2ª Etapa del New Glenn - Inserción Orbital Inteligente
// Calcula TWR, delta-V y burn time dinámicamente según la carga

CLEARSCREEN.
SET TERMINAL:HEIGHT TO 22.
SET TERMINAL:WIDTH TO 45.

// === CONSTANTES ORBITALES ===
LOCAL mu IS BODY:MU.              // Parámetro gravitacional (m³/s²)
LOCAL R_body IS BODY:RADIUS.      // Radio del cuerpo (m)

// === FUNCION DE REFUERZO DE CARGA ===
FUNCTION ReforzarCarga {
    WAIT 0.01.
    SET SHIP:LOADDISTANCE:FLYING:UNLOAD TO 1750000.
    SET SHIP:LOADDISTANCE:FLYING:LOAD TO 1700000.
    WAIT 0.001.
    SET SHIP:LOADDISTANCE:FLYING:PACK TO 1749500.
    SET SHIP:LOADDISTANCE:FLYING:UNPACK TO 1699000.
    
    WAIT 0.01.
    SET SHIP:LOADDISTANCE:SUBORBITAL:UNLOAD TO 1750000.
    SET SHIP:LOADDISTANCE:SUBORBITAL:LOAD TO 1700000.
    WAIT 0.001.
    SET SHIP:LOADDISTANCE:SUBORBITAL:PACK TO 1749500.
    SET SHIP:LOADDISTANCE:SUBORBITAL:UNPACK TO 1699000.
    
    WAIT 0.01.
    SET SHIP:LOADDISTANCE:ORBIT:UNLOAD TO 1750000.
    SET SHIP:LOADDISTANCE:ORBIT:LOAD TO 1700000.
    WAIT 0.001.
    SET SHIP:LOADDISTANCE:ORBIT:PACK TO 1749500.
    SET SHIP:LOADDISTANCE:ORBIT:UNPACK TO 1699000.
}

// === FUNCION: EMPUJE TOTAL DE LOS MOTORES DE LA ETAPA ===
FUNCTION EmpujeEtapa {
    LOCAL thrust IS 0.
    LOCAL tags IS LIST("1E", "2E").
    FOR tag IN tags {
        LOCAL motores IS SHIP:PARTSTAGGED(tag).
        FOR eng IN motores {
            IF eng:ISTYPE("Engine") AND eng:IGNITION {
                SET thrust TO thrust + eng:AVAILABLETHRUST.
            }
        }
    }
    RETURN thrust.
}

// === FUNCION: ISP MEDIO PONDERADO POR EMPUJE ===
FUNCTION IspMedio {
    LOCAL totalThrust IS 0.
    LOCAL sumFlow IS 0.
    LOCAL tags IS LIST("1E", "2E").
    FOR tag IN tags {
        LOCAL motores IS SHIP:PARTSTAGGED(tag).
        FOR eng IN motores {
            IF eng:ISTYPE("Engine") AND eng:IGNITION AND eng:ISP > 0 {
                SET totalThrust TO totalThrust + eng:AVAILABLETHRUST.
                SET sumFlow TO sumFlow + (eng:AVAILABLETHRUST / eng:ISP).
            }
        }
    }
    IF sumFlow > 0 RETURN totalThrust / sumFlow.
    RETURN 1. // fallback seguro
}

// === FUNCION: TWR ACTUAL ===
FUNCTION TWR_Actual {
    LOCAL thrust IS EmpujeEtapa().
    LOCAL weight IS SHIP:MASS * BODY:MU / (BODY:RADIUS + SHIP:ALTITUDE)^2.
    IF weight > 0 RETURN thrust / weight.
    RETURN 0.
}

// === FUNCION: DELTA-V CIRCULARIZACIÓN (Vis-Viva) ===
// Calcula el dV necesario para circularizar en el apoapsis actual
FUNCTION DeltaV_Circular {
    LOCAL r_apo IS R_body + SHIP:APOAPSIS.
    LOCAL a_actual IS SHIP:OBT:SEMIMAJORAXIS.
    
    // Velocidad actual en el apoapsis (vis-viva)
    LOCAL v_apo IS SQRT(mu * (2/r_apo - 1/a_actual)).
    // Velocidad circular objetivo
    LOCAL v_circ IS SQRT(mu / r_apo).
    
    RETURN v_circ - v_apo.
}

// === FUNCION: TIEMPO DE QUEMADO (Tsiolkovsky) ===
// Calcula cuánto durará el quemado dado un dV objetivo
FUNCTION TiempoQuemado {
    PARAMETER dv.
    LOCAL isp IS IspMedio().
    LOCAL ve IS isp * 9.80665.        // Velocidad de escape efectiva
    LOCAL m0 IS SHIP:MASS * 1000.     // Masa en kg
    LOCAL F IS EmpujeEtapa() * 1000.  // Empuje en N
    
    IF F <= 0 OR ve <= 0 RETURN 9999. // fallback seguro
    
    // Tsiolkovsky: t = (m0 * ve / F) * (1 - e^(-dv/ve))
    LOCAL burnTime IS (m0 * ve / F) * (1 - (CONSTANT:E)^(-dv / ve)).
    RETURN burnTime.
}

PRINT "=============================================" AT (0, 0).
PRINT "     NEW GLENN - 2DA ETAPA INTELIGENTE       " AT (0, 1).
PRINT "=============================================" AT (0, 2).

PRINT "Esperando separacion (INTER)..." AT (0, 4).

// Esperamos a que la pieza con tag INTER ya no este (separacion)
WAIT UNTIL SHIP:PARTSTAGGED("INTER"):LENGTH = 0.

PRINT "SEPARACION CONFIRMADA." AT (0, 5).
LOCAL t_separacion IS TIME:SECONDS. // Timestamp de la separación
WAIT 0.5.
RCS ON.
PRINT "IGNICION DE MOTORES 1E y 2E..." AT (0, 6).

// Activar motores de la 2da etapa
LOCAL tagsMotores IS LIST("1E", "2E").

FOR tag IN tagsMotores {
    LOCAL motores IS SHIP:PARTSTAGGED(tag).
    FOR eng IN motores {
        IF eng:ISTYPE("Engine") {
            eng:ACTIVATE().
        }
    }
}

PRINT "MOTORES ACTIVADOS." AT (0, 7).

LOCAL apo_target IS 120000. // 120 km
LOCAL peri_target IS 115000. // 115 km para circularizar

// Diagnóstico inicial de TWR
LOCAL twr0 IS TWR_Actual().
PRINT "TWR inicial: " + ROUND(twr0, 2) AT (0, 8).
PRINT "Masa total:  " + ROUND(SHIP:MASS, 2) + " t" AT (0, 9).
WAIT 2.

// === FASE 1: ASCENSO AL APOAPSIS (PITCH ADAPTATIVO POR TWR) ===
CLEARSCREEN.
PRINT "=============================================" AT (0, 0).
PRINT "  FASE 1: ASCENSO ADAPTATIVO AL APOAPSIS     " AT (0, 1).
PRINT "=============================================" AT (0, 2).

LOCAL pitchActual IS 25.
LOCK THROTTLE TO 1.0.
LOCAL cofiasSeparadas IS FALSE.

UNTIL SHIP:APOAPSIS >= apo_target {
    ReforzarCarga(). // Mantener naves cargadas
    
    // SEPARACION DE COFIAS A LOS 30s POST-SEPARACION
    IF NOT cofiasSeparadas AND (TIME:SECONDS - t_separacion) > 30 {
        LOCAL cofias IS SHIP:PARTSTAGGED("COFIA").
        FOR c IN cofias {
            IF c:HASMODULE("ModuleProceduralFairing") {
                c:GETMODULE("ModuleProceduralFairing"):DOEVENT("deploy").
            } ELSE IF c:HASMODULE("ModuleDecouple") {
                c:GETMODULE("ModuleDecouple"):DOEVENT("separar").
            } ELSE IF c:HASMODULE("ModuleAnchoredDecoupler") {
                c:GETMODULE("ModuleAnchoredDecoupler"):DOEVENT("separar").
            }
        }
        SET cofiasSeparadas TO TRUE.
        PRINT "COFIAS SEPARADAS (T+30s)." AT (0, 3).
    }
    
    // --- PITCH ADAPTATIVO SEGÚN TWR ---
    // TWR alto (carga ligera) -> pitch base más alto, sube rápido
    // TWR bajo (carga pesada) -> pitch base más bajo, prioriza horizontal
    LOCAL twr IS TWR_Actual().
    LOCAL errorAp IS apo_target - SHIP:APOAPSIS.
    LOCAL progreso IS 1 - (errorAp / apo_target). // 0 al inicio, 1 al final
    
    // Pitch base escalado por TWR: más TWR = puede permitirse más vertical
    LOCAL pitchBase IS MIN(30, MAX(10, twr * 12)).
    // Reducir pitch progresivamente conforme se acerca al apoapsis objetivo
    SET pitchActual TO pitchBase * (1 - progreso * 0.85).
    // Límites de seguridad
    SET pitchActual TO MAX(2, MIN(35, pitchActual)).
    
    LOCK STEERING TO HEADING(90, pitchActual).
    
    // DISPLAY
    PRINT "Apoapsis:  " + ROUND(SHIP:APOAPSIS/1000, 2) + " km      " AT (0, 5).
    PRINT "Periapsis: " + ROUND(SHIP:PERIAPSIS/1000, 2) + " km      " AT (0, 6).
    PRINT "Pitch:     " + ROUND(pitchActual, 1) + " deg     " AT (0, 7).
    PRINT "TWR:       " + ROUND(twr, 2) + "          " AT (0, 8).
    PRINT "Masa:      " + ROUND(SHIP:MASS, 2) + " t      " AT (0, 9).
    
    WAIT 0.05.
}

// === FASE 2: PLANEO + CALCULO INTELIGENTE (SIN NODO) ===
// No usamos maneuver nodes porque esta nave NO es la activa (el jugador controla el booster)
LOCK THROTTLE TO 0.

// --- CALCULAR DELTA-V Y BURN TIME ANTES DE APAGAR MOTORES ---
// (EmpujeEtapa() necesita eng:IGNITION = TRUE para leer el empuje)
LOCAL dv_circ IS DeltaV_Circular().
LOCAL burnDur IS TiempoQuemado(dv_circ).
LOCAL halfBurn IS MAX(5, burnDur / 2). // Mínimo 5 segundos de margen

// Velocidad orbital circular objetivo en el apoapsis
LOCAL r_apo_circ IS R_body + SHIP:APOAPSIS.
LOCAL v_circular_target IS SQRT(mu / r_apo_circ).

// AHORA apagar motores (ya tenemos los cálculos)
FOR tag IN tagsMotores {
    LOCAL motores IS SHIP:PARTSTAGGED(tag).
    FOR eng IN motores {
        IF eng:ISTYPE("Engine") { eng:SHUTDOWN(). }
    }
}

CLEARSCREEN.
PRINT "=============================================" AT (0, 0).
PRINT "  FASE 2: PLANEO + CALCULO ORBITAL           " AT (0, 1).
PRINT "=============================================" AT (0, 2).

RCS ON.
LOCK STEERING TO SHIP:PROGRADE.

PRINT "Delta-V circ:    " + ROUND(dv_circ, 1) + " m/s" AT (0, 4).
PRINT "Burn estimado:   " + ROUND(burnDur, 1) + " s" AT (0, 5).
PRINT "Inicio en T-     " + ROUND(halfBurn, 1) + " s" AT (0, 6).
PRINT "V circular obj:  " + ROUND(v_circular_target, 1) + " m/s" AT (0, 7).
PRINT "Masa actual:     " + ROUND(SHIP:MASS, 2) + " t" AT (0, 8).

// Orientarse hacia progrado (es donde quemaremos)
LOCK STEERING TO SHIP:PROGRADE.
PRINT "Orientando a progrado..." AT (0, 10).

// Esperar orientación correcta (dentro de 5°)
WAIT UNTIL VANG(SHIP:FACING:FOREVECTOR, SHIP:PROGRADE:FOREVECTOR) < 5.
PRINT "Orientacion correcta.         " AT (0, 10).

// Esperar hasta T - halfBurn antes del apoapsis
UNTIL ETA:APOAPSIS <= halfBurn OR SHIP:VERTICALSPEED < -1 {
    ReforzarCarga().
    
    // Recalcular solo dV (no requiere motores), NO burn time
    SET dv_circ TO DeltaV_Circular().
    
    PRINT "ETA Apoapsis: " + ROUND(ETA:APOAPSIS, 1) + " s      " AT (0, 12).
    PRINT "dV necesario: " + ROUND(dv_circ, 1) + " m/s    " AT (0, 13).
    PRINT "Inicio en:    " + ROUND(ETA:APOAPSIS - halfBurn, 1) + " s    " AT (0, 14).
    PRINT "Altitud:      " + ROUND(SHIP:ALTITUDE/1000, 2) + " km    " AT (0, 15).
    PRINT "halfBurn:     " + ROUND(halfBurn, 1) + " s    " AT (0, 16).
    
    LOCK STEERING TO SHIP:PROGRADE.
    WAIT 0.1.
}

// === FASE 3: QUEMADO DE CIRCULARIZACIÓN INTELIGENTE (SIN NODO) ===
CLEARSCREEN.
PRINT "=============================================" AT (0, 0).
PRINT "  FASE 3: CIRCULARIZACION INTELIGENTE        " AT (0, 1).
PRINT "=============================================" AT (0, 2).

// Re-encender motores
FOR tag IN tagsMotores {
    LOCAL motores IS SHIP:PARTSTAGGED(tag).
    FOR eng IN motores {
        IF eng:ISTYPE("Engine") { eng:ACTIVATE(). }
    }
}

LOCK STEERING TO SHIP:PROGRADE.

// Velocidad inicial al empezar el quemado
LOCAL v_start IS SHIP:VELOCITY:ORBIT:MAG.
LOCAL dv_total IS v_circular_target - v_start.
IF dv_total < 1 { SET dv_total TO dv_circ. } // fallback

UNTIL SHIP:PERIAPSIS >= 80000 {
    ReforzarCarga().
    
    // --- dV RESTANTE CALCULADO EN TIEMPO REAL ---
    // Diferencia entre velocidad circular objetivo y velocidad actual
    LOCAL v_actual IS SHIP:VELOCITY:ORBIT:MAG.
    LOCAL dvLeft IS v_circular_target - v_actual.
    IF dvLeft < 0 { SET dvLeft TO 0. }
    
    // --- CORTE DE SEGURIDAD ---
    // Si ya superamos la velocidad circular objetivo, parar inmediatamente
    IF v_actual >= v_circular_target { BREAK. }
    
    // --- THROTTLE INTELIGENTE ---
    // 100% si queda mucho dV o el periapsis está lejos
    // Reduce proporcionalmente al acercarse al objetivo
    LOCAL errorPeri IS 80000 - SHIP:PERIAPSIS.
    
    IF dvLeft > 15 {
        LOCK THROTTLE TO 1.0.
    } ELSE IF dvLeft > 3 {
        // Zona de transición: throttle proporcional al dV restante
        LOCK THROTTLE TO MAX(0.08, dvLeft / 15).
    } ELSE {
        // Precisión final: throttle muy bajo basado en error de periapsis
        LOCK THROTTLE TO MAX(0.02, MIN(0.15, errorPeri / 80000)).
    }
    
    // Progreso del quemado
    LOCAL progBurn IS 0.
    IF dv_total > 0 { SET progBurn TO (1 - dvLeft / dv_total) * 100. }
    SET progBurn TO MIN(100, MAX(0, progBurn)).
    
    // DISPLAY
    PRINT "dV restante: " + ROUND(dvLeft, 2) + " m/s     " AT (0, 4).
    PRINT "Throttle:    " + ROUND(THROTTLE * 100, 1) + " %      " AT (0, 5).
    PRINT "Apoapsis:    " + ROUND(SHIP:APOAPSIS/1000, 2) + " km    " AT (0, 6).
    PRINT "Periapsis:   " + ROUND(SHIP:PERIAPSIS/1000, 2) + " km    " AT (0, 7).
    PRINT "TWR:         " + ROUND(TWR_Actual(), 2) + "          " AT (0, 8).
    PRINT "V orbital:   " + ROUND(v_actual, 1) + " m/s    " AT (0, 9).
    PRINT "V objetivo:  " + ROUND(v_circular_target, 1) + " m/s    " AT (0, 10).
    PRINT "Progreso:    " + ROUND(progBurn, 1) + " %    " AT (0, 11).
    
    WAIT 0.01.
}

// === MECO (APAGADO FINAL) ===
LOCK THROTTLE TO 0.
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.

PRINT "ORBITA ALCANZADA." AT (0, 13).

FOR tag IN tagsMotores {
    LOCAL motores IS SHIP:PARTSTAGGED(tag).
    FOR eng IN motores {
        IF eng:ISTYPE("Engine") { eng:SHUTDOWN(). }
    }
}

// ESTABILIZACION PROGRADO
SAS OFF.
RCS ON.
LOCK STEERING TO LOOKDIRUP(SHIP:PROGRADE:FOREVECTOR, SHIP:UP:VECTOR).
PRINT "Estabilizando en progrado..." AT (0, 14).

UNTIL VANG(SHIP:FACING:FOREVECTOR, SHIP:PROGRADE:FOREVECTOR) < 2 AND SHIP:ANGULARVEL:MAG < 0.01 {
    WAIT 0.1.
}

PRINT "NAVE ESTABILIZADA." AT (0, 15).
WAIT 3.

UNLOCK THROTTLE.
UNLOCK STEERING.
RCS OFF.
SAS ON.

CLEARSCREEN.
PRINT "=============================================" AT (0, 0).
PRINT "     2DA ETAPA EN ORBITA ESTABLE              " AT (0, 1).
PRINT "=============================================" AT (0, 2).
PRINT "Apoapsis:   " + ROUND(SHIP:APOAPSIS/1000, 2) + " km" AT (0, 4).
PRINT "Periapsis:  " + ROUND(SHIP:PERIAPSIS/1000, 2) + " km" AT (0, 5).
PRINT "Masa final: " + ROUND(SHIP:MASS, 2) + " t" AT (0, 6).
PRINT "Misión de inserción orbital completada." AT (0, 10).
PRINT "Apagando computador de vuelo..." AT (0, 11).
WAIT 5.
SHUTDOWN.
