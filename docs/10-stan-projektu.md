# Aktualny stan projektu i dalsza kolejność

Aktualizacja: 2026-09-22. Projekt jest w trakcie końcowego odbioru etapu 1; nie ma jeszcze publicznego wydania DMG. Kroki 1-8 są zaimplementowane i odebrane. W kroku 9 wykonano pełne testy automatyczne, audyt dostępności, 10-minutowy pomiar pracy w tle oraz ręczną próbę na urządzeniu referencyjnym, w tym offline i sleep/wake. Gotowy jest lokalny skrypt budowania, podpisywania i notaryzacji DMG. Autostart z `/Applications` po poprawce rozpoznawania login item został potwierdzony przez właściciela. Pozostają wykonanie i odbiór procesu dystrybucji.

## Co działa

- Aplikacja Xcode/SwiftUI dla Apple Silicon i macOS 26+, ciemny interfejs z natywnym Liquid Glass, główne sekcje Przegląd/Sieć/Przewijanie/Dock/Ustawienia i zmiana PL/EN bez restartu.
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

1. **Krok 9:** podpis Developer ID, Hardened Runtime, notarization, odbiór DMG i publikacja GitHub Release 0.8.0. Na 2026-09-20 dostępny jest tylko certyfikat Apple Development; brakuje Developer ID Application oraz wskazanego profilu notarytool.

Etap 2 rozpoczęty na `feat/stage-2`: adapter tylko do odczytu, sampler i modele temperatur/RPM oraz sprzętowy inwentarz M4 Pro. Czujniki są podłączone do wspólnego harmonogramu, mają sekcję Czujniki i trwały wybór °C/°F. Katalog temperatur obejmuje na razie tylko M4 Pro i wymaga niezależnej walidacji; pasek menu ma osobne przełączniki temperatur CPU/GPU i wspólny przełącznik wszystkich wentylatorów, z etykietami nad wartościami. Historia temperatur CPU/GPU oraz osobnych wentylatorów RPM działa przez pięć minut w RAM i pokazuje luki przy braku odczytu lub uśpieniu. [Zakres i wynik pierwszej próby](../Prototypes/Stage2/README.md). Rozszerzony etap 3 pozostaje planowany. Przyjęta kolejność etapu 3 to: prywatny schowek, pełny launcher, wyspa i muzyka. Wspólna architektura ma obsłużyć oba scenariusze integracji TinyCast, a scenariusz 1 jest pierwszym celem wdrożenia.

## Dowody i granice

53 testy Core i 9 testów prototypów przechodzą. Czternaście scenariuszy XCTest UI obejmuje nawigację, język z restartem, rzeczywiste metryki z trwałym interwałem, wykresy, trzy przepływy scrolla, ustawienia paska menu, sterowanie Dockiem i oknem, autostart, kontrolę aktualizacji, diagnostykę oraz audyt dostępności pięciu sekcji. Debug i Release kompilują się dla arm64, a plik Release zawiera wyłącznie arm64. Pomiar Release przez 602 s przy zamkniętym oknie wykazał średnio 0,413% CPU, 96,81 MB RSS i brak wzrostu pamięci; szczegóły zawiera [raport kroku 9](reports/etap-1-krok-9a.md).

Raporty szczegółowe: [prototypy](reports/etap-1-krok-1.md), [szkielet](reports/etap-1-krok-2.md), [sieć](reports/etap-1-krok-5.md), [pomiary](reports/etap-1-krok-3.md), [historia i wykresy](reports/etap-1-krok-4.md), [scroll](reports/etap-1-krok-6.md), [model ustawień i cykl życia](reports/etap-1-krok-7a.md), [ikona i panel paska menu](reports/etap-1-krok-7b.md), [Dock i okno](reports/etap-1-krok-7c.md), [autostart i tryb uruchomienia](reports/etap-1-krok-7d.md), [osobne sekcje Docka i scrolla](reports/etap-1-krok-7e.md), [aktualizacje, prywatność i diagnostyka](reports/etap-1-krok-8.md), [testy automatyczne, dostępność i praca w tle](reports/etap-1-krok-9a.md). Projekt ikony i odtwarzanie zasobów: [Design/AppIcon](../Design/AppIcon/README.md).

To nie jest zamknięty odbiór etapu 1. Nie deklarujemy przetestowania wszystkich Maców Apple Silicon, każdej konfiguracji VPN ani kosztu całej aplikacji na podstawie czasu pojedynczego odczytu. Domyślne buildy developerskie są podpisane ad-hoc. Kopia w `/Applications` użyta do odbioru autostartu ma podpis Apple Development; nie jest publicznym wydaniem Developer ID ani wydaniem notarized.

Buildy developerskie mają osobną tożsamość `.Development`, ustawienia i zgody przewijania. Ekran przewijania pokazuje osobno obie zgody, umożliwia ponowną kontrolę i pomaga wskazać uruchomioną kopię w Finderze. Publiczny DMG zachowuje dotychczasowy identyfikator. Nadanie zgód na czystym profilu i ich zachowanie przy aktualizacji podpisanego wydania wymagają jeszcze walidacji.

Weryfikacja 2026-09-20: ponownie przeszły 53 testy Core, 9 testów prototypów, 5 kontroli zdarzeń autostartu i kompilacja Release arm64 bez podpisu. Nie powtarzano pełnego zestawu UI ani pomiaru obciążenia. Najnowsze poprawki: panel 300 pkt, trzy kolory dostępności pomiarów, brak godziny pobrania IP i ukryta sekcja Wygląd.

Publikacja 0.8.0 została odłożona na prośbę właściciela z powodu konfiguracji hasła notaryzacji. Certyfikat Developer ID Application jest dostępny; historyczny brak certyfikatu z 20 września nie jest już aktualną przeszkodą. Prace etapu 2 są niezależne od publikacji.
