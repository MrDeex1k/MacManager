# Informacje o komponentach zewnętrznych

Główny kod Mac Manager jest objęty [MIT](LICENSE). Poniższe adaptacje zachowują Apache-2.0; nie wymagają instalowania ani uruchamiania Scroll Reversera.

## Scroll Reverser

Źródło: [pilotmoon/Scroll-Reverser](https://github.com/pilotmoon/Scroll-Reverser/tree/187bf3945b6107cd8486327c6165f32e523535a4), rewizja 187bf3945b6107cd8486327c6165f32e523535a4. Copyright 2011 Nicholas Moore. Apache License 2.0.

Adaptowane elementy: klasyfikacja na podstawie gestów dotykowych i czasu w ScrollSourceClassifier.swift, rozdzielenie pasywnej obserwacji gestów od modyfikacji scrolla oraz kolejność transformowania reprezentacji zdarzenia i deklaracje ABI HID w MMInput.c. Zmiany: implementacja Swift, początkowy stan unknown, niezależny kontekst gestu i bezwładności przy zmianie urządzenia, zegar monotoniczny, walidacja delt, dynamiczne rozwiązywanie symboli, wątek wejścia i ograniczone odzyskiwanie tapu po timeoutach. Nie przejęto interfejsu, nazwy produktu, ikony ani ustawień Scroll Reversera.

Pełne NOTICE oraz LICENSE są w [ThirdPartyNotices.txt](MacManager/Resources/ThirdPartyNotices.txt), dołączanym również do zasobów aplikacji. Zachować ten plik przy dystrybucji źródeł i buildów.

Osobne narzędzia prototypowe mają też [informację o referencji Stats](Prototypes/Stage1/THIRD_PARTY_NOTICES.md).
