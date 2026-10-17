# Płynność przełączania sekcji wyspy - 2026-10-15

Poprzedni mechanizm zmiany wysokości wykonywał aktualizację ramki, wymuszał synchroniczny layout NSHostingView, a następnie usypiał Task na około 8 ms. Czas pracy dodawał się do przerwy, więc nawet ekran 120 Hz nie oznaczał aktualizacji co 8,33 ms. Pętla nie była zsynchronizowana z ekranem. Przy zmianie sekcji przypisywano także nowy rootView hosta.

Zmianę wysokości prowadzi teraz CADisplayLink utworzony przez NSView.displayLink(target:selector:). Żądany zakres odświeżania ma maksimum i preferowaną częstotliwość równe maximumFramesPerSecond ekranu; macOS zachowuje kontrolę nad polityką odświeżania. Link działa na głównej pętli w common modes wyłącznie podczas skończonego przejścia. Postęp wynika z targetTimestamp i zegara Core Animation. Nie ma okresowego Task.sleep ani limitu 60 Hz dla tej geometrii.

Ramka panelu, ramka hosta i maska są aktualizowane w jednej transakcji bez animacji pośrednich. Powtórne identyczne ramki są pomijane. AppKit wykonuje layout w normalnym cyklu wyświetlania zamiast wymuszania dodatkowego layoutSubtreeIfNeeded w każdej klatce. Jedno drzewo SwiftUI i powierzchnia Glass pozostają zamontowane między sekcjami; zmienia się obserwowana zawartość.

Zachowano 280 ms, łagodną krzywą początku/końca, wyrównanie do fizycznego piksela i nieruchomą górną krawędź. Zamknięcie, zmiana kierunku, zmiana środowiska i Reduce Motion unieważniają aktywny link. Ukończenie przejścia także usuwa link i jego closures; słaby target nie utrzymuje hosta. Ukryte UI nie ma sterownika klatek.

W Debug testy zbierają liczbę callbacków, ich średnią częstotliwość, największy odstęp i p95 czasu aktualizacji geometrii. Dane nie zawierają treści schowka ani muzyki. To pomiar callbacków aplikacji, nie pełny pomiar klatek zaprezentowanych przez WindowServer/GPU; nie stanowi gwarancji stałych 120 FPS przy każdej polityce energetycznej i obciążeniu systemu.

Publiczne API: [NSView.displayLink](https://developer.apple.com/documentation/appkit/nsview/displaylink(target:selector:)), [CADisplayLink](https://developer.apple.com/documentation/quartzcore/cadisplaylink).

## Odbiór na Macu z ProMotion

Trzy cykle Schowek → Muzyka w teście Debug dały odpowiednio 116,4 / 116,9 / 116,9 callbacków/s. Największe odstępy wyniosły 16,64 / 14,95 / 14,95 ms, a p95 czasu samej aktualizacji geometrii 2,54 / 1,21 / 1,07 ms. Po każdym przejściu driver=0. Są to krótkie próbki z automatyzacją GUI, nie pomiar stałego FPS całego renderowania. Nie zebrano porównywalnego pomiaru poprzedniej wersji.

Trzy testy GUI przeszły: powtarzane przełączanie z pomiarem wysokości i zakotwiczenia górnej krawędzi, zamykanie z odłączeniem pracy i ponownym otwieraniem oraz Reduce Motion ze sterowaniem muzyką. Sprawdzono zrzut po trzecim przełączeniu - bez dodatkowego obramowania. Release przeszedł kompilację.

Wersję Release podmieniono i uruchomiono w /Applications/MacManager.app. Zachowano certyfikat Developer ID, bundle ID i designated requirement. Podpis po podmianie przeszedł weryfikację; działa jeden proces z docelowej instalacji. UserDefaults, Keychain, Application Support i TCC nie były modyfikowane przez instalator.
