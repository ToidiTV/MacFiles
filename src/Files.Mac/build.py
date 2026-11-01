#!/usr/bin/env python3
"""Build and package the native MacFiles application with the bundled archive backend."""
import argparse
import pathlib
import plistlib
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--output", type=pathlib.Path, default=ROOT.parents[1])
parser.add_argument("--configuration", choices=["debug", "release"], default="release")
parser.add_argument("--skip-build", action="store_true")
parser.add_argument("--bundle-id", default="com.toidi.macfiles", help="Use a separate preference domain for UI test builds")
parser.add_argument("--universal", action="store_true", help="Build both Apple Silicon and Intel architectures")
args = parser.parse_args()
architectures = ["--arch", "arm64", "--arch", "x86_64"] if args.universal else []
clang_architectures = ["-arch", "arm64", "-arch", "x86_64"] if args.universal else []
subprocess.run(["xcrun", "clang"] + clang_architectures + ["-O2", "-mmacosx-version-min=14.0", str(ROOT / "Tools/macfiles-askpass.c"), "-o", str(ROOT / "Tools/macfiles-askpass")], check=True)
subprocess.run(["xcrun", "clang"] + clang_architectures + ["-O2", "-mmacosx-version-min=14.0", "-framework", "Security", "-framework", "CoreFoundation", str(ROOT / "Tools/macfiles-git-credential.c"), "-o", str(ROOT / "Tools/macfiles-git-credential")], check=True)
if not args.skip_build:
    subprocess.run(["swift", "build", "-c", args.configuration] + architectures, cwd=ROOT, check=True)
binary_dir = pathlib.Path(subprocess.check_output(
    ["swift", "build", "-c", args.configuration, "--show-bin-path"] + architectures, cwd=ROOT, text=True).strip())
app = args.output.resolve() / "MacFiles.app"
if app.exists():
    shutil.rmtree(app)
macos = app / "Contents" / "MacOS"
resources = app / "Contents" / "Resources"
macos.mkdir(parents=True)
resources.mkdir(parents=True)
shutil.copy2(binary_dir / "MacFiles", macos / "MacFiles")
for bundle in binary_dir.glob("MacFiles_*.bundle"):
    if bundle.name.endswith("Tests.bundle"): continue
    shutil.copytree(bundle, resources / bundle.name)
for license_name in ["LICENSE-MIT", "LICENSE-MPL", "LICENSE-libarchive", "LICENSE-7zip", "LICENSE-LGPL-2.1"]:
    shutil.copy2(ROOT / "Notices" / license_name, resources / license_name)
shutil.copytree(ROOT / "Tools", resources / "Tools")
shutil.copy2(ROOT / "PORTING.md", resources / "PORTING.md")
shutil.copy2(ROOT / "PARITY-AUDIT.md", resources / "PARITY-AUDIT.md")
iconset = ROOT / "work" / "MacFiles.iconset"
iconset.mkdir(parents=True, exist_ok=True)
icon_source = ROOT / "Packaging" / "MacFiles.png"
for size in [16, 32, 128, 256, 512]:
    for scale in [1, 2]:
        target = iconset / f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
        subprocess.run(["sips", "-z", str(size * scale), str(size * scale), str(icon_source), "--out", str(target)],
                       check=True, stdout=subprocess.DEVNULL)
subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(resources / "MacFiles.icns")], check=True)
for localization in (ROOT / "Sources" / "FilesApp" / "Resources").glob("*.lproj"):
    shutil.copytree(localization, resources / localization.name)
info = {
    "CFBundleName": "MacFiles", "CFBundleDisplayName": "MacFiles", "CFBundleExecutable": "MacFiles",
    "CFBundleIdentifier": args.bundle_id, "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "0.7.2", "CFBundleVersion": "12", "CFBundleIconFile": "MacFiles",
    "CFBundleDevelopmentRegion": "en",
    "LSMinimumSystemVersion": "14.0", "NSHighResolutionCapable": True,
    "NSPrincipalClass": "NSApplication", "NSSupportsAutomaticTermination": False,
    "NSAppleEventsUsageDescription": "MacFiles opens Finder’s Get Info window for the files you select.",
    "NSHumanReadableCopyright": "Based on Files Community. See bundled MIT and MPL-2.0 notices.",
    "NSDesktopFolderUsageDescription": "MacFiles browses and manages the files you choose on your Desktop.",
    "NSDocumentsFolderUsageDescription": "MacFiles browses and manages the documents you choose.",
    "NSDownloadsFolderUsageDescription": "MacFiles browses and manages your downloaded files.",
    "NSRemovableVolumesUsageDescription": "MacFiles browses and manages files on connected drives.",
    "NSNetworkVolumesUsageDescription": "MacFiles browses and manages files on mounted network drives.",
    "NSServices": [{"NSMenuItem": {"default": "Open in MacFiles"}, "NSMessage": "openInMacFiles",
                    "NSPortName": "MacFiles", "NSSendTypes": ["public.file-url", "NSFilenamesPboardType"]}],
    "CFBundleDocumentTypes": [{"CFBundleTypeName": "Folder", "CFBundleTypeRole": "Viewer",
                               "LSHandlerRank": "Alternate", "LSItemContentTypes": ["public.folder"]}],
}
with (app / "Contents" / "Info.plist").open("wb") as file:
    plistlib.dump(info, file)
subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(app)], check=True)
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
print(app)
