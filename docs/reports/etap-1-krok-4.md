# Etap 1, krok 4 — historia i wykresy

Data: 2026-09-08. Branch: feat/stage-1. Zakres: F1-03, po wdrożonych krokach 5 i 3.

## Implementacja

- MetricsHistory w lokalnym Core przechowuje snapshoty tylko w RAM, w oknie (teraz − 300 s, teraz]. Retencja zależy od czasu, więc 1/2/5 s zmienia gęstość próbek, a nie długość historii. Restart rozpoczyna pustą historię.
- Wspólny MetricsService zapisuje wyniki istniejącego samplera. Widoki i wybór metryki nie uruchamiają odczytów. Kontroler usuwa wygasłe dane co sekundę, również bez nowych wyników.
- MetricsTime korzysta z mach_continuous_time: sen wlicza się w pięć minut, zmiana daty lub strefy czasowej nie wpływa na retencję. Sleep/wake przerywa serie, unieważnia trwający odczyt i resetuje bazę CPU. Po długim uśpieniu historia jest pusta; nie nadrabiamy próbek.
- Brak dostępnej wartości przerywa tylko serię danej metryki. Przerwa większa niż 1,5 poprzedniego interwału, zmiana źródła lub interwału również zaczyna nowy segment. Poprawne zero pozostaje pomiarem; unavailable/stale/failed nie zamieniają się w zero ani w powtórzenie ostatniej wartości.
- Zmiana interwału odrzuca wynik rozpoczęty ze starym ustawieniem. Nowy odczyt czeka na zakończenie poprzedniego, nawet gdy adapter nie reaguje na anulowanie.
- Skrót do szczegółów sieci przeniesiono do nagłówka Przeglądu, aby pozostał dostępny bez przewijania po dodaniu wykresu.
- Przegląd zawiera Swift Charts z wyborem CPU/GPU/RAM/mocy, stałą osią −5 min…Teraz, minimum/maksimum i liczbą dostępnych próbek. CPU/GPU mają skalę 0–100%, RAM pokazuje GiB. Punkty zapewniają widoczność pojedynczego odczytu; linie nie łączą segmentów.
- Moc pozostaje niedostępna zgodnie z wynikiem kroku 3. Jej wybór pokazuje wyjaśnienie, bez sztucznego 0 W. Treści są dostępne w PL i EN. Brak nowych uprawnień, pakietów zewnętrznych, połączeń sieciowych i zapisu historii na dysku.

## Weryfikacja

Środowisko: Apple M4 Pro, macOS 26.6.2, Xcode 26.6, arm64.

- 22 testy Core: dotychczasowa logika metryk/sieci/ustawień oraz siedem nowych scenariuszy historii i zmiany interwału. Obejmują granicę 300 s przy każdym interwale, wygasanie bez nowych odczytów, brak metryki przy poprawnej innej serii, prawidłowe zero, luki, zmianę źródła/interwału, uśpienie, zmianę czasu kalendarzowego, niepoprawne znaczniki czasu i odrzucenie spóźnionego wyniku.
- Debug i Release: build zakończony powodzeniem. Końcowy pełny przebieg XCTest UI: 3 scenariusze, 0 błędów.
- Testy XCTest UI: nawigacja i pusta historia, natychmiastowa zmiana języka i restart, żywe lokalne pomiary oraz wybór RAM/mocy/CPU i trwały interwał. Testy zatrzymują usługi sieciowe i izolują preferencje.
- Zrzuty własnego okna aplikacji służą do sprawdzenia skali, opisów i układu PL/EN. Pierwszy przebieg ujawnił niedostępny dla XCTest komunikat wewnątrz chartOverlay; przeniesiono go do zwykłej nakładki SwiftUI.

## Granice odbioru i następny krok

Testy zegara i powiadomień symulują czas oraz uśpienie; nie są dowodem fizycznego zamknięcia klapy i wznowienia na każdym Macu. Ręczna macierz sleep/wake, VoiceOver, ustawień dostępności oraz pomiar narzutu długiej sesji pozostają w odbiorze etapu 1. Nie zmieniano ustawień systemowych ani nie usypiano komputera użytkownika podczas pracy.

Następny jest krok 6: wiarygodna klasyfikacja myszy/gładzika i odwracanie scrolla. Pole continuous z prototypu nie wystarcza na urządzeniach właściciela. Etap 1 nie jest jeszcze ukończony; brak publicznego wydania DMG.
