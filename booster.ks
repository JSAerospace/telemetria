// --- CONFIGURACIÓN DE DISTANCIA DE CARGA (RSS) ---
// DEBE SER LO PRIMERO - Se ejecuta ANTES que cualquier cosa para garantizar comunicación
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
SET SHIP:LOADDISTANCE:LANDED:UNLOAD TO 2500000.
SET SHIP:LOADDISTANCE:LANDED:LOAD TO 2400000.
WAIT 0.001.
SET SHIP:LOADDISTANCE:LANDED:PACK TO 2450000.
SET SHIP:LOADDISTANCE:LANDED:UNPACK TO 2350000.
WAIT 0.01.
SET SHIP:LOADDISTANCE:SPLASHED:UNLOAD TO 2500000.
SET SHIP:LOADDISTANCE:SPLASHED:LOAD TO 2400000.
WAIT 0.001.
SET SHIP:LOADDISTANCE:SPLASHED:PACK TO 2450000.
SET SHIP:LOADDISTANCE:SPLASHED:UNPACK TO 2350000.
WAIT 0.01.
SET SHIP:LOADDISTANCE:PRELAUNCH:UNLOAD TO 2500000.
SET SHIP:LOADDISTANCE:PRELAUNCH:LOAD TO 2400000.
WAIT 0.001.
SET SHIP:LOADDISTANCE:PRELAUNCH:PACK TO 2450000.
SET SHIP:LOADDISTANCE:PRELAUNCH:UNPACK TO 2350000.

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

HUDTEXT("BOOSTER: SISTEMA DE CARGA RSS ACTIVADO (2500km)", 5, 2, 30, GREEN, FALSE).
PRINT "SCRIPT VERSION: FIXED (GLOBAL VARIABLES)".

GLOBAL landing_target IS LATLNG(28.277518, -74.543104).

// --- CONSTANTS & CONFIG ---
GLOBAL BoosterHeight IS 70.
GLOBAL FinalDeceleration IS 20.
GLOBAL PIDFactor IS 10.
GLOBAL BoosterRaptorThrust IS 2300. // kN
GLOBAL BoosterReturnMass IS 250. // Tonnes
GLOBAL Scale IS 1.
GLOBAL CatchVS IS -5. // Target vertical speed for catch
GLOBAL HoverTargetVS IS -10. // Target vertical speed during hover
GLOBAL EngineSwitchSpeed IS 60.

// --- VARIABLES DE GUIDANCE ---
GLOBAL LngCtrlPID IS PIDLOOP(0.35, 0.3, 0.25, -10, 10).
GLOBAL LatCtrlPID IS PIDLOOP(0.25, 0.2, 0.1, -5, 5).
GLOBAL HoverPID IS PIDLOOP(0.5, 0.2, 0.15, 0, 1). // PID for vertical velocity control
GLOBAL LngCtrl IS 0.
GLOBAL LatCtrl IS 0.
GLOBAL ApproachVector IS V(0,0,0).
GLOBAL ApproachUPVector IS V(0,0,0).
GLOBAL ErrorVector IS V(0,0,0).
GLOBAL PositionError IS V(0,0,0).
GLOBAL GSVec IS V(0,0,0).
GLOBAL LngError IS 0.
GLOBAL LatError IS 0.
GLOBAL LandingBurnAlt IS 1200.
GLOBAL SteeringVector IS UP:VECTOR.
GLOBAL FinalVec IS UP:VECTOR.
GLOBAL LandingBurnStarted IS FALSE.
GLOBAL HoverMode IS FALSE.
GLOBAL FinalDescent IS FALSE.
GLOBAL CurrentThrottle IS 0.
GLOBAL GearDeployed IS FALSE.
GLOBAL RCSDisabled IS FALSE.

// --- CONFIGURACIÓN DE COMBUSTIBLE ---
GLOBAL max_lh2 IS 485479.21.
GLOBAL max_lox IS 32365.28.
GLOBAL masa_total_inicial IS max_lh2 + max_lox.

// Buscamos el tanque
GLOBAL tanque_booster IS SHIP:PARTSTAGGED("BOOSTER")[0].

// === SECUENCIA DE LANZAMIENTO ===
CLEARSCREEN.
PRINT "=================================".
PRINT "  SISTEMA DE LANZAMIENTO AUTOMATICO".
PRINT "=================================".
PRINT " ".
PRINT "Esperando señal de telemetria (T-10)...".
PRINT "  O presiona 'G' para lanzamiento manual".
PRINT " ".

// Ruta del archivo de telemetría (contiene countdown)
GLOBAL telemetry_file IS "0:/boot/booster_telemetry.json".

// Función para leer T-minus del archivo JSON de telemetría
FUNCTION ReadCountdownTMinus {
    IF NOT EXISTS(telemetry_file) { RETURN -999. }
    
    // Leer última línea del archivo (puede tener múltiples líneas por LOG append)
    LOCAL content IS "".
    LOCAL fileHandle IS OPEN(telemetry_file).
    LOCAL lines IS fileHandle:READALL.
    FOR line IN lines {
        IF line:LENGTH > 10 { SET content TO line. }
    }
    
    IF content:LENGTH < 10 { RETURN -999. }
    
    // Buscar "t_minus": dentro de la sección countdown
    LOCAL search_str IS CHAR(34) + "t_minus" + CHAR(34) + ":".
    LOCAL t_pos IS content:FIND(search_str).
    IF t_pos < 0 { RETURN -999. }
    
    // Calcular posición de inicio del valor
    LOCAL start_idx IS t_pos + search_str:LENGTH.
    LOCAL remaining_len IS content:LENGTH - start_idx.
    IF remaining_len <= 0 { RETURN -999. }
    
    // Extraer substring después de la clave
    LOCAL after_key IS content:SUBSTRING(start_idx, remaining_len).
    
    // Encontrar la coma que termina el valor
    LOCAL comma_pos IS after_key:FIND(",").
    IF comma_pos < 0 { 
        SET comma_pos TO after_key:FIND("}"). 
    }
    IF comma_pos <= 0 { RETURN -999. }
    
    // Extraer el valor numérico
    LOCAL value_str IS after_key:SUBSTRING(0, comma_pos).
    SET value_str TO value_str:TRIM.
    
    LOCAL t_minus_val IS value_str:TONUMBER(-999).
    
    // Verificar que countdown está ACTIVO y NO en HOLD
    IF content:FIND(CHAR(34) + "countdown_active" + CHAR(34) + ":true") < 0 {
        RETURN -999.  // Countdown no está activo
    }
    IF content:FIND(CHAR(34) + "countdown_hold" + CHAR(34) + ":true") >= 0 {
        RETURN -999.  // Countdown está en HOLD, no lanzar
    }
    
    RETURN t_minus_val.
}

// Loop de espera: señal de telemetría O tecla G
LOCAL launch_triggered IS FALSE.
LOCAL sync_countdown IS FALSE.  // TRUE si venimos de telemetría

UNTIL launch_triggered {
    // Verificar archivo de countdown
    LOCAL t_minus IS ReadCountdownTMinus().
    
    IF t_minus >= 0 AND t_minus <= 10 {
        // ¡Señal recibida! T-10 o menos
        SET launch_triggered TO TRUE.
        SET sync_countdown TO TRUE.
        PRINT "SEÑAL RECIBIDA: T-" + ROUND(t_minus, 0) AT (0, 10).
        HUDTEXT("SEÑAL DE LANZAMIENTO RECIBIDA!", 3, 2, 30, GREEN, FALSE).
    }
    
    // Verificar tecla G como backup
    IF TERMINAL:INPUT:HASCHAR {
        LOCAL key IS TERMINAL:INPUT:GETCHAR().
        IF key = "g" OR key = "G" {
            SET launch_triggered TO TRUE.
            SET sync_countdown TO FALSE.
            PRINT "LANZAMIENTO MANUAL ACTIVADO" AT (0, 10).
        }
    }
    
    // Mostrar T-minus actual si hay countdown activo
    IF t_minus > 10 {
        PRINT "Telemetria: T-" + ROUND(t_minus, 0) + " seg     " AT (0, 9).
    } ELSE IF t_minus > 0 {
        PRINT ">>> T-" + ROUND(t_minus, 0) + " - PREPARANDO! <<<     " AT (0, 9).
    }
    
    WAIT 0.2.
}

PRINT " ".
PRINT "INICIANDO SECUENCIA DE LANZAMIENTO...".
PRINT " ".

// 1. Configuración inicial
LOCK THROTTLE TO 1.0.
LOCK STEERING TO HEADING(90, 90).

// Cuenta regresiva T-10 (sincronizada o propia)
IF sync_countdown {
    // Si venimos de telemetría, sincronizar con su T-minus
    LOCAL current_t IS ReadCountdownTMinus().
    LOCAL start_t IS FLOOR(MIN(current_t, 10)).
    
    FROM {LOCAL t IS start_t.} UNTIL t = 0 STEP {SET t TO t - 1.} DO {
        PRINT "T-" + t + " segundos..." AT(0, 12).
        HUDTEXT("T-" + t, 1, 2, 50, YELLOW, FALSE).
        WAIT 1.
    }
} ELSE {
    // Cuenta regresiva manual T-10
    FROM {LOCAL t IS 10.} UNTIL t = 0 STEP {SET t TO t - 1.} DO {
        PRINT "T-" + t + " segundos..." AT(0, 12).
        WAIT 1.
    }
}

PRINT "T-0: ¡IGNICIÓN!" AT(0, 10).

// 2. Encendido de motores (Tags 1 al 7)
PRINT " ".
PRINT "Encendiendo motores individuales...".
FROM {LOCAL i IS 1.} UNTIL i > 7 STEP {SET i TO i + 1.} DO {
    LOCAL motores IS SHIP:PARTSTAGGED(i:TOSTRING).
    FOR eng IN motores {
        eng:ACTIVATE().
    }
}

// Esperar 1 segundo y liberar plataforma con AG1
WAIT 1.
AG1 ON.
PRINT "¡LIBERANDO PLATAFORMA (AG1)!".
WAIT 0.5.

PRINT "¡DESPEGUE!".

// 3. Bucle de Ascenso controlado por Combustible
LOCAL staging_target_set IS FALSE.
LOCAL separation_target IS LATLNG(28.262580, -74.382632). // Target de separación
LOCAL final_landing_target IS LATLNG(28.277518, -74.543104). // Target de aterrizaje

UNTIL FALSE {
    LOCAL cantidad_actual IS 0.
    FOR res IN tanque_booster:RESOURCES {
        SET cantidad_actual TO cantidad_actual + res:AMOUNT.
    }
    LOCAL porcentaje IS (cantidad_actual / masa_total_inicial) * 100.
    
    // A los 10km, establecer target de separación
    IF ALTITUDE > 10000 AND NOT staging_target_set {
        IF ADDONS:TR:AVAILABLE {
            ADDONS:TR:SETTARGET(separation_target).
            SET staging_target_set TO TRUE.
            PRINT "Target de separación establecido a 10km!" AT(0, 17).
        }
    }
    
    // Verificar distancia de impacto para separación
    IF staging_target_set AND ADDONS:TR:HASIMPACT {
        LOCAL impact_pos IS ADDONS:TR:IMPACTPOS.
        LOCAL error_vec IS impact_pos:POSITION - separation_target:POSITION.
        LOCAL dist_to_staging IS error_vec:MAG.
        
        IF dist_to_staging < 3000 OR impact_pos:LNG > separation_target:LNG {
            PRINT "SEPARACION! Dist: " + ROUND(dist_to_staging, 0) + "m / Lng Pasada" AT(0, 17).
            BREAK.
        }
    }
    
    LOCAL PITCH IS MAX(15, 90 - (ALTITUDE / 1000)).
    LOCAL MI_RUMBO IS HEADING(90, PITCH).
    LOCK STEERING TO MI_RUMBO.
    WAIT 0.5. 
    PRINT "Combustible: " + ROUND(porcentaje, 2) + "%   " AT(0, 15).
    PRINT "Pitch:       " + ROUND(PITCH, 1) + " deg   " AT(0, 16).
    IF ADDONS:TR:AVAILABLE {
        IF ADDONS:TR:HASIMPACT {
            LOCAL impactGeo IS ADDONS:TR:IMPACTPOS.
            PRINT "Impact Lat:  " + ROUND(impactGeo:LAT, 4) + "   " AT(0, 18).
            PRINT "Impact Lng:  " + ROUND(impactGeo:LNG, 4) + "   " AT(0, 19).
            IF staging_target_set {
                LOCAL error_vec IS impactGeo:POSITION - separation_target:POSITION.
                PRINT "Dist Sep:    " + ROUND(error_vec:MAG/1000, 2) + " km   " AT(0, 20).
            }
        } ELSE {
            PRINT "Impact:      N/A              " AT(0, 18).
            PRINT "                              " AT(0, 19).
        }
    }
}

// 4. Secuencia de Apagado y Separación
LOCK THROTTLE TO 0.
PRINT "Apagando motores...".
FROM {LOCAL i IS 1.} UNTIL i > 7 STEP {SET i TO i + 1.} DO {
    LOCAL motores IS SHIP:PARTSTAGGED(i:TOSTRING).
    FOR eng IN motores {
        eng:SHUTDOWN().
    }
}
WAIT 2.
PRINT "Separando interetapa (SEPARA)...".
LOCAL separadores IS SHIP:PARTSTAGGED("SEPARA").
FOR sep IN separadores {
    IF sep:HASMODULE("ModuleDecouple") {
        sep:GETMODULE("ModuleDecouple"):DOEVENT("Decouple").
    } ELSE IF sep:HASMODULE("ModuleAnchoredDecoupler") {
        sep:GETMODULE("ModuleAnchoredDecoupler"):DOEVENT("Decouple").
    }
}
PRINT "Separación completada.".

// Configurar target FINAL de aterrizaje - DETECCIÓN AUTOMÁTICA DE EsZunBoat
LOCAL barca_encontrada IS FALSE.
LOCAL barca_target IS LATLNG(28.277518, -74.543104). // Fallback por defecto

// Buscar EsZunBoat en la lista de naves
LIST TARGETS IN todas_naves.
FOR nave IN todas_naves {
    IF nave:NAME = "EsZunBoat" {
        SET barca_target TO nave:GEOPOSITION.
        SET barca_encontrada TO TRUE.
        HUDTEXT("BARCA EsZunBoat DETECTADA!", 5, 2, 30, GREEN, FALSE).
        PRINT "=================================".
        PRINT "  BARCA EsZunBoat ENCONTRADA!".
        PRINT "  Lat: " + ROUND(barca_target:LAT, 6).
        PRINT "  Lng: " + ROUND(barca_target:LNG, 6).
        PRINT "=================================".
        BREAK.
    }
}

IF NOT barca_encontrada {
    HUDTEXT("ADVERTENCIA: EsZunBoat no encontrada - usando coords fijas", 5, 2, 30, YELLOW, FALSE).
    PRINT "ADVERTENCIA: Barca no detectada, usando coordenadas fijas".
}

// Aplicar target
SET landing_target TO barca_target.
IF ADDONS:TR:AVAILABLE {
    ADDONS:TR:SETTARGET(barca_target).
    PRINT "Target de Trajectories actualizado".
}

// 5. Configuración de Retorno
PRINT "Esperando 5 segundos para estabilización...".
WAIT 5.
AG3 ON.
PRINT "GRID FINS DESPLEGADOS (AG3)!".
HUDTEXT("GRID FINS EXTENDIDOS", 3, 2, 25, GREEN, FALSE).
RCS ON.
PRINT "RCS ACTIVADO.".
LOCK STEERING TO LOOKDIRUP(UP:VECTOR, SHIP:NORTH:VECTOR).

// Esperar apogeo
PRINT "Esperando Apogeo...".
UNTIL SHIP:VERTICALSPEED < -1 {
    PRINT "Altitud:      " + ROUND(SHIP:ALTITUDE/1000, 2) + " km    " AT(0, 20).
    PRINT "V. Vertical:  " + ROUND(SHIP:VERTICALSPEED, 1) + " m/s   " AT(0, 21).
    WAIT 0.1.
}

PRINT "Iniciando descenso. Modo RETROGRADO.".
LOCK STEERING TO SRFRETROGRADE.

// Quemado de reentrada (70km)
PRINT "Esperando 70km para quemado...".
UNTIL SHIP:ALTITUDE < 70000 {
    PRINT "Altitud:      " + ROUND(SHIP:ALTITUDE/1000, 2) + " km    " AT(0, 20).
    PRINT "V. Vertical:  " + ROUND(SHIP:VERTICALSPEED, 1) + " m/s   " AT(0, 21).
    PRINT "V. Superficie:" + ROUND(SHIP:VELOCITY:SURFACE:MAG, 1) + " m/s   " AT(0, 22).
    WAIT 0.1.
}

PRINT "Altitud < 70km. Iniciando frenado...".
LOCK THROTTLE TO 1.0.
PRINT "Activando motores 1-3...".
FROM {LOCAL i IS 1.} UNTIL i > 3 STEP {SET i TO i + 1.} DO {
    LOCAL motores IS SHIP:PARTSTAGGED(i:TOSTRING).
    PRINT "  Tag " + i + ": " + motores:LENGTH + " motores encontrados".
    FOR eng IN motores {
        eng:ACTIVATE().
        PRINT "    Motor activado: " + eng:TITLE.
    }
}
WAIT 1.

// Reentry burn - Trigger at 2km, duration based on initial error (UPDATED: 18km threshold)
LOCAL dist_to_target IS 999999.
LOCAL first_2km_time IS 0.
LOCAL burn_active IS TRUE.
LOCAL wait_duration IS 3.5.

IF ADDONS:TR:HASIMPACT {
    LOCAL impact_pos IS ADDONS:TR:IMPACTPOS.
    LOCAL error_vec IS impact_pos:POSITION - landing_target:POSITION.
    SET dist_to_target TO error_vec:MAG.
    
    IF dist_to_target > 18000 {
        SET wait_duration TO 2.0.
        PRINT "Modo Lejano (>18km). Timer será 2.0s tras llegar a 2km" AT(0, 25).
    } ELSE {
        SET wait_duration TO 3.5.
        PRINT "Modo Cercano (<18km). Timer será 3.5s tras llegar a 2km" AT(0, 25).
    }
}

UNTIL NOT burn_active {
    SET dist_to_target TO 999999.
    LOCAL latCorrection IS 0.
    LOCAL correctedSteering IS SRFRETROGRADE:VECTOR.
    
    IF ADDONS:TR:HASIMPACT {
        LOCAL impact_pos IS ADDONS:TR:IMPACTPOS.
        LOCAL target_pos IS landing_target.
        
        LOCAL error_vec IS impact_pos:POSITION - target_pos:POSITION.
        SET dist_to_target TO error_vec:MAG.
        
        // === CORRECCIÓN LATERAL AUMENTADA (Max 5 grados) ===
        // Calcular error lateral (perpendicular a la dirección de vuelo)
        LOCAL velocityDir IS VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE):NORMALIZED.
        LOCAL lateralError IS VXCL(velocityDir, error_vec). // Componente lateral del error
        LOCAL lateralDist IS lateralError:MAG.
        
        // Calcular corrección proporcional al error (max 5 grados)
        // Ganancia aumentada: 0.0005 grados por metro de error lateral
        SET latCorrection TO MIN(5, lateralDist * 0.0005).
        
        // Dirección de corrección (hacia donde necesitamos ir)
        IF lateralDist > 10 { // Solo corregir si hay más de 10m de error
            LOCAL lateralDir IS lateralError:NORMALIZED.
            // Rotar el vector retrograde hacia la corrección lateral
            LOCAL correctionAxis IS VCRS(SRFRETROGRADE:VECTOR, lateralDir):NORMALIZED.
            SET correctedSteering TO SRFRETROGRADE:VECTOR * ANGLEAXIS(latCorrection, correctionAxis).
        }
        
        IF dist_to_target < 2000 AND first_2km_time = 0 {
            SET first_2km_time TO TIME:SECONDS.
            PRINT "Llegamos a 2km! Esperando " + wait_duration + "s..." AT(0, 25).
        }
        
        IF first_2km_time > 0 AND (TIME:SECONDS - first_2km_time) >= wait_duration {
            SET burn_active TO FALSE.
        }
    }
    
    // Aplicar steering con corrección lateral
    LOCK STEERING TO LOOKDIRUP(correctedSteering, UP:VECTOR).

    PRINT "=== REENTRY BURN ===" AT(0, 19).
    PRINT "Altitud:      " + ROUND(SHIP:ALTITUDE/1000, 2) + " km    " AT(0, 20).
    PRINT "V. Vertical:  " + ROUND(SHIP:VERTICALSPEED, 1) + " m/s   " AT(0, 21).
    PRINT "V. Superficie:" + ROUND(SHIP:VELOCITY:SURFACE:MAG, 1) + " m/s   " AT(0, 22).
    PRINT "Dist Impact:  " + ROUND(dist_to_target/1000, 2) + " km     " AT(0, 23).
    PRINT "Lat Correct:  " + ROUND(latCorrection, 2) + " deg    " AT(0, 24).
    
    IF first_2km_time > 0 {
        LOCAL time_elapsed IS TIME:SECONDS - first_2km_time.
        LOCAL time_left IS wait_duration - time_elapsed.
        PRINT "Apagando en: " + ROUND(time_left, 1) + " s                " AT(0, 25).
    } ELSE {
        PRINT "Esperando 2km...                    " AT(0, 25).
    }

    WAIT 0.1.
}

LOCK THROTTLE TO 0.
PRINT "Frenado completado.".
FROM {LOCAL i IS 1.} UNTIL i > 3 STEP {SET i TO i + 1.} DO {
    LOCAL motores IS SHIP:PARTSTAGGED(i:TOSTRING).
    FOR eng IN motores {
        eng:SHUTDOWN().
    }
}

// === DESCENSO AERODINÁMICO Y ATERRIZAJE ===
PRINT "Iniciando Descenso Dinámico...".
LOCK STEERING TO SteeringVector.

UNTIL SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED" {
    SteeringCorrections().
    
    IF NOT LandingBurnStarted {
        IF ALT:RADAR < 1800 {
            LOCK STEERING TO SRFRETROGRADE.
        }
        
        IF ALT:RADAR < LandingBurnAlt {
            SET LandingBurnStarted TO TRUE.
            PRINT "Iniciando Landing Burn (1.2km) a MAXIMA POTENCIA..." AT(0, 23).
             FROM {LOCAL i IS 1.} UNTIL i > 3 STEP {SET i TO i + 1.} DO {
                LOCAL motores IS SHIP:PARTSTAGGED(i:TOSTRING).
                FOR eng IN motores {
                    eng:ACTIVATE().
                }
            }
        }
    } 
    ELSE {
        LandingGuidance().
        
        IF SHIP:VELOCITY:SURFACE:MAG < EngineSwitchSpeed AND NOT HoverMode {
            PRINT "Velocidad < 60 m/s. Apagando motores 2-3..." AT(0, 24).
            FROM {LOCAL i IS 2.} UNTIL i > 3 STEP {SET i TO i + 1.} DO {
                LOCAL motores IS SHIP:PARTSTAGGED(i:TOSTRING).
                FOR eng IN motores {
                    eng:SHUTDOWN().
                }
            }
            SET HoverMode TO TRUE.
            SET HoverPID:SETPOINT TO HoverTargetVS.
            
            LOCK STEERING TO FinalVec.
            PRINT "HOVER MODE - Apuntando al target!" AT(0, 25).
            
            LOCK THROTTLE TO 0.5.
            WAIT 0.1.
        }
        
        IF ALT:RADAR < 500 AND NOT GearDeployed {
            AG2 ON.
            SET GearDeployed TO TRUE.
            PRINT "Patas desplegadas a 500m!" AT(0, 28).
        }
        
        // Apagar RCS a 5km de altitud
        IF SHIP:ALTITUDE < 5000 AND NOT RCSDisabled {
            RCS OFF.
            SET RCSDisabled TO TRUE.
            PRINT "RCS APAGADO a 5km!" AT(0, 29).
            HUDTEXT("RCS DESACTIVADO", 3, 2, 25, YELLOW, FALSE).
        }
        
        IF NOT HoverMode {
            LOCK THROTTLE TO 1.0.
            LOCK STEERING TO SRFRETROGRADE.
        } ELSE {
            SET CurrentThrottle TO LandingThrottle().
            LOCK THROTTLE TO CurrentThrottle.
        }
    }

    // Mejora de seguridad: A 60m de altura, apuntar verticalmente para evitar aterrizaje de lado
    IF ALT:RADAR < 60 {
        LOCK STEERING TO UP:VECTOR.
    }

    PRINT "=== LANDING SEQUENCE ===" AT(0, 19).
    PRINT "Altitud:    " + ROUND(ALT:RADAR, 1) + " m     " AT(0, 20).
    IF HoverMode {
        PRINT "V. Vert Tgt:" + ROUND(HoverPID:SETPOINT, 1) + " m/s     " AT(0, 21).
        PRINT "V. Vert Act:" + ROUND(SHIP:VERTICALSPEED, 1) + " m/s     " AT(0, 22).
    } ELSE {
        PRINT "V. Surface: " + ROUND(SHIP:VELOCITY:SURFACE:MAG, 1) + " m/s     " AT(0, 21).
        PRINT "V. Vert:    " + ROUND(SHIP:VERTICALSPEED, 1) + " m/s     " AT(0, 22).
    }
    PRINT "Throttle:   " + ROUND(CurrentThrottle * 100, 0) + " %      " AT(0, 23).
    PRINT "Dist Target:" + ROUND(PositionError:MAG, 1) + " m     " AT(0, 24).
    PRINT "Lng Err:    " + ROUND(LngError, 1) + " m     " AT(0, 25).
    PRINT "Lat Err:    " + ROUND(LatError, 1) + " m     " AT(0, 26).
    PRINT "H. Speed:   " + ROUND(VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE):MAG, 1) + " m/s     " AT(0, 27).
    IF HoverMode {
        IF ALT:RADAR < 15 {
            PRINT "Phase:      SOFT LANDING      " AT(0, 28).
        } ELSE IF ALT:RADAR < 100 {
            PRINT "Phase:      FINAL APPROACH    " AT(0, 28).
        } ELSE {
            PRINT "Phase:      CONTROLLED DESC   " AT(0, 28).
        }
    } ELSE IF LandingBurnStarted {
        PRINT "Phase:      LANDING BURN      " AT(0, 28).
    } ELSE {
        PRINT "Phase:      COAST             " AT(0, 28).
    }
    WAIT 0.05.
}

FUNCTION SteeringCorrections {
    // Offset de 97m para compensar el retroceso del landing burn
    SET LngCtrlPID:SETPOINT TO 97.

    IF ADDONS:TR:HASIMPACT {
        SET ErrorVector TO ADDONS:TR:IMPACTPOS:POSITION - landing_target:POSITION.
    }
    SET PositionError TO landing_target:POSITION - SHIP:POSITION.
    SET GSVec TO VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE).

    SET ApproachUPVector TO (landing_target:POSITION - BODY:POSITION):NORMALIZED.
    SET ApproachVector TO VXCL(UP:VECTOR, landing_target:POSITION - SHIP:POSITION):NORMALIZED.
    
    SET LatError TO VDOT(ANGLEAXIS(-90, ApproachUPVector) * ApproachVector, ErrorVector).
    SET LngError TO VDOT(ApproachVector, ErrorVector).
    
    SET LngCtrlPID:MAXOUTPUT TO MAX(MIN(ABS(LngError - LngCtrlPID:SETPOINT) / PIDFactor, 30), 2.5).
    SET LngCtrlPID:MINOUTPUT TO -LngCtrlPID:MAXOUTPUT.
    
    SET LngCtrl TO -LngCtrlPID:UPDATE(TIME:SECONDS, LngError).
    SET LatCtrl TO -LatCtrlPID:UPDATE(TIME:SECONDS, LatError).

    SET SteeringVector TO LOOKDIRUP(-SHIP:VELOCITY:SURFACE * ANGLEAXIS(-LngCtrl, LOOKDIRUP(-SHIP:VELOCITY:SURFACE, UP:VECTOR):STARVECTOR) * ANGLEAXIS(LatCtrl, UP:VECTOR), ApproachVector * ANGLEAXIS(2 * LatCtrl, UP:VECTOR)).
}

// === FUNCIÓN Landing Guidance MEJORADA ===
// Esta función reemplaza la función LandingGuidance existente (líneas 458-601)
// Incluye TODAS las mejoras: 5 zonas, tilts aumentados, ganancias mejoradas

FUNCTION LandingGuidance {
    LOCAL RadarRatio IS ALT:RADAR / BoosterHeight.
    LOCAL distToTarget IS PositionError:MAG.
    
    // HOVER LOGIC - Vertical Descent with Smart Correction
    IF HoverMode {
        // 1. Calcular Velocidad Deseada (Proporcional a la distancia)
        LOCAL MaxHorizSpeed IS 15. // Aumentado de 12 a 15 para mejor corrección a distancia
        LOCAL DistanceGain IS 0.6. // Aumentado de 0.5 a 0.6 para respuesta más rápida
        LOCAL SteeringGain IS 0.5. // Aumentado de 0.4 a 0.5 base
        
        // Vector hacia el target (Horizontal)
        LOCAL TargetDir IS VXCL(UP:VECTOR, PositionError):NORMALIZED.
        LOCAL TargetDist IS VXCL(UP:VECTOR, PositionError):MAG.
        
        // STABILITY: Ajuste de ganancias por distancia
        IF TargetDist < 50 {
            SET SteeringGain TO 0.4. // Aumentado de 0.25 a 0.4
        }
        IF TargetDist < 20 {
            SET SteeringGain TO 0.35. // Aumentado de 0.2 a 0.35
        }
        
        LOCAL DesiredVel IS V(0,0,0).

        // Límites de inclinación variables según distancia y altitud
        LOCAL MaxTilt IS 8. // AGRESIVO: Aumentado de 5 a 8 grados por defecto
        IF TargetDist > 100 {
            SET MaxTilt TO 15. // AGRESIVO: Aumentado de 10 a 15° para corrección muy agresiva
        } ELSE IF TargetDist >= 20 {
            // Escalar inclinación con la distancia
            SET MaxTilt TO MIN(12, MAX(8, TargetDist / 6)). // AGRESIVO: Escalado más alto
        } ELSE {
            // Error entre 0 y 20 metros: Inclinación máxima de 8 grados
            SET MaxTilt TO 8. // AGRESIVO: Aumentado de 5 a 8
        }

        // CINCO ZONAS DE FRENADO - SISTEMA MEJORADO
        LOCAL CurrentHSpeed IS VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE):MAG.
        LOCAL CurrentHVel IS VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE).
        
        // === CALCULAR DISTANCIA DE IMPACTO PARA CORRECCIÓN PROPORCIONAL ===
        LOCAL impactDist IS 9999.
        IF ADDONS:TR:HASIMPACT {
            LOCAL impactError IS ADDONS:TR:IMPACTPOS:POSITION - landing_target:POSITION.
            SET impactDist TO impactError:MAG.
        }
        
        // MaxTilt PROPORCIONAL a la distancia (usa el MAYOR entre impactDist y TargetDist)
        // MÁS AGRESIVO: 5-18 grados, ganancia /50 para reacción más rápida
        LOCAL maxError IS MAX(impactDist, TargetDist).
        LOCAL dynamicMaxTilt IS MIN(18, MAX(5, maxError / 50)). // Muy aumentado
        
        // === CORRECCIÓN LIMITADA A 3 GRADOS MÁXIMO EN TODAS LAS FASES ===
        // El punto de impacto ya está cerca cuando cambiamos a 1 motor
        LOCAL GLOBAL_MAX_TILT IS 8. // MÁXIMO 8 GRADOS EN TODAS LAS FASES (Agresivo)
        
        // === CANCELACIÓN DE VELOCIDAD HORIZONTAL A 50m ===
        IF ALT:RADAR < 50 AND CurrentHSpeed > 1 {
            SET DesiredVel TO V(0,0,0).
            
            // Ganancia para frenado
            LOCAL brakeGain IS 2.0.
            IF ALT:RADAR < 30 {
                SET brakeGain TO 3.0.
            }
            
            LOCAL BrakeVec IS -CurrentHVel * brakeGain.
            LOCAL BrakeSteering IS UP:VECTOR + BrakeVec.
            
            // LIMITAR A 2 GRADOS MÁXIMO
            IF VANG(UP:VECTOR, BrakeSteering) > GLOBAL_MAX_TILT {
                LOCAL HorizPart IS VXCL(UP:VECTOR, BrakeSteering):NORMALIZED.
                SET BrakeSteering TO UP:VECTOR + HorizPart * TAN(GLOBAL_MAX_TILT).
            }
            
            SET FinalVec TO BrakeSteering.
            PRINT "CANCEL HVEL: " + ROUND(CurrentHSpeed, 1) + "m/s Tilt:" + ROUND(VANG(UP:VECTOR, FinalVec),1) + "deg (MAX 2)" AT(0, 29).
            PRINT "ImpactDist: " + ROUND(impactDist, 0) + "m TargetDist: " + ROUND(TargetDist, 0) + "m" AT(0, 30).
            RETURN.
        }

        // === TODAS LAS ZONAS USAN MÁXIMO 2 GRADOS ===
        // Zona B y superiores (>30m) - Corrección suave hacia target
        IF ALT:RADAR > 30 {
            IF TargetDist > 5 {
                SET DesiredVel TO TargetDir * MIN(5, TargetDist * 0.1).
            } ELSE {
                SET DesiredVel TO V(0,0,0).
            }
            SET MaxTilt TO GLOBAL_MAX_TILT. // MÁXIMO 2 GRADOS
            SET SteeringGain TO 0.5.
            PRINT "ZONA B+: Tilt MAX 2deg TargetDist:" + ROUND(TargetDist,0) + "m" AT(0, 29).
        }
        // Zona A - Final Approach (15-30m)
        ELSE IF ALT:RADAR > 15 {
            SET DesiredVel TO V(0,0,0).
            SET MaxTilt TO GLOBAL_MAX_TILT. // MÁXIMO 2 GRADOS
            SET SteeringGain TO 0.5.
            
            LOCAL CurrentHSpeedA IS VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE):MAG.
            PRINT "ZONA A: Tilt MAX 2deg HVel:" + ROUND(CurrentHSpeedA,1) + "m/s" AT(0, 29).
        }
        // ZONA FINAL - Ultra-Final Landing (<15m) - SIMPLIFICADO A 2 GRADOS MAX
        ELSE {
            LOCAL FinalHVel IS VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE).
            LOCAL FinalHSpeed IS FinalHVel:MAG.
            LOCAL FinalBrakeVec IS -FinalHVel * 2.0. // Frenado de velocidad horizontal
            
            // SIEMPRE usar GLOBAL_MAX_TILT (2 grados)
            SET MaxTilt TO GLOBAL_MAX_TILT.
            
            // Aplicar Tilt Limit de 2 grados
            LOCAL FinalRawSteering IS UP:VECTOR + FinalBrakeVec.
            
            IF VANG(UP:VECTOR, FinalRawSteering) > GLOBAL_MAX_TILT {
                LOCAL FinalHorizPart IS VXCL(UP:VECTOR, FinalRawSteering):NORMALIZED.
                SET FinalRawSteering TO UP:VECTOR + FinalHorizPart * TAN(GLOBAL_MAX_TILT).
            }
            
            SET FinalVec TO FinalRawSteering.
            PRINT "FINAL: HVel:" + ROUND(FinalHSpeed,1) + "m/s Tilt:MAX 2deg Dist:" + ROUND(TargetDist,0) + "m" AT(0, 29).
            
            RETURN. 
        }
        

        
        // 2. Calcular Error de Velocidad
        LOCAL CurrentHorizVel IS VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE).
        LOCAL VelError IS DesiredVel - CurrentHorizVel.
        
        // 3. Calcular Vector de Dirección (Steering)
        LOCAL CorrectionVec IS VelError * SteeringGain.
        
        // Vector final: Arriba + Corrección
        LOCAL RawSteering IS UP:VECTOR + CorrectionVec.
        
        // Aplicar límite de inclinación (Dinámico)
        // Removed the 100m override to allow better corrections at altitude
        IF VANG(UP:VECTOR, RawSteering) > MaxTilt {
            LOCAL HorizontalPart IS VXCL(UP:VECTOR, RawSteering):NORMALIZED.
            SET RawSteering TO UP:VECTOR + HorizontalPart * TAN(MaxTilt).
        }
        
        SET FinalVec TO RawSteering.
        
        PRINT "Distancia:  " + ROUND(TargetDist, 1) + " m    " AT(0, 30).
        PRINT "Tilt:       " + ROUND(VANG(UP:VECTOR, FinalVec), 2) + " deg  " AT(0, 31).
        
    } 
    // LANDING BURN LOGIC (Old logic preserved for high altitude burn)
    ELSE {
        LOCAL Fpos IS MAX(MIN(-0.0005 * RadarRatio + 0.006, 0.012), 0).
        LOCAL Ferr IS MIN(MAX(0.002 * RadarRatio + 0.005, 0.012), 0.024).
        LOCAL Fgs IS MIN(MAX(-0.01 * RadarRatio + 0.04, 0.0024), 0.036).
        LOCAL Ftrv IS 0. 
        LOCAL Ffwd IS 1. 
        LOCAL Fair IS 0. 
        
        LOCAL gsRatio IS PositionError:MAG * 2 / MAX(GSVec:MAG, 0.0001).
        LOCAL vertRatio IS ALT:RADAR * 2 / MAX(ABS(SHIP:VERTICALSPEED), 0.1).
        LOCAL closureRatio IS (gsRatio / vertRatio) + ALT:RADAR / 6600.
        
        SET Fgs TO Fgs * MAX(0.8 / closureRatio, 0.6).
        SET Fpos TO Fpos * MIN(MAX(closureRatio^4, 0.1), 1.4).
        
        IF VANG(ErrorVector, PositionError) > 90 {
            SET Ferr TO Ferr * 2.2.
            SET Fpos TO Fpos / 2.
        }
        
        SET FinalVec TO UP:VECTOR
            - Fpos * PositionError
            - Ferr * ErrorVector
            - Fgs * GSVec
            + Ffwd * SHIP:FACING:FOREVECTOR.
    }
}

// === FUNCIÓN LandingThrottle MEJORADA ===
// Esta función reemplaza la función LandingThrottle existente (líneas 603-646)
// Incluye velocidades de descenso reducidas para más tiempo de corrección

FUNCTION LandingThrottle {
    IF HoverMode {
        // Calcular error horizontal total (distancia al target)
        LOCAL horizError IS VXCL(UP:VECTOR, PositionError):MAG.
        
        LOCAL targetDescendSpeed IS -20. // Reducido de -30 a -20 para más tiempo de corrección
        
        // MODO CORRECCIÓN AGRESIVA: Error > 100m
        IF horizError > 100 {
            SET targetDescendSpeed TO -15. // Reducido de -20 a -15 para máximo tiempo de corrección
        } 
        // SISTEMA DE FRENADO GRADUAL BASADO EN ALTITUD RADAR (Error < 100m)
        ELSE {
            // La barca está a 34m sobre el nivel del mar

            // A los 200m radar: Descenso más lento
            IF ALT:RADAR < 200 {
                SET targetDescendSpeed TO -12.
            }

            // A los 100m radar: Descenso lento
            IF ALT:RADAR < 100 {
                SET targetDescendSpeed TO -8.
            }

            // Por debajo de 50m radar: Descenso muy suave para touchdown
            IF ALT:RADAR < 50 {
                SET targetDescendSpeed TO -2.
                
                // NUEVO: Si hay velocidad horizontal alta, DETENER descenso hasta cancelarla
                LOCAL currentHSpd IS VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE):MAG.
                IF currentHSpd > 2 {
                    SET targetDescendSpeed TO -1. // Casi hover hasta cancelar velocidad horizontal
                }
                IF currentHSpd > 3 {
                    SET targetDescendSpeed TO -0.5. // Emergencia: casi parar
                }
            }
        }
        
        SET HoverPID:SETPOINT TO targetDescendSpeed.
        
        LOCAL pidOut IS HoverPID:UPDATE(TIME:SECONDS, SHIP:VERTICALSPEED).
        RETURN MAX(MIN(pidOut, 1.0), 0.1). 
    } ELSE {
        LOCAL maxDecel IS (13 * BoosterRaptorThrust / SHIP:MASS) - 9.81. 
        LOCAL stopDist IS (SHIP:VELOCITY:SURFACE:MAG^2) / (2 * maxDecel).
        LOCAL landingRatio IS stopDist / MAX(ALT:RADAR, 1).
        LOCAL thro IS MAX((landingRatio * MIN(maxDecel, 50)) / maxDecel, 0.33).
        IF thro > 1 { RETURN 1. }
        RETURN thro.
    }
}

// === ATERRIZAJE COMPLETADO - CORTAR POTENCIA INMEDIATAMENTE ===
LOCK THROTTLE TO 0.
UNLOCK STEERING.
SAS ON.
PRINT "¡ATERRIZAJE / AMERIZAJE COMPLETADO!".
PRINT "Throttle cortado. Esperando 4 segundos para apagar motor...".
WAIT 4.
LOCAL motores_centrales IS SHIP:PARTSTAGGED("1").
FOR eng IN motores_centrales {
    eng:SHUTDOWN().
}
PRINT "Motor central (tag 1) apagado.".
PRINT "Fin del programa de control de retorno".