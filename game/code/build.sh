#!/bin/zsh
mkdir -p build
pushd build
COMMON_FLAGS=(-Werror -Wall -Wextra -Wpedantic -Wno-unused-function -Wno-deprecated-declarations)
xcrun -sdk macosx metal -c ../game/code/shaders.metal -o shaders.air $COMMON_FLAGS
xcrun -sdk macosx metallib shaders.air -o shaders.metallib
clang++ -g -O0 ../game/code/macOS_main.mm -o HandmadeGame -framework Cocoa -framework Metal -framework QuartzCore -framework GameController -framework AudioUnit $COMMON_FLAGS
popd
