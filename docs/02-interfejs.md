# Interfejs i zachowanie

## Powierzchnie aplikacji

Pełne okno służy do wykresów i szczegółów; pasek menu do szybkiego odczytu i przełączników; wyspa od fazy 3 do schowka i muzyki. Wszystkie pokazują ten sam stan usług. Otwarcie drugiego widoku nie uruchamia drugiego zestawu pomiarów.

Okno: boczna nawigacja „Przegląd”, „Sieć”, „Przewijanie”, „Dock”, „Wyspa”, od fazy 2 „Czujniki”, od fazy 3 „Schowek”, oraz „Ustawienia”. Przewijanie i Dock są osobnymi sekcjami personalizacji umieszczonymi między Siecią i Ustawieniami. Przegląd zawiera CPU, GPU, RAM, W i wykresy pięciominutowe. Sekcja Schowek umożliwia wygodne przeglądanie tej samej historii co wyspa, także gdy użytkownik wyłączy wyspę.

Liquid Glass jest natywną warstwą interfejsu i kontrolek, nie nakładką utrudniającą odczyt wykresów. Ciemny motyw obowiązuje również w panelach AppKit należących do aplikacji. Systemowe okna uprawnień pozostają pod kontrolą macOS.

## Liquid Glass - domyślny materiał od macOS 26

Minimalny system to macOS 26, więc używamy nowych API bez ścieżki zgodności ze starszym macOS i bez przełącznika włączającego Liquid Glass. System może ograniczyć przezroczystość lub animacje zgodnie z preferencjami dostępności użytkownika; aplikacja tego nie omija.

Kompozycja: ciemna powierzchnia robocza, typografia systemowa i jeden akcent. Sekcje danych rozdzielają odstępy i separatory, bez mozaiki dekoracyjnych kart. Nagłówki opisują zadanie lub stan. Natywne animacje przycisków i panelu bocznego sygnalizują interakcję, bez ciągłych efektów w tle.

| Miejsce | Sposób użycia | Etap |
| --- | --- | --- |
| Nawigacja boczna i pasek narzędzi | Standardowe NavigationSplitView, SidebarCommands i ToolbarItem, z wyglądem dostarczanym przez macOS 26. Bez dodatkowej szklanej nakładki. | 1, szkielet |
| Akcje panelu paska menu | Dwie równe kontrolki .glass do otwarcia okna i zakończenia aplikacji. | 1, integracja systemowa |
| Metryki, adresy, wykresy i opisy | Czytelna powierzchnia treści; szkło w kontrolkach, bez rozmywania samych danych. | 1 |
| Panel paska menu | Systemowe materiały panelu i szklane akcje; bez nakładania kilku warstw szkła. | 1, integracja systemowa |
| Rozwinięta wyspa | Natywny Liquid Glass bez wyboru tła; jasna treść i kontrolki poniżej obszaru kamery. Zwinięty stan nadal pusty. | 3 |

## Pasek menu i Dock

Ikona zawsze pozwala otworzyć panel. Kolejność opcjonalnych wskaźników: CPU, GPU, RAM, W, temperatura CPU, temperatura GPU, wentylatory. Temperatury i RPM dostępne od fazy 2. Szerokości wartości powinny być stabilne, aby pasek nie przesuwał się przy każdym pomiarze.

Panel: bieżące CPU, GPU, procent RAM i moc, lokalny/publiczny IPv4, informacja o dostępnej aktualizacji oraz dwie równe akcje „Otwórz okno” i „Zakończ”. Otwarcie okna zamyka panel. Przycisk kopiowania kopiuje dokładny IPv4. Stan scrolla i osobny przycisk Ustawień nie są pokazywane w panelu. Pełne szczegóły znajdują się w odpowiednich sekcjach głównego okna.

Zamknięcie ostatniego okna nie kończy procesu i automatycznie ukrywa ikonę Docka. Aplikacja pozostaje dostępna z paska menu, a ponowne otwarcie okna przywraca Dock zgodnie z preferencją użytkownika. ⌘Q i „Zakończ” zamykają proces i zatrzymują obserwacje. Nie dopuszczać do ustawienia, które pozbawia użytkownika drogi powrotu do interfejsu.

## Stany odczytu

| Stan | Prezentacja |
| --- | --- |
| Start / pierwszy pomiar | „Oczekiwanie na pomiar”; brak fikcyjnego punktu 0. |
| Odczyt poprawny | Wartość, jednostka i wykres. |
| Nieobsługiwany sprzęt | „Pomiar niedostępny na tym modelu”. |
| Brak zgody | Wyjaśnienie dotyczące konkretnej funkcji i droga do ustawień. |
| Odczyt przeterminowany | Oznaczenie nieaktualności i czas ostatniego pomiaru. |
| Uśpienie / przerwa | Luka na wykresie, bez interpolacji przez brak danych. |
| Brak internetu | Lokalny IP nadal działa; publiczny ma stan offline. |
| Brak wiarygodnego wyjścia VPN | „Adres publiczny nieustalony”, bez zgadywania. |

Decyzja inżynierska: metryka jest przeterminowana po trzech interwałach bez nowego odczytu; adapter może jawnie podać dłuższy okres ważności dla wolniejszego źródła. Po wybudzeniu wynik wymaga nowej próbki.

## Scroll

Jeden przełącznik „Odwróć przewijanie myszy”. Gładzik zachowuje ustawienie systemowe i gesty. Nie ma ustawień każdej myszy ani oddzielnych kontrolek osi. Decyzja inżynierska: zmieniamy znak przewijania myszy w obsługiwanych osiach, zachowując wielkość, tempo, przyciski i modyfikatory zdarzenia.

Przy pierwszym włączeniu funkcji wyjaśniamy potrzebę Dostępności do zmiany scrolla i Monitorowania wprowadzania do pasywnej obserwacji gestów. Osobne stany i przycisk kierują do brakującej zgody. Odmowa nie blokuje monitorowania. Po cofnięciu zgody funkcja pokazuje stan nieaktywny. Nie resetujemy systemowego „naturalnego przewijania”.

## Wyspa

Własny panel przy górnej krawędzi, nie systemowa funkcja Dynamic Island ani modyfikacja sprzętowego notcha. Stan zwinięty nie zawiera okładki, tekstu, metryk ani podglądu schowka.

Górna część panelu dochodzi do krawędzi ekranu i obejmuje wysokość wcięcia; kontrolki zaczynają się poniżej safe area kamery. Kształt ma wklęsłe przejścia do górnej krawędzi oraz zaokrąglone dolne rogi. Od 2026-10-15 (D31, końcowe doprecyzowanie właściciela) jedynym tłem jest natywny Liquid Glass. Zastępuje wcześniejszy czarny wariant D27. Na ekranie bez notcha panel jest zakotwiczony w środku górnej krawędzi.

Wybór ekranu jest automatyczny: aktywny wbudowany ekran MacBooka ma pierwszeństwo. Przy zamkniętej klapie albo na Macu stacjonarnym używamy głównego ekranu. Brak dowolnego wyboru monitora i brak duplikacji na wszystkich ekranach. Zmiana konfiguracji ekranów przelicza geometrię bez pozostawiania panelu poza ekranem.

Obszar aktywacji leży przy notchu; na ekranie bez notcha w środku górnej krawędzi. Fizycznie zasłonięty obszar nie zawiera interaktywnych kontrolek. Należy uwzględnić skalowanie, safe area i pasek menu.

~~~mermaid
stateDiagram-v2
    [*] --> Zwinieta
    Zwinieta --> Rozwinieta: najechanie lub skrot
    Rozwinieta --> Zwinieta: wyjscie kursora po zwloce lub Escape
    Rozwinieta --> Rozwinieta: fokus klawiatury lub menu kontekstowe
    Zwinieta --> Ukryta: pelny ekran lub blokada
    Rozwinieta --> Ukryta: pelny ekran lub blokada
    Ukryta --> Zwinieta: powrot do dostepnego pulpitu
~~~

Decyzje inżynierskie do strojenia prototypem: otwarcie po 150 ms, zamknięcie po 350 ms od opuszczenia całego panelu. Nie zamykać podczas pisania w wyszukiwarce, obsługi skrótem ani interakcji z kontrolką. Escape zamyka i oddaje fokus. Sam hover nie kradnie fokusu bieżącej aplikacji; pole wyszukiwania może otrzymać fokus po świadomej interakcji.

Stabilny hover: obszar aktywacji i rozwinięty panel tworzą ciągły obszar interakcji. Przejście kursora od górnej krawędzi do treści nie zwija panelu. Powrót kursora przed upływem zwłoki anuluje zamknięcie; ruch przy granicy nie powoduje naprzemiennego otwierania i zamykania. Opóźnienia 150/350 ms są wartościami początkowymi do walidacji P07.

Fokus: kliknięcie wyszukiwarki świadomie przenosi fokus do pola; otwarcie z klawiatury umożliwia nawigację bez użycia myszy. Escape zamyka panel i przywraca fokus poprzedniej aplikacji, jeśli jest nadal dostępna. Samo najechanie nie aktywuje pola ani nie przechwytuje pisania w poprzedniej aplikacji.

Domyślnie ukryta nad aplikacją pełnoekranową na swoim ekranie; opcja pokazywania dotyczy zwykłych Spaces pełnoekranowych. Nie deklarujemy nakładania nad ekranem logowania, blokadą ani chronionymi powierzchniami systemu.

Po rozwinięciu dwie sekcje: Schowek i Muzyka. Nie pokazujemy automatycznego toastu z kopiowaną treścią. Ukryta/zwinięta wyspa nie wykonuje ciągłych animacji.

Animacje służą otwarciu, zamknięciu i zmianie sekcji oraz natywnej informacji zwrotnej kontrolek. Bez ciągłej wizualizacji audio. Renderowanie postępu muzyki działa tylko przy widocznej sekcji Muzyka; po zmianie sekcji, zwinięciu lub ukryciu zatrzymujemy zadania prezentacji. Nie zatrzymuje to wspólnych usług schowka ani wymaganej obsługi odtwarzaczy. Ponowne otwarcie pokazuje aktualny stan bez nadrabiania niewidocznych klatek. Przejścia respektują Reduce Motion.

Implementacja kroku 5: okno zachowuje stałą geometrię. Maska Core Animation odsłania panel od górnej krawędzi przez 220 ms i zwija go przez 150 ms; przejścia są skończone i nie wymagają timera odświeżającego każdą klatkę ani ciągłego przeliczania układu SwiftUI. Reduce Motion zastępuje zmianę geometrii zanikiem przez 100 ms. Zaznaczenie wpisu i „Skopiowano” zmieniają się łagodnie przez 120 ms, z wyłączeniem tych efektów przy Reduce Motion. Przy zamykaniu prywatna zawartość i zadania prezentacji są usuwane natychmiast; zwija się tylko sylwetka z wybranym tłem, a po przejściu host jest zwalniany. Blokada, sleep, wyłączenie funkcji, niedostępny pełny ekran i zmiana geometrii zamykają panel natychmiast. Muzyka oraz przejścia między sekcjami pozostają częścią integracji 3D.

## Schowek i muzyka

Stan wdrożenia 2026-10-13: sekcja Muzyka obsługuje Apple Music. Oznaczenie źródła jest stałe; Spotify, przełącznik źródeł i automatyczny wybór są zakresem przyszłego rozszerzenia po instalacji Spotify przez właściciela. [Raport Apple Music](reports/etap-3d-apple-music.md).

Schowek w wyspie: pozioma półka najnowszych wpisów, miniatury, fragmenty tekstu, wyszukiwanie tekstowe, przywrócenie wpisu, usunięcie, pauza. Kliknięcie przywraca wpis do systemowego schowka i daje krótki komunikat „Skopiowano”. Nie wysyła ⌘V do innej aplikacji. Czyszczenie całej historii wymaga potwierdzenia w UI.

W wyspie miniatury pozwalają rozpoznać obraz, a fragmenty tekstu zachowują czytelność także dla długich i wielowierszowych wpisów. Przywrócenie wymaga jednej akcji na wpisie; potwierdzenie „Skopiowano” jest jednoznaczne i nie powtarza jego treści. Wyszukiwanie korzysta ze wspólnej usługi i ochrony przed użyciem nieaktualnego wyniku; miniatury dekodujemy tylko dla widocznych wpisów.

Aktualizacja układu 2026-10-15: panel Schowka ma 560 punktów szerokości i wysokość równą obszarowi kamery/paska menu plus 304 punkty treści i odstępów. Zastępuje poprzednie 375 punktów. Na węższym ekranie szerokość maleje. Nagłówek zawiera kompaktowe zakładki i zamknięcie. Pod wyszukiwaniem pozioma półka pokazuje około trzech kafelków i fragment kolejnego, z większymi miniaturami lub fragmentem tekstu, typem i godziną. Usuwanie jest w menu kontekstowym. Strzałki lewo/prawo zmieniają zaznaczenie, gdy pole wyszukiwania jest puste lub nie ma fokusu; przy wpisanym zapytaniu pozostają edycją kursora. Góra/dół nadal zmienia zaznaczenie, Enter przywraca wybrany wpis, Escape zamyka panel. Przycisk przy polu czyści zapytanie. Stopka pokazuje stan nagrywania i włączenie/pauzę/wznowienie; po przywróceniu przez dwie sekundy pokazuje „Skopiowano”. Oczekujące przywracanie jest anulowane po zamknięciu lub zmianie zapytania. Kopiowanie nie zamyka automatycznie wyspy i nie wykonuje wklejania do innej aplikacji.

Muzyka: lokalne źródło Apple Music albo Spotify; tytuł, wykonawca, okładka, postęp i podstawowe przyciski. Postęp służy do podglądu, bez wymagania przewijania utworu. Jeśli gra jedno źródło, wybieramy je automatycznie; przy dwóch grających utrzymujemy ostatni wybór, umożliwiając zmianę. Nie uruchamiamy odtwarzacza przez samo odpytywanie.

Kompaktowy odtwarzacz pokazuje okładkę, tytuł, wykonawcę, postęp oraz przyciski poprzedni, odtwórz/pauza i następny. Bieżące źródło jest czytelnie oznaczone, a wybór Music/Spotify dostępny bezpośrednio w panelu, bez otwierania ustawień. Długie tytuły nie wypychają kontrolek poza panel i nie uruchamiają ciągłego przewijania tekstu.

Brak okładki nie blokuje odtwarzania: neutralny placeholder. Brak odtwarzacza i odmowa Automatyzacji mają osobne komunikaty.

## Dostępność

PL/EN w String Catalog, bez sklejania przetłumaczonych fragmentów i bez hardkodowania formatów liczb. VoiceOver opisuje wartości, jednostki i przyciski. Stanów nie kodujemy wyłącznie kolorem. Uwzględniamy Reduce Motion, Reduce Transparency oraz Increase Contrast, nawet przy wymuszonym ciemnym motywie.

Wyspa ma alternatywną drogę otwarcia z paska menu; użytkownik klawiatury nie musi najpierw najechać kursorem ani przypisywać skrótu. Szczegóły schowka są także w pełnym oknie.


Układ Muzyki w szerokiej wyspie: trzy kolumny - okładka, metadane oraz sterowanie z postępem i czasem pod przyciskami. Dolne akcje pozostają w rogach. Muzyka ma 250 punktów wysokości, Schowek wysokość obszaru kamery/paska menu + 304 punkty; oba mają 560 punktów szerokości i przyłączenie do fizycznej górnej krawędzi. Wysokość zmienia się po wyborze sekcji w animacji 280 ms z łagodnym startem i końcem; fizyczna górna krawędź pozostaje nieruchoma. Geometrię prowadzi CADisplayLink zsynchronizowany z ekranem wyspy, z preferowaną maksymalną częstotliwością tego ekranu, bez pętli czasowej i wymuszania dodatkowego layoutu co klatkę. Sterownik jest usuwany po przejściu lub jego anulowaniu. Szybkie przełączenie startuje od aktualnej ramki, a zamknięcie anuluje przejście. Treść wygasa przez 75 ms przed wymianą sekcji, a następnie pojawia się przez 140 ms, począwszy od pierwszej klatki CADisplayLink, bez dodatkowej pauzy 160 ms. Wewnętrzny układ sekcji jest od razu liczony dla docelowej wysokości; zewnętrzne okno płynnie odsłania go podczas zmiany rozmiaru. Schowek korzysta z podglądów w pamięci i ustawia zaznaczenie przed zamontowaniem widoku. Suwak ma niezależne sprężyste podświetlenie. Reduce Motion ustawia wysokość i treść natychmiast. Równe segmenty włączonych sekcji na szerokość nagłówka mają natywny Liquid Glass i przesuwane podświetlenie, z Reduce Motion. Praca ukrytej sekcji pozostaje wygaszona.


Boczne odstępy zawartości obu sekcji wynoszą 30 punktów, zgodnie z ostatnim doprecyzowaniem właściciela.


Podczas zmiany wysokości root przyjmuje chwilowy rozmiar hosta i wyrównuje treść do góry. Duża zawartość Schowka może być chwilowo przycięta od dołu; nagłówek i górna krawędź nie przesuwają się. Pośrednie ramki są wyrównane do pikseli ekranu, a aktualizacje geometrii nie uruchamiają dodatkowych animacji warstw.


### Tło wyspy

Jedynym tłem jest natywny SwiftUI glassEffect, delegujący wygląd i adaptację przezroczystości do macOS, w tym systemowych ustawień dostępności. Ustawienia nie oferują wyboru materiału ani suwaka intensywności. Glass obowiązuje we wszystkich sekcjach i podczas końcowej animacji zamykania. Przestarzała zapisana wartość tła jest ignorowana bez resetowania pozostałych preferencji. Panel nie dodaje własnego cienia okna, a materiał jest przycięty do sylwetki wyspy, aby uniknąć podwójnego konturu podczas zmiany wysokości.

Kompaktowy Schowek: odstępy głównego stosu 8 pt, półka ma stałe 160 pt i nie rozciąga pustej przestrzeni nad i pod kartami 140 pt. Stopka oddzielona jest od półki odstępem 6 pt; dolny padding wynosi 12 pt. Boczny padding pozostaje 30 pt. Status ma jasny, półgruby tekst na kapsule oraz ikonę i kolor rozróżniające zapisywanie, pauzę, wyłączenie, blokadę, problem uprawnień i potwierdzenie kopiowania.


### Sekcje i Podcast

Suwak docelowo zawiera Schowek | Muzyka | Podcast | Spotify. Ustawienia wyspy mają osobne przełączniki widoczności wszystkich czterech sekcji. Domyślnie wszystkie są włączone. Ukryte sekcje nie zajmują miejsca w suwaku; pozostałe dzielą szerokość równo. Po wyłączeniu aktywnej sekcji wybierana jest pierwsza dostępna i zatrzymywana praca poprzedniej. Wyłączenie ostatniej sekcji wyłącza całą wyspę. Włączenie głównego przełącznika po takim wyzerowaniu przywraca wszystkie cztery; włączenie wtedy pojedynczej sekcji uruchamia wyspę tylko z nią. Zwykłe wyłączenie wyspy zachowuje niepusty wybór sekcji.

Skróty wewnątrz wyspy: Option+1 Schowek, Option+2 Muzyka, Option+3 Podcast, Option+4 Spotify. Wyłączona sekcja nie reaguje na skrót. Numery pozostają stałe niezależnie od liczby widocznych sekcji. Escape zamyka panel, a Spacja/Enter sterują aktywnym odtwarzaczem.

Podcast steruje aplikacją Apple Podcasts przez Dostępność. Wymaga dostępnego okna odtwarzacza i uprawnienia macOS. Pokazuje rzeczywisty tytuł, stan i procent postępu; otwarty rozszerzony odtwarzacz może udostępnić też nazwę audycji i czasy. Przyciski cofają/przesuwają o interwały ustawione w Podcasts (nie zmieniają odcinka). Po jednorazowym udostępnieniu folderu danych Podcastów przyciskiem w ustawieniach Wyspa okładka jest odczytywana z istniejącego lokalnego cache Podcastów, po jednoznacznym dopasowaniu odcinka w lokalnej bibliotece. Preferowana jest okładka odcinka, następnie audycji. Brak cache lub zgodnego formatu biblioteki daje widoczny symbol zastępczy; nie uruchamiamy wyszukiwania internetowego. Nazwa audycji z lokalnego dopasowania zastępuje datę publikacji. UI wyjaśnia brak uprawnienia/okna i oferuje jawne otwarcie aplikacji. Spotify pozostaje opisaną sekcją oczekującą na późniejszą integrację.


Ustawienia wyspy mają osobną pozycję „Wyspa” w bocznej nawigacji, obok Docka. Zawiera ona włączanie wyspy, wybór sekcji, zachowanie na pełnym ekranie i skrót. Ogólne „Ustawienia” nie powielają tych kontrolek.
