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

        self.ship_panel = self.create_stage_panel(self.main_frame, "STAGE 2: SHIP", 0, ["S1"], has_fuel=True)
        self.booster_panel = self.create_stage_panel(self.main_frame, "STAGE 1: BOOSTER", 1, 
                                                    ["R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8", "C1", "C2", "C3"],
                                                    has_fuel=True)

        # Footer de Diagnóstico
        self.footer = tk.Frame(self.root, bg="#0a0c10", height=100)
        self.footer.pack(side="bottom", fill="x")
        
        self.col1 = tk.Frame(self.footer, bg="#0a0c10")
        self.col1.pack(side="left", padx=25, fill="y")
        self.diag_ship = tk.Label(self.col1, text="SHIP [S2]: BUSCANDO...", bg="#0a0c10", fg="#555", font=("Arial", 9, "bold"))
        self.diag_ship.pack(anchor="w", pady=2)
        self.diag_booster = tk.Label(self.col1, text="BOOSTER [S1]: BUSCANDO...", bg="#0a0c10", fg="#555", font=("Arial", 9, "bold"))
        self.diag_booster.pack(anchor="w", pady=2)

        self.col2 = tk.Frame(self.footer, bg="#0a0c10")
        self.col2.pack(side="left", padx=30, fill="both", expand=True)
        tk.Label(self.col2, text="ACTIVE ENGINE CLUSTER STATUS:", bg="#0a0c10", fg="#444", font=("Arial", 8, "bold")).pack(anchor="w")
        self.engine_tags_label = tk.Label(self.col2, text="WAITING FOR SYNC", bg="#0a0c10", fg="#333", font=("Courier", 11, "bold"), wraplength=500, justify="left")
        self.engine_tags_label.pack(anchor="w")

        self.col3 = tk.Frame(self.footer, bg="#0a0c10")
        self.col3.pack(side="right", padx=25, fill="y")
        self.last_update_label = tk.Label(self.col3, text="LINK STATE: OFFLINE", bg="#0a0c10", fg="#444", font=("Arial", 9))
        self.last_update_label.pack(pady=5)
        
        self.test_mode_active = False
        self.test_btn = tk.Button(self.col3, text="SIMULATE FLIGHT", bg="#111", fg="#333", borderwidth=1, relief="flat", padx=10, command=self.toggle_test)
        self.test_btn.pack()

        self.update_telemetry()

    def toggle_test(self):
        self.test_mode_active = not self.test_mode_active
        self.test_btn.config(fg="#00f2ff" if self.test_mode_active else "#333", bg="#1a2634" if self.test_mode_active else "#111")

    def create_stage_panel(self, parent, title, col, tag_list, has_fuel=False):
        frame = tk.LabelFrame(parent, text=title, bg="#05070a", fg="#00f2ff", font=self.font_title, padx=20, pady=20, borderwidth=1, relief="ridge")
        frame.grid(row=0, column=col, sticky="nsew", padx=15)
        parent.columnconfigure(col, weight=1)

        # Campos de Datos COMPLETOS
        fields = ["ALTITUD", "VELOCIDAD", "VS SPEED"]
        if has_fuel: 
            fields.append("THR %")
            fields.append("FUEL %")
            fields.append("H-DIST")
            fields.append("FUEL")
            if "SHIP" in title: fields.append("DELTA-V")
        fields.append("STATUS")

        vars = {}
        row_idx = 0
        for i, name in enumerate(fields):
            tk.Label(frame, text=name, bg="#05070a", fg="#4b5563", font=("Arial", 9, "bold")).grid(row=row_idx, column=0, sticky="w", pady=4)
            v = tk.StringVar(value="---")
            fg_color = "#39ff14" if name == "STATUS" else "white"
            tk.Label(frame, textvariable=v, bg="#05070a", fg=fg_color, font=("Courier", 18, "bold")).grid(row=row_idx, column=1, sticky="e", padx=25)
            
            # Sub-gráfico de barra para Throttle y Fuel %
            if name == "THR %" or name == "FUEL %":
                row_idx += 1
                pb_frame = tk.Frame(frame, bg="#05070a")
                pb_frame.grid(row=row_idx, column=1, sticky="e", padx=25, pady=(0, 10))
                p_var = tk.DoubleVar(value=0)
                color_type = 'determinate.Horizontal.TProgressbar'
                if name == "FUEL %": color_type = 'fuel.Horizontal.TProgressbar'
                
                pb = ttk.Progressbar(pb_frame, variable=p_var, maximum=100, length=120, mode='determinate', style=color_type)
                pb.pack()
                key_pb = "thr_val" if name == "THR %" else "fuel_pct_val"
                vars[key_pb] = p_var
            
            key = name.lower().replace(" ", "").replace("-", "").replace("%", "")
            if name == "FUEL %": key = "fuelpct"
            vars[key] = v
            row_idx += 1
            
        # ENGINE CLUSTER
        tk.Label(frame, text="PROPULSION DIAGNOSTICS", bg="#05070a", fg="#4b5563", font=("Arial", 9, "bold")).grid(row=row_idx, column=0, sticky="w", pady=(30,0))
        row_idx += 1
        canvas = tk.Canvas(frame, width=220, height=220, bg="#020408", highlightthickness=1, highlightbackground="#1a2634")
        canvas.grid(row=row_idx, column=0, columnspan=2, pady=15)
        
        engine_map = {}
        cx, cy = 110, 110
        if len(tag_list) == 1:
            e = canvas.create_oval(cx-40, cy-40, cx+40, cy+40, fill="#0a1016", outline="#1a2634", width=2)
            engine_map[tag_list[0]] = e
            canvas.create_text(cx, cy, text=tag_list[0], fill="#222", font=("Arial", 11, "bold"))
        else:
            # R-Engines (Outer Ring)
            for i in range(8):
                angle = math.radians(i * 45 - 90)
                px = cx + 80 * math.cos(angle)
                py = cy + 80 * math.sin(angle)
                tag = f"R{i+1}"
                e = canvas.create_oval(px-15, py-15, px+15, py+15, fill="#0a1016", outline="#1a2634", width=1)
                engine_map[tag] = e
                canvas.create_text(px, py, text=tag, fill="#222", font=("Arial", 8))
            
            # C-Engines (Inner Cluster)
            for i in range(3):
                angle = math.radians(i * 120 - 90)
                px = cx + 30 * math.cos(angle)
                py = cy + 30 * math.sin(angle)
                tag = f"C{i+1}"
                e = canvas.create_oval(px-20, py-20, px+20, py+20, fill="#0a1016", outline="#1a2634", width=1)
                engine_map[tag] = e
                canvas.create_text(px, py, text=tag, fill="#222", font=("Arial", 9, "bold"))

        return {"vars": vars, "canvas": canvas, "engine_map": engine_map}

    def safe_num(self, val, unit=" m"):
        try:
            f_val = float(val)
            if f_val < -2000000 or f_val > 5000000000: return "---"
            if abs(f_val) < 10 and "m" in unit: return f"{f_val:.1f}{unit}"
            return f"{int(f_val):,}{unit}"
        except: return str(val)

    def parse_kos_json(self, base_name, diag_lbl):
        candidates = [
            os.path.join(BASE_DIR, base_name + "_A.json"),
            os.path.join(BASE_DIR, base_name + "_B.json"),
            os.path.join(BASE_DIR, base_name + ".json")
        ]
        
        target = None
        for p in candidates:
            if os.path.exists(p) and os.path.getsize(p) > 2:
                if not target or os.path.getmtime(p) > os.path.getmtime(target): 
                    target = p
        
        if not target:
            diag_lbl.config(text=f"{base_name.upper()}: SEARCHING...", fg="#444")
            return None

        # Detect staleness (more than 5s)
        if time.time() - os.path.getmtime(target) > 5.0:
            diag_lbl.config(text=f"{base_name.upper()}: STALE", fg="#e67e22")
            return None

        try:
            with open(target, 'r', encoding='utf-8', errors='ignore') as f:
                raw = json.load(f)
        except: return None

        diag_lbl.config(text=f"{base_name.upper()}: LIVE", fg="#00f2ff")
        
        def flatten(data):
            if isinstance(data, dict):
                if "entries" in data:
                    res = {}
                    ent = data.get("entries", [])
                    # kOS serializa lexicones como listas de pares clave-valor consecutivos
                    for i in range(0, len(ent) - 1, 2):
                        k_node = ent[i]
                        v_node = ent[i+1]
                        k = str(k_node.get("value", "UNKNOWN")).upper().strip()
                        res[k] = flatten(v_node)
                    return res
                elif "value" in data:
                    return flatten(data["value"])
                return {str(k).upper().strip(): flatten(v) for k, v in data.items()}
            return data

        return flatten(raw)

    def update_telemetry(self):
        try:
            all_tags_found = set()
            # SHIP (S2)
            d = self.parse_kos_json(BASE_NAME_SHIP, self.diag_ship)
            if self.test_mode_active: d = {'ENGSTATES': {'S1': 1}, 'ALT': 185200, 'VEL': 7250, 'VS': 12, 'STATUS': 'NOMINAL ORBIT'}
            if d:
                v = self.ship_panel["vars"]
                v["altitud"].set(self.safe_num(d.get('ALT', 0), "m"))
                v["velocidad"].set(self.safe_num(d.get('VEL', 0), "m/s"))
                v["vsspeed"].set(self.safe_num(d.get('VS', 0), "m/s"))
                v["thr"].set(f"{d.get('THR', 0)}%")
                v["thr_val"].set(float(d.get('THR', 0)))
                v["fuelpct"].set(f"{d.get('FUELPCT', 0)}%")
                v["fuel_pct_val"].set(float(d.get('FUELPCT', 0)))
                v["hdist"].set(self.safe_num(d.get('HDIST', 0), "m"))
                v["fuel"].set(self.safe_num(d.get('FUEL', 0), "L"))
                if "deltav" in v: v["deltav"].set(self.safe_num(d.get('DV', 0), "m/s"))
                v["status"].set(str(d.get('STATUS', '---')))
                
                # Mostrar versión del sistema en el log global si está disponible
                if d.get('VERSION'):
                    self.engine_tags_label.config(text=f"SYS: {d.get('VERSION')} | {self.engine_tags_label.cget('text')}")
                st = d.get('ENGSTATES', {})
                if st: self.update_engines(self.ship_panel, st); all_tags_found.update(st.keys())

            # BOOSTER (S1)
            d = self.parse_kos_json(BASE_NAME_BOOSTER, self.diag_booster)
            if self.test_mode_active: 
                d = {'ENGSTATES': {'C1':1,'C2':1,'C3':1}, 'ALT': 120, 'VEL': 12, 'VS': -1.5, 'THR': 65, 'HDIST': 4.2, 'FUEL': 1250, 'STATUS': 'FINAL DESCENT'}
            if d:
                v = self.booster_panel["vars"]
                v["altitud"].set(self.safe_num(d.get('ALT', 0), "m"))
                v["velocidad"].set(self.safe_num(d.get('VEL', 0), "m/s"))
                v["vsspeed"].set(self.safe_num(d.get('VS', 0), "m/s"))
                v["thr"].set(f"{d.get('THR', 0)}%")
                v["thr_val"].set(float(d.get('THR', 0)))
                v["fuelpct"].set(f"{d.get('FUELPCT', 0)}%")
                v["fuel_pct_val"].set(float(d.get('FUELPCT', 0)))
                v["hdist"].set(self.safe_num(d.get('HDIST', 0), "m"))
                v["fuel"].set(self.safe_num(d.get('FUEL', 0), "L"))
                status = str(d.get('STATUS', '---')).upper()
                v["status"].set(status)
                
                # EFECTO TOUCHDOWN: Forzar visual si ha aterrizado
                st = d.get('ENGSTATES', {})
                if "LANDED" in status or "SPLASHED" in status:
                    st = {k: 0 for k in self.booster_panel["engine_map"].keys()} # Force OFF
                    self.booster_panel["vars"]["thr_val"].set(0)
                    self.booster_panel["vars"]["thr"].set("0%")
                    
                if st: self.update_engines(self.booster_panel, st); all_tags_found.update(st.keys())

            if all_tags_found:
                self.engine_tags_label.config(text=" | ".join(sorted(all_tags_found)), fg="#39ff14")
            else:
                self.engine_tags_label.config(text="LINKING...", fg="#444")

            self.last_update_label.config(text=f"UTC SYNC: {datetime.now().strftime('%H:%M:%S')}")
            
            # Reset version prefix to avoid accumulation
            cur_text = self.engine_tags_label.cget("text")
            if "SYS:" in cur_text and "|" in cur_text:
                self.engine_tags_label.config(text=cur_text.split("|", 1)[1].strip())
        except Exception as e: pass
        self.root.after(UPDATE_RATE_MS, self.update_telemetry)

    def update_engines(self, panel, states):
        if not isinstance(states, dict): return
        for tag, e_id in panel["engine_map"].items():
            state = states.get(tag.upper(), 0)
            is_active = str(state) == "1" or state == 1
            color = "#39ff14" if is_active else "#0a1016"
            panel["canvas"].itemconfig(e_id, fill=color, outline="#1a2634" if not is_active else "#39ff14")

if __name__ == "__main__":
    root = tk.Tk()
    style = ttk.Style()
    style.theme_use('clam')
    style.configure("determinate.Horizontal.TProgressbar", troughcolor='#05070a', background='#00f2ff', bordercolor='#1a2634', lightcolor='#00f2ff', darkcolor='#00f2ff')
    style.configure("fuel.Horizontal.TProgressbar", troughcolor='#05070a', background='#f1c40f', bordercolor='#1a2634', lightcolor='#f1c40f', darkcolor='#f1c40f')
    app = MissionControlApp(root)
    root.mainloop()
