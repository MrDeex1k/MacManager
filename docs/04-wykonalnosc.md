# Wykonalność, źródła i ryzyka

Rozpoznanie dokumentacyjne wykonane 2026-09-07. Nie wykonano jeszcze prototypów ani walidacji czujników. Poniższe techniki są kandydatami do implementacji; biblioteki i aplikacje referencyjne nie gwarantują zgodności Mac Manager.

## Macierz

| Funkcja | Technika | Pewność / warunek |
| --- | --- | --- |
| CPU | Mach host_processor_info / liczniki czasu | Wysoka wykonalność; walidacja normalizacji, przepełnień i sleep/wake. |
| RAM | host_statistics64, rozmiar strony i pamięć fizyczna | Wysoka wykonalność; jawny algorytm „used” i porównanie kategorii. |
| GPU | Statystyki sterownika przez IOKit; IOReport jako kandydat | Zależne od modelu i OS; nie ma założenia uniwersalnego klucza. |
| W całego Maca | Zweryfikowany czujnik SMC całego systemu | Podwyższone ryzyko; źródło i semantyka muszą przejść P02. |
| Temperatura / RPM | Adapter SMC i katalog model → czujniki | Podwyższone ryzyko; odczyt, bez zapisu i admin helpera. |
| Lokalny IPv4 | getifaddrs + konfiguracja interfejsów | Wysoka wykonalność; LAN, Ethernet, Wi-Fi, link-local, brak sieci. |
| Publiczny IPv4 | Żądanie HTTPS do usługi echo IP | Wykonalne dla konkretnego połączenia. |
| Wiele wyjść VPN | Prototyp ścieżek związanych z tunelami | Best effort; pełna mapa per-app poza gwarancją. |
| Scroll | Modyfikujący CGEvent tap, klasyfikator źródła | Uprawnienie Dostępność i testy urządzeń. |
| Schowek | NSPasteboard, changeCount, kontrola dostępu | Wykonalne z ograniczeniami obserwacji i zgód. |
| Muzyka | Apple Events / ScriptingBridge, osobny adapter odtwarzacza | Zweryfikować słowniki i zgody w aktualnych wersjach aplikacji. |
| Wyspa | NSPanel + NSHostingView, geometria NSScreen | Prototyp hover, fokusu, Spaces i monitorów. |
| Liquid Glass | SwiftUI glassEffect / systemowe komponenty | Publiczne API; testy kontrastu i dostępności. |
| Autostart | SMAppService.mainApp | Publiczne API; system może wymagać zatwierdzenia lub blokować usługę. |
| Aktualizacje | GitHub Releases REST API | Proste sprawdzenie i otwarcie strony; bez instalatora w procesie. |

## Moc i czujniki

Publiczne [ProcessInfo.thermalState](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property) opisuje ogólny stan termiczny, nie temperaturę w stopniach. Nie jest zamiennikiem SEN-01.

W [kodzie odczytów Stats](https://github.com/exelban/stats/blob/master/Modules/Sensors/readers.swift) źródło PSTR jest warunkiem funkcji dotyczących całego systemu, natomiast odczyty CPU/GPU/ANE/RAM/PCI są rozdzielone. Wniosek projektowy: dostępność i znaczenie całego pomiaru trzeba sprawdzić per platforma. Nie kopiujemy list kluczy ani ich znaczenia bez walidacji na docelowym modelu.

Lokalna instrukcja systemowa powermetrics(1), sprawdzona poleceniem man powermetrics, opisuje estymaty mocy podsystemów SoC i ich ograniczoną dokładność. Narzędzie jest referencją diagnostyczną dla prototypu, nie planowanym procesem okresowo uruchamianym przez aplikację. Nie stosujemy sudo ani instalatora administratora jako ukrytego warunku działania.

P02 musi porównać zachowanie źródła na baterii, z zasilaczem, podczas ładowania, przy zmianach jasności i obciążenia. Pomiar zewnętrznym watomierzem, jeśli dostępny, pomaga zbadać granice źródła, ale jego odczyt obejmuje inne straty i nie musi być równy czujnikowi wewnętrznemu. Bez ustalenia semantyki MET-02 pozostaje unavailable.

## Scroll i uprawnienia

Apple rozróżnia nasłuchiwanie wejścia od jego modyfikowania: modyfikujący tap wymaga Dostępności. Źródło: [Advances in macOS Security](https://developer.apple.com/videos/play/wwdc2019/701/).

[scrollWheelEventIsContinuous](https://developer.apple.com/documentation/coregraphics/cgeventfield/scrollwheeleventiscontinuous) jest sygnałem o zdarzeniu, nie dowodem, że pochodzi z gładzika. Myszy z płynnym scrollem i sterowniki mogą zmieniać charakterystykę zdarzeń. Prosty UI nie oznacza, że implementacja może utożsamić wszystkie zdarzenia ciągłe z touchpadem.

P03 sprawdza mysz USB/Bluetooth, Magic Mouse, gładzik wbudowany i zewnętrzny oraz kombinację dwóch urządzeń. Niepewnej klasyfikacji nie wolno naprawiać przez odwracanie wszystkich zdarzeń. Przy nieobsługiwanym przypadku lepszy jest brak zmiany niż zmiana gestów gładzika; ograniczenie należy ujawnić.

## Publiczny IPv4 i VPN

Apple opisuje reguły tras, wyłączenia i połączenia przypisane do interfejsów w [Routing your VPN network traffic](https://developer.apple.com/documentation/networkextension/routing-your-vpn-network-traffic). Użycie per-app VPN lub proxy oznacza, że wynik własnego połączenia nie potwierdza adresów innych aplikacji.

Nie odczytujemy „publicznego IP” z prywatnego adresu tunelu. Nie wymuszamy wyjścia poza VPN, nie zmieniamy routingu i nie traktujemy kill switcha jako błędu do obejścia. W systemie z VPN bez internetowego wyjścia istnieje tunel, lecz nie musi istnieć osobny publiczny adres do pokazania.

## Schowek

[NSPasteboard.changeCount](https://developer.apple.com/documentation/appkit/nspasteboard/changecount) pozwala zauważyć zmianę schowka; nie stanowi kompletnego dziennika zdarzeń. Gdy kilka kopiowań nastąpi między odczytami, pośrednie treści mogą być utracone. Nie obiecujemy bezstratnego przechwycenia każdej operacji.

macOS posiada [NSPasteboard.AccessBehavior](https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.enum). P05 musi zweryfikować zachowanie na macOS 26 przy zezwoleniu, pytaniu i odmowie. Nie zakładamy, że historia działa zawsze bez dodatkowej decyzji systemowej.

Identyfikacja aplikacji źródłowej jest best effort: aktywna aplikacja może nie być właścicielem kopiowania. Wykluczenia i znaczniki poufności zmniejszają ryzyko, lecz nie rozpoznają każdego hasła. Reguły w [modelu danych](05-dane-i-prywatnosc.md).

## Muzyka i wyspa

[ScriptingBridge](https://developer.apple.com/documentation/scriptingbridge/sbapplication) umożliwia wymianę Apple Events ze skryptowalnymi aplikacjami. Przed implementacją odczytać słowniki aktualnie zainstalowanych Music i Spotify, zweryfikować nazwy komend, jednostki czasu, okładki i timeouty. W tym opracowaniu nie potwierdzono lokalnych słowników tych aplikacji.

Nie zakładamy, że MusicKit steruje odtwarzaniem innej aplikacji ani że MPNowPlayingInfoCenter odczyta globalny stan odtwarzaczy. Prywatne MediaRemote nie jest podstawą architektury. Bezpośrednia integracja Spotify Web API nie jest potrzebna do przyjętego zakresu.

Wyspa jest własnym oknem. [NSScreen.auxiliaryTopLeftArea](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea-uglc) pomaga uwzględnić obszar przy wycięciu. Samo API geometrii nie rozstrzyga hover, pełnego ekranu ani fokusu; sprawdza je P07.

[SwiftUI glassEffect](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)) jest podstawą materiału interfejsu. Nie budować własnego renderera Liquid Glass.

## Autostart i podpis

[SMAppService.register](https://developer.apple.com/documentation/servicemanagement/smappservice/register()) rejestruje usługę z uwzględnieniem decyzji użytkownika/systemu. Domyślne „włączone” oznacza próbę rejestracji przy pierwszej konfiguracji i pokazanie faktycznego statusu. Po wyłączeniu w Ustawieniach systemowych aplikacja nie włącza go ponownie przy każdym starcie.

Publiczna dystrybucja wymaga przygotowania Developer ID, Hardened Runtime i notaryzacji według [Apple](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). Dostęp do podpisywania jest warunkiem wydania, nie ukończenia tej dokumentacji.

## Wyniki badań do zachowania

Każdy prototyp P01–P07 z [planu](06-plan-i-testy.md) pozostawia krótki raport: model, wersja OS i odtwarzaczy/sterowników, użyte API, semantyka odczytu, wymagane zgody, zachowanie błędów, koszt działania i decyzja „wdrażamy / ograniczona obsługa / niedostępne”. Raporty nie zawierają danych schowka ani rzeczywistych IP.

