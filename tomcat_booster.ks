// --- JS AEROSPACE: TOMCAT BOOSTER SOFTWARE (v4.7) ---
// Basado en la tecnología de boosterBLOCK2.ks y TomcatHeavy
// Especializado en aterrizaje propulsivo en barcaza (JShip)

// ============================================================
// === CONFIGURACIÓN DE FISICA (RSS) ===
// ============================================================
FUNCTION SetPhysicsRange {
    PARAMETER d.
    SET SHIP:LOADDISTANCE:FLYING:UNLOAD TO d. SET SHIP:LOADDISTANCE:FLYING:LOAD TO d*0.95.
    WAIT 0.001. SET SHIP:LOADDISTANCE:FLYING:PACK TO d*0.98. SET SHIP:LOADDISTANCE:FLYING:UNPACK TO d*0.94.
    WAIT 0.01.
    SET SHIP:LOADDISTANCE:SUBORBITAL:UNLOAD TO d. SET SHIP:LOADDISTANCE:SUBORBITAL:LOAD TO d*0.95.
    WAIT 0.001. SET SHIP:LOADDISTANCE:SUBORBITAL:PACK TO d*0.98. SET SHIP:LOADDISTANCE:SUBORBITAL:UNPACK TO d*0.94.
    SET KUNIVERSE:DEFAULTLOADDISTANCE:FLYING:UNLOAD TO d.
}
SetPhysicsRange(2500000).

// ============================================================
// === VARIABLES GLOBALES ===
// ============================================================
GLOBAL LAUNCH_PAD TO SHIP:GEOPOSITION.
GLOBAL MISSION_STATE IS LEXICON("phase", "PRELAUNCH", "target_lat", 0, "target_lng", 0, "apo", 200000, "head", 90).
LOCAL STATE_FILE IS "0:/mission_state.json".
LOCAL startT IS 0.

FUNCTION SaveMissionState {
    PARAMETER newPhase.
    SET MISSION_STATE["phase"] TO newPhase.
    WRITEJSON(MISSION_STATE, STATE_FILE).
}

// Si estamos en la plataforma, resetear siempre el estado para mostrar el menú
IF SHIP:STATUS = "PRELAUNCH" OR SHIP:STATUS = "LANDED" {
    IF EXISTS(STATE_FILE) { DELETEPATH(STATE_FILE). }
    SET MISSION_STATE["phase"] TO "PRELAUNCH".
}

// Cargar estado guardado si existe
IF EXISTS(STATE_FILE) {
    SET MISSION_STATE TO READJSON(STATE_FILE).
}

SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.

// ============================================================
// === FUNCIONES ===
// ============================================================
FUNCTION GetBoosterFuelPct {
    LOCAL tanques IS SHIP:PARTSTAGGED("BOOSTER").
    IF tanques:LENGTH = 0 {
        // Fallback: usar todo el combustible de la nave
        LOCAL totalFuel IS 0. LOCAL totalCap IS 0.
        FOR p IN SHIP:PARTS {
            FOR r IN p:RESOURCES {
                IF r:NAME = "LiquidFuel" OR r:NAME = "Kerosene" {
                    SET totalFuel TO totalFuel + r:AMOUNT.
                    SET totalCap TO totalCap + r:CAPACITY.
                }
            }
        }
        IF totalCap = 0 { RETURN 100. }
        RETURN (totalFuel / totalCap) * 100.
    }
    LOCAL fuel IS 0. LOCAL cap IS 0.
    FOR p IN tanques {
        FOR r IN p:RESOURCES { SET fuel TO fuel + r:AMOUNT. SET cap TO cap + r:CAPACITY. }
    }
    IF cap = 0 { RETURN 0. }
    RETURN (fuel / cap) * 100.
}

FUNCTION GetBargeTarget {
    LIST TARGETS IN allT.
    FOR t IN allT {
        IF t:NAME:TOUPPER:CONTAINS("JSHIP") { RETURN t. }
    }
    RETURN 0.
}

// ============================================================
// === MENÚ DE LANZAMIENTO ===
// ============================================================
IF MISSION_STATE["phase"] = "PRELAUNCH" {
    LOCAL launchReady IS FALSE.
    LOCAL myGui IS GUI(260).
    myGui:ADDLABEL("<b>TOMCAT BOOSTER v4.7</b>").
    myGui:ADDLABEL("Apoapsis (km):").
    LOCAL apoField IS myGui:ADDTEXTFIELD("200").
    myGui:ADDLABEL("Rumbo (Head):").
    LOCAL headField IS myGui:ADDTEXTFIELD("90").
    LOCAL launchBtn IS myGui:ADDBUTTON(">>> LANZAR <<<").

    SET launchBtn:ONCLICK TO { SET launchReady TO TRUE. }.
    myGui:SHOW().
    WAIT UNTIL launchReady.

    SET MISSION_STATE["apo"] TO apoField:TEXT:TONUMBER(200) * 1000.
    SET MISSION_STATE["head"] TO headField:TEXT:TONUMBER(90).
    myGui:HIDE(). myGui:DISPOSE().

    WRITEJSON(LEXICON("apo", MISSION_STATE["apo"], "head", MISSION_STATE["head"]), "0:/tomcat_config.json").

    FROM { LOCAL t IS 5. } UNTIL t = 0 STEP { SET t TO t - 1. } DO {
        HUDTEXT("T-" + t, 1, 2, 40, YELLOW, FALSE).
        IF t = 2 {
            LOCK THROTTLE TO 1.0.
            LOCK STEERING TO HEADING(MISSION_STATE["head"], 90).
            FOR i IN RANGE(1, 8) { FOR eng IN SHIP:PARTSTAGGED(i:TOSTRING) { eng:ACTIVATE(). } }
            AG9 ON.
        }
        WAIT 1.
    }
    SET startT TO TIME:SECONDS.
    SaveMissionState("ASCENT").
}

// ============================================================
// === ASCENSO ===
// ============================================================
IF MISSION_STATE["phase"] = "ASCENT" {
    IF startT = 0 { SET startT TO TIME:SECONDS. }
    LOCK STEERING TO HEADING(MISSION_STATE["head"], MAX(15, 90 - (ALTITUDE / 750))).
    LOCK THROTTLE TO 1.0.

    LOCAL MECO_DONE IS FALSE.
    UNTIL MECO_DONE {
        LOCAL fuelPct IS GetBoosterFuelPct().
        LOCAL elapsed IS TIME:SECONDS - startT.

        // Verificar flameout (sin combustible)
        LOCAL allOut IS TRUE.
        FOR eng IN SHIP:ENGINES {
            IF eng:IGNITION AND NOT eng:FLAMEOUT { SET allOut TO FALSE. }
        }

        PRINT "ASCENSO | Fuel BOOSTER: " + ROUND(fuelPct, 1) + "%  Apo: " + ROUND(SHIP:APOAPSIS/1000) + "km   " AT (0, 20).

        IF elapsed > 15 {
            IF fuelPct <= 20 OR SHIP:APOAPSIS >= MISSION_STATE["apo"] OR allOut {
                HUDTEXT("MECO - SEPARACION", 5, 2, 30, YELLOW, FALSE).
                LOCK THROTTLE TO 0.

                // Apagar motores por tags (1 al 7 = todos los motores del booster)
                FOR i IN RANGE(1, 8) { FOR eng IN SHIP:PARTSTAGGED(i:TOSTRING) { eng:SHUTDOWN(). } }

                WAIT 1.0.

                // Buscar barcaza y guardar coordenadas
                LOCAL b IS GetBargeTarget().
                IF b <> 0 {
                    SET MISSION_STATE["target_lat"] TO b:GEOPOSITION:LAT.
                    SET MISSION_STATE["target_lng"] TO b:GEOPOSITION:LNG.
                    HUDTEXT("JShip encontrada: " + ROUND(b:GEOPOSITION:LAT,2) + ", " + ROUND(b:GEOPOSITION:LNG,2), 5, 2, 25, GREEN, FALSE).
                } ELSE {
                    // Fallback: punto en el mar en la dirección del lanzamiento
                    LOCAL fallbackPos IS BODY:GEOPOSITIONOF(LAUNCH_PAD:POSITION + HEADING(MISSION_STATE["head"], 0):VECTOR * 45000).
                    SET MISSION_STATE["target_lat"] TO fallbackPos:LAT.
                    SET MISSION_STATE["target_lng"] TO fallbackPos:LNG.
                    HUDTEXT("JShip NO encontrada - usando fallback", 5, 2, 25, RED, FALSE).
                }

                AG7 ON. // Separación
                WAIT 2.0.
                RCS ON. AG2 ON.

                // Ir directo a descenso aerodinámico (sin boostback)
                LOCAL tgtGeo IS LATLNG(MISSION_STATE["target_lat"], MISSION_STATE["target_lng"]).
                IF ADDONS:TR:AVAILABLE { ADDONS:TR:SETTARGET(tgtGeo). }
                SaveMissionState("DESCENT").
                SET MECO_DONE TO TRUE.
            }
        }
        WAIT 0.1.
    }
}

// (Boostback eliminado - el descenso es 100% aerodinámico)

// ============================================================
// === DESCENSO - Guiado hacia objetivo (máx 45°) ===
// ============================================================
IF MISSION_STATE["phase"] = "DESCENT" {
    LOCAL targetGeo IS LATLNG(MISSION_STATE["target_lat"], MISSION_STATE["target_lng"]).
    LOCAL gearDone IS FALSE.

    UNTIL SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED" OR MISSION_STATE["phase"] = "LANDING" {
        LOCAL approachDir IS VXCL(UP:VECTOR, targetGeo:POSITION - SHIP:POSITION):NORMALIZED.
        LOCAL approachUpVec IS (targetGeo:POSITION - BODY:POSITION):NORMALIZED.
        LOCAL sideDir IS VCRS(approachDir, UP:VECTOR):NORMALIZED.

        LOCAL lngError IS 0.
        LOCAL latError IS 0.

        IF ADDONS:TR:AVAILABLE AND ADDONS:TR:HASIMPACT {
            LOCAL errorVec IS ADDONS:TR:IMPACTPOS:POSITION - targetGeo:POSITION.
            SET lngError TO VDOT(approachDir, errorVec).
            SET latError TO VDOT(ANGLEAXIS(-90, approachUpVec) * approachDir, errorVec).
            PRINT "DESCENSO(TR) LngErr:" + ROUND(lngError) + "m  LatErr:" + ROUND(latError) + "m   " AT (0, 20).
        } ELSE {
            LOCAL posErr IS VXCL(UP:VECTOR, targetGeo:POSITION - SHIP:POSITION).
            SET lngError TO -posErr:MAG.
            PRINT "DESCENSO(Dir) Dist:" + ROUND(posErr:MAG/1000,1) + "km  Alt:" + ROUND(ALT:RADAR) + "m   " AT (0, 20).
        }

        LOCAL lngAngle IS MAX(-45, MIN(45, -lngError / 300)).
        LOCAL latAngle IS MAX(-15, MIN(15, -latError / 300)).

        LOCAL retroVec IS SRFRETROGRADE:VECTOR.
        LOCAL correctedVec IS retroVec + approachDir * TAN(lngAngle) + sideDir * TAN(latAngle).
        LOCK STEERING TO LOOKDIRUP(correctedVec:NORMALIZED, SHIP:NORTH:VECTOR).

        IF ALT:RADAR < 2500 {
            HUDTEXT("LANDING BURN!", 5, 2, 30, GREEN, FALSE).
            LOCK THROTTLE TO 1.0.
            FOR tag IN LIST("1", "2", "5") { FOR eng IN SHIP:PARTSTAGGED(tag) { eng:ACTIVATE(). } }
            SaveMissionState("LANDING").
        }

        WAIT 0.05.
    }
}

// ============================================================
// === LANDING BURN ===
// ============================================================
IF MISSION_STATE["phase"] = "LANDING" {
    LOCAL targetGeo IS LATLNG(MISSION_STATE["target_lat"], MISSION_STATE["target_lng"]).
    LOCAL gearDone IS FALSE.
    LOCAL enginesCut IS FALSE.
    LOCAL vsPID IS PIDLOOP(0.6, 0.2, 0.1, 0, 1).

    // Asegurar que los motores de landing están encendidos
    FOR tag IN LIST("1", "2", "5") { FOR eng IN SHIP:PARTSTAGGED(tag) { eng:ACTIVATE(). } }

    UNTIL SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED" {
        IF NOT gearDone AND ALT:RADAR < 600 {
            SET gearDone TO TRUE.
            AG4 ON. GEAR ON.
        }

        // Transición a 1 motor a 100m (v4.7: antes era 35m)
        IF NOT enginesCut AND ALT:RADAR < 100 {
            SET enginesCut TO TRUE.
            FOR tag IN LIST("2", "5") { FOR eng IN SHIP:PARTSTAGGED(tag) { eng:SHUTDOWN(). } }
        }

        // Velocidad objetivo: -6m/s hasta 15m, luego -2m/s (v4.7: descenso más rápido)
        LOCAL targetVS IS -6.
        IF ALT:RADAR < 15 { SET targetVS TO -2.0. }

        // Corte de seguridad a 40m si el cohete empieza a ascender (v4.7)
        IF SHIP:VERTICALSPEED > 0.5 AND ALT:RADAR < 40 {
            HUDTEXT("CORTE DE SEGURIDAD - VS POSITIVO", 5, 2, 30, RED, FALSE).
            LOCK THROTTLE TO 0.
            FOR eng IN SHIP:ENGINES { eng:SHUTDOWN(). }
            BREAK.
        }

        IF SHIP:VERTICALSPEED > -0.5 AND ALT:RADAR < 5 {
            LOCK THROTTLE TO 0. FOR eng IN SHIP:ENGINES { eng:SHUTDOWN(). }
            BREAK.
        }

        SET vsPID:SETPOINT TO targetVS.
        LOCAL thr IS vsPID:UPDATE(TIME:SECONDS, SHIP:VERTICALSPEED).
        LOCAL gComp IS (SHIP:MASS * 9.81) / MAX(1, SHIP:AVAILABLETHRUST).
        LOCK THROTTLE TO MAX(0.01, MIN(1, gComp + thr)).

        LOCAL distError IS VXCL(UP:VECTOR, targetGeo:POSITION - SHIP:POSITION).
        LOCAL velError IS VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE).
        LOCAL steerShift IS (distError * 0.01) - (velError * 0.04).
        IF steerShift:MAG > TAN(10) { SET steerShift TO steerShift:NORMALIZED * TAN(10). }
        LOCK STEERING TO LOOKDIRUP(UP:VECTOR + steerShift, SHIP:NORTH:VECTOR).

        PRINT "LANDING | VS:" + ROUND(SHIP:VERTICALSPEED,1) + "m/s  Alt:" + ROUND(ALT:RADAR) + "m   " AT (0, 20).
        WAIT 0.05.
    }
}

// ============================================================
// === FIN ===
// ============================================================
LOCK THROTTLE TO 0.
FOR eng IN SHIP:ENGINES { eng:SHUTDOWN(). }
UNLOCK STEERING.
IF EXISTS(STATE_FILE) { DELETEPATH(STATE_FILE). }
HUDTEXT("MISION COMPLETADA", 10, 2, 40, GREEN, TRUE).
