# ventoy

[Ventoy](https://www.ventoy.net) packed for [onelf](https://github.com/QaidVoid/onelf)
packages: the USB boot tool as one file per architecture, instead of a
tarball to extract and `cd` into.

## What is different from upstream's tarball

- **One file, seven commands.** The packed binary selects what to run
  from its name: `ventoy` (the CLI, also the default), `ventoy-web`
  (the browser UI on 127.0.0.1:24680), `ventoy-plugson` (the plugin
  configuration UI on 127.0.0.1:24681), `ventoy-gui`, `ventoy-vlnk`,
  `ventoy-create-persistent` and `ventoy-extend-persistent`. A symlink
  named for the command, or `ONELF_ENTRYPOINT`, picks one.
- **No compilation.** Upstream ships prebuilt binaries and scripts;
  what upstream releases is what this carries, checked against the
  SHA-256 in `package.toml`.
- **The GUI is GTK 3, from the [gtk](https://github.com/onelf-pkgs/gtk)
  set.** Upstream's launcher picks its backend from what the host has
  installed; here a `ventoy_gui_type` file pins GTK 3, the Qt and GTK 2
  backends are dropped, and the toolkit is fetched at launch from the
  set the recipe pins by hash. A host without GTK therefore runs the
  GUI anyway.
- **One architecture per package.** The tarball carries i386, x86_64,
  aarch64 and mips64el; each build keeps its own tool directory and
  launcher, since the scripts pick the directory from `uname` anyway.
- **The tree is read-only, and that is fine.** Upstream decompresses
  `tool/<arch>/*.xz` into the install directory on first run and writes
  its logs and scratch files there. The tools are decompressed at build
  time, the logs go to `$VENTOY_LOG`, `/tmp` by default, and the
  scratch and mount directories to `/tmp`.
- **It updates itself.** The bundle fetches the latest release's asset
  for its architecture, downloading only what changed, and accepts only
  updates signed with the key in `update.pub`.
- **musl hosts, without the static swap.** Upstream swaps to a static
  `mkexfatfs` when it detects musl; the bundled binary runs everywhere
  through the package's own glibc, so the swap and its static copy are
  gone.

Still true of Ventoy itself: creating drives needs root, and the
scripts drive the host's `fdisk`, `mkfs.vfat`, `losetup` and friends.
The browser UI and Plugson need `bash`, as upstream's scripts are
written for it. Logs go to `$VENTOY_LOG`, `/tmp` by default; scratch
and mount directories go to `/tmp`.

## Releases

Tagged `v<ventoy version>-<release>`, where `release` counts rebuilds
of the same Ventoy. Each release carries, per architecture:

| Asset | Holds |
|-------|-------|
| `ventoy-<arch>.onelf` | the whole tool, every entrypoint |
| `ventoy-<arch>.onelf.sig` | its signature, which the self-update checks |

At launch the package fetches the gtk3 set it pins, unless the host
store already holds that build.

## Building

```sh
podman run --rm -v "$PWD:/src" -v "$(command -v onelf):/usr/local/bin/onelf:ro" -w /src \
  ghcr.io/void-linux/void-glibc:latest sh build.sh
```

Versions and hashes are in `package.toml`, including the gtk3 set's
pin. `test.sh` runs the packed file in the same container, against the
pinned set or a local build named by `GTK3_SET_FILE`. The
[control repository](https://github.com/onelf-pkgs/.github) bumps the
sources here when upstream releases, and provides `update.pub`.

## Licensing

Ventoy's own code is GPL-3.0-or-later. The release tarball also embeds
prebuilt third-party binaries under their own licenses, which upstream
documents in its `License/` directory; this package redistributes them
unmodified, as the AUR and NixOS packages do.
