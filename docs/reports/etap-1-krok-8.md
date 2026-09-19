# Raport etapu 1, kroku 8 - aktualizacje, prywatność i diagnostyka

Data odbioru: 2026-09-12.

Krok 8 został odebrany. Aplikacja sprawdza stabilne GitHub Releases zgodnie z harmonogramem, pokazuje lokalną diagnostykę i nie dodaje telemetrii ani automatycznego eksportu danych.

## Zakres odbioru

| Obszar | Wynik |
| --- | --- |
| Wersje i wydania | Ścisły format `vMAJOR.MINOR.PATCH`, odrzucanie draftów, prerelease, błędnych tagów, niezgodnych stron i wydań bez przesłanego DMG arm64. |
| Harmonogram | Pierwsza kontrola oraz kolejne kontrole najwyżej raz na 7 dni. Wyłączenie automatycznej kontroli pomija zapytanie, a kontrola ręczna ma osobny limit 60 s. |
| Cache i ETag | Poprawne zachowanie po `304 Not Modified`, trwałość cache i odrzucanie niespójnych danych zapisanych lokalnie. |
| Błędy | Obsłużone stany offline, timeout, limit API, błąd serwera, inny HTTP, błędna odpowiedź i błąd transportu. Znane poprawne wydanie pozostaje w cache po błędzie. |
| Interfejs | Sprawdzone stany: aktualna wersja, dostępna wersja, brak publicznego wydania, błąd i offline. Dostępna wersja oraz offline zostały zweryfikowane po polsku i angielsku. |
| Diagnostyka | Raport zawiera kontrolowane informacje o aplikacji i usługach. Nie zawiera adresów IP, treści użytkownika ani surowych opisów błędów. |
| Prywatność | Produkcyjny ruch ogranicza się do `api.ipify.org`, GitHub API i strony wydania otwieranej po akcji użytkownika. Nie znaleziono telemetrii, kont, reklam ani wysyłania metryk. |

## Znaleziona i usunięta usterka

Odbiór wykrył, że pierwsze wywołanie `setOnline(false)` nie zmieniało stanu z `neverChecked` na `offline`, ponieważ metoda kończyła działanie, gdy poprzednia wartość `isOnline` również była fałszywa. Usunięto to przedwczesne zakończenie. Test jednostkowy oraz uruchomiona aplikacja potwierdzają teraz komunikat o braku połączenia od pierwszego rozpoznania stanu offline.

## Wyniki techniczne

- `swift test --package-path Packages/MacManagerCore`: obecny zestaw 52 testów zakończony powodzeniem.
- `xcodebuild ... build-for-testing`: aplikacja i 13 scenariuszy UI kompilują się poprawnie dla macOS arm64.
- `xcodebuild ... -configuration Release build`: build zakończony powodzeniem; plik wykonywalny zawiera wyłącznie architekturę arm64.
- Lokalny odbiór przez interfejs Dostępności potwierdził pięć stanów aktualizacji oraz polskie i angielskie teksty.
- Testy parsera korzystają z syntetycznych odpowiedzi GitHub dla poprawnego wydania, wersji bieżącej i starszej, draftu, prerelease, braku DMG, błędnego assetu, kodów HTTP i uszkodzonego payloadu.

Pełne uruchomienie XCTest UI zatrzymał systemowy monit macOS wymagający uwierzytelnienia do włączenia automatyzacji interfejsu. Runner nie rozpoczął testów, więc zachowanie nowych scenariuszy sprawdzono bezpośrednio w lokalnym buildzie przez AppKit Accessibility. Zestaw XCTest został skompilowany i pozostaje gotowy do ponownego uruchomienia po zatwierdzeniu systemowego monitu.

## Granice kroku

Krok 8 nie publikuje wydania i nie pobiera aktualizacji wewnątrz aplikacji. Sprawdzenie prawdziwego opublikowanego Release, podpis Developer ID, notarization, gotowy DMG, Gatekeeper i pełna macierz odbioru należą do kroku 9.
