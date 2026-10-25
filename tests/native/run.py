"""Run staged DST offline, recording logs and bounding runtime to 180 seconds."""
from pathlib import Path
import ctypes
import json
import subprocess
import time

HERE = Path(__file__).resolve().parent
RUNTIME = HERE / "runtime"

def short(path):
    # Lua fopen in this Windows build can need an ANSI-compatible path.
    text = str(path.resolve())
    output = ctypes.create_unicode_buffer(32768)
    length = ctypes.windll.kernel32.GetShortPathNameW(text, output, len(output))
    return output.value if length else text

def main():
    logs = HERE / "logs"
    logs.mkdir(exist_ok=True)
    executable = RUNTIME / "bin64" / "dontstarve_dedicated_server_nullrenderer_x64.exe"
    assert executable.is_file(), "Run stage.py first"
    # DST's Windows narrow-string CLI mishandles a non-ASCII absolute storage
    # path. Relative ASCII paths resolve under this explicitly controlled cwd.
    # Validate both destinations before launching. No junctions or user paths.
    working = RUNTIME / "bin64"
    assert (working / "../../storage").resolve() == (HERE / "storage").resolve()
    assert (working / "../../ugc").resolve() == (HERE / "ugc").resolve()
    args = [short(executable), "-persistent_storage_root", "../../storage",
            "-conf_dir", "AgriNative", "-cluster", "Smoke", "-shard", "Master",
            "-offline", "-disabledatacollection", "-skip_update_server_mods",
            "-ugc_directory", "../../ugc", "-nosound", "-nooverlay"]
    (HERE / "ugc").mkdir(exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    metadata = {"args": args, "cwd": short(RUNTIME / "bin64"), "started": stamp,
                "source_build": "756039"}
    (logs / (stamp + ".command.json")).write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
    print("Starting native offline smoke test; all runtime/storage paths are under tests/native.", flush=True)
    with (logs / (stamp + ".stdout.log")).open("wb") as out, (logs / (stamp + ".stderr.log")).open("wb") as err:
        process = subprocess.Popen(args, cwd=short(RUNTIME / "bin64"), stdout=out, stderr=err,
                                   stdin=subprocess.PIPE, creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            exit_code = process.wait(timeout=180)
        except subprocess.TimeoutExpired:
            process.terminate()
            exit_code = process.wait(timeout=10)
            print("Native timeout: terminated only the spawned test process.", flush=True)
    print("Native exit: " + str(exit_code), flush=True)
    serverlog = HERE / "storage" / "AgriNative" / "Smoke" / "Master" / "server_log.txt"
    if serverlog.exists():
        saved_log = logs / (stamp + ".server.log")
        saved_log.write_bytes(serverlog.read_bytes())
        for line in saved_log.read_text(encoding="utf-8", errors="replace").splitlines():
            if "AGRI_NATIVE" in line or "Error" in line or "error" in line:
                print(line, flush=True)

if __name__ == "__main__":
    main()
