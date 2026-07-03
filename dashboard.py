import json
import time
import os

# Ruta al archivo de telemetría de kOS
PATH = r"C:\Users\olano\OneDrive\Desktop\Kerbal Space Program\Ships\Script\telemetry_stage2.json"

def parse_kos_json(raw_data):
    """Convierte el formato 'Lexicon' de kOS a un diccionario de Python normal."""
    result = {}
    try:
        entries = raw_data.get("entries", [])
        # kOS guarda los Lexicon como una lista plana: [llave, valor, llave, valor...]
        # Cada elemento es un objeto con la propiedad 'value'
        for i in range(0, len(entries), 2):
            key = entries[i].get("value")
            val = entries[i+1].get("value")
            result[key] = val
    except:
        pass
    return result

def main():
    print("========================================")
    print("   INICIANDO DASHBOARD DE TELEMETRÍA")
    print("========================================")
    print(f"Buscando archivo en: {PATH}")
    
    last_time = -1
    
    while True:
        try:
            if not os.path.exists(PATH):
                print(f"Esperando archivo... (Asegúrate de que kOS esté enviando datos)  ", end="\r")
            else:
                with open(PATH, 'r', encoding='utf-8') as f:
                    content = f.read()
                    if not content or len(content) < 10:
                        continue
                    
                    raw_json = json.loads(content)
                    # Convertir el formato raro de kOS a algo usable
                    data = parse_kos_json(raw_json)
                
                current_time = data.get('time', last_time)
                
                if current_time != last_time:
                    os.system('cls' if os.name == 'nt' else 'clear')
                    print("========================================")
                    print("   DATOS RECIBIDOS EN TIEMPO REAL")
                    print("========================================")
                    print(f" ALTITUD:    {data.get('alt', 0)} m")
                    print(f" VELOCIDAD:  {data.get('vel', 0)} m/s")
                    print(f" Delta-V:    {data.get('dv', 0)} m/s")
                    print(f" PERIAPSIDE: {data.get('per', 0)} m")
                    print(f" APOAPSIDE:  {data.get('apo', 0)} m")
                    print("========================================")
                    print(f" STATUS: {data.get('status', '---')} | MODO: {data.get('mode', 0)} | T+{current_time}s")
                    print("========================================")
                    print(" [Dashboard activo. Pulsa Ctrl+C para salir]")
                    last_time = current_time
            
        except (PermissionError, json.JSONDecodeError):
            pass
        except Exception as e:
            # print(f"Debug: {e}") # Para depuración
            pass
            
        time.sleep(0.1)

if __name__ == "__main__":
    main()
