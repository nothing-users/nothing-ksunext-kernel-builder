#!/usr/bin/env bash
set -Eeuo pipefail

if (( $# != 4 )); then
  printf 'Usage: %s KERNEL_SOURCE ANDROID_CLANG_BIN ANDROID_BUILD_TOOLS_BIN CONFIG_FRAGMENT\n' "$0" >&2
  exit 2
fi

kernel_source="$1"
clang_bin="$2"
build_tools_bin="$3"
config_fragment="$4"
defconfig="$kernel_source/arch/arm64/configs/gki_defconfig"
config_out="$(mktemp -d)"
trap 'rm -rf "$config_out"' EXIT

for required in \
  "$defconfig" \
  "$config_fragment" \
  "$clang_bin/clang" \
  "$clang_bin/ld.lld" \
  "$build_tools_bin/pahole"; do
  [[ -e "$required" ]] || {
    printf 'Missing defconfig canonicalization input: %s\n' "$required" >&2
    exit 2
  }
done

export PATH="$clang_bin:$build_tools_bin:$PATH"

# Kconfig compiler probes are target-dependent. In particular,
# CONFIG_KASAN_HW_TAGS disappears when gki_defconfig is evaluated with the
# runner's native x86 compiler, which later removes kasan_flag_enabled from the
# QCOM KMI. Use the exact Android Clang toolchain selected by the kernel tree.
make \
  -C "$kernel_source" \
  O="$config_out" \
  ARCH=arm64 \
  LLVM=1 \
  LLVM_IAS=1 \
  CROSS_COMPILE=aarch64-linux-gnu- \
  gki_defconfig
make \
  -C "$kernel_source" \
  O="$config_out" \
  ARCH=arm64 \
  LLVM=1 \
  LLVM_IAS=1 \
  CROSS_COMPILE=aarch64-linux-gnu- \
  savedefconfig

[[ -s "$config_out/defconfig" ]] || {
  printf 'Canonical defconfig was not generated\n' >&2
  exit 1
}

grep -qx 'CONFIG_KASAN_HW_TAGS=y' "$config_out/.config" || {
  printf 'Android Clang config lost CONFIG_KASAN_HW_TAGS; QCOM KMI would lose kasan_flag_enabled\n' >&2
  exit 1
}

while IFS='=' read -r option value; do
  [[ -z "$option" || "$option" == \#* ]] && continue
  if [[ "$value" == n ]]; then
    expected="# $option is not set"
  else
    expected="$option=$value"
  fi
  grep -qxF "$expected" "$config_out/.config" || {
    printf 'Required config was not enabled before canonicalization: %s\n' "$expected" >&2
    exit 1
  }
done < "$config_fragment"

install -m 0644 "$config_out/defconfig" "$defconfig"
printf 'Canonicalized %s with %s and %s\n' \
  "$defconfig" \
  "$(clang --version | sed -n '1p')" \
  "$(pahole --version | sed -n '1p')"
