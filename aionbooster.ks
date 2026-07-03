// TOMCAT_BOOSTER Boot Script (AIONBOOSTER Engine - 9-Engine Cluster Edition)
// Este script opera con una sola pieza de motor cluster (9 motores) controlado por AG3.

clearscreen.
print "==============================".
print " TOMCAT BOOSTER INITIALIZING  ".
print "==============================".

// Inicializar archivos de telemetría para evitar datos obsoletos
writejson(lexicon("status", "PRELAUNCH"), "0:/telemetry_booster_A.json").
writejson(lexicon("status", "PRELAUNCH"), "0:/telemetry_booster_B.json").

// Estado global de los motores del cluster
global engine_mode is 9. // 9 = Todos los motores, 3 = Modo 3 motores, 1 = Modo 1 motor
global booster_engines is list().
global venting_active is false.

function start_drain {
    // AG8 abre las válvulas DRAIN (asignadas en el VAB)
    ag8 on.
    wait 0.1.
    ag8 off.
    set venting_active to true.
    HUDTEXT("DRENADO INICIADO (AG8)", 4, 2, 18, yellow, false).
}

function stop_drain {
    // AG9 cierra las válvulas DRAIN (asignadas en el VAB)
    ag9 on.
    wait 0.1.
    ag9 off.
    set venting_active to false.
    HUDTEXT("DRENADO DETENIDO (AG9)", 4, 2, 18, green, false).
}

function check_fuel_venting {
    if venting_active {
        if get_booster_fuel_pct() <= 17 {
            stop_drain().
            HUDTEXT("VENTEO COMPLETADO AL 17% - DRAIN CERRADO", 5, 2, 18, green, false).
        }
    }
}

// Inicializar motores exclusivos del booster
function init_booster_engines {
    set booster_engines to list().
    list engines in all_engs.
    for eng in all_engs {
        if eng:tag = "BOOSTER_ENGINE" {
            booster_engines:add(eng).
        }
    }
    if booster_engines:length = 0 {
        // Fallback: si no hay tag BOOSTER_ENGINE, usar motores de la etapa de lanzamiento
        print "WARNING: No se encontro tag 'BOOSTER_ENGINE'. Usando fallback por etapa.".
        for eng in all_engs {
            if eng:stage = ship:stage {
                booster_engines:add(eng).
            }
        }
    }
    print "Motores del Booster registrados: " + booster_engines:length.
}
// Función robusta para encontrar la barcaza de aterrizaje
function find_barge {
    if hastarget {
        if target:name:toupper:contains("JSHIP") {
            return target.
        }
    }
    list targets in all_targets.
    for t in all_targets {
        if t:name:toupper:contains("JSHIP") {
            return t.
        }
    }
    return 0.
}
init_booster_engines().

print "==============================".
print " TOMCAT BOOSTER LISTO         ".
print "==============================".

// --- FUNCIONES DE TELEMETRIA ---
function get_booster_fuel_pct {
    local current_fuel is 0.
    local total_cap is 0.
    
    for p in ship:partstagged("BOOSTER") {
        for res in p:resources {
            set current_fuel to current_fuel + res:amount.
            set total_cap to total_cap + res:capacity.
        }
    }
    
    local pct is 0.
    if total_cap > 0 { 
        set pct to (current_fuel / total_cap) * 100. 
    }
    return pct.
}

function get_booster_dv {
    // Calcular deltaV restante del booster
    local fuel_mass is 0.
    
    for res in ship:resources {
        if res:name = "LiquidFuel" or res:name = "Oxidizer" {
            set fuel_mass to fuel_mass + res:amount * 0.005. // Densidad KSP: 0.005 t/unidad
        }
    }
    
    local wet_mass is ship:mass.
    local dry_mass is wet_mass - fuel_mass.
    if dry_mass <= 0 { return 99999. }
    if fuel_mass <= 0 { return 0. }
    
    // ISP: promedio directo de vacuumisp de los motores del booster
    local total_isp is 0.
    local eng_count is 0.
    for eng in booster_engines {
        if eng:vacuumisp > 0 {
            set total_isp to total_isp + eng:vacuumisp.
            set eng_count to eng_count + 1.
        }
    }
    
    local avg_isp is 300.
    if eng_count > 0 { set avg_isp to total_isp / eng_count. }
    
    return avg_isp * 9.80665 * LN(wet_mass / dry_mass).
}

// --- LOG TELEMETRÍA JSON (Vinculación con Mission Control) ---
global telemetry_toggle is true.
global barca_geo is LATLNG(0,0). // Hecho global para usarlo en reentrada y telemetría

function log_booster_telemetry {
    parameter statusText.
    
    local engStates is lexicon().
    local is_ignited is false.
    for eng in booster_engines { if eng:ignition { set is_ignited to true. } }
    
    if is_ignited and throttle > 0 {
        if engine_mode = 9 {
            for i in list("1","2","3","4","5","6","7") { engStates:add(i, 1). }
        } else if engine_mode = 3 {
            for i in list("1","2","3") { engStates:add(i, 1). }
            for i in list("4","5","6","7") { engStates:add(i, 0). }
        } else if engine_mode = 1 {
            engStates:add("1", 1).
            for i in list("2","3","4","5","6","7") { engStates:add(i, 0). }
        }
    } else {
        for i in list("1","2","3","4","5","6","7") { engStates:add(i, 0). }
    }
    
    local current_fuel is 0.
    for p in ship:partstagged("BOOSTER") {
        for res in p:resources {
            if res:name = "LiquidFuel" or res:name = "Oxidizer" or res:name = "Kerosene" or res:name = "LqdOxygen" {
                set current_fuel to current_fuel + res:amount.
            }
        }
    }
    
    local h_dist is 999999.
    if barca_geo:lng <> 0 {
        set h_dist to VXCL(UP:VECTOR, barca_geo:POSITION):MAG.
    }
    
    local data is lexicon(
        "status", statusText,
        "alt", ROUND(ship:altitude, 0),
        "vel", ROUND(ship:velocity:surface:mag, 0),
        "vs", ROUND(ship:verticalspeed, 1),
        "hdist", ROUND(h_dist, 0),
        "fuel", ROUND(current_fuel, 0),
        "fuelpct", ROUND(get_booster_fuel_pct(), 1),
        "thr", ROUND(throttle * 100, 0),
        "engstates", engStates
    ).
    
    if telemetry_toggle {
        writejson(data, "0:/telemetry_booster_A.json").
    } else {
        writejson(data, "0:/telemetry_booster_B.json").
    }
    set telemetry_toggle to not telemetry_toggle.
}

// --- SECUENCIA DE ASCENSO ---
function execute_ascent {
    print "Iniciando secuencia de ascenso...".
    
    if ADDONS:TR:AVAILABLE {
        print "Addon Trajectories detectado.".
    }
    
    // Configuracion inicial de despegue
    lock throttle to 1.0.
    
    local barca_done is false.
    local rcs_activated is false.
    
    // Bucle principal de ascenso. Terminará por apoapsis o por separación.
    until apoapsis > 150000 {
        // Iniciar inclinación gradual a medida que sube.
        set PITCH to max(15, 90 - (ALTITUDE / 800)).
        set MI_RUMBO to HEADING(90, PITCH).
        lock STEERING to MI_RUMBO.
        
        // Imprimir combustible en pantalla
        print "FUEL BOOSTER: " + ROUND(get_booster_fuel_pct(), 1) + " %    " at (0, 10).
        
        // Búsqueda de JShip (a los 500m de altitud)
        if not barca_done and ALTITUDE > 500 {
            HUDTEXT("BUSCANDO OBJETIVO JSHIP...", 5, 2, 18, yellow, false).
            
            // Intentamos localizar la barca
            local b_vessel is find_barge().
            if b_vessel <> 0 {
                set barca_geo to b_vessel:geoposition.
                
                if ADDONS:TR:AVAILABLE {
                    ADDONS:TR:SETTARGET(barca_geo).
                    HUDTEXT("JSHIP LOCALIZADA. OBJETIVO FIJADO EN TRAJECTORIES.", 5, 2, 18, green, false).
                    print "JShip fijada como objetivo de Trajectories.".
                } else {
                    HUDTEXT("JSHIP LOCALIZADA (Sin Trajectories)", 5, 2, 18, yellow, false).
                }
                
                set barca_done to true.
            }
        }
        
        // --- LOGICA DE SEPARACION ---
        if barca_done and ADDONS:TR:AVAILABLE and ADDONS:TR:HASIMPACT {
            local impact_geo is ADDONS:TR:IMPACTPOS.
            
            // Activar RCS cuando el impacto cruza la barca (0km)
            if not rcs_activated and impact_geo:LNG >= barca_geo:LNG {
                HUDTEXT("IMPACTO EN 0km - ACTIVANDO RCS", 5, 2, 18, cyan, false).
                rcs on.
                set rcs_activated to true.
            }
        }
        
        // --- LOGICA DE SEPARACION CUANDO EL IMP. DIST LLEGUE A 17KM PASANDO JSHIP ---
        local sep_triggered is false.
        if barca_done and ADDONS:TR:AVAILABLE and ADDONS:TR:HASIMPACT {
            local impact_geo is ADDONS:TR:IMPACTPOS.
            local dist_impact is (impact_geo:POSITION - barca_geo:POSITION):MAG.
            if impact_geo:LNG >= barca_geo:LNG and dist_impact >= 17000 {
                set sep_triggered to true.
            }
        }
        
        // Fallback de seguridad: separar si el combustible baja al 10%
        if get_booster_fuel_pct() <= 10 {
            set sep_triggered to true.
            HUDTEXT("FALLBACK: COMBUSTIBLE AL 10% - SEPARACION DE EMERGENCIA", 5, 2, 20, red, false).
        }
        
        if sep_triggered {
            // Poner a 0% de potencia
            lock throttle to 0.
            
            // Notificar al Ship que se inicia la separación (AG7)
            ag7 on.
            wait 0.1.
            ag7 off.
            
            // Separar etapa inmediatamente (tag INTER)
            for p in ship:partstagged("INTER") {
                if p:hasmodule("ModuleDecouple") { p:getmodule("ModuleDecouple"):doevent("decouple"). }
                if p:hasmodule("ModuleAnchoredDecoupler") { p:getmodule("ModuleAnchoredDecoupler"):doevent("decouple"). }
            }
            
            // Notificar al Ship que la separación física se ha completado (AG8)
            ag8 on.
            wait 0.1.
            ag8 off.
            
            HUDTEXT("SEPARACION COMPLETADA", 5, 2, 20, green, false).
            
            // Iniciar venteo de combustible excedente hasta llegar al 17%
            start_drain().
            
            break. // Salir del bucle de ascenso principal
        }
        
        log_booster_telemetry("ASCENT").
        wait 0.1.
    }
    
    if not barca_done {
        // Fallback: punto en el mar en la dirección del lanzamiento (aprox 45km)
        set barca_geo to BODY:GEOPOSITIONOF(ship:geoposition:position + HEADING(90, 0):VECTOR * 45000).
        HUDTEXT("JShip no encontrada. Usando posicion fallback en el mar.", 5, 2, 18, red, false).
    }
    
    print "Secuencia de ascenso (Boost) finalizada.".
    lock throttle to 0.
    
    // Mantener el cohete estable 4 segundos tras la separación
    HUDTEXT("COAST - MANTENIENDO ESTABILIDAD 4s", 5, 2, 18, yellow, false).
    lock steering to ship:facing.
    
    local t_coast is time:seconds.
    until time:seconds - t_coast > 4 {
        check_fuel_venting().
        log_booster_telemetry("COAST").
        wait 0.2.
    }
    
    // Orientarlo a vertical con 0 grados de roll
    HUDTEXT("ORIENTANDO VERTICAL (PITCH 90, ROLL 0)", 5, 2, 18, cyan, false).
    lock steering to heading(90, 90, 0).
    
    local t_vert is time:seconds.
    until time:seconds - t_vert > 15 {
        check_fuel_venting().
        log_booster_telemetry("COAST").
        wait 0.2.
    }
}

function read_launch_cfg {
    parameter fpath.
    local result is lexicon().
    local f is open(fpath).
    local content is f:readall().
    for line in content {
        local txt is line:tostring():trim.
        if txt:contains("=") {
            local eqPos is txt:find("=").
            local k is txt:substring(0, eqPos):trim.
            local val is txt:substring(eqPos + 1, txt:length - eqPos - 1):trim.
            result:add(k, val).
        }
    }
    return result.
}

function write_launch_cfg {
    parameter fpath, data.
    if exists(fpath) { deletepath(fpath). }
    log "t_minus=" + data["t_minus"] to fpath.
    log "payload_tons=" + data["payload_tons"] to fpath.
    log "status=" + data["status"] to fpath.
}

function execute_countdown {
    clearscreen.
    print "==============================".
    print " SECUENCIA DE LANZAMIENTO     ".
    print " (Control Remoto via TXT)     ".
    print "==============================".
    
    local config_path is "0:/boot/PreLanzamiento/launch_config.txt".
    
    until exists(config_path) {
        print "Esperando conexion con Mission Control..." at (0, 4).
        log_booster_telemetry("PRELAUNCH").
        wait 1.
    }
    
    local launch_cfg is read_launch_cfg(config_path).
    local t is launch_cfg["t_minus"]:tonumber(10).
    global payload_mass is launch_cfg["payload_tons"]:tonumber(0).
    local launch_status is launch_cfg["status"].
    
    local ignition_done is false.
    local lift_done is false.
    
    until lift_done {
        set launch_cfg to read_launch_cfg(config_path).
        set launch_status to launch_cfg["status"].
        set payload_mass to launch_cfg["payload_tons"]:tonumber(0).
        set t to launch_cfg["t_minus"]:tonumber(t).
        
        if launch_status = "ABORT" {
            HUDTEXT("!!! ABORT !!! SECUENCIA CANCELADA", 10, 2, 24, red, false).
            print "!!! LANZAMIENTO ABORTADO !!!" at (0, 10).
            lock throttle to 0.
            for eng in booster_engines { eng:shutdown(). }
            log_booster_telemetry("ABORTED").
            shutdown.
        }
        
        if launch_status = "READY" {
            print "STATUS: ESPERANDO MC  " at (0, 5).
            print "T- " + ROUND(t, 0) + " s      " at (0, 6).
        }
        else if launch_status = "HOLD" {
            print "STATUS: HOLD          " at (0, 5).
            print "T- " + ROUND(t, 0) + " s      " at (0, 6).
        } 
        else if launch_status = "COUNTDOWN" or launch_status = "LAUNCHED" {
            print "STATUS: COUNTDOWN     " at (0, 5).
            print "T- " + ROUND(t, 0) + " s      " at (0, 6).
            
            if t <= 2 and not ignition_done {
                print "T- 2: IGNICION!                    " at (0, 8).
                lock throttle to 1.0.
                for eng in booster_engines { eng:activate(). }
                set ignition_done to true.
            }
            
            if t <= 0 or launch_status = "LAUNCHED" {
                print "T- 0: DESPEGUE!                    " at (0, 9).
                ag1 on.
                set lift_done to true.
                
                set launch_cfg["status"] to "LAUNCHED".
                write_launch_cfg(config_path, launch_cfg).
            }
        }
        
        print "PAYLOAD: " + ROUND(payload_mass, 1) + " T      " at (0, 7).
        log_booster_telemetry("PRELAUNCH").
        wait 0.2.
    }
    log_booster_telemetry("LIFTOFF").
}

function print_coast_telemetry {
    parameter phase_name.
    print "=== TELEMETRIA COAST (" + phase_name + ") ===" at (0, 10).
    print "ALTITUD:     " + ROUND(ALTITUDE / 1000, 1) + " km      " at (0, 11).
    print "VELOCIDAD:   " + ROUND(ship:velocity:surface:mag, 0) + " m/s      " at (0, 12).
    print "V.SPEED:     " + ROUND(ship:verticalspeed, 1) + " m/s      " at (0, 13).
    
    local vent_str is "APAGADO".
    if venting_active { set vent_str to "ACTIVADO". }
    print "VENTEO FUEL: " + vent_str + " (" + ROUND(get_booster_fuel_pct(), 1) + "%)      " at (0, 14).
    
    local imp_str is "N/D".
    if ADDONS:TR:AVAILABLE and ADDONS:TR:HASIMPACT {
        local impact_geo is ADDONS:TR:IMPACTPOS.
        local dist_impact is (impact_geo:POSITION - barca_geo:POSITION):MAG.
        set imp_str to ROUND(dist_impact / 1000, 2) + " km".
    }
    print "IMP. DIST:   " + imp_str + "        " at (0, 15).
}

function wait_for_descent {
    clearscreen.
    print "==============================".
    print " FASE COAST: ESPERANDO DESCENSO ".
    print "==============================".
    
    until ship:verticalspeed < 0 {
        check_fuel_venting().
        print_coast_telemetry("ESPERANDO APOGEO").
        log_booster_telemetry("COAST").
        wait 0.2.
    }
    
    HUDTEXT("DESCENSO DETECTADO. ESPERANDO 4s...", 5, 2, 18, yellow, false).
    local t_wait is time:seconds.
    until time:seconds - t_wait > 4 {
        check_fuel_venting().
        print_coast_telemetry("INICIO DESCENSO").
        log_booster_telemetry("COAST").
        wait 0.2.
    }
    
    HUDTEXT("ORIENTANDO A RETROGRADO", 5, 2, 18, cyan, false).
    lock steering to ship:retrograde.
    
    local t_align is time:seconds.
    until time:seconds - t_align > 5 {
        check_fuel_venting().
        print_coast_telemetry("ALINEACION RETROGRADO").
        log_booster_telemetry("COAST").
        wait 0.2.
    }
}

function execute_entry_burn {
    print "==============================".
    print " FASE ENTRY BURN              ".
    print "==============================".
    
    print "Esperando altitud 60km para entry burn..." at (0, 4).
    until ALTITUDE < 60000 {
        check_fuel_venting().
        print_coast_telemetry("ESPERANDO 60KM").
        log_booster_telemetry("COAST").
        wait 0.2.
    }
    
    // Cambiar a 3 motores usando Action Group 3
    HUDTEXT("CAMBIANDO A MODO 3 MOTORES (AG3)", 5, 2, 18, yellow, false).
    ag3 on.
    wait 0.2.
    ag3 off.
    set engine_mode to 3.
    
    // Reencender motores
    HUDTEXT("ENTRY BURN - 3 MOTORES", 5, 2, 20, red, false).
    print "Encendiendo motores...".
    lock throttle to 0.6.
    
    print "Entry burn: frenando...".
    local burn_start is time:seconds.
    local entry_steer is ship:retrograde.
    lock steering to entry_steer.
    
    until false {
        if ADDONS:TR:AVAILABLE and ADDONS:TR:HASIMPACT {
            local impact_geo is ADDONS:TR:IMPACTPOS.
            local error_vec is impact_geo:POSITION - barca_geo:POSITION.
            local approach_dir is VXCL(UP:VECTOR, barca_geo:POSITION - ship:POSITION):NORMALIZED.
            local lng_err is VDOT(approach_dir, error_vec).
            local dist_impact is error_vec:MAG.
            local elapsed is ROUND(time:seconds - burn_start, 1).
            
            local approach_up is (barca_geo:POSITION - BODY:POSITION):NORMALIZED.
            local lat_err is VDOT(ANGLEAXIS(-90, approach_up) * approach_dir, error_vec).
            
            // Corrección lateral agresiva — divisor más bajo = más respuesta
            local lat_corr is MAX(-25, MIN(25, -lat_err / 60)).
            
            local retro_vec is -ship:VELOCITY:SURFACE:NORMALIZED.
            local retro_horiz is VXCL(UP:VECTOR, retro_vec):NORMALIZED.
            local flat_retro is (retro_horiz * 0.3 + retro_vec * 0.7):NORMALIZED.
            local corrected_vec is flat_retro * ANGLEAXIS(lat_corr, UP:VECTOR).
            set entry_steer to LOOKDIRUP(corrected_vec:NORMALIZED, UP:VECTOR).
            
            HUDTEXT("JSHIP: " + ROUND(dist_impact/1000,1) + "km | LNG:" + ROUND(lng_err,0) + "m | LAT:" + ROUND(lat_err,0) + "m | LCORR:" + ROUND(lat_corr,1) + "deg | T:" + elapsed + "s", 1, 2, 13, white, false).
            
            // Salir cuando el impacto predicho esté a menos de 500m de la barcaza
            if (time:seconds - burn_start) >= 3 and dist_impact <= 500 {
                HUDTEXT("500M - CORTE ENTRY BURN", 5, 2, 20, green, false).
                break.
            }
        }
        
        log_booster_telemetry("ENTRY BURN").
        wait 0.1.
    }
    
    // Poner a 0% de potencia
    lock throttle to 0.
    
    ag2 on.
    HUDTEXT("ALERONES AERODINAMICOS ACTIVADOS (AG2)", 5, 2, 18, cyan, false).
    print "Entry burn completado. Alerones desplegados.".
}

function execute_dynamic_descent {
    clearscreen.
    print "==============================".
    print " FASE DESCENSO DINAMICO       ".
    print "==============================".
    print "Orientando vertical para coast...".
    
    local approach_vec_init is VXCL(UP:VECTOR, barca_geo:POSITION - ship:POSITION):NORMALIZED.
    local offset_dist is 180.
    if payload_mass > 20 { set offset_dist to 210. }
    local descent_target_offset is BODY:GEOPOSITIONOF(barca_geo:POSITION + approach_vec_init * offset_dist).
    local descent_target is descent_target_offset.
    
    lock steering to LOOKDIRUP(UP:VECTOR, HEADING(270,0):VECTOR).
    
    local LngError is 0.
    local LatError is 0.
    local LngCtrl is 0.
    local LatCtrl is 0.
    local ErrorVector is V(0,0,0).
    local PIDFactor is 10.
    local SteeringVector is LOOKDIRUP(UP:VECTOR, HEADING(270,0):VECTOR).
    
    local LngCtrlPID is PIDLOOP(0.35, 0.3, 0.25, -10, 10).
    local LatCtrlPID is PIDLOOP(0.15, 0.2, 0.1, -4, 4).
    set LngCtrlPID:SETPOINT to 0.
    
    print "--- DESCENSO DINAMICO ---" at (0, 10).
    print "ALT: " at (0, 11).
    print "VEL: " at (0, 12).
    print "IMP>JSHIP: " at (0, 13).
    print "LNG ERR: " at (0, 14).
    print "LAT ERR: " at (0, 15).
    print "LNG CTRL: " at (0, 16).
    
    HUDTEXT("GUIA AERODINAMICA ACTIVA", 5, 2, 20, cyan, false).
    print "Iniciando guía aerodinámica (flaps)...".
    lock steering to SteeringVector.
    
    until ALT:RADAR < 2100 {
        if ADDONS:TR:AVAILABLE and ADDONS:TR:HASIMPACT {
            local approachDir is VXCL(UP:VECTOR, descent_target:POSITION - ship:POSITION):NORMALIZED.
            set ErrorVector to ADDONS:TR:IMPACTPOS:POSITION - descent_target:POSITION.
        }
        
        local ApproachUPVector is (descent_target:POSITION - BODY:POSITION):NORMALIZED.
        local ApproachVector is VXCL(UP:VECTOR, descent_target:POSITION - ship:POSITION):NORMALIZED.
        
        set LatError to VDOT(ANGLEAXIS(-90, ApproachUPVector) * ApproachVector, ErrorVector).
        set LngError to VDOT(ApproachVector, ErrorVector).
        
        set LngCtrlPID:MAXOUTPUT to MAX(MIN(ABS(LngError) / PIDFactor, 23), 1.0).
        set LngCtrlPID:MINOUTPUT to -LngCtrlPID:MAXOUTPUT.
        
        set LngCtrl to -LngCtrlPID:UPDATE(time:seconds, LngError).
        set LatCtrl to -LatCtrlPID:UPDATE(time:seconds, LatError).
        
        local FinalVec is -ship:VELOCITY:SURFACE * ANGLEAXIS(-LngCtrl, LOOKDIRUP(-ship:VELOCITY:SURFACE, UP:VECTOR):STARVECTOR) * ANGLEAXIS(LatCtrl, UP:VECTOR).
        local FinalTopVec is HEADING(270,0):VECTOR * ANGLEAXIS(2 * LatCtrl, UP:VECTOR).
        
        set SteeringVector to LOOKDIRUP(FinalVec, FinalTopVec).
        
        print ROUND(ship:ALTITUDE / 1000, 1) + " km      " at (15, 11).
        print ROUND(ship:VELOCITY:SURFACE:MAG, 0) + " m/s      " at (15, 12).
        print ROUND(ErrorVector:MAG / 1000, 2) + " km      " at (15, 13).
        print ROUND(LngError, 0) + " m      " at (15, 14).
        print ROUND(LatError, 0) + " m      " at (15, 15).
        print ROUND(LngCtrl, 2) + " deg      " at (15, 16).
        
        log_booster_telemetry("DYNAMIC DESCENT").
        wait 0.1.
    }
    
    clearscreen.
    HUDTEXT("DESCENSO DINAMICO COMPLETADO", 5, 2, 20, green, false).
}

function execute_landing_burn {
    clearscreen.
    print "==============================".
    print "=== LANDING BURN ===".
    print "==============================".
    
    local descent_target is barca_geo.
    
    // --- FASE 1: FRENADO RETROGRADO A 2.3KM (3 MOTORES) ---
    HUDTEXT("ESPERANDO 2.8KM PARA LANDING BURN...", 5, 2, 18, yellow, false).
    until ALT:RADAR < 2800 {
        log_booster_telemetry("DYNAMIC DESCENT").
        wait 0.1.
    }
    
    HUDTEXT("LANDING BURN - 3 MOTORES", 5, 2, 20, red, false).
    print "Encendiendo motores al maximo...".
    
    lock throttle to 1.0.
    lock steering to ship:srfretrograde.
    
    rcs off.
    ag6 on. // Desactivar flaps aerodinámicos
    HUDTEXT("FLAPS DESACTIVADOS (AG6)", 3, 2, 18, yellow, false).
    
    print "--- LANDING BURN ---" at (0, 10).
    print "FASE: " at (0, 11).
    print "ALT: " at (0, 12).
    print "VEL: " at (0, 13).
    print "V.VERT: " at (0, 14).
    print "IMP: " at (0, 15).
    print "H.SPD: " at (0, 16).
    print "FUEL: " at (0, 17).
    
    local cutoff_speed is 25.
    
    until ship:VELOCITY:SURFACE:MAG < cutoff_speed {
        local true_alt is MIN(ALT:RADAR, ALTITUDE - 21).
        local GSVec is VXCL(UP:VECTOR, ship:VELOCITY:SURFACE).
        local hspd is GSVec:MAG.
        local distTarget is VXCL(UP:VECTOR, descent_target:POSITION - ship:POSITION).
        
        local impactError is V(0,0,0).
        if ADDONS:TR:AVAILABLE and ADDONS:TR:HASIMPACT {
            set impactError to VXCL(UP:VECTOR, ADDONS:TR:IMPACTPOS:POSITION - descent_target:POSITION).
        } else {
            set impactError to -distTarget + GSVec * 2.0.
        }
        local impactDist is impactError:MAG.
        
        print "FRENADO RETROGRADO    " at (10, 11).
        print ROUND(true_alt, 0) + " m      " at (10, 12).
        print ROUND(ship:VELOCITY:SURFACE:MAG, 0) + " m/s      " at (10, 13).
        print ROUND(ship:VERTICALSPEED, 1) + " m/s      " at (10, 14).
        print ROUND(impactDist, 1) + " m      " at (10, 15).
        print ROUND(hspd, 1) + " m/s      " at (10, 16).
        print ROUND(get_booster_fuel_pct(), 1) + " %      " at (10, 17).
        
        log_booster_telemetry("LANDING BURN 3ENG").
        wait 0.05.
    }
    
    // --- APAGAR 2 MOTORES Y PASAR A MOTOR CENTRAL (1 MOTOR) ---
    HUDTEXT(ROUND(cutoff_speed,0) + " M/S - CAMBIANDO A 1 MOTOR (AG3)", 5, 2, 20, green, false).
    
    // Cambiar a 1 motor usando Action Group 3 de nuevo
    ag3 on.
    wait 0.2.
    ag3 off.
    set engine_mode to 1.
    
    local landing_steer is -ship:VELOCITY:SURFACE:NORMALIZED.
    lock steering to LOOKDIRUP(landing_steer, HEADING(270,0):VECTOR).
    
    local throttleVal is 0.5.
    lock throttle to throttleVal.
    
    // --- DESCENSO CON MOTOR CENTRAL: TWR + HOVER MODE ---
    local hover_mode is false.
    until ship:STATUS = "LANDED" or ship:STATUS = "SPLASHED" {
        local vel is ship:VELOCITY:SURFACE:MAG.
        local vspd is ship:VERTICALSPEED.
        local GSVec is VXCL(UP:VECTOR, ship:VELOCITY:SURFACE).
        local hspd is GSVec:MAG.
        local distTarget is VXCL(UP:VECTOR, descent_target:POSITION - ship:POSITION).
        local hdist is distTarget:MAG.
        local true_alt is MIN(ALT:RADAR, ALTITUDE - 21).
        
        // Detección de touchdown
        if ABS(vspd) < 0.2 and true_alt < 2 { break. }
        
        local impactError is V(0,0,0).
        if ADDONS:TR:AVAILABLE and ADDONS:TR:HASIMPACT {
            set impactError to VXCL(UP:VECTOR, ADDONS:TR:IMPACTPOS:POSITION - descent_target:POSITION).
        } else {
            set impactError to -distTarget + GSVec * 2.0.
        }
        local impactDist is impactError:MAG.
        
        // --- HOVER MODE: Frenar descenso si estamos descentrados a baja altitud ---
        // Se activa si estamos por debajo de 150m y a más de 12.5m del centro
        if true_alt < 150 and hdist > 12.5 {
            set hover_mode to true.
        }
        // Se desactiva cuando el cohete está suficientemente centrado (<= 12.5m)
        if hover_mode and hdist <= 12.5 {
            set hover_mode to false.
        }
        
        local modeStr is "DESCENSO FINAL".
        
        // Curva continua: descendemos agresivo y frenamos suavemente solo al final
        local targetVspd is -1 * (SQRT(MAX(0, true_alt)) * 1.8 + 1.5).
        // Caps de seguridad por altura
        if true_alt < 40  { set targetVspd to MAX(targetVspd, -3.5). }
        if true_alt < 15  { set targetVspd to MAX(targetVspd, -1.8). }
        if true_alt < 5   { set targetVspd to MAX(targetVspd, -0.8). }
        
        // Hover: sobrescribir targetVspd con casi-cero para dar tiempo a corregir posición
        if hover_mode {
            set targetVspd to -0.3.
            set modeStr to "HOVER - CENTRANDO".
            HUDTEXT("HOVER MODE - CENTRANDO: " + ROUND(hdist, 1) + "m", 1, 2, 16, cyan, false).
        }
        
        print modeStr + "      " at (10, 11).
        
        local grav is (body:mu / (body:radius + altitude)^2).
        local max_acc is ship:availablethrust / ship:mass.
        if max_acc < 0.001 { set max_acc to 1. }
        local v_err is targetVspd - vspd.
        local twr_gain is 0.8.
        
        // Compensacion de inclinacion: si el cohete se inclina,
        // aumenta el throttle para mantener el mismo empuje vertical
        local tilt_angle is VANG(UP:VECTOR, ship:facing:forevector).
        local tilt_comp is 1 / MAX(COS(tilt_angle), 0.6). // limitar a max 1.66x para no dispararse
        
        set throttleVal to ((grav + v_err * twr_gain) / max_acc) * tilt_comp.
        
        if vspd > 1 { set throttleVal to 0. }
        set throttleVal to MAX(0, MIN(1.0, throttleVal)).
        
        // --- CÁLCULO DE GUIADO PD (Estilo landing.ks) ---
        local currentTiltLimit is 18.0.
        if true_alt < 1000 { set currentTiltLimit to 12.0. }
        if true_alt < 60   { set currentTiltLimit to 8.0. }
        // En hover: limitar la inclinación para mayor estabilidad
        if hover_mode      { set currentTiltLimit to 4.0. }
        
        // Deseamos una velocidad horizontal hacia el objetivo proporcional al error de distancia (distTarget)
        local maxH is MIN(35, 6 + (true_alt / 200)).
        if hover_mode { set maxH to 4.0. } // En hover: movimiento lateral lento y controlado
        local targetHVel is distTarget * 0.45.
        if targetHVel:MAG > maxH { set targetHVel to targetHVel:NORMALIZED * maxH. }
        
        // El empuje correctivo (nudge) es proporcional al error de velocidad horizontal (GSVec)
        local nudge is (targetHVel - GSVec) * 0.35.
        
        local rawSteer is UP:VECTOR + nudge.
        if VANG(UP:VECTOR, rawSteer) > currentTiltLimit {
            set rawSteer to UP:VECTOR + VXCL(UP:VECTOR, rawSteer):NORMALIZED * TAN(currentTiltLimit).
        }
        
        local smoothFactor is 0.25.
        if true_alt < 60  { set smoothFactor to 0.12. }
        if hover_mode     { set smoothFactor to 0.18. }
        set landing_steer to landing_steer * (1 - smoothFactor) + rawSteer * smoothFactor.
        
        if true_alt < 1000 { ag5 on. }
        
        print ROUND(true_alt, 0) + " m      " at (10, 12).
        print ROUND(vel, 0) + " m/s      " at (10, 13).
        print ROUND(vspd, 1) + " m/s      " at (10, 14).
        print ROUND(hdist, 1) + " m      " at (10, 15).
        print ROUND(hspd, 1) + " m/s      " at (10, 16).
        print ROUND(get_booster_fuel_pct(), 1) + " %      " at (10, 17).
        
        log_booster_telemetry("LANDING BURN 1ENG").
        wait 0.05.
    }
    
    // --- ATERRIZADO ---
    lock throttle to 0.
    unlock steering.
    // unlock throttle. // Mantenemos bloqueado a 0% para evitar aceleracion accidental
    rcs off.
    
    clearscreen.
    
    HUDTEXT("TOUCHDOWN! BOOSTER ATERRIZADO", 10, 2, 24, green, false).
    print "=== BOOSTER ATERRIZADO ===".
    log_booster_telemetry("LANDED").
    wait 5.
    shutdown.
}

// --- EJECUCION PRINCIPAL ---
global payload_mass is 0.

execute_countdown().
execute_ascent().
wait_for_descent().
execute_entry_burn().
execute_dynamic_descent().
execute_landing_burn().
