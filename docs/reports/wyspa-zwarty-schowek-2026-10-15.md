# Zwarty Schowek i czytelny status - 2026-10-15

Usunięto rozciąganie pionowej przestrzeni wokół kart. Główny stos Schowka ma odstępy 8 pt, półka stałe 160 pt, a stopka odstęp 6 pt od półki i 12 pt dolnego paddingu. Karty pozostają 158 × 140 pt, z 4 pt ochrony obramowania i miejscem na poziomy wskaźnik przewijania. Boczne odstępy nadal wynoszą 30 pt. Muzyka zachowuje swój układ i wysokość 250 pt.

Wysokość Schowka jest sumą obszaru kamery/paska menu i 304 pt zamiast wcześniejszych 375 pt. Na ekranie testowym oznacza to 343 pt, czyli o 32 pt mniej. Zmierzone w GUI odstępy mieszczą się w limitach 18 pt od pola wyszukiwania do karty i 24 pt od karty do dolnego przycisku; na zrzucie wynoszą około 15 i 22 pt. Nie zmniejszono samych podglądów.

Status otrzymał jasny półgruby tekst na subtelnej kapsule, z ikoną i kolorem rozróżniającymi zapisywanie, pauzę, wyłączenie, blokadę, problem uprawnień i potwierdzenie kopiowania. Pozostawiono dotychczasowe komunikaty PL/EN i akcje włączenia, pauzy oraz wznowienia. Potwierdzenie „Skopiowano” pozostaje dostępne dla czytnika ekranu.

Trzy testy GUI przeszły: powtarzane przełączanie z pełną historią 50 syntetycznych wpisów i obrazem, Reduce Motion ze sterowaniem muzyką oraz wyszukiwanie/przywracanie/usuwanie tekstu i obrazu. Test Schowka mierzy odstępy, położenie dolnego przycisku i brak przycięcia obramowania w poziomym viewportcie. Zrzut ze statusem pauzy sprawdzono wizualnie. Release przeszedł kompilację.

Release podmieniono i uruchomiono w /Applications/MacManager.app z tym samym certyfikatem Developer ID, bundle ID i designated requirement. Podpis po podmianie przeszedł weryfikację; działa jeden proces z docelowej instalacji. Instalator nie modyfikował danych, preferencji, Keychain ani TCC.
