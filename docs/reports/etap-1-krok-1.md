# Etap 1 / krok 1 — prototypy P01–P04

Data: 2026-09-08. Stan: narzędzia zaimplementowane, pierwsze odczyty wykonane, walidacja sprzętowa częściowa.

Branch etapu: feat/stage-1. Branch prac: feat/stage-1-step-1-prototypes, utworzony z brancha etapu. Zmiany nie są scalone do etapu ani main.

## Środowisko i metoda

MacBook Pro Mac16,8, Apple M4 Pro, 24 GiB RAM (25 769 803 776 bajtów), macOS 26.6.2. Swift 6.3.3, SDK macOS 26.5. Lokalne uruchomienie CLI poza ograniczeniami środowiska wykonawczego Codex, ale bez sudo, admin helpera lub zmiany systemowych uprawnień.

Polecenia: swift test, metrics --samples 5 --interval 1, network --public-ip oraz input --observe-seconds 2. Następnie wykonano z użytkownikiem dwie oddzielne próby input --observe-seconds 20 i powtórzoną próbę myszy przez 30 s. Dodatkowo odczyt porównawczy ioreg, top i vm_stat. Raport nie zawiera prawdziwych IP, numerów seryjnych ani treści użytkownika.

Koszt collectionMilliseconds mierzy wyłącznie synchroniczne zebranie próbki w procesie. Nie obejmuje startu procesu, kodowania JSON, renderowania przyszłego GUI ani pełnego narzutu energetycznego aplikacji.

## Wyniki

| Obszar | Zaobserwowane | Decyzja |
| --- | --- | --- |
| CPU | Pierwsza próbka baseline, następne około 24,6–32,5% w końcowej serii. | Mach nadaje się do dalszej implementacji; kontrolowane obciążenie i sleep/wake pozostają do testu. |
| GPU | AGXAccelerator udostępnia Device Utilization %, około 62–68%, odczyt zmieniał się. | Dostępność potwierdzona dla tego modelu; potrzebny test reakcji na kontrolowane obciążenie i cadence. |
| RAM | Fizyczna pamięć 24 GiB; kandydat użycia około 19,87–20,27 GB w końcowej serii. | Jednostka bajtów i odczyt działają; porównanie znaczenia kategorii nadal wymagane. |
| Moc | PSTR dostępny, typ flt, około 34,8–38,3 W przy AC Power w końcowej serii. | To kandydat. Brak dowodu, że obejmuje właściwy zakres całego Maca. |
| Koszt próbki | Około 0,93–1,04 ms w końcowej serii. | Wstępny koszt adapterów; nie jest pomiarem budżetu CPU/RAM/energii aplikacji. |
| Lokalny IPv4 | Podstawowy interfejs en0, odczyt IPv4 i dodatkowych interfejsów zadziałał. | Podstawowa ścieżka potwierdzona; wynik raportowany z maskowaniem. |
| Publiczny IPv4 | api.ipify.org zwróciło poprawny IPv4. | Potwierdzenie dotyczy procesu prototypu i tego endpointu. |
| Tunele | Występuje pięć interfejsów utun. | Nie dowodzi pięciu VPN ani adresów publicznych; dodatkowe wyjścia unresolved. |
| HID | Wpisy mouse_usage i touchpad_usage są widoczne. | Inwentarz kolekcji nie wiąże zdarzenia scrolla z fizycznym urządzeniem. |
| Zgody wejścia | Istniejące zgody pozwoliły otworzyć pasywny tap. | Nie proszono o nowe zgody i nie zmieniano ich. |
| Scroll — próba wstępna | W dwusekundowej próbie 0 zdarzeń; brak przerwań tapu. | Sprawdza uruchomienie, nie rozróżnienie. |
| Scroll — gładzik | Próba 20 s na gładziku: 2448 continuous, 0 discrete, 1531 phase, 917 momentum, 0 przerwań. | Zapis rzeczywistego gestu działa; znaczniki phase/momentum są dostępne. |
| Scroll — mysz, pierwsza próba | 20 s: 0 zdarzeń; użytkownik potwierdził, że nie zdążył rozpocząć przewijania. | Próba nieważna, nie jest błędem obsługi myszy. |
| Scroll — mysz, powtórzenie | 30 s: 1521 continuous, 0 discrete, 0 phase, 0 momentum, 0 przerwań. | Dla użytej myszy sam continuous daje taki sam wynik jak dla gładzika. Fazy są obiecującym dodatkowym sygnałem. |

Przy porównaniu pamięci top zgłaszał około 22G PhysMem used, w tym około 5824M wired i 6459M compressor. vm_stat pokazał strony 16 384 B i osobne kategorie anonymous, purgeable, wired, compressor oraz file-backed. top uwzględnia inną semantykę niż wybrany wzór bez file cache; różnicy nie ukrywamy skalowaniem. Próbki pochodziły z różnych chwil przy zmiennym obciążeniu, więc nie stanowią porównania dokładności.

## Testy automatyczne

Swift Testing: 9 funkcji testowych, w tym parametryzowana walidacja 13 adresów IPv4; testy normalizacji CPU, spoczynku, pełnego obciążenia, zerowej różnicy i regresji liczników; wzoru RAM, błędnych danych i przepełnień; bezpiecznej polityki scrolla; walidacji odpowiedzi IP i maskowania. Wszystkie przeszły. Testy nie wymagają dostępu do sieci ani zgód wejścia.

Dodatkowo automatycznie sprawdzono realne JSON-y: zakres CPU, baseline bez fikcyjnego zera, RAM w bajtach w granicach fizycznej pamięci, brak niezweryfikowanej wartości wholeDevicePower, maskowanie IP i brak HTTP w domyślnym poleceniu network. Błędne argumenty (NaN, liczba próbek, zbyt długi nasłuch i opcja innego polecenia) dały kod 2 bez wyniku JSON. W czasie prototypowania wykryto i poprawiono niejednoznaczny wybór Double.init dla UInt64; wynik RAM jest jawnie konwertowany liczbowo, nie interpretowany jako bity zmiennoprzecinkowe.

## Braki dowodów i następne działania

1. P01: kontrolowane porównanie CPU/GPU, definicja RAM względem Monitora aktywności, dłuższy pomiar kosztu.
2. P02: bateria, ładowanie, jasność ekranu, akcesoria i ewentualna referencja zewnętrzna. Do tego czasu wholeDevicePower = unavailable.
3. P03: wykonano sesje rzeczywistego gładzika i jednej myszy. Potwierdzono nieprzydatność samego continuous do rozróżnienia tej pary. Trzeba zbadać klasyfikację z phase/momentum, oba urządzenia naprzemiennie i inne myszy/sterowniki. Model myszy i jej sterownik nie zostały potwierdzone. Classifier pozostaje unknown, a transformacja jest testowana tylko na jawnie potwierdzonym źródle, bez modyfikowania systemowych zdarzeń.
4. P04: różne konfiguracje VPN i walidacja przypisania wyjścia do tunelu. Nie testowano omijania ani zmiany tras.
5. Przed deklaracją szerszej obsługi powtórzyć próby na innych modelach Apple Silicon.

Instrukcje wykonania są w [README prototypów](../../Prototypes/Stage1/README.md). Ten raport nie zamyka bramek P01–P04 i nie oznacza ukończenia F1-01 (szkieletu GUI).
