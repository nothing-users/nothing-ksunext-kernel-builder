#!/usr/bin/env bash
set -Eeuo pipefail

if (( $# != 5 )); then
  printf 'Usage: %s KERNEL_IMAGE OUTPUT_ZIP AK3_REPOSITORY AK3_COMMIT KERNEL_STRING\n' "$0" >&2
  exit 2
fi

kernel_image="$1"
output_zip="$2"
ak3_repository="$3"
ak3_commit="$4"
kernel_string="$5"

[[ -s "$kernel_image" ]] || {
  printf 'Missing kernel image: %s\n' "$kernel_image" >&2
  exit 2
}
[[ "$ak3_commit" =~ ^[0-9a-f]{40}$ ]] || {
  printf 'AnyKernel3 commit must be a full SHA-1: %s\n' "$ak3_commit" >&2
  exit 2
}

work_dir="$(mktemp -d)"
ak3_dir="$work_dir/AnyKernel3"
trap 'rm -rf -- "$work_dir"' EXIT

git init --quiet "$ak3_dir"
git -C "$ak3_dir" remote add origin "$ak3_repository"
git -C "$ak3_dir" -c protocol.version=2 fetch \
  --quiet \
  --depth=1 \
  --filter=blob:none \
  origin \
  "$ak3_commit"
git -C "$ak3_dir" checkout --quiet --detach FETCH_HEAD

resolved_commit="$(git -C "$ak3_dir" rev-parse HEAD)"
[[ "$resolved_commit" == "$ak3_commit" ]] || {
  printf 'Unexpected AnyKernel3 commit: %s\n' "$resolved_commit" >&2
  exit 1
}

anykernel="$ak3_dir/anykernel.sh"
[[ -f "$anykernel" ]] || {
  printf 'AnyKernel3 template is missing anykernel.sh\n' >&2
  exit 1
}
grep -qE '^device\.name[0-9]+=Asteroids$' "$anykernel" || {
  printf 'AnyKernel3 template does not support Asteroids\n' >&2
  exit 1
}

python3 - "$anykernel" "$kernel_string" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
kernel_string = sys.argv[2]
text = path.read_text()
updated, replacements = re.subn(
    r"(?m)^kernel\.string=.*$",
    f"kernel.string={kernel_string}",
    text,
    count=1,
)
if replacements != 1:
    raise SystemExit("Could not set kernel.string in anykernel.sh")
path.write_text(updated)
PY

install -m 0644 "$kernel_image" "$ak3_dir/Image"
mkdir -p "$(dirname "$output_zip")"

(
  cd "$ak3_dir"
  zip -q -r9 "$output_zip" . \
    -x '.git/*' \
    -x '.github/*' \
    -x '.gitignore' \
    -x 'README.md' \
    -x '*placeholder'
)

[[ -s "$output_zip" ]] || {
  printf 'AnyKernel3 package was not produced: %s\n' "$output_zip" >&2
  exit 1
}
for required in Image anykernel.sh META-INF/com/google/android/update-binary; do
  unzip -Z1 "$output_zip" | grep -qxF "$required" || {
    printf 'AnyKernel3 package is missing %s\n' "$required" >&2
    exit 1
  }
done

printf 'AnyKernel3 package: %s (%s)\n' "$output_zip" "$resolved_commit"
sha256sum "$output_zip"
