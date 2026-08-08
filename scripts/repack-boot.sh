#!/usr/bin/env bash
set -Eeuo pipefail

if (( $# != 4 )); then
  printf 'Usage: %s STOCK_BOOT IMAGE_GZ MKBOOTIMG_DIR OUTPUT_BOOT\n' "$0" >&2
  exit 2
fi

stock_boot="$1"
image_gz="$2"
mkbootimg_dir="$3"
output_boot="$4"
unpack_script="$mkbootimg_dir/unpack_bootimg.py"
mkbootimg_script="$mkbootimg_dir/mkbootimg.py"

for input in "$stock_boot" "$image_gz" "$unpack_script" "$mkbootimg_script"; do
  [[ -s "$input" ]] || {
    printf 'Missing repack input: %s\n' "$input" >&2
    exit 2
  }
done

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

stock_info="$(python3 "$unpack_script" --boot_img "$stock_boot" --out "$work_dir/stock" --format=mkbootimg)"
[[ "$stock_info" == *'--header_version 4'* ]] || {
  printf 'The supplied image is not an Android boot header v4 image: %s\n' "$stock_info" >&2
  exit 1
}
[[ "$stock_info" == *"--cmdline ''"* ]] || {
  printf 'Unexpected non-empty stock boot cmdline: %s\n' "$stock_info" >&2
  exit 1
}

python3 "$mkbootimg_script" \
  --header_version 4 \
  --kernel "$image_gz" \
  --ramdisk "$work_dir/stock/ramdisk" \
  --cmdline '' \
  --output "$output_boot"

stock_size="$(stat -c '%s' "$stock_boot")"
output_size="$(stat -c '%s' "$output_boot")"
(( output_size <= stock_size )) || {
  printf 'Repacked boot image is larger than the stock partition image (%s > %s)\n' "$output_size" "$stock_size" >&2
  exit 1
}
truncate -s "$stock_size" "$output_boot"

new_info="$(python3 "$unpack_script" --boot_img "$output_boot" --out "$work_dir/new" --format=mkbootimg)"
[[ "$new_info" == *'--header_version 4'* ]] || {
  printf 'Repacked image failed header validation\n' >&2
  exit 1
}
cmp --silent "$image_gz" "$work_dir/new/kernel" || {
  printf 'Kernel extracted from the repacked boot image does not match Image.gz\n' >&2
  exit 1
}

printf 'Repacked boot image verified: %s (%s bytes)\n' "$output_boot" "$stock_size"
sha256sum "$output_boot"
