# Profile energii - 2026-10-06

Branch: `feat/battery-optimization`. Wersja 0.8.2, build 10.

## Zachowanie

Preferencje użytkownika pozostają zapisane niezależnie od chwilowych parametrów. Domyślnie włączony przełącznik adaptacji jest dostępny w ustawieniach, wraz z efektywnym interwałem lub informacją o pauzie. Etykiety mają wersje PL/EN. Uśpienie ma pierwszeństwo przed trybem oszczędzania. Przy starcie i po wybudzeniu aplikacja ponownie sprawdza systemowy stan zasilania.

- Oszczędzanie: pełne metryki co 5 s podczas oglądania Przeglądu, Czujników lub panelu menu; w tle co 10 s wyłącznie wskaźniki wybrane na pasku menu. Brak odbiorców oznacza pauzę. Sprzętowy sampler pomija niepotrzebne odczyty Mach, GPU i SMC. Okno menu jest obserwowane przez AppKit, także gdy SwiftUI zachowuje jego drzewo po zamknięciu.
- Historia: zmiany profilu, brak odczytów oraz uśpienie dzielą wykres na osobne odcinki. Nie tworzymy wartości zastępczych ani ciągłej linii przez przerwę.
- Sieć: lokalne dane co 30 s w tle w oszczędzaniu, co 5 s podczas oglądania sieci/panelu; zmiana ścieżki uruchamia odczyt. Publiczny IP co 3600 s zamiast 900 s. Odświeżenie ręczne i po zmianie ścieżki nadal działa z dotychczasowym ograniczeniem liczby prób. Harmonogram śpi do następnego terminu zamiast budzić się co sekundę.
- Aktualizacje: nowe automatyczne próby czekają na wyłączenie oszczędzania; rozpoczęte próby mogą się zakończyć. Ręczna kontrola pozostaje dostępna. Po wybudzeniu obowiązuje 30 s okresu stabilizacji dla kontroli automatycznej, z zachowaniem dotychczasowej częstotliwości siedmiu dni.
- Launcher: TTL katalogu i ikon 300 s w oszczędzaniu, 60 s normalnie; zmiana języka unieważnia katalog. Wyszukiwanie pozostaje responsywne.
- Schowek: polling 500 ms pozostaje bez zmian; podczas uśpienia zatrzymujemy przechwytywanie i harmonogram retencji. W samej zablokowanej sesji retencja metadanych nadal działa. Wybudzenie sprząta retencję i odtwarza bazowy licznik schowka; przechwytywanie czeka na aktywną odblokowaną sesję. Usługa nadal używa atomowego repozytorium i odrzuca wyniki anulowanych zadań.
- Uśpienie: pętla metryk znika; odczyt w toku nie publikuje wyniku, sesja SMC zamyka się po jego zakończeniu, bez czekania na wybudzenie. Sieć wstrzymuje timer i anuluje HTTP; aktualizacje anulują timer i żądanie. Scroll zatrzymuje event tap i watchdog; wznowienie wymaga aktywnej, odblokowanej sesji i istniejących uprawnień. Launcher ukrywa panel i anuluje wyszukiwanie oraz sprzątanie skrótów nawet przy zamkniętym panelu. Wykresy i cooldown UI są wstrzymane. Żaden panel launchera nie otwiera się sam po wybudzeniu.

## Weryfikacja

- 107 testów Core Release, z fixture Spotlight wskazującym repozytorium: PASS.
- Build Debug i finalny Release: PASS.
- Harness kontrolerów Release: PASS. Sprawdza kadencję, pauzę, odtworzenie zapisanego interwału, powiadomienia systemowe sleep/wake, odroczenie automatycznych aktualizacji w oszczędzaniu, ręczną kontrolę, 30 s odroczenia po wybudzeniu, brak zbędnego pollingu scrolla, rzeczywiste odczyty SMC, wybór samych temperatur CPU oraz reset i ponowne otwarcie sesji.
- Computer Use na izolowanym Debug: rzeczywiste CPU/GPU/RAM/moc, zatrzymanie odczytów bez odbiorców w oszczędzaniu, powrót do zapisanych 2 s po wyłączeniu adaptacji i wznowienie Przeglądu po jej ponownym włączeniu. Automatyczna kontrola aktualizacji ruszyła dopiero po wyłączeniu adaptacji.
- `git diff --check`: PASS.

Uśpienie sprawdzono przez powiadomienia i kontrolowane przejścia polityki, bez usypiania komputera użytkownika. Nie zmieniano systemowego trybu oszczędzania; scenariusz UI korzystał z flagi Debug. Nie wykonano pomiaru czasu pracy na baterii ani porównawczego pomiaru poboru energii. Wykrywanie trybu korzysta z [udokumentowanej właściwości i powiadomień Apple](https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled).

## Powtórzenie harnessu

```sh
swiftc -parse-as-library -target arm64-apple-macosx26.0 \
  -I .build/battery-release/Build/Products/Release \
  -Xcc -fmodule-map-file=.build/battery-release/Build/Intermediates.noindex/GeneratedModuleMaps/MMHardware.modulemap \
  -Xcc -fmodule-map-file=.build/battery-release/Build/Intermediates.noindex/GeneratedModuleMaps/MMInput.modulemap \
  scripts/test-battery-controllers.swift \
  MacManager/Platform/Metrics/MetricsController.swift \
  MacManager/Platform/Scroll/ScrollController.swift \
  MacManager/Platform/Updates/UpdateController.swift \
  MacManager/Platform/Application/EnergyController.swift \
  .build/battery-release/Build/Products/Release/MacManagerCore.o \
  .build/battery-release/Build/Products/Release/MMHardware.o \
  .build/battery-release/Build/Products/Release/MMInput.o \
  -lsqlite3 -framework IOKit -o /tmp/mm-energy-controller-check
/tmp/mm-energy-controller-check
```

Część sprzętowa wymaga obsługiwanego katalogu temperatur i PSTR; wykonana na M4 Pro.

## Instalacja

Podmiana `/Applications/MacManager.app` bez kopii starego bundle. Ten sam identyfikator `dev.macmanager.MacManager`, certyfikat i designated requirement. Bez usuwania preferencji, Application Support lub Keychain. Podpis zweryfikowany przed i po podmianie; plik wykonywalny ma identyczny SHA-256 jak build Release. Wszystkie 18 istniejących kluczy preferencji zachowało zgodne skróty kontrolne (z pominięciem cache aktualizacji). Po uruchomieniu wersja 0.8.2 (10), metryki dostępne, sieć online, publiczny IP dostępny, scroll aktywny z przyznanymi uprawnieniami. Adaptacja jest włączona; przy obecnie wyłączonym systemowym oszczędzaniu efektywny interwał wynosi zapisane 2 s.
