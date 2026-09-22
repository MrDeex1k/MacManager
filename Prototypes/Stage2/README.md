# Etap 2: inwentarz czujników AppleSMC

Narzędzie korzysta z produkcyjnego adaptera MMHardware. Otwiera jedno połączenie, odczytuje katalog kluczy i wypisuje klucze `T...`, liczbę wentylatorów `FNum` oraz bieżące RPM `F...Ac`. Nie zawiera poleceń zapisu, regulacji RPM ani helpera administratora.

Uruchom z katalogu głównego repozytorium:

```sh
clang -I Packages/MacManagerCore/Sources/MMHardware/include \
  Prototypes/Stage2/sensors.c \
  Packages/MacManagerCore/Sources/MMHardware/MMHardware.c \
  -framework IOKit -framework CoreFoundation -o /tmp/macmanager-sensors
/tmp/macmanager-sensors
```

Wynik jest surowym inwentarzem, nie gotowym katalogiem CPU/GPU. Sam prefiks T nie wystarcza do ustalenia znaczenia ani poprawności odczytu. Narzędzie zachowuje również zera i wartości ujemne na potrzeby diagnozy. Brak obsługi typu lub błąd odczytu jest wypisywany jako unavailable. Katalog ograniczono do 16384 kluczy, aby błędna odpowiedź nie powodowała nieograniczonej pracy.

## Próba 2026-09-22

Apple M4 Pro, Mac16,8: dostęp do AppleSMC bez administratora działa. `FNum` = 2, `F0Ac` i `F1Ac` = 0 RPM w chwili próby. To zatrzymane wentylatory, a nie chłodzenie pasywne. Przykładowe odczyty: `Te05` 54,61, `Tg05` 54,33, `Tp1o` 74,39. Nie są jeszcze zweryfikowanymi wartościami zbiorczymi temperatur CPU/GPU.

Występują też `Tp00` = -4, `Tp01` = 2,20 i klucze z zerem. Dowodzi to, że uniwersalna lista kluczy bez identyfikacji modelu może pokazywać błędne temperatury. Dostępne dane wymagają przypisania zakresu czujników oraz porównania z niezależnym narzędziem na tym samym urządzeniu.

## Implementacja początkowa

- Adapter dekoduje flt, sp78, fpe2, ui8, ui16 i ui32, kontrolując długość i skończoność wyniku.
- HardwareSensorSampler odczytuje jawnie wybrane klucze temperatur i fizyczne wentylatory w jednym połączeniu, poza MainActor. Nie ma własnego timera ani integracji z GUI.
- Temperatura jest przechowywana w stopniach Celsjusza. Walidacja docelowych czujników CPU/GPU odrzuca wartości <= 0 i > 150. Sama walidacja nie zastępuje katalogu modelu.
- Brak FNum to stan unavailable; FNum = 0 to passive; 0 RPM to dostępny pomiar zatrzymanego wentylatora.
- 56 testów Core przeszło, w tym dekodowanie, nieprawidłowe dane i rozróżnienie stanów wentylatorów.

Następnie: katalog CPU/GPU dla zidentyfikowanych rodzin chipów, niezależna walidacja pomiarów, integracja z istniejącym harmonogramem i sleep/wake, widok Czujniki, prezentacja °C/°F oraz ustawienia paska menu.


## Krok 2: integracja odczytów i widok Czujniki

Dodano jawny katalog dla `Apple M4 Pro`: CPU to `TCMb` (średnia temperatury die według [katalogu iSMC](https://github.com/dkorunic/iSMC/blob/master/smc/sensors.go)), GPU to średnia dostępnych odczytów ośmiu kluczy z przypiętego katalogu Stats (zachowano MIT w notices aplikacji). Nie używamy listy kluczy rdzeni M4 ze Stats: część z nich na urządzeniu referencyjnym zwracała wartości bliskie zera. Nie podstawiamy temperatury maksymalnej za średnią.

Pozostałe chipy otrzymują jawny brak mapowania temperatur. Odczyt fizycznych wentylatorów nadal działa niezależnie od katalogu temperatur. Wartości temperatur zweryfikowano pod względem dostępności i zakresu, ale nie zakończono porównania ich znaczenia i dokładności z niezależnym narzędziem. Mapowanie pozostaje w fazie walidacji.

HardwareMetricsSampler dołącza wynik czujników do MetricsSnapshot w istniejącym cyklu 1/2/5 s. Nie ma drugiego timera. Anulowanie generacji podczas sleep/wake i zmiany interwału obejmuje także czujniki, a wygaszenie usuwa wartości temperatur i RPM. W obecnym kroku nie zapisujemy historii temperatur ani RPM.

Nowa sekcja Czujniki zawiera CPU, GPU, osobne wentylatory i trwały wybór °C/°F; konwersja następuje tylko w prezentacji. Braki GPU nie są zerami i są oznaczone jako niepełny zestaw. UI jest dostępne w PL/EN. Dotychczasowa kropka w panelu nadal opisuje cztery metryki etapu 1.

Następne kroki: niezależne porównanie sprzętowe i rozszerzenie katalogów, historia czujników, opcje temperatur/RPM w pasku menu oraz pomiar kosztu w tle. Nie podmieniano aplikacji w `/Applications`.

Weryfikacja kroku 2: 59 testów Core przeszło, build Debug i celowany XCTest UI na M4 Pro przeszły. Test GUI odczytał temperatury CPU/GPU i RPM oraz potwierdził zmianę °C/°F i odtworzenie jednostki po restarcie aplikacji. Test sprzętowy jest pomijany na innych chipach.

## Próba wentylatorów pod obciążeniem 2026-09-22

Na prośbę właściciela uruchomiono 10 procesów obciążających CPU przez maksymalnie 90 s, z odczytem SMC co 5 s i przerwaniem po osiągnięciu 95°C średniej CPU. Początek: 58,50°C, oba wentylatory 0 RPM. Po 50 s: 94,36°C, 2017 i 1937 RPM. W zainstalowanej aplikacji `/Applications/MacManager.app` bezpośrednio potwierdzono następnie 2324 i 2503 RPM. Wcześniejsze zera oznaczały zatrzymane wentylatory, nie brak odczytu.

Test zakończył się automatycznie po około 75 s przy odczycie 95,43°C. Potwierdzono brak pozostałych procesów testowych; kolejny odczyt CPU wynosił 72,50°C. Nie sterowano wentylatorami ani nie zmieniano ustawień chłodzenia. Próba potwierdza reakcję odczytów RPM i ich prezentację w GUI; nie stanowi niezależnej kalibracji temperatur.
