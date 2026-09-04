#!/bin/zsh
mkdir -p build
pushd build
COMMON_FLAGS=(-Werror -Wall -Wextra -Wpedantic -Wno-unused-function -Wno-deprecated-declarations -Wno-gnu-anonymous-struct -Wno-nested-anon-types)
xcrun -sdk macosx metal -c ../code/shaders.metal -o shaders.air $COMMON_FLAGS
xcrun -sdk macosx metallib shaders.air -o shaders.metallib
clang++ -DHANDMADE_INTERNAL=1 -DHANDMADE_SLOW=1 -g -O0 ../code/macOS_main.mm -o HandmadeGame -framework Cocoa -framework Metal -framework QuartzCore -framework GameController -framework AudioUnit $COMMON_FLAGS
popd
