"""Assemble the image's /nix/store from a Nix closure, keeping only Fil-C code.

Store paths keep their names, because Fil-C programs name their loader and
libraries by absolute path. The closure cannot be shipped as it is, though: it
reaches ordinary x86-64 packages through things that never run in the image
(#! lines of glibc's helper scripts, say), and the toolchain's sysroot carries
programs and archives built without Fil-C's checks.

Every ELF file is classified:

  filc     links libpizlo.so, as everything the Fil-C compiler emits does
  runtime  the Fil-C runtime itself: a copy of one of the RUNTIME files (below)
           in --runtime, the lib directory of the toolchain's sysroot
  foreign  anything else

Foreign files are left out, and so is any store path that held nothing but
foreign code. A Fil-C program cannot load a foreign library (the ABIs differ),
so none of it can be missed at run time except as a subprocess. Scripts and
symlinks that pointed at something left out go too, as does each --unwanted
path, for files that are fine but of no use in the image.

verify() then walks the result from scratch. It fails the build if anything
foreign or dangling is left, or if a --required program did not make it.
"""

import argparse
import filecmp
import os
import shutil
import subprocess

# What Fil-C programs stand on: the loader, the runtime (allocator, garbage
# collector, syscall layer) and the libc and libm the runtime itself uses.
# These are the trusted computing base; they cannot be compiled with Fil-C.
RUNTIME = {
    "ld-fil1-x86_64.so",
    "libpizlo.so",
    "libyolocimpl.so",
    "libyolomimpl.so",
}

# Of no use at run time. The directories are relative to the store path.
BUILD_ONLY_SUFFIXES = (".a", ".o", ".la")
BUILD_ONLY_DIRS = (
    "include/",
    "nix-support/",
    "lib/pkgconfig/",
    "share/doc/",
    "share/info/",
    "share/man/",
)


def starts_with(path, magic):
    with open(path, "rb") as f:
        return f.read(len(magic)) == magic


def classify(path, runtime_dir):
    """filc, runtime or foreign for an ELF file; None for any other file."""
    if not starts_with(path, b"\x7fELF"):
        return None
    # Fails on what has no dynamic section, which Fil-C's output always has.
    needed = subprocess.run(
        ["patchelf", "--print-needed", path], capture_output=True, text=True
    ).stdout.split()
    if "libpizlo.so" in needed:
        return "filc"
    name = os.path.basename(path)
    if name in RUNTIME and filecmp.cmp(path, os.path.join(runtime_dir, name), shallow=False):
        return "runtime"
    return "foreign"


def interpreter(path):
    """The program a #! script names, or None."""
    with open(path, "rb") as f:
        line = f.readline(512)
    words = line[2:].split() if line.startswith(b"#!") else []
    return words[0].decode() if words else None


def members(top):
    """Everything under top that is not a real directory."""
    if not os.path.isdir(top) or os.path.islink(top):
        yield top
        return
    for directory, subdirectories, names in os.walk(top):
        for name in names:
            yield os.path.join(directory, name)
        for name in subdirectories:  # os.walk does not descend into these
            if os.path.islink(os.path.join(directory, name)):
                yield os.path.join(directory, name)


def build_only(relative):
    return relative.endswith(BUILD_ONLY_SUFFIXES) or relative.startswith(BUILD_ONLY_DIRS)


def resolves(out, path):
    """Whether path, on this machine, leads to something inside the image."""
    for _ in range(40):
        if not path.startswith(out + "/"):
            return False
        # A directory on the way may itself be a symlink into /nix/store.
        head, parts = out, os.path.relpath(path, out).split("/")
        for i, part in enumerate(parts):
            head = os.path.join(head, part)
            if os.path.islink(head):
                target = os.readlink(head)
                if target.startswith("/"):
                    head = out + target
                else:
                    head = os.path.normpath(os.path.join(os.path.dirname(head), target))
                path = os.path.join(head, *parts[i + 1 :])
                break
        else:
            return os.path.exists(path)
    return False


def broken(out, path):
    """Why a file of the image cannot work, or None."""
    if os.path.islink(path):
        return None if resolves(out, path) else "dangling symlink"
    # Interpreters outside /nix/store (/bin/sh, /usr/bin/env) are for the rest
    # of the image to provide.
    program = interpreter(path)
    if program and program.startswith("/nix/store/") and not resolves(out, out + program):
        return f"its interpreter {program} is missing"
    return None


def assemble(store_paths, out, runtime_dir, unwanted):
    dependent = []  # copies that are only as good as another file
    for store_path in store_paths:
        if store_path in unwanted:
            continue
        contents = list(members(store_path))
        kinds = {m: classify(m, runtime_dir) for m in contents if not os.path.islink(m)}
        if set(kinds.values()) - {None} == {"foreign"}:
            print(f"left out {store_path}: not built with Fil-C")
            continue
        for member in contents:
            if (
                kinds.get(member) == "foreign"
                or member in unwanted
                or build_only(os.path.relpath(member, store_path))
            ):
                continue
            copy = out + member
            os.makedirs(os.path.dirname(copy), exist_ok=True)
            shutil.copy2(member, copy, follow_symlinks=False)
            if os.path.islink(member) or interpreter(member):
                dependent.append(copy)

    # Leaving one out can break another.
    while True:
        reasons = {path: broken(out, path) for path in dependent}
        dependent = [path for path in dependent if not reasons[path]]
        if len(dependent) == len(reasons):
            break
        for path, reason in reasons.items():
            if reason:
                print(f"left out {path[len(out):]}: {reason}")
                os.remove(path)


def verify(out, runtime_dir, required):
    counts = {"filc": 0, "runtime": 0}
    problems = []
    for path in members(out):
        name = path[len(out) :]
        reason = broken(out, path)
        if reason:
            problems.append(f"{name}: {reason}")
        elif not os.path.islink(path):
            kind = classify(path, runtime_dir)
            if kind == "foreign":
                problems.append(f"{name}: not built with Fil-C")
            elif kind:
                counts[kind] += 1
            elif starts_with(path, b"!<arch>\n"):
                problems.append(f"{name}: static library")
    for name in required:
        if not resolves(out, out + name):
            problems.append(f"{name}: required, but not in the image")
    if problems:
        raise SystemExit("\n".join(problems))
    print(
        f"{counts['filc']} ELF files built with Fil-C, "
        f"{counts['runtime']} copies of the Fil-C runtime, nothing else"
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--closure", required=True, help="file listing the store paths")
    parser.add_argument("--out", required=True)
    parser.add_argument("--runtime", required=True)
    parser.add_argument("--unwanted", nargs="*", default=[])
    parser.add_argument("--required", nargs="*", default=[])
    args = parser.parse_args()
    with open(args.closure) as f:
        store_paths = sorted(f.read().split())
    assemble(store_paths, args.out, args.runtime, set(args.unwanted))
    verify(args.out, args.runtime, args.required)


if __name__ == "__main__":
    main()
