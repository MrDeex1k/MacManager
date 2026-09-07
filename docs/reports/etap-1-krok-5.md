# Etap 1 / krok 5 — sieć (F1-04)

Data: 2026-09-08. Zgodnie z dyspozycją właściciela krok 5 wykonano przed krokiem 3, na feat/stage-1.

## Implementacja

NetworkService w lokalnym Core publikuje stan LAN/publicznego IPv4, przechowując dane wyłącznie w RAM. getifaddrs daje inwentarz adresów; SystemConfiguration wybiera aktywne fizyczne usługi w systemowej kolejności. Fizyczny PrimaryInterface ma pierwszeństwo, a jeśli domyślne połączenie prowadzi przez tunel, wybór LAN korzysta z kolejności aktywnych usług fizycznych. Brak potwierdzonej usługi daje jawnie nieustalony podstawowy LAN. Lista interfejsów pozostaje dostępna niezależnie od internetu.

NWPathMonitor sygnalizuje zmiany ścieżki; dodatkowy lokalny odczyt co 5 s wykrywa zmiany adresów, które nie zmieniają NWPath. Odczyt odbywa się na osobnym actorze, bez blokowania UI. Zmiana ścieżki unieważnia publiczny wynik i trwające zapytanie; rewizja chroni również przed wynikiem lokalnego odczytu rozpoczętego przed zmianą sieci.

Publiczny adres: HTTPS api.ipify.org?format=json, sesja ephemeral, brak cookies/cache, bez przekierowań, timeout 5 s i limit strumienia 1024 bajty. Parser wymaga odpowiedzi 200 i poprawnego publicznego IPv4. Wynik opisuje wyjście tego procesu do ipify, nie połączenia innych aplikacji. Obecność utun/ppp/ipsec to kandydat tunelu, nie dowód VPN; dodatkowe wyjścia VPN pozostają jawnie nieustalone. Nie ma sondowania przez interfejsy ani prób omijania VPN.

Próba automatyczna przy starcie, po co najmniej 2 s stabilizacji zmiany i co 15 minut; co najmniej 30 s między automatycznymi próbami po zmianach. Ręczne odświeżenie omija harmonogram, ale nie uruchamia drugiego równoczesnego żądania. Offline i wyłączenie funkcji blokują HTTP. Sleep anuluje żądanie, wake wymaga nowego wyniku. Nieudany odczyt nie zachowuje starego adresu jako aktualnego.

GUI PL/EN: LAN/publiczny IPv4, czas obserwacji, interfejsy, ograniczenia VPN, kopiowanie konkretnego adresu do NSPasteboard, przycisk odświeżenia .glass i trwały przełącznik publicznego IP (domyślnie włączony). Brak historii schowka. Usługi startują raz na AppState i nie są mnożone przez nawigację.

## Weryfikacja

- Core: 9 testów przechodzi (4 wcześniejsze i 5 sieciowych). Walidacja IP/statusu/rozmiaru, harmonogram 900/30 s, offline, wyłączenie, sleep, nieudana odpowiedź, ochrona przed spóźnionym wynikiem i wybór LAN zamiast tunelu.
- Build Debug oraz oba dotychczasowe scenariusze XCTest UI przechodzą. Tryb UI testing nie uruchamia rzeczywistej sieci.
- Lokalny adapter na M4 Pro: podstawowy en0, jeden IPv4, pięć kandydatów tuneli. Raport nie zawiera adresów.
- Zewnętrzny test ipify: po jawnej zgodzie właściciela wykonano jedno zapytanie produkcyjnym klientem. Wynik: poprawny publiczny IPv4; adres zredagowany w logu, niezapisany w repozytorium.

Nie przełączano rzeczywistego Wi-Fi, VPN ani stanu uśpienia użytkownika. Macierz zwykłego VPN, split tunnel, wielu połączeń i zmian po wybudzeniu nadal wymaga ręcznego odbioru. Implementacja nie deklaruje wykrywania wszystkich publicznych adresów komputera. Pełny etap 1 pozostaje w realizacji.
