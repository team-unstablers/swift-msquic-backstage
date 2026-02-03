#!/bin/sh
set -e

# clean
rm -rfv dist
rm -rfv build

# clean source code and re-apply patch
cd ./dependencies/msquic
git reset --hard

patch -p1 < ../../msquic-cmake-cpu-platform.patch

cd ../../

# build
python3 build.py --build-dir build/ios --dist-dir dist/ios --platform ios --arch arm64 --configuration Release

python3 build.py --build-dir build/ios-simulator --dist-dir dist/ios-simulator --platform simulator --arch arm64,x86_64 --configuration Release

python3 build.py --build-dir build/macos --dist-dir dist/macos --platform macos --arch arm64,x86_64 --configuration Release

# build xcframework
sh build_xcframework.sh

echo "Done!"
