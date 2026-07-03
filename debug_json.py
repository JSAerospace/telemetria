import json
import os

BASE_DIR = r"C:\Users\olano\OneDrive\Desktop\Kerbal Space Program\Ships\Script"

def analyze_file(prefix):
    f_a = os.path.join(BASE_DIR, f"telemetry_{prefix}_A.json")
    f_b = os.path.join(BASE_DIR, f"telemetry_{prefix}_B.json")
    
    target = None
    if os.path.exists(f_a): target = f_a
    elif os.path.exists(f_b): target = f_b
    
    if target:
        try:
            with open(target, 'r') as f:
                data = json.load(f)
                print(f"--- {prefix.upper()} DATA STRUCTURE ---")
                print(json.dumps(data, indent=2))
        except:
            print(f"Error reading {target}")
    else:
        print(f"No file found for {prefix}")

analyze_file("ship")
analyze_file("booster")
input("Press Enter...")
