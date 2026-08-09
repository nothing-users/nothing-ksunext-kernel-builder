#!/usr/bin/env bash
set -Eeuo pipefail

if (( $# != 4 )); then
  printf 'Usage: %s STOCK_BOOT IMAGE_GZ MAGISKBOOT OUTPUT_BOOT\n' "$0" >&2
  exit 2
fi

stock_boot="$(realpath "$1")"
image_gz="$(realpath "$2")"
magiskboot="$(realpath "$3")"
output_boot="$(realpath -m "$4")"

for input in "$stock_boot" "$image_gz" "$magiskboot"; do
  [[ -s "$input" ]] || {
    printf 'Missing repack input: %s\n' "$input" >&2
    exit 2
  }
done
[[ -x "$magiskboot" ]] || {
  printf 'magiskboot is not executable: %s\n' "$magiskboot" >&2
  exit 2
}

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$work_dir/unpack" "$work_dir/verify"

(
  cd "$work_dir/unpack"
  "$magiskboot" unpack -n "$stock_boot"
  [[ -s kernel ]] || {
    printf 'magiskboot did not extract the stock kernel\n' >&2
    exit 1
  }
  install -m 0644 "$image_gz" kernel
  "$magiskboot" repack -n "$stock_boot" "$output_boot"
)

[[ -s "$output_boot" ]] || {
  printf 'magiskboot did not produce a boot image\n' >&2
  exit 1
}

# magiskboot preserves the physical size of a full partition dump. Fastboot
# expects the logical boot image instead, so remove only the outer partition
# padding. Android boot header v4 has a fixed 4096-byte page size and records
# every payload size in the header.
read_le32() {
  od -An -tu4 -j "$1" -N 4 "$output_boot" | tr -d '[:space:]'
}

header_version="$(read_le32 40)"
header_size="$(read_le32 20)"
kernel_size="$(read_le32 8)"
ramdisk_size="$(read_le32 12)"
signature_size="$(read_le32 1580)"
[[ "$header_version" == 4 && "$header_size" == 1584 ]] || {
  printf 'Unexpected boot header: version=%s size=%s\n' \
    "$header_version" "$header_size" >&2
  exit 1
}

page_size=4096
align_page() {
  printf '%s\n' "$(( ($1 + page_size - 1) / page_size * page_size ))"
}
compact_size="$(($(align_page "$header_size") + \
  $(align_page "$kernel_size") + \
  $(align_page "$ramdisk_size") + \
  $(align_page "$signature_size")))"
repacked_size="$(stat -c '%s' "$output_boot")"
(( compact_size <= repacked_size )) || {
  printf 'Boot payload size exceeds repacked image (%s > %s)\n' \
    "$compact_size" "$repacked_size" >&2
  exit 1
}
truncate -s "$compact_size" "$output_boot"

stock_size="$(stat -c '%s' "$stock_boot")"
output_size="$(stat -c '%s' "$output_boot")"
(( output_size <= stock_size )) || {
  printf 'Repacked boot image is larger than the stock partition image (%s > %s)\n' \
    "$output_size" "$stock_size" >&2
  exit 1
}

(
  cd "$work_dir/verify"
  "$magiskboot" unpack -n "$output_boot"
  [[ -s kernel ]] || {
    printf 'magiskboot did not extract the repacked kernel\n' >&2
    exit 1
  }
  cmp --silent "$image_gz" kernel || {
    printf 'Kernel extracted from the repacked boot image does not match Image.gz\n' >&2
    exit 1
  }
)

printf 'Repacked boot image verified: %s bytes (partition image limit: %s bytes)\n' \
  "$output_size" "$stock_size"
sha256sum "$output_boot"
