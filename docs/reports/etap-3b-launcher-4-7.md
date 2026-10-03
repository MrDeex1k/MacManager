# Etap 3B: personalizacja, pliki, kalkulator i schowek

Data: 2026-09-23. Branch: `feat/stage-3b-launcher`. Rozszerzenie [kroków 1-3](etap-3b-launcher-1-3.md). Kroki 4-7 są zaimplementowane; pełny odbiór etapu pozostaje krokiem 8.

## Zachowanie

4. Personalizacja: menu kontekstowe aplikacji lub polecenia otwiera edytor aliasu, ulubionego, ukrywania oraz własnego skrótu. Ulubione mają pierwszeństwo wśród pasujących wyników. Alias jest dodatkową wyszukiwaną nazwą. Ustawienia launchera pokazują także ukryte pozycje, umożliwiają edycję i reset. Dane są zapisane lokalnie pod identyfikatorem pozycji, bez historii zapytań. Skróty pozycji mają osobne rejestracje Carbon, są odtwarzane przy starcie i usuwane przy zakończeniu. Konflikt z paletą, inną pozycją lub błąd rejestracji zatrzymuje zapis nowego przypisania; poprzednie pozostaje aktywne. Ukrycie wyniku nie wyłącza jawnie przypisanego skrótu.
5. Pliki: funkcja domyślnie wyłączona. Użytkownik dodaje foldery w Ustawieniach i włącza wyszukiwanie. Spotlight przeszukuje nazwy po co najmniej dwóch znakach, z opóźnieniem 180 ms. Filtry: wszystkie pliki, foldery, dokumenty, obrazy. Enter otwiera domyślną aplikacją, menu kontekstowe pokazuje plik w Finderze. Nie czytamy zawartości plików ani nie budujemy własnego indeksu. Jawne zakresy, neutralizacja znaków specjalnych zapytania, weryfikacja granic ścieżek (także symlinków), pomijanie ukrytych ścieżek i wnętrz aplikacji. Limit 200 kandydatów Spotlight, 20 plików i 40 wyników całej palety. Zapytania Spotlight wykonuje osobny, szeregowy actor; nie uruchamiają pollera. Rozpoczęte synchroniczne zapytanie systemowe kończy się przed następnym, a anulowanie/generacja blokuje publikację nieaktualnego wyniku.
6. Kalkulator: lokalny parser Tinycast obsługuje działania, nawiasy, procenty, jednostki i daty/czas. Przykłady: `2+3*4`, `20% of 500`, `10 km to m`, `tomorrow + 2 days`. Składnia słowna jest angielska, objaśnienia interfejsu PL/EN. Polski przecinek dziesiętny jest obsługiwany; wynik kopiowany jest z kropką. Enter kopiuje wynik z markerem własnego zapisu, bez automatycznego wklejania. Nie uruchamiamy shell ani dynamicznego kodu, nie zapisujemy historii kalkulatora i nie pobieramy kursów walut. Nieobsługiwane/niepoprawne wyrażenia nie tworzą wyniku. Wynik kalkulatora ma pierwszeństwo i nie uruchamia zapytania do Spotlight.
7. Schowek: Tab lub przycisk ikony przełącza tryb; polecenie Schowek otwiera ten sam tryb. Obrazy mają miniatury, teksty wyszukiwanie w RAM. Usługa i repozytorium są dokładnie te same co w oknie historii 3A. Enter przywraca wpis, zamyka paletę i pozwala ręcznie wkleić przez Command-V. Pauza, stan uprawnień i blokada wynikają ze wspólnej usługi. Treści nie wchodzą do zwykłego rankingu ani personalizacji. Zamknięcie, uśpienie i blokada czyszczą wyniki palety. Nie dodano drugiego magazynu, klucza ani pollera.

Personalizacja dotyczy aplikacji i poleceń. Wpisy plików, kalkulatora i schowka nie zapisują treści w preferencjach. Wyszukiwanie i obliczenia nie mają połączeń sieciowych. Jawne otwarcie pliku/aplikacji może uruchomić działania programu docelowego.

## Adaptacja i licencje

Silnik Calculator i statyczne tabele pochodzą z tej samej przypiętej rewizji Tinycast co fundament launchera. Zapytania Spotlight adaptują FileSearchService/Query. Nie przejęto usług kursów, historii obliczeń, własnego schowka ani UI Tinycast. Zachowano nagłówki atrybucji i dodano opis zmian oraz licencję Unicode dla danych CLDR do [informacji o komponentach](../../THIRD_PARTY_NOTICES.md) i zasobów aplikacji.

## Weryfikacja

- 85 testów Core przeszło. Nowe przypadki obejmują zapis personalizacji, aliasy/ulubione/ukrywanie, obliczenia, brak kursów, granice i escapowanie zapytań plików oraz odrzucenie spóźnionych prywatnych wyników.
- Test Spotlight uruchomiony jawnie z `MM_LAUNCHER_TEST_ROOT` wskazującym repozytorium potwierdził znalezienie README, respektowanie zakresu i filtrowanie obrazów. Nie przeszukiwano prywatnych folderów użytkownika. Bez tej zmiennej test nie odpytuje rzeczywistego indeksu.
- GUI: obliczenie i kopiowanie wyniku, Tab, wyszukanie/przywrócenie syntetycznego wpisu schowka, brak wpisu w zwykłym trybie, alias, ulubione, konflikt skrótu palety, nowy skrót pozycji Control + Option + N oraz otwarcie sekcji po zamknięciu okna. Przeszła też regresja nawigacji PL/EN i Escape.
- Testy GUI używają izolowanych ustawień i nazwanych schowków, bez czytania/zastępowania schowka użytkownika. Kompilacje Debug i Release przeszły. Układ kalkulatora sprawdzono na nagraniu GUI.

## Dalej

Krok 8: pełny odbiór VoiceOver, IME, Spaces, wielu ekranów i kosztu pracy w tle, scenariusze odmowy dostępu do wybranych folderów i niepełnego indeksu Spotlight. Te warunki mogą dawać niepełne/puste wyniki; wyszukiwarka nie nadaje sobie zgód ani nie wymusza indeksowania.

Następnie etap 3C: wyspa, później muzyka. Ta zmiana nie podmienia instalacji w `/Applications` i nie publikuje wydania.
