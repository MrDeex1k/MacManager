# Etap 1 / krok 2 - szkielet aplikacji (F1-01)

Data: 2026-09-08. Stan: zaimplementowany i sprawdzony lokalnie. Branch: feat/stage-1, wspólny dla całego etapu. Krok 2 nie oznacza ukończenia usług pomiarowych F1-02 - te są krokiem 3.

## Zakres

Projekt MacManager.xcodeproj ma aplikację SwiftUI, target testów UI i współdzielony scheme MacManager. Lokalny pakiet Packages/MacManagerCore zawiera typowany wybór języka i obserwowalny magazyn ustawień. Bez zależności zewnętrznych, generatora projektu i GitHub Actions.

Okno udostępnia Przegląd, Sieć i Ustawienia. Nawigacja działa z panelu bocznego, przycisku szczegółów sieci, paska narzędzi oraz skrótów ⌘1, ⌘2 i ⌘,. PL/EN przełącza się od razu; wybór zachowuje się po restarcie. Domyślnie wybierany jest pierwszy wspierany język z preferencji systemu, z angielskim jako fallbackiem. String Catalog ma 32 klucze z kompletnymi tłumaczeniami. Systemowe menu i okna macOS zachowują własną lokalizację.

Interfejs jest wyłącznie ciemny. Liquid Glass jest domyślny: systemowe NavigationSplitView i toolbar oraz natywny styl przycisku .glass. Brak gałęzi zgodności ze starszym macOS i przełącznika wyłączającego materiał. Ustawienia dostępności systemu nadal mają pierwszeństwo. Zgodnie z kierunkiem opisanym w dokumencie interfejsu treść jest podzielona odstępami i separatorami, bez dekoracyjnych kart i szkła pod każdą wartością.

Przegląd podaje rzeczywistą pojemność fizycznego RAM i główną wersję macOS z ProcessInfo. Pola CPU/GPU/RAM/W oraz adresów mają jawny stan braku danych. Widoki nie uruchamiają prototypów ani zapytań sieciowych; nie wyświetlają wymyślonych pomiarów. Nie ma kontrolek czujników, wyspy, schowka ani muzyki.

## Walidacja

Środowisko: Apple M4 Pro, macOS 26.6.2, Xcode 26.6, Swift 6.3.3, SDK macOS 26.5.

| Sprawdzenie | Wynik |
| --- | --- |
| xcodebuild, Debug, macOS arm64 | Sukces. |
| xcodebuild, Release, macOS arm64 | Sukces; plik wykonywalny Mach-O arm64, LSMinimumSystemVersion 26.0. |
| swift test, MacManagerCore | 4 testy przechodzą: regiony i fallback, jawny język, trwałość ustawień, nieznana wartość bez kasowania innych danych. |
| XCTest UI: nawigacja i brak danych | Przechodzi: otwarcie/aktywacja okna, Przegląd → Sieć, brak danych i sekcji późniejszych faz, ustawienia z toolbaru, ⌘1 i przycisk .glass. |
| XCTest UI: język | Przechodzi: ⌘, → wybór PL → natychmiastowy polski interfejs → Sieć → restart z zachowanym PL. |
| Zrzuty okna z XCTest | Obejrzano Przegląd EN i Ustawienia PL przy 1080 × 740; brak obciętych etykiet i nakładania treści. |
| Katalog tłumaczeń i projekt | Kompletne PL/EN dla 32 kluczy, wszystkie odwołania kodu istnieją; plutil akceptuje projekt. |

Testy UI aktywują aplikację po uruchomieniu i zapisują zrzuty samego okna do xcresult. W Debug korzystają z osobnej domeny preferencji, aby nie zmieniać ustawień użytkownika. Pierwsze próby ujawniły brak aktywacji okna w runnerze i nadpisywanie identyfikatorów dzieci przez kontenery SwiftUI; poprawiono obsługę testów i identyfikatory. Oba scenariusze przeszły razem; po rozszerzeniu scenariusza nawigacji o przyciski powtórzono go z wynikiem pozytywnym.

Sesja macOS w agent-device była zajęta przez inną pracę; nie przejmowano jej. Weryfikacja interfejsu wykorzystała XCTest i jego zrzuty. Nie jest to pełny audyt VoiceOver, kontrastu ani ręczny test wszystkich ustawień Reduce Motion/Transparency i konfiguracji ekranów.

## Uruchomienie

Otworzyć MacManager.xcodeproj, wybrać scheme MacManager i My Mac. Polecenia build/test są w głównym README. Produkty lokalnej walidacji: /tmp/macmanager-app-build/Build/Products/Debug/MacManager.app oraz /tmp/macmanager-release-build/Build/Products/Release/MacManager.app.

Identyfikator rozwojowy: dev.macmanager.MacManager. Buildy podpisane ad-hoc do uruchomienia lokalnego. Xcode wyłącza Hardened Runtime przy takim podpisie, mimo włączonego ustawienia projektu. Nie są to artefakty Developer ID, notarization ani gotowy DMG. Ostrzeżenie o pominięciu ekstrakcji metadanych App Intents wynika z braku tej integracji w szkielecie.

## Granica ukończenia

F1-01 jest gotowe. Usługi pomiarów, historia, odczyt adresów, scroll, pasek menu, ukrywanie Docka, autostart i sprawdzanie wydań pozostają w swoich kolejnych krokach. Nie zainstalowano autostartu ani nie dodano wymagania uprawnień sprzętowych. Bramki sprzętowe z raportu kroku 1 pozostają aktualne; szkielet ich nie zastępuje. Pełny etap 1 nie jest jeszcze ukończony.
