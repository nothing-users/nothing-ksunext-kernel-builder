[Русский](../README.md) | English

---

# Nothing Phone (3a) Asteroids GKI Builder

Reproducible Android Kleaf/Bazel boot-kernel builder for Nothing Phone (3a) and Phone (3a) Pro (`Asteroids`).

This does not put Qualcomm's `pineapple_gki` output into the boot image. It builds the base GKI target `//common:kernel_aarch64`, which is the target compatible with the stock Nothing OS vendor modules.

## Workflow

1. Clone [`nothing-users/android_kernel_msm-6.1_nothing_sm7635`](https://github.com/nothing-users/android_kernel_msm-6.1_nothing_sm7635), defaulting to `sm7635/b/mr_Frogger`.
2. Sync the Kleaf dependencies from Android's `common-android14-6.1-2023-06` kernel manifest.
3. Expose the patched source as both `common` and `msm-kernel`, matching the verified local workspace.
4. Build `//common:kernel_aarch64` with Qualcomm's KMI symbol list.
5. Validate the kernel configuration and all required outputs.
6. Download the pinned `Asteroids_B4.1-260618-1048` boot archive from Nothing Archive, verify both the archive and extracted boot-image SHA-256, replace only the kernel, preserve the partition size, and unpack the result to verify the embedded `Image.gz` byte for byte.
7. Upload `boot.img`, `Image`, `Image.gz`, the config, `System.map`, the build log, metadata, and SHA-256 hashes.

## Running a build

Open **Actions → Build Asteroids GKI → Run workflow**. Normally, leave `kernel_ref` at `sm7635/b/mr_Frogger`. The artifact is named `asteroids-gki-<run number>`. Enabling `create_release` also creates a GitHub Release.

Test with `fastboot boot boot.img` before flashing. Keep a copy of the original image and verify audio, cameras, Wi-Fi, Bluetooth, cellular connectivity, charging, fingerprint, and suspend/resume.

The stock image comes from Nothing Archive's [`Asteroids_B4.1-260618-1048` release](https://github.com/spike0en/nothing_archive/releases/tag/Asteroids_B4.1-260618-1048). The exact release URLs and archive SHA-256 are pinned in the workflow, while the expected extracted `boot.img` SHA-256 is read from the release's `Asteroids_B4.1-260618-1048-hash.sha256` manifest. Nothing Archive is credited as required; OEM firmware remains the property of Nothing Technology Limited and is not stored in this repository.
