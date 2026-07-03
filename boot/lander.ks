// --- SISTEMA DE TELEMETRÍA: ALUNIZADOR (LANDER) ---
// Versión: 1.1 (Doble-Buffer A/B para evitar Sharing Violation)

GLOBAL fileLA TO "0:/telemetry_lander_A.json".
GLOBAL fileLB TO "0:/telemetry_lander_B.json".
GLOBAL useLA IS TRUE.
GLOBAL lastLog IS -1.

// --- CONFIGURACIÓN DE PITCH Y ORIENTACIÓN ---
SET STEERINGMANAGER:MAXSTOPPINGTIME TO 5.
SET STEERINGMANAGER:PITCHPID:KP TO 1.5.
SET STEERINGMANAGER:PITCHPID:KD TO 2.0.

CLEARSCREEN.
PRINT "╔═════════════════════════════════════╗".
PRINT "║      JS AEROSPACE - MUNAR LANDER    ║".
PRINT "╚═════════════════════════════════════╝".

FUNCTION GetFuelPct {
    // Escanea TODOS los tanques del lander (LiquidFuel + Oxidizer)
    LOCAL totalCap IS 0.0001.
    LOCAL totalCur IS 0.
    FOR p IN SHIP:PARTS {
        FOR res IN p:RESOURCES {
            IF res:NAME = "LiquidFuel" OR res:NAME = "Oxidizer" {
                SET totalCap TO totalCap + res:CAPACITY.
                SET totalCur TO totalCur + res:AMOUNT.
            }
        }
    }
    RETURN ROUND((totalCur / totalCap) * 100).
}

FUNCTION GetMonoPct {
    // Porcentaje de Monopropelente
    LOCAL totalCap IS 0.0001.
    LOCAL totalCur IS 0.
    FOR p IN SHIP:PARTS {
        FOR res IN p:RESOURCES {
            IF res:NAME = "MonoPropellant" {
                SET totalCap TO totalCap + res:CAPACITY.
                SET totalCur TO totalCur + res:AMOUNT.
            }
        }
    }
    RETURN ROUND((totalCur / totalCap) * 100).
}

FUNCTION GetLanderTilt {
    // Inclinación del lander respecto a la vertical local
    // 0 = perfectamente vertical, >0 = inclinado
    RETURN ROUND(VANG(SHIP:FACING:VECTOR, SHIP:UP:VECTOR), 1).
}

FUNCTION LogTelemetry {
    IF TIME:SECONDS > lastLog + 0.1 {
        // Seleccionar buffer alterno (evita Sharing Violation con cloud_sync.py)
        LOCAL tFile IS fileLB.
        IF useLA { SET tFile TO fileLA. }
        SET useLA TO NOT useLA.

        // Capturar TODOS los motores (con o sin TAG)
        LOCAL engDict IS LEX().
        LOCAL engIdx IS 0.
        LIST ENGINES IN eList.
        FOR e IN eList {
            LOCAL t IS e:TAG:TOUPPER:TRIM.
            IF t:LENGTH = 0 { SET t TO "ENG" + engIdx. }
            LOCAL is_on IS 0.
            IF e:IGNITION AND NOT e:FLAMEOUT { SET is_on TO 1. }
            SET engDict[t] TO is_on.
            SET engIdx TO engIdx + 1.
        }

        // Safe G-Force Check (evita crash si no hay parte de acelerómetro)
        LOCAL gVal IS 0.
        LIST SENSORS IN S_LIST.
        FOR S IN S_LIST { IF S:TYPE = "ACC" AND S:ACTIVE { SET gVal TO ROUND(S:MAG / 9.80665, 2). } }

        LOCAL data IS LEX(
            "time", ROUND(TIME:SECONDS, 1),
            "alt", ROUND(SHIP:ALTITUDE),
            "alt_radar", ROUND(ALT:RADAR, 1),
            "vs", ROUND(SHIP:VERTICALSPEED, 2),
            "vel", ROUND(SHIP:GROUNDSPEED, 1),
            "apo", ROUND(SHIP:APOAPSIS),
            "per", ROUND(SHIP:PERIAPSIS),
            "twr", ROUND(SHIP:AVAILABLETHRUST / MAX(0.1, SHIP:MASS * (SHIP:BODY:MU / SHIP:BODY:RADIUS^2)), 2),
            "g", gVal,
            "fuelpct", GetFuelPct(),
            "monopct", GetMonoPct(),
            "throttle", ROUND(THROTTLE * 100, 1),
            "tilt", GetLanderTilt(),
            "engstates", engDict,
            "status", SHIP:STATUS
        ).

        WRITEJSON(data, tFile).
        SET lastLog TO TIME:SECONDS.
    }
}

// --- BUCLE PRINCIPAL ---
UNTIL SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED" {
    LogTelemetry().
    
    // UI Local
    PRINT "ALT RADAR: " + ROUND(ALT:RADAR, 1) + " m    " AT (0, 5).
    PRINT "V. SPEED:  " + ROUND(SHIP:VERTICALSPEED, 2) + " m/s    " AT (0, 6).
    PRINT "TILT:      " + GetLanderTilt() + " deg    " AT (0, 7).
    PRINT "FUEL:      " + GetFuelPct() + "%    " AT (0, 8).
    
    WAIT 0.1.
}

PRINT "¡ATERRIZAJE CONFIRMADO!".

// Seguir enviando telemetría post-aterrizaje (para que el dashboard no quede en blanco)
UNTIL FALSE {
    LogTelemetry().
    PRINT "LANDED - AltRadar: " + ROUND(ALT:RADAR, 1) + " m    " AT (0, 5).
    WAIT 1.
}
