# Etap 3B: fundament, paleta oraz aplikacje i polecenia

Data: 2026-09-23. Branch: `feat/stage-3b-launcher`, utworzony z `feat/stage-3a-clipboard` po commicie `ef217b2`. Zakres obejmuje kroki 1-3. To nie jest zakończenie całego launchera ani całego etapu 3.

## Implementacja

1. Wspólny model `LauncherEntry` i typowane akcje aplikacji, sekcji Mac Managera i paneli systemowych. Źródła implementują `LauncherProvider`. Silnik poza MainActor obsługuje dopasowanie dokładne, prefiks, początek słowa, fragment i podciąg, z rankingiem rozróżniającym nazwę, tłumaczenie i identyfikator techniczny. Brak uczenia lub zapisu wpisywanych fraz. Zapytanie jest ograniczone do 256 znaków, lista do 40 wyników. Anulowanie i numer generacji nie pozwalają nadpisać nowych wyników starym zadaniem. W trakcie nowego wyszukiwania nie można wykonać poprzednio wybranego wyniku.
2. Paleta AppKit/SwiftUI z natywnym Liquid Glass, polem wyszukiwania i listą rozwijaną w tej samej powierzchni. Pusty panel pokazuje tylko pole. Strzałki wybierają wynik, Enter go otwiera. Escape najpierw czyści, następnie zamyka. Kompozycja IME ma pierwszeństwo przed obsługą tych klawiszy. Panel jest nieaktywujący, nie zmienia preferencji Docka ani nie otwiera głównego okna. Zamyka się przy utracie fokusu, blokadzie i uśpieniu; stan zapytania znika z modelu.
3. Katalog aplikacji z katalogów systemowych i użytkownika oraz ograniczonego przeszukiwania podfolderów. Pakiety aplikacji nie są przeszukiwane dowolnie; uwzględniamy jeden poziom znanych katalogów aplikacji osadzonych, np. narzędzia Xcode. Deduplikacja po bundle ID, nazwy PL/EN, ikony systemowe i otwieranie/fokus przez NSWorkspace. Skanowanie następuje po otwarciu palety, nie w stałym pollerze. Polecenia otwierają istniejące sekcje Przegląd/Czujniki/Sieć/Schowek/Przewijanie/Dock/Ustawienia. Dwa dotychczas używane odnośniki ustawień macOS dotyczą prywatności oraz rzeczy otwieranych przy logowaniu; wynik pojawia się tylko po znalezieniu odpowiedniej zainstalowanej wtyczki systemowej.

Paleta jest dostępna z menu Widok i sekcji Launcher w Ustawieniach. Aktualizacja 2026-09-28: przycisk launchera usunięto z panelu paska menu. Domyślny skrót globalny to Control + Option + Spacja. Można go wyłączyć lub wybrać zestaw modyfikatorów i fizyczny klawisz. Rejestracja Carbon nie wymaga Dostępności ani Monitorowania wprowadzania. Jeżeli nowa rejestracja się nie uda, poprzednia pozostaje aktywna, a UI pokazuje błąd. To wykrywanie błędu rejestracji, nie gwarancja rozpoznania każdego przechwycenia skrótu przez system lub inne narzędzie. Zamknięcie procesu wyrejestrowuje skrót i handler.

## Adaptacja Tinycast

Rewizja: `c5cff8cbb9b7e12ac75c058da9573045c76029b7`. Przeniesiono ranking `SearchRelevance.swift` i zakresy `SearchScopes.swift`. Zaadaptowano mechanizmy `AppIndex`, `SettingsPaneScanner`, `HotKeyCenter` i `PalettePanel`. Integracja cyklu życia, publiczny kontrakt wyników, PL/EN, ustawienia, interfejs i testy należą do Mac Managera. Zachowano copyright i licencję oraz oznaczono zmiany. Szczegóły: [atrybucje](../../THIRD_PARTY_NOTICES.md); pełna licencja podróżuje także w zasobach aplikacji.

Nie przeniesiono osobnego programu, autostartu, updatera ani magazynu schowka Tinycast. Nie dodano zależności zewnętrznych ani nowych zgód. Kod źródłowy Tinycast pobrano wyłącznie do analizy/adaptacji; launcher nie łączy się z jego repozytorium w czasie działania.

## Weryfikacja i granice

80 testów Core obejmuje sześć nowych przypadków: ranking i Unicode, deterministyczne limity/deduplikację, późne odpowiedzi źródeł, wybór wyników, skanowanie sztucznych pakietów oraz trwałość/walidację skrótu. Testy GUI obejmują otwarcie palety, wyszukiwanie w obu językach, Escape i nawigację, a także rzeczywistą rejestrację skrótu, katalog aplikacji, otwarcie Kalkulatora i powrót do głównego okna po jego zamknięciu. Dwa scenariusze GUI przeszły. Układ palety sprawdzono także na nagraniu rzeczywistego testu. Potwierdzono zmianę skrótu na Control + Option + K i powrót fokusu do Findera. Kompilacje Debug i Release arm64 przeszły. W próbach poprawiono identyfikatory dostępności oraz nadawanie fokusu natywnemu polu po otwarciu przez skrót globalny.

Test z rzeczywistym skrótem używa osobnych ustawień i tymczasowo rejestruje skrót; zamyka uruchomiony przez siebie Kalkulator. Testy schowka nadal nie odczytują schowka użytkownika. Pełny odbiór VoiceOver, IME różnych języków, pełnoekranowych Spaces i pomiar kosztu pozostaje w kroku 8. Poprawna kompilacja i test referencyjny nie oznaczają weryfikacji każdej konfiguracji ekranów i innych narzędzi skrótów.

## Dalej

Aktualizacja: kroki 4-7 wdrożono w [kolejnym raporcie](etap-3b-launcher-4-7.md). Poniższa lista zachowuje kolejność planu; pozostaje odbiór kroku 8.

4. Aliasy, ulubione, ukrywanie wyników i skróty konkretnych pozycji.
5. Pliki i foldery przez Spotlight w wybranych lokalizacjach.
6. Kalkulator, jednostki i operacje daty/czasu.
7. Osobny tryb Schowek korzystający z obecnego magazynu; dopiero wtedy przełączanie trybów Tab.
8. Pełny odbiór dostępności, skrótów, fokusu, wydajności i regresji.

Historia schowka 3A została potwierdzona przez właściciela jako działająca. Osobnego testu aktualizacji podpisanego wydania i Universal Clipboard między urządzeniami nie należy domniemywać z tego potwierdzenia. W tej zmianie nie podmieniano instalacji w `/Applications`, nie tworzono PR ani nie wypychano brancha.
