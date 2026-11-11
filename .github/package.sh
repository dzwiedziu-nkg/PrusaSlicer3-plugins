#!/usr/bin/env bash
# Makes the downloadable package of the system it runs on: the fork, the plugins of this
# repository and plugin-launcher.py frozen into a program, in one archive.
#
#   FORK=<checkout of the fork> OUT=<output directory> .github/package.sh <step>
#
# The steps, in the order .github/workflows/package.yml runs them: launcher, deps, slicer, stage,
# assemble, smoke. On a machine that already has a build of the fork, `deps` and `slicer` can be
# left out (BUILD is its build directory, $FORK/build unless set). Each step's output is kept in
# $OUT/logs.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
: "${FORK:?set FORK to a checkout of the fork}" "${OUT:?set OUT to the output directory}"
BUILD=${BUILD:-$FORK/build}
case $(uname -s) in
    Linux)  SYSTEM=linux ;;
    Darwin) SYSTEM=macos ;;
    *)      SYSTEM=windows ;;  # Git Bash
esac
VERSION=$(sed -n 's/^set(SLIC3R_VERSION "\(.*\)")/\1/p' "$FORK/version.inc")
NAME=PrusaSlicer-plugin-fork-$VERSION-$SYSTEM-$(uname -m)
PACKAGE=$OUT/$NAME
STAGE=$OUT/stage
case $SYSTEM in
    linux)   SLICER=PrusaSlicer/bin/slic3r-app-launcher ;;
    windows) SLICER=PrusaSlicer/slic3r-app-launcher.exe ;;
    macos)   SLICER=PrusaSlicer.app/Contents/MacOS/PrusaSlicer ;;
esac

deps() {
    # MSVC would otherwise build every library a second time, for a Debug slicer nobody packages.
    cmake -S "$FORK/deps" -B "$FORK/deps/build" $([ $SYSTEM = windows ] && echo -DDEP_DEBUG=OFF)
    cmake --build "$FORK/deps/build" --config Release
}

slicer() {
    # Whose build this is: the id ends up in the G-code and in the About box.
    perl -pi -e "s/\+UNKNOWN/+plugin-fork.$(git -C "$FORK" rev-parse --short HEAD)/" "$FORK/version.inc"
    cmake -S "$FORK" -B "$BUILD" -DCMAKE_PREFIX_PATH="$FORK/deps/build/destdir/usr/local" -DSLIC3R_BUILD_TESTS=OFF
    if [ $SYSTEM = windows ]; then
        cmake --build "$BUILD" --config Release  # /MP already compiles in parallel
    else
        cmake --build "$BUILD" --parallel "$(getconf _NPROCESSORS_ONLN)" -- -k
    fi
}

# The slicer as it has to lie on disk to find its resources and its STEP reader.
stage() {
    rm -rf "$STAGE"
    case $SYSTEM in
    linux)
        mkdir -p "$STAGE/PrusaSlicer/bin"
        cp "$BUILD/src/slic3r-app-launcher/slic3r-app-launcher" "$BUILD/src/OCCTWrapper.so" "$STAGE/PrusaSlicer/bin/"
        strip "$STAGE"/PrusaSlicer/bin/*
        cp -R "$FORK/resources" "$STAGE/PrusaSlicer/resources" ;;
    windows)
        mkdir -p "$STAGE/PrusaSlicer"
        local built vs
        built=$(dirname "$(find "$BUILD/src" -name slic3r-app-launcher.exe -path '*/Release/*' | head -1)")
        cp "$built"/*.exe "$built"/*.dll "$STAGE/PrusaSlicer/"  # the build puts the STEP reader and its other DLLs there
        # The C++ runtime too: not every machine has Visual Studio's redistributable installed.
        vs=$("/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe" -latest -property installationPath)
        cp "$(ls -d "$(cygpath -u "$vs")"/VC/Redist/MSVC/*/x64/Microsoft.VC*.CRT | sort | tail -1)"/*.dll "$STAGE/PrusaSlicer/"
        cp -R "$FORK/resources" "$STAGE/PrusaSlicer/resources" ;;
    macos)
        local app=$STAGE/PrusaSlicer.app/Contents
        mkdir -p "$app/MacOS"
        cp "$BUILD/src/slic3r-app-launcher/slic3r-app-launcher" "$app/MacOS/PrusaSlicer"  # the name Info.plist starts
        cp "$BUILD/src/Info.plist" "$app/Info.plist"
        cp -R "$FORK/resources" "$app/Resources"
        cp "$FORK/resources/icons/PrusaSlicer.icns" "$app/Resources/"
        codesign --force --deep --sign - "$STAGE/PrusaSlicer.app" ;;  # ad hoc: Apple Silicon runs nothing unsigned
    esac
    git -C "$FORK" rev-parse HEAD >"$STAGE/fork-commit"
}

launcher() {
    local python=python3 bin=bin
    [ $SYSTEM = windows ] && python=python && bin=Scripts
    rm -rf "$OUT/launcher"
    $python -m venv "$OUT/launcher/venv"
    "$OUT/launcher/venv/$bin/python" -m pip install --quiet "pyinstaller>=6,<7"
    # From source first: a frozen program that fails has no traceback to show.
    "$OUT/launcher/venv/$bin/python" "$HERE/plugin-launcher.py" --self-test
    "$OUT/launcher/venv/$bin/pyinstaller" --noconfirm --log-level WARN --windowed --name plugin-launcher \
        --distpath "$OUT/launcher/dist" --workpath "$OUT/launcher/work" --specpath "$OUT/launcher" \
        "$HERE/plugin-launcher.py"
}

assemble() {
    rm -rf "$PACKAGE"
    mkdir -p "$PACKAGE/plugins"
    cp -R "$STAGE"/. "$PACKAGE/"
    rm "$PACKAGE/fork-commit"
    if [ $SYSTEM = macos ]; then
        cp -R "$OUT/launcher/dist/plugin-launcher.app" "$PACKAGE/"
    else
        cp -R "$OUT/launcher/dist/plugin-launcher"/. "$PACKAGE/"
    fi
    # The committed plugins, not the working tree: a settings.lua edited for one print stays home.
    git -C "$HERE" archive HEAD -- README.md $(git -C "$HERE" ls-tree -d --name-only HEAD | grep -v '^\.') |
        tar -x -C "$PACKAGE/plugins"

    cat >"$PACKAGE/README.txt" <<README
PrusaSlicer $VERSION with slicing plugin hooks - an unofficial build
====================================================================

This is not a Prusa Research release. It is PrusaSlicer with eleven extra slicing hooks and
the Lua plugins that use them. Problems with it belong here, not with Prusa:

  the slicer   https://github.com/dzwiedziu-nkg/PrusaSlicer          commit $(cut -c1-10 "$STAGE/fork-commit")
  the plugins  https://github.com/dzwiedziu-nkg/PrusaSlicer3-plugins  commit $(git -C "$HERE" rev-parse --short=10 HEAD)

Start plugin-launcher, tick the plugins you want and press "Apply and start PrusaSlicer".
What each plugin does is in its README under plugins/, and what can be tuned is in its
settings.lua. The launcher links the ticked plugins from this folder into the slicer's data
directory, so after moving the folder run the launcher again. The data directory is the one
a stock PrusaSlicer 3 alpha uses: profiles are shared with it.

README
    # Outside the text above on purpose: bash 3.2, which macOS has, cannot parse a case inside $( ).
    case $SYSTEM in
    linux) cat >>"$PACKAGE/README.txt" <<'NOTE' ;;
Linux: built on Ubuntu 24.04 for x86_64. It needs glibc 2.39 or newer and the system's GTK 3,
WebKitGTK 4.1 and hidapi:

  sudo apt install libgtk-3-0t64 libwebkit2gtk-4.1-0 libhidapi-hidraw0
NOTE
    windows) cat >>"$PACKAGE/README.txt" <<'NOTE' ;;
Windows: 64-bit, Windows 10 or newer. The programs are not signed, so Windows may say the
publisher is unknown: choose "More info", then "Run anyway".
NOTE
    macos) cat >>"$PACKAGE/README.txt" <<'NOTE' ;;
macOS: Apple Silicon only, macOS 11 or newer. The programs are not signed with an Apple
developer certificate, so macOS refuses to open them as downloaded. Lift that once, in
Terminal, for the whole folder:

  xattr -dr com.apple.quarantine /path/to/this/folder
NOTE
    esac

    rm -f "$PACKAGE".tar.xz "$PACKAGE".zip
    case $SYSTEM in
    linux)   XZ_OPT=-T0 tar -C "$OUT" -cJf "$PACKAGE.tar.xz" "$NAME" ;;
    windows) (cd "$OUT" && 7z a -tzip -bso0 "$NAME.zip" "$NAME") ;;
    macos)   ditto -c -k --keepParent "$PACKAGE" "$PACKAGE.zip" ;;
    esac
    ls -l "$OUT" | grep "$NAME\."
}

cube() {  # a 20 mm cube as ASCII STL
    local corner=("0 0 0" "0 0 20" "0 20 0" "0 20 20" "20 0 0" "20 0 20" "20 20 0" "20 20 20") facet index
    echo "solid cube"
    for facet in "0 2 3" "0 3 1" "4 5 7" "4 7 6" "0 1 5" "0 5 4" "2 6 7" "2 7 3" "0 4 6" "0 6 2" "1 3 7" "1 7 5"; do
        echo "facet normal 0 0 0"
        echo "outer loop"
        for index in $facet; do echo "vertex ${corner[$index]}"; done
        echo "endloop"
        echo "endfacet"
    done
    echo "endsolid cube"
}

# The package as a user gets it: the launcher links, the slicer slices, every plugin loads.
smoke() {
    local work=$OUT/smoke run=$PACKAGE/plugin-launcher manifest id
    [ $SYSTEM = macos ] && run=$PACKAGE/plugin-launcher.app/Contents/MacOS/plugin-launcher
    rm -rf "$work"
    mkdir -p "$work/data/lua"
    cube >"$work/cube.stl"

    case $SYSTEM in
    linux)
        if ldd "$PACKAGE"/PrusaSlicer/bin/* | grep "not found"; then return 1; fi
        echo "The system libraries it loads come from:"
        ldd "$PACKAGE/$SLICER" | awk '$3 ~ "^/" {print $3}' | xargs -r realpath | xargs -r dpkg -S 2>/dev/null |
            cut -d: -f1 | sort -u | tr '\n' ' ' || true  # for README.txt's apt line, not a check
        echo ;;
    macos)
        # Anything outside the system would be a library of the build machine.
        if otool -L "$PACKAGE/$SLICER" | tail -n +2 | grep -v -E '^[[:space:]]*(/usr/lib/|/System/Library/)'; then return 1; fi ;;
    windows)
        "$OUT/launcher/venv/Scripts/python" - "$PACKAGE/PrusaSlicer" <<'PY'
import os, pathlib, re, sys
import pefile  # PyInstaller brings it

package = pathlib.Path(sys.argv[1])
have = {path.name.lower() for path in package.iterdir()}
windows = pathlib.Path(os.environ["SystemRoot"], "System32")
missing = set()
for binary in [*package.glob("*.exe"), *package.glob("*.dll")]:
    pe = pefile.PE(str(binary), fast_load=True)
    pe.parse_data_directories([pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_IMPORT"]])
    for entry in getattr(pe, "DIRECTORY_ENTRY_IMPORT", []):
        name = entry.dll.decode().lower()
        # This machine has Visual Studio's runtime in System32; a user's machine may not.
        runtime = re.match(r"(msvcp|vcruntime|concrt|vcomp|vccorlib)\d", name)
        if name not in have and (runtime or not (name.startswith(("api-ms-", "ext-ms-")) or (windows / name).exists())):
            missing.add(f"{binary.name} needs {name}")
print("\n".join(sorted(missing)) or "every DLL it imports is in the package or part of Windows")
sys.exit(bool(missing))
PY
        ;;
    esac

    "$run" --self-test

    slice() {  # <model> <name>: fails unless G-code came out
        "$PACKAGE/$SLICER" --datadir "$work/data" -g "$1" -o "$work/$2.gcode" --loglevel 3 >"$work/$2.log" 2>&1 ||
            { tail -20 "$work/$2.log"; echo "$2: the slicer failed"; return 1; }
        [ -s "$work/$2.gcode" ] || { tail -20 "$work/$2.log"; echo "$2: no G-code"; return 1; }
    }
    slice "$work/cube.stl" stock
    if grep "plugin in use" "$work/stock.log"; then echo "a plugin loaded from an empty data directory"; return 1; fi
    # The STEP reader is a library of its own, loaded from beside the binary.
    slice "$FORK/src/slic3r-shared/test/data/test_step/test.step" step
    # One plugin at a time, linked the way a user links it: the slicer loads one plugin per hook.
    for manifest in "$PACKAGE"/plugins/*/*/manifest.json; do
        id=$(basename "$(dirname "$manifest")")
        "$run" --lua-dir "$work/data/lua" --link "$id"
        slice "$work/cube.stl" "$id"
        grep -q "plugin in use: $id" "$work/$id.log" || { tail -20 "$work/$id.log"; echo "$id did not load"; return 1; }
        echo "loaded $id"
    done
    "$run" --lua-dir "$work/data/lua" --link
    echo "smoke test passed: $NAME"
}

case ${1:-} in
    deps|slicer|stage|launcher|assemble|smoke) ;;
    *) sed -n '2,10p' "$0"; exit 2 ;;
esac
# The window of the launcher's self-test needs a display, and a build machine has none.
if [ $SYSTEM = linux ] && [ -z "${DISPLAY:-}" ] && { [ "$1" = launcher ] || [ "$1" = smoke ]; }; then
    exec xvfb-run -a "$0" "$1"
fi
mkdir -p "$OUT/logs"
"$1" 2>&1 | tee "$OUT/logs/$1.log"
