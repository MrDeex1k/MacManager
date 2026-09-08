# Etap 1, krok 6 — niezależny scroll myszy

Data: 2026-09-08. Branch: feat/stage-1. Zakres: F1-05 / SCR-01.

## Zachowanie

W Ustawieniach jest jeden przełącznik „Odwróć przewijanie myszy”, domyślnie wyłączony. Po aktywacji zmienia znak obu osi myszy, zachowując wielkość i płynność przewijania. Gładzik zachowuje systemowy kierunek i gesty. Aplikacja nie zmienia systemowego naturalnego przewijania ani ustawień innych aplikacji. Intencja użytkownika jest zapisywana lokalnie i przywracana po restarcie.

Rozróżnianie jest automatyczne: bez wyboru urządzenia, list modeli, sterowników czy konfiguracji każdej myszy. Po wskazaniu Scroll Reversera przez właściciela zaadaptowano jego mechanizm obserwacji dotyku dwóch palców i kontekstu czasowego. Wcześniej rozważana reguła oparta wyłącznie na fazach scrolla nie weszła do finalnej implementacji.

## Mechanizm

- Osobny pasywny CGEvent tap obserwuje gesty; modyfikujący tap otrzymuje tylko scrollWheel. Rozdzielenie zapobiega ingerencji w systemowe gesty. Oba działają na jednym dedykowanym wątku, niezależnie od renderowania SwiftUI.
- ScrollSourceClassifier bierze pod uwagę zdarzenia nieciągłe, dotyk co najmniej dwóch palców w ostatnich 222 ms oraz odstęp ponad 333 ms od dotyku przy braku bezwładności. W niejednoznacznym fragmencie kontynuuje ostatnie źródło, osobno utrzymując właściciela gestu i trwającej bezwładności; początkowe unknown przepuszcza zdarzenie bez zmian. Nie opiera się na samym continuous.
- MMInput zachowuje oryginalne delty liniowe, punktowe i stałoprzecinkowe przed zapisem. Ustawienie delty liniowej w Quartz może nadpisać pozostałe pola, więc kolejność ma znaczenie. Zmieniane są też osie dołączonego zdarzenia IOHID; inne metadane pozostają bez zmian. Nie ma repostowania zdarzeń, przyspieszenia ani wygładzania.
- Prywatne symbole HID są izolowane w małym adapterze C, rozwiązywane dynamicznie. Brak zgodnego mostka zatrzymuje start funkcji. To zależność wymagająca ponownej weryfikacji przy aktualizacji macOS, nie deklaracja gwarantowanego ABI.
- Kontroler działa poza cyklem życia widoku. Wyłączenie przełącznika zamyka bramkę modyfikacji, po czym wątek usuwa tapy. Sleep/wake i zmiana aktywnej sesji zatrzymują/wznawiają usługę z nowym klasyfikatorem; ⌘Q ją kończy. Maksymalnie trzy wznowienia tapu po timeoutach na minutę; dalsze przerwanie wymaga ręcznego ponowienia.

## Zgody i prywatność

Wymagane są Dostępność do modyfikacji oraz Monitorowanie wprowadzania do pasywnej obserwacji gestów. Każda brakująca zgoda ma własny stan i przycisk do właściwego panelu macOS. Zgody są proszone wyłącznie po świadomej akcji użytkownika, bez promptów przy zwykłym uruchomieniu. Odmowa lub cofnięcie zgody zatrzymuje funkcję; monitoring metryk i sieci pozostaje niezależny. Stan jest sprawdzany co sekundę.

Nie obserwujemy klawiszy, kliknięć ani treści okien. Liczba palców, czas i kontekst źródła pozostają chwilowo w RAM. Pasywny prototyp input raportuje wyłącznie sumaryczne liczniki mouseEvents/trackpadEvents/unknownEvents/multiTouchEvents. Nie zapisuje identyfikatorów urządzeń ani pozycji dotknięć.

## Weryfikacja

- 33 testy Core: dotychczasowe 22 oraz 11 scenariuszy scrolla. Testy syntetycznych CGEvent sprawdzają znaki, wielkości, obie osie, flagi i timestamp, zachowanie zdarzeń gładzika i brak częściowej modyfikacji błędnej delty. Klasyfikator sprawdzono z kołem dyskretnym, płynną myszą, dwoma palcami, bezwładnością i zmianą urządzenia. Zgody, restart, sen, wyłączenie, timeouty i ponowienie sprawdzono z atrapą sterownika.
- 9 testów prototypów przechodzi po podłączeniu produkcyjnego klasyfikatora do pasywnego input. Symbole C prototypu otrzymały prefiks mm_probe_, aby nie kolidowały z biblioteką aplikacji.
- 6 testów GUI: nawigacja, PL/EN, żywe metryki/historia oraz trzy przepływy scrolla (odmowa Dostępności, brak Monitorowania wprowadzania również w PL, aktywny stan z fixture i trwałość ustawienia). Testy UI nie instalują globalnych tapów, nie proszą o zgody i nie zmieniają rzeczywistego scrolla.
- Buildy Debug i Release dla arm64 zakończone powodzeniem. Sprawdzono dołączenie pełnych informacji licencyjnych do gotowego pakietu aplikacji.
- Dwusekundowa próba przygotowawcza CLI: tap pasywny działał z istniejącymi zgodami, 0 zdarzeń i 0 przerwań. Sprawdza start obserwacji, nie klasyfikację urządzenia.

## Próby rzeczywistych urządzeń z właścicielem

Próba 25 s gładzika była pusta (0 zdarzeń) i nie stanowi dowodu klasyfikacji. Powtórzenie przez 45 s: **2372 zdarzenia gładzika, 0 myszy, 0 unknown**; 521 zdarzeń z co najmniej dwoma dotknięciami, 1907 zdarzeń bezwładności, 0 przerwań tapu. Wszystkie zdarzenia scrolla miały continuous, co potwierdza potrzebę informacji o dotyku.

Próba myszy 45 s: **1032 zdarzenia myszy, 0 gładzika, 0 unknown**, bez faz, bezwładności, dotyku i przerwań tapu. Również wszystkie miały continuous; klasyfikator rozróżnił obie próby bez informacji o modelu.

Pierwsza próba mieszana (45 s): 731 zdarzeń myszy i 1173 gładzika, 0 unknown. Suma faz i bezwładności wskazała możliwe przejmowanie źródła podczas zmiany urządzenia. Dodano osobny kontekst gestu i bezwładności oraz test regresji: mysz użyta między pakietami bezwładności nie zmienia źródła tych pakietów. To celowa poprawka względem referencyjnego algorytmu, a nie samo pominięcie wyniku próby.

Powtórzona próba mieszana po poprawce (45 s): **533 zdarzenia myszy, 526 gładzika, 0 unknown i 0 przerwań**. Zarejestrowano 114 faz gestu i 412 pakietów bezwładności; żaden z nich nie został przypisany myszy (mouseGestureEvents = 0). Żadne zdarzenie bez faz i bezwładności nie zostało przypisane gładzikowi (trackpadPlainEvents = 0). Próba obejmowała przejście do kółka podczas wyhamowywania gładzika. Wynik dotyczy fizycznej pary użytej w sesji, bez odczytywania jej modelu lub używania go w klasyfikacji.

Były to próby pasywne: potwierdzają rozróżnianie, a nie faktyczne odwracanie scrolla w innych aplikacjach. Transformacja była sprawdzana na syntetycznych CGEvent; pełny test kierunku po włączeniu funkcji i udzieleniu zgód pozostaje w ręcznym odbiorze.

## Licencja i źródła

Adaptacja dotyczy [Scroll Reversera, rewizja 187bf3945](https://github.com/pilotmoon/Scroll-Reverser/tree/187bf3945b6107cd8486327c6165f32e523535a4), w szczególności MouseTap.m i deklaracji SPI. Copyright 2011 Nicholas Moore; Apache-2.0. Pełne NOTICE/LICENSE są w zasobach aplikacji, z opisem zmian w [THIRD_PARTY_NOTICES](../../THIRD_PARTY_NOTICES.md). Główny kod projektu pozostaje MIT.

API: [CGEvent tap](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)), [dotyk NSEvent](https://developer.apple.com/documentation/appkit/nsevent/touches(matching:in:)), lokalne nagłówki SDK macOS 26.5; wymagania zgód porównano z PermissionsManager.m projektu referencyjnego.

## Dalszy odbiór

Automatyczny algorytm nie wymaga znajomości modelu. Pełna macierz sterowników, aplikacji i wersji macOS nadal wymaga prób rzeczywistego wejścia; test syntetyczny nie zastępuje fizycznego scrolla ani ręcznego cofnięcia zgody. W szczególności należy sprawdzić Safari/WebKit, gesty systemowe i naprzemienne używanie obu urządzeń. Podczas testowania odwracania tylko jedna aplikacja powinna je wykonywać, aby dwa odwrócenia się nie znosiły.

Następny krok: 7 — pasek menu, Dock i autostart. Nie oznaczamy całego etapu 1 jako ukończonego.
