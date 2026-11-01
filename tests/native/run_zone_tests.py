"""Connected vs separated native zones, real shared stock and world settings."""
from pathlib import Path
import shutil
from stage import main as stage_main
from run import main as run_main

HERE = Path(__file__).resolve().parent

def main():
    stage_main()
    harness = HERE / "runtime/mods/agri_robot/native_harness.lua"
    shutil.copy2(HERE / "harness_zone_acceptance.lua", harness)
    previous = set((HERE / "logs").glob("*.server.log"))
    try:
        run_main()
    finally:
        shutil.copy2(HERE / "harness_actions.lua", harness)
    created = set((HERE / "logs").glob("*.server.log")) - previous
    if not created:
        raise SystemExit("FAIL: native zones produced no server log")
    latest = max(created, key=lambda p: p.stat().st_mtime_ns)
    content = latest.read_text(encoding="utf-8", errors="replace")
    if "COMPLETE native_connected_zone_plans" not in content or "[AGRI_NATIVE] FAIL" in content or "LUA ERROR" in content:
        raise SystemExit("FAIL: native zones incomplete; see " + str(latest))
    print("PASS: connected/isolated zones,32-slot ratio, exact totals, native seeds and saved plans")

if __name__ == "__main__":
    main()
