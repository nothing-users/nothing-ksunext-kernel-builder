[Русский](../README.md) | English

---

# Nothing Phone (3a) Asteroids KernelSU Next + SUSFS Builder

Reproducible parallel Android Kleaf/Bazel boot-kernel builder for Nothing Phone (3a) and Phone (3a) Pro (`Asteroids`). Each run builds both clean KernelSU Next and KernelSU Next with SUSFS.

This does not put Qualcomm's `pineapple_gki` output into the boot image. It builds the base GKI target `//common:kernel_aarch64`, which is the target compatible with the stock Nothing OS vendor modules.

## Workflow

1. Clone [`nothing-users/android_kernel_msm-6.1_nothing_sm7635`](https://github.com/nothing-users/android_kernel_msm-6.1_nothing_sm7635), defaulting to `sm7635/b/mr_Frogger`.
2. Sync the Kleaf dependencies from Android's `common-android14-6.1-2023-06` kernel manifest.
3. Fetch the selected `ksun_ref` from the official KernelSU Next repository in two independent matrix jobs.
4. In the `ksunext-susfs` variant, additionally apply SUSFS and the compatibility fixes pinned by the `dev` branch; keep the regular `ksunext` variant free of SUSFS.
5. Expose each source tree as both `common` and `msm-kernel`, matching the verified local workspace.
6. Build both `//common:kernel_aarch64` variants in parallel with Qualcomm's KMI symbol list, validating their final configs, KernelSU Next init symbol, and required outputs.
7. Download the pinned `Asteroids_B4.1-260618-1048` boot archive from Nothing Archive, verify both the archive and extracted boot-image SHA-256, replace only the kernel, preserve the partition size, and unpack the result to verify the embedded `Image.gz` byte for byte.
8. Upload `boot.img`, `Image`, `Image.gz`, the config, `System.map`, the build log, resolved versions, metadata, and SHA-256 hashes for both variants.

## Running a build

Open **Actions → Build Asteroids GKI with KernelSU Next and SUSFS → Run workflow**. Normally, leave `kernel_ref` at `sm7635/b/mr_Frogger`, `ksun_ref` and `ksun_patchset` at `dev`, and `susfs_ref` at `gki-android14-6.1`. Ref inputs accept a branch, tag, or commit, and the artifacts record the resolved commits. Results are named `asteroids-ksunext-<run number>` and `asteroids-ksunext-susfs-<run number>`. Enabling `create_release` creates one release containing uniquely prefixed files from both variants.

Test with `fastboot boot boot.img` before flashing. Keep a copy of the original image and verify audio, cameras, Wi-Fi, Bluetooth, cellular connectivity, charging, fingerprint, and suspend/resume.

The stock image comes from Nothing Archive's [`Asteroids_B4.1-260618-1048` release](https://github.com/spike0en/nothing_archive/releases/tag/Asteroids_B4.1-260618-1048). The exact release URLs and archive SHA-256 are pinned in the workflow, while the expected extracted `boot.img` SHA-256 is read from the release's `Asteroids_B4.1-260618-1048-hash.sha256` manifest. Nothing Archive is credited as required; OEM firmware remains the property of Nothing Technology Limited and is not stored in this repository.
