# Xiaomi peridot (SM8650) Kernel

Custom kernel for **Xiaomi peridot** (POCO F6 / Redmi Turbo 3 — SM8650 / Snapdragon 8 Gen 3).
Based on [MiCode/Xiaomi_Kernel_OpenSource](https://github.com/MiCode/Xiaomi_Kernel_OpenSource), Android 14 GKI (kernel 6.1), built with Kleaf (Bazel).

| Item | Value |
|------|-------|
| Device | Xiaomi peridot / POCO F6 / Redmi Turbo 3 |
| SoC | SM8650 (Snapdragon 8 Gen 3, `pineapple` in Qualcomm build system) |
| Android | 14 (U) |
| Kernel | 6.1 GKI |
| Build system | Kleaf (Bazel-based) |
| Compiler | clang-r487747c (LLVM 17) |

---

## Prerequisites

- **OS**: Ubuntu 20.04 / 22.04 / 24.04 (or any Debian-based distro)
- **RAM**: 16 GB recommended (8 GB minimum)
- **Disk**: ~60 GB free (sources ≈ 15 GB, build output ≈ 30 GB)
- **Internet**: Required on first run (~500 MB clang tarball + source repos)

All other dependencies (git, python3, make, bison, flex, etc.) are installed automatically.

---

## Quick Start

```bash
# Clone this repo
git clone https://github.com/ApexLegend007/sm8650-peridot-kernel
cd sm8650-peridot-kernel

# Run the build script (interactive menu on first run)
./build.sh
```

Select **"1) Full setup + build"** for a first-time build. The script handles everything:
cloning sources, downloading clang, setting up the build environment, and compiling.

---

## Build Script

```
Usage:
  ./build.sh                    Interactive menu (recommended)
  ./build.sh --setup            Full first-time setup + build
  ./build.sh --build            Build only (sources already present)
  ./build.sh --clean            Wipe out/ cache and rebuild
  ./build.sh --sync             Sync/clone sources only, no build
  ./build.sh --flash            Flash latest build to device via fastboot
  ./build.sh --menuconfig       Open kernel menuconfig
  ./build.sh --help             Show full help

Options:
  --variant gki|consolidate     Build variant (default: gki)
  --skip-toolchain              Skip Clang/Bazelisk download
```

### Environment Variables

Override defaults without editing the script:

| Variable | Default | Description |
|----------|---------|-------------|
| `GITHUB_REMOTE` | `https://github.com/ApexLegend007` | Base URL for source repo mirrors |
| `GITHUB_PUSH_REMOTE` | *(empty)* | If set, push newly-cloned repos here |
| `MANIFEST_URL` | ApexLegend007 manifest URL | `repo` manifest URL |
| `MANIFEST_BRANCH` | `main` | manifest branch |

**Use your own fork as source:**
```bash
GITHUB_REMOTE=https://github.com/YourUsername ./build.sh --setup
```

**Push newly-cloned repos to your own GitHub:**
```bash
GITHUB_PUSH_REMOTE=https://github.com/YourUsername ./build.sh --sync
```

### What build.sh does — step by step

| Step | What happens |
|------|-------------|
| 1/7 System deps | Installs missing apt packages (git, python3, bison, flex, etc.) |
| 2/7 Sources | Clones all kernel source repos (detects git-cloned vs repo workflow) |
| 3/7 Toolchain | Downloads clang-r487747c from AOSP and Bazelisk |
| 4/7 Pre-build env | Creates hermetic PATH symlinks, generates Bazel Python toolchain stub |
| 5/7 Workspace | Writes `.bazelrc.user` with absolute cache path |
| 6/7 Clean | *(optional)* Wipes `out/` and Bazel cache |
| 7/7 Build | Runs `build_with_bazel.py -t peridot gki --skip abl` |

---

## Build Variants

| Variant | Description |
|---------|-------------|
| `gki` | Production GKI 2.0 image — **use this for flashing** |
| `consolidate` | Debug build with extra in-tree drivers |

---

## Output

Build artifacts are placed in `out/msm-kernel-peridot-<variant>/dist/`:

| Image | Description |
|-------|-------------|
| `Image` / `Image.lz4` | Raw / compressed kernel image |
| `boot.img` | Boot image |
| `dtbo.img` | Device tree overlay image |
| `vendor_boot.img` | Vendor boot image with ramdisk |
| `vendor_dlkm.img` | Vendor Dynamic Kernel Modules partition |
| `system_dlkm.img` | System Dynamic Kernel Modules partition |
| `*.ko` | All kernel modules (~130 vendor DLKMs) |
| `*.dtb` | Device trees |

---

## Flashing

```bash
# Reboot to fastboot
adb reboot bootloader

# Flash via script
./build.sh --flash

# Or manually
fastboot flash boot         out/msm-kernel-peridot-gki/dist/boot.img
fastboot flash vendor_boot  out/msm-kernel-peridot-gki/dist/vendor_boot.img
fastboot flash vendor_dlkm  out/msm-kernel-peridot-gki/dist/vendor_dlkm.img
fastboot flash system_dlkm  out/msm-kernel-peridot-gki/dist/system_dlkm.img
fastboot reboot
```

---

## Repository Layout

```
sm8650-peridot-kernel/              ← this repo (workspace root + build.sh)
├── build.sh                        ← main build & setup script
├── WORKSPACE                       ← Bazel workspace
├── .bazelrc                        ← Bazel build flags
├── msm-kernel/                     ← kernel source (cloned by build.sh)
│   └── arch/arm64/boot/dts/vendor/ ← device trees (cloned by build.sh)
├── build/
│   ├── kernel/                     ← Kleaf build framework (cloned by build.sh)
│   └── bazel_common_rules/         ← Bazel common rules (cloned by build.sh)
├── external/                       ← DTC, Bazel Skylib, abseil-py, stardoc
├── prebuilts/
│   ├── clang/host/linux-x86/
│   │   ├── clang-r487747c/         ← clang binary (downloaded by build.sh)
│   │   └── kleaf/                  ← Bazel toolchain rules (tracked in git)
│   └── kernel-build-tools/         ← avbtool, mkdtimg, etc. (cloned by build.sh)
├── tools/
│   ├── bazel                       ← Bazelisk binary (downloaded by build.sh)
│   └── mkbootimg/                  ← boot image builder (cloned by build.sh)
└── vendor/                         ← out-of-tree kernel modules (cloned by build.sh)
    ├── nxp/opensource/driver/      ← NXP NCI (NFC)
    └── qcom/opensource/
        ├── audio-kernel/           ← Audio (SPF, WCD, WSA, LPASS codecs)
        ├── bt-kernel/              ← Bluetooth (btpower, btfmcodec, BT/FM)
        ├── camera-kernel/          ← Camera subsystem
        ├── dataipa/                ← IPA (data path accelerator)
        ├── datarmnet/              ← RmNet core/ctl
        ├── datarmnet-ext/          ← RmNet extensions
        ├── display-drivers/        ← MSM DRM display
        ├── dsp-kernel/             ← FASTRPC / CDSP loader
        ├── eva-kernel/             ← EVA (video accelerator)
        ├── fingerprint/            ← Fingerprint (QBT handler)
        ├── graphics-kernel/        ← GPU (MSM KGSL)
        ├── mm-drivers/             ← HW fence / sync fence / ext display
        ├── mm-sys-kernel/          ← UBWCP
        ├── mmrm-driver/            ← MMRM (multimedia resource manager)
        ├── securemsm-kernel/       ← TrustZone / QSEECom / crypto
        ├── spu-kernel/             ← SPU (SPCOM / SPSS)
        ├── synx-kernel/            ← SYNX / IPClite
        ├── touch-drivers/          ← Touchscreen (NT36xxx, Goodix, Synaptics, …)
        ├── video-driver/           ← Video codec (Venus)
        └── wlan/
            ├── platform/           ← CNSS2 / iCNSS2 / WLAN platform
            └── qcacld-3.0/         ← QCA WLAN driver
```

Items not tracked in this git repo (created by `build.sh` in Step 4):
- `prebuilts/clang/host/linux-x86/clang-r487747c/` — downloaded from AOSP (~500 MB)
- `prebuilts/build-tools/path/linux-x86/` — machine-local hermetic PATH symlinks
- `prebuilts/build-tools/linux-x86/bin/` — tool symlinks (bison, flex, etc.)
- `prebuilts/build-tools/common/bison/` — symlink to system bison data (`/usr/share/bison`)
- `prebuilts/build-tools/BUILD.bazel` — Bazel Python toolchain stub (generated)
- `prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8/sysroot/` — host sysroot symlinks (selective, no paths with spaces)
- `prebuilts/jdk/jdk11/linux-x86` — symlink to system JDK
- `prebuilts/ndk-r23/` — minimal NDK stub (only a .keep marker is needed)
- `build/BUILD.bazel` — Bazel package root (also tracked via gitignore exception)
- `tools/bazel` — Bazelisk binary
- `out/` — build output

---

## Source Repositories

| Component | Repo | Branch |
|-----------|------|--------|
| Workspace (this repo) | [ApexLegend007/sm8650-peridot-kernel](https://github.com/ApexLegend007/sm8650-peridot-kernel) | `main` |
| Manifest | [ApexLegend007/peridot-kernel-manifest](https://github.com/ApexLegend007/peridot-kernel-manifest) | `main` |
| Kernel source | [ApexLegend007/peridot-msm-kernel](https://github.com/ApexLegend007/peridot-msm-kernel) | `peridot-u-oss` |
| Device tree | [ApexLegend007/peridot-kernel-devicetree](https://github.com/ApexLegend007/peridot-kernel-devicetree) | `peridot-u-oss` |
| Build framework | [ApexLegend007/peridot-kernel-build](https://github.com/ApexLegend007/peridot-kernel-build) | `peridot-u-oss` |
| Vendor modules | [ApexLegend007/kernel_xiaomi_sm8650-modules](https://github.com/ApexLegend007/kernel_xiaomi_sm8650-modules) | `main` |

---

## Troubleshooting

**"Label is invalid because ... is not a package"**
→ The `prebuilts/clang/host/linux-x86/kleaf/` Bazel rules directory is missing.
Run `./build.sh --setup` — it will re-run the full setup including cloning all repos.

**"Clang download failed"**
→ AOSP may be rate-limiting. Download manually:
```bash
mkdir -p prebuilts/clang/host/linux-x86/clang-r487747c
curl -L 'https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android14-release/clang-r487747c.tar.gz' \
  | tar -xz -C prebuilts/clang/host/linux-x86/clang-r487747c
```

**"The repository's path is 'prebuilts/jdk/jdk11/linux-x86' but this directory does not exist"**
→ JDK prebuilts not set up. Run `./build.sh --build` to trigger Step 4 setup, or install Java manually:
```bash
sudo apt-get install -y default-jdk
```

**"The repository's path is 'prebuilts/ndk-r23' but this directory does not exist"**
→ NDK stub missing. Run `./build.sh --build` — Step 4 creates it automatically.

**"Too many levels of symbolic links" in build/kernel/build-tools**
→ Stale symlink loop from an old build.sh run. Remove and re-run:
```bash
rm -f prebuilts/build-tools/path/linux-x86/true prebuilts/build-tools/path/linux-x86/echo
./build.sh --build
```

**"glob pattern 'build-tools/sysroot/**' didn't match anything"**
→ Host sysroot not created. Run `./build.sh --build` — Step 4 sets it up automatically.

**"link or target filename contains space" (espeak-ng-data or similar)**
→ A stale sysroot from an older `build.sh` used a full-directory symlink that Bazel can't handle (filenames with spaces). Remove and recreate:
```bash
rm -rf prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8/sysroot
./build.sh --build
```

**"Expects toybox for tar"**
→ Stale `tar` symlink points directly to `/usr/bin/tar` instead of `toybox`. Remove and recreate:
```bash
rm -f prebuilts/build-tools/path/linux-x86/tar prebuilts/build-tools/path/linux-x86/toybox
./build.sh --build
```

**"cannot open: prebuilts/build-tools/common/bison/m4sugar/m4sugar.m4"**
→ Bison data directory missing or empty. Remove and recreate:
```bash
rm -rf prebuilts/build-tools/common/bison
./build.sh --build
```

**Build fails with stale cache after a source change**
→ Run `./build.sh --clean` to wipe `out/` and the Bazel cache.

**"repo init" fails with "unsupported checkout state"**
→ You are in a git-cloned root. `build.sh` detects this and uses `git clone` per-repo automatically. No action needed.

**sudo fails non-interactively (no password prompt)**
→ Normal behavior in CI or background sessions. `build.sh` skips apt-get when sudo isn't available and continues. Install required packages manually if the build fails due to missing system tools:
```bash
sudo apt-get install -y git curl wget python3 make bc bison flex cpio rsync \
  zip unzip libssl-dev libelf-dev build-essential libncurses-dev \
  gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu lz4 zstd e2fsprogs \
  device-tree-compiler xxd xz-utils bzip2 default-jdk
```

**"ModuleNotFoundError: No module named 'symbol_extraction'"**
→ Kleaf's KMI symbol check can't import its sibling module. Fixed in `peridot-kernel-build` by adding
`imports = ["abi"]` to the `symbol_extraction` py_library. Pull the latest build/kernel and rebuild:
```bash
git -C build/kernel pull
./build.sh --clean && ./build.sh --build
```

**If all else fails — full clean reset of generated files:**
```bash
rm -rf prebuilts/build-tools/path prebuilts/build-tools/linux-x86/bin \
       prebuilts/build-tools/common prebuilts/build-tools/BUILD.bazel \
       prebuilts/build-tools/python3.exe \
       prebuilts/gcc prebuilts/jdk prebuilts/ndk-r23 \
       out/
./build.sh --build
```

---

## License

Kernel sources are licensed under GPL-2.0. See individual source trees for full license text.
