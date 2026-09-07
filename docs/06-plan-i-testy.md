# Plan realizacji i kryteria odbioru

Bieżący stan implementacji i następne kroki: [stan projektu](10-stan-projektu.md).

## Zasada realizacji

Trzy fazy są zatwierdzone. W ramach każdej zaczynamy od rozpoznania zależności technicznych, następnie budujemy funkcję i sprawdzamy zachowanie użytkowe. Nie deklarujemy terminów bez wyników prototypów.

Moc w W jest częścią fazy 1. Temperatury i RPM trafiają do fazy 2. Cała historia schowka i integracje muzyczne, również w zwykłym oknie, trafiają dopiero do fazy 3.

Aktualizacja 2026-09-08: zaimplementowano narzędzia CLI dla kroku 1 i wykonano pierwsze próby P01–P04; szczegóły i brakujące dowody w [raporcie](reports/etap-1-krok-1.md). Prototypy są w toku walidacji. Krok 2 (F1-01: szkielet aplikacji) jest zaimplementowany; buildy Debug/Release, testy Core i przepływy UI opisuje [raport kroku 2](reports/etap-1-krok-2.md). F1-04 wdrożono w kroku 5, a F1-02 w następującym po nim kroku 3; następnie wdrożono F1-03 w kroku 4; pozostałe zadania i późniejsze fazy są w realizacji lub planowane.

## Kolejność kroków etapu 1

Całość rozwijamy na feat/stage-1. Numer kroku obejmuje prototypy, więc krok 2 odpowiada zadaniu F1-01, a krok 3 — F1-02.

1. Prototypy P01–P04 — narzędzia gotowe, walidacja sprzętowa częściowa.
2. Szkielet aplikacji F1-01 — gotowy; SwiftUI, lokalny Core, domyślny Liquid Glass, PL/EN.
3. Usługi pomiarów F1-02 — zaimplementowane po kroku 5; [raport](reports/etap-1-krok-3.md). Moc pozostaje jawnie niedostępna.
4. Wykresy i historia F1-03 — zaimplementowane; bufor 300 s, Swift Charts i luki; [raport](reports/etap-1-krok-4.md).
5. Sieć F1-04 — zaimplementowana przed krokiem 3; wyniki i ograniczenia w [raporcie](reports/etap-1-krok-5.md).
6. Scroll F1-05.
7. Okno, pasek menu, Dock i autostart F1-06.
8. Aktualizacje i prywatność F1-07/F1-08.
9. Odbiór i wydanie F1-09.

## Prototypy i bramki techniczne

| ID | Kiedy | Badanie | Wynik wymagany do dalszych prac |
| --- | --- | --- | --- |
| P01 | Początek fazy 1 | CPU/RAM/GPU na M4 Pro, pomiar kosztu odczytu. | Definicje, źródła i raport poprawności; GPU nie zastąpione estymatą CPU. |
| P02 | Początek fazy 1 | Moc całego Maca: bateria, AC, ładowanie, ekran, obciążenie. | Zweryfikowane źródło albo jawnie niedostępny MET-02; bez sumy CPU+GPU jako całości. |
| P03 | Początek fazy 1 | Scroll: klasyfikacja urządzeń i zgody. | Odwrócona mysz, niezmieniony gładzik; lista przetestowanych urządzeń i ograniczeń. |
| P04 | Faza 1 | IPv4, zwykły VPN, split tunnel, wiele tuneli. | Dowód znaczenia podstawowego IP; dodatkowe wyjścia tylko jeśli potwierdzone. |
| P05 | Początek fazy 3 | Schowek, zgody macOS 26, currentHostOnly, obrazy i retencja. | Poprawny zapis/przywrócenie i odmowa, brak wysyłania oraz zapętlenia historii. |
| P06 | Początek fazy 3 | Słowniki i sterowanie aktualnymi Music/Spotify. | Komendy, jednostki, okładki, timeouty, odmowa zgody i brak automatycznego uruchamiania odtwarzacza. |
| P07 | Początek fazy 3 | Wyspa, hover, notch, monitory, pełny ekran i fokus. | Panel nie przechwytuje interakcji innej aplikacji przez samo najechanie; poprawna geometria. |

Faza 2 dodatkowo rozszerza raport P02 o katalog temperatur i RPM, w tym modele bez wentylatorów. Nie wolno uznać nieudokumentowanego klucza za stabilny kontrakt na przyszłe układy Apple.

Jeśli prototyp nie potwierdzi zachowania, raport wskazuje konkretną granicę. Zatwierdzony fallback dla mocy i dodatkowych adresów VPN pozwala wydać aplikację z komunikatem niedostępności. Nie jest ogólną zgodą na pominięcie CPU, RAM, GPU lub scrolla.

## Faza 1 — monitorowanie i podstawy

| Zadanie | Zależności | Gotowe, gdy |
| --- | --- | --- |
| F1-01: szkielet Xcode, SwiftUI i lokalny Core | Brak | Build dla arm64/macOS 26, PL/EN, ciemny interfejs; bez aktywnych funkcji fazy 3. |
| F1-02: usługi pomiarów | P01, P02 | Jedno próbkowanie, poprawne jednostki, brak fikcyjnych zer. |
| F1-03: wykresy i historia | F1-02 | Dokładnie okno 300 s, 1/2/5 s, luki i reset baz po wybudzeniu. |
| F1-04: sieć | P04 | LAN/publiczny IPv4, kopiowanie, offline, jawna niepewność VPN. |
| F1-05: scroll | P03 | Jeden przełącznik, zgoda i cofnięcie zgody; niezależne zachowanie myszy/gładzika. |
| F1-06: okno/menu/Dock/autostart | F1-01 | Domyślne ustawienia zgodne z produktem; zamknięcie okna pozostawia tło, zakończenie zamyka proces. |
| F1-07: GitHub Releases | F1-01 | Harmonogram 7 dni, kontrola ręczna, wyłączenie, link do zgodnego wydania. |
| F1-08: prywatność i diagnostyka | F1-02–07 | Brak telemetrii, lokalne logi bez danych użytkownika; sprawdzony ruch sieciowy. |
| F1-09: wydanie testowe, potem publiczne | Wszystkie powyższe | Macierz fazy 1, podpisany/notaryzowany DMG i instrukcja instalacji. |

Pierwsze testy wewnętrzne mogą korzystać z lokalnego builda. Wydanie publiczne ma spełniać kryteria dystrybucji w [dokumencie wydań](07-wydania.md).

## Faza 2 — czujniki

Rozszerzyć katalog i adaptery o CPU/GPU w °C, konwersję wyłącznie w warstwie prezentacji, fizyczne wentylatory i RPM. Dodać widok szczegółów oraz niezależne ustawienia paska menu. Zapewnić czyszczenie historii odłączonego/niedostępnego źródła i odpowiednie stany.

Bramka: odczyty porównane z niezależną referencją dostępną na modelu; opisany zakres czujnika, brak jakichkolwiek komend zapisu do SMC, admin helpera lub regulacji RPM. Chłodzenie pasywne i 0 RPM są różnymi poprawnymi stanami. Ponownie zmierzyć koszt pracy w tle.

## Faza 3 — wyspa, schowek, muzyka

Kolejność: P05/P06/P07 → panel i obsługa ekranów → lokalne repozytorium schowka → retencja i ochrona danych → przywracanie i UI → adaptery muzyki → wspólny panel → testy dostępności, migracji i obciążenia.

Bramka: zwinięta wyspa nie pokazuje żadnej treści; schowek działa również bez widocznej wyspy; lokalne odtwarzacze obsługują podstawowe akcje; brak biblioteki, OAuth i sterowania innymi urządzeniami. Żadna odmowa uprawnienia nie unieruchamia całej aplikacji.

## Scenariusze odbioru

| Test | Wymagania | Oczekiwany wynik |
| --- | --- | --- |
| T01: pierwszy start i ponowny start | SYS, APP-02 | PL/EN, ciemny motyw, Dock widoczny; próba autostartu i prawdziwy stan macOS. |
| T02: zamknij okno / zakończ | APP-01 | Metryki działają po zamknięciu okna; ⌘Q kończy proces i event tap. |
| T03: niezależne wskaźniki | BAR-01, SEN-02 | Każdy przełącznik działa osobno; domyślnie tylko ikona. |
| T04: odczyty bazowe | MET-01 | CPU 0–100%, RAM z właściwą kategorią i jednostką, GPU ze źródła GPU. |
| T05: brak/awaria pomiaru | MET-01/02 | Unavailable/stale, brak 0 W lub zawieszonej wartości jako bieżącej. |
| T06: czas, interwał, uśpienie | MET-03 | Odcinanie po 300 s przy każdym interwale; luki, reset baz, brak nadrabiania pętli. |
| T07: sieć i VPN | NET-01/02 | IPv4, offline, zmiana Wi-Fi/Ethernet, VPN/split tunnel/multiple; bez przypisania IP do aplikacji bez dowodu. |
| T08: scroll i TCC | SCR-01 | Mysz odwrócona, gładzik bez zmian; enable/disable/revoke i timeout tapu bez blokowania wejścia. |
| T09: czujniki | SEN-01/02 | Poprawne °C/°F, każdy wentylator, 0 RPM, chłodzenie pasywne i brak czujnika. |
| T10: wyspa | ISL-01/02 | Hover i skrót, pusta po zwinięciu, brak podglądu po kopiowaniu, właściwy ekran. |
| T11: ekrany i sesja | ISL-01 | Otwarta/zamknięta klapa, hot-plug, scaling, Spaces, pełny ekran, lock/unlock. |
| T12: tekst/obraz | CLP-01/02 | Unicode, wielowierszowy tekst, obraz, restart, wyszukiwanie i wierne przywrócenie. |
| T13: własny zapis i szybkie kopiowanie | CLP-01/02 | Bez duplikatu przy przywróceniu; niespójny snapshot odrzucony; udokumentowane ograniczenie szybkich zmian. |
| T14: retencja | CLP-03 | Osobno liczba/wiek/bajty, obniżenie limitów, start z wygasłymi danymi, usuwanie miniatur i osieroconych plików. |
| T15: poufność | CLP-03, PRI-01 | Oznaczone poufne/tymczasowe wpisy pomijane, pauza/wykluczenia/odmowa; brak plaintextu na dysku i treści w logach. |
| T16: uszkodzenie danych | CLP-01 | Brak klucza, pełny dysk, przerwany zapis, uszkodzony payload; brak utraty całej zdrowej historii bez zgody. |
| T17: odtwarzacze | MUS-01 | Music/Spotify osobno i razem, brak aplikacji, odmowa, brak okładki, zmiana utworu i rozbieżne jednostki czasu. |
| T18: aktualizacje | UPD-01 | 7 dni, restart, offline, limit API, starsza wersja, prerelease, brak DMG, uszkodzona odpowiedź; brak instalacji. |
| T19: brak emisji danych | PRI-01 | Ruch zgodny z tabelą endpointów; brak połączeń schowka, metryk i telemetrii. |
| T20: dostępność i lokalizacja | SYS-02/03 | PL/EN, długi tekst, VoiceOver, klawiatura, Reduce Motion/Transparency, kontrast. |
| T21: instalacja i migracja | APP, UPD | Czysty użytkownik, Gatekeeper, aktualizacja przez DMG, zachowane ustawienia i stan autostartu. |

## Strategia testów

Testy jednostkowe dla rzeczywistej logiki: różnice liczników, normalizacja, bufor czasu, jednostki, granice retencji, własne zmiany schowka, parser wersji i harmonogram aktualizacji. Zegar oraz sieć wstrzykiwane — brak testów zależnych od rzeczywistego oczekiwania tygodnia.

Integracyjne: adaptery i repozytorium na syntetycznych danych, odmowy, niedostępność, timeouty, migracja. UI: kluczowe przepływy, fokus i cykl życia; nie testować wyłącznie struktury widoków. Testy TCC i hardware wykonywać ręcznie na czystym profilu użytkownika, dokumentując zgody.

Macierz sprzętowa: referencyjny M4 Pro; co najmniej starszy M1/M2 z wentylatorem; Air bez wentylatora; Mac stacjonarny lub udokumentowana luka jego walidacji. macOS 26.0 oraz bieżąca obsługiwana aktualizacja, ekrany z notchem/bez, zewnętrzny monitor i tryb clamshell. Wynik fixture nie zastępuje fizycznego testu.

## Budżet wydajności — cele do pomiaru

Decyzje inżynierskie, nie wyniki: na referencyjnym M4 Pro przy próbkowaniu co 2 s, faza 1 w tle powinna średnio zużywać poniżej 1% jednego rdzenia CPU w oknie 10 minut i około 100 MB lub mniej pamięci rezydentnej. Dla fazy 3 celem jest około 200 MB przy domyślnych limitach, z dekodowaniem tylko widocznych miniatur. Tymczasowe szczyty obrazów mierzyć osobno.

Nie robić testu akceptacyjnego samego poboru W z odczytu aplikacji, która mierzy własny narzut. Użyć Instruments/Energy i porównania powtarzalnego scenariusza z aplikacją oraz bez niej. Sprawdzić brak wzrostu pamięci w sesji 8-godzinnej, brak ciągłych animacji w ukrytej wyspie i brak mnożenia timerów przy otwieraniu widoków.

## Definicja ukończenia fazy

Kod i istotne testy przechodzą; scenariusze przypisane do fazy mają wynik; pozostałe ograniczenia są jawne i zgodne z zakresem. Dokumentacja, tłumaczenia i release notes odpowiadają rzeczywistemu buildowi. Brak sekretów i danych użytkownika w artefaktach. Nie oznaczać fazy jako ukończonej samym przygotowaniem dokumentacji.
