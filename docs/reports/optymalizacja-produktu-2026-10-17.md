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

## Etap 6 - komponenty prezentacji

ShortcutEditor obsługuje ustawienia launchera, wyspy i personalizacji. Wspólne elementy Charts odpowiadają za oś względnego czasu i pusty stan; zakresy wartości, serie i jednostki pozostają w widokach. Build aplikacji oraz wszystkich plików testów UI przeszedł.

## Etap 5 - wyszukiwanie schowka

ClipboardSearchModel jest osobnym stanem dla każdej powierzchni, współdzieląc implementację request/revision, anulowania, błędów i publikacji wyników. Okno, wyspa i launcher korzystają z tego modelu z dotychczasowymi limitami. Test odrzucania anulowanego/starego żądania i czyszczenia prywatnych wyników oraz build aplikacji przeszły.

## Etap 7 - sesja i obserwacje

NotificationTokens zwalnia rejestracje przy stop oraz zwolnieniu właściciela. SystemSessionMonitor jest jednym źródłem sleep/lock/inactiveSession dla kontrolerów; polityki nadal rozróżniają pełne zawieszenie od samego snu. Clipboard zachowuje maintenance po wake. Test nakładających się powodów zawieszenia i build aplikacji przeszły.

## Etap 8 - składanie aplikacji i odtwarzacze

AppDependencies składa jeden wspólny zestaw usług i uczestników cyklu życia; fixture podmieniają adaptery graniczne i zachowują izolowane dane. MediaSource opisuje bundle ID, teksty, symbole, powiadomienia i możliwości sterowania. Wyspa utrzymuje rejestr usług według źródła. Build aplikacji i testów UI przeszedł.

## Etap 9 - odpowiedzialności platformy

Panele AppKit wyspy i launchera mają osobne pliki i własną obsługę klawiatury. IslandWindowGeometry odpowiada za obszar aktywacji i metadane pełnego ekranu. LauncherIconCache i LauncherItemShortcuts przejmują zasoby systemowe. Koordynatory zachowują przepływ prezentacji, fokus i politykę personalizacji; animacje nadal należą do IslandTransitionHost. Build aplikacji przeszedł.

## Etap 10 - transport i usunięcia

BoundedHTTPClient wspólnie obsługuje ephemeral session, brak cookies/cache, odmowę przekierowań, timeout i limit strumienia. Interpretacja statusów i błędów pozostaje w klientach. Usunięto nieużywane mm_gpu_read/mm_power_read, cryptoCodes, normalize/abbreviate. mm_smc_key_at pozostaje dla prototypu Stage2. 153 testy Core oraz build aplikacji przeszły; test transportu używa syntetycznego URLProtocol.

Scenariusze UI schowka i czterech sekcji wyspy przeszły. Test personalizacji przeszedł zapis aliasu, ulubionych i konfliktu, ale nie otworzył okna przy końcowym Ctrl+Option+N: scenariusz nie ustawia takiego modyfikatora (domyślnie Option). Zostanie doprecyzowany przy końcowej weryfikacji.

## Etap 11 - skanowanie i obliczenia

Katalog aplikacji przekazuje rekordy z metadanymi z jednego skanu; cache jest lokalny dla skanu i odczytuje także symlinki na nowo przy kolejnym odświeżeniu. Okładki odcinka/audycji są wybierane po jednej przyrostowej enumeracji (budżet 2 s/100000 plików, maksymalnie 1024 pasujące warianty na typ). Przekroczenie budżetu zwraca brak okładki zamiast arbitralnego częściowego wyboru. Test katalogu 10050 plików przeszedł.

Kalkulator działa na osobnym actorze, otrzymując kontekst czasu/kalendarza/języka przechwycony przed wywołaniem. Ranking modelu używa rewizji katalogu i personalizacji; duże katalogi utrzymują kopiec najlepszych wyników, małe (do 512 wpisów) zachowują pełne sortowanie ze względu na jego niższy narzut. Testy zgodności z pełnym sortowaniem obejmują remisy, aliasy, ulubione i limity. 155 testów Core przed dodatkowym testem dużego katalogu oraz dodatkowe testy rankingu/skanu przeszły. Prototyp Stage2 nadal się kompiluje.

Porównanie syntetycznego rankingu Release (mediana/P95 ms, osobny przebieg bez równoległych testów):

| Katalog | Przed | Po |
| --- | --- | --- |
| 200 | 0,094 / 0,103 | 0,099 / 0,112 |
| 1000 | 0,446 / 0,479 | 0,419 / 0,500 |
| 5000 | 2,631 / 3,804 | 1,964 / 2,682 |

Zysk dotyczy głównie dużego katalogu; brak dowodu poprawy małego katalogu i P95 dla 1000 wpisów. Nie jest to pomiar opóźnienia całego interfejsu.

## Etap 12 - monitor wierszy i odbiór

LauncherRowMenuMonitor rejestruje jeden lokalny monitor na panel i utrzymuje słabe referencje do wierszy. Usuwa rejestrację po odłączeniu wierszy lub stop kontrolera. Test personalizacji jawnie wybiera Option+N i wysyła ten sam skrót przy sprawdzaniu akcji globalnej. Końcowy przegląd ograniczył reakcję sieci/updatera/energii do faktycznej zmiany snu i zachował rewizję niezmienionego katalogu przy ponownym otwarciu launchera.

`test-session-monitor.sh` sprawdza rzeczywisty mechanizm NotificationCenter przy użyciu syntetycznych powiadomień wewnątrz procesu. Potwierdza pojedynczą publikację, zachowanie zawieszenia po wake przy nieaktywnej sesji i usunięcie rejestracji przy stop; nie blokuje i nie usypia komputera. Wynik: PASS.

Końcowy zestaw Core Release: 156 testów, w tym systemowy pasteboard, Keychain, backup i faktycznie wykonany Spotlight, PASS. Benchmark jest osobnym, jawnym uruchomieniem (łącznie 157 definicji testów). Build aplikacji Release: PASS. Prototyp czujników Stage2: kompilacja PASS.

Pełny pierwszy przebieg UI: 32/36. Niezmieniona kopia main odtworzyła błąd kontrastu częściowo widocznego nagłówka wentylatorów oraz kliknięcie autostartu poza widocznym obszarem. Audyt kontrastu pozostaje aktywny i nie jest wyciszany. Testy przewijania otrzymały gesty wykonywane wewnątrz przecięcia scroll view z oknem oraz kontrolę kierunku rzeczywistego przesunięcia.

Celowany scenariusz aliasu/ulubionych/konfliktu/globalnego skrótu przeszedł po jawnym wyborze Option+N, weryfikacji tytułu edytowanego wpisu oraz zakończenia zapisu przed dalszym wpisywaniem. Dodatkowy test Core odświeżenia aliasu również przeszedł. Testy współdzielonego schowka wyspy i kalkulatora/schowka launchera przeszły na końcowej wersji.

Końcowy wynik UI po celowanych powtórzeniach: 35/36 scenariuszy zweryfikowanych pozytywnie. Autostart i aktualizacje przeszły po poprawieniu gestów przewijania. Jedyny pozostały błąd to audyt kontrastu nagłówka `Fan speed · last 5 minutes`; niezmieniony main zgłasza ten sam element w tych samych współrzędnych. Nie dodano wyjątku wyciszającego to znalezisko.

Wszystkie 12 etapów wdrożono na jednym branchu w osobnych commitach. Zmiana nie obejmuje integracji Spotify. Przygotowano wspólne granice źródeł, adapterów i prezentacji. Nie wykonano nowego profilu Instruments ani porównania pamięci/czasu pierwszej klatki; podane wyniki wydajności dotyczą wyłącznie syntetycznego silnika rankingu.
