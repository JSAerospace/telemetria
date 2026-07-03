import os
import time
import sys

CONFIG_PATH = os.path.join(os.path.dirname(__file__), "boot", "PreLanzamiento", "launch_config.txt")

def read_config():
    if not os.path.exists(CONFIG_PATH):
        return {"t_minus": "10", "payload_tons": "0", "status": "READY"}
    data = {}
    with open(CONFIG_PATH, "r") as f:
        for line in f:
            line = line.strip()
            if "=" in line:
                k, v = line.split("=", 1)
                data[k.strip()] = v.strip()
    return data

def write_config(t_minus, payload_tons, status):
    os.makedirs(os.path.dirname(CONFIG_PATH), exist_ok=True)
    with open(CONFIG_PATH, "w") as f:
        f.write(f"t_minus={t_minus}\n")
        f.write(f"payload_tons={payload_tons}\n")
        f.write(f"status={status}\n")

def main():
    print("=========================================")
    print("      ASOS LAUNCH CONTROLLER (TXT)       ")
    print("=========================================")
    
    cfg = read_config()
    curr_t = int(cfg.get("t_minus", 10))
    curr_payload = float(cfg.get("payload_tons", 0))
    
    print(f"Current setup: T-minus = {curr_t}s, Payload = {curr_payload} tons")
    
    try:
        t_input = input(f"Enter T-minus countdown (seconds) [{curr_t}]: ").strip()
        if t_input:
            curr_t = int(t_input)
    except ValueError:
        print("Invalid input. Using default.")
        
    try:
        p_input = input(f"Enter Payload Mass (tons) [{curr_payload}]: ").strip()
        if p_input:
            curr_payload = float(p_input)
    except ValueError:
        print("Invalid input. Using default.")

    write_config(curr_t, curr_payload, "READY")
    print(f"\nLaunch configuration updated: T-{curr_t}s, Payload={curr_payload}T.")
    print("Ready to start launch countdown. Press Enter to start, or Ctrl+C to exit.")
    
    try:
        input("PRESS ENTER TO START COUNTDOWN...")
    except KeyboardInterrupt:
        print("\nExiting.")
        return
        
    print("\nCOUNTDOWN STARTED! Press Ctrl+C at any time to ABORT.")
    
    status = "COUNTDOWN"
    while curr_t >= 0:
        print(f"T-minus: {curr_t} seconds... (Status: {status})")
        write_config(curr_t, curr_payload, status)
        
        if curr_t == 0:
            break
            
        time.sleep(1.0)
        curr_t -= 1
        
        # Read config to check for external abort/hold
        cfg = read_config()
        if cfg.get("status") == "ABORT":
            print("\n!!! ABORT SIGNAL RECEIVED FROM EXTERNAL SYSTEM !!!")
            return
            
    # Launch trigger
    status = "LAUNCHED"
    write_config(0, curr_payload, status)
    print("\n🚀 LIFTOFF! Booster is flying!")
    
if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n!!! EMERGENCY ABORT INITIATED !!!")
        write_config(0, 0, "ABORT")
        print("Status set to ABORT.")
