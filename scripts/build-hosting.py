from pathlib import Path
from shutil import copyfile
from zipfile import ZIP_DEFLATED, ZipFile


root = Path(__file__).resolve().parent.parent
output = root / "public"
output.mkdir(exist_ok=True)

files = [root / name for name in (
    "Start-DevSetup.ps1", "Launch.cmd", "Launch-Online.cmd", "README.md", "LICENSE"
)]
files.extend(sorted((root / "scripts").glob("*.ps1")))
files.extend(sorted((root / "data").glob("*.json")))

with ZipFile(output / "windows-setup-helper.zip", "w", ZIP_DEFLATED) as archive:
    for file in files:
        archive.write(file, f"windows-setup-helper-main/{file.relative_to(root).as_posix()}")

copyfile(root / "bootstrap.ps1", output / "bootstrap.ps1")
