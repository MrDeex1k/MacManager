# Dokumentacja Mac Manager

Status: wymagania zatwierdzone przez właściciela projektu po wywiadzie Q1-Q28 i końcowym potwierdzeniu. Kroki 1-8 etapu 1 są zaimplementowane. Aktualizacje przez GitHub Releases, lokalna diagnostyka i audyt prywatności mają zakończony odbiór. Do zamknięcia etapu 1 pozostaje krok 9.

Aktualny punkt prac i kolejność kolejnych zadań: [Stan projektu](10-stan-projektu.md).

## Mapa dokumentów

| Dokument | Zawartość |
| --- | --- |
| [Stan projektu](10-stan-projektu.md) | Co działa, co jest następne i pozostałe ograniczenia. |
| [Produkt](01-produkt.md) | Cel, zakres, wymagania i ustawienia domyślne. |
| [Interfejs](02-interfejs.md) | Okno, pasek menu, wyspa, stany i scenariusze. |
| [Architektura](03-architektura.md) | Moduły, przepływ danych, współbieżność i decyzje implementacyjne. |
| [Wykonalność](04-wykonalnosc.md) | API, źródła, ryzyka i prototypy techniczne. |
| [Dane i prywatność](05-dane-i-prywatnosc.md) | Schowek, retencja, uprawnienia i połączenia sieciowe. |
| [Plan i testy](06-plan-i-testy.md) | Trzy fazy, zadania, kryteria odbioru i macierz testów. |
| [Wydania](07-wydania.md) | DMG, GitHub Releases, aktualizacje, GNU AGPL v3.0 only i opcjonalny Homebrew. |
| [Rejestr decyzji](08-decyzje.md) | Zatwierdzone decyzje i drzewo zależności. |
| [Praca z repozytorium](09-praca-z-repozytorium.md) | Lokalne hooki, Conventional Commits, instalacja i testy. |
| [Plan kroku 8](11-plan-kroku-8.md) | Aktualizacje przez GitHub Releases, lokalna diagnostyka, prywatność i testy. |
| [Raport kroku 8](reports/etap-1-krok-8.md) | Wyniki testów aktualizacji, interfejsu, diagnostyki i audytu prywatności. |
| [Raport kroku 9](reports/etap-1-krok-9a.md) | Testy automatyczne, audyt dostępności, wydajność w tle i próba na urządzeniu referencyjnym. |
| [Raport prototypów](reports/etap-1-krok-1.md) | Wyniki pierwszych uruchomień etapu 1 i brakujące dowody. |
| [Raport szkieletu](reports/etap-1-krok-2.md) | Projekt Xcode, lokalny Core, interfejs i wyniki testów kroku 2. |

[Raport sieci - krok 5](reports/etap-1-krok-5.md), [raport pomiarów - krok 3](reports/etap-1-krok-3.md), [raport historii - krok 4](reports/etap-1-krok-4.md), [raport scrolla - krok 6](reports/etap-1-krok-6.md), [raport modelu ustawień i cyklu życia - krok 7a](reports/etap-1-krok-7a.md), [raport paska menu - krok 7b](reports/etap-1-krok-7b.md), [raport Docka i okna - krok 7c](reports/etap-1-krok-7c.md), [raport autostartu i trybu uruchomienia - krok 7d](reports/etap-1-krok-7d.md) oraz [raport osobnych sekcji Docka i scrolla - krok 7e](reports/etap-1-krok-7e.md).

## Jak czytać ustalenia

- **Wymaganie zatwierdzone:** wynika z odpowiedzi użytkownika i końcowego potwierdzenia. Zmiana wymaga jawnej aktualizacji zakresu.
- **Decyzja inżynierska:** sposób realizacji dobrany w tej dokumentacji, możliwy do zmiany po pomiarach lub prototypie bez zmiany zachowania produktu.
- **Do walidacji:** konkretna niewiadoma techniczna; ma zadanie badawcze i warunek zakończenia. Nie jest deklaracją obsługi.

Wszystkie trzy fazy są częścią wizji. Nie należy aktywować obserwacji schowka ani integracji muzycznych przed fazą 3. Moc w W pozostaje w fazie 1, mimo że korzysta z warstwy odczytu sprzętu rozszerzanej w fazie 2.

Środowisko rozpoznane lokalnie: MacBook Pro Mac16,8, Apple M4 Pro, 24 GB RAM, macOS 26.6.2. Jest to punkt startowy testów, nie dowód zgodności ze wszystkimi Macami Apple Silicon. Wyniki prototypów, testów Core i podstawowych przepływów GUI są w raportach kroków 1 i 2. Pełna macierz odbioru aplikacji pozostaje do wykonania.

## Granice opracowania

Dokumentacja nie tworzy aplikacji, repozytorium zdalnego, opublikowanego wydania ani infrastruktury podpisywania. Nie ustalono terminów kalendarzowych bez pomiaru prac nad prototypami. Techniczne warunki przygotowania wydania są wymienione w [planie dystrybucji](07-wydania.md).
