#!/bin/zsh
mkdir -p build
pushd build
clang++ -g -O0 ../game/code/macOS_main.mm -o HandmadeGame -framework Cocoa
popd
