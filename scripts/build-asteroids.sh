#!/usr/bin/env bash
set -Eeuo pipefail

if (( $# != 6 )); then
  printf 'Usage: %s WORKSPACE ARTIFACT_DIR KLEAF_TARGET KMI_SYMBOL_LIST BUILD_VARIANT SUSFS_CONFIG\n' "$0" >&2
  exit 2
fi

workspace="$1"
artifact_dir="$2"
kleaf_target="$3"
kmi_symbol_list="$4"
build_variant="$5"
susfs_config="$6"
output_dir="$workspace/bazel-bin/common/kernel_aarch64"
config="$workspace/bazel-bin/common/kernel_aarch64_config/out_dir/.config"
build_log="$artifact_dir/build.log"

mkdir -p "$artifact_dir"

(
  cd "$workspace"
  export TARGET_PRODUCT=Asteroids
  ./tools/bazel build \
    --nostamp \
    --ignore_missing_projects \
    "--user_kmi_symbol_lists=$kmi_symbol_list" \
    "$kleaf_target"
) 2>&1 | tee "$build_log"

for output in Image Image.gz System.map; do
  [[ -s "$output_dir/$output" ]] || {
    printf 'Missing Kleaf output: %s\n' "$output_dir/$output" >&2
    exit 1
  }
done
[[ -s "$config" ]] || {
  printf 'Missing Kleaf kernel config: %s\n' "$config" >&2
  exit 1
}

grep -qx '# CONFIG_MODULE_SIG_PROTECT is not set' "$config"
grep -qx 'CONFIG_MODULE_SIG_ALL=y' "$config"
grep -qx 'CONFIG_TRIM_UNUSED_KSYMS=y' "$config"
grep -qx 'CONFIG_KSU=y' "$config"
grep -qx '# CONFIG_KSU_DEBUG is not set' "$config"
grep -Eq '[[:space:]](kernelsu_init|kernelsu_init_early)$' "$output_dir/System.map" || {
  printf 'KernelSU Next init symbol is missing from System.map\n' >&2
  exit 1
}

case "$build_variant" in
  ksunext)
    if grep -qx 'CONFIG_KSU_SUSFS=y' "$config"; then
      printf 'The clean KernelSU Next variant unexpectedly enabled SUSFS\n' >&2
      exit 1
    fi
    ;;
  ksunext-susfs)
    [[ -f "$susfs_config" ]] || {
      printf 'Missing SUSFS config fragment: %s\n' "$susfs_config" >&2
      exit 2
    }
    while IFS='=' read -r option value; do
      [[ -z "$option" || "$option" == \#* ]] && continue
      if [[ "$value" == n ]]; then
        expected="# $option is not set"
      else
        expected="$option=$value"
      fi
      grep -qxF "$expected" "$config" || {
        printf 'Required SUSFS config was not enabled: %s\n' "$expected" >&2
        exit 1
      }
    done < "$susfs_config"
    ;;
  *)
    printf 'Unsupported build variant: %s\n' "$build_variant" >&2
    exit 2
    ;;
esac

install -m 0644 "$output_dir/Image" "$artifact_dir/Image"
install -m 0644 "$output_dir/Image.gz" "$artifact_dir/Image.gz"
install -m 0644 "$output_dir/System.map" "$artifact_dir/System.map"
install -m 0644 "$config" "$artifact_dir/kernel.config"

kernel_version="$(strings "$output_dir/Image" | sed -n 's/^Linux version \([^ ]*\).*/\1/p' | head -n 1)"
[[ -n "$kernel_version" ]] || {
  printf 'Unable to determine the built kernel version\n' >&2
  exit 1
}
version_line="$(strings "$output_dir/Image" | grep -m1 '^Linux version ' || true)"
[[ -n "$version_line" && "$version_line" != *maybe-dirty* && "$version_line" != *1970* ]] || {
  printf 'Invalid embedded kernel version string: %s\n' "$version_line" >&2
  exit 1
}
[[ "$version_line" == *'(wee@mrvoki)'* ]] || {
  printf 'Unexpected kernel build identity: %s\n' "$version_line" >&2
  exit 1
}
printf '%s\n' "$kernel_version" > "$artifact_dir/kernel-version.txt"
printf '%s\n' "$version_line" > "$artifact_dir/kernel-version-string.txt"

printf 'Built %s (%s)\n' "$kernel_version" "$kleaf_target"
printf 'Embedded version: %s\n' "$version_line"
sha256sum "$artifact_dir/Image" "$artifact_dir/Image.gz"
