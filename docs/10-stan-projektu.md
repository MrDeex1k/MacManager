# Aktualny stan projektu i dalsza kolejność

Aktualizacja: 2026-09-08. Branch roboczy całego etapu: feat/stage-1. Projekt jest w trakcie etapu 1; nie ma jeszcze publicznego wydania DMG. Kroki 5 i 3 zrealizowano w tej kolejności na prośbę właściciela, następnie wdrożono kroki 4 i 6.

## Co działa

- Aplikacja Xcode/SwiftUI dla Apple Silicon i macOS 26+, ciemny interfejs z natywnym Liquid Glass, Przegląd/Sieć/Ustawienia i zmiana PL/EN bez restartu.
- Lokalny i publiczny IPv4, inwentarz interfejsów, kopiowanie adresów, odświeżanie, wyłączenie odczytu publicznego IP i jawne ograniczenia VPN. Zewnętrzny test ipify przeszedł po zgodzie właściciela.
- Bieżące CPU/GPU/RAM, jeden sampler, interwał 1/2/5 s, stany loading/unavailable/stale i unieważnianie próbek przy uśpieniu. Moc całego Maca pozostaje niedostępna, bez zastępowania jej sumą CPU/GPU.
- Historia ostatnich 300 s w RAM i wykresy Swift Charts CPU/GPU/RAM z przełącznikiem metryki, skalą czasu, minimum/maksimum i liczbą próbek. Luki po brakach odczytu, uśpieniu i zmianie interwału; brak fikcyjnego wykresu mocy.
- Odwracanie scrolla myszy w obu osiach, automatyczna klasyfikacja z gestów dotykowych bez list modeli, zachowanie gładzika i bezwładności, jawne stany Dostępności/Monitorowania wprowadzania, sleep/wake i wyłączenia tapu.
- Ikona aplikacji: miętowy szklany monitor ze wskaźnikami na grafitowym tle. AppIcon podłączony do obu konfiguracji Xcode; źródło i komplet rozmiarów są w repozytorium.
- Ikona w pasku menu otwierająca natywny panel Liquid Glass z metrykami, adresami IPv4, stanem scrolla oraz przejściem do okna i Ustawień. CPU, RAM i W można włączać niezależnie obok ikony; domyślnie widoczna jest sama ikona.
- Sterowanie ikoną Docka przez politykę aktywacji AppKit, z domyślnie widoczną ikoną i trwałym przełącznikiem. Zamknięcie głównego okna pozostawia proces aktywny, a aplikację można ponownie otworzyć z Docka, paska menu lub skrótu.
- Autostart przez `SMAppService.mainApp`, rzeczywisty status macOS, obsługa wymaganej zgody i jednorazowa próba domyślnej rejestracji. Start przy logowaniu pozostaje w tle bez głównego okna, a wszystkie usługi uruchamiają się na poziomie procesu.
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
| 8 | Aktualizacje i prywatność F1-07/F1-08 | Do implementacji i odbioru. |
| 9 | Testy końcowe i wydanie F1-09 | Do wykonania po wcześniejszych krokach. |

## Co dalej

1. **Krok 8:** tygodniowe/ręczne sprawdzanie GitHub Releases, opcja wyłączenia, otwarcie wydania do ręcznej instalacji DMG; weryfikacja prywatności i diagnostyki.
2. **Krok 9:** ręczna macierz sprzętu/sieci/sleep/wake, dostępność i testy obciążenia, próba autostartu z aplikacji w `/Applications`, podpis Developer ID, Hardened Runtime, notarization i DMG.

Etap 2 (temperatury/RPM) i etap 3 (wyspa, schowek, muzyka) pozostają planowane. Nie są aktywne w obecnym buildzie.

## Dowody i granice

40 testów Core i 9 testów prototypów przechodzi. Dziesięć scenariuszy XCTest UI sprawdza nawigację, język z restartem, rzeczywiste metryki z trwałym interwałem, wykresy, trzy przepływy scrolla, ustawienia paska menu, sterowanie Dockiem i oknem, stan autostartu oraz start przy logowaniu bez okna. Debug i Release kompilują się dla arm64. Ikonę aplikacji sprawdzono w katalogu zasobów i gotowym pakiecie aplikacji.

Raporty szczegółowe: [prototypy](reports/etap-1-krok-1.md), [szkielet](reports/etap-1-krok-2.md), [sieć](reports/etap-1-krok-5.md), [pomiary](reports/etap-1-krok-3.md), [historia i wykresy](reports/etap-1-krok-4.md), [scroll](reports/etap-1-krok-6.md), [model ustawień i cykl życia](reports/etap-1-krok-7a.md), [ikona i panel paska menu](reports/etap-1-krok-7b.md), [Dock i okno](reports/etap-1-krok-7c.md), [autostart i tryb uruchomienia](reports/etap-1-krok-7d.md). Projekt ikony i odtwarzanie zasobów: [Design/AppIcon](../Design/AppIcon/README.md).

To nie jest zamknięty odbiór etapu 1. Nie deklarujemy przetestowania wszystkich Maców Apple Silicon, każdej konfiguracji VPN ani kosztu całej aplikacji na podstawie czasu pojedynczego odczytu. Lokalne buildy są podpisane ad-hoc; nie są wydaniami notarized.
