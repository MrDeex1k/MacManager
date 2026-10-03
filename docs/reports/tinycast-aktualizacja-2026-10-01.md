# Przegląd aktualizacji Tinycast

Analiza: 2026-10-01. Branch Mac Managera: `feat/stage-3b-launcher`.

Porównano naszą bazę `c5cff8cbb9b7e12ac75c058da9573045c76029b7` z pobranym HEAD `c0ec714f33017e4afcd9dbb6cdf04af87ecad306`: 104 dodatkowe commity. Daty części commitów upstream wskazują 2026-10-02; zakres identyfikują hashe, nie założenie o poprawności zegara autora. Przejrzano historię oraz kod zmian istotnych dla obecnego launchera. Nie jest to audyt wszystkich funkcji Tinycast.

## Kandydaci do adaptacji

| Priorytet | Zmiana upstream | Znaczenie dla Mac Managera |
| --- | --- | --- |
| Wysoki | [Format 12/24 h w kalkulatorze](https://github.com/abue-ammar/tinycast/commit/2dab27b72bfef39d9a5ce59f4341555fed01a1f7) | Nasz kalkulator ma odziedziczone formaty `h:mm a`. Upstream stosuje lokalizowane szablony `jmm`/`jmmss` i uwzględnia cykl godzinowy w kluczu cache. Mała zmiana możliwa do przeniesienia bez historii obliczeń ani usług sieciowych. |
| Wysoki | [Usuwanie skrótów odinstalowanych aplikacji](https://github.com/abue-ammar/tinycast/commit/34664f7bde719c8f458dd8e996c91422db1be632) | Nasze personalizacje pozostają edytowalne, ale skrót usuniętej aplikacji może nadal zajmować kombinację. Przy adaptacji trzeba potwierdzić brak aplikacji również przez LaunchServices, nie tylko nieobecność w ograniczonym katalogu wyszukiwania. |
| Wysoki, osobna zmiana | [Nowy ranking](https://github.com/abue-ammar/tinycast/commit/d93a09baac74da20a10dedf00b92834ce4c49b04) i [granice camelCase, aliasy, nazwy paneli](https://github.com/abue-ammar/tinycast/commit/03f58a5df0e57ea78aa95e5d4dc1aafdd3b61958) | Warto przenieść lepsze rozpoznawanie początku słów, np. `Stack` w `OrbStack`, oraz ocenę nazw i aliasów. To przebudowa kilku modułów, nie podmiana jednego pliku. Nasze aliasy już uczestniczą w wyszukiwaniu. Liczniki uruchomień i Suggestions zmieniałyby obecne zachowanie, więc wymagają osobnej decyzji. |
| Opcjonalny | [thousand / million / billion](https://github.com/abue-ammar/tinycast/commit/a3e352227df9d3b7b7406d5a1377b9694bb5b97d) | Niewielkie rozszerzenie tokenizera kalkulatora wraz z przypadkami regresji, zgodne z obecną angielską składnią. |
| Opcjonalny | [Kopiowanie całego obliczenia](https://github.com/abue-ammar/tinycast/commit/03e74d2a20abaaecb2c172af9fba67f9de8a895b) | Shift + Command + Enter może kopiować wyrażenie i wynik. Obecne Enter kopiujące sam wynik powinno pozostać bez zmian. |

Rekomendowana kolejność: format czasu, zwalnianie nieaktualnych skrótów, następnie selektywna adaptacja rankingu z porównaniem wyników PL/EN. Nowych mechanizmów Tinycast nie włączono automatycznie w ramach tego przeglądu.

## Zmiany bez bezpośredniego zastosowania

- [Obsługa nazwanych klawiszy w odzyskiwaniu ASCII](https://github.com/abue-ammar/tinycast/commit/f2a27d7d5ac8b3082b70b3efabd3fc560cbce2cc) dotyczy innej ścieżki zdarzeń. Nasze skróty Carbon korzystają z fizycznych kodów klawiszy, a paleta osobno respektuje kompozycję IME.
- [Nazwy aplikacji z lokalizacji zh-Hans](https://github.com/abue-ammar/tinycast/commit/afb388070efea12692d8f883f80e86e8588aef75) nie są obecnie wymagane przez zakres PL/EN.
- [Ujednolicenie ikon list](https://github.com/abue-ammar/tinycast/commit/f507b4ac9849414e73173aa26caa21a19203345e) zależy od cache i stylów Tinycast. Nasza lista już ma stały rozmiar ikon; ewentualny cache wymaga najpierw pomiaru.
- Integracje AI, Rooms, CLI i synchronizacja ustawień wykraczają poza obecny zakres. Nie stanowią zależności aktualizacji launchera.

## Wdrożona zmiana skrótów

Dodano `⌥` jako samodzielny zestaw modyfikatorów. Można ustawić Option + literę albo Spację zarówno dla palety, jak i personalizacji pozycji. Domyślny Control + Option + Spacja oraz istniejące ustawienia pozostają zachowane. Zmiana nie dodaje nowych uprawnień.

Test Core walidacji, etykiety i trwałości ustawienia Option + K przeszedł. Test GUI wyboru Option + Spacja oraz otwarcia palety z Findera przy zamkniętym głównym oknie także przeszedł. Wcześniejsze automatyczne próby Option + K nie otworzyły palety; nie potwierdzono w nich poprawnego wysłania fizycznego klawisza przez narzędzie testowe. Nie stanowią potwierdzenia działania tej konkretnej kombinacji na rzeczywistej klawiaturze. Skróty są fizyczne: kombinacja zajęta przez system lub inną aplikację może wymagać wyboru innego klawisza.
