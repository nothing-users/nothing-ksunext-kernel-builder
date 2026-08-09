Русский | [English](docs/README_EN.md)

---

# Nothing Phone (3a) Asteroids KernelSU Next + SUSFS Builder

Воспроизводимая параллельная сборка двух вариантов загрузочного ядра для Nothing Phone (3a) и Phone (3a) Pro (`Asteroids`) через Android Kleaf/Bazel: чистый KernelSU Next и KernelSU Next с SUSFS.

Это не сборка Qualcomm `pineapple_gki`. В `boot.img` помещается базовый GKI из цели `//common:kernel_aarch64`, совместимый со стоковыми vendor-модулями Nothing OS.

## Что делает workflow

1. Клонирует форк [`nothing-users/android_kernel_msm-6.1_nothing_sm7635`](https://github.com/nothing-users/android_kernel_msm-6.1_nothing_sm7635) и ветку `sm7635/b/mr_Frogger`.
2. Загружает Android kernel manifest `common-android14-6.1-2023-06` и необходимые зависимости Kleaf.
3. В двух независимых matrix-job загружает выбранный `ksun_ref` из официального репозитория KernelSU Next и подключает драйвер.
4. Для варианта `ksunext-susfs` дополнительно применяет SUSFS и compatibility fixes из тех же зафиксированных источников, что используются в ветке `dev`; обычный вариант `ksunext` остаётся без SUSFS.
5. Подключает исходники одновременно как `common` и `msm-kernel`, как в проверенной локальной сборке.
6. Параллельно собирает оба варианта `//common:kernel_aarch64` с KMI-списком Qualcomm и проверяет их итоговые конфигурации, символ KernelSU Next и обязательные файлы.
7. Загружает зафиксированный boot archive `Asteroids_B4.1-260618-1048` из Nothing Archive, проверяет SHA-256 архива и извлечённого `boot.img`, заменяет только kernel на новый `Image.gz`, восстанавливает размер раздела и повторно проверяет содержимое образа.
8. Собирает flashable ZIP на базе зафиксированного [`nothing-users/AnyKernel3-Nothing`](https://github.com/nothing-users/AnyKernel3-Nothing) и публикует три компактных artifacts: два `boot.img`, два AnyKernel3 ZIP и логи обоих вариантов с метаданными и SHA-256.

## Запуск

Откройте **Actions → Build Asteroids GKI with KernelSU Next and SUSFS → Run workflow**.

Обычно достаточно оставить `kernel_ref` равным `sm7635/b/mr_Frogger`, `ksun_ref` и `ksun_patchset` — `dev`, а `susfs_ref` — `gki-android14-6.1`. Поля ref принимают branch, tag или commit; artifacts записывают фактически использованные commit ядра, KernelSU Next, SUSFS и compatibility patches.

Результаты появятся в artifacts `asteroids-boot-images-<run>-<attempt>`, `asteroids-anykernel3-<run>-<attempt>` и `asteroids-build-logs-<run>-<attempt>`. Опция `create_release` создаёт один GitHub Release с двумя именованными `boot.img`, двумя AnyKernel3 ZIP и одним архивом логов.

## Проверка без прошивки

Сначала всегда используйте временную загрузку:

```text
fastboot boot boot.img
```

После загрузки проверьте звук, камеры, Wi-Fi, Bluetooth, мобильную сеть, зарядку, отпечаток и сон. Сохраните оригинальный образ перед `fastboot flash boot`.

## Источник стокового образа

Стоковый образ берётся из релиза [`Asteroids_B4.1-260618-1048`](https://github.com/spike0en/nothing_archive/releases/tag/Asteroids_B4.1-260618-1048) проекта [Nothing Archive](https://github.com/spike0en/nothing_archive). В workflow зафиксированы точные URL релиза и SHA-256 архива, а ожидаемый SHA-256 `boot.img` извлекается из опубликованного в том же релизе файла `Asteroids_B4.1-260618-1048-hash.sha256`. Этот boot image побайтно совпадает с образом, на котором была проверена локальная сборка.

Nothing Archive используется с указанием авторства. OEM firmware принадлежит Nothing Technology Limited и загружается только во время сборки; binary firmware не хранится в этом репозитории. Workflow прекращает работу при несовпадении контрольной суммы или структуры boot image.
