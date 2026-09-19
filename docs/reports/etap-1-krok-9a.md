# Etap 1, krok 9 - testy automatyczne, dostępność i praca w tle

Data weryfikacji: 2026-09-18.

Ten raport zamyka punkty 1, 2, 4 i 5 uzgodnionej części testowej kroku 9. W punkcie 2 potwierdzono metryki, historię, sieć, cykl życia okna, sleep/wake i rozróżnianie myszy od gładzika na urządzeniu referencyjnym. Punkt 3, czyli autostart z zainstalowanej aplikacji, zostaje do osobnej sesji. Podpis Developer ID, notarization i publiczny DMG nadal należą do końcowego odbioru wydania.

## Środowisko

- MacBook Pro z Apple Silicon i 24 GB RAM.
- macOS 26.6.2, build 25G83.
- Xcode 26.4, SDK macOS 26.5.
- Buildy Debug i Release arm64.
- Domyślny interwał pomiarów 2 s.

## Testy automatyczne

Pełny zestaw obejmuje 51 testów `MacManagerCore`, 9 testów prototypów i 14 scenariuszy XCTest UI. Scenariusze UI sprawdzają nawigację, PL/EN, pomiary i wykresy, scroll, pasek menu, Dock, cykl życia okna, start przy logowaniu, aktualizacje i diagnostykę.

Pełne uruchomienie wykryło wyścig przy pierwszym otwarciu okna po starcie jako login item. Okno mogło powstać przed rejestracją obserwatora `didBecomeKey`, przez co pozostawał pusty kontener. Akcje otwierające z menu i paska menu ustawiają teraz widoczność przed wywołaniem `openWindow`. Dodatkowe testy regresji startu w tle oraz zamknięcia i ponownego otwarcia okna przechodzą.

Dwa polskie oczekiwania UI zostały dopasowane do zatwierdzonych etykiet aplikacji: `Otwórz wydanie` i `Kopiuj raport`.

## Dostępność

Dodany audyt XCTest przechodzi kolejno przez Przegląd, Sieć, Scroll, Dock i Ustawienia. Sprawdza:

- kontrast,
- wykrywanie elementów,
- rozmiar obszarów interakcji,
- opisy elementów,
- dostępne akcje,
- relacje rodzic-dziecko.

Audyt wykrył zbyt słaby kontrast stopki paska bocznego oraz opisów metryk. Oba miejsca otrzymały jaśniejszy tekst i większą wagę fontu. Test odfiltrowuje wyłącznie powtarzalne artefakty frameworka: anonimowe grupy układu `NavigationSplitView`, rolę wierszy `NavigationLink`, akcję natywnych `Picker`, kontener systemowego przycisku okna i nieaktywny `TouchBar`. Kontrolki potomne nadal przechodzą pełny audyt.

Istniejące scenariusze potwierdzają obsługę klawiatury przez skróty Command-1, Command-2 i Command-, oraz zmianę języka PL/EN. Aplikacja nie zawiera własnych animacji ani przejść omijających ustawienie Reduce Motion. Korzysta z natywnych materiałów SwiftUI i stałego ciemnego tła, więc Reduce Transparency zachowuje systemowe zachowanie bez utraty treści.

## Pomiar pracy w tle

Pierwszy pomiar builda Release przy zamkniętym oknie ujawnił, że niewidoczne wykresy Swift Charts nadal przeliczały układ po każdej próbce metryk:

| Wariant | Próbki | Czas | Średnie CPU | Zakres CPU | Średni RSS | Zakres RSS | Zmiana RSS | Wątki |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Przed poprawką | 61 | 602 s | 5,198% | 0,3-21,5% | 101,26 MB | 97,39-111,80 MB | -12,36 MB | 7-9 |
| Po poprawce | 61 | 602 s | 0,413% | 0,0-5,9% | 96,81 MB | 94,83-114,59 MB | -19,73 MB | 6-9 |

`AppShellView` usuwa teraz zawartość głównego okna z drzewa SwiftUI po jego zamknięciu i odtwarza ją przy ponownym otwarciu. Usługi procesu, pasek menu i zbieranie metryk pozostają aktywne. Średnie użycie CPU spadło około 12,6 raza i spełnia cel poniżej 1% jednego rdzenia. Pamięć oraz liczba wątków nie wykazują wzrostu w badanym oknie.

Pliki CSV powstały w katalogu tymczasowym maszyny testowej i nie trafiają do repozytorium. Pomiar 8-godzinny pozostaje osobnym kryterium przed stabilnym wydaniem publicznym.

## Ręczna próba na urządzeniu referencyjnym

Build Release uruchomiono z rzeczywistymi zgodami Dostępności i Monitorowania wprowadzania. Potwierdzono:

- bieżące wartości CPU, GPU, RAM i mocy oraz zapis historii podczas kontrolowanego obciążenia CPU,
- utrzymanie próbkowania i historii po zamknięciu okna oraz poprawne ponowne otwarcie z paska menu,
- podstawowy lokalny i publiczny IPv4 oraz ostrożne oznaczanie interfejsów tunelowych bez przypisywania ich do konkretnych aplikacji,
- usunięcie nieaktualnych adresów po odłączeniu sieci i automatyczny powrót adresów po ponownym połączeniu; publiczny IPv4 może pojawić się później niż lokalny, ponieważ wymaga osobnego żądania zewnętrznego,
- odwracanie pionowego i poziomego ruchu myszy przy zachowaniu naturalnego kierunku gładzika,
- automatyczną zmianę klasyfikacji między myszą i gładzikiem bez listy modeli urządzeń,
- wznowienie pomiarów, panelu paska menu i scrolla po fizycznym uśpieniu oraz poprawną przerwę w historii bez łączenia próbek sprzed uśpienia z nowymi.

Próba scrolla ujawniła, że pasywna obserwacja gestów uruchomiona na wątku roboczym nie dostarczała stabilnie danych dotyku z AppKit. Zdarzenia gładzika trafiały wtedy do bezpiecznego fallbacku myszy i były odwracane. Obserwacja gestów działa teraz na głównej pętli AppKit, a osobny tap modyfikujący zdarzenia pozostaje na wątku roboczym. Powtórzona próba sprzętowa potwierdziła poprawne zachowanie obu urządzeń.

## Stan odbioru

Punkty 1, 2, 4 i 5 tej części kroku 9 są wykonane. Punkt 2 został odebrany na urządzeniu referencyjnym. Szersza macierz modeli Apple Silicon pozostaje udokumentowanym ograniczeniem walidacji przed stabilnym wydaniem publicznym i wymaga dostępu do dodatkowych Maców. Punkt 3 pozostaje otwarty. Cały krok 9 zostanie zamknięty dopiero po próbie autostartu z instalacji i przygotowaniu podpisanego, notarized DMG.
