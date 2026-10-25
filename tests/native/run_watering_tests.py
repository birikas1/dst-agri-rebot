"""Verify automatic watering with real native planner, moisture and can."""
from pathlib import Path
import shutil

from stage import main as stage_main
from run import main as run_main

HERE = Path(__file__).resolve().parent


def main():
    stage_main()
    harness = HERE / "runtime" / "mods" / "agri_robot" / "native_harness.lua"
    shutil.copy2(HERE / "harness_watering_acceptance.lua", harness)
    previous = set((HERE / "logs").glob("*.server.log"))
    try:
        run_main()
    finally:
        shutil.copy2(HERE / "harness_actions.lua", harness)
    created = set((HERE / "logs").glob("*.server.log")) - previous
    if not created:
        raise SystemExit("FAIL: automatic watering produced no new server log")
    latest = max(created, key=lambda path: path.stat().st_mtime_ns)
    content = latest.read_text(encoding="utf-8", errors="replace")
    if "COMPLETE native_automatic_watering" not in content or "[AGRI_NATIVE] FAIL" in content or "LUA ERROR" in content:
        raise SystemExit("FAIL: automatic watering did not complete; see " + str(latest))
    print("PASS: automatic planning, native watering, exact use and wet-soil rescan")


if __name__ == "__main__":
    main()
