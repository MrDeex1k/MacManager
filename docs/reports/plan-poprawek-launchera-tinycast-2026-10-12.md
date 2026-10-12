# Plan adaptacji czterech poprawek TinyCast

Data: 2026-10-12. Status: wdrożenie w toku. Baza: `main` po scaleniu PR #8, commit `9e2d24c`.

Branch: `fix/launcher-upstream-improvements`.

## Zakres i źródła

| Zmiana | Przypięty commit TinyCast | Kod źródłowy | Kod Mac Managera |
| --- | --- | --- | --- |
| Bity i bajty w szybkości transferu | [f990908895](https://github.com/abue-ammar/tinycast/commit/f99090889513c65ffba9477ef30abde61029a276) | CalcUnitCatalog.swift, CalcUnits.swift, testy kalkulatora | Packages/MacManagerCore/Sources/MacManagerCore/Launcher/Calculator/CalcUnitCatalog.swift i CalcUnits.swift |
| Najnowsza kopia aplikacji | [4207ab1191](https://github.com/abue-ammar/tinycast/commit/4207ab11914470e79538fbffc6935f63b0bb3ad1) | SearchScopes.swift, testy scopes | SearchScopes.swift, ApplicationProvider.swift, LauncherSearch.swift i LauncherController.swift |
| Foldery będące symlinkami | [5ec0f9de11](https://github.com/abue-ammar/tinycast/commit/5ec0f9de11196183ea92f35c550c43395e2b2245) | SearchScopes.swift, testy scopes | SearchScopes.swift i ApplicationProvider.swift |
| Fokus po zamknięciu menu | [62abccdfc6](https://github.com/abue-ammar/tinycast/commit/62abccdfc6cc06df7fc027099a4defe551386a88) | RootPaletteView.closeMenus | LauncherView.swift, LauncherCustomizationView.swift, LauncherController.swift i LauncherPanel |

Przenosimy wybrane mechanizmy, z zachowaniem własnego cyklu życia, PL/EN, anulowania zadań, cache katalogu i ograniczeń skanowania. Nie robimy cherry-picków całych commitów aplikacji TinyCast. Są one związane z innym modelem wyników, paletą i infrastrukturą testów.

## 1. Przygotowanie po scaleniu PR #8

1. Sprawdzić czyste drzewo, potwierdzić scalenie i pobrać `main` przez fast-forward.
2. Utworzyć `fix/launcher-upstream-improvements`. Przenieść do niego ten plan jako dokument roboczy.
3. Ponownie sprawdzić cztery zmieniane obszary: poprawki review PR #8 mogą zmienić stan względem `9dd3c04`.
4. Korzystać z powyższych przypiętych rewizji upstream. Późniejsze zmiany `main` TinyCast wymagają osobnej analizy.

## 2. Rozróżnienie bitów i bajtów

### Analiza

Katalog zna `Mbps` oraz `MB/s`, ale nie ma jawnych wpisów `Bps`, `kBps`, `MBps`, `GBps`, `TBps`. W efekcie fallback do małych liter traktuje `MBps` jak `Mbps`.

Próba obecnego silnika, bez zmian w repozytorium, potwierdziła:

- `500 Mbps in MBps` daje `500 Mbps`, zamiast `62.5 MBps`.
- `8 bps to Bps` daje `8 bps`, zamiast `1 Bps`.

Upstream dodaje jawne wpisy jednostek i automatyczne odpowiedniki. Nasz indeks już wspiera rozróżnianie wielkości liter, więc nie potrzeba przebudowy parsera.

### Adaptacja

- Dodać `Bps`, `kBps`/`KBps`, `MBps`, `GBps`, `TBps` z czynnikami w bajtach na sekundę: 1, 1000, 1000000, 1000000000 i 1000000000000.
- Zachować kolejność rozpoznania: dokładny alias przed fallbackiem do małych liter. Małe `b` oznacza bity, wielkie `B` bajty.
- Dodać odpowiedniki do `autoTargets`, zgodnie z upstream.
- Zachować istniejące aliasy z `/s`, przedrostki SI i binarne oraz angielską składnię kalkulatora. Nie zmieniać lokalizacji liczb ani sposobu kopiowania wyniku.
- Nie dodawać nowych ustawień ani usług sieciowych.

### Odbiór

Testy wartości i kopiowanego wyniku przez rzeczywisty adapter LocalCalculator, a także kilka przypadków parsera:

| Zapytanie | Oczekiwany wynik liczbowy |
| --- | --- |
| `500 Mbps in MBps` | 62.5 MBps |
| `62.5 MBps to Mbps` | 500 Mbps |
| `8 bps to Bps` | 1 Bps |
| `1 MBps to MB/s` | 1 MB/s |
| `1 MiB/s to MBps` | 1.048576 MBps |
| `500 Mbps + 62.5 MBps` | 125 MBps |

Uzupełnić regresje dla kB/KB, G/T oraz dotychczasowych konwersji. Zweryfikować wyświetlanie PL/EN według aktualnej polityki formatowania; wartości w tabeli są zapisem kanonicznym.

## 3. Wybór najnowszej kopii aplikacji

### Analiza

ApplicationProvider deduplikuje po bundle ID i zatrzymuje pierwszą poprawną aplikację. SearchScopes sortuje obecnie ścieżki alfabetycznie. Przy kilku wersjach w jednym folderze o wyniku może zdecydować nazwa pakietu.

Upstream porządkuje elementy katalogu według CFBundleShortVersionString z porównaniem liczbowym; przy remisie używa nazwy bez `.app`. Kolejność skonfigurowanych zakresów nadal ma pierwszeństwo.

### Reguła docelowa

- Przy kopiach w tym samym katalogu wygrywa najwyższa wersja liczbowo, np. 27.0 przed 9.4.
- Nadal obowiązuje pierwszeństwo zakresów: aplikacja w wcześniejszym scope nie jest zastępowana kopią z późniejszego scope tylko dlatego, że tamta ma nowszą wersję.
- Nie szukamy globalnie najnowszej wersji na całym dysku. Podkatalogi pozostają w ograniczonym porządku skanowania; mechanizm upstream wybiera wersję w obrębie katalogu.
- Przy remisie porządek nazwy bez `.app` jak w Finderze, następnie pełna ścieżka jako stabilny rozstrzygający klucz. Brak czytelnej wersji przegrywa z czytelną wersją.
- Deduplikacja następuje po sprawdzeniu poprawności aplikacji. Niepoprawna lub background-only kopia nie może zasłonić poprawnej.

### Adaptacja

- Dodać odczyt wersji i sortowanie w SearchScopes. Wersję czytać raz na aplikację podczas skanu katalogu, nie przy każdym zapytaniu ani w comparatorze sortowania.
- Zachować anulowanie skanowania i dotychczasowy TTL katalogu 60/300 s.
- Sprawdzić świeżość odczytu metadanych przy aktualizacji pakietu lub zmianie celu symlinka. W razie cache Bundle odczytywać potrzebny Info.plist bezpośrednio podczas skanu.
- Nie rozbudowywać tej poprawki o parser SemVer ani automatyczne aktualizowanie aplikacji.

### Spójność skrótów i personalizacji

To konieczne dostosowanie do naszej aplikacji. Obecny `binding.onPress` przechwytuje zapisaną `value.entry`, a sprzątanie skrótów aktualizuje głównie nieistniejące ścieżki. Gdy stara i nowa kopia istnieją równocześnie, lista może otwierać nową, a skrót nadal starą.

- Po publikacji nowego katalogu udostępnić kontrolerowi wybrane aplikacje według stabilnego ID. Aktualizacja odbywa się raz na zmianę katalogu, poza ścieżką każdego wpisanego znaku.
- Uzgodnić ścieżkę zapisanej personalizacji z wybraną kopią. Zachować alias, ulubione, ukrycie i kombinację skrótu.
- Zaktualizować akcję istniejącego skrótu bez niepotrzebnego wyrejestrowania identycznej kombinacji Carbon. Przywrócić ten sam cel przy następnym uruchomieniu aplikacji.
- Nadal używać istniejącego mechanizmu LaunchServices dla aplikacji przeniesionych lub poza katalogiem; sam brak wyniku skanu nie oznacza odinstalowania.
- Po zmianie ścieżki odświeżyć odpowiednie ikony i zachować ochronę przed wykonaniem nieaktualnych wyników.

### Odbiór

Fixture z kilkoma prawidłowymi bundle: wersje 9.4/26.6/27.0, odwrócona kolejność nazw, równe wersje, brak wersji, niepoprawna najnowsza kopia, dwa scope i dwa różne bundle ID. Dodatkowo test aktualizacji celu skrótu przy zachowanych ustawieniach, gdy stara kopia nadal istnieje.

## 4. Skanowanie symlinków

### Analiza

Upstream oddziela fizyczną ścieżkę katalogu używaną do odczytu od logicznej ścieżki wyniku. Do wykrywania pętli używa zbioru fizycznych przodków bieżącej gałęzi. To istotne: globalny zbiór odwiedzonych katalogów usunąłby poprawne alternatywne aliasy.

Zmiana upstream powstała po poprawce wyboru wersji i używa `newestFirst`. Wdrożyć ją po punkcie 3, w tym samym obszarze kodu.

### Adaptacja

- Podążać za symlinkiem katalogu, zachowując logiczne ścieżki wpisane w scope i wyników aplikacji. Nie zastępować ich wszędzie ścieżkami fizycznymi.
- Rozwiązywać bieżący cel przy każdym pełnym odświeżeniu katalogu. Zmiana celu symlinka staje się widoczna po odświeżeniu, nie po każdym znaku zapytania.
- Wykrywać cykle po rozwiązanych ścieżkach przodków, osobno w każdej gałęzi. Przekazywać kontekst również do katalogów aplikacji osadzonych.
- Zachować nasz `includeEmbedded: false` dla osadzonych pakietów. Upstream ma inną rekursję; nie wolno przez adaptację rozszerzyć jej bez ograniczeń.
- Zachować maksymalnie jeden poziom zwykłych podfolderów, pomijanie ukrytych plików, deterministyczny porządek, anulowanie i końcową deduplikację logicznych ścieżek.
- Pomijać zerwane linki, cykle, niedostępne katalogi i pliki, kontynuując skan pozostałych elementów.
- Nie zmieniać granic i obsługi uprawnień wyszukiwania plików Spotlight. Scope aplikacji i foldery wyszukiwania plików to odrębne mechanizmy.

### Odbiór

Fixture z linkiem folderu głównego, łańcuchem linków, podlinkowanym folderem dostawcy, linkiem `.app`, zmianą celu na inną wersję/pakiet, ukrytym i zerwanym linkiem, pętlą do przodka i dwoma równoległymi linkami do tego samego folderu. Osobno potwierdzić limit głębokości, osadzone aplikacje i wspólne działanie z wyborem najnowszej wersji.

## 5. Fokus po menu i personalizacji

### Analiza

TinyCast dodaje przywrócenie SwiftUI FocusState do `closeMenus`. Nasz launcher ma NSTextField w NSViewRepresentable, natywne `.contextMenu`, popover personalizacji i NSPanel. Obecny `focusSearchField` działa przy otwieraniu palety; nie ma jednej ścieżki przywracania po menu i popoverze.

Nie kopiujemy wprost `searchFocused`. Trzeba ustalić zakończenie menu należącego do naszego launchera i przywrócić właściwego first respondera. Obecna analiza nie zastępuje reprodukcji w GUI.

### Adaptacja

1. Na izolowanym Debug sprawdzić zamknięcie menu przez Escape, kliknięcie i akcję oraz zamknięcie personalizacji przez zapis, anulowanie i kliknięcie poza nią. Zapisać, które scenariusze tracą fokus.
2. Dodać jedną ścieżkę kontrolera do żądania fokusu, z użyciem istniejącego LauncherPanel.focusSearchField. Wykonywać ją po zakończeniu obsługi zdarzenia, na MainActor.
3. Dla popovera obsłużyć każde zakończenie prezentacji, także zamknięcie z zewnątrz. Przywrócić fokus dopiero po jego faktycznym zamknięciu.
4. Dla menu użyć lokalnego, jednoznacznie przypisanego cyklu życia menu. Jeśli SwiftUI nie daje wiarygodnego sygnału, zastosować wąski adapter natywnego NSMenu z NSMenuDelegate dla wiersza. Zachować wygląd, istniejące akcje i dostępność. Nie przejmować delegata wewnętrznego menu SwiftUI.
5. Zakończenie menu prowadzącego do personalizacji nie może odebrać fokusu polu aliasu. Akcja otwierająca Finder albo ukrywająca launcher nie przywraca fokusu do palety.

NSMenuDelegate udostępnia [menuDidClose](https://developer.apple.com/documentation/appkit/nsmenudelegate/menudidclose(_:)). Samo globalne [didEndTrackingNotification](https://developer.apple.com/documentation/appkit/nsmenu/didendtrackingnotification) nie identyfikuje pewnie menu naszego wiersza; nie planujemy reakcji na zakończenie dowolnego menu procesu.

### Ochrona cyklu życia

- Sprawdzić token prezentacji, widoczność panelu, aktywność/key window i brak otwartego popovera lub menu przed wykonaniem opóźnionego żądania.
- Ukrycie, stop, sleep i blokada unieważniają żądanie. Stary callback nie może otworzyć ani aktywować palety.
- Zachować zapytanie, zaznaczenie/kursor i tryb schowka. Nie nadpisywać kompozycji IME.
- Uwzględnić przeniesienie key window do menu/popovera w `resignKey`, aby panel nie znikał w trakcie własnej interakcji. Kliknięcie innej aplikacji nadal zamyka launcher.
- Bez nowych globalnych monitorów klawiatury i bez nowych uprawnień.

### Odbiór

Skoncentrowany test GUI: po zamknięciu menu albo personalizacji można od razu dopisać tekst i poruszać się strzałkami bez ponownego klikania wyszukiwarki. Zapis/anulowanie nie zmieniają zapytania. Oddzielnie sprawdzić przejście menu -> popover, zamknięcie launchera, Finder i spóźniony callback. Krótka próba ręczna kompozycji tekstu; nie deklarować odbioru wszystkich IME na podstawie samego testu EN.

## 6. Walidacja, dokumentacja i dostarczenie

- Testy Core dla jednostek i indeksowania na tymczasowych plikach. Bez skanowania i modyfikacji rzeczywistych aplikacji użytkownika.
- Test kontrolera dla zmiany celu istniejącego skrótu; GUI dla zachowania fokusu. UI korzysta z osobnych preferencji i schowka w konfiguracji Debug.
- Po ostatniej zmianie jeden pełny przebieg testów Core z fixture Spotlight oraz Release arm64; regresje GUI launchera i schowka w zakresie dotkniętym zmianami.
- Jednorazowo porównać czas pełnego skanu syntetycznego katalogu przed/po dodaniu odczytu wersji. Nie mierzyć kosztu każdego zapytania, ponieważ nie powinno ono ponownie skanować katalogu. Nie robić całego audytu Instruments w ramach tych czterech poprawek.
- Uzupełnić nagłówki adaptowanych plików, THIRD_PARTY_NOTICES.md oraz zasób ThirdPartyNotices.txt o konkretne rewizje i lokalne modyfikacje; zachować istniejące informacje źródłowe.
- Zaktualizować README i dokumentację stanu o gotowe zachowanie, wyniki i ograniczenia. Plan otrzyma status wdrożony dopiero po implementacji i weryfikacji.
- Docelowo trzy commity Conventional Commits: `fix(calculator): distinguish bit and byte transfer rates`, `fix(launcher): select current app copies and follow directory symlinks`, `fix(launcher): restore search focus after menus`. Dokumentację i testy zawrzeć w odpowiednich commitach.
- Push i utworzenie kolejnego PR zgodnie z osobnym poleceniem właściciela; autoryzacja PR #8 nie oznacza automatycznej zgody na następny PR. Instalacja w /Applications również wymaga polecenia.

## Gotowość do startu

Plan nie wymaga dodatkowych ustawień produktu ani migracji historii schowka. Główną zależnością jest scalenie PR #8. Najwięcej pracy integracyjnej wymaga spójność celu skrótów oraz właściwy moment odzyskania fokusu; poprawka jednostek jest niezależna, a sortowanie wersji i symlinki należy wdrażać oraz sprawdzać wspólnie.
