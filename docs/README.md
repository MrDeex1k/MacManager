# Dokumentacja Mac Manager

Status: wymagania zatwierdzone przez właściciela projektu po wywiadzie Q1–Q28 i końcowym potwierdzeniu. Dokumentacja opisuje plan aplikacji, nie gotowy produkt. Data opracowania: 2026-09-07.

## Mapa dokumentów

| Dokument | Zawartość |
| --- | --- |
| [Produkt](01-produkt.md) | Cel, zakres, wymagania i ustawienia domyślne. |
| [Interfejs](02-interfejs.md) | Okno, pasek menu, wyspa, stany i scenariusze. |
| [Architektura](03-architektura.md) | Moduły, przepływ danych, współbieżność i decyzje implementacyjne. |
| [Wykonalność](04-wykonalnosc.md) | API, źródła, ryzyka i prototypy techniczne. |
| [Dane i prywatność](05-dane-i-prywatnosc.md) | Schowek, retencja, uprawnienia i połączenia sieciowe. |
| [Plan i testy](06-plan-i-testy.md) | Trzy fazy, zadania, kryteria odbioru i macierz testów. |
| [Wydania](07-wydania.md) | DMG, GitHub Releases, aktualizacje, MIT i opcjonalny Homebrew. |
| [Rejestr decyzji](08-decyzje.md) | Zatwierdzone decyzje i drzewo zależności. |

## Jak czytać ustalenia

- **Wymaganie zatwierdzone:** wynika z odpowiedzi użytkownika i końcowego potwierdzenia. Zmiana wymaga jawnej aktualizacji zakresu.
- **Decyzja inżynierska:** sposób realizacji dobrany w tej dokumentacji, możliwy do zmiany po pomiarach lub prototypie bez zmiany zachowania produktu.
- **Do walidacji:** konkretna niewiadoma techniczna; ma zadanie badawcze i warunek zakończenia. Nie jest deklaracją obsługi.

Wszystkie trzy fazy są częścią wizji. Nie należy aktywować obserwacji schowka ani integracji muzycznych przed fazą 3. Moc w W pozostaje w fazie 1, mimo że korzysta z warstwy odczytu sprzętu rozszerzanej w fazie 2.

Środowisko rozpoznane lokalnie: MacBook Pro Mac16,8, Apple M4 Pro, 24 GB RAM, macOS 26.6.2. Jest to punkt startowy testów, nie dowód zgodności ze wszystkimi Macami Apple Silicon. Nie uruchomiono prototypów czujników ani testów aplikacji.

## Granice opracowania

Dokumentacja nie tworzy aplikacji, repozytorium zdalnego, opublikowanego wydania ani infrastruktury podpisywania. Nie ustalono terminów kalendarzowych bez pomiaru prac nad prototypami. Techniczne warunki przygotowania wydania są wymienione w [planie dystrybucji](07-wydania.md).

