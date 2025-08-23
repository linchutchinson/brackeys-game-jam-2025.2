#!/bin/sh

set -eu
cd "$(dirname "$0")"

for arg in "$@"; do declare $arg='1'; done

mkdir -p out

ODIN="odin-linux/odin"

FLAGS="-debug -out:out/bgj -strict-style -vet"

$ODIN build src $FLAGS
