"""Compile generated PNGs with the installed official Klei toolchain.

PNG pixels are unchanged here; the official compiler packs/downsamples the
texture and converts it to the game's texture and animation formats.
"""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import tempfile
import zipfile
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "art_source/agriwell"
TOOLS = Path(r"C:\Program Files (x86)\Steam\steamapps\common\Don't Starve Mod Tools\mod_tools")


def main():
    build = Path(tempfile.mkdtemp(prefix="agriwell-build-"))
    width, height = Image.open(ART / "building.png").size
    pivot_y = int(height * .78)
    center_y = height / 2 - pivot_y
    scale = .3
    build_xml = (
        '<Build name="agriwell"><Symbol name="wellbody">'
        f'<Frame framenum="0" duration="1" image="wellbody" w="{width}" h="{height}" x="0" y="{center_y}"/>'
        '</Symbol></Build>'
    )
    animation_xml = (
        '<Anims><anim name="idle" root="agriwell" framerate="30">'
        f'<frame x="0" y="{center_y * scale}" w="{width * scale}" h="{height * scale}">'
        f'<element name="wellbody" frame="0" layername="body" m_a="{scale}" m_b="0" m_c="0" m_d="{scale}" m_tx="0" m_ty="0" z_index="0"/>'
        '</frame></anim></Anims>'
    )
    (ART / "build.xml").write_text(build_xml, encoding="utf-8")
    (ART / "animation.xml").write_text(animation_xml, encoding="utf-8")
    intermediate = build / "agriwell.zip"
    with zipfile.ZipFile(intermediate, "w") as package:
        package.write(ART / "building.png", "wellbody.png")
        package.writestr("build.xml", build_xml)
        package.writestr("animation.xml", animation_xml)
    subprocess.run([
        str(TOOLS / "buildtools/windows/Python27/python.exe"),
        str(TOOLS / "tools/scripts/buildanimation.py"), str(intermediate),
        "--scale=.5", "--outputdir=" + str(build / "out"), "--force", "--square",
    ], cwd=build, check=True)
    animation = ROOT / "agri_robot/anim/agriwell.zip"
    animation.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(build / "out/anim/agriwell.zip", animation)
    # Use an ASCII intermediate path for the legacy converter. The PNG stays
    # in art_source; conversion/resizing is performed by Klei's own program.
    shutil.copy2(ART / "icon.png", build / "agriwell-icon.png")
    subprocess.run([
        str(TOOLS / "tools/bin/TextureConverter.exe"),
        "-i", str(build / "agriwell-icon.png"), "-o", str(build / "agriwell.tex"),
        "-f", "bc3", "-p", "opengl", "-w", "128", "-h", "128",
        "--mipmap", "--premultiply",
    ], cwd=build, check=True)
    images = ROOT / "agri_robot/images/inventoryimages"
    images.mkdir(parents=True, exist_ok=True)
    shutil.copy2(build / "agriwell.tex", images / "agriwell.tex")
    (images / "agriwell.xml").write_text(
        '<Atlas><Texture filename="agriwell.tex"/><Elements>'
        '<Element name="agriwell.tex" u1="0" u2="1" v1="0" v2="1"/>'
        '</Elements></Atlas>\n', encoding="utf-8")
    outputs = [animation, images / "agriwell.xml", images / "agriwell.tex"]
    report = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in outputs}
    (ART / "compiled-manifest.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"compiled": report, "scratch": str(build)}, indent=2))


if __name__ == "__main__":
    main()
