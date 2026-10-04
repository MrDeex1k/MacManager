# Optymalizacje pracy w tle - 2026-10-05

Branch: `codex/battery-optimizations-4-8`. Wersja aplikacji: 0.8.1, build 9.

## Zakres

Wdrożono punkty 4-8 z analizy zużycia baterii. Bez adaptacyjnego profilu zasilania, ograniczania zestawu zbieranych metryk ani zmiany obsługi sieci (punkty 1-3).

- Metryki: harmonogram zgodny z wybranym interwałem 1/2/5 s, bez dodatkowego sekundowego przesuwania historii. Zmiana interwału i wznowienie uruchamiają próbkę od razu. Pauza zatrzymuje pętlę. Kontrola świeżości pozostaje aktywna w rytmie próbek także przy wolnym odczycie sterownika.
- Scroll: callback stanu event tap, brak okresowego sprawdzania wyłączonej funkcji. Kontrola awaryjna i watchdog wątku co 30 s; podczas oczekiwania na uprawnienia kontrola co 2 s. Powrót do aplikacji odświeża uprawnienia. Kolejkowany stop run loopa obsługuje zatrzymanie tuż przed rozpoczęciem oczekiwania oraz przerwania zgłaszane callbackiem. Zachowano ograniczenie liczby prób odzyskania event tap i wymóg jawnego retry po błędzie.
- Sprzęt: jedna ponownie używana sesja SMC w actorze; cache metadanych kluczy i ich kodów; unieważnianie metadanych po błędzie odczytu, odtworzenie sesji po całkowitej utracie odczytów oraz przy resecie samplera. RAM korzysta z cache fizycznego rozmiaru pamięci i systemowego `vm_page_size`. Wartości odczytów nadal są pobierane na bieżąco. Wyszukiwanie GPU pozostaje bez zmian; utrwalanie jego uchwytu nie było konieczne do tej partii optymalizacji.
- Schowek: termin retencji z najstarszego rekordu SQLite, zamiast sprzątania co minutę. Przeplanowanie po zmianach historii, preferencji i zegara. Retencja działa także przy zablokowanej sesji, bez odszyfrowania treści; błędy mają backoff. Polling porównuje zapamiętaną datę najstarszego wpisu zamiast przeglądać historię przy każdej próbie. Zwykły zapis nadal odpytuje co 500 ms; brak zgody lub błąd magazynu wydłuża okres do 5 s.
- UI: pojedynczy termin zakończenia cooldownu aktualizacji zamiast `TimelineView` 1 Hz; reaguje również na zmianę zegara. W niewidocznym lub zminimalizowanym oknie ukrywane są wykresy, a zadanie cooldownu jest anulowane. Widoki zachowują stan wyboru i wyszukiwania. Gromadzenie historii metryk pozostaje aktywne.
- Wersja: 0.8.1 (9). Fixture bieżącego wydania w testach UI korzysta z wersji aplikacji, a nie stałej 0.8.0.

## Weryfikacja

- 101 testów Core w Release: PASS, w tym 3 nowe testy terminów retencji, retencji podczas blokady, wolniejszego pollingu bez uprawnień i callbacków scrolla.
- Testy Spotlight uruchomione z `MM_LAUNCHER_TEST_ROOT` wskazującym repozytorium.
- Build Debug i Release: PASS. Jedyny komunikat narzędzia App Intents dotyczy braku zależności AppIntents.framework.
- Dodatkowy harness kontrolerów, również z obiektami Release: PASS. Sprawdza brak sekundowych zmian czasu historii przy interwale 5 s, natychmiastową reakcję na zmianę interwału, suspend/resume, brak pollingu uprawnień wyłączonego scrolla oraz callback przerwania. Wykonuje także 12 rzeczywistych próbek SMC z resetem i ponownym otwarciem sesji na M4 Pro.
- XCTest UI: runner nie rozpoczął scenariuszy (`Timed out while enabling automation mode`). Nie traktujemy tego jako zaliczonych testów UI.
- Zastępcza kontrola przez Computer Use na izolowanym buildzie Debug: aktualne CPU/GPU/RAM/moc, temperatury i obroty wentylatorów, zmiana interwału 2 -> 5 s, przechodzenie między ekranami, włączenie testowego scrolla, filtrowanie syntetycznego schowka i przywrócenie wpisu. Przycisk sprawdzania aktualizacji blokuje się po próbie i odblokowuje po minucie bez sekundowego timera.
- Po instalacji: wszystkie 18 istniejących kluczy ustawień użytkownika zachowało zgodne skróty kontrolne (pominięto cache odpowiedzi aktualizacji). Rzeczywisty scroll nadal zgłasza obie zgody jako przyznane i stan aktywny. Metryki sprzętowe są dostępne.
- `git diff --check`: PASS.

Nie wykonano porównawczego pomiaru energii ani czasu pracy na baterii. Test UI nie potwierdza osobno braku renderowania wykresów podczas zasłonięcia/minimalizacji; ten warunek wynika z kodu obsługującego powiadomienia okna.

## Powtórzenie testu kontrolerów

Po zbudowaniu Release do `.build/battery-release`:

```sh
swiftc -parse-as-library -target arm64-apple-macosx26.0 \
  -I .build/battery-release/Build/Products/Release \
  -Xcc -fmodule-map-file=.build/battery-release/Build/Intermediates.noindex/GeneratedModuleMaps/MMHardware.modulemap \
  -Xcc -fmodule-map-file=.build/battery-release/Build/Intermediates.noindex/GeneratedModuleMaps/MMInput.modulemap \
  scripts/test-battery-controllers.swift \
  MacManager/Platform/Metrics/MetricsController.swift \
  MacManager/Platform/Scroll/ScrollController.swift \
  .build/battery-release/Build/Products/Release/MacManagerCore.o \
  .build/battery-release/Build/Products/Release/MMHardware.o \
  .build/battery-release/Build/Products/Release/MMInput.o \
  -lsqlite3 -framework IOKit -o /tmp/mm-controller-check-release
/tmp/mm-controller-check-release
```

Część sprzętowa wymaga maszyny z obsługiwanym katalogiem temperatur i dostępnym PSTR (sprawdzona na M4 Pro).

## Instalacja lokalna

Aktualizacja `/Applications/MacManager.app`, bez zachowania poprzedniego bundle zgodnie z dyspozycją właściciela. Identyfikator `dev.macmanager.MacManager`, ten sam certyfikat Apple Development i identyczne designated requirement jak w poprzedniej instalacji. Ustawienia, Application Support i Keychain nie są usuwane ani migrowane. Podpis sprawdzony przez `codesign --verify --deep --strict`. Nie jest to publikacja ani notaryzowany artefakt dystrybucyjny.
