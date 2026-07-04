import sys
import os

# Directorio base de los scripts
BASE_DIR = r"C:\Users\olano\OneDrive\Desktop\Kerbal Space Program\Ships\Script"

# Asegurar que los paquetes de Python 3.14 sean encontrados
_site_packages = r"C:\Users\olano\AppData\Local\Python\pythoncore-3.14-64\Lib\site-packages"
if os.path.isdir(_site_packages) and _site_packages not in sys.path:
    sys.path.insert(0, _site_packages)

import http.server
import socketserver
import json
import time
import io
import threading

# --- CONTROL DE LANZAMIENTO (COUNTDOWN & HOLDS) ---
countdown_lock = threading.Lock()
countdown_state = {
    "t_minus": 15,
    "payload_tons": 0.0,
    "status": "READY"
}

def load_initial_config():
    global countdown_state
    cfg_file = os.path.join(BASE_DIR, "boot", "PreLanzamiento", "launch_config.txt")
    if os.path.exists(cfg_file):
        try:
            with open(cfg_file, "r") as f:
                for line in f:
                    if "=" in line:
                        k, v = line.split("=", 1)
                        k, v = k.strip(), v.strip()
                        if k == "t_minus":
                            countdown_state["t_minus"] = int(v)
                        elif k == "payload_tons":
                            countdown_state["payload_tons"] = float(v)
                        elif k == "status":
                            countdown_state["status"] = v
            print(f"[OK] Configuración de lanzamiento inicial cargada: T-{countdown_state['t_minus']}s, Status={countdown_state['status']}")
        except Exception as e:
            print(f"[!] Error cargando configuración inicial de lanzamiento: {e}")

last_config_mtime = 0

def save_config_to_file():
    global last_config_mtime
    cfg_file = os.path.join(BASE_DIR, "boot", "PreLanzamiento", "launch_config.txt")
    tmp_file = cfg_file + ".tmp"
    os.makedirs(os.path.dirname(cfg_file), exist_ok=True)
    try:
        # Escritura atómica: escribir en .tmp y luego renombrar
        # Así kOS nunca ve un archivo a medio escribir (Sharing Violation)
        with open(tmp_file, "w") as f:
            f.write(f"t_minus={countdown_state['t_minus']}\n")
            f.write(f"payload_tons={countdown_state['payload_tons']}\n")
            f.write(f"status={countdown_state['status']}\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_file, cfg_file)  # Atómico en NTFS dentro del mismo drive
        try:
            last_config_mtime = os.path.getmtime(cfg_file)
        except:
            pass
    except Exception as e:
        print(f"[!] Error escribiendo launch_config.txt: {e}")



# --- CAPTURA DE PANTALLA (Pillow + Win32) ---
try:
    from PIL import ImageGrab, Image
    PIL_AVAILABLE = True
    print("[OK] Pillow disponible: captura de cámara activa.")
except ImportError:
    PIL_AVAILABLE = False
    print("[!] Pillow no encontrado. Instala con: pip install pillow")
    print("    La cámara en vivo no estará disponible.")

try:
    import win32gui
    import win32ui
    import win32con
    import ctypes
    WIN32_AVAILABLE = True
    # Declarar el proceso como DPI-aware para obtener coordenadas y tamaños de ventana físicos reales
    try:
        ctypes.windll.user32.SetProcessDPIAware()
    except Exception as e:
        print(f"[!] No se pudo activar DPI-awareness: {e}")
except ImportError:
    WIN32_AVAILABLE = False

def capture_camera_frame(quality=90):
    """Captura la ventana de KSP o OfCourseIStillLoveYou en segundo plano usando PrintWindow."""
    if not PIL_AVAILABLE:
        return None
    
    try:
        # 1. Buscar la ventana activa visible
        hwnd = None
        
        # Buscar ventanas en orden de prioridad
        if WIN32_AVAILABLE:
            # 1. Aerocam (cápsula con cámara embarcada)
            def enum_priority(h, _):
                nonlocal hwnd
                title = win32gui.GetWindowText(h)
                t = title.upper()
                if ('AEROCAM' in t or 'CAPSULA' in t) and win32gui.IsWindowVisible(h):
                    hwnd = h
            win32gui.EnumWindows(enum_priority, None)

            # 2. OfCourseIStillLoveYou
            if not hwnd:
                def enum_ocisly(h, _):
                    nonlocal hwnd
                    title = win32gui.GetWindowText(h)
                    if 'OfCourseIStillLoveYou' in title and win32gui.IsWindowVisible(h):
                        hwnd = h
                win32gui.EnumWindows(enum_ocisly, None)

            # 3. Kerbal Space Program
            if not hwnd:
                def enum_ksp(h, _):
                    nonlocal hwnd
                    title = win32gui.GetWindowText(h)
                    if 'Kerbal Space Program' in title and win32gui.IsWindowVisible(h):
                        hwnd = h
                win32gui.EnumWindows(enum_ksp, None)

        # Si no hay APIs de Win32 o no encontramos ventana, devolver None (sin señal)
        if not hwnd or not WIN32_AVAILABLE:
            return None

        # 2. Captura de segundo plano usando PrintWindow y Device Contexts
        rect = win32gui.GetWindowRect(hwnd)
        w = rect[2] - rect[0]
        h = rect[3] - rect[1]

        if w <= 0 or h <= 0:
            raise ValueError("Window dimensions are invalid")

        hwndDC = win32gui.GetWindowDC(hwnd)
        mfcDC  = win32ui.CreateDCFromHandle(hwndDC)
        saveDC = mfcDC.CreateCompatibleDC()

        saveBitMap = win32ui.CreateBitmap()
        saveBitMap.CreateCompatibleBitmap(mfcDC, w, h)
        saveDC.SelectObject(saveBitMap)

        # Flag 2 = PW_RENDERFULLCONTENT (Captura contenido acelerado por hardware/DirectX en Win10/11)
        result = ctypes.windll.user32.PrintWindow(hwnd, saveDC.GetSafeHdc(), 2)
        if result == 0:
            # Fallback a PrintWindow estándar (0) si falla
            ctypes.windll.user32.PrintWindow(hwnd, saveDC.GetSafeHdc(), 0)

        bmpinfo = saveBitMap.GetInfo()
        bmpstr = saveBitMap.GetBitmapBits(True)
        img = Image.frombuffer('RGB', (bmpinfo['bmWidth'], bmpinfo['bmHeight']), bmpstr, 'raw', 'BGRX', 0, 1)

        # Limpiar objetos GDI inmediatamente
        win32gui.DeleteObject(saveBitMap.GetHandle())
        saveDC.DeleteDC()
        mfcDC.DeleteDC()
        win32gui.ReleaseDC(hwnd, hwndDC)

        # Redimensionar la imagen para optimizar el peso del stream
        img = img.resize((1280, 720), Image.LANCZOS)

        buf = io.BytesIO()
        img.save(buf, format='JPEG', quality=quality, optimize=True)
        buf.seek(0)
        return buf.read()

    except Exception as e:
        print(f"[!] Fallo en captura en segundo plano ({e})")
        return None

PORT = 9090

# --- FIREBASE INTEGRATION ---
FIREBASE_CREDS = os.path.join(BASE_DIR, "tomcat-firebase-creds.json")
FIREBASE_DB_URL = "https://tomcat-b9bdb-default-rtdb.firebaseio.com/"
FIREBASE_STORAGE_BUCKET = "tomcat-b9bdb.firebasestorage.app"

FIREBASE_AVAILABLE = False
fb_db = None
fb_bucket = None
_camera_last_upload = 0

if os.path.exists(FIREBASE_CREDS):
    try:
        import firebase_admin
        from firebase_admin import credentials, db, storage
        cred = credentials.Certificate(FIREBASE_CREDS)
        firebase_admin.initialize_app(cred, {
            'databaseURL': FIREBASE_DB_URL,
            'storageBucket': FIREBASE_STORAGE_BUCKET
        })
        fb_db = db
        fb_bucket = storage.bucket()
        FIREBASE_AVAILABLE = True
        print("[OK] Firebase conectado: RTDB + Storage")
    except Exception as e:
        print(f"[!] Firebase no disponible: {e}")
else:
    print("[!] Credenciales Firebase no encontradas. Ignorando.")

def push_telemetry_to_firebase(combined=None):
    if not FIREBASE_AVAILABLE:
        return
    try:
        if combined is None:
            ship_data = get_latest_telemetry("ship", check_stale=False)
            booster_data = get_latest_telemetry("booster", check_stale=False)
            combined = {
                "ship": ship_data,
                "booster": booster_data,
                "server_time": time.time()
            }
        fb_db.reference('/telemetry').set(combined)
        with countdown_lock:
            fb_db.reference('/countdown').set(countdown_state)
    except Exception as e:
        print(f"[!] Error subiendo telemetría a Firebase: {e}")

def push_camera_to_firebase(frame_bytes):
    global _camera_last_upload
    now = time.time()
    if now - _camera_last_upload < 5.0:
        return
    if not FIREBASE_AVAILABLE:
        return
    try:
        import base64
        # Guardar como Base64 en RTDB (funciona siempre, sin necesidad de Storage)
        b64 = base64.b64encode(frame_bytes).decode()
        fb_db.reference('/camera').set({
            'frame_b64': b64,
            'updated': now
        })
        _camera_last_upload = now
    except Exception as e:
        print(f"[!] Error subiendo cámara a Firebase: {e}")

def get_latest_telemetry(prefix, check_stale=True):
    """Busca el archivo más reciente (A o B) para un prefijo dado."""
    file_a = os.path.join(BASE_DIR, f"telemetry_{prefix}_A.json")
    file_b = os.path.join(BASE_DIR, f"telemetry_{prefix}_B.json")
    
    latest_file = None
    latest_time = 0
    
    for f in [file_a, file_b]:
        if os.path.exists(f):
            mtime = os.path.getmtime(f)
            if mtime > latest_time:
                latest_time = mtime
                latest_file = f
    
    if latest_file:
        if check_stale and time.time() - latest_time > 5.0:
            return None

        try:
            with open(latest_file, 'r', encoding='utf-8') as f:
                raw_data = json.load(f)
                return parse_kos_json(raw_data)
        except:
            return None
    return None

def parse_kos_json(data):
    """Convierte Lexicons de kOS a diccionarios de Python (Ultra-Robust)."""
    if not isinstance(data, dict):
        return data
    
    # Si tiene la estructura de Lexicon de kOS
    if "entries" in data:
        result = {}
        entries = data["entries"]
        
        # Formato Moderno: [{"key": {"value": "..."}, "value": {"value": "..."}}, ...]
        if len(entries) > 0 and isinstance(entries[0], dict) and "key" in entries[0]:
            for item in entries:
                k_obj = item.get("key", {})
                v_obj = item.get("value", {})
                # Extraer valor real (puede ser un escalar o otro Lexicon)
                k = k_obj.get("value") if isinstance(k_obj, dict) else k_obj
                v = v_obj.get("value") if isinstance(v_obj, dict) else v_obj
                
                # Recursividad para Lexicons anidados
                if isinstance(v, dict) and "entries" in v:
                    v = parse_kos_json(v)
                
                if k is not None:
                    result[str(k)] = v
        
        # Formato Antiguo: [{"value": "key"}, {"value": "val"}, ...]
        else:
            for i in range(0, len(entries), 2):
                if i + 1 < len(entries):
                    k_obj = entries[i]
                    v_obj = entries[i+1]
                    k = k_obj.get("value") if isinstance(k_obj, dict) else k_obj
                    v = v_obj if (isinstance(v_obj, dict) and "entries" in v_obj) else (v_obj.get("value") if isinstance(v_obj, dict) else v_obj)
                    
                    if isinstance(v, dict) and "entries" in v:
                        v = parse_kos_json(v)
                    
                    if k is not None:
                        result[str(k)] = v
        return result
    
    # Si no es un Lexicon pero es un dict, procesar sus campos
    return {k: parse_kos_json(v) for k, v in data.items()}

class ThreadedTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    """Servidor HTTP multi-hilo: cada request se maneja en su propio thread."""
    daemon_threads = True
    allow_reuse_address = True

class TelemetryHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'X-Requested-With, Content-type, ngrok-skip-browser-warning')
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

    def do_GET(self):
        if self.path == '/remote':
            self.send_response(200)
            self.send_header('Content-type', 'text/html; charset=utf-8')
            self.end_headers()
            html_path = os.path.join(BASE_DIR, "tomcat-remote.html")
            if os.path.exists(html_path):
                with open(html_path, 'rb') as f:
                    self.wfile.write(f.read())
            else:
                self.wfile.write(b"<h1>Remote Dashboard not found</h1>")

        elif self.path == '/' or self.path == '/tomcat':
            self.send_response(200)
            self.send_header('Content-type', 'text/html; charset=utf-8')
            self.end_headers()
            html_path = os.path.join(BASE_DIR, "tomcat.html")
            if os.path.exists(html_path):
                with open(html_path, 'rb') as f:
                    self.wfile.write(f.read())
            else:
                self.wfile.write(b"<h1>Tomcat Dashboard file not found</h1>")
        
        elif self.path.startswith('/api/telemetry'):
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            
            ship_data = get_latest_telemetry("ship")
            booster_data = get_latest_telemetry("booster")
            combined = {
                "ship": ship_data,
                "booster": booster_data,
                "server_time": time.time()
            }
            self.wfile.write(json.dumps(combined).encode())

            # Push a Firebase (en segundo plano)
            if FIREBASE_AVAILABLE:
                threading.Thread(target=push_telemetry_to_firebase, args=(combined,), daemon=True).start()

        elif self.path.startswith('/api/camera'):
            frame = capture_camera_frame(quality=90) if PIL_AVAILABLE else None
            if frame:
                self.send_response(200)
                self.send_header('Content-type', 'image/jpeg')
                self.send_header('Content-Length', str(len(frame)))
                self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate')
                self.end_headers()
                self.wfile.write(frame)

                # Push a Firebase Storage (máx 1 frame cada 5s)
                if FIREBASE_AVAILABLE:
                    threading.Thread(target=push_camera_to_firebase, args=(frame,), daemon=True).start()
            else:
                # Devolver JSON de error si no hay captura disponible
                self.send_response(503)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"error": "Camera unavailable. Install Pillow: pip install pillow"}).encode())

        elif self.path.startswith('/api/camera_status'):
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            status = {
                "pil_available": PIL_AVAILABLE,
                "win32_available": WIN32_AVAILABLE,
                "firebase_available": FIREBASE_AVAILABLE
            }
            self.wfile.write(json.dumps(status).encode())

        elif self.path.startswith('/api/launch_control') and not self.path.startswith('/api/launch_control/command'):
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            with countdown_lock:
                self.wfile.write(json.dumps(countdown_state).encode())

        elif self.path.startswith('/api/launch_control/command'):
            from urllib.parse import urlparse, parse_qs
            query = parse_qs(urlparse(self.path).query)
            cmd = query.get('cmd', [''])[0]
            val = query.get('val', [''])[0]
            
            with countdown_lock:
                if cmd == 'start':
                    countdown_state['status'] = 'COUNTDOWN'
                elif cmd == 'hold':
                    countdown_state['status'] = 'HOLD'
                elif cmd == 'resume':
                    countdown_state['status'] = 'COUNTDOWN'
                elif cmd == 'abort':
                    countdown_state['status'] = 'ABORT'
                elif cmd == 'reset':
                    countdown_state['status'] = 'READY'
                    if val:
                        countdown_state['t_minus'] = int(val)
                elif cmd == 'set_t':
                    countdown_state['t_minus'] = int(val)
                elif cmd == 'set_payload':
                    countdown_state['payload_tons'] = float(val)
                
                save_config_to_file()
                
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            with countdown_lock:
                self.wfile.write(json.dumps(countdown_state).encode())

        else:
            super().do_GET()

def main():
    global last_config_mtime
    print(f"=========================================")
    print(f"     CENTRO DE TELEMETRÍA PREMIMUM")
    print(f"=========================================")
    print(f"[*] Firebase:    {'CONECTADO' if FIREBASE_AVAILABLE else 'NO DISPONIBLE'}")
    
    # Cargar mtime inicial
    cfg_file = os.path.join(BASE_DIR, "boot", "PreLanzamiento", "launch_config.txt")
    if os.path.exists(cfg_file):
        try:
            last_config_mtime = os.path.getmtime(cfg_file)
        except:
            pass

    # Hilo para procesar el countdown segundo a segundo
    def bg_countdown():
        global countdown_state
        while True:
            time.sleep(1.0)
            with countdown_lock:
                status = countdown_state["status"]
                if status == "COUNTDOWN":
                    if countdown_state["t_minus"] > 0:
                        countdown_state["t_minus"] -= 1
                    else:
                        countdown_state["status"] = "LAUNCHED"
                    save_config_to_file()
                elif status in ["READY", "HOLD", "ABORT", "LAUNCHED"]:
                    save_config_to_file()

    threading.Thread(target=bg_countdown, daemon=True).start()
    print("[*] Hilo de control de lanzamiento web activo")

    # Hilo para escribir launch_data.js y detectar cambios manuales
    def bg_local_js():
        global last_config_mtime, countdown_state
        while True:
            try:
                # 1. Detectar cambios manuales del usuario en el txt
                if os.path.exists(cfg_file):
                    mtime = os.path.getmtime(cfg_file)
                    if mtime > last_config_mtime:
                        time.sleep(0.05)  # Evitar lectura a medio escribir
                        with countdown_lock:
                            with open(cfg_file, "r") as f:
                                for line in f:
                                    if "=" in line:
                                        k, v = line.split("=", 1)
                                        k, v = k.strip(), v.strip()
                                        if k == "t_minus":
                                            countdown_state["t_minus"] = int(v)
                                        elif k == "payload_tons":
                                            countdown_state["payload_tons"] = float(v)
                                        elif k == "status":
                                            countdown_state["status"] = v
                            last_config_mtime = os.path.getmtime(cfg_file)

                # 2. Escribir launch_data.js
                ship_data = get_latest_telemetry("ship", check_stale=True)
                booster_data = get_latest_telemetry("booster", check_stale=True)
                combined = {
                    "ship": ship_data,
                    "booster": booster_data,
                    "launch_control": {
                        "t_minus": countdown_state["t_minus"],
                        "payload_tons": countdown_state["payload_tons"],
                        "status": countdown_state["status"]
                    },
                    "server_time": time.time()
                }
                js_content = f"window.tomcatData = {json.dumps(combined, indent=2)};\n"
                js_file = os.path.join(BASE_DIR, "launch_data.js")
                tmp_file = js_file + ".tmp"
                with open(tmp_file, "w", encoding="utf-8") as f:
                    f.write(js_content)
                    f.flush()
                    os.fsync(f.fileno())
                os.replace(tmp_file, js_file)
            except Exception as e:
                pass
            time.sleep(0.2)

    threading.Thread(target=bg_local_js, daemon=True).start()
    print("[*] Hilo local launch_data.js activo (Soporte Offline)")

    # Hilo para capturar cámara y guardarla en live_camera.jpg
    def bg_camera():
        while True:
            try:
                frame = capture_camera_frame(quality=70)
                if frame:
                    # Guardar localmente para modo offline
                    cam_file = os.path.join(BASE_DIR, "live_camera.jpg")
                    tmp_file = cam_file + ".tmp"
                    with open(tmp_file, "wb") as f:
                        f.write(frame)
                        f.flush()
                        os.fsync(f.fileno())
                    os.replace(tmp_file, cam_file)
                    
                    if FIREBASE_AVAILABLE:
                        push_camera_to_firebase(frame)
            except:
                pass
            time.sleep(0.5)

    threading.Thread(target=bg_camera, daemon=True).start()
    print("[*] Hilo de cámara en vivo activo (escribiendo live_camera.jpg)")

    # Hilos opcionales de Firebase
    if FIREBASE_AVAILABLE:
        def bg_push():
            while True:
                try:
                    # Preparar combined
                    ship_data = get_latest_telemetry("ship", check_stale=True)
                    booster_data = get_latest_telemetry("booster", check_stale=True)
                    combined = {
                        "ship": ship_data,
                        "booster": booster_data,
                        "server_time": time.time()
                    }
                    push_telemetry_to_firebase(combined)
                except:
                    pass
                time.sleep(2)
        threading.Thread(target=bg_push, daemon=True).start()
        print("[*] Push automático a Firebase cada 2s activado")

    # Iniciar servidor local si el puerto está libre
    server_running = False
    try:
        httpd = ThreadedTCPServer(("0.0.0.0", PORT), TelemetryHandler)
        print(f"[*] Servidor corriendo en el puerto {PORT}")
        import socket
        try:
            hostname = socket.gethostname()
            local_ip = socket.gethostbyname(hostname)
            print(f"[*] Acceso Local: http://localhost:{PORT}")
            print(f"[*] Acceso Red:  http://{local_ip}:{PORT}")
        except:
            pass
        server_running = True
    except OSError as e:
        print(f"\n[!] AVISO: Puerto {PORT} ocupado. Iniciando en MODO LOCAL / PORTLESS.")
        print(f"    Podes abrir 'tomcat.html' haciendo doble clic directamente en el archivo.")
        print(f"    Los comandos se controlan editando 'launch_config.txt' o mediante los archivos .bat\n")

    if server_running:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nServidor apagado.")
    else:
        # Si el servidor no corre, mantener el script vivo para los hilos de fondo
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            print("\nServidor apagado.")

if __name__ == "__main__":
    main()
