#!/bin/sh
# Tests the Ventoy package build.sh wrote. Runs in the same container,
# right after it.
#
# The launches draw the gtk3 set the bundle pins from the gtk release,
# as on a user's machine. GTK3_SET_FILE names a local build of that set
# to launch against instead, such as one not released yet.
#
# Usage: test.sh
set -eu
cd "$(dirname "$0")"

arch=$(uname -m)

xbps-install -Syu xbps > /dev/null
xbps-install -Syu > /dev/null
xbps-install -y curl bash libgcc > /dev/null

packed=dist/ventoy-$arch.onelf
onelf verify "$packed"

# The tree inside the package must not write into the read-only
# working directory: every path the scripts wrote is redirected at
# build time, the tools are decompressed there, and only the GUI
# backend the gtk3 set serves stays.
extract=$(mktemp -d)
store=$(mktemp -d)
trap 'rm -rf "$extract" "$store"' EXIT
onelf extract "$packed" -o "$extract" --file Ventoy2Disk.sh \
    --file VentoyWeb.sh --file VentoyPlugson.sh --file tool/VentoyWorker.sh \
    --file CreatePersistentImg.sh --file ventoy_gui_type --file .onelf/sets
if grep -r -q -e '\./log\.txt' -e 'LOGFILE=log\.txt' -e '\./VentoyPlugson\.log' \
        -e '\./tmp_mnt' -e '\./diskuuid\.bin' -e '\./rsvdata\.bin' \
        -e '\./persist_tmp_mnt' -e 'chmod +x -R \./tool' "$extract"; then
    echo "the scripts still write into the package tree" >&2
    exit 1
fi
[ "$(cat "$extract/ventoy_gui_type")" = gtk3 ]
list=$(onelf list "$packed")
for path in "tool/$arch/Ventoy2Disk.qt5" "tool/$arch/Ventoy2Disk.gtk2" \
    "tool/$arch/mkexfatfs_static" "tool/i386" "tool/mips64el"
do
    case $list in
    *"$path"*)
        echo "the package carries $path" >&2
        exit 1
        ;;
    esac
done
for path in "tool/$arch/Ventoy2Disk.gtk3" "tool/$arch/vtoycli" "WebUI/index.html" \
    "boot/boot.img" "ventoy/ventoy.disk.img.xz"
do
    case $list in
    *"$path"*) : ;;
    *)
        echo "the package is missing $path" >&2
        exit 1
        ;;
    esac
done
set_hash=$(sed -n 's/^blake3 = "\(.*\)"/\1/p' "$extract/.onelf/sets")

# The launch fetches the set only when the store does not already hold
# the build its pin names.
if [ -n "${GTK3_SET_FILE:-}" ]; then
    mkdir -p "$store/gtk3"
    cp "$GTK3_SET_FILE" "$store/gtk3/$set_hash.onelf"
fi
export ONELF_PLATFORM_STORE=$store

# No arguments: the CLI prints its usage (and exits nonzero, as
# upstream's worker does).
"$packed" > "$extract/usage.txt" 2>&1 || true
grep -q "Usage" "$extract/usage.txt"

# The web UI serves on 127.0.0.1:24680.
ln -s "$(cd dist && pwd)/ventoy-$arch.onelf" ventoy-web
./ventoy-web > "$extract/web.log" 2>&1 &
web=$!
i=0
while [ $i -lt 30 ]; do
    if curl -sf http://127.0.0.1:24680/ > "$extract/index.html"; then
        break
    fi
    i=$((i + 1))
    sleep 1
done
kill "$web" 2> /dev/null || true
wait "$web" 2> /dev/null || true
grep -q "Ventoy" "$extract/index.html"
rm -f ventoy-web

# Plugson without a disk prints its usage.
ln -s "$(cd dist && pwd)/ventoy-$arch.onelf" ventoy-plugson
./ventoy-plugson > "$extract/plugson.txt" 2>&1
grep -q "Usage" "$extract/plugson.txt"
rm -f ventoy-plugson

echo "ventoy-$arch: verify, contents and launches ok"
