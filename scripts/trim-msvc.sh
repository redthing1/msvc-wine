#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: trim-msvc.sh [options]

Options:
  --root <path>            MSVC install root (default: /opt/msvc)
  --keep-archs "<list>"    Target archs to keep (default: $MSVC_ARCHS or "x64")
  --host-arch <arch>       Host arch for tools (default: $HOST_ARCH or "x64")
  --sdk-version <ver>      Windows SDK version to keep (default: from msvcenv.sh)
  --only-sdk-version       Remove other SDK versions
  --trim-optional          Remove optional bundles (redist, testing, refs, etc.)
  --dry-run                Print what would be removed
  -h, --help               Show this help
EOF
}

ROOT=${MSVC_ROOT:-/opt/msvc}
KEEP_ARCHS="${MSVC_ARCHS:-}"
HOST_ARCH="${HOST_ARCH:-}"
SDKVER=""
ONLY_SDKVER="no"
TRIM_OPTIONAL="no"
DRY_RUN="no"

while [ $# -gt 0 ]; do
    case "$1" in
        --root)
            ROOT=$2
            shift 2
            ;;
        --keep-archs)
            KEEP_ARCHS=$2
            shift 2
            ;;
        --host-arch)
            HOST_ARCH=$2
            shift 2
            ;;
        --sdk-version)
            SDKVER=$2
            shift 2
            ;;
        --only-sdk-version)
            ONLY_SDKVER="yes"
            shift
            ;;
        --trim-optional)
            TRIM_OPTIONAL="yes"
            shift
            ;;
        --dry-run)
            DRY_RUN="yes"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ -z "$KEEP_ARCHS" ]; then
    KEEP_ARCHS="x64"
fi
if [ -z "$HOST_ARCH" ]; then
    HOST_ARCH="x64"
fi

maybe_rm() {
    local path=$1
    if [ -e "$path" ]; then
        if [ "$DRY_RUN" = "yes" ]; then
            echo "DRY-RUN: rm -rf \"$path\""
        else
            rm -rf "$path"
        fi
    fi
}

host_dir_for() {
    case "$1" in
        x64) echo "Hostx64" ;;
        x86) echo "Hostx86" ;;
        arm) echo "Hostarm" ;;
        arm64) echo "Hostarm64" ;;
        *) echo "Host$1" ;;
    esac
}

find_sdkver() {
    local arch
    for arch in $KEEP_ARCHS; do
        if [ -f "$ROOT/bin/$arch/msvcenv.sh" ]; then
            SDKVER=$(grep -E '^SDKVER=' "$ROOT/bin/$arch/msvcenv.sh" | head -n1 | cut -d= -f2)
            [ -n "$SDKVER" ] && return 0
        fi
    done
    return 1
}

find_msvcver() {
    local arch
    for arch in $KEEP_ARCHS; do
        if [ -f "$ROOT/bin/$arch/msvcenv.sh" ]; then
            MSVCVER=$(grep -E '^MSVCVER=' "$ROOT/bin/$arch/msvcenv.sh" | head -n1 | cut -d= -f2)
            [ -n "$MSVCVER" ] && return 0
        fi
    done
    return 1
}

if [ -z "$SDKVER" ]; then
    if ! find_sdkver; then
        echo "Unable to determine SDK version from $ROOT/bin/*/msvcenv.sh" >&2
        exit 1
    fi
fi
if ! find_msvcver; then
    echo "Unable to determine MSVC version from $ROOT/bin/*/msvcenv.sh" >&2
    exit 1
fi

MSVC_TOOLS="$ROOT/VC/Tools/MSVC/$MSVCVER"
SDK_ROOT="$ROOT/Windows Kits/10"

keep_arch() {
    local a=$1
    local k
    for k in $KEEP_ARCHS; do
        if [ "$a" = "$k" ]; then
            return 0
        fi
    done
    return 1
}

prune_arch_dirs() {
    local base=$1
    local sub
    [ -d "$base" ] || return 0
    for sub in "$base"/*; do
        [ -d "$sub" ] || continue
        local name
        name=$(basename "$sub")
        if ! keep_arch "$name"; then
            maybe_rm "$sub"
        fi
    done
}

# Prune MSVC libs per-arch.
if [ -d "$MSVC_TOOLS/lib" ]; then
    prune_arch_dirs "$MSVC_TOOLS/lib"
    if [ -d "$MSVC_TOOLS/lib/onecore" ]; then
        prune_arch_dirs "$MSVC_TOOLS/lib/onecore"
    fi
fi

# Prune MSVC bins by host + target archs.
if [ -d "$MSVC_TOOLS/bin" ]; then
    keep_host_dir=$(host_dir_for "$HOST_ARCH")
    for hostdir in "$MSVC_TOOLS/bin"/Host*; do
        [ -d "$hostdir" ] || continue
        if [ "$(basename "$hostdir")" != "$keep_host_dir" ]; then
            maybe_rm "$hostdir"
            continue
        fi
        prune_arch_dirs "$hostdir"
    done
fi

# Prune Windows SDK libs per-arch.
if [ -d "$SDK_ROOT/Lib/$SDKVER" ]; then
    for section in um ucrt km ucrt_enclave; do
        if [ -d "$SDK_ROOT/Lib/$SDKVER/$section" ]; then
            prune_arch_dirs "$SDK_ROOT/Lib/$SDKVER/$section"
        fi
    done
fi

# Prune Windows SDK bins per-arch (versioned and non-versioned).
if [ -d "$SDK_ROOT/bin/$SDKVER" ]; then
    prune_arch_dirs "$SDK_ROOT/bin/$SDKVER"
fi
if [ -d "$SDK_ROOT/bin" ]; then
    for dir in "$SDK_ROOT/bin"/x86 "$SDK_ROOT/bin"/x64 "$SDK_ROOT/bin"/arm "$SDK_ROOT/bin"/arm64; do
        [ -d "$dir" ] || continue
        if ! keep_arch "$(basename "$dir")"; then
            maybe_rm "$dir"
        fi
    done
fi

# Remove other SDK versions if requested.
if [ "$ONLY_SDKVER" = "yes" ]; then
    for base in "$SDK_ROOT/Include" "$SDK_ROOT/Lib" "$SDK_ROOT/bin"; do
        [ -d "$base" ] || continue
        for dir in "$base"/*; do
            [ -d "$dir" ] || continue
            if [ "$(basename "$dir")" = "$SDKVER" ]; then
                continue
            fi
            case "$(basename "$dir")" in
                x86|x64|arm|arm64) continue ;;
            esac
            maybe_rm "$dir"
        done
    done
fi

# Remove optional bundles if requested.
if [ "$TRIM_OPTIONAL" = "yes" ]; then
    maybe_rm "$ROOT/VC/Tools/Llvm"
    maybe_rm "$ROOT/VC/Redist"
    maybe_rm "$ROOT/VC/vcpkg"
    maybe_rm "$ROOT/DIA SDK"

    maybe_rm "$SDK_ROOT/App Certification Kit"
    maybe_rm "$SDK_ROOT/Testing"
    maybe_rm "$SDK_ROOT/References"
    maybe_rm "$SDK_ROOT/Redist"
    maybe_rm "$SDK_ROOT/Source"
    maybe_rm "$SDK_ROOT/DesignTime"
    maybe_rm "$SDK_ROOT/UnionMetadata"
    maybe_rm "$SDK_ROOT/Catalogs"
fi
