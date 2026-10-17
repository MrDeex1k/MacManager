# Okładki Apple Podcasts w wyspie

Data: 2026-10-17. Wersja: 0.8.9 (13).

Poprzedni adapter miał wyłącznie symbol zastępczy; publiczne AX nie przekazuje pikseli okładki. Dodano opcjonalny adapter lokalnego cache. Dopasowanie dokładnego tytułu i, jeśli dostępna, audycji pochodzi z MTLibrary.sqlite otwartego z SQLITE_OPEN_READONLY. Niepewne dopasowanie jest odrzucane. Dostępna okładka odcinka ma pierwszeństwo przed okładką audycji; wybierany jest mały ostry wariant cache, bez plików blurred. Nazwa audycji zastępuje datę publikacji. Dane cache oraz biblioteka nie są modyfikowane, żaden URL nie jest pobierany, tytuł nie opuszcza komputera.

Pliki wejściowe mają limit 8 MB, miniatura ImageIO 256 px i 1 MB PNG. Pamięć obejmuje jedną bieżącą miniaturę i metadane; jest zwalniana po ukryciu. Odczyt nie zachodzi przy ukrytej sekcji; brakujące dane ponawiają próbę po 30 s. Ustawienia Wyspa zawierają jednorazowy systemowy wybór konkretnego folderu danych Podcastów. Zgoda jest zapamiętana jako security-scoped bookmark tylko do odczytu; zakres jest otwierany i zamykany wokół odczytu. Nie wymaga Pełnego dostępu do dysku. Bez zgody pozostaje symbol zastępczy. Zmiana schematu biblioteki, brak pliku lub odmowa dostępu pozostawiają widoczny symbol zastępczy. Format biblioteki/cache jest szczegółem implementacyjnym Apple i może się zmienić.

143 testy Core przeszły. Nowe testy sprawdzają pierwszeństwo odcinka, wybór ostrego cache audycji, etykiety z przecinkami, odrzucanie powtarzających się tytułów, brak pomylenia obrazów i brak modyfikacji/utworzenia biblioteki przy odczycie.


Rzeczywisty odczyt początkowo blokowała ochrona danych innych aplikacji w macOS (SystemPolicyAppDataDetailed). Nie obchodzono jej przez proces pomocniczy ani Pełny dostęp do dysku. Właściciel wyraził zgodę na konkretny folder, a udostępnienie wykonano przez NSOpenPanel wskazujący wyłącznie folder Podcastów. Testy UI nie otwierają rzeczywistego panelu zgody ani nie odczytują tego bookmarka.

Po udostępnieniu folderu w zainstalowanej aplikacji potwierdzono wizualnie okładkę Futura Podcast oraz nazwę audycji przy bieżącym odcinku. Po pełnym zamknięciu i ponownym uruchomieniu MacManager okładka nadal się wyświetla bez ponownego wyboru folderu. Sprawdzono również niezmienione wyświetlanie okładki F1 The Album w Apple Music. Nie sterowano odtwarzaniem ani nie zmieniano bieżących odcinków/utworów podczas tej próby.

Końcowa regresja GUI osobnej strony Wyspa oraz wyłączania/przywracania sekcji przeszła. Ponowny przebieg Core: 143/143. Release dla obu architektur przeszedł.
