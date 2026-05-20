#!/bin/bash
# =============================================================================
#  Xiaomi peridot (SM8650) — Kernel Build & Setup Script
#  Device  : Xiaomi peridot / POCO F6 / Redmi Turbo 3
#  SoC     : SM8650 / Snapdragon 8 Gen 3 (pineapple)
#  Kernel  : Android 14, GKI 2.0, kernel 6.1
#  Build   : Kleaf (Bazel-based Android kernel build)
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

# ── colours ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
    BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BLUE=''; MAGENTA=''
    BOLD=''; DIM=''; NC=''
fi

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[FAIL]${NC}  $*" >&2; exit 1; }
step()  { echo -e "\n${BOLD}${BLUE}════${NC}${BOLD}  $*  ${BLUE}════${NC}"; }
banner(){ echo -e "${BOLD}${MAGENTA}$*${NC}"; }
ask()   { echo -en "${BOLD}${YELLOW}  → $*${NC} "; }

# =============================================================================
# Configuration — all values here are safe defaults for any user.
# Override with environment variables before running if needed.
# =============================================================================

# Source of all mirrored kernel repos (public, read-only).
# Change to your own mirror URL if you've forked these repos.
GITHUB_REMOTE="${GITHUB_REMOTE:-https://github.com/ApexLegend007}"

# Set GITHUB_PUSH_REMOTE to push newly-cloned repos to your own GitHub.
# Example: export GITHUB_PUSH_REMOTE=https://github.com/YOUR_USERNAME
# Leave empty (default) to skip auto-push.
GITHUB_PUSH_REMOTE="${GITHUB_PUSH_REMOTE:-}"

MANIFEST_URL="${MANIFEST_URL:-https://github.com/ApexLegend007/peridot-kernel-manifest}"
MANIFEST_BRANCH="${MANIFEST_BRANCH:-main}"

CLANG_VERSION="r487747c"
CLANG_DIR="$ROOT_DIR/prebuilts/clang/host/linux-x86/clang-$CLANG_VERSION"
CLANG_ARCHIVE_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android14-release/clang-${CLANG_VERSION}.tar.gz"

BAZELISK_VER="v1.19.0"
BAZELISK_URL="https://github.com/bazelbuild/bazelisk/releases/download/${BAZELISK_VER}/bazelisk-linux-amd64"
BAZEL_BIN="$ROOT_DIR/tools/bazel"

KERNEL_DIR="$ROOT_DIR/msm-kernel"

# ── state ─────────────────────────────────────────────────────────────────────
INTERACTIVE=false
DO_SYNC=false
DO_CLEAN=false
SKIP_TOOLCHAIN=false
SKIP_BUILD=false
DO_MENUCONFIG=false
DO_FLASH=false
VARIANT="gki"

# ── help ──────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF

${BOLD}Usage:${NC}
  ./build.sh                    Interactive menu (recommended for first run)
  ./build.sh --setup            Full first-time setup + build
  ./build.sh --build            Build only (sources must be present)
  ./build.sh --clean            Clean build (wipe out/ then build)
  ./build.sh --sync             Sync/clone sources only, no build
  ./build.sh --flash            Flash latest build to device via fastboot
  ./build.sh --menuconfig       Open kernel menuconfig
  ./build.sh --help             Show this help

${BOLD}Options (combinable):${NC}
  --variant gki|consolidate     Build variant (default: gki)
  --skip-toolchain              Skip Clang/Bazelisk download step

${BOLD}Environment variables:${NC}
  GITHUB_REMOTE=<url>           Override repo mirror URL (default: ApexLegend007)
  GITHUB_PUSH_REMOTE=<url>      Push newly-cloned repos to this remote (optional)
  MANIFEST_URL=<url>            Override repo manifest URL
  MANIFEST_BRANCH=<branch>      Override manifest branch (default: main)

${BOLD}Examples:${NC}
  ./build.sh                          # interactive menu
  ./build.sh --setup                  # full first-time setup + build
  ./build.sh --clean                  # wipe out/ and rebuild
  ./build.sh --build --variant consolidate
  ./build.sh --sync --build           # re-sync then build
  GITHUB_PUSH_REMOTE=https://github.com/YourUser ./build.sh --setup

EOF
}

# ── argument parsing ──────────────────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
    INTERACTIVE=true
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --setup)           DO_SYNC=true ;;
        --sync)            DO_SYNC=true; SKIP_BUILD=true ;;
        --build)           : ;;
        --clean)           DO_CLEAN=true ;;
        --flash)           DO_FLASH=true; SKIP_BUILD=true ;;
        --menuconfig)      DO_MENUCONFIG=true ;;
        --skip-toolchain)  SKIP_TOOLCHAIN=true ;;
        --variant)         VARIANT="$2"; shift ;;
        --help|-h)         usage; exit 0 ;;
        *) echo -e "${RED}Unknown option:${NC} $1  (use --help)"; exit 1 ;;
    esac
    shift
done

# ── banner ────────────────────────────────────────────────────────────────────
clear_screen() { [[ -t 1 ]] && clear || true; }

print_banner() {
    echo ""
    banner "╔══════════════════════════════════════════════════════╗"
    banner "║   Xiaomi peridot (SM8650) Kernel Build               ║"
    banner "║   Android 14 · GKI 2.0 · kernel 6.1 · Kleaf/Bazel   ║"
    banner "╚══════════════════════════════════════════════════════╝"
    echo ""
}

# ── source status helper ──────────────────────────────────────────────────────
source_status() {
    local kernel vendor build toolchain bazel
    [[ -d "$KERNEL_DIR/arch" ]]                               && kernel="${GREEN}✓${NC}"    || kernel="${RED}✗${NC}"
    [[ -d "$ROOT_DIR/vendor/qcom/opensource/audio-kernel" ]]  && vendor="${GREEN}✓${NC}"    || vendor="${RED}✗${NC}"
    [[ -d "$ROOT_DIR/build/kernel/kleaf" ]]                   && build="${GREEN}✓${NC}"     || build="${RED}✗${NC}"
    [[ -f "$CLANG_DIR/bin/clang" ]]                           && toolchain="${GREEN}✓${NC}" || toolchain="${YELLOW}↓${NC}"
    [[ -x "$BAZEL_BIN" ]]                                     && bazel="${GREEN}✓${NC}"     || bazel="${YELLOW}↓${NC}"

    echo -e "  ${DIM}Sources:${NC}  kernel $kernel  vendor $vendor  build-fw $build"
    echo -e "  ${DIM}Tools:${NC}    clang $toolchain  bazel $bazel"
    echo ""
}

# ── interactive menu ──────────────────────────────────────────────────────────
interactive_menu() {
    clear_screen
    print_banner
    source_status

    echo -e "${BOLD}  What do you want to do?${NC}"
    echo ""
    echo -e "   ${BOLD}1)${NC} Full setup + build   ${DIM}(sync sources, download toolchain, build)${NC}"
    echo -e "   ${BOLD}2)${NC} Build only           ${DIM}(sources already present)${NC}"
    echo -e "   ${BOLD}3)${NC} Clean build          ${DIM}(wipe out/ cache and rebuild)${NC}"
    echo -e "   ${BOLD}4)${NC} Sync sources only    ${DIM}(clone/update repos, no build)${NC}"
    echo -e "   ${BOLD}5)${NC} Menuconfig           ${DIM}(configure kernel options interactively)${NC}"
    echo -e "   ${BOLD}6)${NC} Flash to device      ${DIM}(fastboot flash latest build)${NC}"
    echo -e "   ${BOLD}0)${NC} Exit"
    echo ""
    ask "Choose [0-6]:"
    read -r CHOICE

    case "$CHOICE" in
        1) DO_SYNC=true ;;
        2) : ;;
        3) DO_CLEAN=true ;;
        4) DO_SYNC=true; SKIP_BUILD=true ;;
        5) DO_MENUCONFIG=true ;;
        6) DO_FLASH=true; SKIP_BUILD=true ;;
        0) echo ""; exit 0 ;;
        *) warn "Invalid choice '$CHOICE'"; sleep 1; interactive_menu; return ;;
    esac

    # variant selection (skip for sync/flash only)
    if [[ "$SKIP_BUILD" == false && "$DO_FLASH" == false ]]; then
        echo ""
        echo -e "${BOLD}  Build variant:${NC}"
        echo -e "   ${BOLD}1)${NC} gki         ${DIM}(default — GKI 2.0 image, recommended for flashing)${NC}"
        echo -e "   ${BOLD}2)${NC} consolidate ${DIM}(debug build with extra in-tree drivers)${NC}"
        echo ""
        ask "Choose [1-2, default=1]:"
        read -r VCHOICE
        case "$VCHOICE" in
            2) VARIANT="consolidate" ;;
            *) VARIANT="gki" ;;
        esac
    fi

    echo ""
}

# ── flash helper ──────────────────────────────────────────────────────────────
do_flash() {
    step "Flash to device"

    local DIST_DIR="$ROOT_DIR/out/msm-kernel-peridot-gki/dist"
    [[ -d "$DIST_DIR" ]] || err "No build found at $DIST_DIR — build first"

    echo ""
    echo -e "${BOLD}  Images to flash from:${NC} $DIST_DIR"
    echo ""

    for f in boot.img vendor_boot.img vendor_dlkm.img system_dlkm.img dtbo.img; do
        if [[ -f "$DIST_DIR/$f" ]]; then
            printf "   ${GREEN}✓${NC}  %-30s  %s\n" "$f" "$(du -sh "$DIST_DIR/$f" 2>/dev/null | cut -f1)"
        else
            printf "   ${YELLOW}–${NC}  %-30s  not found\n" "$f"
        fi
    done

    echo ""
    warn "Make sure your device is in fastboot mode (adb reboot bootloader)"
    ask "Flash now? [y/N]:"
    read -r CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { info "Flash cancelled."; return; }

    echo ""
    local FAILED=0

    for pair in \
        "boot:$DIST_DIR/boot.img" \
        "vendor_boot:$DIST_DIR/vendor_boot.img" \
        "vendor_dlkm:$DIST_DIR/vendor_dlkm.img" \
        "system_dlkm:$DIST_DIR/system_dlkm.img" \
        "dtbo:$DIST_DIR/dtbo.img"
    do
        local part="${pair%%:*}"
        local img="${pair##*:}"
        [[ -f "$img" ]] || continue
        info "fastboot flash $part ..."
        if fastboot flash "$part" "$img"; then
            ok "Flashed $part"
        else
            warn "Failed to flash $part"
            FAILED=$((FAILED + 1))
        fi
    done

    if [[ $FAILED -eq 0 ]]; then
        echo ""
        ask "Reboot device now? [Y/n]:"
        read -r REBOOT
        [[ "$REBOOT" =~ ^[Nn]$ ]] || fastboot reboot
        ok "Done."
    else
        warn "$FAILED partition(s) failed to flash"
    fi
}

# ── run interactive menu ───────────────────────────────────────────────────────
[[ "$INTERACTIVE" == true ]] && interactive_menu

# ── flash only mode ───────────────────────────────────────────────────────────
if [[ "$DO_FLASH" == true ]]; then
    do_flash
    exit 0
fi

# ── header for non-interactive runs ───────────────────────────────────────────
[[ "$INTERACTIVE" == false ]] && print_banner

###############################################################################
# Step 1 — System dependencies
###############################################################################
step "Step 1/7 — System dependencies"

PKGS=(git curl wget python3 make bc bison flex cpio rsync zip unzip
      libssl-dev libelf-dev build-essential libncurses-dev
      gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu
      lz4 zstd e2fsprogs device-tree-compiler
      xxd xz-utils bzip2 default-jdk)

MISSING=()
for p in "${PKGS[@]}"; do
    dpkg -s "$p" &>/dev/null || MISSING+=("$p")
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    info "Missing packages: ${MISSING[*]}"
    if sudo -n true 2>/dev/null; then
        # Passwordless sudo available (CI / configured system)
        sudo apt-get update -qq || true
        sudo apt-get install -y "${MISSING[@]}" || warn "Some packages failed to install — continuing"
    elif [[ -t 0 ]]; then
        # Interactive terminal — prompt for sudo password
        info "Installing missing packages (sudo password may be required) ..."
        sudo apt-get update -qq || true
        sudo apt-get install -y "${MISSING[@]}" || warn "Some packages failed to install — continuing"
    else
        # Non-interactive, no passwordless sudo — skip and warn
        warn "Cannot install packages automatically (no interactive terminal and sudo requires a password)."
        warn "Please install manually: sudo apt-get install -y ${MISSING[*]}"
        warn "Continuing — build may fail if critical packages are missing."
    fi
fi
ok "All dependencies satisfied"

###############################################################################
# Step 2 — Source sync
###############################################################################
step "Step 2/7 — Sources"

ensure_repo_tool() {
    if command -v repo &>/dev/null; then return; fi
    info "Installing repo tool ..."
    mkdir -p "$HOME/bin"
    curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o "$HOME/bin/repo"
    chmod +x "$HOME/bin/repo"
    export PATH="$HOME/bin:$PATH"
    ok "repo installed"
}

# Clone a single repo only if the target path is not already a git repo.
# Usage: git_clone_if_missing <repo_name> <dest_path> <branch> [remote_base_url]
git_clone_if_missing() {
    local repo_name="$1" dest="$2" branch="$3"
    local remote="${4:-$GITHUB_REMOTE}"
    if [[ -d "$ROOT_DIR/$dest/.git" || -f "$ROOT_DIR/$dest/HEAD" ]]; then
        return 0
    fi
    info "  Cloning $repo_name → $dest ..."
    mkdir -p "$(dirname "$ROOT_DIR/$dest")"
    git clone --depth=1 -b "$branch" "$remote/$repo_name" "$ROOT_DIR/$dest"
}

# Push a newly-cloned repo to GITHUB_PUSH_REMOTE if set.
# Skips silently if the remote push target already exists or push fails.
push_repo_if_configured() {
    local dest="$1" repo_name="$2"
    [[ -n "$GITHUB_PUSH_REMOTE" ]] || return 0
    local full_path="$ROOT_DIR/$dest"
    [[ -d "$full_path/.git" ]] || return 0

    local push_url="$GITHUB_PUSH_REMOTE/$repo_name"
    info "  Pushing $repo_name to $push_url ..."
    git -C "$full_path" remote set-url origin "$push_url" 2>/dev/null || \
        git -C "$full_path" remote add push-target "$push_url" 2>/dev/null || true
    git -C "$full_path" push origin HEAD 2>/dev/null || \
        git -C "$full_path" push push-target HEAD 2>/dev/null || \
        warn "  Could not push $repo_name (may already exist upstream or auth needed)"
}

# Sync all repos via individual git clones.
# Used when we are already inside a git-cloned root (.git exists, .repo does not).
git_sync_all() {
    info "Cloning all source repos from $GITHUB_REMOTE ..."

    # msm-kernel MUST come first; devicetree is a subdirectory of it
    git_clone_if_missing peridot-msm-kernel              msm-kernel                            peridot-u-oss

    # Clone everything else in parallel
    git_clone_if_missing peridot-kernel-devicetree       msm-kernel/arch/arm64/boot/dts/vendor peridot-u-oss  &
    git_clone_if_missing peridot-kernel-build            build/kernel                          peridot-u-oss  &
    git_clone_if_missing peridot-bazel-common-rules      build/bazel_common_rules              android14-release &
    git_clone_if_missing peridot-external-dtc            external/dtc                          master         &
    git_clone_if_missing peridot-external-bazel-skylib   external/bazel-skylib                 master         &
    git_clone_if_missing peridot-external-absl-py        external/python/absl-py               master         &
    git_clone_if_missing peridot-external-stardoc        external/stardoc                      main           &
    git_clone_if_missing peridot-kernel-prebuilts-build-tools prebuilts/kernel-build-tools     main           &
    git_clone_if_missing kernel_xiaomi_sm8650-modules    vendor                                main           &
    git_clone_if_missing platform/system/tools/mkbootimg tools/mkbootimg                       android14-release \
        https://android.googlesource.com                                                                       &
    wait

    ok "All repos cloned"

    # Optional: push newly-cloned repos to user's own GitHub
    if [[ -n "$GITHUB_PUSH_REMOTE" ]]; then
        info "Pushing repos to $GITHUB_PUSH_REMOTE ..."
        for pair in \
            "msm-kernel:peridot-msm-kernel" \
            "msm-kernel/arch/arm64/boot/dts/vendor:peridot-kernel-devicetree" \
            "build/kernel:peridot-kernel-build" \
            "build/bazel_common_rules:peridot-bazel-common-rules" \
            "external/dtc:peridot-external-dtc" \
            "external/bazel-skylib:peridot-external-bazel-skylib" \
            "external/python/absl-py:peridot-external-absl-py" \
            "external/stardoc:peridot-external-stardoc" \
            "prebuilts/kernel-build-tools:peridot-kernel-prebuilts-build-tools" \
            "vendor:kernel_xiaomi_sm8650-modules"
        do
            local dest="${pair%%:*}" rname="${pair##*:}"
            push_repo_if_configured "$dest" "$rname" &
        done
        wait
        ok "Push complete (or skipped for already-existing repos)"
    fi
}

# repo-based sync (for fresh empty directory, no .git at root)
repo_sync_all() {
    ensure_repo_tool
    export PATH="$HOME/bin:$PATH"

    if [[ ! -d "$ROOT_DIR/.repo" ]]; then
        info "Initialising repo manifest ..."
        info "  URL   : $MANIFEST_URL"
        info "  Branch: $MANIFEST_BRANCH"
        repo init -u "$MANIFEST_URL" -b "$MANIFEST_BRANCH" --depth=1
    else
        info ".repo already initialised — updating"
    fi

    info "Syncing sources ($(nproc) parallel jobs) ..."
    repo sync -c --no-tags --no-clone-bundle -j"$(nproc)"
    ok "repo sync complete"
}

# Auto-trigger sync if sources are missing
if [[ ! -d "$KERNEL_DIR/arch" ]] && [[ "$DO_SYNC" == false ]]; then
    warn "Kernel sources not found — triggering sync automatically"
    DO_SYNC=true
fi

if [[ "$DO_SYNC" == true ]]; then
    # If we are inside a git-cloned root (has .git but no .repo),
    # repo init would conflict with the existing checkout.
    # Use individual git clones instead — faster and always safe.
    if [[ -d "$ROOT_DIR/.git" && ! -d "$ROOT_DIR/.repo" ]]; then
        info "Detected git-cloned root — using per-repo git clone strategy"
        git_sync_all
    else
        repo_sync_all
    fi
fi

[[ -d "$KERNEL_DIR/arch" ]]                               || err "msm-kernel missing — run with --setup"
[[ -d "$ROOT_DIR/build/kernel/kleaf" ]]                   || err "build/kernel missing — run with --setup"
[[ -d "$ROOT_DIR/vendor/qcom/opensource/audio-kernel" ]]  || err "vendor modules missing — run with --setup"
ok "All sources present"

###############################################################################
# Step 3 — Toolchain (Clang + Bazelisk)
###############################################################################
step "Step 3/7 — Toolchain"

if [[ "$SKIP_TOOLCHAIN" == false ]]; then

    # ── Clang ────────────────────────────────────────────────────────────────
    if [[ -f "$CLANG_DIR/bin/clang" ]]; then
        ok "clang-$CLANG_VERSION already present ($("$CLANG_DIR/bin/clang" --version | head -1))"
    else
        info "Downloading clang-$CLANG_VERSION (~500 MB) ..."
        mkdir -p "$CLANG_DIR"
        if ! curl -fL --retry 5 --retry-delay 10 --progress-bar \
                "$CLANG_ARCHIVE_URL" | tar -xz -C "$CLANG_DIR"; then
            rm -rf "$CLANG_DIR"
            err "Clang download failed.
  Manual download:
    mkdir -p $CLANG_DIR
    curl -L '$CLANG_ARCHIVE_URL' | tar -xz -C $CLANG_DIR"
        fi
        find "$CLANG_DIR/bin" -type f -exec chmod +x {} \; 2>/dev/null || true
        [[ -f "$CLANG_DIR/bin/clang" ]] || err "clang binary missing after extract"
        ok "Clang ready: $("$CLANG_DIR/bin/clang" --version | head -1)"
    fi

    # ── Bazelisk ─────────────────────────────────────────────────────────────
    if [[ -x "$BAZEL_BIN" ]]; then
        ok "Bazelisk already present"
    else
        info "Downloading Bazelisk $BAZELISK_VER ..."
        mkdir -p "$ROOT_DIR/tools"
        curl -fsSL "$BAZELISK_URL" -o "$BAZEL_BIN"
        chmod +x "$BAZEL_BIN"
        ok "Bazelisk installed"
    fi
fi

[[ -f "$CLANG_DIR/bin/clang" ]] || err "Clang not found — remove --skip-toolchain or download it manually"
[[ -x "$BAZEL_BIN" ]]           || err "tools/bazel not found — remove --skip-toolchain"
export PATH="$CLANG_DIR/bin:$PATH"
ok "Toolchain ready"

###############################################################################
# Step 4 — Pre-build environment setup
#
# Kleaf uses a "hermetic" build environment where all tools are accessed via
# stable symlinks in prebuilts/build-tools/path/linux-x86/ and
# prebuilts/build-tools/linux-x86/bin/ instead of relying on the host PATH.
# These symlinks are machine-local (absolute paths) so they are NOT stored
# in git and must be created on each fresh checkout.
###############################################################################
step "Step 4/7 — Pre-build environment"

setup_build_tools() {
    local TOOLS_DIR="$ROOT_DIR/prebuilts/build-tools"
    local HPATH="$TOOLS_DIR/path/linux-x86"      # hermetic PATH directory
    local HBIN="$TOOLS_DIR/linux-x86/bin"         # additional bin/ tools
    local HCOMMON="$TOOLS_DIR/common"

    mkdir -p "$HPATH" "$HBIN" "$HCOMMON/bison"

    # ── 1. Hermetic PATH symlinks to /usr/bin/* ───────────────────────────────
    local usr_tools=(
        awk basename bc bzcat bzip2 cat chmod cmp comm cp cpio cut date dd
        diff dirname du echo egrep env expr find flex getconf grep gzip head
        hostname id install ln ls m4 make md5sum mkdir mktemp mv nproc od
        openssl paste pgrep pkill ps pwd readlink realpath rm rmdir sed seq
        setsid sha1sum sha256sum sha512sum sleep sort stat tail tee test
        timeout touch tr true truncate uname uniq unzip wc which whoami xargs
        xxd xz xzcat zipinfo
    )
    for t in "${usr_tools[@]}"; do
        if [[ ! -e "$HPATH/$t" ]]; then
            local src
            # Use type -P to get the filesystem path only (avoids shell builtins
            # like "true" or "echo" returning just the builtin name which would
            # create a self-referential symlink loop).
            src="$(type -P "$t" 2>/dev/null || true)"
            if [[ -n "$src" ]]; then
                ln -sf "$src" "$HPATH/$t"
            else
                warn "  tool not found on host: $t (some features may be missing)"
            fi
        fi
    done

    # python — always use python3
    local py3
    py3="$(command -v python3 2>/dev/null || true)"
    if [[ -n "$py3" ]]; then
        for pname in python python2 python2.7 python3; do
            [[ -e "$HPATH/$pname" ]] || ln -sf "$py3" "$HPATH/$pname"
        done
    fi

    # ── 2. Special stub scripts ───────────────────────────────────────────────
    # cxx_extractor: Clang extraction tool stub (not needed for kernel builds)
    if [[ ! -x "$HPATH/cxx_extractor" ]]; then
        cat > "$HPATH/cxx_extractor" <<'STUB'
#!/bin/sh
echo "stub: $0" >&2
STUB
        chmod +x "$HPATH/cxx_extractor"
    fi

    # runextractor: companion stub
    if [[ ! -x "$HPATH/runextractor" ]]; then
        cat > "$HPATH/runextractor" <<'STUB'
#!/bin/sh
echo "stub: $0" >&2
STUB
        chmod +x "$HPATH/runextractor"
    fi

    # unix2dos: stub (rarely needed in kernel builds)
    if [[ ! -x "$HPATH/unix2dos" ]]; then
        cat > "$HPATH/unix2dos" <<'STUB'
#!/bin/sh
echo "stub: $0" >&2
STUB
        chmod +x "$HPATH/unix2dos"
    fi

    # toybox: thin wrapper that delegates to the real system tool.
    # IMPORTANT: Kleaf's hermetic_tools.bzl requires that the `tar` entry in
    # the hermetic PATH resolves (via symlinks) to a file named "toybox".
    # It then generates a wrapper: `exec /path/to/toybox tar "$@" <fixed-args>`.
    # The stub must therefore find the REAL system binary by absolute path to
    # avoid re-calling itself (which would loop since tar → toybox → exec tar…).
    if [[ ! -x "$HPATH/toybox" ]]; then
        cat > "$HPATH/toybox" <<'STUB'
#!/bin/sh
# toybox stub — resolves to real system binaries by absolute path.
CMD=$(basename "$0")
if [ "$CMD" = "toybox" ]; then CMD="$1"; shift; fi
# Search standard system dirs (avoid re-calling ourselves)
for d in /usr/bin /bin /usr/local/bin /usr/sbin /sbin; do
    [ -x "$d/$CMD" ] && exec "$d/$CMD" "$@"
done
echo "toybox stub: '$CMD' not found in system PATH" >&2
exit 127
STUB
        chmod +x "$HPATH/toybox"
    fi
    # tar must symlink to toybox (same directory) so that Kleaf's hermetic_tools
    # check `basename(realpath(tar)) == "toybox"` passes.
    rm -f "$HPATH/tar"
    ln -sf toybox "$HPATH/tar"

    # ── 3. Bison data directory ───────────────────────────────────────────────
    # build/kernel/build-tools/path/linux-x86/bison is a wrapper script that
    # sets BISON_PKGDATADIR=$ROOT/prebuilts/build-tools/common/bison before
    # invoking the real bison binary. Symlink that directory to the system's
    # bison data (e.g. /usr/share/bison) so the wrapper can find m4sugar etc.
    local BISON_DATA_DIR="$ROOT_DIR/prebuilts/build-tools/common/bison"
    if [[ ! -d "$BISON_DATA_DIR/m4sugar" ]]; then
        rm -rf "$BISON_DATA_DIR"
        local SYS_BISON_DATA
        for d in /usr/share/bison /usr/local/share/bison; do
            [[ -d "$d/m4sugar" ]] && SYS_BISON_DATA="$d" && break
        done
        if [[ -n "$SYS_BISON_DATA" ]]; then
            mkdir -p "$(dirname "$BISON_DATA_DIR")"
            ln -sf "$SYS_BISON_DATA" "$BISON_DATA_DIR"
            info "  Bison data: $BISON_DATA_DIR -> $SYS_BISON_DATA"
        else
            warn "  bison data dir not found — bison genrules may fail"
        fi
    fi

    # ── 4. linux-x86/bin/ tools (used by Kleaf scripts) ─────────────────────
    local bin_tools=(bison flex m4 make openssl)
    for t in "${bin_tools[@]}"; do
        if [[ ! -e "$HBIN/$t" ]]; then
            local src
            src="$(type -P "$t" 2>/dev/null || true)"
            [[ -n "$src" ]] && ln -sf "$src" "$HBIN/$t"
        fi
    done

    # cxx_extractor and runextractor in bin/ (same stubs)
    for t in cxx_extractor runextractor; do
        if [[ ! -x "$HBIN/$t" ]]; then
            cat > "$HBIN/$t" <<'STUB'
#!/bin/sh
echo "stub: $0" >&2
STUB
            chmod +x "$HBIN/$t"
        fi
    done

    # ziptool: use zip/unzip if available
    if [[ ! -e "$HBIN/ziptool" ]]; then
        local zt
        zt="$(type -P zip 2>/dev/null || true)"
        [[ -n "$zt" ]] && ln -sf "$zt" "$HBIN/ziptool" || true
    fi

    # ── 4. BUILD.bazel stub ───────────────────────────────────────────────────
    # prebuilts/build-tools/BUILD.bazel is gitignored (machine-specific paths).
    # Generate it here so Bazel can register the Python toolchain.
    # Create a symlink prebuilts/build-tools/python3 → clang's python3 binary.
    # Bazel filegroup srcs cannot use absolute paths, so we expose the binary
    # via a relative symlink within the package directory, then reference it
    # as a simple label ":python3_bin" in BUILD.bazel.
    local CLANG_PY3="$CLANG_DIR/python3/bin/python3"
    if [[ ! -f "$CLANG_PY3" ]]; then
        CLANG_PY3="$(type -P python3 2>/dev/null || echo /usr/bin/python3)"
    fi
    # NOTE: the symlink is named 'python3.exe' (not 'python3') to avoid a
    # Bazel dependency cycle: a filegroup(srcs=["python3"]) in the same
    # package would resolve to the py_runtime target named "python3".
    if [[ ! -e "$TOOLS_DIR/python3.exe" ]]; then
        ln -sf "$CLANG_PY3" "$TOOLS_DIR/python3.exe"
    fi

    if [[ ! -f "$TOOLS_DIR/BUILD.bazel" ]]; then
        cat > "$TOOLS_DIR/BUILD.bazel" <<'BUILDEOF'
# Auto-generated by build.sh — do not commit this file.
# Provides a Python toolchain using the bundled clang python3 binary.
load("@bazel_tools//tools/python:toolchain.bzl", "py_runtime_pair")

package(default_visibility = ["//visibility:public"])

filegroup(
    name = "linux-x86",
    srcs = glob(["linux-x86/**"], allow_empty = True),
)

# build.sh creates a symlink 'python3.exe' -> clang's python3 binary.
# Named .exe to avoid a Bazel dep cycle (filegroup "python3" in the same
# package would resolve to the py_runtime target also named "python3").
filegroup(
    name = "python3_bin",
    srcs = ["python3.exe"],
)

py_runtime(
    name = "python3",
    interpreter = ":python3_bin",
    python_version = "PY3",
)

py_runtime(
    name = "python2",
    interpreter = ":python3_bin",
    python_version = "PY2",
)

py_runtime_pair(
    name = "py_runtime_pair",
    py2_runtime = ":python2",
    py3_runtime = ":python3",
)

toolchain(
    name = "py_toolchain",
    toolchain = ":py_runtime_pair",
    toolchain_type = "@bazel_tools//tools/python:toolchain_type",
)
BUILDEOF
        info "  Generated prebuilts/build-tools/BUILD.bazel"
    fi

    # ── 5. JDK prebuilts — WORKSPACE references prebuilts/jdk/jdk11/linux-x86 ─
    # workspace.bzl registers @local_jdk pointing to prebuilts/jdk/jdk11/linux-x86.
    # This path is gitignored; create symlinks to the system JDK here.
    local JDK_DIR="$ROOT_DIR/prebuilts/jdk/jdk11/linux-x86"
    if [[ ! -x "$JDK_DIR/bin/java" ]]; then
        info "  Setting up JDK prebuilts ..."
        mkdir -p "$JDK_DIR/bin"
        # Prefer a real JDK install so javac is available
        local JAVA_HOME_FOUND=""
        for candidate in \
            /usr/lib/jvm/java-11-openjdk-amd64 \
            /usr/lib/jvm/java-17-openjdk-amd64 \
            /usr/lib/jvm/java-21-openjdk-amd64 \
            /usr/lib/jvm/default-java
        do
            if [[ -x "$candidate/bin/java" ]]; then
                JAVA_HOME_FOUND="$candidate"
                break
            fi
        done

        if [[ -n "$JAVA_HOME_FOUND" ]]; then
            # Symlink the whole JDK home so glob(["**"]) in jdk11.BUILD works
            rm -rf "$JDK_DIR"
            ln -sf "$JAVA_HOME_FOUND" "$JDK_DIR"
        elif command -v java &>/dev/null; then
            # Fall back: just symlink the binaries
            ln -sf "$(command -v java)"  "$JDK_DIR/bin/java"
            ln -sf "$(command -v javac 2>/dev/null || command -v java)" "$JDK_DIR/bin/javac"
        else
            warn "  Java not found — Bazel may fail. Install: sudo apt-get install -y openjdk-21-jdk"
        fi
    fi

    # ── 7. NDK prebuilt stub — workspace.bzl registers @prebuilt_ndk ─────────
    # ndk.BUILD globs toolchains/llvm/prebuilt/linux-x86_64/sysroot/**
    # (allow_empty=False). We don't need the full NDK — just a .keep file
    # to satisfy the glob.  prebuilts/ndk-r23/ is gitignored (machine-local).
    local NDK_SYSROOT="$ROOT_DIR/prebuilts/ndk-r23/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include"
    if [[ ! -f "$NDK_SYSROOT/.keep" ]]; then
        info "  Setting up NDK stub ..."
        mkdir -p "$NDK_SYSROOT"
        touch "$NDK_SYSROOT/.keep"
    fi

    # ── 9. rules_pkg stub — WORKSPACE references build/bazel_common_rules/rules/pkg_stub ─
    # Kleaf normally generates this during a build. On a fresh checkout it
    # doesn't exist yet, causing @rules_pkg fetch to fail before anything builds.
    # Bootstrap it here with the same content Kleaf would generate.
    local PKG_STUB="$ROOT_DIR/build/bazel_common_rules/rules/pkg_stub"
    if [[ ! -f "$PKG_STUB/WORKSPACE" ]]; then
        info "  Bootstrapping rules_pkg stub ..."
        mkdir -p "$PKG_STUB/pkg"
        echo 'workspace(name = "rules_pkg")' > "$PKG_STUB/WORKSPACE"
        echo '# Stub pkg/ package for @rules_pkg' > "$PKG_STUB/pkg/BUILD.bazel"
        cat > "$PKG_STUB/pkg/mappings.bzl" <<'STUBEOF'
"""Stub rules_pkg mappings – no-op implementations for kernel-only builds."""

def pkg_files(**kwargs):
    """No-op stub for pkg_files."""
    pass

_strip_prefix = struct(
    from_pkg = lambda path = "": path,
    from_root = lambda path = "": path,
)

strip_prefix = _strip_prefix
STUBEOF
    fi

    # ── 11. build/BUILD.bazel — makes //build a Bazel package ────────────────
    # msm_platforms.bzl loads "//build:msm_kernel_extensions.bzl" so build/
    # must be a Bazel package. The file is tracked in git but gitignore
    # exceptions can sometimes be tricky — generate it here as a safety net.
    local BUILD_PKG="$ROOT_DIR/build/BUILD.bazel"
    if [[ ! -f "$BUILD_PKG" ]]; then
        mkdir -p "$ROOT_DIR/build"
        echo "# Auto-generated by build.sh — package root for //build:msm_kernel_extensions.bzl" \
            > "$BUILD_PKG"
        info "  Generated build/BUILD.bazel"
    fi

    # ── 6. Host sysroot for Kleaf hermetic toolchain ─────────────────────────
    # build/kernel/BUILD.bazel defines a :sysroot filegroup that globs
    # build-tools/sysroot/** (allow_empty=False). The sysroot symlink in
    # build/kernel/build-tools/sysroot points to:
    #   prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8/sysroot
    # That directory must contain real files — it is machine-local (symlinks to
    # the host's system libs and headers) and is never committed to git.
    local SYSROOT="$ROOT_DIR/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8/sysroot"
    if [[ ! -f "$SYSROOT/lib/.keep" ]]; then
        info "  Setting up host sysroot ..."
        local ARCH="x86_64-linux-gnu"
        # Prefer /usr/lib/<arch> (Ubuntu 22.04+); fall back to /lib/<arch>
        local SYSLIB="/usr/lib/$ARCH"
        [[ -d "$SYSLIB" ]] || SYSLIB="/lib/$ARCH"
        local SYSLIB_LIB="/lib/$ARCH"
        [[ -d "$SYSLIB_LIB" ]] || SYSLIB_LIB="$SYSLIB"

        mkdir -p "$SYSROOT/lib/$ARCH" "$SYSROOT/lib64" \
                 "$SYSROOT/usr/include" "$SYSROOT/usr/lib" "$SYSROOT/usr/lib64"

        # .keep markers ensure glob(allow_empty=False) succeeds
        touch "$SYSROOT/lib/.keep" "$SYSROOT/usr/include/.keep" "$SYSROOT/usr/lib/.keep"

        # lib/  — shared libs used at build time
        for f in libc.so libc.so.6 libm.so libm.so.6; do
            [[ -e "$SYSLIB/$f" ]]     && ln -sf "$SYSLIB/$f"     "$SYSROOT/lib/$f"           2>/dev/null || true
            [[ -e "$SYSLIB_LIB/$f" ]] && ln -sf "$SYSLIB_LIB/$f" "$SYSROOT/lib/$f"           2>/dev/null || true
        done

        # lib/<arch>/ — glibc versioned libs
        for f in libc.so.6 libdl.so.2 libm.so.6 libpthread.so.0; do
            local src="$SYSLIB_LIB/$f"
            [[ -e "$SYSLIB/$f" ]] && src="$SYSLIB/$f"
            [[ -e "$src" ]] && ln -sf "$src" "$SYSROOT/lib/$ARCH/$f" 2>/dev/null || true
        done

        # lib64/ — dynamic linker
        for f in ld-linux-x86-64.so.2; do
            local src="$SYSLIB_LIB/$f"
            [[ -e "$SYSLIB/$f" ]] && src="$SYSLIB/$f"
            [[ -e "$src" ]] && ln -sf "$src" "$SYSROOT/lib64/$f" 2>/dev/null || true
        done

        # usr/lib/ — CRT objects and shared libs needed for linking
        for f in Scrt1.o crt1.o crti.o crtn.o libc.so libc.so.6 libm.so libm.so.6 libpthread.so.0; do
            [[ -e "$SYSLIB/$f" ]] && ln -sf "$SYSLIB/$f" "$SYSROOT/usr/lib/$f" 2>/dev/null || true
        done

        # usr/lib/<arch>/ — selectively symlink files (NO directory symlinks — Bazel
        # globs recursively through symlinked dirs and chokes on filenames with spaces
        # e.g. espeak-ng-data/voices/!v/Mr serious inside /usr/lib/x86_64-linux-gnu).
        mkdir -p "$SYSROOT/usr/lib/$ARCH"
        if [[ -d "$SYSLIB" ]]; then
            # Only symlink regular files/symlinks whose names contain no spaces
            while IFS= read -r -d '' f; do
                local fname
                fname=$(basename "$f")
                # Skip anything with a space in the name (Bazel runfiles can't handle it)
                [[ "$fname" == *" "* ]] && continue
                [[ -e "$SYSROOT/usr/lib/$ARCH/$fname" ]] || \
                    ln -sf "$f" "$SYSROOT/usr/lib/$ARCH/$fname" 2>/dev/null || true
            done < <(find "$SYSLIB" -maxdepth 1 \( -type f -o -type l \) -print0 2>/dev/null)
        fi

        # usr/include/ — selectively symlink top-level headers only (no deep traversal)
        mkdir -p "$SYSROOT/usr/include"
        if [[ -d /usr/include ]]; then
            while IFS= read -r -d '' f; do
                local fname
                fname=$(basename "$f")
                [[ "$fname" == *" "* ]] && continue
                [[ -e "$SYSROOT/usr/include/$fname" ]] || \
                    ln -sf "$f" "$SYSROOT/usr/include/$fname" 2>/dev/null || true
            done < <(find /usr/include -maxdepth 1 \( -type f -o -type l -o -type d \) ! -name 'include' -print0 2>/dev/null)
        fi
        touch "$SYSROOT/usr/include/.keep" 2>/dev/null || true
    fi

    # ── 10. Clang symlinks into Kleaf hermetic PATH ───────────────────────────
    # build/kernel/build-tools/path/linux-x86/ hosts clang/llvm for cc-can-link.sh
    local KLEAF_HPATH="$ROOT_DIR/build/kernel/build-tools/path/linux-x86"
    if [[ -d "$KLEAF_HPATH" ]]; then
        for bin in clang clang++ ld.lld llvm-ar llvm-nm llvm-objcopy llvm-strip; do
            local src="$CLANG_DIR/bin/$bin"
            local dst="$KLEAF_HPATH/$bin"
            [[ -f "$src" ]] && [[ ! -e "$dst" ]] && ln -sf "$src" "$dst"
        done
    fi

    ok "Hermetic build environment ready"
}

setup_build_tools

###############################################################################
# Step 5 — Workspace configuration
###############################################################################
step "Step 5/7 — Workspace"

cat > "$ROOT_DIR/.bazelrc.user" <<EOF
# Auto-generated by build.sh — do not commit this file.
# Absolute path to the Kleaf kernel config cache directory.
build --//build/kernel/kleaf:cache_dir=$ROOT_DIR/out/cache
EOF
ok ".bazelrc.user written"

###############################################################################
# Step 6 — Clean (optional)
###############################################################################
if [[ "$DO_CLEAN" == true ]]; then
    step "Step 6/7 — Clean"
    info "Wiping out/ ..."
    rm -rf "$ROOT_DIR/out"
    info "Expunging Bazel cache ..."
    "$BAZEL_BIN" clean --expunge 2>/dev/null || true
    ok "Clean complete"
else
    step "Step 6/7 — Clean  ${DIM}(skipped — use --clean to wipe)${NC}"
fi

###############################################################################
# Step 7 — Build
###############################################################################
if [[ "$SKIP_BUILD" == true ]]; then
    step "Step 7/7 — Build  ${DIM}(skipped)${NC}"
    ok "Done."
    exit 0
fi

step "Step 7/7 — Build  [variant=${BOLD}$VARIANT${NC}]"

DIST_DIR="$ROOT_DIR/out/msm-kernel-peridot-$VARIANT/dist"
LOG_DIR="$ROOT_DIR/out/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/build_$(date +%Y%m%d_%H%M%S).log"

echo ""
echo -e "  ${BOLD}Device  :${NC} Xiaomi peridot (SM8650 / Snapdragon 8 Gen 3)"
echo -e "  ${BOLD}Kernel  :${NC} Android 14 GKI 2.0, kernel 6.1"
echo -e "  ${BOLD}Variant :${NC} $VARIANT"
echo -e "  ${BOLD}Compiler:${NC} clang-$CLANG_VERSION (LLVM 17)"
echo -e "  ${BOLD}Output  :${NC} $DIST_DIR"
echo -e "  ${BOLD}Log     :${NC} $LOG"
echo ""

BUILD_ARGS=("-t" "peridot" "$VARIANT" "--skip" "abl")
[[ "$DO_MENUCONFIG" == true ]] && BUILD_ARGS+=("--menuconfig")

BUILD_START=$(date +%s)

# Stream output to console AND save to log file
set +e
python3 "$KERNEL_DIR/build_with_bazel.py" "${BUILD_ARGS[@]}" 2>&1 | tee "$LOG"
BUILD_EXIT="${PIPESTATUS[0]}"
set -e

BUILD_END=$(date +%s)
BUILD_TIME=$(( BUILD_END - BUILD_START ))
BUILD_MIN=$(( BUILD_TIME / 60 ))
BUILD_SEC=$(( BUILD_TIME % 60 ))

echo ""
if [[ $BUILD_EXIT -ne 0 ]]; then
    echo -e "${RED}╔══════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  BUILD FAILED  (exit $BUILD_EXIT)                   ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Log: $LOG"
    echo ""
    echo -e "${BOLD}  Last 40 lines of log:${NC}"
    tail -40 "$LOG"
    echo ""
    echo -e "${BOLD}  Troubleshooting tips:${NC}"
    echo -e "   • Re-run with ${BOLD}--clean${NC} to rule out stale cache"
    echo -e "   • Check the full log: ${BOLD}cat $LOG${NC}"
    echo -e "   • Ensure all system packages are installed: ${BOLD}./build.sh --setup${NC}"
    exit 1
fi

###############################################################################
# Build summary + post-build artifact check
###############################################################################
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  BUILD SUCCESSFUL  ✓                     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Time   :${NC} ${BUILD_MIN}m ${BUILD_SEC}s"
echo -e "  ${BOLD}Log    :${NC} $LOG"
echo ""

if [[ -d "$DIST_DIR" ]]; then
    echo -e "  ${BOLD}Artifacts: $DIST_DIR${NC}"
    echo ""

    MISSING_IMGS=()
    for f in boot.img vendor_boot.img dtbo.img vendor_dlkm.img system_dlkm.img; do
        if [[ -f "$DIST_DIR/$f" ]]; then
            printf "   ${GREEN}✓${NC}  %-30s  %s\n" "$f" "$(du -sh "$DIST_DIR/$f" | cut -f1)"
        else
            printf "   ${YELLOW}–${NC}  %-30s  not produced\n" "$f"
            MISSING_IMGS+=("$f")
        fi
    done

    for f in Image Image.lz4 init_boot.img super.img; do
        [[ -f "$DIST_DIR/$f" ]] && \
            printf "   ${GREEN}✓${NC}  %-30s  %s\n" "$f" "$(du -sh "$DIST_DIR/$f" | cut -f1)"
    done

    DTB_N=$(find "$DIST_DIR" -maxdepth 1 -name "*.dtb"  2>/dev/null | wc -l)
    KO_N=$( find "$DIST_DIR" -name "*.ko"               2>/dev/null | wc -l)
    [[ $DTB_N -gt 0 ]] && printf "   ${GREEN}✓${NC}  %-30s  %d files\n"   "*.dtb" "$DTB_N"
    [[ $KO_N  -gt 0 ]] && printf "   ${GREEN}✓${NC}  %-30s  %d modules\n" "*.ko"  "$KO_N"

    if [[ ${#MISSING_IMGS[@]} -gt 0 ]]; then
        echo ""
        warn "The following images were not produced: ${MISSING_IMGS[*]}"
        warn "This may be expected for some build variants."
    fi

    echo ""
    echo -e "  ${BOLD}Flash commands:${NC}"
    echo -e "   ${DIM}fastboot flash boot         $DIST_DIR/boot.img${NC}"
    echo -e "   ${DIM}fastboot flash vendor_boot  $DIST_DIR/vendor_boot.img${NC}"
    echo -e "   ${DIM}fastboot flash vendor_dlkm  $DIST_DIR/vendor_dlkm.img${NC}"
    echo -e "   ${DIM}fastboot flash system_dlkm  $DIST_DIR/system_dlkm.img${NC}"
    echo -e "   ${DIM}fastboot reboot${NC}"
    echo ""
    echo -e "   Or run: ${BOLD}./build.sh --flash${NC}"
else
    warn "No dist/ directory found at $DIST_DIR — build may have produced output elsewhere"
fi

echo ""
ok "Done."
