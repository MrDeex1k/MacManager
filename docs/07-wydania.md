# Wydania i utrzymanie

## Model dystrybucji

Oficjalne wydania są zawsze bezpłatne. Publiczny kod na MIT. Podstawowym artefaktem jest podpisany i notaryzowany DMG udostępniony w GitHub Releases; architektura arm64, minimum macOS 26.

Opcjonalny Homebrew Cask może instalować ten sam DMG. Aplikacja nigdy nie uruchamia brew do kontroli lub instalowania aktualizacji. Ręczne polecenia Homebrew użytkownika pozostają poza kontrolą aplikacji.

Brak Sparkle, wbudowanego instalatora, pobierania kodu wykonywalnego w tle i automatycznego zastępowania plików aplikacji. Użytkownik sam otwiera stronę wydania, pobiera DMG i instaluje.

## Kontrola aktualizacji

Źródło: publiczny endpoint GitHub GET /repos/{owner}/{repo}/releases/latest. Repozytorium jest stałą konfiguracji builda, nie dowolnym URL z serwera. [GitHub Releases API](https://docs.github.com/en/rest/releases/releases#get-the-latest-release).

Sprawdzamy stabilne wydanie i porównujemy sparsowaną wersję, nie ciągi znaków leksykograficznie. Konwencja: tag vMAJOR.MINOR.PATCH, CFBundleShortVersionString zgodny z tagiem, CFBundleVersion rosnący. Prerelease, draft, błędna wersja lub brak zgodnego DMG nie są proponowaną aktualizacją.

Przy pierwszym uruchomieniu można wykonać jedną kontrolę. Kolejna automatyczna dopiero po 7 dniach od rzeczywistej próby HTTP; harmonogram zapisany lokalnie i odporny na restart. Aplikacja nie budzi Maca i nie uruchamia się tylko po to, żeby sprawdzić wydanie. Jeśli termin minął przy wyłączonej aplikacji, sprawdza po kolejnym uruchomieniu i dostępności sieci.

Brak połączenia wykryty przed wysłaniem żądania nie zużywa próby; po powrocie sieci można wykonać zaległą kontrolę. Nieudana próba HTTP, także 403/429, nie powoduje automatycznej pętli ponowień przed upływem 7 dni. Ręczna kontrola jest możliwa, z respektowaniem limitów GitHub i blokadą równoległych żądań. Udana kontrola ręczna odsuwa automatyczną o 7 dni.

Automatyczne kontrole można wyłączyć, ręczne pozostają dostępne. Rozróżniamy: „Aktualna wersja”, „Dostępna wersja”, „Nie udało się sprawdzić”, „Brak publicznego wydania”. Błąd API nigdy nie oznacza potwierdzenia aktualności.

Stosować HTTPS, ETag/304 i małe ograniczone odpowiedzi. Bez tokenu użytkownika, cookies i identyfikatora instalacji. Link musi prowadzić do oczekiwanego repozytorium na github.com. Otwieramy konkretną stronę release; nie wykonujemy komend z release notes.

## Publiczny DMG

1. Zbudować Release arm64 z ustalonym bundle ID i deployment target.
2. Uruchomić testy oraz sprawdzić podpisy i uprawnienia.
3. Podpisać aplikację Developer ID z Hardened Runtime.
4. Przygotować DMG z aplikacją i skrótem do Applications; dołączyć informacje o wersji i sumę SHA-256 do wydania.
5. Przeprowadzić notaryzację, dołączyć ticket i zweryfikować Gatekeeper na pobranym artefakcie.
6. Przetestować instalację na czystym profilu i zastąpienie poprzedniej wersji.
7. Opublikować release z listą zmian, znanymi ograniczeniami i przetestowanymi modelami.

Wymagania podpisywania i notaryzacji opisuje [Apple Developer ID](https://developer.apple.com/developer-id/). Nie sugerować użytkownikom wyłączania Gatekeeper. Lokalne buildy rozwojowe nie są tym samym co gotowy publiczny DMG.

Instalacja nowej wersji: zakończyć aplikację, zastąpić ją w Applications, uruchomić. Dane pozostają w Application Support i UserDefaults. Niezmienny bundle ID jest ważny dla uprawnień, Keychain, ustawień i autostartu. Migracje danych muszą być wersjonowane i sprawdzone; rollback kodu nie gwarantuje odczytu nowszego schematu.

## Warunki operacyjne przed pierwszym wydaniem

| Element | Status po opracowaniu dokumentacji |
| --- | --- |
| Nazwa produktu | Mac Manager. |
| Publiczne owner/repo | Do konfiguracji przed integracją aktualizacji; nie opublikowano w tym zadaniu. |
| Bundle ID | Do nadania przed pierwszym buildem wymagającym trwałych zgód i kluczy. |
| Apple Developer Team / Developer ID | Dostępność niezweryfikowana; wymagane przed publicznym DMG. |
| Sekrety notaryzacji i podpisu | Nie odczytywano ani nie tworzono; konfiguracja poza kodem. |
| GitHub Releases | Kanał zatwierdzony; brak wydania w tym zadaniu. |
| Homebrew | Opcjonalna przyszła instalacja; brak Caska w tym zadaniu. |

To dane wdrożeniowe, które nie blokują zatwierdzonego projektu. Nie wymyślać owner/repo, identyfikatora zespołu ani komendy instalacyjnej w README.

## Licencja i zależności

Kod projektu: [MIT](../LICENSE). Oficjalna bezpłatność jest zobowiązaniem projektu; MIT dopuszcza również komercyjne wykorzystanie przez innych i wymaga zachowania informacji licencyjnych. [Tekst MIT](https://opensource.org/license/mit).

Preferujemy frameworki systemowe. Każda przyszła zależność ma przypiętą wersję, cel i informację licencyjną. Nie kopiować kodu czujników, grafiki ani elementów cudzej aplikacji wyłącznie dlatego, że repozytorium jest publiczne. Zachować wymagane notices po dodaniu rzeczywistej zależności. Biblioteki referencyjne z analizy nie są automatycznie zależnościami projektu.

CI może budować i testować na macOS, a publikację wykonywać z zaufanego tagu. Sekrety podpisywania nie są dostępne dla niezaufanych pull requestów. Konkretnego workflow jeszcze nie utworzono.

