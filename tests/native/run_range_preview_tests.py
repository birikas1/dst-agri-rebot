"""Native recipe/placer/range integration without desktop input."""
from pathlib import Path
import shutil
from stage import main as stage_main
from run import main as run_main

HERE = Path(__file__).resolve().parent

def main():
    stage_main()
    harness = HERE / "runtime/mods/agri_robot/native_harness.lua"
    shutil.copy2(HERE / "harness_range_preview.lua", harness)
    previous = set((HERE / "logs").glob("*.server.log"))
    try:
        run_main()
    finally:
        shutil.copy2(HERE / "harness_actions.lua", harness)
    created = set((HERE / "logs").glob("*.server.log")) - previous
    if not created:
        raise SystemExit("FAIL: no native preview log")
    log = max(created, key=lambda p: p.stat().st_mtime_ns)
    content = log.read_text(encoding="utf-8", errors="replace")
    if "COMPLETE native_range_preview" not in content or "[AGRI_NATIVE] FAIL" in content or "LUA ERROR" in content:
        raise SystemExit("FAIL: native preview; see " + str(log))
    print("PASS: recipe wiring, native circle assets, fixed/new origins, movement and cancellation; mouse UI not certified")

if __name__ == "__main__":
    main()
