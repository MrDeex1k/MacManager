# Aktualny stan projektu i dalsza kolejność

Scalone do `main` w PR #8 (`9e2d24c`), 2026-10-12: profile oszczędzania i sleep/wake są wdrożone, a sampler ponownie używa uchwytu GPU. Sieć korzysta z powiadomień SCDynamicStore i rzadszej kontroli awaryjnej. Schowek przechowuje krótkie podglądy i wczytuje pełne treści na żądanie ze wspólnym cache danych 16 MB; wyszukiwanie pozostaje pełnotekstowe. [Pamięć schowka](reports/pamiec-schowka-2026-10-12.md). Wersja na `main`: 0.8.3. [Profile energii](reports/profile-energii-2026-10-06.md), [GPU i sieć](reports/gpu-siec-2026-10-12.md).

Aktualizacja: 2026-09-23. Projekt jest w trakcie końcowego odbioru etapu 1; nie ma jeszcze publicznego wydania DMG. Kroki 1-8 są zaimplementowane i odebrane. W kroku 9 wykonano pełne testy automatyczne, audyt dostępności, 10-minutowy pomiar pracy w tle oraz ręczną próbę na urządzeniu referencyjnym, w tym offline i sleep/wake. Gotowy jest lokalny skrypt budowania, podpisywania i notaryzacji DMG. Autostart z `/Applications` po poprawce rozpoznawania login item został potwierdzony przez właściciela. Pozostają wykonanie i odbiór procesu dystrybucji.

Aktualizacja brancha `fix/launcher-upstream-improvements`, 2026-10-12: kalkulator rozróżnia bity i bajty szybkości transferu. Katalog wybiera najnowszą poprawną kopię aplikacji w folderze, respektując kolejność zakresów, obsługuje symlinki i uzgadnia personalizacje oraz cele skrótów. Menu wyników i zamknięcie personalizacji przywracają fokus wyszukiwarki z ochroną cyklu życia i kompozycji tekstu. [Wdrożenie i walidacja](reports/plan-poprawek-launchera-tinycast-2026-10-12.md). Te zmiany nie są jeszcze scalone do `main`.

## Co działa

- Aplikacja Xcode/SwiftUI dla Apple Silicon i macOS 26+, ciemny interfejs z natywnym Liquid Glass, główne sekcje Przegląd/Czujniki/Sieć/Schowek/Przewijanie/Dock/Ustawienia i zmiana PL/EN bez restartu.
- Lokalny i publiczny IPv4, inwentarz interfejsów, kopiowanie adresów, odświeżanie, wyłączenie odczytu publicznego IP i jawne ograniczenia VPN. Zewnętrzny test ipify przeszedł po zgodzie właściciela.
- Bieżące CPU/GPU/RAM oraz szacowana moc AppleSMC PSTR, jeden sampler, interwał 1/2/5 s, stany loading/unavailable/stale i unieważnianie próbek przy uśpieniu. PSTR został potwierdzony na AC i baterii na urządzeniu testowym; brak czujnika daje stan unavailable.
- Historia ostatnich 300 s w RAM i wykresy Swift Charts CPU/GPU/RAM/mocy z przełącznikiem metryki, skalą czasu, minimum/maksimum i liczbą próbek. Luki powstają po brakach odczytu, uśpieniu i zmianie interwału.
- Odwracanie scrolla myszy w obu osiach, automatyczna klasyfikacja z gestów dotykowych bez list modeli, zachowanie gładzika i bezwładności, jawne stany Dostępności/Monitorowania wprowadzania, sleep/wake i wyłączenia tapu.
- Ikona aplikacji: miętowy szklany monitor ze wskaźnikami na grafitowym tle. AppIcon podłączony do obu konfiguracji Xcode; źródło i komplet rozmiarów są w repozytorium.
- Ikona w pasku menu otwierająca natywny panel Liquid Glass z CPU, GPU, procentem RAM, mocą i adresami IPv4. Panel ma dwie równe akcje: otwarcie okna i zakończenie aplikacji. CPU, GPU, RAM i W można włączać niezależnie obok ikony; domyślnie widoczna jest sama ikona, a po włączeniu dowolnej wartości pasek pokazuje tylko wartości z etykietami.
- Sterowanie ikoną Docka przez politykę aktywacji AppKit, z domyślnie widoczną ikoną podczas pracy z oknem i trwałym przełącznikiem w osobnej sekcji głównej. Zamknięcie głównego okna ukrywa ikonę Docka, pozostawia proces aktywny i zachowuje dostęp przez pasek menu. Scroll ma własną sekcję pomiędzy Siecią i Ustawieniami.
- Autostart przez `SMAppService.mainApp`, rzeczywisty status macOS, obsługa wymaganej zgody i jednorazowa próba domyślnej rejestracji. Start przy logowaniu pozostaje w tle bez głównego okna, a wszystkie usługi uruchamiają się na poziomie procesu.
- Kontrola stabilnych GitHub Releases przy pierwszym starcie i najwyżej raz na 7 dni, ETag, ścisła kwalifikacja tagu i DMG arm64, ręczne sprawdzanie oraz zachowanie potwierdzonego wydania w lokalnym cache.
- Sekcje aktualizacji i diagnostyki w Ustawieniach oraz informacja o dostępnej wersji w panelu paska menu. Diagnostyka korzysta z prywatnych kategorii OSLog, jawnego podglądu i kopiowania tylko na bieżącym Macu.
- Conventional Commits i zakaz znaku Unicode em dash są egzekwowane lokalnymi hookami. Zmiany trafiają na skoncentrowane branche i są scalane do `main` po odbiorze.

## Stan kroków etapu 1

| Krok | Zakres | Stan |
| --- | --- | --- |
| 1 | Prototypy P01–P04 | Narzędzia gotowe, część prób wykonana; walidacja sprzętu/VPN/scrolla nadal częściowa. |
| 2 | Szkielet F1-01 | Gotowy. |
| 3 | Usługi pomiarów F1-02 | Zaimplementowane i sprawdzone lokalnie; szersza macierz sprzętowa nadal do wykonania. |
| 4 | Wykresy i historia F1-03 | Zaimplementowane; retencja i przerwy sprawdzane deterministycznie, wykresy w testach GUI, a fizyczny sleep/wake potwierdzono na urządzeniu referencyjnym. |
| 5 | Sieć F1-04 | Zaimplementowana i sprawdzona lokalnie; dodatkowe wyjścia VPN pozostają nieustalone. |
| 6 | Scroll F1-05 | Zaimplementowany z adaptacją mechanizmu Scroll Reversera; rzeczywiste próby gładzika, myszy i zmiany urządzenia rozpoznane poprawnie, bez list modeli. |
| 7 | Okno/menu/Dock/autostart F1-06 | Zaimplementowane. Pasek menu, Dock, `SMAppService.mainApp`, cykl życia procesu i start przy logowaniu bez okna mają testy automatyczne. Próba podpisanego wydania pozostaje w kroku 9. |
| 8 | Aktualizacje i prywatność F1-07/F1-08 | Gotowy. Harmonogram, kwalifikacja wydania, cache, ETag, UI PL/EN, diagnostyka i prywatność zostały odebrane; szczegóły w [raporcie](reports/etap-1-krok-8.md). |
| 9 | Testy końcowe i wydanie F1-09 | W toku. Punkty 1, 2, 4 i 5 są wykonane; w punkcie 2 potwierdzono metryki, historię, sieć z offline i powrotem połączenia, sleep/wake, cykl życia okna oraz scroll myszy i gładzika; [raport](reports/etap-1-krok-9a.md). Punkt 3 (autostart z instalacji, bez okna i ikony Docka) potwierdził właściciel po poprawce `ea043eb`. Pozostaje podpisane wydanie. |

## Co dalej

1. **Krok 9:** podpis Developer ID, Hardened Runtime, notarization, odbiór DMG i publikacja GitHub Release 0.8.0. Certyfikat Developer ID Application jest dostępny. Konfiguracja profilu notarytool i odbiór dystrybucji pozostają odłożone przez właściciela.

Etap 2 jest scalony do `main` (`7051293`): adapter tylko do odczytu, sampler i modele temperatur/RPM oraz sprzętowy inwentarz M4 Pro. Czujniki są podłączone do wspólnego harmonogramu, mają sekcję Czujniki i trwały wybór °C/°F. Katalog temperatur obejmuje na razie tylko M4 Pro; właściciel potwierdził poprawność temperatur i RPM po niezależnym sprawdzeniu na urządzeniu referencyjnym. Pasek menu ma osobne przełączniki temperatur CPU/GPU i wspólny przełącznik wszystkich wentylatorów, z etykietami nad wartościami. Historia temperatur CPU/GPU oraz osobnych wentylatorów RPM działa przez pięć minut w RAM i pokazuje luki przy braku odczytu lub uśpieniu. [Zakres i wynik prób](../Prototypes/Stage2/README.md). [Pomiar kosztu w tle](reports/etap-2-koszt-tla.md) wykazał średnio 2,338% jednego rdzenia CPU w 10-minutowej próbie i brak narastania RSS. Optymalizację odłożono na później. Rozszerzenie mapowania i próby na pozostałych Macach Apple Silicon nadal są do wykonania. Etap 3A jest zaimplementowany na `feat/stage-3a-clipboard`; szczegóły poniżej. Przyjęta kolejność etapu 3 to: prywatny schowek, pełny launcher, wyspa i muzyka. Wspólna architektura ma obsłużyć oba scenariusze integracji TinyCast, a scenariusz 1 jest pierwszym celem wdrożenia.

## Etap 3A: schowek

Zaimplementowany na `feat/stage-3a-clipboard`, opartym na aktualnym `main`. Nowa sekcja Schowek zawiera historię tekstów i obrazów, wyszukiwanie w RAM, podgląd, przywracanie do systemowego schowka, usuwanie i konfigurację retencji. Od 2026-10-14 historia schowka jest domyślnie włączona zgodnie z decyzją właściciela. Domyślne limity: 50 wpisów, 7 dni, 200 MB.

SQLite przechowuje tylko metadane. Treści i miniatury są zaszyfrowane AES-GCM. Klucz odtwarzany jest z materiału Secure Enclave zapisanego w niesynchronizowanym Keychain. Usługa działa niezależnie od okna, zatrzymuje odczyty po pauzie/odmowie/blokadzie i nie przejmuje skrótów kopiowania ani wklejania.

Weryfikacja: 74 testy Core i dwa nowe testy GUI przechodzą. Rzeczywisty test Secure Enclave/Keychain używa własnego tymczasowego wpisu. Testy interfejsu korzystają z osobnego schowka i danych syntetycznych. Właściciel potwierdził działanie zainstalowanego schowka 3A. Oddzielny odbiór aktualizacji podpisanego wydania pozostaje do wykonania. Nie podmieniano instalacji w `/Applications`. [Raport 3A](reports/etap-3a-schowek.md).

Dalej: pełny launcher lokalny (3B), panel wyspy (3C), integracje Music/Spotify (3D). Publikacja DMG i rozszerzanie mapowania Apple Silicon pozostają niezależnymi zadaniami.

## Etap 3B: launcher, kroki 1-7

Na `feat/stage-3b-launcher`, opartym na branchu 3A, wdrożono rdzeń wyszukiwarki, paletę ze skrótem globalnym oraz katalog aplikacji i poleceń. Ranking i mechanizmy katalogu/panelu/skrótu adaptowano z przypiętej rewizji Tinycast. Paleta działa niezależnie od głównego okna i ustawienia Docka; domyślny skrót to Control + Option + Spacja. Zapytania nie są zapisywane ani wysyłane. [Raport kroków 1-3](reports/etap-3b-launcher-1-3.md).

Wdrożono także personalizację i skróty pozycji, pliki przez Spotlight w wybranych folderach, lokalny kalkulator i wspólny tryb Schowek pod Tab. [Raport kroków 4-7](reports/etap-3b-launcher-4-7.md). Do 3B pozostaje krok 8: pełny odbiór dostępności, IME/Spaces, uprawnień folderów i kosztu pracy w tle.

## Etapy 3C/3D: plan wyspy i muzyki

2026-10-12: właściciel zatwierdził uwzględnienie pięciu priorytetów po analizie konkurencji: stabilny hover, przewidywalny fokus, czytelny schowek, kompaktowy odtwarzacz i animacje ograniczone do potrzebnych momentów. [Plan wdrożenia i odbioru](06-plan-i-testy.md#plan-wyspy-3c-i-integracji-muzyki-3d) obejmuje kroki 3C/3D i scenariusze T22–T26; [specyfikacja interfejsu](02-interfejs.md#wyspa) opisuje zachowanie.

2026-10-13: kroki 1–2 są zaimplementowane lokalnie: czarny panel połączony z górną krawędzią/notchem, hover 150/350 ms bez pollera, świadome przejęcie klawiatury, Escape i przywracanie fokusu. Dostęp z menu aplikacji, panelu paska menu i ustawień; skrót globalny domyślnie nieprzypisany. Panel zawiera pole do odbioru interakcji; schowek i muzyka nie są jeszcze podłączone. Pełna macierz P07 pozostaje otwarta. [Raport wdrożenia i weryfikacji](reports/etap-3c-wyspa-1-2.md).

Kolejne wdrożenie 2026-10-13: krok 3 podłączył wspólny ClipboardService do wyspy. Panel pokazuje historię, miniatury i fragmenty tekstu, wyszukuje oraz przywraca wpis kliknięciem/Enter z „Skopiowano”. Dostępne są usuwanie wpisu, włączenie/pauza i nawigacja strzałkami. Zamknięcie usuwa stan prezentacji i anuluje oczekujące przywracanie. Muzyka pozostaje w 3D, animowane przejścia w kroku 5. [Raport kroku 3](reports/etap-3c-wyspa-3.md).

Krok 5, 2026-10-13: animacje otwierania/zamykania są skończone, oparte na masce Core Animation, z wariantem Reduce Motion. Zamknięcie natychmiast odłącza zawartość schowka i anuluje pracę prezentacji; końcowa animacja pokazuje samą czarną sylwetkę. Ukryty panel nie ma hosta ani zadań prezentacji, a ponowne otwarcie odczytuje bieżący stan wspólnej usługi. 124 testy Core i pięć testów GUI przeszły. Pełny profil Instruments oraz odbiór ekranów/sesji pozostają otwarte; druga sekcja i renderowanie muzyki będą sprawdzane w 3D. [Raport kroku 5](reports/etap-3c-wyspa-5.md).

## Dowody i granice

Aktualizacja 2026-10-03: na branchu 3B wdrożono cache katalogu i ikon launchera, stabilną listę wyników z ochroną przed wykonaniem starego wyniku, anulowalne zapytania Spotlight i wyszukiwanie schowka poza MainActor. Kalkulator respektuje format 12/24h użytkownika; skróty usuniętych aplikacji są zwalniane, a przeniesionych uzgadniane przez LaunchServices. Pozostałe zmiany obejmują naprawę pętli updatera, przyrostowe odświeżanie historii schowka, ograniczenie pracy w tle, wspólny odczyt SMC oraz cache wykresów i paska menu. 98 testów Core Release z rzeczywistym Spotlight i build Release przeszły. Test interfejsu wykonano przez Computer Use po timeoutcie inicjalizacji XCTest UI. Pełny profil Instruments i odbiór na macOS 26 pozostają do wykonania. Narzędzia i CI/CD bez zmian. [Raport wdrożenia](reports/wdrozenie-optymalizacji-2026-10-03.md).

Historyczny odbiór etapu 1: 53 testy Core i 9 testów prototypów przeszło. Czternaście scenariuszy XCTest UI obejmuje nawigację, język z restartem, rzeczywiste metryki z trwałym interwałem, wykresy, trzy przepływy scrolla, ustawienia paska menu, sterowanie Dockiem i oknem, autostart, kontrolę aktualizacji, diagnostykę oraz audyt dostępności pięciu sekcji. Debug i Release kompilują się dla arm64, a plik Release zawiera wyłącznie arm64. Pomiar Release przez 602 s przy zamkniętym oknie wykazał średnio 0,413% CPU, 96,81 MB RSS i brak wzrostu pamięci; szczegóły zawiera [raport kroku 9](reports/etap-1-krok-9a.md).

Raporty szczegółowe: [prototypy](reports/etap-1-krok-1.md), [szkielet](reports/etap-1-krok-2.md), [sieć](reports/etap-1-krok-5.md), [pomiary](reports/etap-1-krok-3.md), [historia i wykresy](reports/etap-1-krok-4.md), [scroll](reports/etap-1-krok-6.md), [model ustawień i cykl życia](reports/etap-1-krok-7a.md), [ikona i panel paska menu](reports/etap-1-krok-7b.md), [Dock i okno](reports/etap-1-krok-7c.md), [autostart i tryb uruchomienia](reports/etap-1-krok-7d.md), [osobne sekcje Docka i scrolla](reports/etap-1-krok-7e.md), [aktualizacje, prywatność i diagnostyka](reports/etap-1-krok-8.md), [testy automatyczne, dostępność i praca w tle](reports/etap-1-krok-9a.md). Projekt ikony i odtwarzanie zasobów: [Design/AppIcon](../Design/AppIcon/README.md).

To nie jest zamknięty odbiór etapu 1. Nie deklarujemy przetestowania wszystkich Maców Apple Silicon, każdej konfiguracji VPN ani kosztu całej aplikacji na podstawie czasu pojedynczego odczytu. Domyślne buildy developerskie są podpisane ad-hoc. Kopia w `/Applications` użyta do odbioru autostartu ma podpis Apple Development; nie jest publicznym wydaniem Developer ID ani wydaniem notarized.

Buildy developerskie mają osobną tożsamość `.Development`, ustawienia i zgody przewijania. Ekran przewijania pokazuje osobno obie zgody, umożliwia ponowną kontrolę i pomaga wskazać uruchomioną kopię w Finderze. Publiczny DMG zachowuje dotychczasowy identyfikator. Nadanie zgód na czystym profilu i ich zachowanie przy aktualizacji podpisanego wydania wymagają jeszcze walidacji.

Weryfikacja 2026-09-20: ponownie przeszły 53 testy Core, 9 testów prototypów, 5 kontroli zdarzeń autostartu i kompilacja Release arm64 bez podpisu. Nie powtarzano pełnego zestawu UI ani pomiaru obciążenia. Najnowsze poprawki: panel 300 pkt, trzy kolory dostępności pomiarów, brak godziny pobrania IP i ukryta sekcja Wygląd.

Publikacja 0.8.0 została odłożona na prośbę właściciela z powodu konfiguracji hasła notaryzacji. Certyfikat Developer ID Application jest dostępny; historyczny brak certyfikatu z 20 września nie jest już aktualną przeszkodą. Prace etapu 2 są niezależne od publikacji.

## Optymalizacje pracy w tle - 2026-10-05

Lokalna aktualizacja 0.8.1 (build 9) ogranicza okresowe kontrole metryk i scrolla, ponownie używa sesji/metadanych SMC, planuje retencję schowka według daty wygaśnięcia i usuwa sekundowy timer ustawień aktualizacji. Punkty dotyczące adaptacyjnego profilu baterii, zbierania metryk na żądanie i powiadomień sieciowych pozostają poza tym zakresem. Szczegóły i wyniki weryfikacji: [raport](reports/optymalizacje-baterii-2026-10-05.md).


Krok 4, 2026-10-13: lokalna integracja Apple Music jest wdrożona w sekcji Muzyka wyspy. Dostępne są metadane, okładka, postęp i trzy podstawowe akcje, czytelne stany zgód/błędów oraz odłączanie pracy przy ukryciu sekcji. 128 testów Core i testy GUI sterowania, odmowy oraz cyklu ukrywania przeszły. W podpisanej instalacji potwierdzono zgodę, stan bez bieżącego utworu oraz metadane, okładkę i aktualizację postępu podczas rzeczywistego odtwarzania. Dodatkowy odbiór na prawdziwym Music potwierdził pauzę/wznowienie, następny/poprzedni oraz zmianę i przywrócenie okładki. Poprzedni zachowuje natywną semantykę: po kilku sekundach najpierw restart utworu, kolejne szybkie kliknięcie cofa w kolejce. Podmiana zachowała certyfikat, bundle ID i designated requirement. Spotify czeka na instalację przez właściciela. [Raport kroku 4](reports/etap-3d-apple-music.md).


2026-10-13: wdrożono szerszy panel 560 × 350, poziome kafelki schowka z menu kontekstowym i klawiaturą oraz odtwarzacz ułożony obok okładki. [Zakres i weryfikacja](reports/etap-3c-wyspa-poziomy-schowek.md).


Dopracowanie wyspy: Muzyka ma trzy kolumny i wysokość 250 punktów; postęp/czas jest pod sterowaniem w prawej kolumnie. Schowek pozostaje szerszą półką o wysokości 375 punktów. Nagłówek ma suwak z dwoma równymi segmentami Liquid Glass. Podmiana zachowała certyfikat i dane; testy sterowania, zgód, zmiany sekcji, geometrii hover oraz schowka przeszły.


Przełączanie wysokości wyspy ma teraz skończoną animację 240 ms z nieruchomą górną krawędzią, kontynuacją od bieżącej ramki przy ponownym wyborze i anulowaniem przy zamknięciu. Reduce Motion zmienia wysokość natychmiast. Testy końcowych wysokości, cykli, hover i wygaszania prezentacji przeszły; nowa podpisana kopia jest zainstalowana w `/Applications`.


Dopracowano rytm przełączania sekcji: niezależny suwak, wygaszenie starej treści, przejście wysokości 280 ms i łagodne pojawienie nowej treści. Osobne anulowanie faz chroni szybkie kolejne wybory i zamknięcie. Testy cykli, Reduce Motion i wygaszania pracy przeszły; podpisana aktualizacja jest zainstalowana.


2026-10-14: uporządkowano podwójny autostart (stara kopia z DerivedData wyłączona i przeniesiona do Kosza), usunięto akcję wyspy z panelu paska menu, ustawiono domyślnie historię schowka i launcher ⌥Q. Interwał 2 s, adaptacja energii i wyspa pozostają domyślnie włączone. 129 testów Core i dwa testy GUI przeszły; podpisana instalacja i bieżące pięć ustawień zweryfikowane. [Raport](reports/ustawienia-autostart-2026-10-14.md).


2026-10-15: zgodnie z końcowym poleceniem właściciela wyspa używa wyłącznie natywnego Liquid Glass, bez wyboru tła. Usunięto dodatkowy cień okna i przycięto zewnętrzną otoczkę materiału do sylwetki wyspy. Dawny zapis wyboru tła nie resetuje pozostałych ustawień. [Raport](reports/wyspa-tlo-2026-10-15.md).

2026-10-15: zmiana wysokości sekcji korzysta z CADisplayLink powiązanego z ekranem wyspy zamiast pętli Task.sleep. Zachowuje jedno drzewo SwiftUI i powierzchnię Glass; nie wymusza dodatkowego layoutu każdej klatki. W trzech próbkach Debug zmierzono 116,4–116,9 callbacków/s na ProMotion. Trzy testy GUI przełączania, cyklu życia i Reduce Motion oraz Release przeszły. [Pomiar i granice weryfikacji](reports/wyspa-promotion-2026-10-15.md).

2026-10-15, powrót do Schowka: usunięto dodatkową pauzę 160 ms przed pokazywaniem zawartości. Karty i stopka od początku dostają docelowy układ, a pierwsze zaznaczenie jest przygotowane przed montowaniem widoku. Pięć testów GUI, w tym trzy cykle z pełną historią 50 syntetycznych wpisów i obrazem, przeszło. [Pomiar i zakres odbioru](reports/wyspa-powrot-schowek-2026-10-15.md).

2026-10-15, zwarty Schowek: stała półka 160 pt, odstęp od filtra 8 pt i od stopki 6 pt zastępują rozciąganie pustej przestrzeni. Wysokość panelu jest teraz sumą obszaru kamery/paska menu i 304 pt. Status jest jasną kapsułą z ikoną stanu, z zachowaniem dotychczasowych komunikatów i akcji.
