"""Native recipe images, Flock chest build and container animation integration."""
from pathlib import Path
import shutil
from stage import main as stage_main
from run import main as run_main

HERE = Path(__file__).resolve().parent

def main():
    stage_main()
    harness = HERE / "runtime/mods/agri_robot/native_harness.lua"
    shutil.copy2(HERE / "harness_appearance_acceptance.lua", harness)
    previous = set((HERE / "logs").glob("*.server.log"))
    try:
        run_main()
    finally:
        shutil.copy2(HERE / "harness_actions.lua", harness)
    created = set((HERE / "logs").glob("*.server.log")) - previous
    if not created:
        raise SystemExit("FAIL: no appearance log")
    log = max(created, key=lambda p: p.stat().st_mtime_ns)
    text = log.read_text(encoding="utf-8", errors="replace")
    if "COMPLETE native_appearance" not in text or "[AGRI_NATIVE] FAIL" in text or "LUA ERROR" in text:
        raise SystemExit("FAIL: native appearance; see " + str(log))
    print("PASS: native recipe image ids, chest/ghost loading and open/close; skinned pixels not certified offline")

if __name__ == "__main__":
    main()
