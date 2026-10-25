"""Run independent grid acceptance in the isolated DST runtime, never user saves."""
from pathlib import Path
import shutil

from stage import main as stage_main
from run import main as run_main

HERE = Path(__file__).resolve().parent
MARKER = "COMPLETE native_grid_8_9_16_cleanup_and_preparation"


def main():
    stage_main()
    harness = HERE / "runtime" / "mods" / "agri_robot" / "native_harness.lua"
    shutil.copy2(HERE / "harness_grid_acceptance.lua", harness)
    previous = set((HERE / "logs").glob("*.server.log"))
    try:
        run_main()
    finally:
        # Restore the ordinary smoke harness for subsequent save/reload tests.
        shutil.copy2(HERE / "harness_actions.lua", harness)
    created = set((HERE / "logs").glob("*.server.log")) - previous
    if not created:
        raise SystemExit("FAIL: native run produced no new server log")
    latest = max(created, key=lambda path: path.stat().st_mtime_ns)
    content = latest.read_text(encoding="utf-8", errors="replace")
    if MARKER not in content or "[AGRI_NATIVE] FAIL" in content or "LUA ERROR" in content:
        raise SystemExit("FAIL: native grid acceptance did not complete; see " + str(latest))
    print("PASS: native 8/9/16 grids, natural-hole cleanup and durability")


if __name__ == "__main__":
    main()
