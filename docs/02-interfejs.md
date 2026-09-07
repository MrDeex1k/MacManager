# Interfejs i zachowanie

## Powierzchnie aplikacji

Pełne okno służy do wykresów i szczegółów; pasek menu do szybkiego odczytu i przełączników; wyspa od fazy 3 do schowka i muzyki. Wszystkie pokazują ten sam stan usług. Otwarcie drugiego widoku nie uruchamia drugiego zestawu pomiarów.

Okno: boczna nawigacja „Przegląd”, „Sieć”, od fazy 2 „Czujniki”, od fazy 3 „Schowek”, oraz „Ustawienia”. Przegląd zawiera CPU, GPU, RAM, W i wykresy pięciominutowe. Sekcja Schowek umożliwia wygodne przeglądanie tej samej historii co wyspa, także gdy użytkownik wyłączy wyspę.

Liquid Glass jest natywną warstwą interfejsu i kontrolek, nie nakładką utrudniającą odczyt wykresów. Ciemny motyw obowiązuje również w panelach AppKit należących do aplikacji. Systemowe okna uprawnień pozostają pod kontrolą macOS.

## Liquid Glass — domyślny materiał od macOS 26

Minimalny system to macOS 26, więc używamy nowych API bez ścieżki zgodności ze starszym macOS i bez przełącznika włączającego Liquid Glass. System może ograniczyć przezroczystość lub animacje zgodnie z preferencjami dostępności użytkownika; aplikacja tego nie omija.

Kompozycja: ciemna powierzchnia robocza, typografia systemowa i jeden akcent. Sekcje danych rozdzielają odstępy i separatory, bez mozaiki dekoracyjnych kart. Nagłówki opisują zadanie lub stan. Natywne animacje przycisków i panelu bocznego sygnalizują interakcję, bez ciągłych efektów w tle.

| Miejsce | Sposób użycia | Etap |
| --- | --- | --- |
| Nawigacja boczna i pasek narzędzi | Standardowe NavigationSplitView, SidebarCommands i ToolbarItem, z wyglądem dostarczanym przez macOS 26. Bez dodatkowej szklanej nakładki. | 1, szkielet |
| Akcja otwarcia szczegółów sieci | Natywny styl przycisku .glass; system obsługuje stany interakcji i dostępność. | 1, szkielet |
| Metryki, adresy, wykresy i opisy | Czytelna powierzchnia treści; szkło w kontrolkach, bez rozmywania samych danych. | 1 |
| Panel paska menu | Systemowe materiały panelu i szklane akcje; bez nakładania kilku warstw szkła. | 1, integracja systemowa |
| Rozwinięta wyspa | Materiał panelu i grupy akcji; dobór kontrastu na rzeczywistym tle. Zwinięty stan nadal pusty. | 3 |

## Pasek menu i Dock

Ikona zawsze pozwala otworzyć panel. Kolejność opcjonalnych wskaźników: CPU, RAM, W, temperatura CPU, temperatura GPU, wentylatory. Temperatury i RPM dostępne od fazy 2. Szerokości wartości powinny być stabilne, aby pasek nie przesuwał się przy każdym pomiarze.

Panel: bieżące wartości, lokalny/publiczny IPv4, stan scrolla, informacja o dostępnej aktualizacji oraz „Otwórz okno”, „Ustawienia”, „Zakończ”. Kliknięcie adresu lub przycisku kopiowania kopiuje dokładny IPv4. Pełne szczegóły VPN znajdują się w sekcji Sieć.

Zamknięcie ostatniego okna nie kończy procesu. ⌘Q i „Zakończ” zamykają go, zatrzymując obserwacje. Ukrycie Docka nie usuwa ikony z paska menu. Nie dopuszczać do ustawienia, które pozbawia użytkownika drogi powrotu do interfejsu.

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

Przy pierwszym włączeniu funkcji wyjaśniamy potrzebę Dostępności. Odmowa nie blokuje monitorowania. Po cofnięciu zgody funkcja pokazuje stan nieaktywny. Nie resetujemy systemowego „naturalnego przewijania”.

## Wyspa

Własny panel przy górnej krawędzi, nie systemowa funkcja Dynamic Island ani modyfikacja sprzętowego notcha. Stan zwinięty nie zawiera okładki, tekstu, metryk ani podglądu schowka.

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

Domyślnie ukryta nad aplikacją pełnoekranową na swoim ekranie; opcja pokazywania dotyczy zwykłych Spaces pełnoekranowych. Nie deklarujemy nakładania nad ekranem logowania, blokadą ani chronionymi powierzchniami systemu.

Po rozwinięciu dwie sekcje: Schowek i Muzyka. Nie pokazujemy automatycznego toastu z kopiowaną treścią. Ukryta/zwinięta wyspa nie wykonuje ciągłych animacji.

## Schowek i muzyka

Schowek: lista najnowszych wpisów, miniatury, fragmenty tekstu, wyszukiwanie tekstowe, przywrócenie wpisu, usunięcie, pauza. Kliknięcie przywraca wpis do systemowego schowka i daje krótki komunikat „Skopiowano”. Nie wysyła ⌘V do innej aplikacji. Czyszczenie całej historii wymaga potwierdzenia w UI.

Muzyka: lokalne źródło Apple Music albo Spotify; tytuł, wykonawca, okładka, postęp i podstawowe przyciski. Postęp służy do podglądu, bez wymagania przewijania utworu. Jeśli gra jedno źródło, wybieramy je automatycznie; przy dwóch grających utrzymujemy ostatni wybór, umożliwiając zmianę. Nie uruchamiamy odtwarzacza przez samo odpytywanie.

Brak okładki nie blokuje odtwarzania: neutralny placeholder. Brak odtwarzacza i odmowa Automatyzacji mają osobne komunikaty.

## Dostępność

PL/EN w String Catalog, bez sklejania przetłumaczonych fragmentów i bez hardkodowania formatów liczb. VoiceOver opisuje wartości, jednostki i przyciski. Stanów nie kodujemy wyłącznie kolorem. Uwzględniamy Reduce Motion, Reduce Transparency oraz Increase Contrast, nawet przy wymuszonym ciemnym motywie.

Wyspa ma alternatywną drogę otwarcia z paska menu; użytkownik klawiatury nie musi najpierw najechać kursorem ani przypisywać skrótu. Szczegóły schowka są także w pełnym oknie.

