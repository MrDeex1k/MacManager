# Ikona Mac Manager

Grafitowe tło i miętowy szklany monitor z trzema wskaźnikami. Motyw łączy komputer z monitorowaniem zasobów, zachowując jeden akcent zgodny z interfejsem. Bez tekstu; symbol pozostaje czytelny w małych rozmiarach.

master.png to finalny obraz źródłowy wygenerowany dla projektu z użyciem imagegen. Jest nieprzezroczysty i dochodzi do krawędzi płótna, bez zapisanej szachownicy ani pozornej przezroczystości. To statyczny zasób rastrowy inspirowany szkłem, nie warstwowy dokument Icon Composer. Natywne materiały kontrolek w aplikacji pozostają prawdziwymi API Liquid Glass.

[Apple opisuje dostosowanie kształtu istniejących ikon do macOS 26](https://developer.apple.com/videos/play/wwdc2025/220/). Nie wspieramy starszych wersji macOS. Dedykowane warianty warstwowe Icon Composer mogą być późniejszym rozszerzeniem marki.

## Zasoby i odtwarzanie

- Źródło: Design/AppIcon/master.png.
- Katalog: MacManager/Resources/Assets.xcassets/AppIcon.appiconset.
- 10 wariantów macOS: 16, 32, 128, 256 i 512 punktów w skalach 1×/2× (do 1024 px).
- Xcode: ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon w Debug i Release.

Po zmianie obrazu źródłowego uruchomić z repozytorium:

```sh
./scripts/build-app-icon.sh
```

Skrypt korzysta z systemowego sips wyłącznie do przygotowania rozmiarów PNG. Build kompiluje zasób do AppIcon.icns/Assets.car i ustawia odwołanie ikony w Info.plist. Nie trzeba zewnętrznych bibliotek ani generatora podczas zwykłego budowania aplikacji.

Kontrola: obejrzano wersję 64 px i źródło, sprawdzono wymiary plików oraz dołączenie AppIcon w zbudowanej aplikacji. Zmiana ikony istniejącej instalacji może wymagać ponownego uruchomienia aplikacji, zanim system odświeży jej prezentację.
