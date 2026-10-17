# Etap 3C: wyspa, krok 5 - animacje i ukryta prezentacja

Data: 2026-10-13. Zakres: otwieranie/zamykanie obecnej wyspy ze schowkiem oraz zatrzymywanie jej pracy po ukryciu. Druga sekcja i postęp muzyki wymagają 3D.

## Zachowanie i cykl życia

- IslandTransitionHost utrzymuje stałą geometrię panelu. Maska Core Animation odsłania go od obszaru notcha przez 220 ms; zwinięcie trwa 150 ms. Krzywa easeInEaseOut i zanik są skończone. Nie animujemy rozmiaru NSPanel ani układu SwiftUI co klatkę, więc pozostają zachowane wysokość, szerokość i połączenie z krawędzią ekranu.
- Reduce Motion używa wyłącznie zaniku przez 100 ms. Zmiana ustawień dostępności zatrzymuje bieżące przejście. Zaznaczenie i potwierdzenie kopiowania mają krótkie przejścia 120 ms, wyłączane przez systemowe Reduce Motion.
- Zamknięcie najpierw dezaktywuje IslandClipboardModel, anuluje wyszukiwanie, oczekujące przywracanie i potwierdzenie oraz usuwa wyniki/zapytanie. Prywatny podwidok SwiftUI jest zastępowany samą czarną sylwetką; jego zadania i dekodowane miniatury nie pozostają częścią animacji zamykania.
- Po zakończeniu animacji okno jest ukrywane, host odłączany, a zadanie przejścia zwalniane. Ukryty panel nie ma widoku zawartości ani animacji i nie odpytuje schowka. Pozostają pasywne monitory potrzebne do kolejnego hover oraz wspólna usługa schowka z niezależnym cyklem życia.
- Blokada, sleep, wyłączenie wyspy, niedostępny pełny ekran, zmiana ekranów i zakończenie aplikacji zamykają bez animacji. Nowe otwarcie unieważnia poprzedni callback przejścia i aktywuje nową prezentację na aktualnej historii; spóźnione wyniki nie mogą odtworzyć starego panelu.
- Zadania wyszukiwania i przywracania mają własne identyfikatory oraz generację prezentacji. Anulowany starszy callback nie usuwa uchwytu nowego zadania. Harmonogram hover nie jest ponownie tworzony dla każdego ruchu wewnątrz tego samego obszaru, jeśli termin się nie zmienił.

## Weryfikacja

- 124 testy Core przeszły.
- Pięć testów GUI przeszło: geometria i hover; pisanie/Escape/fokus; tekst/obraz/wspólna historia/usuwanie; wielokrotne cykle otwarcia/zamknięcia; wariant Reduce Motion. Dwa nowe testy po zamknięciu sprawdzają brak hosta, aktywnej prezentacji, animacji oraz zadań wyszukiwania/przywracania/potwierdzenia przy zachowanej historii. Obejmują też zamknięcie po wpisaniu zapytania bez oczekiwania na wynik.
- Stan wewnętrzny jest udostępniany tylko przez Debug z `--ui-testing`; nie trafia do zwykłego interfejsu. Wariant Reduce Motion jest wymuszany argumentem testowym, bez zmiany ustawień użytkownika. Testy nie korzystają z prywatnego pasteboardu ani repozytorium użytkownika.
- Kompilacje Debug i Release arm64. Kontrola stanu ukrytej prezentacji potwierdza zatrzymanie jej własnej pracy; nie jest pomiarem poboru energii całej aplikacji.

## Granice i dalszy odbiór

Pełny profil Instruments/Energy, wiele ekranów/clamshell i fizyczne sleep/lock/wake pozostają w odbiorze etapu. Nie dodano sztucznej sekcji Muzyka: animacje przełączania sekcji i zatrzymywanie renderowania jej postępu zostaną zweryfikowane po integracji 3D. Wspólne usługi oraz działania zlecone przez użytkownika, takie jak usunięcie wpisu lub zmiana ustawień przechwytywania, nie są zatrzymywane przez ukrycie widoku.

Końcowy Release zainstalowano i uruchomiono w `/Applications/MacManager.app` przez scripts/install-local-app.py. Instalator potwierdził ten sam certyfikat Developer ID, bundle ID i designated requirement. Nie resetował danych, ustawień, Keychain ani TCC; poprzedni pakiet zachował w Koszu. Końcowy przebieg testu cykli prezentacji po dopracowaniu przerywania zaniku również przeszedł.
