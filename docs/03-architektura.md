# Architektura techniczna

## Kierunek

Decyzja inżynierska: jedna aplikacja macOS, modułowa wewnętrznie, bez backendu i bez uprzywilejowanego procesu pomocniczego. Xcode project dla aplikacji i testów UI; logika domenowa w lokalnym pakiecie Swift Package Manager. Swift 6 z kontrolą współbieżności, SDK pozwalające budować dla macOS 26. Nie dobieramy numerów wersji zależności przed utworzeniem projektu.

SwiftUI odpowiada za widoki, Observation za stan prezentacji, Swift Charts za wykresy. AppKit obsługuje cykl życia, Dock, status item i panel wyspy. Aplikacja jest dystrybuowana poza App Store, bez App Sandbox, z Hardened Runtime i minimalnym zestawem faktycznie wymaganych entitlements. Brak sandboxa nie zwalnia z systemowych zgód.

Nie dodawać Sparkle, chmurowej bazy, SDK telemetrii ani Spotify Web API do początkowej architektury. Publiczne API mają pierwszeństwo; niestabilne odczyty sprzętu pozostają za adapterami.

## Moduły

| Moduł | Odpowiedzialność |
| --- | --- |
| AppShell | Cykl życia, okna, menu bar, Dock, wstrzykiwanie usług. |
| SettingsStore | Typowane ustawienia, migracje wersji, domyślne wartości. |
| MetricsService | Wspólny harmonogram CPU/GPU/RAM/W, historia 300 s, stany odczytów. |
| HardwareAdapters | Mach, IOKit, SMC/IOReport jeśli walidacja potwierdzi potrzebę. |
| NetworkService | Lokalny IPv4, stan sieci, publiczny IPv4 i zweryfikowane wyjścia VPN. |
| ScrollService | Event tap, rozpoznawanie źródła, odwracanie i reakcja na odebranie zgody. |
| PermissionService | Stan Dostępności, schowka, Automatyzacji i autostartu; bez zbiorczego wymuszania zgód. |
| LoginItemService | Integracja z SMAppService.mainApp. |
| ReleaseService | Tygodniowy harmonogram, GitHub Releases, wersje, link do wydania. |
| SensorService | Faza 2: temperatura i wentylatory, wspólne adaptery sprzętu. |
| IslandCoordinator | Faza 3: ekran, geometria, hover, fokus, skrót, pełny ekran. |
| ClipboardService / Repository | Faza 3: obserwacja, filtrowanie, zapis, retencja i przywracanie. |
| MusicService / PlayerAdapters | Faza 3: osobne adaptery Apple Music i Spotify. |
| Diagnostics | Lokalne, zredagowane błędy techniczne i świadomy eksport. |

~~~mermaid
flowchart TD
    SwiftUI["Okno / pasek menu / wyspa"] --> Presentation["Stan prezentacji: MainActor"]
    Presentation --> Services["Usługi domenowe"]
    Services --> Metrics["MetricsService + SensorService"]
    Metrics --> Adapters["Adaptery Mach / IOKit / SMC / IOReport"]
    Metrics --> History["Bufor historii 300 s w RAM"]
    Services --> Clipboard["ClipboardService"]
    Clipboard --> Storage["Lokalny zapis szyfrowany"]
    Services --> Music["Adaptery lokalnych odtwarzaczy"]
    Services --> Network["IPv4 / GitHub Releases"]
    Network --> HTTPS["Jawnie określone usługi HTTPS"]
~~~

## Przepływ i współbieżność

Każda usługa publikuje niewielki, niemutowalny snapshot. MainActor przetwarza tylko stan widoków i wymagające go operacje AppKit. Dekodowanie obrazów, odczyty sprzętu, zapisy i sieć nie blokują UI.

Usługi ze zmiennym stanem używają actorów albo wyraźnej serializacji. Wywołania C, które mogą blokować, trafiają na ograniczoną kolejkę roboczą; samo opakowanie ich w Task nie rozwiązuje blokowania. Nie wykonywać równoległych odczytów jednego niethread-safe adaptera.

Event tap ma minimalną ścieżkę: rozpoznaj, ewentualnie zmień delty, zwróć zdarzenie. Bez await, logowania każdego zdarzenia, alokowania obrazu, zapisu plików i HTTP. Obsłużyć wyłączenie tapu po timeoutach oraz przejście do bezpiecznego przepuszczania zdarzeń.

Jeden harmonogram metryk współdzielony przez wszystkie widoki, bez nakładających się pomiarów. UI nie musi renderować, gdy jest niewidoczne, ale gromadzenie pięciominutowej historii trwa podczas pracy komputera. W uśpieniu próbkowanie ustaje. Zablokowanie sesji ukrywa dane schowka i wstrzymuje jego obserwację.

## Kontrakty danych

| Typ | Pola i zasady |
| --- | --- |
| MetricSample | ID metryki, timestamp, wartość opcjonalna, jednostka, źródło, zakres pomiaru, jakość/status. |
| MetricStatus | loading, available, unavailable, permissionDenied, stale, failed. |
| MetricSeries | Punkty z ostatnich 300 s; odcinanie po czasie, nie wyłącznie po liczbie wpisów. |
| SensorDescriptor | ID, model/platforma, grupa CPU/GPU/fan, jednostka, reguła walidacji i opis semantyki. |
| NetworkSnapshot | Podstawowy lokalny IPv4, publiczne obserwacje, interfejs/trasa jeśli potwierdzone, czas i stan. |
| PublicIPObservation | IPv4, endpoint, zaobserwowana ścieżka, zakres dowodu, czas sprawdzenia. |
| PlayerSnapshot | Źródło, utwór opcjonalny, wykonawca, długość, pozycja, stan, dostępne akcje, okładka opcjonalna. |
| ReleaseInfo | Wersja, tag, adres strony wydania, zgodny asset DMG, czas kontroli. |

Model metryki musi rozróżniać poprawne zero od braku wartości. Przy pierwszym odczycie licznika różnicowego zbieramy bazę; nie publikujemy fikcyjnego zera. Czas monotoniczny służy do różnic liczników; czas kalendarzowy do dat w UI i retencji. Po uśpieniu resetujemy bazę tam, gdzie liczniki nie zapewniają poprawnej różnicy.

Seria przy interwale 1 s zawiera około 300 punktów na metrykę. Zmiana interwału nie wydłuża okna ponad 5 minut. Współdzielona historia jest niezależna od tego, czy wskaźnik w pasku menu jest włączony.

## Sieć

Lokalne adresy pobieramy z interfejsów systemowych; podstawowy oznacza adres fizycznego połączenia LAN wybranego na podstawie aktywnej konfiguracji sieci, a nie automatycznie adres tunelu. Przy kilku połączeniach regułę wyboru testujemy i opisujemy. Adres loopback nie spełnia wymagania lokalnego IP. Sam stan NWPathMonitor nie wyznacza publicznego IPv4.

Decyzja inżynierska: dostawca bazowy [ipify IPv4](https://www.ipify.org/), endpoint HTTPS api.ipify.org z odpowiedzią JSON. Brak automatycznego przełączania na nieujawnionych dostawców. Publiczne IP można wyłączyć.

Odświeżenie przy starcie/wznowieniu usługi, zmianie sieci po 2 s stabilizacji, ręcznie i nie częściej niż co 15 minut okresowo. Limit zbiorczy: co najmniej 30 s między automatycznymi próbami przy serii zmian; offline bez pętli retry. Limit czasu żądania 5 s, mała ograniczona odpowiedź i walidacja IPv4; brak cookies, identyfikatora instalacji i lokalnych adresów w żądaniu.

VPN: brak skanowania internetowych celów ani uruchamiania innych aplikacji w celu wykrywania ich tras. Przypisanie żądania do interfejsu to tylko kandydat do prototypu. Wynik wolno opisać nazwą tunelu dopiero po potwierdzeniu ścieżki. Sam obecny utun, odpowiedź serwera ani adres bramy nie dowodzą osobnego publicznego IP. Jeśli adapter nie potrafi tego wykazać, zwraca unknown.

## Zaimplementowany szkielet — krok 2

MacManager.xcodeproj zawiera target aplikacji i testy UI oraz współdzielony scheme MacManager. Lokalne Packages/MacManagerCore dostarcza AppLanguage i PreferencesStore (Observation, MainActor, wstrzykiwany UserDefaults). AppState utrzymuje nawigację i jedną instancję ustawień; AppStrings wybiera PL/EN z kompilowanego String Catalog, dzięki czemu zmiana treści jest natychmiastowa. SwiftUI Locale odpowiada za formatowanie. Systemowe menu i okna macOS zachowują język systemu.

App/ zawiera scenę pojedynczego okna, nawigację, komendy i motyw. Features/ zawiera Przegląd, Sieć i Ustawienia. Widoki nie uruchamiają prototypów CLI ani usług pomiarowych. Brak danych jest jawny, fizyczna pojemność RAM pochodzi z ProcessInfo. Jedynym zapisywanym ustawieniem jest obecnie język. W Debug flagi --ui-testing i --reset-preferences izolują ustawienia testów od profilu użytkownika; w Release nie są obsługiwane.

Konfiguracja: arm64, minimalny macOS 26.0, Swift 6, bez zależności zewnętrznych i generatora projektu. Identyfikator rozwojowy: dev.macmanager.MacManager. Podpis lokalny ad-hoc, bez skonfigurowanego Developer ID. ENABLE_HARDENED_RUNTIME jest włączone w projekcie, lecz Xcode wyłącza Hardened Runtime przy ad-hoc signing; weryfikacja podpisanego wydania pozostaje osobną bramką.

## Docelowa struktura kodu

~~~text
MacManager/
  App/
  Features/
    Overview/ Network/ Settings/ MenuBar/
    Sensors/ Island/ Clipboard/ Music/
  Platform/
    Hardware/ Scroll/ Permissions/ LoginItems/
  Resources/
    Localizable.xcstrings
Packages/
  MacManagerCore/
    Sources/
    Tests/
MacManagerTests/
MacManagerUITests/
docs/
~~~

Istnieją App/, Features/Overview, Network, Settings, Resources, lokalny Core i MacManagerUITests. Pozostałe katalogi i funkcje dodajemy w przypisanych krokach i fazach. Test doubles dla zegara, adapterów, pasteboardu, repozytorium i HTTP umożliwiają sprawdzenie awarii bez prawdziwych danych użytkownika.

