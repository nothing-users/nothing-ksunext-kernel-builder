#!/usr/bin/env bash
set -Eeuo pipefail

if (( $# != 4 )); then
  printf 'Usage: %s KERNEL_SOURCE KSU_SOURCE KSU_REPOSITORY KSU_REF\n' "$0" >&2
  exit 2
fi

kernel_source="$1"
ksu_source="$2"
ksu_repository="$3"
ksu_ref="$4"
ksu_driver="$kernel_source/drivers/kernelsu"
defconfig="$kernel_source/arch/arm64/configs/gki_defconfig"

for required in \
  "$kernel_source/drivers/Makefile" \
  "$kernel_source/drivers/Kconfig" \
  "$defconfig"; do
  [[ -f "$required" ]] || {
    printf 'Missing KernelSU integration input: %s\n' "$required" >&2
    exit 2
  }
done

grep -qx 'CONFIG_KPROBES=y' "$defconfig" || {
  printf 'KernelSU Next requires CONFIG_KPROBES=y\n' >&2
  exit 1
}
grep -qx 'CONFIG_EXT4_FS=y' "$defconfig" || {
  printf 'KernelSU Next requires CONFIG_EXT4_FS=y\n' >&2
  exit 1
}

[[ ! -e "$ksu_source" && ! -L "$ksu_source" ]] || {
  printf 'KernelSU source path already exists: %s\n' "$ksu_source" >&2
  exit 2
}
[[ ! -e "$ksu_driver" && ! -L "$ksu_driver" ]] || {
  printf 'KernelSU driver path already exists: %s\n' "$ksu_driver" >&2
  exit 2
}

git init "$ksu_source" >/dev/null
git -C "$ksu_source" remote add origin "$ksu_repository"
git -C "$ksu_source" -c protocol.version=2 fetch \
  --filter=blob:none \
  --tags \
  origin \
  "$ksu_ref"
git -C "$ksu_source" checkout --detach FETCH_HEAD

for required in kernel/Kbuild kernel/Kconfig kernel/core/init.c; do
  [[ -f "$ksu_source/$required" ]] || {
    printf 'Fetched KernelSU ref is missing %s\n' "$required" >&2
    exit 1
  }
done

ksu_commit="$(git -C "$ksu_source" rev-parse HEAD)"
ksu_tag="$(git -C "$ksu_source" describe --tags --abbrev=0 HEAD 2>/dev/null || printf unknown)"
ksu_version_code="$((30000 + $(git -C "$ksu_source" rev-list --count HEAD)))"
[[ "$ksu_tag" =~ ^[A-Za-z0-9._+-]+$ ]] || {
  printf 'Unsupported KernelSU tag for Kbuild metadata: %s\n' "$ksu_tag" >&2
  exit 1
}

# Kleaf's source glob does not traverse a directory symlink here. Copy the
# kernel-only tree so Kconfig and Kbuild see every file inside the sandbox.
mkdir -p "$ksu_driver"
cp -a "$ksu_source/kernel/." "$ksu_driver/"

# In the upstream tree this points from kernel/include/uapi to the repository's
# top-level uapi directory. Materialize it because its relative target changes
# after the kernel-only tree is copied under drivers/.
[[ -L "$ksu_driver/include/uapi" ]] || {
  printf 'Expected KernelSU UAPI symlink is missing\n' >&2
  exit 1
}
unlink "$ksu_driver/include/uapi"
cp -a "$ksu_source/uapi" "$ksu_driver/include/uapi"

# The separate KernelSU .git directory is intentionally outside Kleaf's
# sandbox. Preserve the exact upstream version metadata via Kbuild fallbacks.
sed -i \
  "s/^KSU_VERSION_FALLBACK := 1$/KSU_VERSION_FALLBACK := $ksu_version_code/" \
  "$ksu_driver/Kbuild"
sed -i \
  "s/^KSU_VERSION_TAG_FALLBACK := v0\.0\.1$/KSU_VERSION_TAG_FALLBACK := $ksu_tag/" \
  "$ksu_driver/Kbuild"
grep -qx "KSU_VERSION_FALLBACK := $ksu_version_code" "$ksu_driver/Kbuild"
grep -qx "KSU_VERSION_TAG_FALLBACK := $ksu_tag" "$ksu_driver/Kbuild"

if ! grep -q 'CONFIG_KSU.*kernelsu/' "$kernel_source/drivers/Makefile"; then
  printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$kernel_source/drivers/Makefile"
fi

if ! grep -q 'drivers/kernelsu/Kconfig' "$kernel_source/drivers/Kconfig"; then
  sed -i '/^endmenu$/i source "drivers/kernelsu/Kconfig"' "$kernel_source/drivers/Kconfig"
fi

printf 'KernelSU Next integrated: %s (%s, version code %s)\n' \
  "$ksu_commit" "$ksu_tag" "$ksu_version_code"
