# Aktualny stan projektu i dalsza kolejność

Aktualizacja: 2026-09-08. Branch roboczy całego etapu: feat/stage-1. Projekt jest w trakcie etapu 1; nie ma jeszcze publicznego wydania DMG. Kroki 5 i 3 zrealizowano w tej kolejności na prośbę właściciela, następnie wdrożono krok 4.

## Co działa

- Aplikacja Xcode/SwiftUI dla Apple Silicon i macOS 26+, ciemny interfejs z natywnym Liquid Glass, Przegląd/Sieć/Ustawienia i zmiana PL/EN bez restartu.
- Lokalny i publiczny IPv4, inwentarz interfejsów, kopiowanie adresów, odświeżanie, wyłączenie odczytu publicznego IP i jawne ograniczenia VPN. Zewnętrzny test ipify przeszedł po zgodzie właściciela.
- Bieżące CPU/GPU/RAM, jeden sampler, interwał 1/2/5 s, stany loading/unavailable/stale i unieważnianie próbek przy uśpieniu. Moc całego Maca pozostaje niedostępna, bez zastępowania jej sumą CPU/GPU.
- Historia ostatnich 300 s w RAM i wykresy Swift Charts CPU/GPU/RAM z przełącznikiem metryki, skalą czasu, minimum/maksimum i liczbą próbek. Luki po brakach odczytu, uśpieniu i zmianie interwału; brak fikcyjnego wykresu mocy.
- Ikona aplikacji: miętowy szklany monitor ze wskaźnikami na grafitowym tle. AppIcon podłączony do obu konfiguracji Xcode; źródło i komplet rozmiarów są w repozytorium.
- Conventional Commits egzekwowane lokalnym hookiem. Wszystkie kroki etapu trafiają na jeden branch, bez automatycznego merge do main.

## Stan kroków etapu 1

| Krok | Zakres | Stan |
| --- | --- | --- |
| 1 | Prototypy P01–P04 | Narzędzia gotowe, część prób wykonana; walidacja sprzętu/VPN/scrolla nadal częściowa. |
| 2 | Szkielet F1-01 | Gotowy. |
| 3 | Usługi pomiarów F1-02 | Zaimplementowane i sprawdzone lokalnie; szersza macierz sprzętowa nadal do wykonania. |
| 4 | Wykresy i historia F1-03 | Zaimplementowane; retencja i przerwy sprawdzane deterministycznie, wykresy w testach GUI. Fizyczny sleep/wake pozostaje w macierzy odbioru. |
| 5 | Sieć F1-04 | Zaimplementowana i sprawdzona lokalnie; dodatkowe wyjścia VPN pozostają nieustalone. |
| 6 | Scroll F1-05 | Do implementacji; najpierw rozwiązać wiarygodną klasyfikację źródła zdarzeń. |
| 7 | Okno/menu/Dock/autostart F1-06 | Do implementacji. Okno i utrzymanie procesu już istnieją, pozostałe integracje nie. |
| 8 | Aktualizacje i prywatność F1-07/F1-08 | Do implementacji i odbioru. |
| 9 | Testy końcowe i wydanie F1-09 | Do wykonania po wcześniejszych krokach. |

## Co dalej

1. **Krok 6:** wrócić do wyników prototypu scrolla. Zarówno mysz, jak i gładzik właściciela zgłaszały continuous, więc samo to pole nie pozwala bezpiecznie odwracać myszy. Dopiero po potwierdzeniu klasyfikacji podłączyć przełącznik i obsługę Dostępności.
2. **Krok 7:** pasek menu i panel, niezależne CPU/RAM/W, pokazywanie/ukrywanie Docka, autostart przez SMAppService z rzeczywistym stanem systemu i pełny cykl życia usług.
3. **Krok 8:** tygodniowe/ręczne sprawdzanie GitHub Releases, opcja wyłączenia, otwarcie wydania do ręcznej instalacji DMG; weryfikacja prywatności i diagnostyki.
4. **Krok 9:** ręczna macierz sprzętu/sieci/sleep/wake, dostępność i testy obciążenia, podpis Developer ID, Hardened Runtime, notarization i DMG.

Etap 2 (temperatury/RPM) i etap 3 (wyspa, schowek, muzyka) pozostają planowane. Nie są aktywne w obecnym buildzie.

## Dowody i granice

22 testy Core przechodzą. Trzy scenariusze XCTest UI sprawdzono z wynikiem pozytywnym: nawigacja, język z restartem oraz rzeczywiste metryki z trwałym interwałem oraz przełączanie wykresów i pusty stan mocy. Debug i Release kompilują się dla arm64. Ikonę sprawdzono osobno w katalogu zasobów i gotowym pakiecie aplikacji.

Raporty szczegółowe: [prototypy](reports/etap-1-krok-1.md), [szkielet](reports/etap-1-krok-2.md), [sieć](reports/etap-1-krok-5.md), [pomiary](reports/etap-1-krok-3.md), [historia i wykresy](reports/etap-1-krok-4.md). Projekt ikony i odtwarzanie zasobów: [Design/AppIcon](../Design/AppIcon/README.md).

To nie jest zamknięty odbiór etapu 1. Nie deklarujemy przetestowania wszystkich Maców Apple Silicon, każdej konfiguracji VPN ani kosztu całej aplikacji na podstawie czasu pojedynczego odczytu. Lokalne buildy są podpisane ad-hoc; nie są wydaniami notarized.
