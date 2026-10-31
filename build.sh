#!/bin/sh
# Builds Ventoy for this machine's architecture into dist/:
#
#   ventoy-<arch>.onelf
#
# Nothing is compiled: upstream's release tarball carries the binaries
# and scripts, and the recipe assembles them into an AppDir whose GUI
# draws its GTK 3 stack from the shared gtk3 set at launch. The bundle
# updates itself from the latest release, accepting only updates signed
# with update.pub when the repository has one, and unsigned ones until
# then.
#
# Usage: build.sh
#
# Runs as root in a Void Linux (glibc) container with this directory as
# the working directory and onelf on PATH.
set -eu
cd "$(dirname "$0")"

arch=$(uname -m)
case $arch in
x86_64 | aarch64) ;;
*)
    echo "unsupported architecture: $arch" >&2
    exit 1
    ;;
esac

# toml <table> <key>: the string value of <key> in [<table>] of
# package.toml.
toml() {
    awk -v table="[$1]" -v key="$2" '
        /^\[/ { in_table = ($0 == table); next }
        in_table && $1 == key && $2 == "=" { gsub(/"/, "", $3); print $3; exit }
    ' package.toml
}

version=$(toml sources.ventoy version)
release=$(sed -n 's/^release = //p' package.toml)
gtk3_set_version=$(toml sets.gtk3 version)
gtk3_set_url=$(toml sets.gtk3 url | sed "s/{version}/$gtk3_set_version/; s/{arch}/$arch/")
gtk3_set_blake3=$(toml sets.gtk3.blake3 "$arch")
if [ -z "$gtk3_set_blake3" ]; then
    echo "the gtk3 set for $arch is not pinned yet; fill [sets.gtk3.blake3] from gtk v$gtk3_set_version" >&2
    exit 1
fi

# The runtime installs only a strictly newer revision, so a client is
# never rolled back: 1.1.18 release 2 is 1001018002. awk reads Ventoy's
# zero-padded parts, such as the 05 of 1.1.05, as decimal.
revision=$(echo "$version.$release" | awk -F. '
    NF != 4 { exit 1 }
    { for (i = 2; i <= 4; i++) if ($i >= 1000) exit 1 }
    { printf "%.0f", $1 * 1e9 + $2 * 1e6 + $3 * 1e3 + $4 }
') || {
    echo "version $version release $release does not fit an update revision" >&2
    exit 1
}
if [ -f update.pub ]; then
    trust="key = \"$PWD/update.pub\""
else
    trust="unsigned = true"
fi

xbps-install -Syu xbps > /dev/null
xbps-install -Syu > /dev/null
xbps-install -y curl findutils patchelf tar gzip xz libgcc > /dev/null

work=$PWD/build/work
file=build/src/ventoy-$version-linux.tar.gz
if [ ! -f "$file" ]; then
    mkdir -p build/src
    curl -fL --retry 3 -o "$file.part" \
        "https://github.com/ventoy/Ventoy/releases/download/v$version/ventoy-$version-linux.tar.gz"
    mv "$file.part" "$file"
fi
echo "$(toml sources.ventoy sha256)  $file" | sha256sum -c - > /dev/null

rm -rf "$work"
mkdir -p "$work"
tar -xzf "$file" -C "$work"
tree=$work/ventoy-$version
cd "$tree"

# Only this architecture's tools and GUI launcher stay: the scripts
# pick the tool directory from uname at runtime, so the others are dead
# weight. GTK 3 is the GUI backend the set supplies, so the others go.
rm -rf tool/i386 tool/mips64el
rm -f VentoyGUI.i386 VentoyGUI.mips64el
for other in x86_64 aarch64; do
    [ "$other" = "$arch" ] || rm -rf "tool/$other" "VentoyGUI.$other"
done
rm -f "tool/$arch/Ventoy2Disk.qt5" "tool/$arch/Ventoy2Disk.gtk2"

# The tools are xz-compressed in the tarball and the scripts decompress
# them into the install directory on first run; a bundle's tree is
# read-only, so they are decompressed here. The static mkexfatfs for
# musl hosts goes: the bundled binary runs everywhere.
for f in tool/$arch/*.xz; do
    xz -d "$f"
    chmod +x "${f%.xz}"
done
rm -f "tool/$arch/mkexfatfs_static"

# The scripts and tools write their logs and scratch files into the
# working directory, which in a bundle is the read-only package tree.
# Logs move to VENTOY_LOG, /tmp by default like the log.txt they were,
# scratch and mount directories to /tmp, and the chmods that prepared
# the tree for first use go: the build made it ready.
sed -i 's|>> \./log\.txt|>> ${VENTOY_LOG:-/tmp/ventoy-$UID.log}|g' Ventoy2Disk.sh
sed -i 's|^LOGFILE=log\.txt$|LOGFILE=${VENTOY_LOG:-/tmp/ventoy-$UID.log}|' VentoyWeb.sh
sed -i 's|>> \./VentoyPlugson\.log|>> ${VENTOY_LOG:-/tmp/ventoy-plugson-$UID.log}|g' VentoyPlugson.sh
sed -i 's|^chmod +x -R \./tool/\$TOOLDIR$|:|' VentoyPlugson.sh
sed -i 's|^chmod +x -R \./tool/\$TOOLDIR$|:|' Ventoy2Disk.sh
sed -i 's|\./tmp_mnt|/tmp/ventoy-tmp_mnt|g; s|\./diskuuid\.bin|/tmp/ventoy-diskuuid.bin|g; s|\./rsvdata\.bin|/tmp/ventoy-rsvdata.bin|g' tool/VentoyWorker.sh
sed -i 's|\./persist_tmp_mnt|/tmp/ventoy-persist_tmp_mnt|g' CreatePersistentImg.sh

# The GUI launcher picks its backend from what the host has installed;
# the bundle always means GTK 3.
echo gtk3 > ventoy_gui_type

for f in boot/boot.img ventoy/ventoy.disk.img.xz "tool/$arch/Ventoy2Disk.gtk3" WebUI/index.html; do
    if [ ! -f "$f" ]; then
        echo "the tree is missing $f" >&2
        exit 1
    fi
done

# The GTK 3 stack comes from the shared set, so the bundler must not
# pull it from the container even where the container has it. The
# recipe is checked in beside this script; its placeholders expand
# from this environment when onelf loads it. The update section names
# this architecture's asset, so it is added here.
export VENTOY_VERSION=$version
export VENTOY_GUI=VentoyGUI.$arch
export GTK3_SET_URL=$gtk3_set_url
export GTK3_SET_BLAKE3=$gtk3_set_blake3
cp "$OLDPWD/onelf.toml" "$tree/onelf.toml"
cat >> "$tree/onelf.toml" <<EOF

[update]
url = "https://github.com/onelf-pkgs/ventoy/releases/latest/download/ventoy-$arch.onelf"
revision = $revision
$trust
EOF

mkdir -p "$OLDPWD/dist"
onelf build "$tree" -o "$OLDPWD/dist/ventoy-$arch.onelf"

ls -l "$OLDPWD/dist"
