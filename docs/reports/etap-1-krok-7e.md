# Etap 1, krok 7e - osobne sekcje Docka i scrolla

Data: 2026-09-08. Stan: zaimplementowany na branchu feat/stage-1. Zmiana domyka organizację ustawień w F1-06.

## Zakres

- Główna nawigacja zawiera kolejno Przegląd, Sieć, Przewijanie, Dock i Ustawienia.
- Przełącznik widoczności ikony Docka, komunikat błędu macOS oraz opcje CPU, RAM i W wyświetlane obok ikony paska menu znajdują się wyłącznie w sekcji Dock.
- Odwracanie przewijania, stan usługi i obsługa zgód znajdują się wyłącznie w sekcji Przewijanie.
- Ustawienia zachowują język, wygląd, próbkowanie, autostart i opis prywatności.
- Obie nowe sekcje korzystają z istniejącej nawigacji SwiftUI i natywnego Liquid Glass oraz działają po polsku i angielsku.

## Weryfikacja

Scenariusze UI otwierają Dock i Przewijanie z głównego panelu bocznego. Test Docka sprawdza brak przełącznika w Ustawieniach, zmianę widoczności i trwałość po ponownym uruchomieniu. Testy scrolla sprawdzają stan, zgody, zmianę języka i trwałość ustawienia w wydzielonej sekcji.

## Granice

Sekcja Dock obejmuje widoczność ikony Docka oraz zawartość prezentowaną obok ikony paska menu. Kolejne opcje związane z obecnością aplikacji w Docku i pasku menu mogą zostać dodane w tym miejscu bez rozbudowy ustawień ogólnych.
