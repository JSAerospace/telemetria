// boosterBLOCK2.ks - Script de lanzamiento
// Motores: 1-3 centrales, 4-13 medios, 14-33 exteriores
// ============================================================
// === FUNCION DE REFUERZO DE CARGA (METODO RSS) ===
// ============================================================
FUNCTION ReforzarCarga {
    // RESETEAR GLOBALES (KUNIVERSE) A DEFECTO
    SET KUNIVERSE:DEFAULTLOADDISTANCE:FLYING:UNLOAD TO 2500.
    SET KUNIVERSE:DEFAULTLOADDISTANCE:FLYING:LOAD TO 2250.
    SET KUNIVERSE:DEFAULTLOADDISTANCE:SUBORBITAL:UNLOAD TO 2500.
    SET KUNIVERSE:DEFAULTLOADDISTANCE:SUBORBITAL:LOAD TO 2250.
    SET KUNIVERSE:DEFAULTLOADDISTANCE:ORBIT:UNLOAD TO 2500.
    SET KUNIVERSE:DEFAULTLOADDISTANCE:ORBIT:LOAD TO 2250.
    SET KUNIVERSE:DEFAULTLOADDISTANCE:LANDED:UNLOAD TO 2500.
    SET KUNIVERSE:DEFAULTLOADDISTANCE:LANDED:LOAD TO 2250.

    // Configuración RSS - Distancias extremas para mantener conexión
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
    
    WAIT 0.01.
    SET SHIP:LOADDISTANCE:LANDED:UNLOAD TO 1750000.
    SET SHIP:LOADDISTANCE:LANDED:LOAD TO 1700000.
    WAIT 0.001.
    SET SHIP:LOADDISTANCE:LANDED:PACK TO 1749500.
    SET SHIP:LOADDISTANCE:LANDED:UNPACK TO 1699000.
}

// ============================================================
// === FUNCION PARA ESCRIBIR ALTURA A JSON ===
// ============================================================
GLOBAL TELEMETRY_A IS "0:/telemetry_booster_A.json".
GLOBAL TELEMETRY_B IS "0:/telemetry_booster_B.json".
GLOBAL TELEMETRY_TOGGLE IS TRUE.

FUNCTION LogTelemetry {
    PARAMETER statusText.
    
    // 1. Estados de Motores (1-33)
    // Generar un Lexicon con el estado (1=Activo, 0=Inactivo)
    LOCAL engStates IS LEXICON().
    
    // Optimización: Solo chequear si throttle > 0, si no todos 0
    // Optimización: Solo chequear si throttle > 0, si no todos 0
    IF THROTTLE > 0 {
        // Center C1-C3
        FOR i IN RANGE(1, 4) {
            LOCAL key IS "C" + i.
            LOCAL parts IS SHIP:PARTSTAGGED(key).
            LOCAL st IS 0.
            FOR p IN parts { IF p:IGNITION { SET st TO 1. } }
            engStates:ADD(key, st).
        }
        // Ring R1-R8
        FOR i IN RANGE(1, 9) {
            LOCAL key IS "R" + i.
            LOCAL parts IS SHIP:PARTSTAGGED(key).
            LOCAL st IS 0.
            FOR p IN parts { IF p:IGNITION { SET st TO 1. } }
            engStates:ADD(key, st).
        }
    }

    // 2. Combustible (RP-1/LOX o METHALOX)
    // Asumimos que el tanque principal está taggeado BOOSTER
    LOCAL fuelPct IS 0.
    LOCAL parts IS SHIP:PARTSTAGGED("BOOSTER").
    IF parts:LENGTH > 0 {
        LOCAL tank IS parts[0].
        LOCAL curr IS 0.
        LOCAL cap IS 0.
        FOR res IN tank:RESOURCES {
            SET curr TO curr + res:AMOUNT.
            SET cap TO cap + res:CAPACITY.
        }
        IF cap > 0 { SET fuelPct TO (curr / cap) * 100. }
    }

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
    
    // 4. Escribir alternado A/B
    IF TELEMETRY_TOGGLE {
        WRITEJSON(data, TELEMETRY_A).
    } ELSE {
        WRITEJSON(data, TELEMETRY_B).
    }
    SET TELEMETRY_TOGGLE TO NOT TELEMETRY_TOGGLE.
}

// SIEMPRE borrar y recrear el archivo al inicio para evitar datos antiguos
// Inicializar archivos
WRITEJSON(LEXICON("status", "BOOT"), TELEMETRY_A).
WRITEJSON(LEXICON("status", "BOOT"), TELEMETRY_B).
PRINT "Telemetry Init OK" AT (0, 2).
PRINT "altura.json RESET OK" AT (0, 2).

// === APLICAR CARGA INMEDIATAMENTE ===
ReforzarCarga().

PRINT "=== BOOSTER BLOCK 2 ===" AT (0, 0).
PRINT "CARGA: 1750 km ACTIVA" AT (0, 1).
SET LAUNCH_PAD TO SHIP:GEOPOSITION. // Guardar coordenadas de la torre
PRINT "COORD TORRE GUARDADAS" AT (0, 1).
PRINT "Presiona G para iniciar secuencia de lanzamiento".

// === BUSCAR TORRE (TITANS/KANALOA) ===
// Buscar ahora que estamos cerca y cargados
GLOBAL TOWER_VESSEL IS 0.
// 1. Buscar en mi propio buque (si estamos conectados)
FOR p IN SHIP:PARTS {
    IF p:NAME:CONTAINS("Titans") OR p:TITLE:CONTAINS("Kanaloa") OR p:TITLE:CONTAINS("CompoMax") {
        SET TOWER_VESSEL TO SHIP.
        PRINT "TOWER FOUND (ON SHIP): " + p:TITLE AT (0, 2).
        BREAK.
    }
}
// 2. Si no, buscar en targets cercanos
IF TOWER_VESSEL = 0 {
    LIST TARGETS IN targets.
    FOR t IN targets {
        IF t:LOADED {
            FOR p IN t:PARTS {
                IF p:NAME:CONTAINS("Titans") OR p:TITLE:CONTAINS("Kanaloa") OR p:TITLE:CONTAINS("CompoMax") {
                    SET TOWER_VESSEL TO t.
                    PRINT "TOWER FOUND: " + t:NAME AT (0, 2).
                    BREAK.
                }
            }
        }
        IF TOWER_VESSEL <> 0 { BREAK. }
    }
}
IF TOWER_VESSEL = 0 { PRINT "WARNING: TOWER NOT FOUND" AT (0, 2). }

// === OPCION DE SIMULAR FALLO DE MOTOR ===
GLOBAL SIMULAR_FALLO_MOTOR IS FALSE.

PRINT " " AT (0, 3).
PRINT "Pulsa 'F' para ACTIVAR simulacion fallo motor 2" AT (0, 4).
PRINT "Pulsa 'G' para iniciar lanzamiento" AT (0, 5).
PRINT " " AT (0, 6).
PRINT "FALLO MOTOR: DESACTIVADO" AT (0, 7).

// Esperar tecla G o F
UNTIL FALSE {
    IF TERMINAL:INPUT:HASCHAR {
        LOCAL ch IS TERMINAL:INPUT:GETCHAR().
        IF ch = "g" OR ch = "G" {
            BREAK.
        }
        ELSE IF ch = "f" OR ch = "F" {
            SET SIMULAR_FALLO_MOTOR TO NOT SIMULAR_FALLO_MOTOR.
            IF SIMULAR_FALLO_MOTOR {
                PRINT "FALLO MOTOR: >> ACTIVADO << (Motor 2 fallara)" AT (0, 7).
            } ELSE {
                PRINT "FALLO MOTOR: DESACTIVADO                     " AT (0, 7).
            }
        }
    }
    WAIT 0.1.
}

// Cuenta atrás T-10
PRINT " ".
PRINT "INICIANDO SECUENCIA DE LANZAMIENTO".

FROM { LOCAL t IS 10. } UNTIL t = 0 STEP { SET t TO t - 1. } DO {
    PRINT "T-" + t + " segundos   " AT (0, 5).
    
    // A T-2 encender motores
    IF t = 2 {
        PRINT "IGNICION DE MOTORES" AT (0, 6).
        LOCK THROTTLE TO 1.0.
        LOCK STEERING TO HEADING(90, 90).
        
        // Motores centrales (1-3)
        FOR i IN RANGE(1, 4) {
            LOCAL motores IS SHIP:PARTSTAGGED(i:TOSTRING).
            FOR eng IN motores {
                eng:ACTIVATE().
            }
        }
        
        // Motores medios (4-13)
        FOR i IN RANGE(4, 14) {
            LOCAL motores IS SHIP:PARTSTAGGED(i:TOSTRING).
            FOR eng IN motores {
                eng:ACTIVATE().
            }
        }
        
        // Motores exteriores (14-33)
        FOR i IN RANGE(14, 34) {
            LOCAL motores IS SHIP:PARTSTAGGED(i:TOSTRING).
            FOR eng IN motores {
                eng:ACTIVATE().
            }
        }
        
        PRINT "33 MOTORES ENCENDIDOS" AT (0, 7).
    }
    
    WAIT 1.
}

PRINT "T-0 LIFTOFF!        " AT (0, 5).

// T+1: Liberar plataforma
WAIT 1.
AG1 ON.
PRINT "T+1 PLATAFORMA LIBERADA" AT (0, 8).

// === ASCENSO ===
PRINT "INICIANDO ASCENSO" AT (0, 10).

// Configuración del tanque
SET FUEL_MAX TO 354155.23.
SET OX_MAX TO 432856.39.
SET MOTOR_APAGADO TO FALSE.

// Configurar variables iniciales de dirección
SET PITCH TO 90.
SET MI_ROLL TO 90.
LOCK STEERING TO HEADING(90, PITCH, MI_ROLL).

UNTIL FALSE {
    ReforzarCarga(). // CRITICO: Cada ciclo
    LogTelemetry("ASCENT").
    
    // Iniciar inclinación gradual a medida que sube.
    SET PITCH TO MAX(15, 90 - (ALTITUDE / 750)).  // Inclinación suave hasta llegar a 15°.
    
    // Roll: 90° durante ascenso, 0° a partir de 40km
    IF ALTITUDE < 40000 {
        SET MI_ROLL TO 90.
    } ELSE {
        SET MI_ROLL TO 0.
    }
    
    // NO hacemos LOCK STEERING aqui dentro, ya está hecho fuera
    // Las variables PITCH y MI_ROLL se actualizan automáticamente en el HEADING
    
    // Calcular porcentaje de combustible
    SET TANQUE TO SHIP:PARTSTAGGED("BOOSTER")[0].
    SET FUEL_ACTUAL TO 0.
    FOR res IN TANQUE:RESOURCES {
        SET FUEL_ACTUAL TO FUEL_ACTUAL + res:AMOUNT.
    }
    SET FUEL_PORCENTAJE TO (FUEL_ACTUAL / (FUEL_MAX + OX_MAX)) * 100.
    
    PRINT "Altitud: " + ROUND(ALTITUDE/1000, 1) + " km   " AT (0, 11).
    PRINT "Pitch: " + ROUND(PITCH, 1) + "°   " AT (0, 12).
    PRINT "Fuel: " + ROUND(FUEL_PORCENTAJE, 1) + "%   " AT (0, 13).
    
    // Al 27% apagar motores medios y exteriores (simétrico)
    IF FUEL_PORCENTAJE <= 27 AND NOT MOTOR_APAGADO {
        PRINT "APAGANDO MOTORES EXTERNOS" AT (0, 15).
        
        // Apagar motores medios (4-13) simétricamente
        FOR i IN RANGE(4, 14) {
            LOCAL motores IS SHIP:PARTSTAGGED(i:TOSTRING).
            FOR eng IN motores {
                eng:SHUTDOWN().
            }
        }
        
        // Apagar motores exteriores (14-33) simétricamente
        FOR i IN RANGE(14, 34) {
            LOCAL motores IS SHIP:PARTSTAGGED(i:TOSTRING).
            FOR eng IN motores {
                eng:SHUTDOWN().
            }
        }
        
        SET MOTOR_APAGADO TO TRUE.
        PRINT "SOLO MOTORES CENTRALES (1-3) ACTIVOS" AT (0, 16).
        
        // Esperar 3 segundos y separar
        WAIT 3.
        PRINT "SEPARACION" AT (0, 17).
        FOR sep IN SHIP:PARTSTAGGED("HOT") {
            sep:GETMODULE("ModuleDecouple"):DOEVENT("decouple").
        }
        PRINT "BOOSTER SEPARADO" AT (0, 18).
        
        // Configuración inicial de target (Defecto: TORRE)
        SET TARGET_MODE TO "TOWER". // "WATER" o "TOWER"
        SET LANDING_TARGET TO LAUNCH_PAD. // Coordenadas de la torre
        
        // Buscar procesador de la torre para catch
        SET TOWER_PROCESSOR TO 0.
        
        IF ADDONS:TR:AVAILABLE {
            ADDONS:TR:SETTARGET(LANDING_TARGET).
        }
        
        BREAK.
    }
    
    WAIT 0.5.  // Giro gradual.
}

// === BOOSTBACK (FLIP CONTROLADO) ===
CLEARSCREEN.
PRINT "=== BOOSTBACK ===" AT (0, 0).

// Variables de guía
SET LngError TO 0.
SET LatError TO 0.
SET ErrorVector TO V(0,0,0).
SET PositionError TO V(0,0,0).
SET GSVec TO V(0,0,0).
SET LngCtrl TO 0.
SET LatCtrl TO 0.

// PIDs de guía
SET PIDFactor TO 8.
SET LngCtrlPID TO PIDLOOP(0.35, 0.3, 0.25, -10, 10).
SET LatCtrlPID TO PIDLOOP(0.25, 0.2, 0.15, -5, 5).
SET LngCtrlPID:SETPOINT TO 50.

// Calcular vectores de aproximación
LOCAL ApproachUPVector IS (LANDING_TARGET:POSITION - BODY:POSITION):NORMALIZED.
LOCAL ApproachVector IS VXCL(UP:VECTOR, LANDING_TARGET:POSITION - SHIP:POSITION):NORMALIZED.

// Función para calcular correcciones de steering
FUNCTION SteeringCorrections {
    IF ADDONS:TR:HASIMPACT {
        SET PositionError TO LANDING_TARGET:POSITION - SHIP:POSITION.
        SET ErrorVector TO ADDONS:TR:IMPACTPOS:POSITION - LANDING_TARGET:POSITION.
        SET GSVec TO VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE).
        
        SET LatError TO VDOT(ANGLEAXIS(-90, ApproachUPVector) * ApproachVector, ErrorVector).
        SET LngError TO VDOT(ApproachVector, ErrorVector).
        
        SET LngCtrlPID:MAXOUTPUT TO MAX(MIN(ABS(LngError) / PIDFactor, 10), 1.0).
        SET LngCtrlPID:MINOUTPUT TO -LngCtrlPID:MAXOUTPUT.
        
        SET LngCtrl TO -LngCtrlPID:UPDATE(TIME:SECONDS, LngError).
        SET LatCtrl TO -LatCtrlPID:UPDATE(TIME:SECONDS, LatError).
    }
}

// Calcular pitch actual (0 = horizontal, 90 = vertical arriba, -90 = vertical abajo)
FUNCTION GetPitchAngle {
    RETURN 90 - VANG(UP:VECTOR, SHIP:FACING:FOREVECTOR).
}

// --- FASE 1: FLIP CONTROLADO A HORIZONTAL ---
PRINT "INICIANDO FLIP CONTROLADO..." AT (0, 2).

SET separationTime TO TIME:SECONDS.
RCS ON.
SAS OFF.

// Encender motores centrales al 30% para control
PRINT "ENCENDIENDO CENTRALES (1-3)" AT (0, 3).
FOR i IN RANGE(1, 4) {
    LOCAL motores IS SHIP:PARTSTAGGED(i:TOSTRING).
    FOR eng IN motores { eng:ACTIVATE(). }
}
LOCK THROTTLE TO 0.3.

// Calcular heading hacia el target (opuesto a la dirección de vuelo actual)
LOCAL targetHeading IS LANDING_TARGET:HEADING.
PRINT "Target Heading: " + ROUND(targetHeading, 1) + " deg" AT (0, 4).

// Usar LOCK STEERING para girar suavemente a horizontal (pitch 0)
// Roll 0 para mantener orientación correcta
LOCK STEERING TO HEADING(targetHeading, 0, 0).

PRINT "GIRANDO A HORIZONTAL..." AT (0, 5).

// Esperar hasta estar horizontal (pitch cerca de 0)
LOCAL pitchAngle IS GetPitchAngle().
LOCAL flipStartTime IS TIME:SECONDS.

UNTIL ABS(pitchAngle) < 10 {
    ReforzarCarga().
    SET pitchAngle TO GetPitchAngle().
    LOCAL elapsed IS TIME:SECONDS - flipStartTime.
    
    // Throttle alto durante el flip para control con motores
    LOCK THROTTLE TO 1.0.
    
    PRINT "Flip: Pitch " + ROUND(pitchAngle, 1) + " deg  T+" + ROUND(elapsed, 1) + "s   " AT (0, 6).
    
    // Timeout de seguridad: 15 segundos
    IF elapsed > 15 { 
        PRINT "TIMEOUT - FORZANDO HORIZONTAL" AT (0, 7).
        BREAK. 
    }
    
    WAIT 0.1.
}

// --- FASE 2: ESTABILIZACIÓN HORIZONTAL (5 SEGUNDOS) ---
PRINT "HORIZONTAL ALCANZADO" AT (0, 5).
PRINT "ESTABILIZANDO 5 SEGUNDOS..." AT (0, 6).

// Mantener steering horizontal
LOCK STEERING TO HEADING(targetHeading, 0, 0).
LOCK THROTTLE TO 0.8.

// Encender motores medios durante estabilización
PRINT "ENCENDIENDO MEDIOS (4-13)" AT (0, 7).
FOR i IN RANGE(4, 14) {
    LOCAL motores IS SHIP:PARTSTAGGED(i:TOSTRING).
    FOR eng IN motores { eng:ACTIVATE(). }
}

// Esperar 5 segundos para estabilizar completamente
LOCAL stabilizeStart IS TIME:SECONDS.
UNTIL TIME:SECONDS - stabilizeStart > 5 {
    ReforzarCarga().
    LogTelemetry("STABILIZING").
    
    LOCAL remaining IS 5 - (TIME:SECONDS - stabilizeStart).
    LOCAL currentPitch IS GetPitchAngle().
    LOCAL angularRate IS SHIP:ANGULARVEL:MAG * 57.3. // rad/s a deg/s
    
    PRINT "Estabilizando: " + ROUND(remaining, 1) + " s   " AT (0, 8).
    PRINT "Pitch: " + ROUND(currentPitch, 1) + " deg  AngVel: " + ROUND(angularRate, 1) + " deg/s   " AT (0, 9).
    
    WAIT 0.1.
}

// --- FASE 3: INICIAR CORRECCIONES ---
PRINT "ESTABILIZADO - INICIANDO BOOSTBACK BURN" AT (0, 6).
LOCK THROTTLE TO 1.0.

// --- FASE 2: BOOSTBACK BURN ---
PRINT "BOOSTBACK BURN" AT (0, 6).
SET BOOSTBACK_ACTIVO TO TRUE.
SET MEDIOS_APAGADOS TO FALSE.

PRINT "PULSA 'G' => IR A TORRE" AT (0, 18).
PRINT "PULSA 'A' => IR AL AGUA (ABORT)" AT (0, 19).

// Loop principal de boostback (como booster.ks)
UNTIL NOT BOOSTBACK_ACTIVO {
    ReforzarCarga().
    LogTelemetry("BOOSTBACK").
    SteeringCorrections().
    
    // Actualizar vectores de aproximación
    SET ApproachUPVector TO (LANDING_TARGET:POSITION - BODY:POSITION):NORMALIZED.
    SET ApproachVector TO VXCL(UP:VECTOR, LANDING_TARGET:POSITION - SHIP:POSITION):NORMALIZED.
    
    // Check Input Usuario
    IF TERMINAL:INPUT:HASCHAR {
        LOCAL ch IS TERMINAL:INPUT:GETCHAR().
        IF ch = "g" OR ch = "G" {
            SET TARGET_MODE TO "TOWER".
            SET LANDING_TARGET TO LAUNCH_PAD.
            IF ADDONS:TR:AVAILABLE { ADDONS:TR:SETTARGET(LANDING_TARGET). }
        } ELSE IF ch = "a" OR ch = "A" {
            SET TARGET_MODE TO "WATER".
            SET LANDING_TARGET TO LATLNG(28.635687, -80.575344).
            IF ADDONS:TR:AVAILABLE { ADDONS:TR:SETTARGET(LANDING_TARGET). }
        }
    }
    
    // Steering apunta hacia -ErrorVector (hacia el target)
    LOCK SteeringVector TO LOOKDIRUP(VXCL(UP:VECTOR, -ErrorVector), UP:VECTOR).
    LOCK STEERING TO SteeringVector.
    
    // Throttle proporcional al error longitudinal - SIN LIMITE INFERIOR
    LOCAL throttleVal IS MAX(MIN(-(LngError + 1000) / 2500 + 0.01, 1.0), 0.1).
    LOCK THROTTLE TO throttleVal.
    
    // Display
    SET DIST_TARGET TO ErrorVector:MAG.
    PRINT "MODE: " + TARGET_MODE + "           " AT (0, 7).
    PRINT "Error Mag:   " + ROUND(DIST_TARGET/1000, 1) + " km     " AT (0, 8).
    PRINT "Lng Error:   " + ROUND(LngError, 0) + " m       " AT (0, 9).
    PRINT "Lat Error:   " + ROUND(LatError, 0) + " m       " AT (0, 10).
    PRINT "H Speed:     " + ROUND(GSVec:MAG, 0) + " m/s     " AT (0, 11).
    PRINT "Throttle:    " + ROUND(throttleVal * 100, 0) + "%      " AT (0, 12).
    
    // --- CRITERIOS DE TERMINACION (MODO TORRE) ---
    
    // Apagar medios a 25km del target (solo modo TORRE)
    IF TARGET_MODE = "TOWER" AND ErrorVector:MAG < 25000 AND NOT MEDIOS_APAGADOS {
        PRINT "MEDIOS OFF (25km)" AT (0, 14).
        FOR i IN RANGE(4, 14) {
            LOCAL motores IS SHIP:PARTSTAGGED(i:TOSTRING).
            FOR eng IN motores { eng:SHUTDOWN(). }
        }
        SET MEDIOS_APAGADOS TO TRUE.
    }
    
    // Apagar centrales a 5km del target (solo modo TORRE)
    IF TARGET_MODE = "TOWER" AND ErrorVector:MAG < 5000 {
        PRINT "CENTRALES OFF (5km) - BOOSTBACK CUTOFF" AT (0, 15).
        FOR i IN RANGE(1, 4) {
            LOCAL motores IS SHIP:PARTSTAGGED(i:TOSTRING).
            FOR eng IN motores { eng:SHUTDOWN(). }
        }
        LOCK THROTTLE TO 0.
        SET BOOSTBACK_ACTIVO TO FALSE.
    }
    
    // Modo WATER: criterio original por LngError
    IF TARGET_MODE = "WATER" {
        IF ErrorVector:MAG < 7000 AND NOT MEDIOS_APAGADOS {
            PRINT "APAGANDO MOTORES MEDIOS" AT (0, 14).
            FOR i IN RANGE(4, 14) {
                LOCAL motores IS SHIP:PARTSTAGGED(i:TOSTRING).
                FOR eng IN motores { eng:SHUTDOWN(). }
            }
            SET MEDIOS_APAGADOS TO TRUE.
        }
        
        IF LngError > -1500 OR ErrorVector:MAG < 2000 {
            PRINT "BOOSTBACK CUTOFF" AT (0, 15).
            FOR i IN RANGE(1, 4) {
                LOCAL motores IS SHIP:PARTSTAGGED(i:TOSTRING).
                FOR eng IN motores { eng:SHUTDOWN(). }
            }
            LOCK THROTTLE TO 0.
            SET BOOSTBACK_ACTIVO TO FALSE.
        }
    }
    
    // Seguridad: terminar si bajamos de 50km
    IF ALTITUDE < 50000 {
        PRINT "ALTITUDE SAFETY CUTOFF" AT (0, 15).
        FOR i IN RANGE(1, 14) {
            LOCAL motores IS SHIP:PARTSTAGGED(i:TOSTRING).
            FOR eng IN motores { eng:SHUTDOWN(). }
        }
        LOCK THROTTLE TO 0.
        SET BOOSTBACK_ACTIVO TO FALSE.
    }
    
    WAIT 0.05.
}

PRINT " " AT (0, 14).
PRINT "BOOSTBACK COMPLETADO" AT (0, 15).

// Activar RCS y AG2
RCS ON.
AG2 ON.
PRINT "RCS Y AG2 ACTIVADOS" AT (0, 14).

// Poner booster vertical con 0 grados de roll
LOCK STEERING TO HEADING(90, 90, 90).  // Apuntar arriba, roll 0
PRINT "ORIENTACION VERTICAL" AT (0, 15).

// Esperar a que empiece a descender
PRINT "Esperando apogeo..." AT (0, 16).
WAIT UNTIL SHIP:VERTICALSPEED < -1.
PRINT "DESCENSO INICIADO" AT (0, 17).

// Transición suave a retrograde mientras desciende
PRINT "Transicion a retrograde..." AT (0, 18).
UNTIL SHIP:ALTITUDE < 70000 {
    ReforzarCarga(). // CRITICO: Cada ciclo
    LogTelemetry("TRANSITION").
    
    // Interpolar entre vertical y retrograde según altitud
    LOCAL interpFactor IS (SHIP:ALTITUDE - 70000) / 50000.  // 1 a 120km, 0 a 70km
    SET interpFactor TO MAX(0, MIN(1, interpFactor)).
    
    // Mezclar orientación: vertical cuando interpFactor=1, retrograde cuando interpFactor=0
    IF interpFactor > 0.5 {
        LOCK STEERING TO HEADING(90, 90, 90).
    } ELSE {
        LOCK STEERING TO LOOKDIRUP(SRFRETROGRADE:VECTOR, HEADING(90,0):VECTOR).
    }
    
    PRINT "Altitud: " + ROUND(SHIP:ALTITUDE/1000, 1) + " km   " AT (0, 19).
    PRINT "V.Vert:  " + ROUND(SHIP:VERTICALSPEED, 0) + " m/s   " AT (0, 20).
    WAIT 0.2.
}

// === VARIABLES DE GUIDANCE ===
SET PIDFactor TO 10.
SET LngCtrlPID TO PIDLOOP(0.35, 0.3, 0.25, -10, 10).
SET LatCtrlPID TO PIDLOOP(0.25, 0.2, 0.1, -2, 2).

SET LngCtrl TO 0.
SET LatCtrl TO 0.
SET ErrorVector TO V(0,0,0).
SET PositionError TO V(0,0,0).
SET GSVec TO V(0,0,0).
SET LngError TO 0.
SET LatError TO 0.
SET SteeringVector TO UP:VECTOR.

// Variables de control de venteo
SET VENTEO_ACTIVO TO FALSE.
SET VENTEO_COMPLETADO TO FALSE.

// === DESCENSO DINÁMICO (desde 70km) ===
CLEARSCREEN.
PRINT "=== DESCENSO DINAMICO ===" AT (0, 0).
PRINT "Altitud < 70km - Iniciando guia" AT (0, 2).

LOCK STEERING TO SteeringVector.

// Loop de descenso dinámico - guía aerodinámica hacia el target
UNTIL ALT:RADAR < 2600 {
    ReforzarCarga(). // CRITICO: Cada ciclo
    LogTelemetry("AERO DESCENT").
    
    // === VENTEO A 50KM ===
    IF SHIP:ALTITUDE < 50000 AND NOT VENTEO_COMPLETADO {
        IF NOT VENTEO_ACTIVO {
            AG3 ON.
            SET VENTEO_ACTIVO TO TRUE.
            PRINT "VENTEO ACTIVADO" AT (0, 3).
        }
        
        // Calcular porcentaje de combustible
        SET TANQUE TO SHIP:PARTSTAGGED("BOOSTER")[0].
        SET FUEL_ACTUAL TO 0.
        FOR res IN TANQUE:RESOURCES {
            SET FUEL_ACTUAL TO FUEL_ACTUAL + res:AMOUNT.
        }
        SET FUEL_PORCENTAJE TO (FUEL_ACTUAL / (FUEL_MAX + OX_MAX)) * 100.
        
        IF FUEL_PORCENTAJE <= 5 {
            AG3 OFF.
            // RCS se mantiene activo para control
            SET VENTEO_COMPLETADO TO TRUE.
            PRINT "VENTEO COMPLETADO - 5%" AT (0, 3).
        }
    }

    // Calcular errores con offset para landing burn
    IF ADDONS:TR:HASIMPACT {
        // Offset diferente según modo
        LOCAL offsetDist IS 100.  // Default: WATER
        IF TARGET_MODE = "TOWER" {
            SET offsetDist TO 300.  // TORRE: 300m de offset
        }
        
        LOCAL ApproxDir IS VXCL(UP:VECTOR, LANDING_TARGET:POSITION - SHIP:POSITION):NORMALIZED.
        SET ErrorVector TO ADDONS:TR:IMPACTPOS:POSITION - (LANDING_TARGET:POSITION + ApproxDir * offsetDist).
    }
    SET PositionError TO LANDING_TARGET:POSITION - SHIP:POSITION.
    SET GSVec TO VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE).
    
    LOCAL ApproachUPVector IS (LANDING_TARGET:POSITION - BODY:POSITION):NORMALIZED.
    LOCAL ApproachVector IS VXCL(UP:VECTOR, LANDING_TARGET:POSITION - SHIP:POSITION):NORMALIZED.
    
    SET LatError TO VDOT(ANGLEAXIS(-90, ApproachUPVector) * ApproachVector, ErrorVector).
    SET LngError TO VDOT(ApproachVector, ErrorVector).
    
    // PID control para steering
    SET LngCtrlPID:SETPOINT TO 0.
    SET LngCtrlPID:MAXOUTPUT TO MAX(MIN(ABS(LngError) / PIDFactor, 22), 1.0). // Max 22 grados
    SET LngCtrlPID:MINOUTPUT TO -LngCtrlPID:MAXOUTPUT.
    
    SET LngCtrl TO -LngCtrlPID:UPDATE(TIME:SECONDS, LngError).
    SET LatCtrl TO -LatCtrlPID:UPDATE(TIME:SECONDS, LatError).
    
    // Calcular vector base de steering con correcciones
    LOCAL BaseSteeringVec IS -SHIP:VELOCITY:SURFACE * ANGLEAXIS(-LngCtrl, LOOKDIRUP(-SHIP:VELOCITY:SURFACE, UP:VECTOR):STARVECTOR) * ANGLEAXIS(LatCtrl, UP:VECTOR).
    LOCAL BaseTopVec IS HEADING(90,0):VECTOR * ANGLEAXIS(2 * LatCtrl, UP:VECTOR).
    
    // MEZCLA CON RETROGRADE: A medida que el error baja de 500m, forzar retrograde
    // Esto reduce el angulo de ataque final y evita oscilaciones de corrección
    LOCAL mixRetro IS MAX(0, MIN(1, 1 - (ABS(LngError)/500))).
    
    // Interpolar vectores: De corrección a Retrograde puro
    LOCAL RetroVec IS -SHIP:VELOCITY:SURFACE:NORMALIZED.
    LOCAL FinalVec IS BaseSteeringVec:NORMALIZED * (1 - mixRetro) + RetroVec * mixRetro.
    
    // Construir dirección final
    SET SteeringVector TO LOOKDIRUP(FinalVec, BaseTopVec).
    
    // Display
    PRINT "Altitud:    " + ROUND(SHIP:ALTITUDE/1000, 1) + " km   " AT (0, 4).
    PRINT "Velocidad:  " + ROUND(SHIP:VELOCITY:SURFACE:MAG, 0) + " m/s   " AT (0, 5).
    PRINT "Dist Impact:" + ROUND(ErrorVector:MAG/1000, 2) + " km   " AT (0, 6).
    PRINT "Lng Error:  " + ROUND(LngError, 0) + " m   " AT (0, 7).
    PRINT "Lat Error:  " + ROUND(LatError, 0) + " m   " AT (0, 8).
    PRINT "Lng Ctrl:   " + ROUND(LngCtrl, 2) + " deg   " AT (0, 9).
    PRINT "Lat Ctrl:   " + ROUND(LatCtrl, 2) + " deg   " AT (0, 10).
    
    WAIT 0.1.
}

PRINT " " AT (0, 12).
PRINT "DESCENSO DINAMICO COMPLETADO" AT (0, 13).

// === LANDING BURN ===
CLEARSCREEN.
PRINT "=== LANDING BURN ===" AT (0, 0).

// Variables de control
SET FASE_LANDING TO 0.  // 0=espera, 1=todos, 2=menos medios, 3=solo centrales, 4=hover
SET PATAS_DESPLEGADAS TO FALSE.
SET HOVER_COMPLETADO TO FALSE.
SET HOVER_START_TIME TO 0.
SET ARMS_SENT TO FALSE.

// Esperar a 2.2km para iniciar
WAIT UNTIL ALT:RADAR < 2600.
PRINT "=== LANDING BURN ===" AT (0, 0).
PRINT " " AT (0, 20). // Limpiar linea de V.Vert anteriors (4-13)
PRINT "IGNICION - CENTRALES + MEDIOS" AT (0, 2).
RCS OFF.
LOCK THROTTLE TO 1.0.
LOCK STEERING TO LOOKDIRUP(SRFRETROGRADE:VECTOR, HEADING(90,0):VECTOR).

FOR i IN RANGE(1, 4) {
    LOCAL motores IS SHIP:PARTSTAGGED(i:TOSTRING).
    FOR eng IN motores { eng:ACTIVATE(). }
}
FOR i IN RANGE(4, 14) {
    LOCAL motores IS SHIP:PARTSTAGGED(i:TOSTRING).
    FOR eng IN motores { eng:ACTIVATE(). }
}
SET FASE_LANDING TO 1.
SET CATCH_COMPLETADO TO FALSE.

// Loop de landing - NO SE SALE POR LANDED (brazos lo detectan como landed)
// Solo se sale al llegar a 106m de altitud o con BREAK explícito
UNTIL CATCH_COMPLETADO OR SHIP:STATUS = "SPLASHED" {
    LogTelemetry("LANDING BURN").

    LOCAL vel IS SHIP:VELOCITY:SURFACE:MAG.
    
    // A 130 m/s: Cambiar a centrales + 7 y 12, iniciar corrección
    IF vel < 130 AND FASE_LANDING = 1 {
        PRINT "FASE 2: CENTRALES + 7 + 12" AT (0, 3).
        // Apagar todos los medios excepto 7 y 12
        FOR i IN RANGE(4, 14) {
            IF i <> 7 AND i <> 12 {
                LOCAL motores IS SHIP:PARTSTAGGED(i:TOSTRING).
                FOR eng IN motores { eng:SHUTDOWN(). }
            }
        }
        SET FASE_LANDING TO 2.
    }
    
    // A 40 m/s: Apagar 7 y 12, solo centrales para aterrizar
    IF vel < 40 AND FASE_LANDING = 2 {
        // === SIMULACION FALLO MOTOR 2 ===
        IF SIMULAR_FALLO_MOTOR {
            PRINT "!! FALLO MOTOR 2 - USANDO MOTOR 7 !!" AT (0, 4).
            LOCAL motor2 IS SHIP:PARTSTAGGED("2").
            FOR eng IN motor2 { eng:SHUTDOWN(). }
            
            LOCAL motores12 IS SHIP:PARTSTAGGED("12").
            FOR eng IN motores12 { eng:SHUTDOWN(). }
            
            LOCAL motor7 IS SHIP:PARTSTAGGED("7").
            FOR eng IN motor7 { 
                IF NOT eng:IGNITION {
                    eng:ACTIVATE().
                }
            }
            PRINT ">> MOTOR 7 ACTIVO (RESPALDO) <<" AT (0, 5).
        } ELSE {
            // Operación normal: apagar 7 y 12
            PRINT "FASE 3: SOLO CENTRALES" AT (0, 4).
            LOCAL motores7 IS SHIP:PARTSTAGGED("7").
            FOR eng IN motores7 { eng:SHUTDOWN(). }
            LOCAL motores12 IS SHIP:PARTSTAGGED("12").
            FOR eng IN motores12 { eng:SHUTDOWN(). }
        }
        SET FASE_LANDING TO 3.
    }
    
    // Desplegar patas a 500m
    IF ALT:RADAR < 500 AND NOT PATAS_DESPLEGADAS {
        AG4 ON.
        SET PATAS_DESPLEGADAS TO TRUE.
        PRINT "PATAS DESPLEGADAS" AT (0, 5).
    }
    
    // === NUEVA LOGICA DE STEERING POR FASES ===
    
    IF FASE_LANDING = 1 {
        // FASE 1: RETROGRADO PURO - Solo frenar
        LOCK STEERING TO LOOKDIRUP(SRFRETROGRADE:VECTOR, HEADING(90,0):VECTOR).
        PRINT "Fase 1: RETROGRADO PURO" AT (0, 6).
    }
    ELSE IF FASE_LANDING = 2 {
        // FASE 2: CORRECCION CON 7 GRADOS MAX
        LOCAL TargetDir IS VXCL(UP:VECTOR, LANDING_TARGET:POSITION - SHIP:POSITION):NORMALIZED.
        LOCAL TargetDist IS VXCL(UP:VECTOR, LANDING_TARGET:POSITION - SHIP:POSITION):MAG.
        LOCAL CurrentHVel IS VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE).
        LOCAL HSpeed IS CurrentHVel:MAG.
        
        // Velocidad deseada hacia el target
        LOCAL MaxCorrVel IS 20.
        LOCAL DesiredVel IS TargetDir * MIN(MaxCorrVel, TargetDist * 0.5).
        LOCAL VelError IS DesiredVel - CurrentHVel.
        
        // Correccion
        LOCAL CorrectionVec IS VelError * 0.8.
        LOCAL RawSteering IS UP:VECTOR + CorrectionVec.
        
        // Limitar a 7 grados
        IF VANG(UP:VECTOR, RawSteering) > 7 {
            LOCAL HorizPart IS VXCL(UP:VECTOR, RawSteering):NORMALIZED.
            SET RawSteering TO UP:VECTOR + HorizPart * TAN(7).
        }
        
        LOCK STEERING TO LOOKDIRUP(RawSteering, HEADING(90,0):VECTOR).
        PRINT "Fase 2: CORRECCION 7deg  Dist:" + ROUND(TargetDist,0) + "m" AT (0, 6).
    }
    ELSE IF FASE_LANDING >= 3 {
        // FASE 3: ATERRIZAJE FINO - Basado en Punto de Impacto
        
        LOCAL TargetDir IS VXCL(UP:VECTOR, LANDING_TARGET:POSITION - SHIP:POSITION):NORMALIZED.
        LOCAL TargetDist IS VXCL(UP:VECTOR, LANDING_TARGET:POSITION - SHIP:POSITION):MAG.
        LOCAL CurrentHVel IS VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE).
        LOCAL HSpeed IS CurrentHVel:MAG.
        
        // Calcular Offset de Impacto (predicción)
        LOCAL ImpactOffset IS TargetDist. 
        IF ADDONS:TR:HASIMPACT {
             LOCAL ImpactPos IS ADDONS:TR:IMPACTPOS:POSITION.
             LOCAL ImpactVec IS VXCL(UP:VECTOR, ImpactPos - LANDING_TARGET:POSITION).
             SET ImpactOffset TO ImpactVec:MAG.
        }
        
        LOCAL DesiredVel IS V(0,0,0).
        
        // LOGICA: "Regular" (eliminar) velocidad horizontal a partir de 10m
        // Si offset > 10m: Corregir hacia el target
        // Si offset <= 10m: Frenar (Velocidad horizontal 0) para estabilidad
        
        IF ImpactOffset > 10 {
             LOCAL corrSpeed IS MAX(1.0, ImpactOffset * 0.1).
             SET corrSpeed TO MIN(corrSpeed, 5.0).
             SET DesiredVel TO TargetDir * corrSpeed.
        } ELSE {
             // Dentro de 10m: Regular a 0 para suavidad total
             SET DesiredVel TO V(0,0,0).
        }
        
        LOCAL VelError IS DesiredVel - CurrentHVel.
        
        // Ganancia MUY SUAVE (0.2)
        LOCAL corrGain IS 0.2.
        IF HSpeed > 10 { SET corrGain TO 0.5. } // Solo si es emergencia
        
        LOCAL CorrectionVec IS VelError * corrGain.
        LOCAL RawSteering IS UP:VECTOR + CorrectionVec.
        
        // Limitar a 3 grados
        IF VANG(UP:VECTOR, RawSteering) > 3 {
            LOCAL HorizPart IS VXCL(UP:VECTOR, RawSteering):NORMALIZED.
            SET RawSteering TO UP:VECTOR + HorizPart * TAN(3).
        }
        
        LOCK STEERING TO LOOKDIRUP(RawSteering, HEADING(90,0):VECTOR).
        PRINT "Fase 3: ImpOff:" + ROUND(ImpactOffset,1) + "m  HSpd:" + ROUND(HSpeed,1) + "   " AT (0, 6).
    }
    
    // Throttle adaptativo para aterrizaje suave y Hover
    IF FASE_LANDING >= 3 {
        // === COMUNICACION TORRE (200m) ===
        IF ALT:RADAR < 200 AND NOT ARMS_SENT {
             // Debug Estado
             PRINT "CHECKING COMMS (Mode: " + TARGET_MODE + ")" AT (0, 14).
             
             // Si no tenemos torre, buscarla de nuevo (ahora estamos cerca)
             IF TOWER_VESSEL = 0 {
                 PRINT "RE-SEARCHING TOWER..." AT (0, 15).
                 LIST TARGETS IN targets.
                 FOR t IN targets {
                     IF t:LOADED {
                         FOR p IN t:PARTS {
                             IF p:NAME:CONTAINS("Titans") OR p:TITLE:CONTAINS("Kanaloa") OR p:TITLE:CONTAINS("CompoMax") {
                                 SET TOWER_VESSEL TO t.
                                 PRINT "TOWER FOUND: " + t:NAME AT (0, 15).
                                 BREAK.
                             }
                         }
                     }
                     IF TOWER_VESSEL <> 0 { BREAK. }
                 }
             }

             IF TARGET_MODE = "TOWER" {
                 IF TOWER_VESSEL <> 0 {
                     IF TOWER_VESSEL:CONNECTION:ISCONNECTED {
                         TOWER_VESSEL:CONNECTION:SENDMESSAGE("CloseArms").
                         PRINT ">>> SIGNAL SENT: CATCH (150m) <<<" AT (0, 14).
                         SET ARMS_SENT TO TRUE.
                     } ELSE {
                         PRINT "ERROR: NO CONNECTION TO TOWER" AT (0, 16).
                     }
                 } ELSE {
                     PRINT "WARNING: NO TOWER VESSEL FOUND" AT (0, 14).
                 }
             } ELSE {
                 PRINT "MSG ABORT: MODE IS " + TARGET_MODE AT (0, 14).
                 // Marcar como enviado para no spammear, aunque no se envio
                 SET ARMS_SENT TO TRUE. 
             }
        }

        // === PERFIL DE VELOCIDAD PARA SIMULAR CATCH (SUPER HEAVY STYLE) ===
        // Objetivo: Llegar a 70m (altura brazos) con velocidad casi cero
        LOCAL catchAlt IS 70. 
        LOCAL targetVS IS -2.

        IF ALT:RADAR > 1000 {
            // Descenso rápido inicial
            SET targetVS TO -MAX(30, (ALT:RADAR - 1000) * 0.1). 
        } ELSE IF ALT:RADAR > 200 {
             // Frenado de 30 m/s a 15 m/s (más rápido)
             LOCAL factor IS (ALT:RADAR - 200) / 800.
             SET targetVS TO -(15 + factor * 15).
        } ELSE IF ALT:RADAR > 80 {
             // Aproximación final: de 15 m/s a 3 m/s (más progresivo)
             // Transición suave para no desviarse del target
             LOCAL factor IS (ALT:RADAR - 80) / 120.
             SET targetVS TO -(3 + factor * 12). 
        } ELSE {
             // ZONA DE CATCH (< 80m)
             // Mantener descenso LENTISIMO (0.5 m/s)
             SET targetVS TO -0.5.
        }
        
        // === LÓGICA DE CATCH ===
        // A 135m: descenso a -3.5 m/s con corrección (4 grados max)
        IF ALT:RADAR < 135 {
            SET FASE_LANDING TO 4.
            PRINT ">>> CATCH MODE (-3.5 m/s) <<<" AT (0, 12).
            
            // Corrección suave hacia el target + offset de 2m
            LOCAL ApproachDir IS VXCL(UP:VECTOR, LANDING_TARGET:POSITION - SHIP:POSITION):NORMALIZED.
            LOCAL OffsetTarget IS LANDING_TARGET:POSITION + ApproachDir * 2. 
            LOCAL TargetDir IS VXCL(UP:VECTOR, OffsetTarget - SHIP:POSITION):NORMALIZED.
            LOCAL TargetDist IS VXCL(UP:VECTOR, OffsetTarget - SHIP:POSITION):MAG.
            LOCAL CurrentHVel IS VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE).
            LOCAL HSpeed IS CurrentHVel:MAG.
            
            // Velocidad deseada hacia el target
            LOCAL DesiredVel IS V(0,0,0).
            IF TargetDist > 1 {
                LOCAL maxSpeed IS MIN(3.0, TargetDist * 0.15).
                SET DesiredVel TO TargetDir * maxSpeed.
            }
            
            LOCAL VelError IS DesiredVel - CurrentHVel.
            LOCAL corrGain IS 0.5.
            IF HSpeed > 1.0 { SET corrGain TO 0.7. } 
            LOCAL CorrectionVec IS VelError * corrGain.
            LOCAL RawSteering IS UP:VECTOR + CorrectionVec.
            
            // Limitar a 4 grados MAX (antes 2)
            IF VANG(UP:VECTOR, RawSteering) > 4 {
                LOCAL HorizPart IS VXCL(UP:VECTOR, RawSteering):NORMALIZED.
                SET RawSteering TO UP:VECTOR + HorizPart * TAN(4).
            }
            
            LOCK STEERING TO LOOKDIRUP(RawSteering, HEADING(90,0):VECTOR).
            
            // Objetivo: descender a -3.5 m/s constante
            SET targetVS TO -3.5.
            
            // Mostrar info
            PRINT "Alt: " + ROUND(ALT:RADAR, 0) + "m  Dist:" + ROUND(TargetDist, 1) + "m  VS:" + ROUND(SHIP:VERTICALSPEED, 1) + "   " AT (0, 13).
            
            // A 106m sobre el terreno (ALT:RADAR): APAGAR MOTORES (CATCH)
            IF ALT:RADAR <= 106 {
                PRINT "!!! CATCH A 106m - MOTORES OFF !!!" AT (0, 14).
                LOCK THROTTLE TO 0.
                FOR eng IN SHIP:ENGINES { eng:SHUTDOWN(). }
                SET CATCH_COMPLETADO TO TRUE.
                BREAK. // Salir del loop
            }
        }

        // Calculo de TWR dinámico
        LOCAL GRAV IS BODY:MU / (SHIP:BODY:POSITION:MAG ^ 2).
        LOCAL TWR IS SHIP:AVAILABLETHRUST / (SHIP:MASS * GRAV).
        LOCAL HoverThrot IS 1 / MAX(0.1, TWR).

        LOCAL vsError IS targetVS - SHIP:VERTICALSPEED.
        
        // PID Vertical agresivo
        LOCAL kP IS 0.2.
        // Si subimos, cortar gas INMEDIATAMENTE
        IF SHIP:VERTICALSPEED > 0.5 { SET kP TO 0.8. }
        // Si bajamos muy rápido cerca del suelo, meter gas fuerte
        IF ALT:RADAR < 100 AND SHIP:VERTICALSPEED < targetVS - 2 { SET kP TO 0.4. }

        SET throttleAdj TO HoverThrot + (vsError * kP).
        LOCK THROTTLE TO MAX(0.01, MIN(1.0, throttleAdj)).
    }
    
    // Display
    PRINT "Altitud:   " + ROUND(ALT:RADAR, 0) + " m     " AT (0, 7).
    PRINT "Velocidad: " + ROUND(vel, 1) + " m/s   " AT (0, 8).
    PRINT "V.Vert:    " + ROUND(SHIP:VERTICALSPEED, 1) + " m/s   " AT (0, 9).
    PRINT "Dist Tgt:  " + ROUND(VXCL(UP:VECTOR, LANDING_TARGET:POSITION - SHIP:POSITION):MAG, 0) + " m   " AT (0, 10).
    
    // Escribir altura a JSON para el catch de la torre
    EscribirAltura(ALT:RADAR).
    
    IF FASE_LANDING = 1 { PRINT "Fase: RETROGRADO       " AT (0, 11). }
    ELSE IF FASE_LANDING = 2 { PRINT "Fase: CORRECCION 7deg  " AT (0, 11). }
    ELSE IF FASE_LANDING = 3 { PRINT "Fase: ATERRIZAJE       " AT (0, 11). }
    
    WAIT 0.05.
}

// === ATERRIZAJE COMPLETADO ===
LOCK THROTTLE TO 0.
UNLOCK STEERING.
// SAS OFF - No activar SAS automáticamente
PRINT " " AT (0, 13).
PRINT "=== AMERIZAJE COMPLETADO ===" AT (0, 14).

WAIT 2.
FOR i IN RANGE(1, 4) {
    LOCAL motores IS SHIP:PARTSTAGGED(i:TOSTRING).
    FOR eng IN motores { eng:SHUTDOWN(). }
}
PRINT "Motores apagados. Fin del programa." AT (0, 15).
