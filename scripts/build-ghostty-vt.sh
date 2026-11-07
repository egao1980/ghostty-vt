#!/usr/bin/env bash
# Build libghostty-vt + the ghostty-vt-cl shim into lib/<os>-<arch>/.
#
#   scripts/build-ghostty-vt.sh [os-arch ...]     default: the host
#   os-arch ∈ linux-amd64 linux-arm64 darwin-arm64 windows-amd64
#
# Sources are the signed release tarballs, never a git checkout (a checkout
# builds the Ghostty app). Signatures and SHA256SUMS are verified first.
# Zig cross-compiles: every Linux/Windows target builds from any host.
#
# Env: GHOSTTY_VT_VERSION (default 1.0.0), GHOSTTY_VT_WORK (default build/)
set -euo pipefail

VERSION="${GHOSTTY_VT_VERSION:-1.0.0}"
PUBKEY="RWQlAjJC23149WL2sEpT/l0QKy7hMIFhYdQOFy0Z7z7PbneUgvlsnYcV"
BASE_URL="https://release.files.ghostty.org/libghostty-vt/${VERSION}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${GHOSTTY_VT_WORK:-${ROOT}/build}"
GLIBC="2.31"   # oldest glibc the Linux overlays accept

die() { echo "build-ghostty-vt.sh: $*" >&2; exit 1; }
for cmd in curl tar zig minisign; do
  command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
done

sha256_check() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c --ignore-missing SHA256SUMS
  else
    shasum -a 256 -c --ignore-missing SHA256SUMS
  fi
}

host_os_arch() {
  local os arch
  case "$(uname -s)" in
    Linux) os=linux ;; Darwin) os=darwin ;;
    MINGW*|MSYS*|CYGWIN*) os=windows ;; *) die "unknown host OS" ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) arch=amd64 ;; arm64|aarch64) arch=arm64 ;;
    *) die "unknown host arch" ;;
  esac
  echo "${os}-${arch}"
}

zig_target() {
  case "$1" in
    linux-amd64) echo "x86_64-linux-gnu.${GLIBC}" ;;
    linux-arm64) echo "aarch64-linux-gnu.${GLIBC}" ;;
    darwin-arm64) echo "aarch64-macos" ;;
    windows-amd64) echo "x86_64-windows-gnu" ;;
    *) die "unsupported os-arch: $1" ;;
  esac
}

fetch_sources() {
  local dl="${WORK}/download"
  mkdir -p "$dl"
  (
    cd "$dl"
    for f in "libghostty-vt-${VERSION}.tar.gz" "libghostty-vt-${VERSION}-deps.tar.gz" SHA256SUMS; do
      [[ -f "$f" ]] || curl -fsSL -o "$f" "${BASE_URL}/${f}"
      [[ -f "$f.minisig" ]] || curl -fsSL -o "$f.minisig" "${BASE_URL}/${f}.minisig"
      minisign -V -q -P "$PUBKEY" -m "$f" || die "bad signature: $f"
    done
    sha256_check || die "checksum mismatch"
  )
  local src="${WORK}/src"
  if [[ ! -d "${src}/libghostty-vt-${VERSION}" ]]; then
    rm -rf "$src"; mkdir -p "$src"
    tar -xzf "${dl}/libghostty-vt-${VERSION}.tar.gz" -C "$src"
    tar -xzf "${dl}/libghostty-vt-${VERSION}-deps.tar.gz" -C "$src"
  fi
}

build_one() {
  local pair="$1" target prefix out
  target="$(zig_target "$pair")"
  prefix="${WORK}/prefix-${pair}"
  out="${ROOT}/lib/${pair}"
  echo "==> ${pair} (${target})"
  rm -rf "$prefix" "${WORK}/zig-cache-${pair}" "$out"
  (
    cd "${WORK}/src/libghostty-vt-${VERSION}"
    # A fresh, empty cache per build (Zig 0.17 can crash on a reused one).
    ZIG_GLOBAL_CACHE_DIR="${WORK}/zig-cache-${pair}" zig build \
      --prefix "$prefix" \
      --system "../libghostty-vt-${VERSION}-deps" \
      -Doptimize=ReleaseFast -Dstrip=true -Dcpu=baseline -Dtarget="$target"
  )
  mkdir -p "$out"
  local shim=(zig cc -target "$target" -O2 -shared -fvisibility=hidden
              -I "${prefix}/include" "${ROOT}/native/ghostty-vt-cl.c")
  case "$pair" in
    linux-*)
      # One real file under the SONAME; overlays carry no symlinks.
      cp -L "${prefix}/lib/libghostty-vt.so.1" "$out/libghostty-vt.so.1"
      "${shim[@]}" -L "${prefix}/lib" -lghostty-vt -Wl,-rpath,'$ORIGIN' \
        -Wl,-soname,libghostty-vt-cl.so -o "$out/libghostty-vt-cl.so"
      ;;
    darwin-*)
      cp "${prefix}/lib/libghostty-vt.1.dylib" "$out/"
      "${shim[@]}" -L "${prefix}/lib" -lghostty-vt -Wl,-rpath,@loader_path \
        -Wl,-install_name,@rpath/libghostty-vt-cl.dylib -o "$out/libghostty-vt-cl.dylib"
      ;;
    windows-*)
      cp "${prefix}/bin/ghostty-vt.dll" "$out/"
      "${shim[@]}" -L "${prefix}/lib" -lghostty-vt -o "$out/ghostty-vt-cl.dll"
      rm -f "$out"/*.lib "$out"/*.pdb
      ;;
  esac
  ls -la "$out"
}

pairs=("$@")
[[ ${#pairs[@]} -gt 0 ]] || pairs=("$(host_os_arch)")
fetch_sources
for pair in "${pairs[@]}"; do
  build_one "$pair"
done
