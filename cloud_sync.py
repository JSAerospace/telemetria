import json
import os
import time
import sys
import requests
import re

# --- CONFIGURACIÓN DE FIREBASE ---
MISSION_ID = None  # Inicializado globalmente

try:
    import serial  # Requiere: pip install pyserial
except ImportError:
    serial = None
    print("[!] Aviso: Librería 'pyserial' no encontrada. El panel físico no funcionará.")
    print("    Instálala con: pip install pyserial")
FIREBASE_URL = "https://control-de-mision-js-default-rtdb.firebaseio.com/"
BASE_DIR = r"C:\Users\olano\OneDrive\Desktop\Kerbal Space Program\Ships\Script"

# SESIÓN PERSISTENTE (Keep-Alive)
session = requests.Session()

# --- CONFIGURACIÓN SERIAL (ARDUINO) ---
SERIAL_PORT = "COM3"
BAUD_RATE = 9600
arduino = None

if serial:
    try:
        arduino = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=0.1)
        print(f"[OK] Panel de Control detectado en {SERIAL_PORT}")
    except Exception as e:
        print(f"[!] Aviso: No se pudo abrir {SERIAL_PORT} ({e}). Continuando sin panel físico.")
else:
    print("[!] Panel físico desactivado (Falta pyserial)")

def sanitize_key(key):
    """Limpia las claves para que sean aceptadas por Firebase."""
    if not isinstance(key, str):
        key = str(key)
    # Firebase no permite: . $ # [ ] / o caracteres de control ASCII 0-31 o 127
    return re.sub(r'[.$#\[\]/]', '_', key)

def sanitize_data(data):
    if isinstance(data, dict):
        new_dict = {}
        for k, v in data.items():
            new_dict[sanitize_key(k)] = sanitize_data(v)
        return new_dict
    elif isinstance(data, list):
        return [sanitize_data(item) for item in data]
    else:
        return data

def upload_telemetry(stage, data):
    """Sube los datos a Firebase Realtime Database usando sesión persistente."""
    if not data or not MISSION_ID:
        return False
    
    clean_data = sanitize_data(data)
    
    try:
        # PATH: missions/{ID}/{ship|booster}.json
        url = f"{FIREBASE_URL}missions/{MISSION_ID}/{stage}.json"
        # Usamos la sesión global para reusar conexión TCP/SSL
        response = session.put(url, json=clean_data, timeout=3)
        if response.status_code == 200:
            return True
        else:
            print(f"\n[!] Error al subir {stage}: Status {response.status_code}")
            return False
    except Exception as e:
        print(f"\n[!] Error de red subiendo {stage}: {e}")
        return False

def get_latest_telemetry(stage):
    """Lee el JSON generado por kOS para la etapa correspondiente, buscando variantes _A y _B."""
    # Variantes posibles ordenadas por prioridad (nuevos nombres primero)
    variants = [
        f"telemetry_{stage}_A.json",
        f"telemetry_{stage}_B.json",
        f"telemetry_{stage}.json",
        f"{stage}.json",
        f"telemetry_{stage}_L.json" # Variante para Lander
    ]
    
    latest_path = None
    latest_time = 0
    
    for v in variants:
        p = os.path.join(BASE_DIR, v)
        if os.path.exists(p):
            try:
                mtime = os.path.getmtime(p)
                if mtime > latest_time:
                    latest_time = mtime
                    latest_path = p
            except:
                continue
            
    if not latest_path:
        return None
    
    try:
        with open(latest_path, "r", encoding="utf-8") as f:
            content = f.read().strip()
            if not content: return None
            return json.loads(content)
    except:
        return None

def parse_kos_json(data):
    """Convierte la estructura Lexicon de kOS en algo legible para el Dashboard."""
    if not data or not isinstance(data, dict):
        return data
        
    # kOS a veces exporta diccionarios simples o con 'entries'
    if "entries" in data and isinstance(data["entries"], list):
        parsed = {}
        entries = data["entries"]
        # Intenta el formato de lista de diccionarios {key: ..., value: ...}
        if all(isinstance(entry, dict) and "key" in entry and "value" in entry for entry in entries):
            for entry in entries:
                k = entry["key"].get("value") if isinstance(entry["key"], dict) else entry["key"]
                v = entry["value"].get("value") if isinstance(entry["value"], dict) else entry["value"]
                if isinstance(v, dict): v = parse_kos_json(v)
                parsed[str(k).lower()] = v
        # Si no, intenta el formato de lista plana [key1, value1, key2, value2, ...]
        else:
            result = {} # Use a new dict for this alternative parsing
            for i in range(0, len(entries) - 1, 2):
                k_obj = entries[i]
                v_obj = entries[i + 1]
                k = k_obj.get("value") if (isinstance(k_obj, dict) and "value" in k_obj) else (k_obj if not isinstance(k_obj, dict) else None)
                if k is None and isinstance(k_obj, dict): k = k_obj
                
                v = v_obj.get("value") if (isinstance(v_obj, dict) and "value" in v_obj) else v_obj
                if isinstance(v, dict): v = parse_kos_json(v)
                if k is not None: result[str(k).strip().lower()] = v
            parsed = result # Assign the result of this parsing to 'parsed'
        return parsed
    
    # Caso plano
    return {str(k).lower(): v for k, v in data.items() if k != "$type"}

def handle_arduino_commands():
    """Lee comandos del puerto Serial y los ejecuta en Firebase."""
    global arduino, MISSION_ID
    if not arduino or not MISSION_ID: return
    
    try:
        if arduino.in_waiting > 0:
            raw_line = arduino.readline()
            if not raw_line: return
            line = raw_line.decode('utf-8', errors='ignore').strip()
            if not line: return
            
            print(f"\n[HOTKEY] Comando recibido: {line}")
            
            if line == "CMD_GO":
                # Toggle Mission Go
                url = f"{FIREBASE_URL}missions/{MISSION_ID}/global/mission_go.json"
                resp = session.get(url)
                current = resp.json() if resp.status_code == 200 else False
                new_state = not current
                session.put(url, json=new_state)
                print(f" >> MISSION GO: {'VERDE' if new_state else 'ROJO'} (Physical Switch)")
                
            elif line == "CMD_RESET":
                # Reset MET
                url = f"{FIREBASE_URL}missions/{MISSION_ID}/global/mission_start.json"
                session.put(url, json=None)
                print(f" >> CRONÓMETRO REINICIADO (Physical Switch)")
    except Exception as e:
        print(f"\n[!] Error de conexión Serial (Arduino): {e}")
        print("[*] Continuando sin panel físico. Reinicia el script para reconectar.")
        arduino = None # Desactivar para que no siga intentando y crashee

def update_arduino_lcd(client_go):
    """Envía el estado del cliente al Arduino para mostrarlo en el LCD."""
    global arduino
    if not arduino: return
    
    try:
        msg = f"ST_CLIENT_GO:{1 if client_go else 0}\n"
        arduino.write(msg.encode('utf-8'))
    except Exception as e:
        print(f"[!] Error enviando datos al LCD: {e}")
        arduino = None # Desactivar si falla para no bloquear el bucle

def main():
    global MISSION_ID
    print("╔══════════════════════════════════════════════╗")
    print("║   KSP MISSION CONTROL: MULTI-MISSION SYNC    ║")
    print("╚══════════════════════════════════════════════╝")
    
    # NUEVO: Selección de ID de Misión
    MISSION_ID = input("[?] Código de Misión (ej: HS-001): ").strip().upper()
    if not MISSION_ID: MISSION_ID = "HS-DEFAULT"
    
    print(f"[*] Modo: PARTICIONADO (/missions/{MISSION_ID})")
    print(f"[*] Destino: {FIREBASE_URL}")
    print("[*] Estado: CONECTANDO...")
    
    # Test inicial y Limpieza de Reloj
    print("Probando conexión...")
    try:
        global_path = f"{FIREBASE_URL}missions/{MISSION_ID}/global.json"
        
        # NUEVO: Aseguramos que la misión exista para que el login pueda validarla
        # Si no existe nombre de misión, ponemos uno genérico
        check_resp = session.get(f"{FIREBASE_URL}missions/{MISSION_ID}/global/mission_name.json")
        if check_resp.status_code == 200 and check_resp.json() is None:
            print(f"[*] Inicializando canal de misión: {MISSION_ID}")
            session.patch(global_path, json={
                "mission_name": f"MISIÓN {MISSION_ID}",
                "client_name": "PENDIENTE",
                "mission_start": None
            })

        response = session.get(global_path)
        if response.status_code == 200:
            config_data = response.json()
            print("[OK] Conexión establecida. Canal de misión activo. 🚀")
            if config_data and config_data.get("mission_start"):
                print(f"[*] Reloj detectado: T+ {int(time.time() - config_data['mission_start'])}s")
        else:
            print("[!] No se pudo conectar a la base de datos.")
    except Exception as e:
        print(f"[!] Error de conexión: {e}")

    print("\n[*] Transmitiendo datos... (No cierres esta ventana)")
    
    last_print = 0
    mission_started = False
    base_alt = None
    last_arduino_sync = 0
    last_client_go_state = None
    
    while True:
        s_raw = get_latest_telemetry("ship")
        b_raw = get_latest_telemetry("booster")
        l_raw = get_latest_telemetry("lander") # NUEVO: Munar Lander
        
        # Procesar comandos físicos (Arduino)
        handle_arduino_commands()

        # Obtener estado Global (Sync con LCD)
        if time.time() - last_arduino_sync > 2: # Cada 2 segundos sincronizamos el LCD
            try:
                global_data = session.get(f"{FIREBASE_URL}missions/{MISSION_ID}/global.json").json()
                if global_data:
                    c_go = global_data.get("client_go", False)
                    if c_go != last_client_go_state:
                        update_arduino_lcd(c_go)
                        last_client_go_state = c_go
                last_arduino_sync = time.time()
            except: pass
        
        # Subir los datos RAW
        updates = []
        if s_raw and upload_telemetry("ship", s_raw): updates.append("S2")
        if b_raw and upload_telemetry("booster", b_raw): updates.append("BOOSTER")
        if l_raw and upload_telemetry("lander", l_raw): updates.append("LANDER")
        
        # Parsear datos para lógica interna
        s_data = parse_kos_json(s_raw) if s_raw else {}
        b_data = parse_kos_json(b_raw) if b_raw else {}
        l_data = parse_kos_json(l_raw) if l_raw else {}
        
        # --- LÓGICA DE DETECCIÓN CRUZADA ---
        active_data = b_data if b_data.get('vs', 0) > s_data.get('vs', 0) else s_data
        
        if active_data:
            vs = float(active_data.get('vs', 0))
            alt = float(active_data.get('alt', 0))
            status = str(active_data.get('status', '')).upper()
            
            if vs < 0.2 and not mission_started:
                base_alt = alt
            
            # Reset si vuelve a tierra o status PRELAUNCH SCALED BY MISSION
            if (status == "PRELAUNCH" or (alt < (base_alt + 10 if base_alt else 20) and vs < 0.5)) and mission_started:
                try:
                    session.patch(f"{FIREBASE_URL}missions/{MISSION_ID}/global.json", json={"mission_start": None})
                    mission_started = False
                    print(f"\n[*] Misión {MISSION_ID} reseteada")
                except: pass

            # Lógica de despegue desactivada (Gestionada por la Web Dashboard)
            pass
        
        # Feedback visual
        if time.time() - last_print > 1:
            vs_show = active_data.get('vs', 0) if active_data else 0
            alt_show = active_data.get('alt', 0) if active_data else 0
            rel_show = (alt_show - base_alt) if base_alt else 0
            if updates:
                print(f"\r >> {' + '.join(updates)} | VS: {vs_show} | AltRel: {rel_show} | Reloj: {mission_started}    ", end="")
            else:
                print(f"\r .. Esperando datos .. VS: {vs_show} | Alt: {alt_show}                   ", end="")
            last_print = time.time()
            
        time.sleep(0.15)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n[*] Sincronización detenida.")
    except Exception as e:
        print(f"\n\n[ERROR CRÍTICO]: {e}")
        input("Presiona Enter para cerrar...")
