# Prototypy etapu 1 - krok 1

Narzędzia do badań P01–P04: CPU/GPU/RAM, kandydat pomiaru mocy, IPv4/VPN i wejście myszy/gładzika. To pakiet CLI, nie szkielet aplikacji SwiftUI F1-01 i nie ukończone funkcje produktu.

Wymagania: Apple Silicon, macOS 26+, Xcode z kompilatorem Swift 6 i SDK macOS 26. Brak zewnętrznych zależności. Mała warstwa C izoluje ABI Mach/IOKit/SMC; logika, CLI, format JSON i testy są w Swift.

## Uruchomienie z katalogu głównego repozytorium

~~~sh
swift test --package-path Prototypes/Stage1
swift run --package-path Prototypes/Stage1 mac-manager-probe metrics --samples 5 --interval 1
swift run --package-path Prototypes/Stage1 mac-manager-probe network
swift run --package-path Prototypes/Stage1 mac-manager-probe network --public-ip
swift run --package-path Prototypes/Stage1 mac-manager-probe input
~~~

Wynik: JSON Lines na stdout, błędy składni CLI na stderr z kodem wyjścia 2. Niedostępność konkretnego odczytu jest wynikiem badania i ma własny status w JSON; nie kończy pozostałych pomiarów.

Pierwsza próbka CPU ma status baseline, bez wartości. Kolejne są znormalizowaną różnicą liczników zajętości do 0–100%. Cofnięcie/przepełnienie licznika lub odstęp ponad 30 s rozpoczyna nową bazę. Ten krótki prototyp nie implementuje jeszcze pełnego cyklu sleep/wake aplikacji.

RAM: wynik w bajtach, wzór (internal - purgeable + wired + compressor) × pageSize. Wyklucza file cache i używa fizycznych stron kompresora. Status candidate do zakończenia porównania definicji z Monitorem aktywności; nie należy utożsamiać go z „PhysMem used” polecenia top.

GPU: Device Utilization % z jednego AGXAccelerator. Brak zgodnego licznika, wielu niejednoznacznych kandydatów lub wartość poza 0–100 daje unavailable. Częstotliwość aktualizacji licznika jest kontrolowana przez sterownik.

## Moc: kandydat i pomiar produktu to różne pola

powerCandidate odczytuje wyłącznie PSTR przez AppleSMC, polecenia metadanych (9) i odczytu (5), selector 2. Odczytane flt/sp78 są dekodowane; inne typy pozostają nieobsługiwane. Nie ma polecenia zapisu, sterowania wentylatorami ani odczytu dowolnego klucza z argumentu użytkownika.

PSTR ma status unverified nawet wtedy, gdy odczyt się udał. wholeDevicePower pozostaje unavailable, ponieważ nie wykonano pełnej walidacji AC/bateria/ładowanie/ekran/akcesoria. Nie promujemy prawdopodobnej wartości do zweryfikowanego pomiaru całego Maca.

Referencja dla nieudokumentowanego ABI: [Stats SMC](https://github.com/exelban/stats/blob/master/SMC/smc.swift). Informacja licencyjna w [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md). ABI jest sprawdzane przez statyczne asercje rozmiaru i offsetu; to nie gwarantuje zgodności ze wszystkimi modelami.

## IPv4 i VPN

Domyślnie adresy w wyniku są maskowane. --show-addresses jawnie pokazuje je lokalnie; nie używać tej opcji do raportów przeznaczonych do commita lub udostępnienia.

Bez --public-ip nie ma żądań HTTP. Z tą opcją następuje jedno żądanie do api.ipify.org po normalnej trasie systemowej. Timeout 5 s, odpowiedź do 1024 bajtów, bez cookies/cache i bez podążania za przekierowaniami.

Prototyp pokazuje aktywne IPv4 i podstawowy interfejs według SystemConfiguration. Jeśli podstawowy jest tunelem albo wybór jest niejednoznaczny, nie wymyśla lokalnego LAN. Interfejsy utun są tylko kandydatami tuneli, a nie potwierdzoną listą VPN. Nie oznaczają tylu różnych publicznych adresów. Brak modyfikacji tras, wymuszania interfejsu fizycznego lub prób obejścia VPN. Dodatkowe wyjścia pozostają unresolved.

## Scroll: pasywna obserwacja

~~~sh
swift run --package-path Prototypes/Stage1 mac-manager-probe input --observe-seconds 15
~~~

Najpierw kompilacja, potem 15 sekund przewijania. W celu precyzyjnego rozpoczęcia można użyć zbudowanego pliku z Prototypes/Stage1/.build/debug/mac-manager-probe.

Odczyt zgód nie wyświetla promptów. Jeśli brak Input Monitoring, obserwacja zwraca permission_denied. Uprawnienia procesu CLI/terminala nie dowodzą, że przyszła aplikacja z własnym bundle ID otrzyma je automatycznie.

Od kroku 6 pasywny input obserwuje także gesty dotykowe i korzysta z tego samego automatycznego ScrollSourceClassifier co aplikacja. W JSON są dodatkowe liczniki mouseEvents, trackpadEvents, unknownEvents i multiTouchEvents, a także pomocnicze mouseGestureEvents/trackpadPlainEvents do porównania z charakterystyką konkretnej próby. Klasyfikacja łączy dotyk co najmniej dwóch palców z czasem, ciągłością i bezwładnością; nie potrzebuje list modeli. Nie zbieramy klawiszy, pozycji kursora/palców, tytułów okien, identyfikatorów procesów ani treści aplikacji.

Prototyp nigdy nie zmienia rzeczywistego scrolla. W celu weryfikacji wykonaj oddzielne próby po 25 s: wyłącznie gładzik (również bezwładność), wyłącznie kółko myszy, na koniec naprzemienne użycie obu. Porównaj mouseEvents/trackpadEvents z faktycznie używanym urządzeniem. Liczniki nie dowodzą samego odwrócenia; to sprawdza się w aplikacji po udzieleniu zgód i wyłączeniu odwracania w innym narzędziu.

Lista IOHID przedstawia kolekcje usage, nie unikalne fizyczne urządzenia, i nie steruje klasyfikatorem. Zależność od lokalnego MacManagerCore pozwala testować produkcyjny algorytm; kod aplikacji nie uruchamia prototypów.

## Ręczna macierz dalszych prób

| Obszar | Próba | Kryterium |
| --- | --- | --- |
| P01 CPU | Spoczynek i znane obciążenie; porównanie tych samych okien czasowych. | Prawidłowa reakcja licznika 0–100, bez skoków po nowej bazie. |
| P01 RAM | Porównanie wzoru i kategorii z Monitorem aktywności, także przy presji. | Jawna semantyka i różnice wobec cache; nie sama zgodność z top. |
| P01 GPU | Powtarzalne obciążenie GPU i powrót do spoczynku. | Odczyt reaguje; ustalone opóźnienie i cadence sterownika. |
| P02 | AC bez ładowania, AC z ładowaniem, bateria; różna jasność i obciążenie. | Ustalony zakres fizyczny PSTR, brak mylenia ładowarki/SoC z całym urządzeniem. |
| P03 | Osobne sesje: tylko gładzik, tylko mysz z kółkiem, mysz z płynnym scrollem, oba urządzenia. | Rzeczywisty dowód klasyfikacji lub jawny brak dowodu. |
| P04 | Bez VPN, zwykły VPN, split tunnel, kilka tuneli. | Publiczny adres opisany zakresem dowodu, bez ujawniania adresu poza VPN. |

Po próbach zapisać tylko zredagowane podsumowanie w docs/reports. Raport bieżącego uruchomienia: [etap 1, krok 1](../../docs/reports/etap-1-krok-1.md).

## Granica ukończenia

Gotowe są uruchamialne narzędzia i testy logiki. Nie oznacza to zamknięcia wszystkich bramek P01–P04. Ukończenie walidacji zależy od realnych urządzeń, scenariuszy zasilania i VPN. Nie uruchamiać tego pakietu jako stale działającego procesu produkcyjnego.
