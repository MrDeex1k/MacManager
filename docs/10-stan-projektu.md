# Aktualny stan projektu i dalsza kolejność

Aktualizacja: 2026-09-18. Projekt jest w trakcie etapu 1; nie ma jeszcze publicznego wydania DMG. Kroki 1-8 są zaimplementowane i odebrane. W kroku 9 wykonano pełne testy automatyczne, audyt dostępności, 10-minutowy pomiar pracy w tle oraz część ręcznej próby na urządzeniu referencyjnym. Pozostają próby offline i sleep/wake, autostart z instalacji oraz odbiór dystrybucji.

## Co działa

- Aplikacja Xcode/SwiftUI dla Apple Silicon i macOS 26+, ciemny interfejs z natywnym Liquid Glass, główne sekcje Przegląd/Sieć/Przewijanie/Dock/Ustawienia i zmiana PL/EN bez restartu.
- Lokalny i publiczny IPv4, inwentarz interfejsów, kopiowanie adresów, odświeżanie, wyłączenie odczytu publicznego IP i jawne ograniczenia VPN. Zewnętrzny test ipify przeszedł po zgodzie właściciela.
- Bieżące CPU/GPU/RAM oraz szacowana moc AppleSMC PSTR, jeden sampler, interwał 1/2/5 s, stany loading/unavailable/stale i unieważnianie próbek przy uśpieniu. PSTR został potwierdzony na AC i baterii na urządzeniu testowym; brak czujnika daje stan unavailable.
- Historia ostatnich 300 s w RAM i wykresy Swift Charts CPU/GPU/RAM/mocy z przełącznikiem metryki, skalą czasu, minimum/maksimum i liczbą próbek. Luki powstają po brakach odczytu, uśpieniu i zmianie interwału.
- Odwracanie scrolla myszy w obu osiach, automatyczna klasyfikacja z gestów dotykowych bez list modeli, zachowanie gładzika i bezwładności, jawne stany Dostępności/Monitorowania wprowadzania, sleep/wake i wyłączenia tapu.
- Ikona aplikacji: miętowy szklany monitor ze wskaźnikami na grafitowym tle. AppIcon podłączony do obu konfiguracji Xcode; źródło i komplet rozmiarów są w repozytorium.
- Ikona w pasku menu otwierająca natywny panel Liquid Glass z metrykami, adresami IPv4, stanem scrolla oraz przejściem do okna i Ustawień. CPU, RAM i W można włączać niezależnie obok ikony; domyślnie widoczna jest sama ikona.
- Sterowanie ikoną Docka przez politykę aktywacji AppKit, z domyślnie widoczną ikoną i trwałym przełącznikiem w osobnej sekcji głównej. Scroll również ma własną sekcję pomiędzy Siecią i Ustawieniami. Zamknięcie głównego okna pozostawia proces aktywny, a aplikację można ponownie otworzyć z Docka, paska menu lub skrótu.
- Autostart przez `SMAppService.mainApp`, rzeczywisty status macOS, obsługa wymaganej zgody i jednorazowa próba domyślnej rejestracji. Start przy logowaniu pozostaje w tle bez głównego okna, a wszystkie usługi uruchamiają się na poziomie procesu.
- Kontrola stabilnych GitHub Releases przy pierwszym starcie i najwyżej raz na 7 dni, ETag, ścisła kwalifikacja tagu i DMG arm64, ręczne sprawdzanie oraz zachowanie potwierdzonego wydania w lokalnym cache.
- Sekcje aktualizacji i diagnostyki w Ustawieniach oraz informacja o dostępnej wersji w panelu paska menu. Diagnostyka korzysta z prywatnych kategorii OSLog, jawnego podglądu i kopiowania tylko na bieżącym Macu.
- Conventional Commits egzekwowane lokalnym hookiem. Wszystkie kroki etapu trafiają na jeden branch, bez automatycznego merge do main.

## Stan kroków etapu 1

| Krok | Zakres | Stan |
| --- | --- | --- |
| 1 | Prototypy P01–P04 | Narzędzia gotowe, część prób wykonana; walidacja sprzętu/VPN/scrolla nadal częściowa. |
| 2 | Szkielet F1-01 | Gotowy. |
| 3 | Usługi pomiarów F1-02 | Zaimplementowane i sprawdzone lokalnie; szersza macierz sprzętowa nadal do wykonania. |
| 4 | Wykresy i historia F1-03 | Zaimplementowane; retencja i przerwy sprawdzane deterministycznie, wykresy w testach GUI. Fizyczny sleep/wake pozostaje w macierzy odbioru. |
| 5 | Sieć F1-04 | Zaimplementowana i sprawdzona lokalnie; dodatkowe wyjścia VPN pozostają nieustalone. |
| 6 | Scroll F1-05 | Zaimplementowany z adaptacją mechanizmu Scroll Reversera; rzeczywiste próby gładzika, myszy i zmiany urządzenia rozpoznane poprawnie, bez list modeli. |
| 7 | Okno/menu/Dock/autostart F1-06 | Zaimplementowane. Pasek menu, Dock, `SMAppService.mainApp`, cykl życia procesu i start przy logowaniu bez okna mają testy automatyczne. Próba podpisanego wydania pozostaje w kroku 9. |
| 8 | Aktualizacje i prywatność F1-07/F1-08 | Gotowy. Harmonogram, kwalifikacja wydania, cache, ETag, UI PL/EN, diagnostyka i prywatność zostały odebrane; szczegóły w [raporcie](reports/etap-1-krok-8.md). |
| 9 | Testy końcowe i wydanie F1-09 | W toku. Punkty 1, 4 i 5 są wykonane, a w punkcie 2 potwierdzono metryki, historię, sieć, cykl życia okna oraz scroll myszy i gładzika; [raport](reports/etap-1-krok-9a.md). Pozostają offline, sleep/wake, punkt 3 i podpisane wydanie. |

## Co dalej

1. **Krok 9:** dokończenie punktu 2 przez próby offline i sleep/wake, następnie punkt 3 z autostartem aplikacji w `/Applications`, a później podpis Developer ID, Hardened Runtime, notarization i DMG.

Etap 2 (temperatury/RPM) i etap 3 (wyspa, schowek, muzyka) pozostają planowane. Nie są aktywne w obecnym buildzie.

## Dowody i granice

51 testów Core i 9 testów prototypów przechodzi. Czternaście scenariuszy XCTest UI obejmuje nawigację, język z restartem, rzeczywiste metryki z trwałym interwałem, wykresy, trzy przepływy scrolla, ustawienia paska menu, sterowanie Dockiem i oknem, autostart, kontrolę aktualizacji, diagnostykę oraz audyt dostępności pięciu sekcji. Debug i Release kompilują się dla arm64, a plik Release zawiera wyłącznie arm64. Pomiar Release przez 602 s przy zamkniętym oknie wykazał średnio 0,413% CPU, 96,81 MB RSS i brak wzrostu pamięci; szczegóły zawiera [raport kroku 9](reports/etap-1-krok-9a.md).

Raporty szczegółowe: [prototypy](reports/etap-1-krok-1.md), [szkielet](reports/etap-1-krok-2.md), [sieć](reports/etap-1-krok-5.md), [pomiary](reports/etap-1-krok-3.md), [historia i wykresy](reports/etap-1-krok-4.md), [scroll](reports/etap-1-krok-6.md), [model ustawień i cykl życia](reports/etap-1-krok-7a.md), [ikona i panel paska menu](reports/etap-1-krok-7b.md), [Dock i okno](reports/etap-1-krok-7c.md), [autostart i tryb uruchomienia](reports/etap-1-krok-7d.md), [osobne sekcje Docka i scrolla](reports/etap-1-krok-7e.md), [aktualizacje, prywatność i diagnostyka](reports/etap-1-krok-8.md), [testy automatyczne, dostępność i praca w tle](reports/etap-1-krok-9a.md). Projekt ikony i odtwarzanie zasobów: [Design/AppIcon](../Design/AppIcon/README.md).

To nie jest zamknięty odbiór etapu 1. Nie deklarujemy przetestowania wszystkich Maców Apple Silicon, każdej konfiguracji VPN ani kosztu całej aplikacji na podstawie czasu pojedynczego odczytu. Lokalne buildy są podpisane ad-hoc; nie są wydaniami notarized.
