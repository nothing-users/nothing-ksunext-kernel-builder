#!/usr/bin/env bash
set -Eeuo pipefail

if (( $# != 4 )); then
  printf 'Usage: %s WORKSPACE KERNEL_SOURCE MANIFEST_URL MANIFEST_BRANCH\n' "$0" >&2
  exit 2
fi

workspace="$1"
kernel_source="$2"
manifest_url="$3"
manifest_branch="$4"
repo_launcher="$workspace/repo"
dtc_commit="6ab7e35a241f6b1513c4701c66fe479ab040eafb"

[[ -f "$kernel_source/bazel.WORKSPACE" ]] || {
  printf 'Patched kernel source is missing bazel.WORKSPACE: %s\n' "$kernel_source" >&2
  exit 2
}
[[ -f "$kernel_source/build.config.nothing.Asteroids.bazel" ]] || {
  printf 'Kernel ref does not contain Asteroids Kleaf support\n' >&2
  exit 2
}
[[ -f "$kernel_source/kleaf_support/compat.bzl" ]] || {
  printf 'Kernel ref does not contain Qualcomm Kleaf compatibility shims\n' >&2
  exit 2
}

rm -rf "$workspace"
mkdir -p "$workspace"

curl --fail --location --retry 3 \
  https://storage.googleapis.com/git-repo-downloads/repo \
  --output "$repo_launcher"
chmod +x "$repo_launcher"

(
  cd "$workspace"
  python3 "$repo_launcher" init \
    -u "$manifest_url" \
    -b "$manifest_branch" \
    --depth=1 \
    --no-repo-verify

  python3 "$repo_launcher" sync \
    --use-superproject \
    -c \
    --no-tags \
    --no-clone-bundle \
    -j4 \
    build/kernel \
    build/bazel_common_rules \
    external/bazel-skylib \
    external/stardoc \
    external/python/absl-py \
    prebuilts/bazel/linux-x86_64 \
    prebuilts/jdk/jdk11 \
    prebuilts/ndk-r23 \
    prebuilts/clang/host/linux-x86 \
    prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8 \
    prebuilts/build-tools \
    prebuilts/clang-tools \
    prebuilts/kernel-build-tools \
    kernel/configs \
    kernel/tests \
    common-modules/virtual-device \
    tools/mkbootimg

  mkdir -p external/dtc
  git -C external/dtc init
  git -C external/dtc remote add origin https://android.googlesource.com/platform/external/dtc
  git -C external/dtc fetch --depth=1 origin "$dtc_commit"
  git -C external/dtc checkout --detach FETCH_HEAD

  rm -f WORKSPACE common msm-kernel build/BUILD.bazel build/msm_kernel_extensions.bzl
  ln -s "$kernel_source" common
  ln -s "$kernel_source" msm-kernel
  ln -s msm-kernel/bazel.WORKSPACE WORKSPACE
  ln -s ../msm-kernel/kleaf_support/BUILD.bazel build/BUILD.bazel
  ln -s ../msm-kernel/msm_kernel_extensions.bzl build/msm_kernel_extensions.bzl
)

[[ -x "$workspace/tools/bazel" ]] || {
  printf 'Kleaf Bazel launcher was not created\n' >&2
  exit 1
}
[[ -x "$workspace/tools/mkbootimg/mkbootimg.py" ]] || {
  printf 'mkbootimg tools were not synced\n' >&2
  exit 1
}

printf 'Kleaf workspace ready: %s\n' "$workspace"
