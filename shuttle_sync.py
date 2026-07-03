import json
import os
import time
import re
import requests

# --- CONFIGURACIÓN ---
FIREBASE_URL = "https://control-de-mision-js-default-rtdb.firebaseio.com/"
BASE_DIR = r"C:\Users\olano\OneDrive\Desktop\Kerbal Space Program\Ships\Script"

session = requests.Session()

# --- MISIÓN ---
print("╔══════════════════════════════════════════════╗")
print("║   KSP CLOUD SYNC - SPACE SHUTTLE             ║")
print("╚══════════════════════════════════════════════╝")
MISSION_ID = input("[?] Código de Misión (ej: STS-001): ").strip().upper()
if not MISSION_ID:
    MISSION_ID = "HS-DEFAULT"
print(f"[*] Canal: missions/{MISSION_ID}/shuttle")
print(f"[*] Destino: {FIREBASE_URL}")
print("[*] Escuchando telemetría del Shuttle...\n")

def sanitize_key(key):
    if not isinstance(key, str):
        key = str(key)
    return re.sub(r'[.$#\[\]/]', '_', key)

def sanitize_data(data):
    if isinstance(data, dict):
        return {sanitize_key(k): sanitize_data(v) for k, v in data.items()}
    elif isinstance(data, list):
        return [sanitize_data(i) for i in data]
    return data

def parse_kos(data):
    if not data or not isinstance(data, dict): return data
    if "entries" in data and isinstance(data["entries"], list):
        result = {}
        entries = data["entries"]
        is_type_a = entries and isinstance(entries[0], dict) and "key" in entries[0]
        if is_type_a:
            for entry in entries:
                k = entry.get("key", {}).get("value") if isinstance(entry.get("key"), dict) else entry.get("key")
                v = entry.get("value", {}).get("value") if isinstance(entry.get("value"), dict) else entry.get("value")
                if isinstance(v, dict): v = parse_kos(v)
                if k is not None: result[str(k).strip().lower()] = v
        else:
            for i in range(0, len(entries) - 1, 2):
                k_obj = entries[i]
                v_obj = entries[i + 1]
                k = k_obj.get("value") if (isinstance(k_obj, dict) and "value" in k_obj) else (k_obj if not isinstance(k_obj, dict) else None)
                if k is None and isinstance(k_obj, dict): k = k_obj
                
                v = v_obj.get("value") if (isinstance(v_obj, dict) and "value" in v_obj) else v_obj
                if isinstance(v, dict): v = parse_kos(v)
                if k is not None: result[str(k).strip().lower()] = v
        return result
    processed = {}
    for k, v in data.items():
        if k == "$type": continue
        processed[str(k).lower()] = parse_kos(v) if isinstance(v, dict) else v
    return processed

def get_shuttle_telemetry():
    variants = ["telemetry_shuttle_A.json", "telemetry_shuttle_B.json"]
    latest_path, latest_mtime = None, 0
    for v in variants:
        p = os.path.join(BASE_DIR, v)
        if os.path.exists(p):
            try:
                mtime = os.path.getmtime(p)
                if mtime > latest_mtime:
                    latest_mtime, latest_path = mtime, p
            except: pass
    if not latest_path: return None, None, 0
    try:
        with open(latest_path, "r", encoding="utf-8") as f:
            content = f.read().strip()
            if not content: return None, latest_path, 0
            raw = json.loads(content)
            parsed = parse_kos(raw)
            age = round(time.time() - latest_mtime, 1)
            return parsed, latest_path, age
    except Exception as e:
        return None, latest_path, 0

def upload(data):
    try:
        clean = sanitize_data(data)
        url = f"{FIREBASE_URL}missions/{MISSION_ID}/shuttle.json"
        r = session.put(url, json=clean, timeout=5)
        return r.status_code == 200
    except Exception:
        return False

last_print, uploads_ok, uploads_fail, last_upload = 0, 0, 0, 0

while True:
    data, path, age = get_shuttle_telemetry()
    if data:
        now = time.time()
        if now - last_upload >= 0.5:
            if upload(data): uploads_ok += 1
            else: uploads_fail += 1
            last_upload = now

        if time.time() - last_print > 1:
            alt = data.get("alt", 0)
            aoa = data.get("aoa", 0)
            vel = data.get("vel", 0)
            status = data.get("status", "?")
            file_short = os.path.basename(path) if path else "?"
            stale_tag = f" [DATOS VIEJOS: {age}s]" if age > 5 else ""
            print(f"\r[OK:{uploads_ok} ERR:{uploads_fail}] Alt:{alt:.0f}m | Vel:{vel:.1f}m/s | AoA:{aoa:.1f}° | Status:{status} | [{file_short}]{stale_tag}    ", end="")
            last_print = time.time()
    else:
        if time.time() - last_print > 2:
            print(f"\r .. Esperando shuttle .. (Ejecuta shuttle.ks en KSP)                          ", end="")
            last_print = time.time()
    time.sleep(0.1)
