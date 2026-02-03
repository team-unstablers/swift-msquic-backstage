#!/usr/bin/env python3
import argparse
import filecmp
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path


def run(cmd, cwd=None):
    printable = " ".join(shlex.quote(str(part)) for part in cmd)
    print(f"+ {printable}")
    subprocess.run([str(part) for part in cmd], cwd=cwd, check=True)


def is_executable(path):
    return bool(path) and os.path.isfile(path) and os.access(path, os.X_OK)


def pick_compiler(explicit, default_path, label):
    if explicit:
        if is_executable(explicit):
            return explicit
        print(f"warning: {label} not executable: {explicit}", file=sys.stderr)
        return None
    if is_executable(default_path):
        return default_path
    return None


def copy_if_different(src, dst):
    if dst.exists():
        try:
            if filecmp.cmp(src, dst, shallow=False):
                return False
        except OSError:
            pass
    shutil.copy2(src, dst)
    return True


def main():
    parser = argparse.ArgumentParser(description="Build msquic for Apple platforms.")
    parser.add_argument("--cmake", default="/opt/homebrew/bin/cmake", help="Path to cmake.")
    parser.add_argument("--package-root", default="./dependencies/msquic", help="Repo root.")
    parser.add_argument("--build-dir", required=True, help="CMake build directory.")
    parser.add_argument("--dist-dir", required=True, help="Install destination.")
    parser.add_argument("--configuration", default="Release", choices=["Debug", "Release"], help="Build configuration.")
    parser.add_argument("--platform", required=True, choices=["ios", "macos", "simulator"], help="Target platform.")
    parser.add_argument("--arch", required=True, help="Target architecture(s).")
    parser.add_argument("--xcode-path", default="/Applications/Xcode.app", help="Xcode.app path.")
    parser.add_argument("--generator", default="Ninja", help="CMake generator.")
    parser.add_argument("--make-program", default="ninja", help="CMake make program.")
    parser.add_argument("--cc", default="", help="C compiler path.")
    parser.add_argument("--cxx", default="", help="C++ compiler path.")
    args = parser.parse_args()

    cmake = Path(args.cmake)
    if not cmake.exists():
        print(f"error: cmake not found at {cmake}", file=sys.stderr)
        return 1

    package_root = Path(args.package_root)
    build_dir = Path(args.build_dir)
    dist_dir = Path(args.dist_dir)
    built_lib = dist_dir / "lib" / "libmsquic.a"

    archs = []
    for token in args.arch.replace(",", " ").replace(";", " ").split():
        if token and token not in archs:
            archs.append(token)
    if not archs:
        print("error: --arch must include at least one architecture.", file=sys.stderr)
        return 1
    arch_list = ";".join(archs)

    configure_args = [
        cmake,
        "-S",
        package_root,
        "-B",
        build_dir,
        "-DQUIC_BUILD_SHARED=OFF",
        # "-DQUIC_ENABLE_LOGGING=ON",
        # "-DQUIC_LOGGING_TYPE=stdout",
        "-DQUIC_BUILD_TOOLS=OFF",
        "-DQUIC_BUILD_TEST=OFF",
        "-DQUIC_BUILD_PERF=OFF",
        f"-DCMAKE_INSTALL_PREFIX={dist_dir}",
        f"-DCMAKE_BUILD_TYPE={args.configuration}",
    ]


    xcode_path = Path(args.xcode_path)

    default_cc = xcode_path / "Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    default_cxx = xcode_path / "Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
    cc = pick_compiler(args.cc or os.environ.get("MSQUIC_C_COMPILER"), default_cc, "C compiler")
    cxx = pick_compiler(args.cxx or os.environ.get("MSQUIC_CXX_COMPILER"), default_cxx, "C++ compiler")

    if cc:
        configure_args.append(f"-DCMAKE_C_COMPILER={cc}")
    if cxx:
        configure_args.append(f"-DCMAKE_CXX_COMPILER={cxx}")

    if args.generator:
        configure_args.extend(["-G", args.generator])
        if args.make_program:
            configure_args.append(f"-DCMAKE_MAKE_PROGRAM={args.make_program}")

    if args.platform == "ios":
        platform_path = xcode_path / "Contents/Developer/Platforms/iPhoneOS.platform" 
        sdk_path = platform_path / "Developer/SDKs/iPhoneOS.sdk"

        configure_args.extend(
            [
                "-DCMAKE_SYSTEM_NAME=iOS",
                "-DSDK_NAME=iphoneos",
                "-DDEPLOYMENT_TARGET=14.0",
                f"-DCMAKE_OSX_SYSROOT={sdk_path}",
                f"-DCMAKE_OSX_ARCHITECTURES={arch_list}",
            ]
        )
    elif args.platform == "simulator":
        platform_path = xcode_path / "Contents/Developer/Platforms/iPhoneSimulator.platform" 
        sdk_path = platform_path / "Developer/SDKs/iPhoneSimulator.sdk"

        configure_args.extend(
            [
                "-DCMAKE_SYSTEM_NAME=iOS",
                "-DSDK_NAME=iphonesimulator",
                "-DDEPLOYMENT_TARGET=14.0",
                f"-DCMAKE_OSX_SYSROOT={sdk_path}",
                f"-DCMAKE_OSX_ARCHITECTURES={arch_list}",
            ]
        )
    else:
        configure_args.extend(
            [
                "-DSDK_NAME=macosx",
                "-DDEPLOYMENT_TARGET=11.0",
                f"-DCMAKE_OSX_ARCHITECTURES={arch_list}",
            ]
        )

    run(configure_args)
    run([cmake, "--build", build_dir, "--target", "msquic_lib", "--config", args.configuration])
    run([cmake, "--install", build_dir])

    if not built_lib.exists():
        print(f"error: built library not found: {built_lib}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
