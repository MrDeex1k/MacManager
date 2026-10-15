# Wyspa - poziomy schowek i szeroki układ

2026-10-13. Zmiana zatwierdzona przez właściciela po przeglądzie kierunku wizualnego NotchNook, Alcove i Atoll.

Panel docelowo ma 560 × 350 punktów, licząc obszar kamery; szerokość ogranicza ekran, a wysokość ma minimum na treść. Rozszerza się symetrycznie wokół notcha i pozostaje przy fizycznej górnej krawędzi. Kompaktowe zakładki zastępują osobny tytuł i etykietę sekcji.

Schowek ma poziomy LazyHStack z kafelkami 158 × 140 punktów. Widać około trzech wpisów oraz fragment kolejnego. Tekst ma większy podgląd, obraz miniaturę; stopka kafelka pokazuje typ, godzinę lub potwierdzenie kopiowania. Kliknięcie przywraca wpis, menu kontekstowe usuwa. Wyszukiwanie i pauza nagrywania korzystają z tej samej usługi i danych. Lewo/prawo wybiera kafelki przy pustym lub nieaktywnym polu wyszukiwania; wpisane zapytanie zachowuje zwykłą edycję kursora. Góra/dół nadal wybiera, Enter przywraca, Escape zamyka. Zaznaczony wpis przewija się do środka półki.

Muzyka korzysta z tej samej geometrii: większa okładka po lewej, metadane i przyciski po prawej, postęp pod nimi. Nie zmieniono protokołu Apple Music ani zakresu zgód. Animacje i Reduce Motion pozostają skończone; zamknięcie odłącza prywatny host i pracę prezentacji.

Dane, schema repozytorium, bundle ID i certyfikat pozostają takie same. Instalacja używa dotychczasowego skryptu sprawdzającego designated requirement; nie resetuje TCC ani ustawień.


## Weryfikacja i instalacja

Buildy Debug i Release przeszły. Sześć testów GUI przeszło: wspólny schowek (poziome rozmieszczenie, klawiatura, wyszukiwanie, przywrócenie, usunięcie z menu), geometria i hover, fokus/Escape, sterowanie Music i zatrzymanie pracy, ukrywanie/ponowne otwieranie oraz Reduce Motion. Pierwsza próba usuwania w teście użyła niewłaściwej etykiety systemowego menu; poprawiono selektor na Delete item i test przeszedł.

Po instalacji sprawdzono wygląd obu sekcji oraz rzeczywiste przewijanie poziome do starszych wpisów i powrót. Istniejąca historia została zachowana. Installer potwierdził zgodność designated requirement, podpisał pakiet tym samym Developer ID i uruchomił `/Applications/MacManager.app`. Poprzedni pakiet pozostaje w Koszu. Nie zmieniono danych ani zgód TCC.


Dopracowanie kontrolek: akcje otwarcia/odświeżenia/zgody w Muzyce oraz włączenia/pauzy/wznowienia i zgody w Schowku używają natywnego stylu bordered, rozmiaru regular i czytelnej etykiety. Kafelki pozostają własnymi obramowanymi przyciskami przywracania.


Dalsze dopracowanie Muzyki: trzy kolumny (okładka 80 px, metadane, sterowanie i postęp/czas w prawej kolumnie 160 px). Panel Muzyki jest niższy - około 280 punktów; Schowek zachowuje 350. Zmiana sekcji aktualizuje ramkę od fizycznej górnej krawędzi, ograniczenia rozmiaru i maskę hosta; nie stosuje animowanego resize okna. Szeroki suwak zastąpił krótki Picker: dwa równe segmenty, natywny glassEffect i przesuwane podświetlenie zaznaczenia. Akcje odświeżania/otwarcia nadal pozostają w dolnych rogach.


Odbiór kompaktowej Muzyki: buildy Debug/Release przeszły. Testy GUI potwierdziły sterowanie i zatrzymanie pracy po zmianie sekcji, panel Muzyki poniżej 300 punktów, odmowę zgody i powrót do schowka; testy hover/geometrii i przywracania/usuwania schowka również przeszły. Podczas dopracowania suwaka poprawiono selektory oraz usunięto dziedziczenie identyfikatora dostępności kontenera, które przesłaniało identyfikatory segmentów. Wizualnie sprawdzono podpisaną instalację: dwa równe segmenty Liquid Glass, niższy panel i dolne akcje w rogach. Instalacja zachowała certyfikat i dane.


Kolejne dopracowanie na prośbę właściciela: zamknięcie jest czerwonym okrągłym przyciskiem 28 punktów, kolumna sterowania i czasu ma 208 zamiast 160 punktów i rozsuwa przyciski na swoją szerokość. Muzyka jest niższa o 15 punktów (około 265); zmniejszono odstępy pionowe, zachowując dolne akcje w rogach.


Weryfikacja ostatniej korekty: Release oraz testy GUI sterowania/zamknięcia/przełączania sekcji i odmowy zgody przeszły. Zainstalowano w `/Applications` tym samym certyfikatem, z zgodnym designated requirement i zachowaniem danych.


Ostatnia korekta proporcji: Muzyka ma dokładnie 250 punktów wysokości, sterowanie/postęp 234 punkty (+12,5%), a boczny padding obu sekcji wynosi 24 zamiast 22 punktów (+9,1%). Komunikaty niedostępności odtwarzacza są w kolumnie metadanych, aby dolne przyciski mieściły się w mniejszym panelu.


Ostateczna wartość bocznych odstępów po doprecyzowaniu przez właściciela: 30 punktów w obu sekcjach. Wysokość Muzyki pozostaje 250 punktów, prawa kolumna 234 punkty.


Animowana wysokość: przełączenie sekcji interpoluje ramkę przez 240 ms (smoothstep) ze stałą górną krawędzią. Host dopasowuje bounds i maskę, nie tworząc nowej zawartości przy każdej klatce. Zadanie należy do koordynatora przejść i jest anulowane przy zamknięciu, zmianie ekranu lub kolejnym wyborze. Nowe przejście zaczyna się od rzeczywistej bieżącej ramki. Hover używa aktualnej ramki okna, a po zakończeniu blokowane są końcowe min/max size. Reduce Motion ustawia docelową ramkę bez animacji wysokości.


Odbiór animacji wysokości: buildy Debug/Release przeszły. Testy GUI sprawdziły końcowe wysokości 250/350, serię trzech powrotów między sekcjami, sterowanie muzyką i zwolnienie pracy, wariant Reduce Motion, hover oraz wielokrotne zamknięcia/otwarcia. Jedna próba cykli utraciła widoczność panelu przed pierwszym kliknięciem; powtórzenie przeszło. W podpisanej instalacji sprawdzono końcowy układ Muzyki po przełączeniu. Instalacja zachowała certyfikat, bundle ID, designated requirement i dane. Profil płynności w Instruments oraz pełna macierz ekranów/sesji pozostają osobnym odbiorem.


Korekta przycinania obramowań Schowka: docelowa wysokość wzrosła o 25 punktów do 375. Półka ma minimalną wysokość 164 punktów oraz 4 punkty luzu nad i pod kafelkami; mieści pełny kafelek 140 punktów i pasek przewijania. Muzyka pozostaje na 250 punktach. Test odbioru porównuje pionowe granice kafelka z obszarem przewijania.


Odbiór korekty obramowań: trzy testy GUI przeszły - geometria/hover, zmiany wysokości i sterowanie Muzyką, oraz schowek z porównaniem pełnych granic kafelka do viewportu. Zrzut z fikcyjnymi wpisami potwierdził wizualnie pełne narożniki i obramowania. Release przeszedł; podmiana w `/Applications` zachowała certyfikat i dane.


Dopracowanie przełączania: wybrana sekcja suwaka zmienia się natychmiast, a widoczna treść wygasa przez 75 ms. Dopiero wtedy poprzednia usługa jest odłączana i aktywowana nowa sekcja. Po 70 ms nowa treść pojawia się przez 160 ms. Geometria zmienia się przez 280 ms krzywą smootherstep, z zerową prędkością i przyspieszeniem na końcach. Odświeżanie dopasowano do maksymalnej częstotliwości ekranu, do 120 Hz, wyłącznie podczas skończonego przejścia. Ramka i host są aktualizowane przed odrysowaniem, co ogranicza pokazywanie poprzedniego układu w klatce. Suwak ma osobną sprężystą animację.

Osobne anulowanie wymiany treści chroni szybkie kolejne wybory i zamknięcie przed opóźnionym odtworzeniem ukrytej sekcji. Ukryta zawartość nie przyjmuje interakcji. Reduce Motion pomija zarówno fazowanie treści, jak i ruch wysokości.


Odbiór dopracowania przejść: Debug/Release i trzy testy GUI przeszły (seria przełączeń ze sterowaniem, ten sam scenariusz z Reduce Motion, ukrywanie/ponowne otwieranie bez pozostawionej pracy). Końcowy układ po przełączeniu sprawdzono w podpisanej instalacji. Nowy pakiet w `/Applications` zachowuje certyfikat, designated requirement i dane.


## Regresja drgania podczas przełączania

Nagranie właściciela ujawniło przejściowe przesunięcie nagłówka przy rozszerzaniu z Muzyki do Schowka. Testy końcowych wysokości tego nie wykrywały. Root SwiftUI przyjmował minimalny rozmiar treści i centrował za dużą zawartość w chwilowo mniejszym hoście. Naprawa jawnie ustawia minWidth/minHeight na zero i wyrównanie topLeading, aby akceptować aktualną ramkę i kotwiczyć górę.

Wysokości pośrednie są zaokrąglane do pikseli backing scale; zmiana ramek hosta, hosting view i maski odbywa się w transakcji bez domyślnych animacji warstw. Nowa treść pojawia się później (160 ms po rozpoczęciu zmiany geometrii), ograniczając widoczną kompresję dolnej części.

Nowy test DEBUG wymusza Schowek w ramce 250 punktów, odtwarzając warunki pośrednie. Pierwsza korekta samego wyrównania nie przeszła tej próby; pełna korekta ograniczeń rozmiaru przeszła. Test porównuje pozycje segmentów i zamknięcia między sekcjami oraz sprawdza, że nagłówek nie trafia do obszaru przy kamerze. Cykle przełączania, hover i Reduce Motion przeszły. Release przeszedł.
