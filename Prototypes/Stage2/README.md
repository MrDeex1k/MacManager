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
