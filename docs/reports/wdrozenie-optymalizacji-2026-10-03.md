# Wdrożenie optymalizacji - 2026-10-03

Implementacja po [audycie](audyt-optymalizacji-2026-10-03.md). Bez zmian narzędzi, zależności, minimalnej wersji systemu oraz CI/CD.

## Launcher

- Katalog aplikacji pozostaje w pamięci między otwarciami. Odświeżenie po 60 s i zmianie języka odbywa się w tle, a niezależni providerzy pracują współbieżnie. Dostępny katalog jest od razu przeszukiwany.
- Silnik przygotowuje znormalizowane pola raz na zmianę katalogu lub personalizacji. Zachowano dotychczasowe reguły aliasów i ulubionych.
- Pisanie nie zeruje listy. Do czasu publikacji aktualnych wyników poprzednie wiersze pozostają widoczne, ale nie można ich uruchomić. Kontrola obejmuje także zmieniony wynik kalkulatora o tym samym ID.
- Obszar wyników ma stabilną wysokość, bez animowanych zmian przy każdej literze. Panel i host SwiftUI są używane ponownie. Zamknięcie trybu schowka usuwa prywatną zawartość widoku.
- Wyszukiwanie tekstów schowka odbywa się w osobnym actorze, z kontrolą anulowania między wpisami i kończy zbieranie po 40 trafieniach. Nadal przeszukuje pełny tekst.
- Spotlight działa asynchronicznie, można zatrzymać trwające zapytanie. Debounce wynosi 120 ms tylko dla plików, limit czasu 5 s, limit wyników 20. Normalizacja roots odbywa się raz, kontrola symlinków i granic katalogów pozostaje. Pliki mają miejsce w łącznym budżecie 40 wyników.
- Ograniczone cache ikon aplikacji i miniatur. Ikony są odświeżane po TTL, miniatury czyszczone po zamknięciu/zmianie historii.
- Rejestracja skrótów przy starcie nie zapisuje ponownie całej personalizacji. Sprawdzanie zapisanych ścieżek i LaunchServices usuwa skróty skasowanych aplikacji, a przeniesionym aktualizuje ścieżkę i powiązanie. Aliasy i ulubione pozostają. Pomijane są niezamontowane woluminy.
- Kalkulator respektuje preferencję cyklu 12/24h niezależnie od języka aplikacji. Cache formatterów uwzględnia cykl godzinowy.

## Pozostała aplikacja

- Updater nie planuje kolejnej natychmiastowej próby podczas aktywnego pobierania. Stop/sleep anuluje request, a generacja chroni przed późnym wynikiem.
- Zapis, usuwanie i retencja schowka aktualizują historię przyrostowo. Maintenance bez zmian nie odszyfrowuje i nie publikuje ponownie historii. Jawne odświeżenie wykorzystuje aktualne podglądy w pamięci.
- SQLite otrzymał indeks porządku historii, odczyty po ID i LIMIT 1. Zachowano trwałość zapisu i szyfrowanie.
- Główny widok schowka także filtruje poza MainActor i korzysta z cache miniatur. Zablokowanie sesji usuwa lokalne wyniki i miniatury.
- Schowek odpytuje pasteboard tylko podczas aktywnego zapisu; retencja ma osobny harmonogram. Wyłączony scroll rzadziej sprawdza uprawnienia, timery otrzymały tolerancje. Sieć nie tworzy zadań HTTP przed terminem odświeżenia i ponownie używa obiektów SystemConfiguration.
- Moc PSTR i sensory korzystają z jednej sesji SMC na próbkę zamiast dwóch.
- Pasek menu ponownie używa obrazu, gdy wyświetlane segmenty się nie zmieniły. Serie wykresów są przeliczane po zmianie danych, zamiast przy każdym przesunięciu osi czasu.
- Signposty `launcher/Search`, `launcher/Rank` i `clipboard-search/Filter` umożliwiają dalsze profilowanie bez zapisu zapytań ani treści schowka.

## Walidacja

- **98 testów Core w Release: PASS**, z ustawionym `MM_LAUNCHER_TEST_ROOT` na repozytorium. Integracja Spotlight faktycznie wyszukała README, sprawdziła ograniczenie katalogów i filtr obrazów. Poprzedni przebieg Debug: 97 testów PASS; ostatni dodany test uzgadniania katalogu wykonano w Release.
- **Build aplikacji Release: PASS**. Usunięto nowe ostrzeżenia Swift. Pozostaje komunikat narzędzia Xcode o pomijaniu ekstrakcji App Intents, których aplikacja nie używa.
- Testy obejmują m.in. brak wykonania nieaktualnych wyników, zamknięcie/przełączenie prywatnego trybu, ponowne otwarcie bez skanu, unieważnienie indeksu, przeniesione/usunięte aplikacje, format 12/24h, delty schowka, brak ponownego odszyfrowywania przy maintenance i anulowanie updatera.
- XCTest UI nie rozpoczął scenariuszy: system zgłosił `Timed out while enabling automation mode`. Wykonano zastępczy test interfejsu przez Computer Use na buildzie Debug z `--ui-testing --reset-preferences --clipboard-fixture`, z izolowanymi preferencjami, danymi i pasteboardem.
- Test interfejsu: wyszukanie `netw` i `siec`, Escape, Enter i nawigacja do sieci, kalkulator `2+3*4 = 14`, ponowne otwarcie i fokus, Tab do schowka, wyszukanie testowego tekstu, brak jego wyników w trybie aplikacji, zamknięcie w trybie schowka i ponowne otwarcie, filtrowanie oraz przywrócenie wpisu w głównym widoku schowka. Wszystkie te scenariusze przeszły.
- `git diff --check`: PASS.

## Pomiary porównawcze

Ten sam zestaw zapytań i sposób pomiaru `swiftc -O` co w audycie, 180 prób na katalog. To czas silnika, nie czas do pierwszej klatki interfejsu.

| Ranking | Mediana przed | Mediana po | P95 przed | P95 po |
| --- | ---: | ---: | ---: | ---: |
| 188 aplikacji | 0,460 ms | 0,327 ms | 0,727 ms | 0,685 ms |
| 1000 pozycji syntetycznych | 2,565 ms | 1,712 ms | 6,604 ms | 6,597 ms |
| 5000 pozycji syntetycznych | 12,203 ms | 8,919 ms | 29,338 ms | 30,536 ms |

Mediana dla rzeczywistego katalogu spadła o około 29%. Wyniki nie potwierdzają poprawy ogona dla dużego katalogu; pełne sortowanie nadal jest wykonywane. Nie traktować pojedynczej serii jako gwarancji wydajności.

Powtórzenie reprodukcji planisty updatera, z fetch opóźnionym o sekundę i licznikiem w kopii kontrolera: **19 617 -> 1 wywołanie planowania w 200 ms** podczas aktywnego requestu. Jedno wywołanie to ręczne uruchomienie reprodukcji, bez kolejnych przeplanowań.

Filtr pełnych tekstów nadal może być kosztowny. Poprawa polega przede wszystkim na przeniesieniu tej pracy poza executor UI i anulowaniu nieaktualnych zapytań, a nie skróceniu samego `localizedStandardContains` dla przypadku bez trafień.

## Granice wdrożenia

Nie wykonano pełnego profilu Instruments ani pomiaru opóźnienia do pierwszej klatki. Nie ogłaszamy osiągnięcia proponowanych w audycie celów P95 dla całego interfejsu. Testowano na macOS 27.0.1; macOS 26 wymaga osobnej weryfikacji.

Pełne teksty istniejącej historii nadal są w pamięci usługi. Ograniczenie ich pamięci przez odczyt na żądanie i osobny budżet wyszukiwania wymaga osobnej zmiany modelu danych. Nie dodano kolejnego trwałego cache prywatnych treści. Sprzątanie osieroconych plików pozostaje przy jawnym load, który już nie następuje po każdej mutacji i maintenance.

Stałe uchwyty SMC/GPU, cache metadanych ABI, powiadomienia SCDynamicStore zamiast okresowego odczytu, top-k i wydzielanie wierszy SwiftUI pozostają kandydatami do profilowania. Zachowano zakresy skanowania Utilities: ich usunięcie zmniejszałoby także głębokość wyszukiwania, pomijając część aplikacji.
