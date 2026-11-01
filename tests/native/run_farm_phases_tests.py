"""Codex 2x2 farm acceptance in the disposable DST runtime and saves."""
from pathlib import Path
import shutil
from stage import main as stage_main
from run import main as run_main

HERE = Path(__file__).resolve().parent


def main():
    stage_main()
    harness = HERE / "runtime" / "mods" / "agri_robot" / "native_harness.lua"
    shutil.copy2(HERE / "harness_farm_phases_acceptance.lua", harness)
    previous = set((HERE / "logs").glob("*.server.log"))
    try:
        run_main()
    finally:
        shutil.copy2(HERE / "harness_actions.lua", harness)
    created = set((HERE / "logs").glob("*.server.log")) - previous
    if not created:
        raise SystemExit("FAIL: four-plot farm test produced no log")
    latest = max(created, key=lambda path: path.stat().st_mtime_ns)
    content = latest.read_text(encoding="utf-8", errors="replace")
    if "COMPLETE native_four_plot_farm_phases" not in content or "[AGRI_NATIVE] FAIL" in content or "LUA ERROR" in content:
        raise SystemExit("FAIL: four-plot farm acceptance did not complete; see " + str(latest))
    print("PASS: native 2x2 debris, stray holes, batch till/plant, watering and rescans")


if __name__ == "__main__":
    main()
