// tower_catch.ks - SISTEMA DE CAPTURA POR JSON (Buzón Compartido)
// Este script debe cargarse en el procesador kOS de la Torre
// ============================================================

CLEARSCREEN.
PRINT "=========================================".
PRINT "   MECHAZILLA CATCH SYSTEM (JSON)".
PRINT "=========================================".
PRINT "Estado: Monitoreando archivo de señal...".
PRINT "Configuracion: AG5 para Cierre".

LOCAL signalPath IS "0:/catch_signal.json".

// Limpiar señal anterior si existe
IF EXISTS(signalPath) { DELETEPATH(signalPath). }

UNTIL FALSE {
    // Si el archivo existe, leemos la señal
    IF EXISTS(signalPath) {
        LOCAL data IS READJSON(signalPath).
        
        IF data:HASKEY("signal") AND data["signal"] = "CLOSE" {
            HUDTEXT("¡SEÑAL JSON RECIBIDA! ACTIVANDO AG5", 5, 2, 35, GREEN, TRUE).
            PRINT ">>> Señal de Cierre detectada en JSON! Activando AG5...".
            
            AG5 ON.
            
            // Borramos el archivo para no disparar dos veces
            DELETEPATH(signalPath).
            PRINT "SECUENCIA COMPLETADA. Brazos cerrados.".
        }
    }
    
    // Telemetría básica
    PRINT "Buscando archivo... [OK]" AT (0, 6).
    WAIT 0.1.
}
