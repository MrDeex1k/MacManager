# Informacje o komponentach zewnętrznych

Główny kod Mac Manager jest objęty [GNU AGPL v3.0 only](LICENSE). Poszczególne adaptacje zachowują licencje wskazane poniżej. Nie wymagają instalowania ani uruchamiania projektów źródłowych.

## Scroll Reverser

Źródło: [pilotmoon/Scroll-Reverser](https://github.com/pilotmoon/Scroll-Reverser/tree/187bf3945b6107cd8486327c6165f32e523535a4), rewizja 187bf3945b6107cd8486327c6165f32e523535a4. Copyright 2011 Nicholas Moore. Apache License 2.0.

Adaptowane elementy: klasyfikacja na podstawie gestów dotykowych i czasu w ScrollSourceClassifier.swift, rozdzielenie pasywnej obserwacji gestów od modyfikacji scrolla oraz kolejność transformowania reprezentacji zdarzenia i deklaracje ABI HID w MMInput.c. Zmiany: implementacja Swift, początkowy stan unknown, niezależny kontekst gestu i bezwładności przy zmianie urządzenia, zegar monotoniczny, walidacja delt, dynamiczne rozwiązywanie symboli, wątek wejścia i ograniczone odzyskiwanie tapu po timeoutach. Nie przejęto interfejsu, nazwy produktu, ikony ani ustawień Scroll Reversera.

Pełne NOTICE oraz LICENSE są w [ThirdPartyNotices.txt](MacManager/Resources/ThirdPartyNotices.txt), dołączanym również do zasobów aplikacji. Zachować ten plik przy dystrybucji źródeł i buildów.

Osobne narzędzia prototypowe mają też [informację o referencji Stats](Prototypes/Stage1/THIRD_PARTY_NOTICES.md).

## Stats: katalog czujników GPU

Lista kluczy GPU dla M4 Pro w SensorCatalog.swift pochodzi z [Stats](https://github.com/exelban/stats/blob/a9bf99866eac97d62e8952c058961f6c5e51bc67/Modules/Sensors/values.swift), rewizja `a9bf99866eac97d62e8952c058961f6c5e51bc67`, MIT, Copyright (c) 2019 Serhiy Mytrovtsiy. Własna implementacja odczytu i UI; nie przejęto sterowania wentylatorami. Tekst MIT dołączono do ThirdPartyNotices.txt w aplikacji.

## Tinycast: lokalny launcher

Źródło: [abue-ammar/tinycast](https://github.com/abue-ammar/tinycast/tree/c5cff8cbb9b7e12ac75c058da9573045c76029b7), rewizja `c5cff8cbb9b7e12ac75c058da9573045c76029b7`. Copyright (C) 2026 Abue Ammar. AGPL-3.0-or-later; adaptacja korzysta z wersji 3.

Przeniesiono `SearchRelevance.swift` (FuzzyMatch, role pól, progi i ranking) oraz `SearchScopes.swift` (zakresy katalogów aplikacji). Z `AppIndex.swift` i `SettingsPaneScanner.swift` zaadaptowano skanowanie, deduplikację bundle ID i identyfikację paneli systemowych w `ApplicationProvider.swift`. Z `HotKeyCenter.swift` pochodzi mechanizm Carbon w `LauncherHotKey.swift`; z `PalettePanel.swift` konfiguracja panelu i zasada ochrony kompozycji tekstu w `LauncherController.swift`.

Modyfikacje z 2026-09-23: wspólny kontrakt wyników Mac Managera, ranking bez zapisu zapytań i bez uczenia, anulowanie zadań, deterministyczne skanowanie i ograniczenie zagnieżdżonych pakietów, PL/EN, ograniczona lista odnośników systemowych, transakcyjna zmiana skrótu z raportowaniem błędu i pełnym wyrejestrowaniem, uproszczona paleta Liquid Glass oraz integracja z istniejącymi oknem/Dockiem/cyklem życia. Nie przeniesiono brandingu, ikon, modeli AI, runtime rozszerzeń, updatera ani magazynu schowka Tinycast.

Informacja o autorze, zmianach i pełny tekst licencji Tinycast są również dołączone do zasobów aplikacji w `ThirdPartyNotices.txt`.

Rozszerzenie z 2026-09-23 (kroki 4-7): zaadaptowano modele silnika Calculator (parser, procenty, jednostki, daty/czas, formatowanie i statyczne tabele) oraz mechanizm zapytań nazw Spotlight z FileSearchService/Query. Nie przeniesiono CurrencyFeed, pobierania kursów ani historii kalkulatora. Własne preferencje personalizacji i integracja schowka wykorzystują istniejące usługi Mac Managera. Wiele skrótów ma odrębne identyfikatory Carbon.

Tabele `CountryZoneData.generated.swift` i `CurrencyData.generated.swift` zawierają dane Unicode CLDR (nazwy krajów i walut) oraz IANA zone.tab (mapowanie stref). Licencja Unicode V3 z https://www.unicode.org/license.txt jest dołączona do zasobów aplikacji. Dane stref IANA pochodzą z domeny publicznej: https://www.iana.org/time-zones.
