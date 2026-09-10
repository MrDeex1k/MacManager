# Rejestr decyzji i drzewo projektu

Wszystkie decyzje produktowe poniżej zatwierdzone w wywiadzie i końcowym podsumowaniu. Rozwiązania implementacyjne zapisane w pozostałych dokumentach są decyzjami inżynierskimi; nie są przypisywane użytkownikowi jako dosłowne odpowiedzi.

## Drzewo decyzji

~~~mermaid
flowchart TD
    A["Mac Manager: publiczny i bezplatny"] --> B["Apple Silicon / macOS 26+"]
    A --> C["GitHub / DMG / MIT"]
    A --> D["Lokalne dane, bez kont i telemetrii"]
    B --> E["SwiftUI / ciemny Liquid Glass / PL i EN"]
    B --> F["Faza 1"]
    F --> G["CPU GPU RAM / W / 5 minut"]
    G --> H["Walidacja zrodel / brak odczytu zamiast zgadywania"]
    F --> I["IPv4 / potwierdzone wyjscia VPN"]
    F --> J["Prosty scroll mysz kontra gladzik"]
    F --> K["Okno / menu bar / Dock / autostart"]
    G --> L["Faza 2: temperatura i RPM"]
    K --> M["Faza 3: wyspa"]
    M --> N["Hover / pusta zwinieta / ekran MacBooka lub glowny"]
    M --> O["Schowek lokalny / limity / prywatnosc"]
    M --> P["Lokalne Music i Spotify"]
    C --> R["Kontrola GitHub raz na tydzien / instalacja reczna"]
~~~

## Ustalenia

| ID | Ustalenie końcowe | Źródło |
| --- | --- | --- |
| D01 | Najpierw testy właściciela, potem publiczny projekt i DMG; Homebrew opcjonalnie. | Q1–Q2 |
| D02 | Tylko Apple Silicon, minimum macOS 26. | Q3, Q8 |
| D03 | Faza 1: pozostałe funkcje podstawowe; faza 2: temperatura/RPM; faza 3: wyspa, cały schowek i muzyka. | Q4, Q6 |
| D04 | Taskbar oznacza górny pasek menu z otwarciem pełnego okna. | Q5 |
| D05 | Energia oznacza chwilową moc całego Maca w W; niedostępność jest dozwolona, jeśli brak wiarygodnego źródła. | Q7, Q11 |
| D06 | Metryki całego systemu, ostatnie 5 min w RAM, 2 s domyślnie, wybór 1/2/5 s, przerwy podczas snu. | Q9, Q14, podsumowanie |
| D07 | Dock i autostart domyślnie włączone, oba można wyłączyć; zamknięcie okna pozostawia tło. | Q10, podsumowanie |
| D08 | Proste rozróżnienie myszy i gładzika; bez panelu profili i osobnych opcji osi. | Q12 |
| D09 | Lokalny/publiczny IPv4; dodatkowe publiczne IP VPN tylko z potwierdzeniem, bez kompletnej mapy per aplikacja. | Q13, Q16 |
| D10 | W pasku domyślnie ikona; CPU, RAM, W, później temperatury i RPM wybierane osobno. | Q15 |
| D11 | Dopuszczone nieudokumentowane odczyty, początkowo bez admin helpera; bez sterowania wentylatorami. | Q17 |
| D12 | Trwały schowek tekstów/obrazów; 50 wpisów/7 dni/200 MB, pierwszy przekroczony limit; wyszukiwanie i ręczne przywrócenie. | Q18 |
| D13 | Pauza, wykluczenia aplikacji, pomijanie oznaczonej poufnej/tymczasowej treści; brak gwarancji rozpoznania wszystkich haseł. | Q19 |
| D14 | Lokalny podgląd i podstawowe sterowanie Music/Spotify; wybór źródła; bez biblioteki i innych urządzeń. | Q20 |
| D15 | Wyspa rozwija się po hover; opcjonalny skrót; zwinięta nie pokazuje nic. | Q21, Q26 |
| D16 | Aktywny ekran MacBooka ma wyłączność; bez niego ekran główny. | Q22 |
| D17 | Domyślnie ukryta nad pełnym ekranem, z możliwością zmiany. | Końcowe podsumowanie |
| D18 | Tylko ciemny Liquid Glass, aplikacja PL/EN, dokumentacja PL, README EN. | Q23 |
| D19 | Oficjalne wydania zawsze bezpłatne, open source na MIT. | Q24, podsumowanie |
| D20 | GitHub Releases, sprawdzanie co tydzień i ręcznie; link do strony DMG, instalacja ręczna; niezależnie od Homebrew. | Q25, Q27 |
| D21 | Brak kont, reklam, telemetrii, automatycznych raportów i synchronizacji; dane lokalne. | Q28 |
| D22 | Połączenia zewnętrzne potrzebne dla publicznego IP i GitHub są jawne; lokalność dotyczy danych aplikacji. | Końcowe podsumowanie |

## Decyzje inżynierskie

| ID | Decyzja | Dlaczego |
| --- | --- | --- |
| E01 | AppKit jako uzupełnienie SwiftUI; modularny Core. | Panel wyspy i cykl życia wymagają kontroli zachowania okien. |
| E02 | Bez App Sandbox, z Hardened Runtime. | Zakres integracji systemowych i dystrybucja poza App Store. |
| E03 | Adaptery źródeł i statusy jakości danych. | Zmiany układów/OS nie mogą wymuszać zgadywania wartości. |
| E04 | Wspólny harmonogram metryk i bufory 300 s. | Spójny UI i ograniczenie kosztu monitorowania. |
| E05 | ipify jako początkowy serwis IPv4, bez ukrytych fallbacków. | Prosty kontrakt i jawny odbiorca zapytań. |
| E06 | Zaszyfrowane payloady i miniatury schowka, lokalny klucz, wyszukiwanie w RAM. | Ograniczenie jawnej treści na dysku bez backendu. |
| E07 | Apple Events dla lokalnych odtwarzaczy. | Zakres sterowania lokalnego; brak potrzeby konta OAuth. |
| E08 | Placeholder zamiast sieciowego wyszukiwania okładki. | Zachowanie uzgodnionej lokalności danych muzycznych. |
| E09 | Brak automatycznej instalacji aktualizacji i Sparkle. | Uzgodniony przepływ GitHub → strona wydania → DMG. |

## Niewiadome techniczne, nie otwarte decyzje produktowe

Źródła GPU/W, kompletność czujników, rozpoznanie nietypowych myszy, potwierdzanie dodatkowego wyjścia VPN, zgody schowka i zachowanie odtwarzaczy wymagają P01–P07. Każde badanie ma kryterium w [planie](06-plan-i-testy.md).

Dane wdrożeniowe owner/repo, bundle ID i podpis są do konfiguracji przed odpowiednim etapem. Nie zastępują ich wymyślone wartości. Terminy można oszacować po wynikach prototypów.

## Odrzucone kierunki

Lista procesów, wielodniowe metryki, temperatura zastąpiona stanem thermalState, moc całego Maca zastąpiona sumą CPU/GPU, profile każdej myszy, IPv6 w interfejsie, przejmowanie ⌘C/automatyczne ⌘V, widoczna okładka w zwiniętej wyspie, wybór dowolnego ekranu, jasny motyw, Spotify Web API jako domyślna integracja, aktualizator Homebrew/Sparkle i chmurowa historia.

## Aktualizacja ustaleń

Zmianę produktową zapisać jako nową decyzję z przyczyną, wpływem na fazę i zgodą właściciela. Zmianę implementacyjną zapisać w E lub raporcie prototypu, aktualizując powiązane testy. Nie oznaczać niezweryfikowanej możliwości jako obsługiwanej na podstawie samej dokumentacji zewnętrznej.


## Doprecyzowania implementacyjne - 2026-09-08

- Cały etap rozwijamy na jednym branchu feat/stage-1; kolejne kroki rozdzielają commity, bez osobnych branchy kroków.
- macOS 26+ oznacza domyślne użycie natywnego Liquid Glass w nawigacji i akcjach. Nie dodajemy przełącznika ani fallbacku dla starszego macOS; respektujemy systemowe ustawienia dostępności. Szczegółowy dobór miejsc jest w dokumencie interfejsu.

Uzupełnienie implementacyjne kroku 6 (2026-09-08): na prośbę właściciela funkcja ma zastąpić automatyczne rozróżnianie Scroll Reversera bez wyboru modelu. Zaadaptowano jego klasyfikację dotyku i mostek zdarzeń z zachowaniem Apache-2.0/NOTICE; główny kod pozostaje MIT. Pasywna obserwacja gestów wymaga Monitorowania wprowadzania obok Dostępności. Szczegóły i wyniki: [raport kroku 6](reports/etap-1-krok-6.md).
