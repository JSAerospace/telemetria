// --- JS AEROSPACE: SPACE SHUTTLE TELEMETRY ---
// Archivo: 0:/boot/shuttle.ks
// Etiquetar motores: "MAIN" (central), "OMS1" (lateral 1), "OMS2" (lateral 2)

CLEARSCREEN.
PRINT "╔══════════════════════════════════════════════╗".
PRINT "║   JS AEROSPACE - SHUTTLE FLIGHT SOFTWARE     ║".
PRINT "╚══════════════════════════════════════════════╝".

LOCAL fileA TO "0:/telemetry_shuttle_A.json".
LOCAL fileB TO "0:/telemetry_shuttle_B.json".
LOCAL useA TO TRUE.
LOCAL lastLog IS -1.

// Funciones de recursos
FUNCTION GetFuelPercent {
    LOCAL totalCap IS 0.001. LOCAL totalCur IS 0.
    FOR res IN SHIP:RESOURCES {
        IF res:NAME = "LiquidFuel" {
            SET totalCap TO totalCap + res:CAPACITY.
            SET totalCur TO totalCur + res:AMOUNT.
        }
    }
    RETURN (totalCur / totalCap) * 100.
}

FUNCTION GetMonoPercent {
    LOCAL totalCap IS 0.001. LOCAL totalCur IS 0.
    FOR res IN SHIP:RESOURCES {
        IF res:NAME = "Monopropellant" {
            SET totalCap TO totalCap + res:CAPACITY.
            SET totalCur TO totalCur + res:AMOUNT.
        }
    }
    RETURN (totalCur / totalCap) * 100.
}

// Bucle principal de telemetría
UNTIL FALSE {
    IF TIME:SECONDS > lastLog + 0.5 {
        LOCAL tFile TO fileB. IF useA { SET tFile TO fileA. }
        SET useA TO NOT useA.
        
        // --- ESTADO DE MOTORES ---
        LOCAL engDict IS LEX("MAIN", 0, "OMS1", 0, "OMS2", 0).
        LIST ENGINES IN engList.
        FOR e IN engList {
            LOCAL t IS e:TAG:TOUPPER:TRIM.
            LOCAL key IS "".
            IF t:CONTAINS("MAIN") { SET key TO "MAIN". }
            ELSE IF t:CONTAINS("OMS1") OR t:CONTAINS("OMS 1") { SET key TO "OMS1". }
            ELSE IF t:CONTAINS("OMS2") OR t:CONTAINS("OMS 2") { SET key TO "OMS2". }
            
            IF key <> "" {
                LOCAL is_on IS 0.
                IF e:IGNITION AND (e:THRUST / MAX(0.01, e:POSSIBLETHRUST) >= 0.01) { SET is_on TO 1. }
                IF is_on = 1 { SET engDict[key] TO 1. }
            }
        }
        
        // --- ESTADO DE FASE DE VUELO ---
        LOCAL statusStr IS "ORBIT".
        IF ALT:RADAR < 100 AND SHIP:STATUS = "LANDED" { SET statusStr TO "LANDED". }
        ELSE IF SHIP:ALTITUDE < 70000 AND SHIP:VERTICALSPEED < -100 { SET statusStr TO "REENTRY". }
        ELSE IF ALT:RADAR < 15000 AND SHIP:VERTICALSPEED < -10 { SET statusStr TO "GLIDE APPROACH". }
        ELSE IF SHIP:STATUS = "PRELAUNCH" { SET statusStr TO "PRELAUNCH". }
        ELSE IF SHIP:VERTICALSPEED > 100 { SET statusStr TO "ASCENT". }
        
        // --- AERODINÁMICA ---
        LOCAL aoa IS VANG(SHIP:FACING:VECTOR, SHIP:VELOCITY:SURFACE).
        IF SHIP:VELOCITY:SURFACE:MAG < 5 { SET aoa TO 0. } // Evitar "ruido" en tierra
        
        LOCAL pitch IS 90 - VANG(UP:VECTOR, SHIP:FACING:VECTOR).
        LOCAL northPole IS LATLNG(90, 0).
        LOCAL heading_val IS MOD(360 - northPole:BEARING, 360).
        LOCAL roll IS VANG(UP:VECTOR, SHIP:FACING:STARVECTOR) - 90.

        // Compilar datos
        LOCAL data IS LEX(
            "time", ROUND(TIME:SECONDS, 1),
            "alt", ROUND(SHIP:ALTITUDE),
            "alt_radar", ROUND(ALT:RADAR),
            "vel", ROUND(SHIP:AIRSPEED),
            "mach", ROUND(SHIP:AIRSPEED / 340.29, 2),
            "vs", ROUND(SHIP:VERTICALSPEED, 1),
            "pitch", ROUND(pitch, 1),
            "heading", ROUND(heading_val, 1),
            "roll", ROUND(roll, 1),
            "aoa", ROUND(aoa, 1),
            "q", ROUND(SHIP:Q * 100, 1),
            "fuelpct", ROUND(GetFuelPercent(), 1),
            "monopct", ROUND(GetMonoPercent(), 1),
            "gear", GEAR,
            "brakes", BRAKES,
            "rcs", RCS,
            "throttle", ROUND(THROTTLE * 100, 1),
            "engstates", engDict,
            "status", statusStr
        ).
        
        IF HOMECONNECTION:ISCONNECTED {
             WRITEJSON(data, tFile).
        }
        SET lastLog TO TIME:SECONDS.
        
        PRINT " Telemetry Active | Alt: " + ROUND(SHIP:ALTITUDE) + "m | AoA: " + ROUND(aoa,1) + "deg | Status: " + statusStr + "    " AT (0, 5).
        PRINT " Engines Debug: MAIN=" + engDict["MAIN"] + " OMS1=" + engDict["OMS1"] + " OMS2=" + engDict["OMS2"] + "      " AT (0, 6).
    }
    WAIT 0.1. // 10 ticks por segundo, transmisión a 2Hz
}
