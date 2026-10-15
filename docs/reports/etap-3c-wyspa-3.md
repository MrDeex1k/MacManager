# Etap 3C: wyspa, krok 3 - wspólny schowek

Data: 2026-10-13. Zakres: czytelny schowek w istniejącym czarnym panelu wyspy. Muzyka i animowane przejścia pozostają osobnymi krokami.

## Wdrożone zachowanie

- `AppState` przekazuje wyspie dokładnie tę samą instancję ClipboardService co launcherowi i oknu. Nie powstał drugi magazyn, obserwator pasteboardu ani harmonogram przechwytywania.
- `IslandClipboardModel` przechowuje wyłącznie stan prezentacji: zapytanie, wyniki wyszukiwania, zaznaczenie, operację przywracania i krótkie potwierdzenie. Puste zapytanie pokazuje najnowsze wpisy usługi. Zapytania korzystają z istniejącego asynchronicznego wyszukiwania pełnych treści; identyfikator zapytania obejmuje frazę, rewizję historii i zawieszenie. Nieaktualne wyniki nie są widoczne ani wykonywalne.
- Lista używa LazyVStack i wspólnego ClipboardThumbnailView. Pokazuje miniatury obrazów, fragmenty tekstu do 200 znaków, maksymalnie dwie linie i godzinę wpisu. Panel ma stałą wysokość 340 punktów treści plus obszar kamery; przewijanie listy nie rozszerza okna.
- Kliknięcie wpisu albo Enter przywraca go do systemowego schowka, bez symulowania ⌘V. Strzałki wybierają wpis. Stopka przez dwie sekundy pokazuje „Skopiowano”, a wiersz znacznik sukcesu. Panel pozostaje otwarty. Usunięcie wpisu działa na wspólnej historii; dostępne są też włączenie, pauza/wznowienie i świadoma prośba o dostęp przy brakującej zgodzie.
- Historia nie włącza się automatycznie przez otwarcie wyspy. Stany wyłączony, pauza, blokada, brak zgody, błędy magazynu i brak wyników są jawne. Uszkodzonych wpisów nie można przywrócić.
- Zamknięcie, zawieszenie i zmiana zapytania anulują oczekujące przywracanie oraz potwierdzenie. ClipboardService sprawdza anulowanie przed odczytem i przed zapisem do pasteboardu, a także obecność wpisu po odczycie. Zamknięty panel zwalnia wyniki, miniatury i zapytanie.

## Weryfikacja

- Pełny zestaw Core: 124 testy zakończone powodzeniem, w tym nowy przypadek anulowanego przywracania bez zapisu i bez duplikatu.
- Trzy testy GUI obejmują ograniczoną geometrię i ponowne otwarcie przez hover, pisanie/Escape/powrót fokusu oraz wspólny schowek: wyszukiwanie tekstu, przywracanie, zgodny UUID w pełnym oknie, usuwanie widoczne w obu powierzchniach, czyszczenie zapytania i przywrócenie obrazu. Dodatkowy przebieg schowka sprawdza przywracanie tekstu klawiszem Enter.
- Dane testowe są syntetyczne: tekst wielowierszowy, Unicode i PNG. Testy korzystają z osobnych preferencji, repozytorium z kluczem efemerycznym i nazwanego pasteboardu; nie odczytują ani nie zastępują prywatnego schowka użytkownika.
- Debug i Release arm64. Zrzut panelu z XCTest służy kontroli czytelności i miniatur.

## Pozostały odbiór

Nie zamykamy całej macierzy P07 ani całego 3C. Pozostają VoiceOver, pełne IME, wiele ekranów/clamshell, fizyczne sleep/lock/wake i pomiar Instruments. Sam test jednostkowy/GUI nie stanowi dowodu kosztu energetycznego.

Build Release z krokiem 3 zainstalowano i uruchomiono w `/Applications/MacManager.app`, używając stałego certyfikatu Developer ID i tego samego bundle ID przez scripts/install-local-app.py. Instalator potwierdził zgodność designated requirement z poprzednią kopią. Nie zmieniał ustawień, historii, klucza schowka ani TCC. Dalsza kolejność: krok 5, potem odtwarzacz (krok 4 w 3D).
