# Etap 1, krok 7b - ikona i panel paska menu

Data: 2026-09-08. Stan: zaimplementowany i sprawdzony lokalnie na branchu feat/stage-1. Jest to druga część F1-06.

## Zakres

- `MenuBarExtra` dodaje stałą ikonę Mac Manager do systemowego paska menu i otwiera panel w stylu okna.
- Zwarta etykieta korzysta z symbolu `macbook`. Domyślnie nie pokazuje tekstu.
- Użytkownik może niezależnie włączyć CPU, RAM i moc w W obok ikony. Kolejność pozostaje stała: CPU, RAM, W.
- CPU i RAM są prezentowane jako zaokrąglone wartości procentowe. Moc ma jedno miejsce po przecinku. Brak odczytu jest oznaczony znakiem `-`, bez fikcyjnego zera.
- Panel pokazuje bieżące CPU, GPU, RAM i moc, lokalny oraz publiczny IPv4, stan scrolla i przyciski do otwarcia głównego okna, Ustawień oraz zakończenia aplikacji.
- Adresy IPv4 można kopiować bez przechodzenia do głównego okna.
- Panel i przyciski korzystają z natywnych stylów Liquid Glass dostępnych w macOS 26.
- Sekcja Ustawień udostępnia trzy niezależne przełączniki. Wybór jest zapisywany w `UserDefaults` i działa po ponownym uruchomieniu.

## Zachowanie przy ograniczonej szerokości

Wartości są składane w jeden tekst etykiety, ponieważ `MenuBarExtra` może upraszczać układ złożony z wielu osobnych widoków. macOS nadal decyduje o dostępnej szerokości paska, szczególnie na ekranie z notchem i przy dużej liczbie ikon. Priorytet wynika z kolejności CPU, RAM, W.

## Weryfikacja

- 39 testów MacManagerCore przechodzi, w tym formatowanie wybranych wskaźników, ich kolejność i brak dostępnej wartości.
- 7 scenariuszy XCTest UI przechodzi, w tym domyślnie wyłączone wartości, niezależne włączenie CPU/RAM/W i odtworzenie ustawień po restarcie.
- Debug build aplikacji dla arm64 i macOS 26 przechodzi.
- String Catalog kompiluje polskie i angielskie treści panelu.

## Następna część

Sterowanie widocznością Docka i ponowne otwieranie głównego okna wdrożono w [kroku 7c](etap-1-krok-7c.md). Pozostała część F1-06 obejmuje autostart przez `SMAppService.mainApp`, przeniesienie startu usług na poziom procesu oraz scenariusze uruchomienia ręcznego i przy logowaniu.
