# Etap 3C: wyspa, kroki 1–2

Data: 2026-10-13. Zakres: implementacja stabilnego hover i przewidywalnego fokusu. Panel służy na razie do odbioru interakcji; nie zawiera historii schowka ani integracji muzycznych.

## Zachowanie

- `IslandCoordinator` jest uczestnikiem wspólnego cyklu życia aplikacji. Wybiera aktywny wbudowany ekran, a bez niego ekran główny; zmiana konfiguracji ekranów przelicza geometrię i zamyka poprzednią prezentację.
- Czarny panel dochodzi do górnej krawędzi i obejmuje wysokość notcha. Wklęsłe ramiona i zaokrąglone dolne rogi odpowiadają referencji właściciela (D27). Kontrolki są poniżej safe area kamery. Po zwinięciu panel nie wyświetla niczego.
- Zdarzenia myszy zastępują okresowe odpytywanie pozycji. `IslandInteraction` wyznacza terminy otwarcia 150 ms i zamknięcia 350 ms; jeden anulowalny callback obsługuje najbliższy termin. Przejście do panelu i powrót kursora anulują zamknięcie. Escape blokuje ponowne otwarcie do opuszczenia obszaru aktywacji.
- `NSPanel` jest nieaktywujący: hover tylko pokazuje okno. Kliknięcie pola lub otwarcie przez menu/skrót pozwala pisać. Fokus klawiatury i śledzenie własnego menu podtrzymują panel; Escape zamyka i oddaje fokus poprzedniej aplikacji lub oknu MacManagera. Kompozycja IME może najpierw obsłużyć Escape we własnym edytorze.
- Wyspę można otworzyć z menu Widok, panelu paska menu i ustawień. Skrót jest domyślnie nieprzypisany, konfigurowalny i korzysta z istniejącej rejestracji Carbon; konflikt nie zastępuje działającego skrótu.
- Ustawienia obejmują włączenie wyspy i opcję pokazywania nad pełnym ekranem. Domyślnie pełny ekran na wybranym monitorze blokuje otwarcie. Odczyt publicznych metadanych geometrii okien nie wymaga dostępu do ich tytułów ani treści.
- Sleep, nieaktywna sesja i blokada mają osobne przyczyny zawieszenia. Wybudzenie nie usuwa nadal obowiązującej blokady. Zatrzymanie usługi unieważnia callbacki oraz usuwa monitory zdarzeń, obserwacje i rejestrację skrótu.

## Weryfikacja

- Pięć testów Core sprawdza krótkie wejście, terminy hover, ciągły ruch w obszarze, powrót przed zamknięciem, podtrzymanie klawiaturą, Escape/reset i trwałość ustawień. Pełny zestaw Core: 123 testy zakończone powodzeniem.
- XCTest GUI na urządzeniu referencyjnym sprawdza wejście w obszar aktywacji, przejście do pola bez kliknięcia i zwinięcie po opuszczeniu. Drugi test otwiera wyspę z menu Widok, wpisuje tekst, zamyka przez Escape i wykonuje polecenie klawiaturowe w głównym oknie.
- Kompilacje Debug i Release arm64 zakończone powodzeniem. Oba testy GUI przeszły ponownie po dopasowaniu czarnego kształtu do referencji. Zrzut panelu z załącznika XCTest sprawdzono wizualnie: czarne tło, połączenie z górną krawędzią i kontrolki poniżej kamery. Testy GUI używają `--ui-testing`, osobnych preferencji i schowka testowego. Pomocnicza kopia do inspekcji miała odrębny bundle ID `.IslandQA`.

## Granice odbioru i dalsze kroki

Nie zamykamy P07 ani całego 3C. Pozostają fizyczne próby clamshell, hot-plug, różnych skal, ekranów bez notcha, zwykłych Spaces pełnoekranowych i lock/sleep/wake oraz potwierdzenie braku przejęcia pisania w innej aplikacji przez sam hover. Nie wykonano pełnego odbioru IME/VoiceOver ani profilu Instruments.

Następny krok to czytelny schowek ze wspólną usługą (3), następnie animowane przejścia i kontrola niewidocznej pracy prezentacji (5). Odtwarzacz z wyborem źródła (4) pozostaje w 3D. Nie podmieniano aplikacji w `/Applications`, nie tworzono wydania ani PR.

Późniejsza instalacja na polecenie właściciela (2026-10-13): build Release z wyspą trafił do `/Applications/MacManager.app`. Po zgłoszeniu utraty zgód Scrolla podpis ad hoc zastąpiono stałą tożsamością Developer ID, z zachowaniem bundle ID i danych. Tymczasowa zmodyfikowana kopia potwierdziła inny CDHash przy identycznym designated requirement. Kolejne podmiany korzystają z [instalatora zachowującego tożsamość](../07-wydania.md#lokalne-podmiany-w-applications--zachowanie-tożsamości); zachowanie rzeczywistych zgód TCC między kolejnymi instalacjami nadal wymaga odbioru na urządzeniu.

Poprawka po zrzucie właściciela (2026-10-13): sam zadany frame panelu nie wystarczał do połączenia z krawędzią. Poziom `.floating` pozostawiał górną część pod paskiem menu, a domyślny `constrainFrameRect` mógł ograniczać pozycję do `visibleFrame`. Panel używa teraz poziomu `statusBar + 1` i zachowuje frame wyliczony względem pełnego ekranu. Test hover dodatkowo sprawdza rzeczywiste `minY` panelu i jego warstwę WindowServer na podstawie geometrii, bez odczytu tytułów cudzych okien.

Poprawka wysokości po kolejnym zrzucie właściciela (2026-10-13): widok SwiftUI miał nieograniczoną wysokość, a `NSHostingView` zachowywał domyślne publikowanie rozmiarów do okna. Panel po hover mógł rozciągać się na wysokość ekranu. Host otrzymuje teraz jawny rozmiar i `sizingOptions = []`, a panel ma zgodne min/max size: 440 punktów szerokości (ograniczone szerokością ekranu) oraz 220 punktów wysokości treści plus obszar kamery/paska menu. Test mierzy wysokość po hover, przejściu kursora do treści i ponownym otwarciu. Poprzednia kontrola samej górnej krawędzi i warstwy nie wykrywała tego błędu.
