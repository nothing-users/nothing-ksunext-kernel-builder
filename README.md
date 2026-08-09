Русский | [English](docs/README_EN.md)

---

# Nothing Phone (3a) Asteroids GKI Builder

Воспроизводимая сборка загрузочного ядра для Nothing Phone (3a) и Phone (3a) Pro (`Asteroids`) через Android Kleaf/Bazel.

Это не сборка Qualcomm `pineapple_gki`. В `boot.img` помещается базовый GKI из цели `//common:kernel_aarch64`, совместимый со стоковыми vendor-модулями Nothing OS.

## Что делает workflow

1. Клонирует форк [`nothing-users/android_kernel_msm-6.1_nothing_sm7635`](https://github.com/nothing-users/android_kernel_msm-6.1_nothing_sm7635) и ветку `sm7635/b/mr_Frogger`.
2. Загружает Android kernel manifest `common-android14-6.1-2023-06` и необходимые зависимости Kleaf.
3. Подключает исходники одновременно как `common` и `msm-kernel`, как в проверенной локальной сборке.
4. Собирает `//common:kernel_aarch64` с KMI-списком Qualcomm.
5. Проверяет обязательные параметры конфигурации и наличие `Image`, `Image.gz` и `System.map`.
6. Загружает зафиксированный boot archive `Asteroids_B4.1-260618-1048` из Nothing Archive, проверяет SHA-256 архива и извлечённого `boot.img`, заменяет только kernel на новый `Image.gz`, восстанавливает размер раздела и повторно проверяет содержимое образа.
7. Публикует готовый `boot.img`, ядро, конфигурацию, карту символов, лог и SHA-256.

## Запуск

Откройте **Actions → Build Asteroids GKI → Run workflow**.

Обычно достаточно оставить `kernel_ref` равным `sm7635/b/mr_Frogger`. Можно указать другой branch, tag или commit этого же форка, если он содержит поддержку Asteroids Kleaf.

Результат появится в artifact `asteroids-gki-<run number>`. Опция `create_release` дополнительно создаёт GitHub Release.

## Проверка без прошивки

Сначала всегда используйте временную загрузку:

```text
fastboot boot boot.img
```

После загрузки проверьте звук, камеры, Wi-Fi, Bluetooth, мобильную сеть, зарядку, отпечаток и сон. Сохраните оригинальный образ перед `fastboot flash boot`.

## Источник стокового образа

Стоковый образ берётся из релиза [`Asteroids_B4.1-260618-1048`](https://github.com/spike0en/nothing_archive/releases/tag/Asteroids_B4.1-260618-1048) проекта [Nothing Archive](https://github.com/spike0en/nothing_archive). В workflow зафиксированы точные URL релиза и SHA-256 архива, а ожидаемый SHA-256 `boot.img` извлекается из опубликованного в том же релизе файла `Asteroids_B4.1-260618-1048-hash.sha256`. Этот boot image побайтно совпадает с образом, на котором была проверена локальная сборка.

Nothing Archive используется с указанием авторства. OEM firmware принадлежит Nothing Technology Limited и загружается только во время сборки; binary firmware не хранится в этом репозитории. Workflow прекращает работу при несовпадении контрольной суммы или структуры boot image.
