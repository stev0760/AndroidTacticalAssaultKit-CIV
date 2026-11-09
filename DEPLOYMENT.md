# ATAK-CIV: Self-Built Field Stack (Galaxy Tab A / LineageOS)

**Status:** Host APK built from this fork, installed, and verified on the target device. The S2 Underground plugins are **not yet usable**; see "Plugins" below.
**Date:** 2026-11-08
**Fork:** `github.com/stev0760/AndroidTacticalAssaultKit-CIV`, based on the archived `deptofdefense/AndroidTacticalAssaultKit-CIV` at ATAK-CIV **4.6.0.5**
**Target device:** Samsung Galaxy Tab A 10.1 (SM-T510), LineageOS 22.2 (Android 15, API 35), 32-bit userspace (`armeabi-v7a`), about 1.9 GB RAM, no Google Play Services
**Compliance note:** ATAK-CIV is subject to the US Export Administration Regulations (EAR). Building it for yourself is fine. Publishing binaries (for example as GitHub release assets) is a compliance question.

## Why self-build

The Play Store ATAK-CIV build is arm64-v8a only, so it can't install on a 32-bit-only ROM. This fork builds all three ABIs (armeabi-v7a, arm64-v8a, x86) into one APK, signed with our own key. It has no GMS dependency: location comes from the plain `LocationManager`.

## Build environment (container)

The 4.6 build needs 2021-era tools: NDK r12b (gcc/gnustl), JDK 8 (`javah`, Gradle 6.9), Conan 1.x and CMake 3.1x. A current Arch host can't provide these, so everything runs in an Ubuntu 20.04 container. The only host requirements are `podman` and `adb`.

One-time host setup (rootless podman needs subuids):

```sh
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER
podman system migrate
```

Files in `scripts/container/`:

| File | Purpose |
|---|---|
| `Containerfile` | Ubuntu 20.04 with OpenJDK 8 (first on PATH), ant, swig, autotools, cmake 3.16, Conan 1.66 |
| `run.sh [cmd]` | Runs a command, or a shell, in the container with the repo at `/src` |
| `run-bg.sh <name> '<cmd>'` | Runs a long step detached and logs to `.buildlogs/<name>.log`. Use this for anything that takes more than a couple of minutes |
| `package-deps.sh` | Second half of `scripts/prebuild.sh`: Conan and mavenLocal packaging |

Persistent state lives in `~/.cache/atak-build/`: the SDK, NDK r12b, `~/.gradle`, `~/.conan`, `~/.m2` and the **signing keystore** (`home/keys/atak-dev.jks`).

## Build from a fresh clone

```sh
podman build -t atak-build -f scripts/container/Containerfile scripts/container
scripts/container/run.sh bash -c 'git config --global --add safe.directory "*"; git lfs install --skip-repo; git lfs pull; git submodule update --init'
```

1. **SDK and NDK** (one-time, into the cache volume): NDK r12b from `dl.google.com/android/repository/android-ndk-r12b-linux-x86_64.zip`, unpacked to `/opt/android/`. Then use cmdline-tools `sdkmanager` (run it with JDK 11) to install `platforms;android-29`, `platforms;android-30`, `build-tools;30.0.2`, `build-tools;30.0.3` and `cmake;3.18.1` into `/opt/android/sdk`.
2. **Extract the modified third-party sources** to the repo root: `assimp`, `gdal`, `libLAS` and `LASzip` from `depends/*.tar.gz`.
3. **Third-party native build**, about 1 hour per ABI. Run the three in parallel:
   ```sh
   for T in armeabi-v7a arm64-v8a x86; do
     scripts/container/run-bg.sh ttp-$T "cd takthirdparty && make TARGET=android-$T GDAL_USE_KDU=no build_spatialite build_commoncommo build_gdal build_assimp"
   done
   ```
   The `ogdi ... install-so-link Error 1` lines are expected. Make ignores them.
4. **Package the dependencies**: `scripts/container/run-bg.sh package scripts/container/package-deps.sh`
5. **Signing:** create `atak/local.properties` and `atak/ATAK/local.properties` (git-ignored):
   ```ini
   sdk.dir=/opt/android/sdk
   ndk.dir=/opt/android/android-ndk-r12b
   cmake.dir=/opt/android/sdk/cmake/3.18.1
   takDebugKeyFile=/root/keys/atak-dev.jks
   takDebugKeyFilePassword=...
   takDebugKeyAlias=atak
   takDebugKeyPassword=...
   takReleaseKeyFile=/root/keys/atak-dev.jks
   takReleaseKeyFilePassword=...
   takReleaseKeyAlias=atak
   takReleaseKeyPassword=...
   ```
   Copy the same file to `takkernel/local.properties`. Paths are as the container sees them.
6. **APK** (takengine compiles from source, about 4 minutes on 24 cores):
   ```sh
   scripts/container/run-bg.sh apk "cd atak/ATAK && ./gradlew --no-daemon assembleCivRelease"
   ```
   Output: `atak/ATAK/app/build/outputs/apk/civ/release/ATAK-4.6.0.5-<sha>-civ-release.apk` (about 190 MB).

**Back up the keystore.** Every future update must be signed with the same key. Otherwise you have to uninstall first, which loses ATAK's data.

## Install

Plain `adb install` hung on this tablet, probably because of incremental install on Android 11+. Use:

```sh
adb push <apk> /data/local/tmp/atak.apk && adb shell pm install -r /data/local/tmp/atak.apk && adb shell rm /data/local/tmp/atak.apk
```

`adb install --no-incremental <apk>` should also work, but it isn't verified here.

On first launch, accept the EULA and grant location, "All files access" and notifications.

## Changes in this fork (vs. upstream 4.6.0.5)

- **Containerized build:** `scripts/container/`, plus a `.gitignore` for generated and secret files.
- **`takkernel/gradle/conan.gradle`:** no longer tries to add and log in to a Conan remote at `http://localhost` when no TAK repo is configured. It uses the local cache only.
- **Bundled map sources** (`atak/ATAK/app/src/main/assets/wms/`). Upstream deleted these in 4.2 but the code still referenced them, so a fresh install had only a blurry built-in world image. All are online sources, checked 2026-11-08:
  - Esri World Imagery (now the **default**), Esri World Topo, Esri World Street
  - OpenStreetMap, OpenTopoMap
  - USGS Topo, USGS Imagery Only, USGS Imagery Topo (US, zoom 15–16)
  - NRL OpenStreetMap, NRL DRG / DRG Mosaic, NRL FAA Sectionals, NRL NAIP (CONUS)
  - Dropped because the services are gone: NOAA RNC, NRL FAA TACs and WACs.
- **`AppVersionUpgrade`** deploys everything in `assets/wms` and redeploys when `WMS_SOURCES_VERSION` is bumped. **Bump it whenever you add or change sources.** It also migrates the stock `NRL-OpenStreetMap` default, which matched no layer name and showed a pale white globe, to `Esri World Imagery`.

Switch maps from **Maps & Favorites** (the folded-map icon) → **Mobile**. To use maps offline, select a source and use the download tool in that panel to cache an area. Check each provider's terms before bulk caching (OSM's tile servers in particular). Any MOBAC `customMapSource` XML dropped into `/sdcard/atak/imagery/mobile/mapsources/` also works.

## Plugins (S2 Underground)

S2's ATAK plugins all live under `github.com/s2underground`, with release APKs:

| Plugin | Repo | Purpose |
|---|---|---|
| Illum | `Illum-TAK` | Lunar/solar illumination, twilight times, terrain masking (NVG planning) |
| Quick Search | `QuickSearch-TAK` | Search bar and clipboard-coordinate jump |
| GhostMaps | `GhostMaps-TAK` | Browse/download/update S2's KMZ layers and icon sets from GitHub, no server needed |
| Blast | `Blast-TAK` | Blast-effects tool |
| HAZ-TAK | `HAZ-TAK` | HAZMAT response |
| TFR | `TFR-TAK` | FAA Temporary Flight Restrictions overlay |

### Current blocker: version mismatch (verified on device)

- The S2 release APKs declare `plugin-api = com.atakmap.app@5.6.0.CIV`. This fork is **4.6.0**.
- ATAK 4.6 requires an **exact** plugin-api match (`AtakPluginRegistry.isTakCompatible`). On the tablet, Illum 1.1.1 was detected and logged as `will NOT load`, and it doesn't appear in the Plugins list.
- **Signature:** 4.6 loads a plugin only if it's signed with the host's own key or a key in its built-in TAK list. S2's APKs are signed with "TAK Product Center ATAK Untrusted Plugin Release", which isn't in 4.6's list. So the **downloaded** plugin APKs can't work with **any** self-built host. Plugins have to be built from source and signed with our key.
- **Arch:** the plugins are pure Java (no `.so`), so 32-bit isn't a problem for them.

### Path forward

1. **Rebase the fork onto `TAK-Product-Center/atak-civ` 5.5.1.10**, the latest public source. It still builds `armeabi-v7a` (its `ndkAbiFiltersAll` includes it) and uses a newer toolchain (NDK 25, compileSdk 35). Expect to redo the build container for it. Its compatibility check also accepts older ≥4.10 plugins on a newer core.
2. **Build each S2 plugin from source** against the 5.5.1 SDK, signed with our keystore. The GhostMaps README says the plugins were already built against the 5.5.1.8 SDK, so setting `ATAK_VERSION=5.5.1` should be close to enough. Being signed with the host's key satisfies the signature check.
3. Install order: host APK → launch once → plugin APKs → ATAK prompts to load them.

### Without plugins, today

S2's KMZ layers (`github.com/s2underground/GhostMaps`: ArcGIS layer exports, Global Centers of Gravity, incident-response products) are plain KMZ. Download them to the tablet and open them with ATAK's **Import Manager**, or copy them into `/sdcard/atak/overlays/`. They appear under Overlay Manager. That also tests the GDAL/KML native stack.

Other S2 resources: the Obsidian research vault (`publish.obsidian.md/s2underground`), the NomadNet/Reticulum report mirror, and GhostNet (radio check-in net).

## Verify

1. `adb shell dumpsys package com.atakmap.app.civ | grep primaryCpuAbi` shows `armeabi-v7a`.
2. The app launches with no GMS. `adb logcat -b crash` stays empty, and there are no `UnsatisfiedLinkError`/`dlopen failed` messages.
3. The default map shows satellite imagery that sharpens as you zoom in.
4. A KMZ import renders.

## Rollback

`adb uninstall com.atakmap.app.civ`. App data and maps live under `/sdcard/atak/`; delete that at your discretion.

## Traps (learned the hard way)

- **Git LFS:** without `git lfs pull`, every `depends/` and `takthirdparty/distfiles/` tarball is a 130-byte pointer. (The host has no git-lfs, so `git status` on the host shows those tarballs as modified. Their contents are unchanged; don't commit them.)
- **Empty submodules** (`stl-soft`, `khronos/*`): run `git submodule update --init`.
- **JDK:** Ubuntu's `ant` package pulls in JDK 11. JDK 8 must be first on PATH, as the Containerfile sets it.
- **Conan 2 and CMake 4 both break the build.** The container pins Conan 1.66 and CMake 3.16/3.18.
- **`scripts/prebuild.sh` runs `rm -rf ~/.conan`**, which is harmless in the container but destructive on a host.
- **Long steps and tool timeouts:** run builds detached (`run-bg.sh`). The third-party make is serial and takes about 1 hour per ABI.
- **Screen off = ATAK paused.** With the tablet dozing, ATAK waits on its loading screen and the plugin scan never runs.
- **Hardware:** 1.9 GB RAM. It works, but heavy imagery and 3D are slow.
