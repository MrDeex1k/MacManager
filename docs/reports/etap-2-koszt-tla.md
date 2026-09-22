# Etap 2: koszt pracy w tle

Data pomiaru: 2026-09-22.

## Warunki

- Zainstalowany `/Applications/MacManager.app`, wersja 0.8.0, działający proces po zamknięciu głównego okna. Pasek menu i pozostałe usługi aplikacji były aktywne.
- MacBook Pro z Apple M4 Pro i 24 GB RAM, macOS 27.0 (26A428).
- Interwał pomiarów aplikacji: 2 s. Po zamknięciu okna odczekano 15 s, następnie pobrano 61 próbek procesu co 10 s przez 600 s.
- `ps` dostarczył bieżące `%CPU`, RSS i skumulowany czas CPU. Średni koszt CPU obliczono przede wszystkim z przyrostu skumulowanego czasu, aby krótkie skoki odczytu `%CPU` nie dominowały wyniku.

| Miara | Wynik |
| --- | ---: |
| Czas CPU procesu | 15,28 s -> 29,31 s, przyrost 14,03 s |
| Średni koszt CPU z czasu procesu | 2,338% jednego rdzenia |
| Średnia z chwilowych odczytów `%CPU` | 3,038% jednego rdzenia |
| Zakres chwilowych odczytów `%CPU` | 0,0-13,1% |
| Średni RSS | 127,53 MiB |
| Zakres RSS | 101,42-141,58 MiB |
| RSS początkowy -> końcowy | 141,47 -> 104,00 MiB |

Proces działał przez cały pomiar. RSS spadł o 37,47 MiB; w tej 10-minutowej próbie nie widać narastania pamięci. Krótka próba nie zastępuje długotrwałego testu pamięci.

W [pomiarze etapu 1](etap-1-krok-9a.md) średnia z chwilowych odczytów CPU wynosiła 0,413% po poprawce usuwającej niewidoczne wykresy z drzewa SwiftUI. Obecny odczyt 3,038% jest wyższy, a średnia z czasu procesu przekracza wcześniejszy cel poniżej 1% jednego rdzenia. To porównanie ma charakter orientacyjny: poprzedni pomiar wykonano na macOS 26.6.2, przed dodaniem czujników i ich historii oraz przy innym stanie konfiguracji paska menu. Mierzyliśmy cały proces, więc nie można przypisać różnicy wyłącznie odczytom AppleSMC.

Wynik wskazuje potrzebę profilowania i ograniczenia kosztu CPU przed zamknięciem odbioru etapu 2. Pomiar nie obejmuje bezpośrednio poboru energii w watach ani czasu pracy na baterii. Surowy CSV znajduje się tylko w katalogu tymczasowym maszyny testowej i nie jest dodawany do repozytorium.
