# Ograniczenie pamięci schowka - 2026-10-12

Branch: `feat/battery-optimization`. Zmiana dotyczy schowka i trybu schowka w launcherze; nie zmienia retencji ani zawartości systemowego schowka.

## Zachowanie

- Lista przechowuje metadane, źródło i podgląd do 300 znaków, z dodatkowym ograniczeniem wejścia do 1200 bajtów UTF-8. Nie trzyma pełnych tekstów ani danych miniatur wszystkich wpisów.
- Szczegóły pobierają pełny tekst lub obraz dopiero po otwarciu. Przywrócenie nadal zapisuje oryginalną treść do systemowego schowka.
- Miniatury są odczytywane na żądanie. Zdekodowane obrazy pozostają w widocznych wierszach; zniknięcie wiersza zwalnia jego lokalny podgląd. Schowek i launcher nie mają osobnych cache obrazów.
- Jeden cache danych odszyfrowanych ma budżet 16 000 000 bajtów, wspólny dla treści i miniatur. Przy braku miejsca usuwa najdawniej używane dane (LRU). Wpis większy od budżetu można otworzyć lub przywrócić, ale nie trafia do cache.
- Wyszukiwanie pozostaje pełnotekstowe, poza wątkiem UI. Czyta kolejno pojedyncze zaszyfrowane treści, sprawdza anulowanie i nie zapełnia cache skanowaną historią. Nie powstaje dodatkowy indeks tekstu jawnego na dysku.
- Blokada sesji usuwa podglądy listy, anuluje wyszukiwanie i czyści cache. Odczyt treści jest zablokowany do wznowienia. Usunięcie wpisu, retencja i wyczyszczenie historii usuwają odpowiadające dane cache.
- Nowe pliki podglądu mają format v2 z krótkim tekstem. Format v1 jest nadal czytelny i skracany podczas ładowania, bez utraty pełnej treści w pliku payload.

## Granice

16 MB jest limitem cache danych, a nie całkowitej pamięci procesu. Metadane, krótkie podglądy, dane przetwarzane podczas odczytu, zdekodowane widoczne obrazy oraz aktualnie otwarte szczegóły potrzebują dodatkowego RAM. Zwalnianie referencji nie gwarantuje fizycznego zerowania pamięci ani natychmiastowego spadku RSS. Wyszukiwanie dużej historii może wymagać więcej odczytów dysku; nie utrzymuje całej odszyfrowanej historii w pamięci.

## Weryfikacja

- 112 testów Core w konfiguracji Release: zgodność starego formatu, ograniczenie podglądu (także Unicode), pełnotekstowe wyszukiwanie, kolejność/limit/anulowanie, odczyt obrazów na żądanie, LRU, usuwanie i czyszczenie po blokadzie.
- Dwa istniejące testy GUI w konfiguracji Debug przeszły: wyszukiwanie/przywrócenie/retencja/czyszczenie oraz współdzielony tryb schowka w launcherze. Testy używają osobnego schowka i katalogu danych.
- Kompilacja aplikacji Release arm64.

Pierwszą próbę GUI uruchomiono błędnie w Release, który nie aktywuje izolowanych fixture testowych; nie znaleziono wtedy wpisów testowych. Właściwa próba w Debug przeszła. Nie mierzono spadku RSS całego procesu ani kosztu skanowania maksymalnej historii na dysku.

## Poprawki review PR #8

Błąd wyszukiwania kończy bieżące żądanie i pokazuje istniejący komunikat PL/EN z możliwością ponowienia. Anulowane lub nieaktualne zadanie nie może zastąpić wyników nowszego żądania. Repozytorium sprawdza anulowanie przed otwarciem bazy i odczytem klucza. Osobna poprawka scrolla używa stałej `kCGSessionOnConsoleKey` z SDK podczas ustalania początkowego stanu sesji.

Weryfikacja: 113 testów Core Release, w tym nowa regresja anulowania przed utworzeniem magazynu; końcowy build Release arm64; istniejący test GUI schowka (wyszukiwanie, przywracanie, retencja i czyszczenie) w Debug. Wszystkie przeszły. Test GUI jest kontrolą regresji zwykłego przepływu, nie symulacją awarii klucza ani zmiany użytkownika systemu.
