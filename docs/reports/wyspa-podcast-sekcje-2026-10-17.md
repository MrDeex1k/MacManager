# Wyspa: cztery sekcje i Apple Podcasts

Data: 2026-10-17. Wersja gałęzi: 0.8.8 (12).

## Zakres

- Schowek | Muzyka | Podcast | Spotify, wspólne podświetlenie Liquid Glass, stałe skróty Option+1...4 i opisy dostępności.
- Ustawienia włączania sekcji. Wyłączenie ostatniej wyłącza wyspę; ponowne włączenie głównego przełącznika przy pustym wyborze przywraca wszystkie. Włączenie pojedynczej sekcji z pustego wyboru uruchamia tylko ją. Niepusty wybór przetrwa zwykłe wyłączenie i restart.
- Wyłączenie bieżącej sekcji wybiera pierwszą dostępną. Ukryte przyciski nie zajmują miejsca; ich skróty są ignorowane. Wyłączenie wyspy usuwa host i zatrzymuje pracę prezentacji.
- Osobny czytnik Apple Podcasts, wspólny model sterowania i jawne stany niedostępności. Spotify pozostaje sekcją z informacją o odłożonej integracji.

## Apple Podcasts: granice publicznego interfejsu

Na lokalnej wersji Podcasts 1.1.0 nie ma słownika Apple Events; sdef zwraca -10827. Adapter korzysta z publicznego Accessibility, skierowanego do istniejącego procesu com.apple.podcasts. Wymaga uprawnienia Dostępność i dostępnego okna odtwarzacza. Nie otwiera aplikacji automatycznie i nie wywołuje dialogu zgody przy samym odczycie.

Tytuł, stan odtwarzania, pozycja procentowa i natywne kontrolki są dostępne w miniPlayer. Rozszerzony odtwarzacz udostępnia rzeczywiste czasy. Gdy usuwa oddzielne pole tytułu miniPlayer, adapter zachowuje pełną połączoną etykietę daty, odcinka i audycji, bez zgadywania granic nazw zawierających przecinki. Bez czasów UI pokazuje procent, bez wymyślania długości odcinka. Publiczne AX nie udostępnia pikseli okładki; używany jest symbol Podcastów.

Cofanie i przewijanie zachowują interwały ustawione w Podcasts, np. 15 i 30 sekund. Nie są to przyciski poprzedniego/następnego odcinka. Akcje korzystają z AXPress na przyciskach źródła, bez globalnych skrótów. [Skróty Apple Podcasts](https://support.apple.com/guide/podcasts/keyboard-shortcuts-podcd31cff4/mac) dokumentują także semantykę odtwarzania i przewijania samej aplikacji.

Odczyt zaczyna od AXWindows, pomijając drzewo menu. Wspiera osobne kontrolki miniPlayer i nowPlaying, ponieważ po zakończeniu rozwijania Podcasts usuwa miniPlayer. Pole isPlaying w identyfikatorze potrafi być nieaktualne po AXPress; w obsługiwanych PL/EN aktualna etykieta Odtwarzaj/Pauza ma pierwszeństwo. Osobny test regresji pokrywa tę rozbieżność.

## Weryfikacja

- 139 testów Core przeszło: dekodowanie starych ustawień, wybór sekcji i zależność enabled/sections, zapis po restarcie, parsowanie czasów Podcastów, brak wymyślonych metadanych, niezależność czytników i zatrzymanie ukrytej usługi.
- GUI: cztery przyciski, Option+1...4 również z fokusem w wyszukiwarce, odtwórz/pauza, przewijanie, Spacja i wygaszanie czytnika po przejściu do Spotify przeszły.
- GUI: kontrolowane stany braku uprawnienia i brak dostępnego okna Podcasts przeszły. Testy nie zmieniają rzeczywistej bazy TCC.
- GUI: hover i Escape/przywrócenie fokusu przeszły. Zawieszenie i wznowienie sesji wywołują rzeczywiste ścieżki koordynatora w kontrolowanym trybie Debug; ukrycie zatrzymuje odczyty.

Fizyczne uśpienie, blokada komputera i pełna macierz Spaces/fullscreen nie zostały odebrane na rzeczywistej sesji. Próba XCTest przejścia w fullscreen utraciła dostęp do okna i nie stanowi pozytywnego wyniku; scenariusz pozostaje do odbioru ręcznego. Nie blokowano ani nie usypiano komputera właściciela.

Test ustawień GUI przeszedł: tylko Spotify, wyłączenie ostatniej sekcji, nieaktywna akcja otwarcia wyspy i przywrócenie wszystkich czterech głównym przełącznikiem. Test ujawnił potrzebę przewijania kontrolek w całości do viewportu; kliknięcie przyciętego przełącznika nie jest wiarygodną akcją testową. Regresja zmiany wysokości sekcji oraz zawieszenia/wznowienia również przeszła.

W finalnej podpisanej instalacji 0.8.8 (12) potwierdzono odczyt prawdziwego odcinka w miniPlayer i pełnym nowPlaying. Przewinięcie zmieniło 0:00 na 0:30, cofnięcie na 0:15; odtwarzanie pokazało Pauzę, a pauza przywróciła Odtwórz. Pełny tryb pokazał rzeczywiste 55:57, miniaturowy tryb procent postępu. Po próbie przywrócono pauzę, 0:00 i miniaturowy widok źródła.

Release przeszedł. Instalator porównał bundle ID i designated requirement z istniejącą aplikacją, podpisał tym samym certyfikatem 89BB0A8D7F01DE8676FBAE22B17B3D5643F9EC00 i uruchomił /Applications/MacManager.app. UserDefaults, Keychain, Application Support i TCC nie były usuwane ani resetowane. Kontrola końcowa potwierdza pojedynczy proces z /Applications.

Doprecyzowanie nawigacji: Wyspa ma osobną stronę w pasku bocznym, obok Docka. Wszystkie dotychczasowe preferencje i skrót przeniesiono z ogólnych Ustawień; zapisane wartości pozostają bez zmian.

Uzupełnienie w 0.8.9: zamiast stałego placeholdera adapter odczytuje okładkę z lokalnego cache Podcastów i nazwę audycji z jednoznacznego dopasowania biblioteki tylko do odczytu. [Szczegóły poprawki](wyspa-okladki-podcast-2026-10-17.md).
