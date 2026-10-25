"""Prepare an isolated copy of DST for native server tests, never user saves/mods."""
from pathlib import Path
import shutil

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
GAME = Path(r"C:\Program Files (x86)\Steam\steamapps\common\Don't Starve Together")
RUNTIME = HERE / "runtime"

def main():
    RUNTIME.mkdir(exist_ok=True)
    for folder in ("bin64", "data"):
        destination = RUNTIME / folder
        if not (HERE / (folder + ".copied")).exists():
            print("Copying native " + folder, flush=True)
            shutil.copytree(GAME / folder, destination, dirs_exist_ok=True)
            (HERE / (folder + ".copied")).write_text("Source build 756039\n", encoding="utf-8")
    shutil.copy2(GAME / "version.txt", RUNTIME / "version.txt")
    mods = RUNTIME / "mods"
    mods.mkdir(exist_ok=True)
    shutil.copytree(ROOT / "agri_robot", mods / "agri_robot", dirs_exist_ok=True)
    (mods / "modsettings.lua").write_text('ForceEnableMod("agri_robot")\n', encoding="utf-8")
    (mods / "dedicated_server_mods_setup.lua").write_text("-- Offline native test. No workshop downloads.\n", encoding="utf-8")
    with (mods / "agri_robot" / "modmain.lua").open("a", encoding="utf-8") as f:
        f.write('\n-- Harness exists only in this disposable test copy.\nmodimport("native_harness.lua")\n')
    shutil.copy2(HERE / "harness_actions.lua", mods / "agri_robot" / "native_harness.lua")
    cluster = HERE / "storage" / "AgriNative" / "Smoke"
    master = cluster / "Master"
    master.mkdir(parents=True, exist_ok=True)
    (cluster / "cluster.ini").write_text("""[GAMEPLAY]
game_mode = endless
max_players = 1
pvp = false
pause_when_empty = false

[NETWORK]
cluster_name = Local Agri Native Test
cluster_description = Disposable offline validation
offline_cluster = true
lan_only_cluster = true
cluster_password = isolated-test

[MISC]
console_enabled = true
max_snapshots = 1

[SHARD]
shard_enabled = false
""", encoding="utf-8")
    (master / "server.ini").write_text("""[NETWORK]
server_port = 11999

[SHARD]
is_master = true

[STEAM]
authentication_port = 18999
master_server_port = 18998
""", encoding="utf-8")
    (master / "modoverrides.lua").write_text('return { agri_robot = { enabled = true, configuration_options = { debug_log = true } } }\n', encoding="utf-8")
    (master / "worldgenoverride.lua").write_text('return { override_enabled = true, preset = "SURVIVAL_TOGETHER", overrides = { world_size = "small", season_start = "autumn", start_location = "default" } }\n', encoding="utf-8")
    print("Isolated native runtime ready: " + str(RUNTIME), flush=True)

if __name__ == "__main__":
    main()
