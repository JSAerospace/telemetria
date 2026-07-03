import tkinter as tk
from tkinter import ttk, messagebox
import json
import os
import math
import traceback
import time
from datetime import datetime

# --- CONFIGURACIÓN ---
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_NAME_SHIP = "telemetry_ship"
BASE_NAME_BOOSTER = "telemetry_booster"
UPDATE_RATE_MS = 500 

class MissionControlApp:
    def __init__(self, root):
        self.root = root
        self.root.title("ASOS MISSION CONTROL - SPACEX STYLE")
        self.root.geometry("1200x820")
        self.root.configure(bg="#05070a")

        self.font_title = ("Arial", 16, "bold")
        self.font_label = ("Arial", 10)
        self.font_data = ("Courier", 20, "bold")

        # --- CONTENEDOR PRINCIPAL ---
        self.main_frame = tk.Frame(self.root, bg="#05070a")
        self.main_frame.pack(fill="both", expand=True, padx=25, pady=20)

        self.ship_panel = self.create_stage_panel(self.main_frame, "STAGE 2: SHIP", 0, ["S1"])
        self.booster_panel = self.create_stage_panel(self.main_frame, "STAGE 1: BOOSTER", 1, 
                                                    ["R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8", "C1", "C2", "C3"],
                                                    has_fuel=True)

        # Footer de Diagnóstico
        self.footer = tk.Frame(self.root, bg="#111", height=120)
        self.footer.pack(side="bottom", fill="x")
        
        self.col1 = tk.Frame(self.footer, bg="#111")
        self.col1.pack(side="left", padx=20, fill="y")
        self.diag_ship = tk.Label(self.col1, text="SHIP: BUSCANDO...", bg="#111", fg="#f1c40f", font=("Arial", 9))
        self.diag_ship.pack(anchor="w")
        self.diag_booster = tk.Label(self.col1, text="BOOSTER: BUSCANDO...", bg="#111", fg="#f1c40f", font=("Arial", 9))
        self.diag_booster.pack(anchor="w")

        self.col2 = tk.Frame(self.footer, bg="#111")
        self.col2.pack(side="left", padx=20, fill="both", expand=True)
        tk.Label(self.col2, text="ENGINE TAGS DETECTADOS:", bg="#111", fg="#7f8c8d", font=("Arial", 8, "bold")).pack(anchor="w")
        self.engine_tags_label = tk.Label(self.col2, text="NINGUNO", bg="#111", fg="#555", font=("Courier", 11), wraplength=500, justify="left")
        self.engine_tags_label.pack(anchor="w")

        self.col3 = tk.Frame(self.footer, bg="#111")
        self.col3.pack(side="right", padx=20, fill="y")
        self.last_update_label = tk.Label(self.col3, text="SISTEMA LISTO", bg="#111", fg="#7f8c8d", font=("Arial", 9))
        self.last_update_label.pack(pady=5)
        
        self.test_mode_active = False
        self.test_btn = tk.Button(self.col3, text="PROBAR GUI (TEST)", bg="#222", fg="#555", borderwidth=0, command=self.toggle_test)
        self.test_btn.pack()

        self.update_telemetry()

    def toggle_test(self):
        self.test_mode_active = not self.test_mode_active
        self.test_btn.config(fg="#39ff14" if self.test_mode_active else "#555")

    def create_stage_panel(self, parent, title, col, tag_list, has_fuel=False):
        frame = tk.LabelFrame(parent, text=title, bg="#05070a", fg="#00f2ff", font=self.font_title, padx=20, pady=20, borderwidth=1, relief="flat")
        frame.grid(row=0, column=col, sticky="nsew", padx=15)
        parent.columnconfigure(col, weight=1)

        fields = ["ALTITUD", "VELOCIDAD", "APOAPSIS", "PERIAPSIS"]
        if has_fuel: fields.append("LIQ FUEL")
        fields.append("STATUS")

        vars = {}
        for i, name in enumerate(fields):
            tk.Label(frame, text=name, bg="#05070a", fg="#7f8c8d", font=self.font_label).grid(row=i, column=0, sticky="w", pady=2)
            v = tk.StringVar(value="---")
            tk.Label(frame, textvariable=v, bg="#05070a", fg="white", font=self.font_data).grid(row=i, column=1, sticky="e", padx=25)
            vars[name.lower().replace(" ", "")] = v
            
        tk.Label(frame, text="ENGINE CLUSTER HEALTH", bg="#05070a", fg="#7f8c8d", font=self.font_label).grid(row=len(fields), column=0, sticky="w", pady=(35,0))
        canvas = tk.Canvas(frame, width=240, height=240, bg="#05070a", highlightthickness=0)
        canvas.grid(row=len(fields)+1, column=0, columnspan=2, pady=20)
        
        engine_map = {}
        cx, cy = 120, 120
        if len(tag_list) == 1:
            e = canvas.create_oval(cx-45, cy-45, cx+45, cy+45, fill="#1a2634", outline="#333", width=2)
            engine_map[tag_list[0]] = e
            canvas.create_text(cx, cy, text=tag_list[0], fill="#333", font=("Arial", 10, "bold"))
        else:
            for i in range(8):
                angle = math.radians(i * 45 - 90)
                px = cx + 85 * math.cos(angle)
                py = cy + 85 * math.sin(angle)
                tag = f"R{i+1}"
                e = canvas.create_oval(px-15, py-15, px+15, py+15, fill="#1a2634", outline="#222", width=1)
                engine_map[tag] = e
                canvas.create_text(px, py, text=tag, fill="#333", font=("Arial", 7))
            
            for i in range(3):
                angle = math.radians(i * 120 - 90)
                px = cx + 30 * math.cos(angle)
                py = cy + 30 * math.sin(angle)
                tag = f"C{i+1}"
                e = canvas.create_oval(px-18, py-18, px+18, py+18, fill="#1a2634", outline="#222", width=1)
                engine_map[tag] = e
                canvas.create_text(px, py, text=tag, fill="#333", font=("Arial", 8))

        return {"vars": vars, "canvas": canvas, "engine_map": engine_map}

    def safe_num(self, val, unit=" m"):
        try:
            f_val = float(val)
            if f_val < -2000000 or f_val > 5000000000: return "---"
            return f"{int(f_val):,} {unit}".strip()
        except: return str(val)

    def parse_kos_json(self, base_name, diag_lbl):
        # Ping-Pong System: look for _A, _B, and original name
        candidates = [
            os.path.join(BASE_DIR, base_name + "_A.json"),
            os.path.join(BASE_DIR, base_name + "_B.json"),
            os.path.join(BASE_DIR, base_name + ".json"),
            os.path.join(BASE_DIR, base_name)
        ]
        
        target = None
        for p in candidates:
            if os.path.exists(p) and os.path.getsize(p) > 2:
                if not target or os.path.getmtime(p) > os.path.getmtime(target): 
                    target = p
        
        if not target:
            diag_lbl.config(text=f"{base_name.upper()}: NO EXISTE", fg="#e74c3c")
            return None

        # Extremely fast read with retry logic for Windows
        raw = None
        for _ in range(5):
            try:
                with open(target, 'r', encoding='utf-8', errors='ignore') as f:
                    raw = json.load(f)
                break
            except (json.JSONDecodeError, PermissionError, IOError):
                time.sleep(0.2)
        
        if not raw:
            diag_lbl.config(text=f"{base_name.upper()}: ERROR", fg="#e67e22")
            return None

        diag_lbl.config(text=f"{base_name.upper()}: CONECTADO", fg="#39ff14")
        
        def flatten(data):
            if isinstance(data, dict):
                if "entries" in data:
                    res = {}
                    ent = data.get("entries", [])
                    for i in range(0, len(ent) - 1, 2):
                        k_node = ent[i]
                        k = str(k_node.get("value", "UNKNOWN")).upper().strip()
                        v_node = ent[i+1]
                        v = v_node.get("value") if "value" in v_node else v_node
                        res[k] = flatten(v)
                    return res
                return {str(k).upper().strip(): flatten(v) for k, v in data.items()}
            return data

        return flatten(raw)

    def update_telemetry(self):
        try:
            all_tags_found = set()
            # SHIP
            d = self.parse_kos_json(BASE_NAME_SHIP, self.diag_ship)
            if self.test_mode_active: d = {'ENGSTATES': {'S1': 1}, 'ALT': 150000, 'VEL': 2800, 'STATUS': 'ORBIT'}
            if d:
                v = self.ship_panel["vars"]
                v["altitud"].set(self.safe_num(d.get('ALT', 0)) + " m")
                v["velocidad"].set(self.safe_num(d.get('VEL', 0)) + " m/s")
                v["apoapsis"].set(self.safe_num(d.get('APO', 0)) + " m")
                v["periapsis"].set(self.safe_num(d.get('PER', 0)) + " m")
                v["status"].set(str(d.get('STATUS', '---')))
                st = d.get('ENGSTATES', {})
                if st:
                    self.update_engines(self.ship_panel, st)
                    all_tags_found.update(st.keys())

            # BOOSTER
            d = self.parse_kos_json(BASE_NAME_BOOSTER, self.diag_booster)
            if self.test_mode_active: d = {'ENGSTATES': {'R1':1,'R2':1,'C1':1}, 'ALT': 15000, 'FUEL': 400, 'STATUS': 'LANDING'}
            if d:
                v = self.booster_panel["vars"]
                v["altitud"].set(self.safe_num(d.get('ALT', 0)) + " m")
                v["velocidad"].set(self.safe_num(d.get('VEL', 0)) + " m/s")
                v["apoapsis"].set(self.safe_num(d.get('APO', 0)) + " m")
                v["periapsis"].set(self.safe_num(d.get('PER', 0)) + " m")
                v["liqfuel"].set(self.safe_num(d.get('FUEL', 0), unit=" L"))
                v["status"].set(str(d.get('STATUS', '---')))
                st = d.get('ENGSTATES', {})
                if st:
                    self.update_engines(self.booster_panel, st)
                    all_tags_found.update(st.keys())

            if all_tags_found:
                self.engine_tags_label.config(text=", ".join(sorted(all_tags_found)), fg="#39ff14")
            else:
                self.engine_tags_label.config(text="NINGUNO", fg="#e74c3c")

            self.last_update_label.config(text=f"ACTUALIZADO: {datetime.now().strftime('%H:%M:%S')}")
        except Exception as e: pass
        self.root.after(UPDATE_RATE_MS, self.update_telemetry)

    def update_engines(self, panel, states):
        if not isinstance(states, dict): return
        for tag, e_id in panel["engine_map"].items():
            state = states.get(tag.upper(), 0)
            is_active = str(state) == "1" or state == 1
            color = "#39ff14" if is_active else "#1a2634"
            panel["canvas"].itemconfig(e_id, fill=color)

if __name__ == "__main__":
    try:
        root = tk.Tk()
        app = MissionControlApp(root)
        root.mainloop()
    except Exception as e:
        with open("crash_report.txt", "w") as f: f.write(traceback.format_exc())
