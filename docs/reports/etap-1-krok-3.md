# Etap 1 / krok 3 — usługi pomiarowe (F1-02)

Data: 2026-09-08. Zaimplementowano po kroku 5, zgodnie z dyspozycją właściciela. Branch: feat/stage-1.

## Zakres

Jedna usługa MetricsService i jeden HardwareMetricsSampler współdzielone przez aplikację. Actor sprzętowy serializuje odczyty C/Mach/IOKit poza MainActor. Kontroler uruchamia próbkowanie domyślnie co 2 s; ustawienia oferują 1/2/5 s i zachowują wybór po restarcie. Nie ma nadrabiania zaległych próbek ani równoczesnych odczytów. Obsługa sleep unieważnia trwający wynik; po wake resetowana jest baza CPU. Zamknięcie okna nie kończy procesu; menu bar i autostart nadal należą do kroku 7.

| Metryka | Źródło i definicja | Dostępność |
| --- | --- | --- |
| CPU | HOST_CPU_LOAD_INFO, przyrost (user + system + nice) / przyrost wszystkich ticków. Skala całej maszyny 0–100%. | Pierwszy odczyt, regresja licznika i przerwa >30 s wymagają nowej bazy. |
| GPU | AGXAccelerator / PerformanceStatistics / Device Utilization %. | Tylko jeden poprawny wynik 0–100%; brak lub niejednoznaczność daje unavailable. To nieudokumentowana statystyka sterownika. |
| RAM | (internal − purgeable + wired + physical compressor) × pageSize. | Cache plików i logiczna wielkość danych skompresowanych nie są doliczane; overflow, ujemna kategoria i wynik >RAM dają unavailable. |
| Moc | Brak zweryfikowanego źródła całego urządzenia. | Unavailable, bez fikcyjnego 0 W. Produkcyjny target nie odczytuje SMC/PSTR. |

Każdy odczyt ma źródło, status i opcjonalną wartość, a rodzaj metryki określa jednostkę. Snapshot ma czas kalendarzowy i monotoniczny. Poprawne zero jest dostępne; NaN, infinity i błędny zakres nie są zerem. Po trzech interwałach wynik staje się stale i nie pokazuje liczby jako aktualnej. Przegląd wyświetla wartości i stany w PL/EN oraz wyjaśnia zakres RAM i brak mocy. Historia 300 s i wykresy pozostają w kroku 4.

## Testy i pomiary

- Buildy Debug i Release dla arm64/macOS 26: sukces.
- Core: 15 testów przechodzi. Sześć nowych obejmuje normalizację i regresję CPU, poprawne zero, zakresy, pamięć/overflow, stale przy różnych interwałach, brak nakładania prób i odrzucenie wyniku sprzed sleep, reset po wznowieniu oraz trwałość interwału i przełącznika publicznego IP.
- XCTest: wcześniejsze scenariusze nawigacji i PL/EN przechodzą. Nowy scenariusz rzeczywistych metryk i interwału przechodzi po poprawieniu asercji na AXValue (macOS publikuje tam tekst statyczny). Sprawdza bieżący CPU, brak wartości W oraz zachowanie wyboru 5 s po restarcie.
- Debug --ui-testing --live-metrics uruchamia prawdziwy sampler przy zatrzymanej sieci; testy nie wysyłają IP ani nie zmieniają ustawień normalnego profilu.
- Pięć próbek produkcyjnego samplera co 1 s na M4 Pro/macOS 26.6.2: CPU najpierw loading, potem 39,5 / 28,0 / 18,7 / 16,9%; GPU 56–66%; RAM 19,84–20,42 GiB; moc unavailable. Koszt zebrania próbki 0,12–0,36 ms. Jawny reset samplera ponownie daje CPU loading.
- Kontrola kategorii RAM: odczyt C podał 328471 stron anonymous, 17992 purgeable, 393078 wired, 601110 fizycznego compressor, strona 16384 B. Następujący bezpośrednio vm_stat podał odpowiednio 328563 / 17994 / 393074 / 601084. Niewielkie różnice wynikają z niesynchronicznych próbek na działającym systemie.

Kategorie i pominięcie cache odpowiadają rozróżnieniu użytej pamięci oraz cache opisanemu przez [Apple](https://support.apple.com/guide/activity-monitor/view-memory-usage-actmntr1004/mac). Wzór jest jawną definicją implementacyjną z liczników Mach, nie obietnicą identyczności z zaokrągleniami Monitora aktywności. Ogólne PhysMem w top obejmuje inny zakres, więc nie jest bezpośrednią referencją tego pola.

## Pozostała walidacja

Nie wykonano kontrolowanego obciążenia GPU, fizycznego sleep/wake, długiego pomiaru narzutu w tle, testu macOS 26.0 ani innych modeli Apple Silicon. Koszt samplera nie jest kosztem całej aplikacji. Do tych prób wracamy przy odbiorze etapu; P01 i P02 nie są w całości zamknięte. Moc pozostaje zatwierdzonym fallbackiem unavailable. Nie dodano jeszcze historii, wykresów, scrolla, menu bar, autostartu ani aktualizacji.
