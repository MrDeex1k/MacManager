# Plan etapu 1, kroku 8 - aktualizacje, prywatność i diagnostyka

Krok 8 realizuje F1-07 i F1-08. Aplikacja sprawdza stabilne wydania na GitHub raz na 7 dni lub na żądanie użytkownika. Nie pobiera i nie instaluje aktualizacji. Diagnostyka pozostaje lokalna i nie zawiera danych użytkownika.

## 8.1 Model ustawień i stanu aktualizacji

- Dodać trwałą zgodę na automatyczne sprawdzanie, domyślnie włączoną.
- Przechowywać datę ostatniej zakończonej kontroli oraz dane cache potrzebne do ograniczenia zapytań.
- Rozdzielić stany: bez kontroli, sprawdzanie, aktualna wersja, dostępna aktualizacja i błąd.
- Wstrzykiwać zegar, bieżącą wersję i klienta sieciowego, aby testy nie czekały rzeczywistych 7 dni.

## 8.2 Klient GitHub Releases i wybór wydania

- Korzystać wyłącznie z publicznego API repozytorium bez tokenu użytkownika.
- Obsłużyć timeout, brak sieci, limity API, odpowiedzi HTTP i błędny JSON bez wpływu na pozostałe usługi.
- Odrzucać drafty, prerelease, błędne tagi i wydania bez zgodnego pliku DMG dla Apple Silicon.
- Porównywać wersje semantycznie w konwencji `vMAJOR.MINOR.PATCH`.
- Stosować ETag i zapytania warunkowe, aby nie pobierać niezmienionej odpowiedzi.

## 8.3 Harmonogram i cykl życia

- Przy starcie procesu sprawdzać, czy od ostatniej zakończonej kontroli minęło co najmniej 7 dni.
- Nie wykonywać zapytania, gdy automatyczne sprawdzanie jest wyłączone.
- Kontrola ręczna pomija termin harmonogramu, ale blokuje równoległe duplikaty zapytania.
- Błąd pozostaje nieblokujący i nie uruchamia agresywnych ponowień w tle.

## 8.4 Interfejs aktualizacji

- Dodać sekcję aktualizacji w Ustawieniach z przełącznikiem automatycznej kontroli, stanem, datą ostatniej próby i przyciskiem Sprawdź teraz.
- Pokazać numer nowej wersji tylko po zweryfikowaniu zgodnego wydania.
- Udostępnić przycisk otwierający stronę konkretnego GitHub Release do ręcznego pobrania DMG.
- Nie dodawać pobierania, montowania DMG ani instalacji w aplikacji.
- Uzupełnić teksty PL/EN, obsługę klawiatury, VoiceOver i systemowe ustawienia ograniczenia ruchu.

## 8.5 Lokalne logi i diagnostyka

- Wprowadzić kategorie `OSLog` dla cyklu życia, pomiarów, sieci, scrolla i aktualizacji.
- Rejestrować stany i typy błędów bez adresów IP, treści schowka, identyfikatorów urządzeń i surowych danych użytkownika.
- Dodać lokalny podgląd podstawowej diagnostyki: wersja aplikacji, wersja macOS, architektura oraz dostępność usług.
- Eksport lub kopiowanie diagnostyki wykonywać wyłącznie po jawnej akcji użytkownika i po wcześniejszym zredagowaniu danych.

## 8.6 Audyt prywatności i ruchu sieciowego

- Potwierdzić, że aplikacja łączy się tylko z uzgodnionymi usługami publicznego IPv4 i GitHub Releases.
- Sprawdzić brak telemetrii, konta, synchronizacji chmurowej i wysyłania metryk.
- Uzupełnić tabelę endpointów, zachowanie offline oraz opis metadanych widocznych dla usługodawców.
- Zweryfikować ustawienia prywatności w obu językach względem faktycznego działania aplikacji.

## 8.7 Testy i odbiór kroku

- Testy jednostkowe obejmą parser wersji, kwalifikację wydania, harmonogram 7 dni, ETag i wszystkie stany błędów.
- Testy integracyjne użyją lokalnych odpowiedzi HTTP dla nowej, bieżącej, starszej i uszkodzonej wersji, prerelease, draftu, braku DMG oraz limitu API.
- Testy UI obejmą kontrolę ręczną, wyłączenie automatycznej kontroli, trwałość ustawienia, wersję aktualną, dostępną aktualizację i błąd offline w PL/EN.
- Audyt logów i połączeń potwierdzi brak danych użytkownika oraz brak nieudokumentowanych endpointów.
- Raport kroku zapisze wyniki, znane ograniczenia i zadania przeniesione do odbioru wydania w kroku 9.

## Kolejność commitów

1. `feat(updates): add update state and release selection`
2. `feat(updates): check GitHub Releases on schedule`
3. `feat(settings): add update controls and release action`
4. `feat(diagnostics): add private local diagnostics`
5. `test(updates): verify update and privacy flows`
6. `docs(stage-1): record step 8 validation`
