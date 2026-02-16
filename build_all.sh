#!/bin/sh
set -e

build_variant() {
  configuration="$1"
  build_root="$2"
  dist_root="$3"

  python3 build.py --build-dir "$build_root/ios" --dist-dir "$dist_root/ios" --platform ios --arch arm64 --configuration "$configuration"

  python3 build.py --build-dir "$build_root/ios-simulator" --dist-dir "$dist_root/ios-simulator" --platform simulator --arch arm64,x86_64 --configuration "$configuration"

  python3 build.py --build-dir "$build_root/macos" --dist-dir "$dist_root/macos" --platform macos --arch arm64,x86_64 --configuration "$configuration"

  CONFIGURATION="$configuration" DIST_DIR="$dist_root" bash build_xcframework.sh
}

# clean
rm -rfv dist dist_debug
rm -rfv build build_debug

# clean source code and re-apply patch
cd ./dependencies/msquic
git reset --hard

patch -p1 < ../../msquic-cmake-cpu-platform.patch
patch -p1 < ../../quictls-multiarch-support.patch

cd ../../

build_variant Release build dist
build_variant Debug build_debug dist_debug

echo "Done!"
