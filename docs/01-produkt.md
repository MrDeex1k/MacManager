# Produkt i wymagania

## Cel

Mac Manager daje szybki dostęp do stanu Maca oraz kilku codziennych narzędzi: niezależnego kierunku przewijania myszy, historii schowka i sterowania muzyką. Najpierw służy właścicielowi do testów, następnie jest publicznie dostępny na GitHub. Oficjalne wydania pozostają bezpłatne, a kod jest otwarty na licencji MIT.

Odbiorca: użytkownik Maca Apple Silicon, który chce odczytów systemowych i wygodnych narzędzi w jednej aplikacji. Produkt nie jest narzędziem do czyszczenia RAM, regulowania chłodzenia ani zarządzania procesami.

## Zakres i identyfikatory

| ID | Faza | Wymaganie |
| --- | --- | --- |
| SYS-01 | 1 | Apple Silicon, minimum macOS 26; bez wersji Intel. |
| SYS-02 | 1 | Swift + SwiftUI; wyłącznie ciemny wygląd z Liquid Glass. |
| SYS-03 | 1 | Interfejs PL/EN, dokumentacja PL, README EN. |
| MET-01 | 1 | Bieżące zużycie CPU, GPU i RAM dla całego komputera. |
| MET-02 | 1 | Chwilowy pobór mocy całego Maca w W, gdy źródło jest zweryfikowane. |
| MET-03 | 1 | Historia do 5 minut w RAM, domyślnie pomiar co 2 s; wybór 1/2/5 s. |
| NET-01 | 1 | Podstawowy lokalny IPv4 i publiczny IPv4. |
| NET-02 | 1 | Dodatkowe adresy publiczne VPN wyłącznie wtedy, gdy można je wiarygodnie ustalić. |
| SCR-01 | 1 | Jeden przełącznik odwracania przewijania myszy, gładzik bez zmian. |
| APP-01 | 1 | Pełne okno, panel w pasku menu oraz praca w tle po zamknięciu okna. |
| APP-02 | 1 | Dock domyślnie widoczny, autostart domyślnie włączony; oba konfigurowalne. |
| BAR-01 | 1 | Domyślnie sama ikona; CPU, RAM i W włączane niezależnie. |
| UPD-01 | 1 | GitHub Releases: automatyczna kontrola raz w tygodniu i kontrola ręczna. |
| SEN-01 | 2 | Temperatura CPU/GPU, wybór °C/°F. |
| SEN-02 | 2 | Odczyt RPM wentylatorów; osobne opcje wskaźników temperatur i wentylatorów. |
| ISL-01 | 3 | Wyspa przy notchu lub w odpowiadającym mu obszarze ekranu bez notcha. |
| ISL-02 | 3 | Rozwijanie najechaniem, opcjonalny konfigurowalny skrót; zwinięta nie pokazuje treści. |
| CLP-01 | 3 | Lokalna trwała historia tekstów i obrazów, bez przejmowania ⌘C. |
| CLP-02 | 3 | Wyszukiwanie tekstów, przywrócenie do schowka i ręczne wklejenie przez ⌘V. |
| CLP-03 | 3 | Limity, usuwanie, pauza, wykluczanie aplikacji i pomijanie oznaczonych poufnych treści. |
| MUS-01 | 3 | Apple Music/Spotify: tytuł, wykonawca, okładka, postęp, play/pause, poprzedni/następny. |
| PRI-01 | 1–3 | Bez kont, reklam, telemetrii, automatycznych raportów i synchronizacji aplikacji. |

## Znaczenie pomiarów

CPU: procent czasu zajętości całego procesora, znormalizowany do 0–100%, a nie suma przekraczająca 100% dla wielu rdzeni. GPU: odczyt ogólnego wykorzystania dostępny dla danego układu; etykieta i definicja mają odpowiadać rzeczywistemu źródłu. Nie zastępować wykorzystania GPU obciążeniem CPU.

RAM: użycie względem całej pamięci zunifikowanej, w GB i procentach. Dodatkowo można pokazać kompresję, swap i presję pamięci w szczegółach, jeśli źródła zostaną zweryfikowane. To decyzja inżynierska, nie rozszerzenie do listy procesów. Algorytm musi dokumentować uwzględniane kategorie; nie traktować całego cache jako pamięci nieodzyskiwalnej.

Waty oznaczają moc, nie energię w Wh, procent baterii, moc znamionową ładowarki ani Energy Impact. Wartość jest próbką/średnią w krótkim oknie źródła, nie matematycznym pomiarem w pojedynczym punkcie czasu. Nie obiecywać pomiaru na gniazdku elektrycznym. Weryfikacja obejmuje to, czy źródło uwzględnia ładowanie baterii i zasilanie akcesoriów. Źródło o niejasnej semantyce nie spełnia MET-02.

Temperatury: osobny pomiar CPU i GPU; decyzja inżynierska — średnia ze zweryfikowanych czujników danej grupy w widoku skrótowym, maksimum i lista dostępnych czujników w szczegółach. Nie mieszać czujników obudowy z temperaturą rdzeni. Nie wykrywać czujników wyłącznie po podobieństwie nazwy.

RPM: każdy fizyczny wentylator oddzielnie w szczegółach; w pasku menu najwyższe bieżące RPM z dostępnych wentylatorów. Brak wentylatorów to „Chłodzenie pasywne”, a zatrzymany wentylator z prawidłowym odczytem to 0 RPM.

## Ustawienia domyślne

| Ustawienie | Wartość |
| --- | --- |
| Wygląd | Ciemny, niezależny od motywu systemu. |
| Język | Systemowy dla PL/EN; EN jako fallback; ręczny wybór PL/EN. |
| Dock / autostart | Włączone; faktyczny stan autostartu odczytywany z macOS. |
| Uruchomienie ręczne / przy logowaniu | Okno przy uruchomieniu ręcznym; tylko tło przy logowaniu. |
| Pasek menu | Ikona, wszystkie liczbowe dodatki wyłączone. |
| Odwrócenie scrolla myszy | Wyłączone do świadomego uruchomienia funkcji. |
| Historia pomiarów | 300 sekund, w RAM; po restarcie pusta. |
| Próbkowanie | 2 s; ustawienia 1, 2, 5 s. |
| Jednostka temperatury | °C; użytkownik może wybrać °F. |
| Automatyczne aktualizacje | Sprawdzanie raz na 7 dni; bez instalacji w tle. |
| Wyspa | Od fazy 3 włączona, bez treści w stanie zwiniętym. |
| Wyspa na pełnym ekranie | Ukryta; opcja pokazywania w ustawieniach. |
| Skrót wyspy | Nieprzypisany, konfigurowalny. |
| Historia schowka | Aktywowana przy konfiguracji funkcji i po dostępności wymaganej zgody systemu. |
| Limity schowka | 50 wpisów, 7 dni, 200 MB; pierwszy osiągnięty limit uruchamia czyszczenie. |

Wartości doprecyzowujące technikę działania, np. sposób inicjalizacji języka i aktywacja schowka, są decyzjami inżynierskimi tego projektu. Nie zmieniają zatwierdzonych domyślnych ustawień Docka ani autostartu.

## Poza zakresem trzech faz

Mac App Store, Intel, macOS starszy niż 26, jasny motyw, kolejne języki, lista procesów i ich zatrzymywanie, wielodniowa historia metryk, eksport pomiarów jako funkcja produktu, regulowanie wentylatorów, profile każdej myszy, przyspieszanie/wygładzanie scrolla, IPv6 w UI, gwarantowana mapa VPN per aplikacja, automatyczne wklejanie, pliki i formatowany tekst w historii, OCR, synchronizacja schowka, biblioteka muzyczna i sterowanie innymi urządzeniami.

Homebrew pozostaje opcjonalnym kanałem instalacji. Funkcje przyszłych faz nie pojawiają się w pierwszej fazie jako aktywne lub pozornie działające kontrolki.

