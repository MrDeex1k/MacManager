# Plan realizacji i kryteria odbioru

Bieżący stan implementacji i następne kroki: [stan projektu](10-stan-projektu.md).

## Zasada realizacji

Trzy fazy są zatwierdzone. W ramach każdej zaczynamy od rozpoznania zależności technicznych, następnie budujemy funkcję i sprawdzamy zachowanie użytkowe. Nie deklarujemy terminów bez wyników prototypów.

Moc w W jest częścią fazy 1. Temperatury i RPM trafiają do fazy 2. Cała historia schowka i integracje muzyczne, również w zwykłym oknie, trafiają dopiero do fazy 3.

Aktualizacja 2026-09-18: kroki 1-8 są zaimplementowane. W kroku 9 wykonano pełne testy automatyczne, audyt dostępności, 10-minutowy pomiar pracy w tle oraz ręczną próbę na urządzeniu referencyjnym. Potwierdzono metryki, historię, sieć wraz z offline i powrotem połączenia, sleep/wake, cykl życia okna i automatyczne rozróżnianie myszy od gładzika. Wyniki opisuje [raport częściowy](reports/etap-1-krok-9a.md). Autostart z instalacji i odbiór dystrybucji pozostają otwarte.

## Kolejność kroków etapu 1

Całość rozwijamy na feat/stage-1. Numer kroku obejmuje prototypy, więc krok 2 odpowiada zadaniu F1-01, a krok 3 - F1-02.

1. Prototypy P01–P04 - narzędzia gotowe, walidacja sprzętowa częściowa.
2. Szkielet aplikacji F1-01 - gotowy; SwiftUI, lokalny Core, domyślny Liquid Glass, PL/EN.
3. Usługi pomiarów F1-02 - zaimplementowane po kroku 5; [raport](reports/etap-1-krok-3.md). Odczyt mocy AppleSMC PSTR został następnie włączony jako szacunek dostępny na obsługiwanych urządzeniach.
4. Wykresy i historia F1-03 - zaimplementowane; bufor 300 s, Swift Charts i luki; [raport](reports/etap-1-krok-4.md).
5. Sieć F1-04 - zaimplementowana przed krokiem 3; wyniki i ograniczenia w [raporcie](reports/etap-1-krok-5.md).
6. Scroll F1-05 - zaimplementowany; automatyczne rozróżnianie z gestów dotykowych, transformacja, zgody i cykl życia; [raport](reports/etap-1-krok-6.md).
7. Okno, pasek menu, Dock i autostart F1-06 - zaimplementowane; model ustawień, cykl życia procesu, pasek menu, opcjonalne CPU/GPU/RAM/W, Dock, `SMAppService.mainApp` i start bez okna przy logowaniu są gotowe. Próba z podpisaną aplikacją w `/Applications` pozostaje w odbiorze wydania.
8. Aktualizacje, prywatność i diagnostyka F1-07/F1-08 - gotowe; [plan](11-plan-kroku-8.md) i [raport odbioru](reports/etap-1-krok-8.md).
9. Odbiór i wydanie F1-09 - w toku; automatyzacja, dostępność, pomiar 10-minutowy oraz ręczna próba na urządzeniu referencyjnym są gotowe. Pozostają autostart z instalacji i wydanie.

## Prototypy i bramki techniczne

| ID | Kiedy | Badanie | Wynik wymagany do dalszych prac |
| --- | --- | --- | --- |
| P01 | Początek fazy 1 | CPU/RAM/GPU na M4 Pro, pomiar kosztu odczytu. | Definicje, źródła i raport poprawności; GPU nie zastąpione estymatą CPU. |
| P02 | Faza 1 | Moc Maca: bateria i AC. | PSTR potwierdzony na AC i baterii na urządzeniu testowym. Produkcja pokazuje go jako szacunek AppleSMC i zachowuje stan niedostępny, gdy czujnika nie ma. |
| P03 | Początek fazy 1 | Scroll: klasyfikacja urządzeń i zgody. | Odwrócona mysz, niezmieniony gładzik; lista przetestowanych urządzeń i ograniczeń. |
| P04 | Faza 1 | IPv4, zwykły VPN, split tunnel, wiele tuneli. | Dowód znaczenia podstawowego IP; dodatkowe wyjścia tylko jeśli potwierdzone. |
| P05 | Początek fazy 3 | Schowek, zgody macOS 26, currentHostOnly, obrazy i retencja. | Poprawny zapis/przywrócenie i odmowa, brak wysyłania oraz zapętlenia historii. |
| P06 | Początek fazy 3 | Słowniki i sterowanie aktualnymi Music/Spotify. | Komendy, jednostki, okładki, timeouty, odmowa zgody i brak automatycznego uruchamiania odtwarzacza. |
| P07 | Początek fazy 3 | Wyspa, hover, notch, monitory, pełny ekran i fokus. | Panel nie przechwytuje interakcji innej aplikacji przez samo najechanie; poprawna geometria. |

Faza 2 dodatkowo rozszerza raport P02 o katalog temperatur i RPM, w tym modele bez wentylatorów. Nie wolno uznać nieudokumentowanego klucza za stabilny kontrakt na przyszłe układy Apple.

Jeśli prototyp nie potwierdzi zachowania, raport wskazuje konkretną granicę. Zatwierdzony fallback dla mocy i dodatkowych adresów VPN pozwala wydać aplikację z komunikatem niedostępności. Nie jest ogólną zgodą na pominięcie CPU, RAM, GPU lub scrolla.

## Faza 1 - monitorowanie i podstawy

| Zadanie | Zależności | Gotowe, gdy |
| --- | --- | --- |
| F1-01: szkielet Xcode, SwiftUI i lokalny Core | Brak | Build dla arm64/macOS 26, PL/EN, ciemny interfejs; bez aktywnych funkcji fazy 3. |
| F1-02: usługi pomiarów | P01, P02 | Jedno próbkowanie, poprawne jednostki, brak fikcyjnych zer. |
| F1-03: wykresy i historia | F1-02 | Dokładnie okno 300 s, 1/2/5 s, luki i reset baz po wybudzeniu. |
| F1-04: sieć | P04 | LAN/publiczny IPv4, kopiowanie, offline, jawna niepewność VPN. |
| F1-05: scroll | P03 | Jeden przełącznik, Dostępność i Monitorowanie wprowadzania, cofnięcie zgód; niezależne zachowanie myszy/gładzika. |
| F1-06: okno/menu/Dock/autostart | F1-01 | Domyślne ustawienia zgodne z produktem; zamknięcie okna pozostawia tło, zakończenie zamyka proces. |
| F1-07: GitHub Releases | F1-01 | Harmonogram 7 dni, kontrola ręczna, wyłączenie, link do zgodnego wydania. |
| F1-08: prywatność i diagnostyka | F1-02–07 | Brak telemetrii, lokalne logi bez danych użytkownika; sprawdzony ruch sieciowy. |
| F1-09: wydanie testowe, potem publiczne | Wszystkie powyższe | Macierz fazy 1, podpisany/notaryzowany DMG i instrukcja instalacji. |

Pierwsze testy wewnętrzne mogą korzystać z lokalnego builda. Wydanie publiczne ma spełniać kryteria dystrybucji w [dokumencie wydań](07-wydania.md).

## Faza 2 - czujniki

Rozszerzyć katalog i adaptery o CPU/GPU w °C, konwersję wyłącznie w warstwie prezentacji, fizyczne wentylatory i RPM. Dodać widok szczegółów oraz niezależne ustawienia paska menu. Zapewnić czyszczenie historii odłączonego/niedostępnego źródła i odpowiednie stany.

Bramka: odczyty porównane z niezależną referencją dostępną na modelu; opisany zakres czujnika, brak jakichkolwiek komend zapisu do SMC, admin helpera lub regulacji RPM. Chłodzenie pasywne i 0 RPM są różnymi poprawnymi stanami. Ponownie zmierzyć koszt pracy w tle.

## Faza 3 - wyspa, schowek, muzyka

Stan na 2026-09-23: 3A (schowek) jest zaimplementowane na `feat/stage-3a-clipboard`. Testy automatyczne zakończone; właściciel potwierdził działanie zainstalowanej wersji. [Raport i zakres walidacji P05](reports/etap-3a-schowek.md). 3B ma wdrożone kroki 1-3 na osobnym branchu: [rdzeń, paleta, aplikacje i polecenia](reports/etap-3b-launcher-1-3.md). Wdrożono również [kroki 4-7](reports/etap-3b-launcher-4-7.md): personalizację, pliki Spotlight, kalkulator i wspólny tryb Schowek. Dalej pozostają krok 8 odbioru launchera, 3C wyspa i 3D muzyka.

Rozszerzenie kierunku (D24-D25): właściciel zatwierdził wspólną architekturę pod oba scenariusze integracji oraz kolejność rozszerzonego etapu 3: prywatny schowek, pełny launcher, wyspa i muzyka. Najpierw wdrażamy scenariusz 1, następnie rozwijamy go w kierunku scenariusza 2 bez wymiany wyszukiwarki ani magazynu schowka. [Scenariusze integracji](12-scenariusze-integracji-tinycast.md) opisują granice obu wariantów i dalsze moduły. Etap 2 pozostaje niezależnym etapem czujników.

Kolejność rozszerzonego etapu 3: P05 → prywatne repozytorium schowka, retencja i ochrona danych → przywracanie i UI → pełny launcher z aplikacjami, plikami, komendami i nawigacją → P07 i panel wyspy → P06 i adaptery muzyki → wspólny panel → testy dostępności, migracji i obciążenia. Wyspa korzysta z tej samej usługi schowka i nie tworzy drugiego pollera ani magazynu.

Bramka: zwinięta wyspa nie pokazuje żadnej treści; schowek działa również bez widocznej wyspy; lokalne odtwarzacze obsługują podstawowe akcje; brak biblioteki, OAuth i sterowania innymi urządzeniami. Żadna odmowa uprawnienia nie unieruchamia całej aplikacji.

### Plan wyspy 3C i integracji muzyki 3D

Aktualizacja 2026-10-12 (D26): pierwsza wersja obejmuje pięć priorytetów doprecyzowanych po analizie NotchNook, Alcove i Atoll. Specyfikacja zachowania znajduje się w [dokumencie interfejsu](02-interfejs.md#wyspa). To plan prac i odbioru, nie deklaracja wdrożenia.

Aktualizacja 2026-10-13: kroki 1–2 mają implementację panelu AppKit, sterowanie z menu i opcjonalny skrót oraz testy logiki hover i GUI. Czarna powierzchnia łączy się z notchem zgodnie z D27. Pełny odbiór P07 na wielu konfiguracjach ekranów i sesji pozostaje otwarty. [Raport kroków 1–2](reports/etap-3c-wyspa-1-2.md). Schowek, odtwarzacz i animowane przejścia pozostają kolejnymi krokami.

Krok 3 jest zaimplementowany lokalnie (2026-10-13): wyspa pokazuje wspólną historię tekstów i obrazów, miniatury, wyszukiwanie, przywrócenie z „Skopiowano”, usuwanie oraz włączanie/pauzę nagrywania. Strzałki wybierają wpis, Enter przywraca, Escape zamyka. Panel ma stałą wysokość 340 punktów treści plus obszar kamery, a lista przewija się wewnątrz. [Raport kroku 3](reports/etap-3c-wyspa-3.md). Kroki 5 i 4 dla Apple Music zostały następnie wdrożone; zakres odbioru opisano poniżej.

Krok 5 ma implementację i odbiór funkcjonalny (2026-10-13): skończone przejścia otwierania/zamykania, Reduce Motion, łagodne zmiany zaznaczenia i potwierdzenia oraz natychmiastowe zwalnianie prywatnej zawartości przy zamykaniu. Ukryty panel nie ma hosta, animacji ani aktywnych zadań prezentacji; wspólne usługi pozostają niezależne. Testy sprawdzają wielokrotne cykle, anulowanie wyszukiwania i stan bezczynny. [Raport kroku 5](reports/etap-3c-wyspa-5.md). Pomiar Instruments i pełna macierz sesji/ekranów pozostają w odbiorze. Zmiana sekcji oraz zatrzymanie pracy Muzyki są sprawdzone testami GUI w 3D.

| Krok | Etap / zależności | Zakres i kryterium ukończenia |
| --- | --- | --- |
| 1. Stabilny hover | 3C / P07 | Geometria aktywacji i panelu pozwala przejść od górnej krawędzi do treści bez zwinięcia. Ruch przy granicy nie powoduje migotania; powrót kursora anuluje oczekujące zamknięcie. Zwłoki 150/350 ms stroimy na urządzeniu. |
| 2. Przewidywalny fokus | 3C / P07 | Hover otwiera bez aktywacji aplikacji i bez przejęcia pisania. Kliknięcie pola umożliwia wyszukiwanie; skrót i pasek menu zapewniają drogę klawiaturową. Pisanie i menu kontekstowe podtrzymują panel; Escape zamyka i oddaje fokus. |
| 3. Czytelny schowek | 3C / istniejący ClipboardService | Rozpoznawalne miniatury, czytelne fragmenty tekstu, responsywne wyszukiwanie i przywrócenie jedną akcją z potwierdzeniem „Skopiowano”. Ta sama historia co w launcherze i oknie, bez drugiego obserwatora, magazynu ani automatycznego wklejania. |
| 4. Kompaktowy odtwarzacz | Apple Music wdrożone; Spotify odłożone / P06 i panel 3C | Okładka, tytuł, wykonawca, postęp i poprzedni/odtwórz-pauza/następny. Źródło oznaczone i przełączane w panelu; jedno grające wybierane automatycznie, dwa utrzymują ostatni wybór. Brak zgody, odtwarzacza i okładki mają czytelne stany. |
| 5. Animacje tylko wtedy, gdy potrzebne | 3C, następnie odbiór z 3D | Dopracowane otwarcie, zamknięcie i zmiana sekcji; Reduce Motion. Bez wizualizacji audio. Renderowanie postępu tylko w widocznej sekcji Muzyka; zwinięcie, ukrycie i zmiana sekcji zatrzymują zadania prezentacji, bez mnożenia timerów przy ponownym otwieraniu. |

Kolejność wykonania: prototyp P07 i kroki 1–2 → schowek w panelu (3) → przejścia i zatrzymywanie pracy prezentacji (5) → P06 i odtwarzacz (4) → wspólny odbiór 3C/3D, w tym ponowna kontrola kroku 5. Odtwarzacz pozostaje w 3D; aktualizacja nie zmienia kolejności 3A → 3B → 3C → 3D.

Odbiór pierwszej wersji obejmuje T10–T12, T17, T20 oraz poniższe scenariusze T22–T26. Każdy otrzymuje wynik i opis konfiguracji; samo przygotowanie dokumentacji nie zamyka kroku. Półka plików, przeciąganie wpisów schowka, gesty, Live Activities, zastępowanie systemowych HUD-ów i widżety blokady nie są częścią tych pięciu priorytetów.

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
| T22: stabilność hover | ISL-01/02, D26 | Przejście od krawędzi do treści, ruch wzdłuż granicy i szybkie wyjście/powrót: bez migotania i przedwczesnego zwinięcia. Powtórzyć na ekranie z notchem i bez oraz przy zmianie skali. |
| T23: fokus wyspy | ISL-02, D26 | Pisać w innej aplikacji podczas hover: fokus pozostaje. Kliknąć wyszukiwarkę, pisać, otworzyć menu wpisu; panel pozostaje otwarty. Skrót/pasek menu umożliwiają obsługę klawiaturą; Escape zamyka i oddaje fokus. |
| T24: schowek w wyspie | CLP-01/02, D26 | Tekst krótki/długi/wielowierszowy i obraz: czytelne wpisy, wyszukiwanie, jedna akcja przywrócenia i „Skopiowano”. Zgodność z historią okna/launchera, bez duplikatu i symulowania ⌘V. |
| T25: kompaktowe media | MUS-01, D26 | Music/Spotify osobno i równocześnie: poprawny wybór automatyczny, utrzymanie ostatniego źródła przy dwóch grających i ręczna zmiana w panelu. Długi tytuł i brak okładki nie zasłaniają przycisków; podstawowe akcje działają. |
| T26: praca prezentacji i animacje | ISL-01/02, MUS-01, D26 | Otwieranie/zamykanie, zmiana sekcji, pełny ekran i blokada zatrzymują niewidoczne animacje/renderowanie postępu; powrót pokazuje aktualny stan. Powtarzane otwarcia nie mnożą timerów/obserwatorów; Reduce Motion respektowane. Koszt potwierdzony profilem, bez zatrzymywania wspólnych usług. |

## Strategia testów

Testy jednostkowe dla rzeczywistej logiki: różnice liczników, normalizacja, bufor czasu, jednostki, granice retencji, własne zmiany schowka, parser wersji i harmonogram aktualizacji. Zegar oraz sieć wstrzykiwane - brak testów zależnych od rzeczywistego oczekiwania tygodnia.

Integracyjne: adaptery i repozytorium na syntetycznych danych, odmowy, niedostępność, timeouty, migracja. UI: kluczowe przepływy, fokus i cykl życia; nie testować wyłącznie struktury widoków. Testy TCC i hardware wykonywać ręcznie na czystym profilu użytkownika, dokumentując zgody.

Macierz sprzętowa: referencyjny M4 Pro; co najmniej starszy M1/M2 z wentylatorem; Air bez wentylatora; Mac stacjonarny lub udokumentowana luka jego walidacji. macOS 26.0 oraz bieżąca obsługiwana aktualizacja, ekrany z notchem/bez, zewnętrzny monitor i tryb clamshell. Wynik fixture nie zastępuje fizycznego testu.

## Budżet wydajności - cele do pomiaru

Decyzje inżynierskie, nie wyniki: na referencyjnym M4 Pro przy próbkowaniu co 2 s, faza 1 w tle powinna średnio zużywać poniżej 1% jednego rdzenia CPU w oknie 10 minut i około 100 MB lub mniej pamięci rezydentnej. Dla fazy 3 celem jest około 200 MB przy domyślnych limitach, z dekodowaniem tylko widocznych miniatur. Tymczasowe szczyty obrazów mierzyć osobno.

Nie robić testu akceptacyjnego samego poboru W z odczytu aplikacji, która mierzy własny narzut. Użyć Instruments/Energy i porównania powtarzalnego scenariusza z aplikacją oraz bez niej. Sprawdzić brak wzrostu pamięci w sesji 8-godzinnej, brak ciągłych animacji w ukrytej wyspie i brak mnożenia timerów przy otwieraniu widoków.

## Definicja ukończenia fazy

Kod i istotne testy przechodzą; scenariusze przypisane do fazy mają wynik; pozostałe ograniczenia są jawne i zgodne z zakresem. Dokumentacja, tłumaczenia i release notes odpowiadają rzeczywistemu buildowi. Brak sekretów i danych użytkownika w artefaktach. Nie oznaczać fazy jako ukończonej samym przygotowaniem dokumentacji.


### Krok 4 - Apple Music, 2026-10-13

Zgodnie z decyzją właściciela aktualny zakres obejmuje tylko Apple Music. Wdrożono sekcję Muzyka: tytuł, wykonawca, album, lokalna okładka lub placeholder, postęp i czas w sekundach, poprzedni/odtwórz-pauza/następny. Obsługiwane są brak procesu, brak utworu, wymagana zgoda, odmowa, timeout i błąd polecenia. Przycisk Połącz Apple Music uruchamia standardową zgodę Automatyzacji; pasywny odczyt nie wywołuje promptu ani nie uruchamia Music.

128 testów Core przeszło. Testy GUI pokrywają podstawowe akcje, odmowę zgody i zatrzymanie pracy po zmianie sekcji/zamknięciu. Lokalny słownik Music 1.7 i dostęp z podpisanej instalacji zostały sprawdzone; odczyt rzeczywistego stanu bez bieżącego utworu działa. Po uruchomieniu utworu przez właściciela potwierdzono prawdziwe metadane, okładkę, czas trwania i aktualizację postępu. Dodatkowy odbiór na prawdziwym Music potwierdził pauzę/wznowienie, następny/poprzedni oraz zmianę i przywrócenie okładki. Poprzedni zachowuje natywną semantykę: po kilku sekundach najpierw restart utworu, kolejne szybkie kliknięcie cofa w kolejce. [Raport](reports/etap-3d-apple-music.md).

T17/T25 dla Spotify, równoczesne źródła, automatyczny wybór oraz ręczny przełącznik odtwarzacza zostają odłożone do instalacji Spotify przez właściciela. Dostępność, pełna macierz ekranów/sesji i pomiar Instruments pozostają w odbiorze 3C/3D.


### Odbiór poziomej półki schowka

Aktualizacja 2026-10-13: poziome kafelki i wspólny szeroki układ Muzyki zastępują pionową listę w wyspie. Odbiór obejmuje geometrię 560 × 350, hover pomiędzy notchem a bokami panelu, poziome rozmieszczenie, klawiaturę, wyszukiwanie/przywracanie/usuwanie i wygaszanie pracy po ukryciu, także z Reduce Motion. [Raport](reports/etap-3c-wyspa-poziomy-schowek.md).
