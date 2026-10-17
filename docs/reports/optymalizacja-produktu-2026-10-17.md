# Optymalizacja produktu - 2026-10-17

Branch: `perf/product-optimization`. Kolejność commitów odpowiada etapom: 1, 2, 3, 4, 6, 5, 7, 8, 9, 10, 11, 12. Docelowa integracja przez squash.

## Etap 1 - punkt odniesienia

Testy UI podzielone według funkcji, ze wspólną bazą AppUITestSupport. Testy wymagające pasteboardu, Keychain i atrybutów backupu mają jawny warunek `MM_SYSTEM_TESTS=1`. Brak konfiguracji Spotlight jest raportowany jako pominięcie zamiast pozornego sukcesu.

Uruchomienia:

```sh
swift test --package-path Packages/MacManagerCore
MM_SYSTEM_TESTS=1 swift test --package-path Packages/MacManagerCore
MM_LAUNCHER_TEST_ROOT="$PWD" swift test --package-path Packages/MacManagerCore --filter launcherSpotlightSearchesOnlyExplicitRepositoryFixture
MM_BENCHMARKS=1 swift test -c release --package-path Packages/MacManagerCore --filter launcherRankingBenchmark
xcodebuild -project MacManager.xcodeproj -scheme MacManager -configuration Debug build-for-testing
```

Zestaw logiki: 148 testów, bez błędów; integracje systemowe jawnie pominięte przy braku flag. Benchmark używa syntetycznych katalogów 200/1000/5000 wpisów i 180 zapytań na katalog. Nie mierzy czasu do pierwszej klatki UI. Czasy UI, pamięć i animacje wymagają odrębnej sesji profilowania, dlatego nie są przedstawiane jako zmierzone.

## Etap 2 - ustawienia wyspy

Obserwacja ponownie uzbraja watchPreferences, które stosuje ustawienia dokładnie raz. Usunięto dodatkowe wywołanie applyPreferences z callbacku. Bazowy build testów UI i 149 testów Core (z integracjami systemowymi) przeszły; wcześniejsze błędy pasteboardu/Keychain/backup wynikały z ograniczonego środowiska wykonania.

## Etap 3 - obrazy

ImageThumbnail centralizuje ograniczone skalowanie i kodowanie PNG. Music i Podcasts używają identycznych limitów jak wcześniej; schowek zachowuje osobną walidację oryginału. Test wymiarów, błędnych danych i budżetów przeszedł.

Bazowy ranking Release, mediana/P95 w ms: 200 wpisów 0,094/0,103; 1000 wpisów 0,446/0,479; 5000 wpisów 2,631/3,804. Syntetyczny katalog, jedna seria pomiarowa.

## Etap 4 - miniatury schowka

Zadanie widoku jest identyfikowane wpisem, typem i stanem zawieszenia, zamiast rewizją całej historii. Teksty nie odpytują repozytorium o miniatury. Usunięto puste pole ClipboardEntry.thumbnail; zaszyfrowany Preview i odczyt wersji 1/2 pozostają zgodne. 25 testów schowka i obrazów, łącznie z integracjami systemowymi, przeszło.
