"""Run Lua 5.1 syntax and isolated regression suites; no game/save mutations."""
from pathlib import Path
import os
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / ".test-deps"))
from lupa.lua51 import LuaRuntime

MOD = ROOT / "agri_robot"
os.chdir(ROOT)
failures = []
runtime = LuaRuntime(unpack_returned_tuples=True)
compile_lua = runtime.eval("function(source, name) local fn, err = loadstring(source, name); return fn ~= nil, err end")
sources = list(MOD.rglob("*.lua"))
for path in sources:
    ok, error = compile_lua(path.read_text(encoding="utf-8-sig"), "@" + str(path))
    if not ok:
        failures.append(f"SYNTAX {path}: {error}")
print(f"Lua 5.1 syntax: {len(sources)} files, {len(failures)} failures")

selected = sys.argv[1:]
suites = [ROOT / p for p in selected] if selected else sorted((ROOT / "tests").glob("*_regression.lua"))
for path in suites:
    lua = LuaRuntime(unpack_returned_tuples=True)
    # Lua 5.1 Windows fopen uses the ANSI codepage. Relative paths avoid losing
    # non-ASCII characters in the user's project directory.
    lua.globals().package.path = "agri_robot/scripts/?.lua;" + lua.globals().package.path
    try:
        result = lua.execute(path.read_text(encoding="utf-8-sig"), name="@" + str(path))
        print(f"PASS {path.name}: {result or 'ok'}")
    except Exception as error:
        failures.append(f"FAIL {path.name}: {error}")
for error in failures:
    print(error)
sys.exit(bool(failures))
