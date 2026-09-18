# Etap 1, krok 7c - sterowanie Dockiem i oknem

Data: 2026-09-08. Stan: zaimplementowany i sprawdzony lokalnie na branchu feat/stage-1. Jest to trzecia część F1-06.

## Zakres

- `DockController` stosuje zapisaną preferencję po uruchomieniu cyklu życia aplikacji. Widoczność jest dodatkowo ograniczona do czasu, gdy główne okno jest otwarte.
- Widoczny Dock używa polityki aktywacji AppKit `.regular`, a ukryty Dock używa `.accessory`.
- Zmiana działa od razu. Preferencja jest zapisywana dopiero wtedy, gdy macOS przyjmie nową politykę aktywacji.
- Domyślnie ikona Docka jest widoczna, zgodnie z wymaganiem produktu.
- Zamknięcie głównego okna automatycznie ukrywa ikonę Docka i nie wpływa na `MenuBarExtra`, dlatego użytkownik zachowuje drogę do panelu, ponownego otwarcia okna i zakończenia aplikacji.
- Ustawienia pokazują przełącznik Docka, krótki opis zachowania oraz jawny błąd, jeśli system odrzuci zmianę.
- Zamknięcie ostatniego okna nadal nie kończy procesu.
- Akcje w panelu paska menu i skróty aplikacji otwierają pojedyncze główne okno oraz wybierają właściwą sekcję.
- Ponowne otwarcie okna z paska menu przywraca ikonę Docka, jeśli użytkownik ma włączoną jej widoczność, i aktywuje istniejące główne okno.

## Weryfikacja

- Scenariusz XCTest UI sprawdza domyślnie widoczny Dock przy otwartym oknie, natychmiastową zmianę, trwałość ustawienia po restarcie, zamknięcie okna bez zakończenia procesu i ponowne otwarcie przez komendę aplikacji. Próba systemowa potwierdza przejście procesu z typu `Foreground` do `UIElement` po Command-W.
- Pełny zestaw obejmuje teraz 8 scenariuszy XCTest UI.
- 39 testów MacManagerCore pozostaje zielonych.
- Debug build aplikacji dla arm64 i macOS 26 przechodzi, a String Catalog kompiluje polskie i angielskie treści.

## Granice

Autostart nie jest jeszcze rejestrowany. Jego implementacja musi użyć `SMAppService.mainApp`, pokazywać rzeczywisty stan macOS i rozróżniać zwykłe uruchomienie od startu przy logowaniu.

## Następna część

Autostart przez `SMAppService.mainApp`, przeniesienie startu usług na poziom procesu oraz scenariusze uruchomienia ręcznego i przy logowaniu wdrożono w [kroku 7d](etap-1-krok-7d.md).
