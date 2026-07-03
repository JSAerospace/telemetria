// boosterBLOCK2.ks - Script de lanzamiento
// Motores: 1-3 centrales, 4-13 medios, 14-33 exteriores
// ============================================================
// === FUNCION DE REFUERZO DE CARGA (METODO RSS) ===
// ============================================================
FUNCTION ReforzarCarga {
    // Configuración RSS - Distancias extremas para mantener conexión
    // NO reseteamos a 2500 para evitar que la Ship se borre
    SET SHIP:LOADDISTANCE:FLYING:UNLOAD TO 1750000.
    SET SHIP:LOADDISTANCE:FLYING:LOAD TO 1700000.
    SET SHIP:LOADDISTANCE:FLYING:PACK TO 1749500.
    SET SHIP:LOADDISTANCE:FLYING:UNPACK TO 1699000.
    
    SET KUNIVERSE:DEFAULTLOADDISTANCE:FLYING:UNLOAD TO 1750000.
    SET KUNIVERSE:DEFAULTLOADDISTANCE:FLYING:LOAD TO 1700000.
}


// ============================================================
// === FUNCION PARA ESCRIBIR ALTURA A JSON ===
// ============================================================
GLOBAL TELEMETRY_A IS "0:/telemetry_booster_A.json".
GLOBAL TELEMETRY_B IS "0:/telemetry_booster_B.json".
GLOBAL TELEMETRY_TOGGLE IS TRUE.

// === PERSISTENCIA DE MISIÓN (Resiliencia ante Reboots) ===
GLOBAL MISSION_STATE_FILE IS "0:/mission_state.json".

FUNCTION SaveMissionState {
    PARAMETER phase.
    LOCAL data IS LEXICON("phase", phase, "time", TIME:SECONDS, "lat", SHIP:GEOPOSITION:LAT, "lng", SHIP:GEOPOSITION:LNG).
    WRITEJSON(data, MISSION_STATE_FILE).
}

FUNCTION GetMissionState {
    IF EXISTS(MISSION_STATE_FILE) { RETURN READJSON(MISSION_STATE_FILE). }
    RETURN LEXICON("phase", "PRELAUNCH").
}

// Acumulador para la succión final (Memoria de error)
IF NOT (DEFINED PosIntegral) { GLOBAL PosIntegral IS V(0,0,0). }

FUNCTION LandingGuidance {
    LOCAL RadarRatio IS ALT:RADAR / 72. // Altura booster promedio
    LOCAL GSVec IS VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE).
    
    // 1. TARGETING DE ALTA PRECISION (Directo al OLM)
    LOCAL targetPos IS LANDING_TARGET:POSITION.
    IF TOWER_VESSEL <> 0 AND TOWER_VESSEL:ISTYPE("Vessel") AND TOWER_VESSEL:LOADED { 
        LOCAL mounts IS TOWER_VESSEL:PARTS.
        FOR p IN mounts {
            LOCAL n IS p:TITLE:TOLOWER() + p:NAME:TOLOWER().
            IF n:CONTAINS("mount") OR n:CONTAINS("olm") OR n:CONTAINS("support") {
                SET targetPos TO p:POSITION.
                BREAK.
            }
        }
    }
    
    LOCAL posErr IS VXCL(UP:VECTOR, targetPos - SHIP:POSITION).
    
    // --- INTEGRAL DE POSICIÓN (Memoria para cerrar el "casi") ---
    IF ALT:RADAR < 250 {
        SET PosIntegral TO PosIntegral + (posErr * 0.015). // Reducido un poco para evitar sobre-inclinación
        IF PosIntegral:MAG > 3 { SET PosIntegral TO PosIntegral:NORMALIZED * 3. } // Cap más estricto
    } ELSE {
        SET PosIntegral TO V(0,0,0). 
    }
    
    // 2. ESCALADO DE GANANCIAS (Pro-Starship Catch Tuning)
    // Reducido para evitar maniobras demasiado agresivas
    LOCAL Fpos IS MAX(MIN(-0.0001 * RadarRatio + 0.010, 0.020), 0.004).
    LOCAL Ferr IS MIN(MAX(0.002 * RadarRatio + 0.005, 0.010), 0.025).
    LOCAL Fgs IS MIN(MAX(-0.005 * RadarRatio + 0.05, 0.005), 0.035). 
    LOCAL Fi IS 0.02. 
    
    IF ALT:RADAR < 200 { 
        SET Fpos TO Fpos * 3.0.  
        SET Fgs TO Fgs * 2.5.   
        SET Fi TO 0.08. // Succión final más potente
    }
    
    // 3. VECTOR DE GUIADO DINÁMICO (Predictive Impact Steering)
    // Guiamos el PUNTO DE IMPACTO al objetivo, no al cohete físicamente.
    
    LOCAL steeringErr IS posErr. // Fallback: Error de posición actual
    LOCAL isLockedOn IS FALSE.
    
    // --- GUIADO POR IMPACTO ( trajectories ) ---
    IF ADDONS:TR:AVAILABLE AND ADDONS:TR:HASIMPACT {
        // Calculamos el error desde donde vamos a caer HACIA la torre
        LOCAL impactErr IS VXCL(UP:VECTOR, LANDING_TARGET:POSITION - ADDONS:TR:IMPACTPOS:POSITION).
        
        // LIMITADOR DE ERROR DE IMPACTO (Evita giros bruscos si Trajectories salta)
        IF impactErr:MAG > 40 { SET impactErr TO impactErr:NORMALIZED * 40. }
        
        SET steeringErr TO impactErr. 
        
        IF impactErr:MAG < 1.5 { SET isLockedOn TO TRUE. }
    }
    
    LOCAL distError IS steeringErr:MAG.
    LOCAL closureRate IS VDOT(GSVec, posErr:NORMALIZED). 
    
    // Escalado de ganancia dinámico (v4.0)
    // Menos error = menos corrección. Muy suave cerca del centro.
    LOCAL gainScale IS MIN(1.0, 0.05 + (distError / 15)). 
    LOCAL dynamicFpos IS Fpos * gainScale.
    LOCAL dynamicFgs IS Fgs.
    
    IF isLockedOn AND ALT:RADAR > 250 {
        SET dynamicFpos TO dynamicFpos * 0.4. // Penalización menos severa para permitir correcciones finales
        SET dynamicFgs TO dynamicFgs * 1.2. 
    }
    
    // AMORTIGUACIÓN DINÁMICA
    IF closureRate > 0.5 {
        SET dynamicFgs TO dynamicFgs * (1.3 + (closureRate / 10)).
    }
    
    // El vector de guiado ahora empuja el PUNTO DE IMPACTO hacia el centro
    LOCAL targetVec TO UP:VECTOR + (dynamicFpos * steeringErr) - (dynamicFgs * GSVec) + (Fi * PosIntegral).
    
    // Gate de precisión final (Ajustado para Catch a 200m)
    IF posErr:MAG < 0.1 AND ALT:RADAR < 210 { SET targetVec TO UP:VECTOR. }
    
    LOCAL finalDir IS targetVec:NORMALIZED.
    
    // --- LÍMITE DE INCLINACIÓN DINÁMICO ---
    // Límite firme de 12º para mantener el control y la estética de booster pesado
    LOCAL maxTiltAllowed IS MIN(12, 1.0 + (posErr:MAG * 0.4)). 
    
    // Altura: Seguridad extrema cerca del punto de captura (200m)
    IF ALT:RADAR < 300 { SET maxTiltAllowed TO MIN(maxTiltAllowed, 6). }
    
    // Si estamos alineados y bajando rápido (15m/s), permitimos un poco más de autoridad para mantener el centro
    IF ALT:RADAR < 230 { 
        IF posErr:MAG < 5.0 { SET maxTiltAllowed TO MIN(maxTiltAllowed, 4.5). }
        ELSE { SET maxTiltAllowed TO MIN(maxTiltAllowed, 3.5). } 
    }
    
    IF VANG(UP:VECTOR, finalDir) > maxTiltAllowed {
        LOCAL horizPart IS VXCL(UP:VECTOR, finalDir):NORMALIZED.
        SET finalDir TO (UP:VECTOR + horizPart * TAN(maxTiltAllowed)):NORMALIZED.
    }
    
    // --- SISTEMA DE ROLL FILTRADO (Anti-Círculos) ---
    LOCAL rawRoll IS V(0,0,0).
    IF ALT:RADAR > 500 {
        SET rawRoll TO VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE).
    } ELSE {
        SET rawRoll TO VXCL(UP:VECTOR, targetPos - SHIP:POSITION).
    }
    
    // Si el vector es muy pequeño, mantenemos el anterior o el Este
    IF NOT (DEFINED filteredRoll) { GLOBAL filteredRoll IS HEADING(90,0):VECTOR. }
    IF rawRoll:MAG > 0.05 {
        // Filtro: 5% nuevo vector, 95% anterior (suavizado extremo)
        SET filteredRoll TO (filteredRoll * 0.95 + rawRoll:NORMALIZED * 0.05):NORMALIZED.
    }
    
    // DEBUG DE ÁNGULOS (Para terminal)
    GLOBAL debug_TgtTilt IS VANG(UP:VECTOR, finalDir).
    GLOBAL debug_MaxTilt IS maxTiltAllowed.

    RETURN LOOKDIRUP(finalDir, filteredRoll).
}

FUNCTION LogTelemetry {
    PARAMETER statusText.
    
    // 1. Estados de Motores (1-33)
    LOCAL engStates IS LEXICON().
    
    IF THROTTLE > 0 {
        FOR i IN RANGE(1, 18) {
            LOCAL key IS i:TOSTRING.
            LOCAL parts IS SHIP:PARTSTAGGED(key).
            LOCAL st IS 0.
            FOR p IN parts { IF p:IGNITION { SET st TO 1. } }
            engStates:ADD(key, st).
        }
    }

    // 2. Combustible (Tag BOOSTER con Fallback a SHIP)
    LOCAL fuelPct IS 0.
    LOCAL parts IS SHIP:PARTSTAGGED("BOOSTER").
    
    // Si no hay partes tageadas, usamos todas las partes del cohete
    IF parts:LENGTH = 0 { SET parts TO SHIP:PARTS. }
    
    LOCAL curr IS 0.
    LOCAL cap IS 0.
    
    FOR p IN parts {
        FOR res IN p:RESOURCES {
            SET curr TO curr + res:AMOUNT.
            SET cap TO cap + res:CAPACITY.
        }
    }
    
    IF cap > 0 { SET fuelPct TO (curr / cap) * 100. }

    // 3. Empaquetar
    LOCAL data IS LEXICON(
        "status", statusText,
        "alt", ROUND(SHIP:ALTITUDE, 0),
        "vel", ROUND(SHIP:VELOCITY:SURFACE:MAG, 0),
        "vs", ROUND(SHIP:VERTICALSPEED, 1),
        "hdist", ROUND(VXCL(UP:VECTOR, LANDING_TARGET:POSITION - SHIP:POSITION):MAG, 0),
        "fuel", ROUND(curr, 0),
        "fuelPct", ROUND(fuelPct, 1),
        "thr", ROUND(THROTTLE * 100, 0),
        "engStates", engStates
    ).
    
    IF TELEMETRY_TOGGLE {
        WRITEJSON(data, TELEMETRY_A).
    } ELSE {
        WRITEJSON(data, TELEMETRY_B).
    }
    SET TELEMETRY_TOGGLE TO NOT TELEMETRY_TOGGLE.
}

FUNCTION EscribirAltura {
    PARAMETER h.
    LOCAL data IS LEXICON("alt", ROUND(h, 1)).
    WRITEJSON(data, "0:/altura.json").
}

WRITEJSON(LEXICON("status", "BOOT"), TELEMETRY_A).
WRITEJSON(LEXICON("status", "BOOT"), TELEMETRY_B).
WRITEJSON(LEXICON("apo", 200000, "head", 90), "0:/tomcat_config.json").
PRINT "Telemetry Init OK (A/B)" AT (0, 2).
PRINT "altura.json RESET OK" AT (0, 3).
PRINT "CONFIG SHIP OK (200km)" AT (0, 4).
IF EXISTS("0:/catch_signal.json") { DELETEPATH("0:/catch_signal.json"). }

ReforzarCarga().

PRINT "=== BOOSTER BLOCK 2 ===" AT (0, 0).
PRINT "CARGA: 1750 km ACTIVA" AT (0, 1).
GLOBAL TARGET_MODE IS "TOWER".
GLOBAL SIMULAR_FALLO_MOTOR IS FALSE.
GLOBAL TOWER_VESSEL IS 0.   // Declarado aquí para que LandingGuidance siempre lo encuentre
GLOBAL PATAS_DESPLEGADAS IS FALSE.
GLOBAL ARMS_SENT IS FALSE.
GLOBAL CATCH_COMPLETADO IS FALSE.
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
GLOBAL MISSION_STATE IS GetMissionState().
GLOBAL IS_RESUMING IS FALSE.
GLOBAL TARGET_SITE IS "TOWER". // "TOWER" o "SEA"
GLOBAL CATCH_ABORTED IS FALSE.

// Si la fase guardada NO es Prelaunch Y ADEMÁS estamos en el aire, intentamos recuperar
IF MISSION_STATE:phase <> "PRELAUNCH" AND (SHIP:STATUS <> "PRELAUNCH" AND SHIP:STATUS <> "LANDED") {
    SET IS_RESUMING TO TRUE.
    PRINT "!! RESILIENCIA: REINICIO EN FASE " + MISSION_STATE:phase + " !!" AT (0, 6).
    
    // Recuperar posición de la torre
    IF EXISTS("0:/launch_pos.json") {
        LOCAL posData IS READJSON("0:/launch_pos.json").
        SET LAUNCH_PAD TO LATLNG(posData:lat, posData:lng).
    } ELSE {
        SET LAUNCH_PAD TO SHIP:GEOPOSITION.
    }
    SET LANDING_TARGET TO LAUNCH_PAD.
    WAIT 1.
} ELSE {
    // Es una misión nueva o reset manual
    LOCAL posLog IS LEXICON("lat", SHIP:GEOPOSITION:LAT, "lng", SHIP:GEOPOSITION:LNG).
    WRITEJSON(posLog, "0:/launch_pos.json").
    SET LAUNCH_PAD TO SHIP:GEOPOSITION.
    GLOBAL LANDING_TARGET IS LAUNCH_PAD.
    SaveMissionState("PRELAUNCH").
    PRINT "COORD TORRE GUARDADAS" AT (0, 7).
}


// === DETECCIÓN DE TORRE (Siempre activa para reanudar catch) ===
GLOBAL TOWER_VESSEL IS 0.
LIST TARGETS IN allTargets.
FOR t IN allTargets {
    IF t:LOADED {
        LOCAL n IS t:NAME:TOLOWER().
        IF n:CONTAINS("tower") OR n:CONTAINS("mechazilla") OR n:CONTAINS("kanaloa")
           OR n:CONTAINS("launch") OR n:CONTAINS("olm") OR n:CONTAINS("mlt") {
            SET TOWER_VESSEL TO t.
            BREAK.
        }
    }
}
IF TOWER_VESSEL = 0 {
    FOR t IN allTargets {
        IF t:LOADED {
            FOR p IN t:PARTS {
                IF p:TAG = "TOWER" OR p:TAG = "tower" OR p:NAME:CONTAINS("OLM") OR p:TITLE:CONTAINS("Kanaloa") {
                    SET TOWER_VESSEL TO t.
                    BREAK.
                }
            }
        }
        IF TOWER_VESSEL <> 0 { BREAK. }
    }
}
IF TOWER_VESSEL = 0 AND HASTARGET {
    IF TARGET:ISTYPE("Vessel") { SET TOWER_VESSEL TO TARGET. }
}

IF TOWER_VESSEL <> 0 {
    PRINT "TOWER FOUND: " + TOWER_VESSEL:NAME AT (0, 2).
} ELSE {
    PRINT "TOWER: No detectada. La GUI mostrara NO-GO." AT (0, 2).
}

// ============================================================
// === GUI DE PRE-LANZAMIENTO — Solo si NO estamos resumiendo
// ============================================================
IF NOT IS_RESUMING {
        LOCAL launchReady IS FALSE.
        LOCAL failActive IS FALSE.
        LOCAL myGui IS GUI(280).
        LOCAL box IS myGui:ADDVBOX().
        box:ADDLABEL("=== TOMCAT HEAVY — FLIGHT COMPUTER ===").
        box:ADDLABEL(" ").
    box:ADDLABEL("VESSEL:  " + SHIP:NAME).

    LOCAL towerLbl IS box:ADDLABEL("TOWER:   Buscando...").
    LOCAL fuelLbl IS box:ADDLABEL("FUEL:    -- %").
    box:ADDLABEL("ENGINES: " + SHIP:ENGINES:LENGTH + " detectados").
    box:ADDLABEL(" ").

    LOCAL goNoGoLbl IS box:ADDLABEL("STATUS:  Verificando sistemas...").
    box:ADDLABEL(" ").

    LOCAL failBtn IS box:ADDBUTTON("[ ] Simular Fallo Motor #2").
    box:ADDLABEL(" ").

    LOCAL siteBtn IS box:ADDBUTTON("DESTINO: TORRE (RTLS)").
    box:ADDLABEL(" ").

    LOCAL launchBtn IS box:ADDBUTTON(">>> LANZAR <<<").

    SET siteBtn:ONCLICK TO {
        IF TARGET_SITE = "TOWER" {
            SET TARGET_SITE TO "SEA".
            SET siteBtn:TEXT TO "DESTINO: MAR (ASDS)".
        } ELSE {
            SET TARGET_SITE TO "TOWER".
            SET siteBtn:TEXT TO "DESTINO: TORRE (RTLS)".
        }
    }.

    SET failBtn:ONCLICK TO {
        SET failActive TO NOT failActive.
        SET SIMULAR_FALLO_MOTOR TO failActive.
        IF failActive { SET failBtn:TEXT TO "[X] Simular Fallo Motor #2 ACTIVO". }
        ELSE           { SET failBtn:TEXT TO "[ ] Simular Fallo Motor #2". }
    }.
    SET launchBtn:ONCLICK TO { SET launchReady TO TRUE. }.

    myGui:SHOW().
    WAIT 0.1.

    // --- Bucle de refresco ---
    UNTIL launchReady {
        // DETECCIÓN CONTINUA DE TORRE
        IF TOWER_VESSEL = 0 OR NOT TOWER_VESSEL:LOADED {
            LIST TARGETS IN allTargets.
            FOR t IN allTargets {
                IF t:LOADED {
                    LOCAL n IS t:NAME:TOLOWER().
                    // Búsqueda por nombre/título
                    IF n:CONTAINS("tower") OR n:CONTAINS("mechazilla") OR n:CONTAINS("olm") 
                       OR n:CONTAINS("mount") OR n:CONTAINS("launch") OR n:CONTAINS("plataforma") {
                        SET TOWER_VESSEL TO t. BREAK.
                    }
                    // Búsqueda por tag en piezas
                    FOR p IN t:PARTS {
                        IF p:TAG:TOLOWER() = "tower" OR p:TAG:TOLOWER() = "torre" {
                            SET TOWER_VESSEL TO t. BREAK.
                        }
                    }
                }
                IF TOWER_VESSEL <> 0 { BREAK. }
            }
            // Fallback: Si el usuario tiene la torre como TARGET manual
            IF TOWER_VESSEL = 0 AND HASTARGET {
                IF TARGET:ISTYPE("Vessel") { SET TOWER_VESSEL TO TARGET. }
            }
        }

        IF TOWER_VESSEL <> 0 {
            SET towerLbl:TEXT TO "TOWER:   OK - " + TOWER_VESSEL:NAME.
        } ELSE {
            SET towerLbl:TEXT TO "TOWER:   BUSCANDO...".
        }

        LOCAL fuelAct IS 0. LOCAL fuelCap IS 1.
        FOR p IN SHIP:PARTSTAGGED("BOOSTER") {
            FOR r IN p:RESOURCES {
                SET fuelAct TO fuelAct + r:AMOUNT.
                SET fuelCap TO fuelCap + r:CAPACITY.
            }
        }
        LOCAL fuelPct IS ROUND((fuelAct / fuelCap) * 100, 1).
        SET fuelLbl:TEXT TO "FUEL:    " + fuelPct + " %".

        IF TOWER_VESSEL:ISTYPE("Vessel") AND fuelPct > 90 {
            SET goNoGoLbl:TEXT TO "STATUS:  GO - LISTO PARA LANZAR".
        } ELSE IF fuelPct > 90 {
            SET goNoGoLbl:TEXT TO "STATUS:  NO-GO: Torre no detectada".
        } ELSE {
            SET goNoGoLbl:TEXT TO "STATUS:  NO-GO: Combustible bajo (" + fuelPct + "%)".
        }

        // Fallback teclado
        IF TERMINAL:INPUT:HASCHAR {
            LOCAL ch IS TERMINAL:INPUT:GETCHAR().
            IF ch = "g" OR ch = "G" { SET launchReady TO TRUE. }
            ELSE IF ch = "f" OR ch = "F" {
                SET failActive TO NOT failActive.
                SET SIMULAR_FALLO_MOTOR TO failActive.
            }
        }
        PRINT "Clic en LANZAR o presiona [G] en la terminal" AT (0, 9).
        WAIT 0.2.
    }
    // Lanzamiento iniciado
    SET launchBtn:TEXT TO "¡VOLANDO!".
    SET launchBtn:ENABLED TO FALSE.
    SET siteBtn:ENABLED TO FALSE. // Bloquear cambio de destino tras lanzar
    
    // Cambiamos el botón de fallo por el de ABORTO
    SET failBtn:TEXT TO "!!! ABORTAR CATCH !!!".
    SET failBtn:STYLE:TEXTCOLOR TO RED.
    SET failBtn:ONCLICK TO {
        SET CATCH_ABORTED TO TRUE.
        HUDTEXT("!!! ABORTO MANUAL DESDE PANEL !!!", 10, 2, 40, RED, TRUE).
    }.

    FROM { LOCAL t IS 10. } UNTIL t = 0 STEP { SET t TO t - 1. } DO {
        SET goNoGoLbl:TEXT TO "CUENTA ATRÁS: T-" + t.
        IF t = 2 {
            LOCK THROTTLE TO 1.0.
            LOCK STEERING TO HEADING(90, 90).
            FOR i IN RANGE(1, 18) {
                LOCAL motores IS SHIP:PARTSTAGGED(i:TOSTRING).
                FOR eng IN motores { eng:ACTIVATE(). }
            }
        }
        WAIT 1.
    }
    SET goNoGoLbl:TEXT TO "STATUS: EN ASCENSO".
    SaveMissionState("ASCENT").
    AG9 ON. // Desconexión de torre
    }

    SET PITCH TO 90.
    LOCK STEERING TO HEADING(90, PITCH, 90).
    
    // Solo entramos al bucle de ascenso si estamos en esa fase (nueva o resume)
    IF MISSION_STATE:phase = "ASCENT" OR NOT IS_RESUMING {
        UNTIL FALSE {
            ReforzarCarga().
            LogTelemetry("ASCENT").
            SET PITCH TO MAX(15, 90 - (ALTITUDE / 750)).
            
            LOCAL FUEL_ACTUAL IS 0.
            LOCAL FUEL_CAP_TOTAL IS 0.
            LOCAL parts IS SHIP:PARTSTAGGED("BOOSTER").
            FOR p IN parts {
                FOR res IN p:RESOURCES {
                    SET FUEL_ACTUAL TO FUEL_ACTUAL + res:AMOUNT.
                    SET FUEL_CAP_TOTAL TO FUEL_CAP_TOTAL + res:CAPACITY.
                }
            }
            SET FUEL_PORCENTAJE TO (FUEL_ACTUAL / MAX(1, FUEL_CAP_TOTAL)) * 100.
    
            IF FUEL_PORCENTAJE <= 20 {
                // --- INICIO DE SEPARACIÓN (Hot Staging) ---
                FOR eng IN SHIP:ENGINES {
                    LOCAL t IS eng:TAG.
                    IF NOT (t = "1" OR t = "2" OR t = "4" OR t = "6" OR t = "8") { eng:SHUTDOWN(). }
                }
                WAIT 0.1.
                AG7 ON. // Separación Lado Booster
                WAIT 0.8.
                AG8 ON. // Separación Lado Ship
                
                IF TARGET_SITE = "TOWER" {
                    SET TARGET_MODE TO "TOWER".
                    SET LANDING_TARGET TO LAUNCH_PAD.
                } ELSE {
                    SET TARGET_MODE TO "SEA".
                    // Punto en el mar a 50km en la dirección ecuatorial (Heading 90)
                    SET LANDING_TARGET TO BODY:GEOPOSITIONFOR(LAUNCH_PAD:POSITION + HEADING(90, 0):VECTOR * 50000).
                }
                
                IF ADDONS:TR:AVAILABLE { ADDONS:TR:SETTARGET(LANDING_TARGET). }
                BREAK.
            }
            WAIT 0.5.
        }
    }

CLEARSCREEN.
PRINT "=== BOOSTBACK ===" AT (0, 0).
SaveMissionState("BOOSTBACK").
LOCK STEERING TO SHIP:FACING.
LOCK THROTTLE TO 0.05.
RCS ON.

SET LngCtrlPID TO PIDLOOP(0.35, 0.3, 0.25, -10, 10).
SET LatCtrlPID TO PIDLOOP(0.25, 0.2, 0.15, -5, 5).
SET LngCtrlPID:SETPOINT TO 0.
SET PIDFactor TO 8.

FUNCTION SteeringCorrections {
    IF ADDONS:TR:HASIMPACT {
        SET ErrorVector TO ADDONS:TR:IMPACTPOS:POSITION - LANDING_TARGET:POSITION.
        LOCAL ApproachUP IS (LANDING_TARGET:POSITION - BODY:POSITION):NORMALIZED.
        LOCAL ApproachV IS VXCL(UP:VECTOR, LANDING_TARGET:POSITION - SHIP:POSITION):NORMALIZED.
        SET LatError TO VDOT(ANGLEAXIS(-90, ApproachUP) * ApproachV, ErrorVector).
        SET LngError TO VDOT(ApproachV, ErrorVector).
        SET LngCtrlPID:MAXOUTPUT TO MAX(MIN(ABS(LngError) / PIDFactor, 10), 1.0).
        SET LngCtrlPID:MINOUTPUT TO -LngCtrlPID:MAXOUTPUT.
    }
}

LOCAL flipStartTime TO TIME:SECONDS.
UNTIL FALSE {
    LOCAL targetVector IS VXCL(UP:VECTOR, LANDING_TARGET:POSITION - SHIP:POSITION):NORMALIZED.
    LOCK STEERING TO LOOKDIRUP(targetVector, UP:VECTOR).
    LOCK THROTTLE TO 1.0.
    LOCAL bearingError IS VANG(SHIP:FACING:FOREVECTOR, targetVector).
    LOCAL pitchAngle IS 90 - VANG(UP:VECTOR, SHIP:FACING:FOREVECTOR).
    IF ABS(pitchAngle) < 15 AND bearingError < 10 { BREAK. }
    IF TIME:SECONDS - flipStartTime > 25 { BREAK. }
    WAIT 0.1.
}

LOCAL stabilizeStart TO TIME:SECONDS.
UNTIL TIME:SECONDS - stabilizeStart > 5 {
    LOCAL targetVector IS VXCL(UP:VECTOR, LANDING_TARGET:POSITION - SHIP:POSITION):NORMALIZED.
    LOCK STEERING TO LOOKDIRUP(targetVector, UP:VECTOR).
    LOCK THROTTLE TO 0.8.
    LOCAL tagsMotores IS LIST("1", "2", "4", "6", "8").
    FOR eng IN SHIP:ENGINES {
        LOCAL t IS eng:TAG.
        IF (t = "1" OR t = "2" OR t = "4" OR t = "6" OR t = "8") {
             IF NOT eng:IGNITION { eng:ACTIVATE(). }
        } ELSE {
             eng:SHUTDOWN().
        }
    }
    WAIT 0.1.
}

SET BOOSTBACK_ACTIVO TO TRUE.
SET MEDIOS_APAGADOS TO FALSE.
UNTIL NOT BOOSTBACK_ACTIVO {
    ReforzarCarga().
    LogTelemetry("BOOSTBACK").
    SteeringCorrections().
    
    LOCAL targetVector IS V(0,0,0).
    IF ADDONS:TR:HASIMPACT { SET targetVector TO VXCL(UP:VECTOR, -ErrorVector):NORMALIZED. }
    ELSE { SET targetVector TO VXCL(UP:VECTOR, LANDING_TARGET:POSITION - SHIP:POSITION):NORMALIZED. }
    
    LOCK STEERING TO LOOKDIRUP(targetVector, UP:VECTOR).
    LOCAL alignment TO VDOT(SHIP:FACING:FOREVECTOR, targetVector).
    // Aumento de autoridad: Throttle más agresivo para cerrar distancia
    LOCAL throttleVal IS MAX(MIN(-(LngError + 500) / 1500 + 0.1, 1.0), 0.1).
    LOCK THROTTLE TO throttleVal * MAX(0, alignment).

    IF TARGET_MODE = "TOWER" AND ErrorVector:MAG < 25000 AND NOT MEDIOS_APAGADOS {
        FOR i IN RANGE(4, 14) {
            LOCAL motores IS SHIP:PARTSTAGGED(i:TOSTRING).
            FOR eng IN motores { eng:SHUTDOWN(). }
        }
        SET MEDIOS_APAGADOS TO TRUE.
    }

    // Fin normal del boostback
    IF TARGET_MODE = "TOWER" AND ErrorVector:MAG > 100 AND ErrorVector:MAG < 300 {
        FOR eng IN SHIP:ENGINES { eng:SHUTDOWN(). }
        LOCK THROTTLE TO 0.
        SET BOOSTBACK_ACTIVO TO FALSE.
    }

    // Límite de seguridad removido por petición del usuario para permitir boostbacks profundos
    WAIT 0.05.
}

SaveMissionState("DESCENSO").
RCS ON.
AG2 ON.
LOCK STEERING TO HEADING(90, 90, 90).
WAIT UNTIL SHIP:VERTICALSPEED < -1.

UNTIL SHIP:ALTITUDE < 60000 {
    ReforzarCarga().
    LOCAL interpFactor IS MAX(0, MIN(1, (SHIP:ALTITUDE - 60000) / 40000)).
    IF interpFactor > 0.5 { LOCK STEERING TO HEADING(90, 90, 90). }
    ELSE { LOCK STEERING TO LOOKDIRUP(SRFRETROGRADE:VECTOR, HEADING(90,0):VECTOR). }
    WAIT 0.2.
}

HUDTEXT("MODO: DESCENSO AERODINÁMICO", 5, 2, 30, YELLOW, FALSE).
PRINT "TRANSICIÓN: DESCENSO AERODINÁMICO (60KM)" AT (0, 10).

SET LngCtrlPID TO PIDLOOP(0.4, 0.5, 0.2, -15, 15).
SET LngCtrlPID:SETPOINT TO 0. // Puntería directa, sin offset.
SET LatCtrlPID TO PIDLOOP(0.3, 0.2, 0.1, -10, 10).
GLOBAL PIDFactor IS 12. 
IF NOT (BODY:RADIUS > 1600000) { SET PIDFactor TO 8. } // Ajuste Stock
GLOBAL BoosterGlideDistance IS 1200.
IF BODY:RADIUS > 1600000 { SET BoosterGlideDistance TO 2100. } // Ajuste RSS

CLEARSCREEN.
PRINT "=== DESCENSO DINAMICO ===" AT (0, 0).
SET FASE_LANDING TO 1.
SET PATAS_DESPLEGADAS TO FALSE.
SET CATCH_COMPLETADO TO FALSE.
SET ARMS_SENT TO FALSE.

// SINTONIZACION PROFESIONAL PARA ESTABILIDAD AERO
SET STEERINGMANAGER:MAXSTOPPINGTIME TO 2.5. 
SET STEERINGMANAGER:PITCHPID:KD TO 3.0.     
SET STEERINGMANAGER:YAWPID:KD TO 3.0.
SET STEERINGMANAGER:PITCHPID:KP TO 3.5. // Reducido de 7.0 para evitar oscilaciones
SET STEERINGMANAGER:YAWPID:KP TO 3.5. // Reducido de 7.0 para evitar oscilaciones

FUNCTION SetGridFinAuthority {
    PARAMETER x.
    LIST PARTS IN allParts.
    FOR p IN allParts {
        IF p:HASMODULE("ModuleControlSurface") {
            p:GETMODULE("ModuleControlSurface"):SETFIELD("authority limiter", x).
        }
    }
}

UNTIL ALT:RADAR < 4000 {
    ReforzarCarga().
    LogTelemetry("AERO DESCENT").
    
    LOCAL offsetDist IS 0. // Puntería directa al objetivo como pidió el usuario
    LOCAL ApproxDir IS VXCL(UP:VECTOR, LANDING_TARGET:POSITION - SHIP:POSITION):NORMALIZED.
    LOCAL targetDist IS VXCL(UP:VECTOR, LANDING_TARGET:POSITION - SHIP:POSITION):MAG.
    IF ADDONS:TR:HASIMPACT {
        SET ErrorVector TO ADDONS:TR:IMPACTPOS:POSITION - LANDING_TARGET:POSITION.
        SET LngError TO VDOT(ApproxDir, ErrorVector).
        SET LatError TO VDOT(ANGLEAXIS(-90, UP:VECTOR) * ApproxDir, ErrorVector).
    }

    SetGridFinAuthority(32).

    // 1. AUTORIDAD DINAMICA STARSHIP (v3.5.2)
    SET LngCtrlPID:MAXOUTPUT TO MAX(MIN(ABS(LngError - LngCtrlPID:SETPOINT) / PIDFactor, 10), 2.5).
    SET LngCtrlPID:MINOUTPUT TO -LngCtrlPID:MAXOUTPUT.
    
    SET LngCtrl TO -LngCtrlPID:UPDATE(TIME:SECONDS, LngError).
    SET LatCtrl TO -LatCtrlPID:UPDATE(TIME:SECONDS, LatError).

    // 2. GUIA STARSHIP PRO (Vector Rotation)
    // El signo LngCtrl se usa POSITIVO para inclinar hacia el CIELO (Nose-Up) y frenar
    LOCAL BaseDir IS SRFRETROGRADE:VECTOR:NORMALIZED.
    LOCAL FinalVec IS BaseDir * 
                     ANGLEAXIS(LngCtrl, LOOKDIRUP(BaseDir, UP:VECTOR):STARVECTOR) * 
                     ANGLEAXIS(LatCtrl, UP:VECTOR).
    
    // 3. SECUENCIA DE AUTORIDAD DINÁMICA
    LOCAL glideMult IS 1.0.
    // Si el error es pequeño (<50m), suavizamos para evitar oscilaciones
    IF ABS(LngError) < 50 { SET glideMult TO 0.5. }
    
    // Si estamos sobrevolando (overshooting), autoridad máxima para frenar
    IF LngError > 0 { SET glideMult TO 1.2. }
    
    SET FinalVec TO BaseDir * 
                     ANGLEAXIS(glideMult * LngCtrl, LOOKDIRUP(BaseDir, UP:VECTOR):STARVECTOR) * 
                     ANGLEAXIS(glideMult * LatCtrl, UP:VECTOR).

    LOCK STEERING TO LOOKDIRUP(FinalVec, ApproxDir * ANGLEAXIS(2 * LatCtrl, UP:VECTOR)).
    
    PRINT "Tilt Aero: " + ROUND(VANG(UP:VECTOR, SHIP:FACING:FOREVECTOR), 1) + " deg   " AT (0, 11).
    PRINT " Authority: " + ROUND(LngCtrlPID:MAXOUTPUT, 1) + " deg   " AT (0, 12).
    WAIT 0.1.
}

// El tuning ya se realizó al inicio del descenso dinámico

GLOBAL HoverPID IS PIDLOOP(0.3, 0.1, 0.2, -0.5, 0.5). // P, I, D, Min, Max output
SET HoverPID:SETPOINT TO -2.0.

// --- LOGICA DE FRENADO PRO (Serie Starship) ---
// Primero calculamos el empuje disponible para frenar
GLOBAL BoosterRaptorThrust IS 2130. // RSS Default
IF BODY:RADIUS < 1600000 { SET BoosterRaptorThrust TO 555. } // Stock

LOCK maxDecel TO (3 * BoosterRaptorThrust / SHIP:MASS) - 9.805.
LOCK stopDist TO (SHIP:VERTICALSPEED^2) / (2 * MAX(0.01, maxDecel)).
LOCK landingRatio TO stopDist / MAX(1, ALT:RADAR).

GLOBAL CatchVS IS -10.0. // Velocidad de aproximación inicial
GLOBAL TargetTransitionAlt IS 250. // Altura para reducir a 5 m/s
GLOBAL Planet1G IS 9.805.
GLOBAL RSS IS (BODY:RADIUS > 1600000).
GLOBAL TARGET_ALIGN_DIST IS 500. 

FUNCTION LandingThrottle {
    LOCAL tiltComp IS 1 / COS(MIN(80, VANG(SHIP:FACING:FOREVECTOR, UP:VECTOR))).
    
    // --- LÓGICA DE VELOCIDAD DINÁMICA (3 ETAPAS) ---
    LOCAL currentTargetVS IS CatchVS.
    IF ALT:RADAR < TargetTransitionAlt { SET currentTargetVS TO -5.0. }
    
    // Fase de Descenso Final (2 m/s) para máxima precisión de alineación
    IF ALT:RADAR < 235 { SET currentTargetVS TO -2.0. }

    // Si ya estamos alineados sobre el OLM/Torre, bajamos a 15m/s como pidió el usuario
    LOCAL posError IS VXCL(UP:VECTOR, LANDING_TARGET:POSITION - SHIP:POSITION).
    IF posError:MAG < 5.0 AND ALT:RADAR < 225 { SET currentTargetVS TO -15.0. }

    // --- MODO CONTROL DE VELOCIDAD (Cerca del TargetVS) ---
    IF ALT:RADAR < 500 AND VERTICALSPEED > currentTargetVS - 3 {
        // CONTROLADOR DE VS DINÁMICO (Mejorado con amortiguación)
        LOCAL vError IS VERTICALSPEED - currentTargetVS. 
        LOCAL hoverThr IS (Planet1G * SHIP:MASS * tiltComp) / MAX(1, SHIP:AVAILABLETHRUST).
        
        // P-Controller suave para mantener la velocidad
        LOCAL finalThr IS hoverThr - (vError * 0.20). 
        RETURN MIN(1, MAX(0.01, finalThr)).
    } 
    
    // --- DESCENSO INICIAL / FRENADO FUERTE (Suicide Burn a Altitud Objetivo) ---
    // Ajustamos stopDist para que apunte a 5 m/s a los 250m
    LOCAL targetAlt IS 0.
    LOCAL targetV IS 0.
    IF ALT:RADAR > TargetTransitionAlt {
        SET targetAlt TO TargetTransitionAlt.
        SET targetV TO 5.0.
    }

    LOCAL vDiffSq IS MAX(0, SHIP:VERTICALSPEED^2 - targetV^2).
    LOCAL distToTarget IS MAX(1, ALT:RADAR - targetAlt).
    LOCAL dynamicStopDist TO vDiffSq / (2 * MAX(0.01, maxDecel)).
    LOCAL dynamicRatio TO dynamicStopDist / distToTarget.

    IF RSS {
        RETURN MAX((dynamicRatio * MIN(maxDecel, 65) * tiltComp) / maxDecel, 0.29).
    } ELSE {
        RETURN MAX((dynamicRatio * MIN(maxDecel, 45) * tiltComp) / maxDecel, 0.33).
    }
}

PRINT "=== LANDING BURN ===" AT (0, 0).
SaveMissionState("LANDING").
LOCK THROTTLE TO LandingThrottle().

// APAGADO ABSOLUTO DE SEGURIDAD (Solo queremos 1, 2, 6 como pediste)
FOR eng IN SHIP:ENGINES {
    LOCAL t IS eng:TAG.
    IF NOT (t = "1" OR t = "2" OR t = "6") {
        eng:SHUTDOWN().
    } ELSE {
        eng:ACTIVATE().
    }
}

SET FASE_STEER TO 1.

UNTIL CATCH_COMPLETADO OR SHIP:STATUS = "SPLASHED" {
    LOCAL posError IS VXCL(UP:VECTOR, LANDING_TARGET:POSITION - SHIP:POSITION).
    LOCAL targetDist IS posError:MAG.
    
    // La lógica de velocidad ahora se maneja dentro de LandingThrottle para mayor precisión
    LOCAL dummy IS 0. 

    LogTelemetry("LANDING BURN").
    LOCAL vel IS SHIP:VELOCITY:SURFACE:MAG.
    
    // ROLLVECTOR DINAMICO (Estilo Starship Pro)
    // Apuntar HACIA la torre en tiempo real con filtro para evitar jitter
    LOCAL newRoll IS posError:NORMALIZED.
    IF NOT (DEFINED LockedApproach) {
        GLOBAL LockedApproach IS newRoll.
    } ELSE {
        // Low-pass filter: actualizar suavemente (10% nuevo, 90% anterior)
        SET LockedApproach TO (LockedApproach * 0.90 + newRoll * 0.10):NORMALIZED.
    }
    LOCAL GRAV IS BODY:MU / (SHIP:BODY:POSITION:MAG ^ 2).
    LOCAL currentTWR IS SHIP:AVAILABLETHRUST / MAX(0.1, SHIP:MASS * GRAV).
    LOCAL TWR_Margin IS 1.6 - MIN(0.5, (ALT:RADAR / 1200) * 0.5).
    LOCAL MaxTilt IS 0.
    IF currentTWR > TWR_Margin { SET MaxTilt TO ARCCOS(TWR_Margin / currentTWR). }
    SET MaxTilt TO MIN(MaxTilt, 12). // Cap de 12 grados para evitar descontrol en cohete alto

    IF ALT:RADAR < 500 AND NOT PATAS_DESPLEGADAS {
        AG4 ON.
        SET PATAS_DESPLEGADAS TO TRUE.
    }
    // LandingGuidance() ya usa LockedApproach internamente — coherente y sin error de scope
    LOCK STEERING TO LandingGuidance().

    LOCK THROTTLE TO LandingThrottle().

    IF ALT:RADAR < 220 AND NOT ARMS_SENT AND TARGET_MODE = "TOWER" {
        // VERIFICACIÓN DE SEGURIDAD ANTES DE PEDIR BRAZOS
        IF targetDist < 8 {
            WRITEJSON(LEXICON("signal", "CLOSE"), "0:/catch_signal.json").
            SET ARMS_SENT TO TRUE.
        } ELSE {
            // ABORTO AUTOMÁTICO: Muy lejos para captura segura
            SET CATCH_ABORTED TO TRUE.
            HUDTEXT("!!! ABORTO: FUERA DE RANGO PARA CAPTURA !!!", 10, 2, 40, RED, TRUE).
        }
    }
    
    // --- LÓGICA DE ABORTO (EVASIÓN) ---
    IF (DEFINED CATCH_ABORTED) AND CATCH_ABORTED {
        SET TARGET_MODE TO "SEA".
        // Maniobra de evasión: apuntar a 20m de distancia de la torre inmediatamente
        LOCAL escapeVec IS (SHIP:POSITION - LANDING_TARGET:POSITION):NORMALIZED.
        SET LANDING_TARGET TO BODY:GEOPOSITIONFOR(LANDING_TARGET:POSITION + escapeVec * 50).
        SET CatchVS TO -8.0. // Descenso más rápido para salir de zona de peligro
    }

    IF ALT:RADAR <= 196 AND NOT CATCH_ABORTED { // Un poco más de margen para el catch a 15m/s
        LOCK THROTTLE TO 0.
        FOR eng IN SHIP:ENGINES { eng:SHUTDOWN(). }
        SET CATCH_COMPLETADO TO TRUE.
        BREAK.
    }
    // Si abortamos y estamos muy bajos, aterrizar normalmente (fallback patas)
    IF CATCH_ABORTED AND ALT:RADAR < 15 {
        LOCK THROTTLE TO 0.
        FOR eng IN SHIP:ENGINES { eng:SHUTDOWN(). }
        BREAK.
    }

    PRINT "Modo: Starship Pro (Tilt: " + ROUND(VANG(UP:VECTOR, SHIP:FACING:FOREVECTOR), 1) + "deg)   " AT (0, 7).
    PRINT "TWR: " + ROUND(currentTWR, 2) + "  Throt: " + ROUND(THROTTLE*100,0) + "%   " AT (0, 8).
    PRINT "Altitud:   " + ROUND(ALT:RADAR, 0) + " m     " AT (0, 10).
    // Capturamos la velocidad objetivo actual para el print
    LOCAL printTargetVS IS CatchVS.
    IF ALT:RADAR < TargetTransitionAlt { SET printTargetVS TO -5.0. }
    IF posError:MAG < 5.0 AND ALT:RADAR < 225 { SET printTargetVS TO -15.0. }

    PRINT "V.Vert:    " + ROUND(SHIP:VERTICALSPEED, 1) + " (Tgt:" + ROUND(printTargetVS,1) + ")   " AT (0, 11).
    PRINT "Dist Tgt:  " + ROUND(targetDist, 1) + " m   " AT (0, 12).
    PRINT "Tilt/Lim:  " + ROUND(debug_TgtTilt, 1) + " / " + ROUND(debug_MaxTilt, 1) + " deg   " AT (0, 13).
    EscribirAltura(ALT:RADAR).
    ReforzarCarga(). // Mantener segunda etapa y torre cargadas durante el landing burn
    WAIT 0.05.
}

LOCK THROTTLE TO 0.
UNLOCK STEERING.
WAIT 2.
FOR i IN RANGE(1, 4) {
    LOCAL motores IS SHIP:PARTSTAGGED(i:TOSTRING).
    FOR eng IN motores { eng:SHUTDOWN(). }
}
PRINT "FIN DEL PROGRAMA".
