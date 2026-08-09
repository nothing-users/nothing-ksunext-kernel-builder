[Русский](../README.md) | English

---

# Nothing Phone (3a) Asteroids KernelSU Next Builder

Reproducible Android Kleaf/Bazel boot-kernel builder with clean KernelSU Next for Nothing Phone (3a) and Phone (3a) Pro (`Asteroids`). SUSFS and third-party kernel patches are not applied.

This does not put Qualcomm's `pineapple_gki` output into the boot image. It builds the base GKI target `//common:kernel_aarch64`, which is the target compatible with the stock Nothing OS vendor modules.

## Workflow

1. Clone [`nothing-users/android_kernel_msm-6.1_nothing_sm7635`](https://github.com/nothing-users/android_kernel_msm-6.1_nothing_sm7635), defaulting to `sm7635/b/mr_Frogger`.
2. Sync the Kleaf dependencies from Android's `common-android14-6.1-2023-06` kernel manifest.
3. Fetch the selected `ksun_ref` from the official KernelSU Next repository and integrate the driver; verify that the final config has `CONFIG_KSU=y` with debug mode disabled.
4. Expose the patched source as both `common` and `msm-kernel`, matching the verified local workspace.
5. Build `//common:kernel_aarch64` with Qualcomm's KMI symbol list.
6. Validate the kernel configuration, the KernelSU Next init symbol, and all required outputs.
7. Download the pinned `Asteroids_B4.1-260618-1048` boot archive from Nothing Archive, verify both the archive and extracted boot-image SHA-256, replace only the kernel, preserve the partition size, and unpack the result to verify the embedded `Image.gz` byte for byte.
8. Upload `boot.img`, `Image`, `Image.gz`, the config, `System.map`, the build log, resolved versions, metadata, and SHA-256 hashes.

## Running a build

Open **Actions → Build Asteroids GKI with KernelSU Next → Run workflow**. Normally, leave `kernel_ref` at `sm7635/b/mr_Frogger` and `ksun_ref` at `dev`. Both inputs accept a branch, tag, or commit, and the artifact records the resolved commits. The artifact is named `asteroids-ksunext-<run number>`. Enabling `create_release` also creates a GitHub Release.

Test with `fastboot boot boot.img` before flashing. Keep a copy of the original image and verify audio, cameras, Wi-Fi, Bluetooth, cellular connectivity, charging, fingerprint, and suspend/resume.

The stock image comes from Nothing Archive's [`Asteroids_B4.1-260618-1048` release](https://github.com/spike0en/nothing_archive/releases/tag/Asteroids_B4.1-260618-1048). The exact release URLs and archive SHA-256 are pinned in the workflow, while the expected extracted `boot.img` SHA-256 is read from the release's `Asteroids_B4.1-260618-1048-hash.sha256` manifest. Nothing Archive is credited as required; OEM firmware remains the property of Nothing Technology Limited and is not stored in this repository.
