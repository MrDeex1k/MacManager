# Dwa scenariusze integracji TinyCast

Data: 2026-09-20. Podstawa techniczna: [analiza kodu obu projektów](reports/analiza-integracji-tinycast.md), TinyCast w commicie `c5cff8cbb9b7e12ac75c058da9573045c76029b7`.

## Ustalone przez właściciela

1. Połączyć funkcje schowka, zachowując prywatność.
2. Dołączyć cały moduł wyszukiwania TinyCast do Mac Managera, z paletą aplikacji i komend jak na załączonym zrzucie.
3. Użytkownik chce jedną aplikację skupiającą wiele narzędzi oraz dwa scenariusze jej rozwoju.

Decyzja wdrożeniowa: wspólna architektura obsługuje oba scenariusze. Najpierw wdrażamy scenariusz A, a następnie rozwijamy go w kierunku scenariusza B bez wymiany wyszukiwarki ani magazynu schowka. Etap 2 pozostaje etapem czujników. Rozszerzony etap 3 realizujemy jako: prywatny schowek, pełny launcher, wyspa i muzyka.

Poniżej porównujemy pełny launcher lokalny z rozbudową o pozostałe moduły TinyCast. To warianty zakresu jednej aplikacji, nie polecenie przygotowania dwóch instalatorów. Szczegółowy zestaw dodatkowych modułów, nowe przepływy danych i kolejność wdrażania są propozycją do wyboru. Nie oznaczamy żadnego z tych modułów jako zaimplementowanego.

## Wspólny efekt użytkowy

Po skrócie globalnym lub akcji w pasku menu pojawia się pływająca paleta. Stan początkowy nawiązuje do zrzutu: szeroki, niski, mocno zaokrąglony pasek, ciemne szkło z prześwitującym tłem, ikona lupy i pole „Szukaj aplikacji i poleceń…”. Po wpisaniu zapytania panel rozwija listę wyników w tej samej powierzchni. Sam zrzut pokazuje wygląd stanu początkowego; zachowanie rozwiniętego panelu opisujemy na podstawie kodu TinyCast i poniższych propozycji.

Pełny moduł launchera obejmuje wspólną obsługę wyników, dopasowanie przybliżone, ranking, aliasy, ulubione, akcje kontekstowe, nawigację klawiaturą, skrót globalny, fokus i przechodzenie do ekranów narzędzi. Skopiowanie samego pola tekstowego nie spełnia tego celu.

Proponowane zachowanie: strzałki wybierają wynik, Enter wykonuje wskazaną akcję, Tab przełącza wyszukiwanie i schowek, a Escape najpierw czyści zapytanie, następnie zamyka panel i oddaje fokus. Każda akcja ma widoczną nazwę; Enter na wpisie schowka przywraca go do schowka systemowego zgodnie z dotychczasową regułą ręcznego ⌘V. Skrót jest konfigurowalny, z informacją o konflikcie. Zwykłe wyszukiwanie nie wymaga zgód potrzebnych wyłącznie zaawansowanym funkcjom.

Paleta jest osobnym oknem tej samej aplikacji. Wyspa przy notchu zachowuje własną geometrię, hover i pusty stan zwinięty. Paleta, wyspa i pełne okno korzystają z tej samej historii. Uruchomienie palety nie pokazuje automatycznie głównego okna ani nie zmienia ustawienia Docka.

## Scenariusz A: pełny launcher lokalny i prywatny schowek

Cel: codzienne narzędzia i wyszukiwanie pod jednym skrótem, ze wspólnym interfejsem Mac Managera i bez automatycznego wysyłania zapytań lub historii do usług zewnętrznych.

### Zakres

| Obszar | Docelowe zachowanie |
| --- | --- |
| Aplikacje | Wyszukiwanie przybliżone, otwieranie/fokus, ikony, aliasy, ulubione, ukrywanie wybranych pozycji i obsługa klawiaturą. |
| Polecenia Mac Managera | Otwórz Przegląd/Sieć/Czujniki/Schowek/Ustawienia; steruj istniejącymi funkcjami przez ich obecne usługi. Brak drugiego systemu ustawień czy aktualizacji. |
| Ustawienia systemowe | Wyszukiwanie i otwieranie dostępnych paneli macOS; tylko zweryfikowane odnośniki dla obsługiwanych wersji systemu. |
| Pliki i foldery | Szukanie nazw przez Spotlight w wybranych lokalizacjach, filtry i otwieranie wyników. Bez własnego indeksu zawartości i bez czytania plików przy każdym wpisanym znaku. |
| Kalkulator | Obliczenia, procenty, jednostki i operacje daty/czasu, dostępne lokalnie. Świeże kursy walut i kryptowalut wymagają wariantu z jawnym pobieraniem danych. |
| Historia schowka | Teksty/obrazy, szyfrowanie, wyszukiwanie w RAM, limity, pauza, wykluczenia i ręczne przywracanie. Jeden magazyn niezależny od widoczności panelu. |
| Skróty | Wspólna konfiguracja skrótu palety oraz skrótów aplikacji/poleceń, wykrywanie konfliktów i prawidłowe wyrejestrowanie. |
| Lokalne dodatki | Emoji, słownik macOS oraz zapisane odnośniki mogą otrzymać własne ekrany w tej samej palecie. |

Notatki, szablony tekstu, zarządzanie oknami i uruchamianie Apple Shortcuts mogą rozszerzać A jako kolejne lokalne moduły. Nie są konieczne do samego wyszukiwania aplikacji i komend. Automatyczne rozwijanie tekstu, manipulowanie cudzymi oknami i uruchamianie skrótów mają własne zasady aktywacji i uprawnienia.

„Lokalny launcher” opisuje wyszukiwanie i przetwarzanie danych, nie gwarancję braku sieci w całym komputerze. Otwarcie strony, aplikacji lub Apple Shortcut może uruchomić ich połączenia. Wbudowane publiczne IP i aktualizacje Mac Managera zachowują ujawnione endpointy. Dowolny shell i runtime rozszerzeń nie są częścią tego wariantu podstawowego.

### Prywatność

Historia jest szyfrowana AES-GCM; klucz lokalny w Keychain, treść/źródło/miniatury poza jawnymi tabelami SQLite. Indeks tekstów działa w RAM. Zamknięcie sesji ukrywa dane i zatrzymuje przechwytywanie. Nie zapisujemy treści schowka ani pełnych zapytań w logach lub diagnostyce.

Uczenie rankingu TinyCast zapisuje dane związane z zapytaniami. Proponujemy start od deterministycznego rankingu, ulubionych i jawnych aliasów; personalizacja może używać lokalnych liczników aktywacji identyfikatorów aplikacji/poleceń. Trwała historia wpisywanych fraz pozostaje domyślnie wyłączona. Wyszukiwanie schowka nie zasila rankingu aplikacji ani historii kalkulatora.

Zawartość historii pojawia się w dedykowanym trybie Schowek. Ogólne wyniki pokazują polecenie otwarcia tego trybu, bez przypadkowego wyświetlania skopiowanych sekretów podczas szukania aplikacji. Ewentualne wspólne wyniki treści wymagają osobnej opcji.

### Koszt i ograniczenia

To znacząca integracja kilku modułów, ale z ograniczoną liczbą przepływów danych. Najwięcej własnej pracy wymaga bezpieczny magazyn schowka, dostosowanie palety do cyklu życia Mac Managera, PL/EN oraz testy fokusu i uprawnień. Nie obiecujemy zachowania wszystkich funkcji TinyCast jedynie przez adaptację katalogu `Launcher`.

Wariant A daje docelowy wygląd i pełny przepływ lokalnego wyszukiwania. Jest też wspólną podstawą wariantu B.

## Scenariusz B: Mac Manager jako rozbudowany zestaw narzędzi TinyCast

Cel: zakres A i kolejne moduły uruchamiane z tej samej palety. Użytkownik instaluje jedną aplikację, a w ustawieniach wybiera aktywne funkcje. Wyłączone moduły nie uruchamiają obserwatorów, procesów ani odświeżania w tle.

### Dodatkowy zakres

| Grupa | Zawartość i zależności |
| --- | --- |
| Narzędzia lokalne | Notatki, snippets, quicklinks, wyszukiwanie menu aplikacji, przełączanie i układy okien, akcje systemowe, Apple Shortcuts. Część wymaga Dostępności lub Automatyzacji. |
| Integracje systemowe | Kalendarz, spotkania i kamera, włączane osobno ze zgodami systemowymi. Kalendarz może zawierać dane z kont synchronizowanych przez macOS. |
| AI i Quick Actions | Osobno model na urządzeniu, lokalny serwer i zewnętrzny dostawca. Zdalny wariant wysyła wybrany tekst/załączniki do wskazanego dostawcy. Wyłączenie AI Chat musi również pozwalać wyłączyć niezależne Quick Actions. |
| Rozszerzenia Raycast | Instalowanie i wykonywanie obsługiwanego podzbioru rozszerzeń; własne zależności, sieć, OAuth, procesy i mostek do API hosta. Zgodność wymaga macierzy testów konkretnych rozszerzeń. |
| Własne komendy | Zapisywane polecenia shell i argumenty; uruchamianie dopiero przez wyraźną akcję. Pole wyszukiwania nie wykonuje automatycznie wpisanego tekstu jako kodu. |
| Dane sieciowe | Kursy walut/kryptowalut i inne wybrane źródła z ujawnieniem endpointów. Brak wysyłania całej wpisywanej frazy, jeśli wystarczy pobrać wspólną tabelę kursów. |
| Import i eksport | Wybrane ustawienia, aliasy, skróty i dane. Historia schowka wymaga osobnego, szyfrowanego formatu eksportu i świadomego wyboru; klucz urządzenia nie trafia do zwykłego archiwum. Import nie włącza automatycznie uprawnień/modułów. |
| Dodatkowe narzędzia utrzymania | Ewentualny moduł odinstalowywania aplikacji oraz pozostałe funkcje TinyCast wymagają własnego zakresu i odbioru operacji usuwających dane. |

B oznacza przejmowanie możliwości, z zachowaniem tożsamości Mac Managera. Nie przenosimy drugiej aplikacji `@main`, updatera, autostartu, brandingu TinyCast ani jego monitów wsparcia finansowego. Nie deklarujemy, że każde rozszerzenie Raycast zadziała: sam upstream opisuje ograniczenia kompatybilności.

### Warunki zachowania prywatnego schowka

Ten sam szyfrowany magazyn jak w A pozostaje właścicielem historii. AI, quicklinks, snippets i rozszerzenia nie otrzymują automatycznie referencji do całego repozytorium ani pełnej historii. Ewentualne przekazanie wybranego wpisu jest odrębną akcją, z widocznym odbiorcą. Schowek nie staje się domyślnym kontekstem AI.

W TinyCast występują konkretne drogi dostępu wymagające adaptacji: `ExtensionHostBridge` obsługuje schowek, runtime wystawia `fetch`, pliki i procesy, quicklinks mogą podstawiać `{clipboard}` do URL, a snippets odwoływać się do wcześniejszych wpisów. Nasz broker dostępu musi kontrolować te drogi. Sam przełącznik w widoku AI nie jest wystarczający.

Szyfrowanie na dysku nie izoluje dowolnego kodu wykonywanego jako ten sam użytkownik. Jeśli rozszerzenie może uruchomić dowolny proces lub odczytać dowolne pliki, może ominąć ograniczenia naszego API i sięgnąć po systemowy schowek. Oddzielny proces pomocniczy bez ograniczeń systemowych również nie rozwiązuje tego problemu.

Dlatego etap rozszerzeń potrzebuje prototypu rzeczywistej izolacji: ograniczenia plików, sieci i procesów oraz kontrolowanego mostka do hosta. Taka izolacja może wykluczać część rozszerzeń. Alternatywą jest jawny tryb zaufanego kodu z szerszym dostępem; nie wolno opisywać go jako tej samej gwarancji prywatności co wariant A. To warunek decyzji o zakresie B, nie istniejąca właściwość Mac Managera.

Zdalny AI może zachować prywatność całej historii, gdy otrzymuje wyłącznie wybrane dane, ale wybrana wysłana treść opuszcza urządzenie. Włączenie takich usług wymaga jawnego rozszerzenia aktualnych zasad „bez kont” i tabeli dozwolonych połączeń. Nie wynika ono automatycznie z prośby o dwa scenariusze.

### Koszt i ograniczenia

B to kilka kolejnych wydań i istotnie szersze utrzymanie: połączenia dostawców, SDK/runtime rozszerzeń, zgodność macOS, przechowywanie danych dodatkowych modułów oraz znacznie większa macierz testów. Docelowego RAM/CPU nie można wyliczyć przez dodanie deklaracji obu projektów; mierzymy osobno pracę z wyłączonymi modułami i scenariusze obciążenia.

Nie podajemy daty ukończenia przed wydzieleniem zależności i prototypem izolacji. Największą niewiadomą B jest pogodzenie swobody rozszerzeń z wymaganiem prywatności.

## Porównanie

| Kryterium | A: lokalny launcher | B: rozbudowa o pozostałe moduły |
| --- | --- | --- |
| Pasek jak na zrzucie, rozwijane wyniki, klawiatura | Tak | Tak, ten sam komponent |
| Aplikacje, pliki, komendy, kalkulator, schowek | Tak | Tak |
| Szyfrowana historia | Tak | Tak |
| Domyślne przekazywanie schowka do AI | Brak | Brak |
| Zdalny AI i logowania do dostawców | Poza zakresem | Opcjonalne, jawnie konfigurowane |
| Rozszerzenia i dowolny shell | Poza zakresem podstawowym | Osobna granica uprawnień i kompatybilności |
| Zgodność z obecnymi zasadami danych lokalnych | Wysoka | Wymaga jawnych wyjątków dla wybranych usług |
| Złożoność utrzymania | Skupiona na lokalnych API i UI | Dodatkowo dostawcy, procesy, OAuth i kod zewnętrzny |
| Możliwość rozbudowy | Wspólny rdzeń gotowy na B | Rozszerzenie A, bez drugiego magazynu/palety |

## Wpływ na etapy

Etap 2 nadal obejmuje temperatury i RPM. TinyCast nie zastępuje walidacji źródeł sprzętowych.

Zatwierdzona kolejność rozszerzonego etapu 3:

1. **3A: prywatny schowek.** P05, szyfrowanie, retencja, własne zapisy, odmowa zgody i restart.
2. **3B: pełny launcher.** Aplikacje i komendy, ranking/aliasy/ulubione, skróty, pliki, kalkulator, nawigacja i wspólny tryb Schowek. Testy fokusu, IME, działania z ukrytym Dockiem oraz braku emisji zapytań.
3. **3C: wyspa i muzyka.** P07/P06, te same dane schowka, lokalne Music/Spotify i odbiór całego etapu.
4. **Dalsza rozbudowa scenariusza B:** lokalne moduły dodatkowe, następnie opcjonalne integracje AI/sieciowe, a runtime rozszerzeń po prototypie granicy uprawnień. Scenariusz B nie wymaga wymiany wspólnej palety, wyszukiwarki ani repozytorium schowka.

Można wydać A i później rozszerzać go w kierunku B. Wcześniejsze zbudowanie A nie powoduje konieczności przepisania wyszukiwarki: źródła wyników dostarczają moduły przez wspólny kontrakt, a wykonanie komendy sprawdza aktywność modułu i jego uprawnienia. Samo dopasowanie tekstu nie uruchamia efektów ubocznych.

## Kryteria wspólnego odbioru

- Jedna aplikacja, jeden pasek menu, jeden autostart/updater i jedna historia schowka.
- Paleta dostępna skrótem i z paska menu; działa po zamknięciu okna i z ukrytym Dockiem; zamykanie przywraca fokus bez niezamierzonego wklejania.
- Wyszukiwanie aplikacji/poleceń/plików nie wysyła zapytań ani historii na zewnątrz. W B sieć uruchamiają wyłącznie skonfigurowane funkcje zgodnie z ich jawnym kontraktem.
- Filtry poufności, wykluczenia, pauza, trzy limity, brak klucza, uszkodzenie pliku i późne zadania obrazów nie powodują zapisu plaintextu ani samoczynnego kasowania zdrowej historii.
- Kopiowanie z palety, okna i wyspy nie tworzy dodatkowego wpisu ani nie przedłuża jego retencji.
- PL/EN, VoiceOver, Reduce Motion/Transparency, IME i konflikt skrótu sprawdzone w pełnym przepływie.
- Wyłączone moduły nie działają w tle; regresja scrolla, metryk i autostartu oraz pomiar CPU/RAM po integracji.

## Rekomendacja

Zaprojektować wspólny rdzeń pod oba scenariusze i wdrożyć najpierw A. Daje pełny panel, którego oczekuje właściciel, i jedno miejsce codziennej pracy. B rozwijać modułami bez wymiany wyszukiwarki ani magazynu schowka, po określeniu przepływów danych i granic uprawnień. Wybór B nie wymaga rezygnacji z szyfrowania schowka, ale wymaga uczciwego rozróżnienia historii chronionej przez aplikację od dostępu dowolnego kodu uruchamianego na tym samym koncie.

## Źródła

- [Paleta i nawigacja TinyCast](https://github.com/abue-ammar/tinycast/blob/c5cff8cbb9b7e12ac75c058da9573045c76029b7/docs/features/palette.md)
- [Katalog komend](https://github.com/abue-ammar/tinycast/blob/c5cff8cbb9b7e12ac75c058da9573045c76029b7/Tinycast/Features/Launcher/Model/CommandID.swift)
- [Wyszukiwanie plików](https://github.com/abue-ammar/tinycast/blob/c5cff8cbb9b7e12ac75c058da9573045c76029b7/docs/features/file-search.md)
- [AI i osobne ścieżki dostawców](https://github.com/abue-ammar/tinycast/blob/c5cff8cbb9b7e12ac75c058da9573045c76029b7/docs/features/ai.md)
- [Runtime rozszerzeń](https://github.com/abue-ammar/tinycast/blob/c5cff8cbb9b7e12ac75c058da9573045c76029b7/docs/features/extensions.md)
- [Mostek hosta, w tym dostęp do schowka](https://github.com/abue-ammar/tinycast/blob/c5cff8cbb9b7e12ac75c058da9573045c76029b7/Tinycast/Features/Extensions/Service/ExtensionHostBridge.swift)
