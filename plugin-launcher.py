#!/usr/bin/env python3
"""Tick the plugins to use, then start the fork.

A slicing plugin is installed by a symlink to its bundle in the slicer's data directory
(README.md, "Installing one"), and the slicer has no screen for that. This window is that
screen: every bundle in this repository gets a checkbox, the ticked ones are linked, the
others unlinked, and the slicer is started.

It only ever creates and removes links: symlinks, and on Windows junctions. A bundle that
sits in the data directory as a real directory was put there by something else; it is shown
and left alone.

It runs from a checkout of this repository, and frozen into a program inside the downloadable
package (.github/package.sh), where the plugins are in plugins/ and the slicer is beside it.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PROGRAM = Path(sys.executable if getattr(sys, "frozen", False) else __file__).resolve()
# A frozen macOS build sits inside its .app; what it looks for is beside the bundle.
REPO = next((parent.parent for parent in PROGRAM.parents if parent.suffix == ".app"), PROGRAM.parent)
BUNDLES = REPO / "plugins" if (REPO / "plugins").is_dir() else REPO
if sys.platform == "win32":
    CONFIG_HOME = Path(os.environ["APPDATA"])
elif sys.platform == "darwin":
    CONFIG_HOME = Path.home() / "Library" / "Application Support"
else:
    CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
# shortcut: the "-dev" data directory of an alpha or a beta, drop the suffix for a final release
DEFAULT_LUA_DIR = CONFIG_HOME / "PrusaSlicer3-dev" / "lua"
SAVED_SLICER = CONFIG_HOME / "prusaslicer3-plugin-launcher.path"
TITLE = "PrusaSlicer fork: slicing plugins"


def find_bundles(repo):
    """Every directory that holds a manifest.json and is named after its id."""
    bundles = []
    for manifest in repo.glob("*/*/manifest.json"):
        try:
            meta = json.loads(manifest.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if meta.get("id") != manifest.parent.name:
            continue  # the slicer would not load it either
        bundles.append({
            "id": meta["id"],
            "name": meta.get("name", meta["id"]),
            "description": meta.get("description", ""),
            "hooks": sorted(api for api in meta.get("required_apis", {}) if api.startswith("slicing.")),
            "path": manifest.parent.resolve(),
        })
    return sorted(bundles, key=lambda bundle: bundle["name"].lower())


def is_link(path):
    """A symlink, or a junction (Python 3.12 is the first to tell one from a directory)."""
    return path.is_symlink() or getattr(os.path, "isjunction", lambda _: False)(path)


def make_link(link, target):
    if os.name == "nt":
        import _winapi
        _winapi.CreateJunction(str(target), str(link))  # a symlink needs administrator rights there
    else:
        link.symlink_to(target, target_is_directory=True)


def link_state(lua_dir, bundle):
    """'on' for a link, 'off' for nothing, 'foreign' for a real directory."""
    link = lua_dir / bundle["id"]
    if is_link(link):
        return "on"
    return "foreign" if link.exists() else "off"


def apply(lua_dir, bundles, wanted):
    """Link the bundles whose id is in `wanted`, unlink the rest."""
    lua_dir.mkdir(parents=True, exist_ok=True)
    for bundle in bundles:
        link = lua_dir / bundle["id"]
        if is_link(link):
            if bundle["id"] in wanted and link.resolve() == bundle["path"]:
                continue
            link.unlink()
        elif link.exists():
            continue
        if bundle["id"] in wanted:
            make_link(link, bundle["path"])


def shared_hooks(bundles, wanted):
    """Hooks more than one wanted bundle asks for: the slicer loads one plugin per hook."""
    claims = {}
    for bundle in bundles:
        if bundle["id"] in wanted:
            for hook in bundle["hooks"]:
                claims.setdefault(hook, []).append(bundle["name"])
    return {hook: names for hook, names in claims.items() if len(names) > 1}


def is_program(path):
    return bool(path) and os.path.isfile(path) and os.access(path, os.X_OK)


def find_slicer():
    """The package's own binary, else the one used last time, `prusaslicer-fork` on PATH, a checkout next to this one."""
    candidates = [
        str(REPO / "PrusaSlicer/bin/slic3r-app-launcher"),
        str(REPO / "PrusaSlicer/slic3r-app-launcher.exe"),
        str(REPO / "PrusaSlicer.app/Contents/MacOS/PrusaSlicer"),
        SAVED_SLICER.read_text(encoding="utf-8").strip() if SAVED_SLICER.is_file() else "",
        shutil.which("prusaslicer-fork"),
        str(REPO.parent / "PrusaSlicer/build/src/slic3r-app-launcher/slic3r-app-launcher"),
    ]
    return next((path for path in candidates if is_program(path)), "")


def build_window(lua_dir, slicer):
    import tkinter as tk
    from tkinter import filedialog, messagebox, ttk

    bundles = find_bundles(BUNDLES)
    root = tk.Tk()
    root.title(TITLE)
    if root.tk.call("tk", "windowingsystem") == "x11":
        ttk.Style(root).theme_use("clam")  # X11's default theme draws a tick as a grey square
    frame = ttk.Frame(root, padding=12)
    frame.pack(fill="both", expand=True)
    frame.columnconfigure(1, weight=1)

    ttk.Label(frame, text=f"Linked into {lua_dir}").grid(columnspan=3, sticky="w", pady=(0, 8))

    description = tk.StringVar(value="Point at a plugin to read what it does.")
    warning = tk.StringVar()
    ticks = {}

    def wanted():
        return {bundle_id for bundle_id, tick in ticks.items() if tick.get()}

    def warn():
        warning.set("\n".join(
            f"{hook} is asked for by {' and '.join(names)}: the slicer will load only one of them."
            for hook, names in sorted(shared_hooks(bundles, wanted()).items())))

    for bundle in bundles:
        state = link_state(lua_dir, bundle)
        ticks[bundle["id"]] = tick = tk.BooleanVar(value=state != "off")
        box = ttk.Checkbutton(frame, text=bundle["name"], variable=tick, command=warn)
        note = ", ".join(bundle["hooks"])
        if state == "foreign":
            box.state(["disabled"])
            note += "  (a real directory, not a link: left alone)"
        hooks = ttk.Label(frame, text=note, foreground="gray40")
        row = frame.grid_size()[1]
        box.grid(row=row, column=0, sticky="w")
        hooks.grid(row=row, column=1, columnspan=2, sticky="w", padx=(16, 0))
        for widget in (box, hooks):
            widget.bind("<Enter>", lambda _, text=bundle["description"]: description.set(text))

    ttk.Separator(frame).grid(columnspan=3, sticky="ew", pady=8)
    # Three lines tall whatever it says, so the buttons do not move under the pointer.
    plain = {"bg": ttk.Style(root).lookup("TFrame", "background"), "wraplength": 640,
             "anchor": "nw", "justify": "left"}
    tk.Label(frame, textvariable=description, height=3, **plain).grid(columnspan=3, sticky="ew")
    tk.Label(frame, textvariable=warning, fg="#b00020", **plain).grid(columnspan=3, sticky="ew")

    slicer_path = tk.StringVar(value=slicer)
    row = frame.grid_size()[1]
    ttk.Label(frame, text="PrusaSlicer:").grid(row=row, column=0, sticky="w", pady=8)
    ttk.Entry(frame, textvariable=slicer_path).grid(row=row, column=1, sticky="ew")

    def browse():
        path = filedialog.askopenfilename(title="The fork's slic3r-app-launcher")
        if path:
            slicer_path.set(path)

    ttk.Button(frame, text="Browse…", command=browse).grid(row=row, column=2, padx=(8, 0))

    def link():
        try:
            apply(lua_dir, bundles, wanted())
        except OSError as error:
            messagebox.showerror(TITLE, f"Could not update the links:\n{error}")
            return False
        return True

    def start():
        path = slicer_path.get().strip()
        if not is_program(path):
            messagebox.showerror(TITLE, "Point the PrusaSlicer field at the fork's binary:\n"
                                        "build/src/slic3r-app-launcher/slic3r-app-launcher")
            return
        if not link():
            return
        SAVED_SLICER.parent.mkdir(parents=True, exist_ok=True)
        SAVED_SLICER.write_text(path + "\n", encoding="utf-8")
        subprocess.Popen([path], start_new_session=True)
        root.destroy()

    buttons = ttk.Frame(frame)
    buttons.grid(columnspan=3, sticky="e")
    # The slicer rescans its plugins for every slice, so linking under a running one works.
    ttk.Button(buttons, text="Apply", command=link).pack(side="left", padx=(0, 8))
    ttk.Button(buttons, text="Apply and start PrusaSlicer", command=start, default="active").pack(side="left")
    root.bind("<Return>", lambda _: start())
    warn()
    return root


def self_test():
    with tempfile.TemporaryDirectory() as scratch:
        repo, lua_dir = Path(scratch, "repo"), Path(scratch, "data", "lua")

        def bundle(directory, bundle_id, hooks):
            path = repo / directory / bundle_id
            path.mkdir(parents=True)
            (path / "manifest.json").write_text(json.dumps(
                {"id": bundle_id, "name": directory, "required_apis": {hook: "1.0.0" for hook in hooks}}))

        bundle("b-fill", "x.b", ["slicing.fill_planner"])
        bundle("a-fill", "x.a", ["slicing.fill_planner", "slicing.layer_planner"])
        bundle("c-order", "x.c", ["slicing.island_order"])
        bundle("misnamed", "x.d", [])
        (repo / "misnamed" / "x.d").rename(repo / "misnamed" / "elsewhere")
        bundles = find_bundles(repo)
        assert [b["id"] for b in bundles] == ["x.a", "x.b", "x.c"], bundles

        (lua_dir / "x.c").mkdir(parents=True)  # installed by something else
        apply(lua_dir, bundles, {"x.a", "x.c"})
        apply(lua_dir, bundles, {"x.a", "x.c"})  # a second time changes nothing
        assert [link_state(lua_dir, b) for b in bundles] == ["on", "off", "foreign"]
        assert (lua_dir / "x.a" / "manifest.json").is_file()

        make_link(lua_dir / "x.b", Path(scratch))  # a link to some other checkout is repointed
        apply(lua_dir, bundles, {"x.b"})
        assert [link_state(lua_dir, b) for b in bundles] == ["off", "on", "foreign"]
        assert (lua_dir / "x.b").resolve() == bundles[1]["path"]
        assert (lua_dir / "x.c").is_dir() and not is_link(lua_dir / "x.c")
        apply(lua_dir, bundles, set())
        assert not (lua_dir / "x.b").exists() and bundles[1]["path"].is_dir()  # the link went, not the bundle

        assert shared_hooks(bundles, {"x.a", "x.b", "x.c"}) == {"slicing.fill_planner": ["a-fill", "b-fill"]}
        assert shared_hooks(bundles, {"x.a", "x.c"}) == {}

        window = build_window(lua_dir, "")  # the widgets too: a frozen build is what loses Tk
        window.update()
        window.destroy()
    print("self-test passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--lua-dir", type=Path, default=DEFAULT_LUA_DIR,
                        help="the lua/ of the slicer's data directory (default: %(default)s)")
    parser.add_argument("--link", nargs="*", metavar="ID",
                        help="no window: link exactly these plugins, unlink the others and exit")
    parser.add_argument("--self-test", action="store_true", help="check the linking and the window, then exit")
    arguments = parser.parse_args()
    if arguments.self_test:
        sys.exit(self_test())
    if arguments.link is not None:
        known = find_bundles(BUNDLES)
        if unknown := set(arguments.link) - {bundle["id"] for bundle in known}:
            parser.error(f"no such plugin: {', '.join(sorted(unknown))}")
        sys.exit(apply(arguments.lua_dir, known, set(arguments.link)))
    build_window(arguments.lua_dir, find_slicer()).mainloop()
