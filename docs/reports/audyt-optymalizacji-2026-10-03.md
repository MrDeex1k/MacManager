# Audyt wydajności i narzędzi - 2026-10-03

Analizowana rewizja: `9249f32`. Zakres: launcher, schowek, metryki i sensory, sieć, scroll, aktualizator, cykl życia aplikacji, UI oraz konfiguracja budowania. To przegląd kodu i wybrane pomiary, nie pełny profil Instruments ani audyt bezpieczeństwa. Kod produkcyjny pozostawiono bez zmian.

**Wniosek:** launcher można zauważalnie usprawnić. Dla obecnego katalogu największy sens mają stabilizacja prezentacji wyników, zachowanie indeksu między otwarciami oraz usunięcie kosztownego filtrowania schowka z MainActor. Sam ranking aplikacji jest już szybki. Niezależnie od launchera należy poprawić pętlę planowania aktualizacji.

## 1. Walidacja i pomiary

- Xcode 27.0, build `27A266a`, Apple Swift 6.4, arm64, macOS 27.0.1.
- `swift test --package-path Packages/MacManagerCore -c release`: **86 testów przeszło**. Test Spotlight bez `MM_LAUNCHER_TEST_ROOT` kończy się bez wykonywania integracji z indeksem systemowym; nie liczę go jako potwierdzenia działania Spotlight.
- `xcodebuild -project MacManager.xcodeproj -scheme MacManager -configuration Release -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build`: **BUILD SUCCEEDED**.
- Ostrzeżenie testów: mutacja przechwyconego `now` w `MetricsHistoryTests.swift:91`. W buildzie aplikacji komunikat o pominiętej ekstrakcji App Intents, ponieważ aplikacja nie używa tego frameworka.
- Pierwsze próby kompilacji zatrzymały ograniczenia sandboxa narzędzi Xcode. Wyniki powyżej pochodzą z udanych uruchomień poza sandboxem, z artefaktami w `/tmp`.
- Nie uruchamiano aplikacji produkcyjnej ani testów UI. Nie zmieniano uprawnień systemowych, ustawień aplikacji ani zawartości schowka użytkownika.

Benchmark skompilowano przez `swiftc -O -swift-version 6` bez modyfikowania plików launchera. Używał jego rzeczywistych klas, katalogu aplikacji odczytanego przez ApplicationProvider i syntetycznych tekstów schowka. Końcowy przebieg wykonano po zakończeniu buildów. Czasy obejmują wywołanie silnika, nie renderowanie okna.

| Operacja | Próby | Mediana | P95 / maksimum |
| --- | ---: | ---: | ---: |
| Ranking rzeczywistego katalogu 188 aplikacji | 180 | 0,460 ms | P95 0,727 ms |
| Ranking 1000 syntetycznych pozycji | 180 | 2,565 ms | P95 6,604 ms |
| Ranking 5000 syntetycznych pozycji | 180 | 12,203 ms | P95 29,338 ms |
| Kalkulator: nazwy aplikacji, arytmetyka, jednostki, daty | 360 | 0,005 ms | P95 0,017 ms; max 0,959 ms |
| Filtrowanie 50 tekstów po około 1 kB | 5 | 0,399 ms | max 0,458 ms |
| Filtrowanie 1000 tekstów po około 10 kB | 5 | 74,733 ms | max 85,742 ms |
| Filtrowanie 50 tekstów tuż poniżej 1 MB | 5 | 374,099 ms | max 425,551 ms |

Ranking: 15 powtórzeń zestawu `s`, `sa`, `saf`, `safa`, `safari`, `ter`, `terminal`, `cod`, `siec`, `zzzzz`, pustego zapytania i spacji. Rozszerzone katalogi powielają nazwy rzeczywistych aplikacji, ale mają unikalne identyfikatory i sufiksy. Nie są odzwierciedleniem typowej instalacji z 5000 aplikacji.

Schowek: wyszukiwanie nieobecnej frazy przez `filter { localizedStandardContains(...) }.prefix(40)`, czyli mechanizm obecnego launchera. Największy tekst miał 999 952 bajty i mieścił się w limicie pojedynczego wpisu. To test obciążeniowy, nie pomiar prywatnej historii użytkownika. Pięć prób nie wystarcza do wiarygodnej statystyki ogona, dlatego dla schowka podano maksimum.

Pierwszy skan aplikacji w końcowym procesie trwał 263,479 ms; mediana ośmiu skanów 9,410 ms. Pierwsze skany w pozostałych procesach miały 113-338 ms. Nie czyszczono cache systemu plików, więc nie są to kontrolowane pomiary zimnego startu. Nie mierzono tu skanowania paneli ustawień ani czasu od skrótu do pierwszej klatki.

## 2. Launcher

### L1. P1 - stabilna lista i geometria podczas pisania

**Dowód:** `LauncherSearch.swift:105` zeruje `results` i `selectedID` przy każdej zmianie tekstu. Następnie publikuje wyniki katalogu, a później listę rozszerzoną. `LauncherView.swift:102` i `:103` reagują osobno na liczbę wyników i tekst. `LauncherController.swift:179` wywołuje animowane `setFrame` bez sprawdzania, czy rozmiar się zmienił.

**Skutek:** kod tworzy sekwencję pustych i wypełnionych wyników, resetuje zaznaczenie oraz może ponawiać animację, również przy niezmienionej docelowej wysokości. SwiftUI może scalić część zmian, więc faktyczną liczbę klatek i animacji trzeba zmierzyć; sam zbędny reset jest potwierdzony.

**Zmiana:** zachować ostatnią wyrenderowaną listę do atomowej publikacji nowej; osobno oznaczać generację zapytania i generację wykonywalnych wyników. Enter i kliknięcie nie mogą uruchamiać pozycji z poprzedniego zapytania. Nie wystarczy usunąć `results = []`, ponieważ obecne zerowanie pełni tę ochronną rolę, a testy jej oczekują. Sprawdzać zmianę docelowej wysokości; podczas pisania stosować stabilną wysokość obszaru wyników albo jedną kontrolowaną aktualizację bez kolejnych animacji. Zachować zaznaczenie, gdy ten sam wynik nadal występuje.

**Walidacja:** szybkie pisanie i Backspace, Enter natychmiast po zmianie tekstu, spóźniony wynik plików, Tab do schowka, Escape, IME. Celem jest brak pustych przejściowych list i uruchamiania starego wyniku.

### L2. P1 - indeks aplikacji niezależny od otwarcia palety

**Dowód:** `LauncherController.swift:104` za każdym razem tworzy providerów i woła `load`. `LauncherSearch.swift:81` zaczyna od `cancel`, a `:133` usuwa katalog również przy zamykaniu. Providerzy są przetwarzani kolejno i katalog jest publikowany dopiero po obu skanach.

**Skutek:** po ponownym otwarciu aplikacje ponownie czekają na I/O; w międzyczasie można otrzymać wyłącznie komendy. ApplicationProvider poprawnie skanuje poza MainActor, ale nie eliminuje to czasu oczekiwania na wyniki.

**Zmiana:** utrzymywać niemający prywatnych treści katalog przez czas życia procesu. Zamknięcie palety anuluje zapytanie i czyści sesję, a nie katalog. Odświeżać indeks po zmianie języka, zmianach katalogów aplikacji oraz okresowo według ograniczonego TTL. Publikować dostępny katalog od razu, a odświeżenie wykonywać w tle. Dwa niezależne źródła mogą ładować się współbieżnie. Ograniczyć duplikowane przejścia po Utilities w `SearchScopes`.

**Osobna optymalizacja:** `LauncherController.swift:117` tworzy nowy NSHostingView, a `:192` usuwa go przy ukryciu. Można zachować host i panel, resetując zawartość/fokus. To hipoteza wymagająca pomiaru pierwszej klatki; zachowany host nie może zatrzymywać prywatnych tekstów po blokadzie sesji.

### L3. P1 - wyszukiwanie schowka poza MainActor

**Dowód:** closure `additionalResults` jest jawnie `@MainActor`; `LauncherController.swift:49` filtruje wszystkie teksty przez `localizedStandardContains`. `.prefix(40)` następuje po zachłannym `filter`. `ClipboardView.swift:14` wykonuje podobne filtrowanie w computed property odczytywanym wielokrotnie przez body.

**Skutek:** przy większych danych samo wyszukiwanie może zajmować 75-425 ms, w obecnym kodzie na executorze UI. Powyższy benchmark mierzy pracę filtra; przypisanie jej do MainActor wynika z kodu.

**Zmiana:** wyszukiwać snapshot historii w osobnym actorze, przerywać pracę pomiędzy wpisami i publikować tylko aktualną generację. Utrzymywać indeks lub przygotowane pola dla aktualnej wersji historii. Zatrzymać zbieranie po 40 trafieniach. Sama zamiana na lazy filter nie rozwiąże przypadku bez trafień. Widok główny powinien korzystać z gotowych wyników i ich licznika.

**Ograniczenia:** cache odszyfrowanych tekstów czyścić przy blokadzie/wyłączeniu zgodnie z ustaloną polityką. Nie zastępować pełnotekstowego wyszukiwania cichym przeszukiwaniem tylko krótkiego podglądu. Nie wprowadzać nieszyfrowanego indeksu FTS na dysku.

### L4. P2 - Spotlight: opóźnienie, anulowanie i stan wyszukiwania

**Dowód:** `LauncherController.swift:60` dodaje 180 ms debounce wyłącznie przed wyszukiwaniem plików. `LauncherFileSearch.swift:51` używa synchronicznego MDQueryExecute wewnątrz actora. Anulowanie jest sprawdzane przed zapytaniem i podczas odczytu wyników, ale nie przerywa trwającego wywołania synchronicznego. Kolejne wyszukiwanie tego actora musi poczekać. `isLoading` modelu reprezentuje ładowanie katalogu, a nie stan wyszukiwania plików.

**Zmiana:** asynchroniczne zapytanie Spotlight z kontrolowanym cyklem życia i anulowaniem, albo wydzielony executor dla blokującego API; nie zakładać, że samo `Task.cancel()` przerywa MDQueryExecute. Debounce zachować tylko dla plików, ewentualnie dostroić do 80-120 ms po pomiarach. Pokazywać osobny stan oczekiwania na pliki. Normalizować roots raz na zapytanie i kończyć po 20 zaakceptowanych pozycjach zamiast przetwarzać do 200, skoro końcowo zachowujemy pierwsze 20. Zachować kontrolę symlinków i granic katalogów także przy otwieraniu pliku.

**Dodatkowe zachowanie:** `(matches + extra).prefix(40)` może całkowicie wyciąć pliki, jeżeli katalog aplikacji wypełni 40 pozycji. Warto jawnie ustalić budżet lub grupowanie źródeł. Obecne 180 ms nie opóźnia samego rankingu aplikacji.

### L5. P2 - cache ikon i izolacja wierszy

**Dowód:** `LauncherView.swift:111` pobiera ikonę przez NSWorkspace w budowaniu widoku. `:108` tworzy NSImage z miniatury schowka; analogicznie `ClipboardView.swift`.

**Zmiana:** ograniczony cache ikon po URL/wersji aplikacji/rozmiarze oraz miniatur po ID wpisu. Osobny widok wiersza ograniczy zakres przeliczania przy zmianie zaznaczenia. API AppKit obsługiwać z właściwą izolacją; nie przenosić NSImage arbitralnie do Task.detached. LazyVStack ogranicza renderowanie, a NSWorkspace może mieć własny cache, więc rzeczywisty zysk należy potwierdzić w Instruments.

### L6. P3 - przygotowanie pól rankingu raz na wersję indeksu

**Dowód:** `LauncherSearch.swift:47` tworzy SearchFields od nowa; `SearchRelevance.swift:53` normalizuje kandydata przy każdym porównaniu. Wszystkie trafienia są sortowane przed obcięciem do 40.

**Zmiana:** IndexedEntry z przygotowanymi aliasami, znormalizowanymi polami i długościami; przebudowa przy zmianie katalogu/personalizacji. Dla bardzo dużych katalogów rozważyć top-k zamiast pełnego sortowania. Przy 188 aplikacjach ranking P95 poniżej 1 ms nie uzasadnia zaczynania od skomplikowanego algorytmu lub rozbudowanej równoległości. Nie dodawać globalnego debounce dla aplikacji.

### L7. P2/P3 - spójność produktu i utrzymywalność

- Alias użytkownika dodawany jest jako `.name(alias)` w `LauncherSearch.swift:48`, mimo istniejącego `.userAlias`. Oznacza to inne reguły rankingu i dopuszczenie fuzzy match. Ustalić zamierzoną semantykę i dopiero wtedy zmienić; nie robić tego ukradkiem przy optymalizacji. Priorytet ulubionych jest obecnie jawnie testowany, więc nie uznaję go za błąd.
- Rejestracja skrótów podczas startu wywołuje `saveCustomization` dla każdej pozycji (`LauncherController.swift:175`). To ponownie zapisuje cały słownik do UserDefaults i uruchamia wyszukiwanie. Oddzielić rejestrację od zapisu/odświeżania; wykonać najwyżej jeden refresh.
- Czyścić lub dezaktywować skróty odinstalowanych aplikacji po potwierdzeniu braku przez LaunchServices; brak w ograniczonym indeksie sam w sobie nie wystarcza.
- Kalkulator uruchamia się na MainActor, ale w zmierzonym zestawie jest tani. Przeniesienie go do actora może uprościć jednolity pipeline, lecz nie jest główną optymalizacją.
- Format czasu jest sztywny: `CalcTimeZone.swift:455` i `CalcDateTime.swift:788` używają `h:mm a`. Uwzględnić preferencję 12/24 h i jej wpływ na cache formatowania.

## 3. Pozostałe moduły

### A1. P1 - potwierdzona pętla aktualizatora bez oczekiwania

**Dowód:** `UpdateController.swift:81` oblicza termin następnej próby. Jeśli termin minął, po Task.yield wywołuje `service.check` i ponownie planuje sprawdzenie. `UpdateService.swift:110` natychmiast zwraca false, gdy request już trwa. `lastAttempt` zmienia się dopiero po zakończeniu żądania, więc termin pozostaje w przeszłości.

**Wyzwalacz:** ponowne planowanie podczas trwającego sprawdzenia, np. callback ścieżki sieciowej, zdarzenie zegara lub zmiana automatycznych aktualizacji. Anulowanie taska planującego nie anuluje automatycznie osobnego taska fetch.

**Reprodukcja:** użyto rzeczywistego UpdateService z wstrzykniętym, jednosekundowym fetch zwracającym syntetyczny wynik, bez HTTP. Tymczasowa kopia UpdateController różniła się licznikiem wywołań scheduleNextCheck i metodą uruchamiającą to planowanie w stanie running bez rejestrowania monitorów systemowych. Po rozpoczęciu fetch uruchomiono ponowne planowanie. W 200 ms naliczono **19 617 przeplanowań**. To odtworzenie błędu planisty, nie pomiar CPU działającej aplikacji.

**Zmiana:** jeden właściciel zadania i jawny stan in-flight; w czasie żądania nie tworzyć nowego natychmiastowego harmonogramu. Następną próbę ustalać po zakończeniu aktywnego requestu. Kontrolować anulowanie/generację również po await i w ścieżce zerowego delay. Dodać test: pending fetch + reschedule nie zwiększa liczby sprawdzeń aż do zakończenia fetch. Obsłużyć stop/sleep bez pozostawionych zadań.

### A2. P1/P2 - przyrostowe odświeżanie schowka i ograniczenie pamięci

**Dowód:** `ClipboardRepository.swift:39` po każdym load przegląda metadane, usuwa osierocone pliki, odczytuje i odszyfrowuje wszystkie preview. Preview tekstowe zawiera cały tekst, do 1 MB. `ClipboardService` robi refresh po zapisie/usunięciu i bezwarunkowo po maintain. `ClipboardController.swift:67` wywołuje maintenance co minutę również bez zmian danych.

**Skutek:** powtarzalne I/O, kryptografia, dekodowanie JSON i alokacje całej historii. To odbywa się poza MainActor, ale zwiększa koszt tła i rozmiar publikowanego snapshotu. Ustawienia dopuszczają 1000 wpisów i 2 GB magazynu; nie należy traktować każdego preview jako małego obiektu.

**Zmiana:** zwracać delty insert/delete/prune, zachować ograniczony cache już odszyfrowanych podglądów, pomijać refresh przy maintenance bez zmian. Pełną treść dla szczegółów/restore ładować na żądanie; pełnotekstowe wyszukiwanie obsłużyć osobno z jawnym budżetem pamięci. Sprzątanie osieroconych plików przenieść do otwarcia/naprawy lub rzadszego maintenance. Używać `EXISTS`, `LIMIT 1`, wyszukiwania po ID i indeksu `(captured DESC, id ASC)` zamiast kolejnych odczytów całej tabeli. Te zmiany mają pierwszeństwo przed tuningiem pragm SQLite; nie obniżać trwałości zapisu tylko dla benchmarku.

### A3. P2 - ograniczenie powtarzanych odczytów sprzętowych

**Dowód:** `mm_power_read` otwiera/zamyka SMC, a `HardwareSensorSampler.sample` robi to ponownie w tym samym cyklu. `mm_smc_read_number` odczytuje metadane klucza przed każdym odczytem wartości. `mm_gpu_read` ponownie wyszukuje AGXAccelerator. Rozmiar pamięci fizycznej odczytywany jest ponownie przez sysctl w każdej próbce.

**Zmiana:** wspólna sesja dla PSTR i sensorów, cache metadanych kluczy i stałych parametrów, ewentualnie utrzymywanie uchwytu sterownika. Po błędzie/wake unieważniać zasoby i odkrywać je ponownie; ABI jest nieudokumentowane, więc walidacje długości/typu muszą zostać. Najpierw zmierzyć czas CPU i collectionMilliseconds osobno dla CPU/GPU/SMC, potem ocenić, czy wystarczy jedna sesja na próbkę, czy potrzebna jest dłuższa.

Historyczny raport `etap-2-koszt-tla.md` z 22 września wskazuje 2,338% jednego rdzenia z przyrostu czasu CPU. To potwierdza potrzebę pomiaru, ale nie identyfikuje winnego i nie jest dzisiejszym wynikiem. Nie przypisuję całego kosztu czujnikom.

### A4. P2 - praca w tle dopasowana do stanu usług

**Dowód:** schowek budzi się co 500 ms także przy wyłączonym zapisie; scroll co sekundę sprawdza uprawnienia także w stanie off; metryki i sieć mają osobne pętle sekundowe. Czytnik sieci co pięć sekund odtwarza obiekty SystemConfiguration i listę usług.

**Zmiana:** osobne harmonogramy aktywnego przechwytywania i retencji, rzadsze sprawdzanie uprawnień wyłączonej funkcji, wybudzanie aktualizatora/sieci według terminów i zdarzeń. Dla lokalnych adresów rozważyć SCDynamicStore notifications oraz okresowy fallback zamiast samego pełnego odczytu co 5 s. Użyć tolerancji/coalescing tam, gdzie nie jest potrzebna natychmiastowa reakcja. Nie wyłączać historii metryk automatycznie po ukryciu okna, jeśli ma pozostać ciągła; jest to decyzja produktowa.

### A5. P2/P3 - pasek menu i wykresy

`MenuBarLabelView.swift:29` tworzy ImageRenderer i obraz dla każdego przeliczenia statusImage, nawet jeśli tekst po zaokrągleniu jest taki sam. Cache według wyświetlanych segmentów, języka, skali i istotnego wyglądu ograniczy tę pracę. `segments` jest też liczone wielokrotnie.

`MetricsService.checkFreshness` co sekundę przesuwa referenceTime historii, więc widoczne wykresy przeliczają punkty i serie także pomiędzy próbkami. Można przygotowywać serie raz na wersję danych i oddzielić przesunięcie osi od obliczania wartości. Limit historii wynosi 300 sekund, dlatego nie zaczynałbym od przepisywania jej na specjalistyczną strukturę. AppShellView już usuwa zawartość głównego okna po jego ukryciu - tę korzystną właściwość zachować.

### A6. P2 - diagnostyka i testy wydajności

Brak signpostów i budżetów regresji dla launchera. Dodać pomiary: skrót -> pierwsza klatka, zmiana tekstu -> publikacja aktualnych wyników -> klatka, katalog, Spotlight, filtrowanie schowka. Raportować czasy i liczby rekordów bez zapytań i prywatnych tekstów.

Osobne testy powinny obejmować duży schowek, szybkie anulowanie, zamknięcie podczas wyszukiwania, ponowne otwarcie bez skanu i odtwarzanie planisty aktualizacji. Obecne 86 testów to przede wszystkim poprawność funkcjonalna. Ostrzeżenie zegara w teście zastąpić zegarem testowym z jawną izolacją zamiast mutowanej lokalnej zmiennej.

## 4. Narzędzia, pakiety i aktualizacje

Stan źródeł internetowych sprawdzono 3 października 2026.

| Obszar | Stan i rekomendacja |
| --- | --- |
| Xcode | Lokalny 27.0 (`27A266a`) odpowiada stabilnemu wydaniu Apple z 14 września. Nowsze 27.1 i 27.2 beta 2 są wersjami testowymi. Brak powodu do przejścia na betę w celu naprawienia obecnych lagów. [Apple releases](https://developer.apple.com/news/releases/), [wymagania Xcode](https://developer.apple.com/xcode/system-requirements). |
| Swift | Kompilator to już 6.4. `SWIFT_VERSION = 6.0` oznacza tryb języka Swift 6, a `swift-tools-version: 6.0` minimum manifestu; nie oznacza starego kompilatora. Nie zmieniać SWIFT_VERSION na 6.4. Podniesienie wersji manifestu ma sens dopiero przy potrzebie nowszych API PackageDescription lub świadomym podniesieniu minimum toolchainu. [Swift 6.4](https://www.swift.org/blog/swift-6.4-released/), [tabela Apple](https://developer.apple.com/xcode/system-requirements). |
| Zależności | Brak zdalnych zależności SwiftPM, CocoaPods/Carthage/npm w aplikacji. Core i prototyp używają lokalnych targetów/pakietu. SQLite, AppKit, SwiftUI, Charts, CryptoKit i IOKit są dostarczane przez system/SDK; nie mają osobnego upgrade pakietu w tym repo. |
| macOS | Deployment target 26.0 pozostawić, jeśli nadal chcemy wspierać macOS 26. Nowy SDK nie wymaga podnoszenia minimum. Sprawdzać UI/uprawnienia na 26 i 27. Lokalny system to już 27.0.1. |
| GitHub REST API | Kod używa `2026-03-10`. Jest to wspierana wersja; brak potrzebnej zmiany nagłówka. [GitHub API versions](https://docs.github.com/en/rest/about-the-rest-api/api-versions). |
| Formatter | Dodać projektową konfigurację swift-format i kontrolę w CI. Narzędzie jest już w toolchainach Swift 6+, więc nie trzeba dodawać zależności. Wprowadzać formatowanie osobno od optymalizacji. [swift-format](https://github.com/swiftlang/swift-format). |
| CI | Brak `.github/workflows`. Dodać build aplikacji, Core tests, test hooków i lint. Wybrać jawnie Xcode oraz architekturę runnera; testy Keychain/SMC i UI oddzielić od testów deterministycznych. Sam `xcodebuild test` obecnego schematu obejmuje target UI; testy Core wymagają oddzielnego uruchomienia SwiftPM. |
| Reprodukowalność | Zapisać przetestowaną wersję Xcode w konfiguracji projektu/CI i dokumentacji. Minimum Xcode 26 w README odróżnić od aktualnie zalecanej wersji 27.0. Release script ma domyślny build number 8 - jawny, rosnący numer wydania zmniejszy ryzyko powtarzania go. |

**Kod adaptowany wymaga selektywnej synchronizacji, nie aktualizacji przez menedżer pakietów.** Tinycast, Stats i Scroll Reverser są źródłami wybranych fragmentów. Obecne wydania upstream to [Tinycast 0.11.12](https://github.com/abue-ammar/tinycast/releases), [Stats 3.0.19](https://github.com/exelban/stats/releases/tag/v3.0.19) i [Scroll Reverser 1.9](https://github.com/pilotmoon/Scroll-Reverser/releases/tag/v1.9); numer wydania sam nie dowodzi, że adaptowany fragment wymaga zmiany.

Dla Tinycast raport z 1 października już identyfikuje format 12/24 h, zwalnianie nieaktualnych skrótów i ulepszenia granic słów. W lokalnym kodzie sztywny format czasu i brak czyszczenia skrótów pozostają. [Upstream: usuwanie skrótu skasowanej aplikacji](https://github.com/abue-ammar/tinycast/commit/34664f7bde719c8f458dd8e996c91422db1be632). Nie wykonano tu pełnego diffu wszystkich nowszych commitów tych trzech projektów.

`CountryZoneData.generated.swift` i `CurrencyData.generated.swift` wskazują skrypty generatorów nieobecne w repo. Dodać odtwarzalny generator, przypięte wersje danych i datę regeneracji przed ich przyszłą aktualizacją. Nie podmieniać ręcznie całych tabel ani nie dodawać pobierania kursów do lokalnego kalkulatora przy okazji porządkowania zależności.

## 5. Zalecana kolejność wdrożenia

1. **Planista aktualizacji i schowek poza MainActor.** Dwa przypadki mają potwierdzony potencjał długiego zajmowania executora UI.
2. **Stabilna prezentacja launchera, kontrola generacji i brak zbędnych resize.** Najbardziej bezpośredni wpływ na pisanie i nawigację.
3. **Trwały w RAM katalog aplikacji i cache ikon.** Szybsze kolejne otwarcia i mniej pracy podczas renderowania.
4. **Przyrostowy schowek i anulowalne wyszukiwanie plików.** Lepsze zachowanie przy większych danych.
5. **Profilowanie tła, SMC, pasek menu, harmonogramy.** Zmiany dobierać do zmierzonych udziałów w CPU.
6. **CI, formatter, przypięty toolchain i selektywne aktualizacje upstream.** Ranking top-k dopiero jeśli pomiary większych katalogów tego wymagają.

Proponowane kryteria, a nie osiągnięte wyniki: publikacja lokalnych wyników P95 < 16 ms; ciepłe otwarcie do pierwszej klatki P95 < 50 ms; brak pracy filtra schowka > 8 ms na MainActor; brak przeplanowań aktualizatora podczas pending fetch; brak zbędnego skanu przy drugim otwarciu. Spotlight mierzyć osobno, ponieważ zależy od indeksu i wybranych katalogów. Zweryfikować te cele w Release przez Instruments i testy UI na maszynie referencyjnej.
