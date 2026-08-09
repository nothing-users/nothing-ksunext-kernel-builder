#!/usr/bin/env bash
set -Eeuo pipefail

if (( $# != 11 )); then
  printf 'Usage: %s KERNEL_SOURCE KSU_SOURCE SUSFS_SOURCE SUSFS_REPOSITORY SUSFS_REF SUSFS_PATCH PATCHES_SOURCE PATCHES_REPOSITORY PATCHES_COMMIT KSU_PATCHSET CONFIG_FRAGMENT\n' "$0" >&2
  exit 2
fi

kernel_source="$1"
ksu_source="$2"
susfs_source="$3"
susfs_repository="$4"
susfs_ref="$5"
susfs_patch="$6"
patches_source="$7"
patches_repository="$8"
patches_commit="$9"
ksu_patchset="${10}"
config_fragment="${11}"
ksu_driver="$kernel_source/drivers/kernelsu"
defconfig="$kernel_source/arch/arm64/configs/gki_defconfig"
patch_logs="$(mktemp -d)"
trap 'rm -rf "$patch_logs"' EXIT

case "$ksu_patchset" in
  dev|stable) ;;
  *)
    printf 'Unsupported KernelSU Next compatibility patchset: %s\n' "$ksu_patchset" >&2
    exit 2
    ;;
esac

for required in \
  "$kernel_source/Makefile" \
  "$kernel_source/fs/proc/base.c" \
  "$ksu_source/kernel/Kconfig" \
  "$ksu_driver/Kbuild" \
  "$defconfig" \
  "$kernel_source/scripts/config" \
  "$config_fragment"; do
  [[ -f "$required" ]] || {
    printf 'Missing SUSFS integration input: %s\n' "$required" >&2
    exit 2
  }
done

for checkout in "$susfs_source" "$patches_source"; do
  [[ ! -e "$checkout" && ! -L "$checkout" ]] || {
    printf 'SUSFS integration checkout already exists: %s\n' "$checkout" >&2
    exit 2
  }
done

git init "$susfs_source" >/dev/null
git -C "$susfs_source" remote add origin "$susfs_repository"
git -C "$susfs_source" -c protocol.version=2 fetch \
  --depth=1 \
  --filter=blob:none \
  origin \
  "$susfs_ref"
git -C "$susfs_source" checkout --detach FETCH_HEAD

git init "$patches_source" >/dev/null
git -C "$patches_source" remote add origin "$patches_repository"
git -C "$patches_source" -c protocol.version=2 fetch \
  --depth=1 \
  --filter=blob:none \
  origin \
  "$patches_commit"
git -C "$patches_source" checkout --detach FETCH_HEAD

resolved_patches_commit="$(git -C "$patches_source" rev-parse HEAD)"
if [[ "$resolved_patches_commit" != "$patches_commit" ]]; then
  printf 'Unexpected compatibility patches commit: %s\n' "$resolved_patches_commit" >&2
  exit 1
fi

susfs_version="$(awk -F'"' '/^#define SUSFS_VERSION/{print $2; exit}' \
  "$susfs_source/kernel_patches/include/linux/susfs.h")"
if [[ "$susfs_version" != v2.2.0 ]]; then
  printf 'Unsupported SUSFS compatibility patch version: %s\n' "$susfs_version" >&2
  exit 1
fi

ksu_patch="$susfs_source/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
if [[ "$ksu_patchset" == stable ]]; then
  fix_dir="$patches_source/next/susfs_fix_patches/stable/$susfs_version"
else
  fix_dir="$patches_source/next/susfs_fix_patches/$susfs_version"
fi

ksu_patch_status=0
patch \
  --directory="$ksu_source" \
  --batch \
  --forward \
  -p1 \
  < "$ksu_patch" \
  > "$patch_logs/10_enable_susfs_for_ksu.log" 2>&1 || ksu_patch_status=$?
cat "$patch_logs/10_enable_susfs_for_ksu.log"

mapfile -d '' ksu_rejects < <(find "$ksu_source/kernel" -type f -name '*.rej' -print0)
if (( ksu_patch_status != 0 )) && (( ${#ksu_rejects[@]} == 0 )); then
  printf 'KernelSU Next SUSFS patch failed without reject files\n' >&2
  exit "$ksu_patch_status"
fi

for reject_file in "${ksu_rejects[@]}"; do
  reject_relative="${reject_file#"$ksu_source"/}"
  fix_patch="$fix_dir/fix_$(basename "$reject_file" .rej).patch"

  if [[ "$ksu_patchset" == stable && "$reject_relative" == kernel/Kconfig.rej ]]; then
    kconfig_block="$patch_logs/ksun-susfs-kconfig"
    sed -n '/^+menu "KernelSU - SUSFS"$/,/^+endmenu$/p' "$ksu_patch" |
      sed -n -e 's/^+//p' -e 's/^ //p' > "$kconfig_block"
    grep -q '^config KSU_SUSFS$' "$kconfig_block" || {
      printf 'Could not extract SUSFS Kconfig block\n' >&2
      exit 1
    }
    awk -v block="$kconfig_block" '
      { lines[NR] = $0 }
      END {
        last = 0
        for (i = 1; i <= NR; i++)
          if (lines[i] == "endmenu") last = i
        if (!last) exit 1
        for (i = 1; i <= NR; i++) {
          if (i == last) {
            while ((getline line < block) > 0) print line
            close(block)
          }
          print lines[i]
        }
      }
    ' "$ksu_source/kernel/Kconfig" > "$ksu_source/kernel/Kconfig.susfs.tmp"
    mv "$ksu_source/kernel/Kconfig.susfs.tmp" "$ksu_source/kernel/Kconfig"
    continue
  fi

  [[ -f "$fix_patch" ]] || {
    printf 'Missing KernelSU Next compatibility patch: %s\n' "$fix_patch" >&2
    exit 1
  }
  patch --directory="$ksu_source" --batch --forward -p1 < "$fix_patch"
done

patch --directory="$ksu_source" --batch --forward -p1 \
  < "$fix_dir/overwrite_hook_mode.patch"
patch --directory="$ksu_source" --batch --forward -p1 \
  < "$fix_dir/ksu_toolkit.patch"

if [[ "$ksu_patchset" == stable ]]; then
  sed -i '/^-[[:space:]]/d' "$ksu_source/kernel/Kconfig"
fi
if grep -nE '^[+-][[:space:]]' "$ksu_source/kernel/Kconfig"; then
  printf 'KernelSU Next Kconfig contains unresolved diff markers\n' >&2
  exit 1
fi
find "$ksu_source" -type f -name '*.rej' -delete
grep -q '^config KSU_SUSFS$' "$ksu_source/kernel/Kconfig" || {
  printf 'KernelSU Next SUSFS integration was not applied\n' >&2
  exit 1
}

# Refresh the copy embedded in the kernel tree after patching the standalone
# KernelSU checkout. Keep the materialized UAPI tree required by Kleaf.
rm -rf "$ksu_driver"
mkdir -p "$ksu_driver"
cp -a "$ksu_source/kernel/." "$ksu_driver/"
[[ -L "$ksu_driver/include/uapi" ]] || {
  printf 'Expected KernelSU UAPI symlink is missing after SUSFS patching\n' >&2
  exit 1
}
unlink "$ksu_driver/include/uapi"
cp -a "$ksu_source/uapi" "$ksu_driver/include/uapi"

ksu_tag="$(git -C "$ksu_source" describe --tags --abbrev=0 HEAD 2>/dev/null || printf unknown)"
ksu_version_code="$((30000 + $(git -C "$ksu_source" rev-list --count HEAD)))"
sed -i \
  "s/^KSU_VERSION_FALLBACK := 1$/KSU_VERSION_FALLBACK := $ksu_version_code/" \
  "$ksu_driver/Kbuild"
sed -i \
  "s/^KSU_VERSION_TAG_FALLBACK := v0\.0\.1$/KSU_VERSION_TAG_FALLBACK := $ksu_tag/" \
  "$ksu_driver/Kbuild"
grep -qx "KSU_VERSION_FALLBACK := $ksu_version_code" "$ksu_driver/Kbuild"
grep -qx "KSU_VERSION_TAG_FALLBACK := $ksu_tag" "$ksu_driver/Kbuild"

sublevel="$(awk '/^SUBLEVEL =/{print $3; exit}' "$kernel_source/Makefile")"
if (( sublevel <= 141 )) && ! grep -q '^#include <linux/dma-buf.h>$' "$kernel_source/fs/proc/base.c"; then
  sed -i '/^#include <linux\/cpufreq_times.h>$/a #include <linux/dma-buf.h>' \
    "$kernel_source/fs/proc/base.c"
fi
if (( sublevel >= 157 )); then
  sed -i '/^#include <trace\/hooks\/blk.h>$/d' "$kernel_source/fs/namespace.c"
fi

cp -a "$susfs_source/kernel_patches/fs/." "$kernel_source/fs/"
cp -a "$susfs_source/kernel_patches/include/linux/." "$kernel_source/include/linux/"
patch \
  --directory="$kernel_source" \
  --batch \
  --forward \
  -p1 \
  < "$susfs_source/$susfs_patch"

if find "$kernel_source" -type f -name '*.rej' -print -quit | grep -q .; then
  find "$kernel_source" -type f -name '*.rej' -print >&2
  exit 1
fi

while IFS='=' read -r option value; do
  [[ -z "$option" || "$option" == \#* ]] && continue
  symbol="${option#CONFIG_}"
  case "$value" in
    y) "$kernel_source/scripts/config" --file "$defconfig" -e "$symbol" ;;
    n) "$kernel_source/scripts/config" --file "$defconfig" -d "$symbol" ;;
    *) "$kernel_source/scripts/config" --file "$defconfig" --set-val "$symbol" "$value" ;;
  esac
done < "$config_fragment"

printf 'SUSFS integrated: %s (%s), compatibility patches %s\n' \
  "$susfs_version" "$(git -C "$susfs_source" rev-parse HEAD)" "$resolved_patches_commit"
