# Wydania i utrzymanie

## Model dystrybucji

Oficjalne wydania są zawsze bezpłatne. Główny kod jest objęty GNU AGPL v3.0 only; adaptowane fragmenty scrolla zachowują Apache-2.0. Podstawowym artefaktem jest podpisany i notaryzowany DMG udostępniony w GitHub Releases; architektura arm64, minimum macOS 26.

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
4. Przygotować DMG z aplikacją, skrótem do Applications i tekstem GNU AGPL v3.0; dołączyć informacje o wersji i sumę SHA-256 do wydania.
5. Przeprowadzić notaryzację, dołączyć ticket i zweryfikować Gatekeeper na pobranym artefakcie.
6. Przetestować instalację na czystym profilu i zastąpienie poprzedniej wersji.
7. Opublikować release z listą zmian, znanymi ograniczeniami i przetestowanymi modelami.

Wymagania podpisywania i notaryzacji opisuje [Apple Developer ID](https://developer.apple.com/developer-id/). Nie sugerować użytkownikom wyłączania Gatekeeper. Lokalne buildy rozwojowe nie są tym samym co gotowy publiczny DMG.

Instalacja nowej wersji: zakończyć aplikację, zastąpić ją w Applications, uruchomić. Dane pozostają w Application Support i UserDefaults. Niezmienny bundle ID jest ważny dla uprawnień, Keychain, ustawień i autostartu. Migracje danych muszą być wersjonowane i sprawdzone; rollback kodu nie gwarantuje odczytu nowszego schematu.

## Warunki operacyjne przed pierwszym wydaniem

| Element | Status po opracowaniu dokumentacji |
| --- | --- |
| Nazwa produktu | Mac Manager. |
| Publiczne owner/repo | `MrDeex1k/MacManager`, skonfigurowane w kliencie aktualizacji. |
| Bundle ID | `dev.macmanager.MacManager`; zmiana przed wydaniem wymaga ponownej walidacji zgód i autostartu. |
| Apple Developer Team / Developer ID | Dostępność niezweryfikowana; wymagane przed publicznym DMG. |
| Sekrety notaryzacji i podpisu | Nie odczytywano ani nie tworzono; konfiguracja poza kodem. |
| GitHub Releases | Kanał i ścisły format artefaktu są skonfigurowane; brak opublikowanego wydania. |
| Homebrew | Opcjonalna przyszła instalacja; brak Caska w tym zadaniu. |

Lokalny skrypt `scripts/build-release-dmg.sh` archiwizuje aplikację arm64, sprawdza Developer ID i Hardened Runtime, umieszcza tekst licencji w obrazie, buduje DMG, wysyła go do notaryzacji, dołącza ticket oraz generuje SHA-256. Nie publikuje wydania i wymaga jawnie przekazanej tożsamości podpisu, Team ID oraz profilu `notarytool` z pęku kluczy.

## Licencja i zależności

Kod projektu: [GNU AGPL v3.0 only](../LICENSE), z [adaptacjami Apache-2.0](../THIRD_PARTY_NOTICES.md). Pełne informacje licencyjne `ThirdPartyNotices.txt` muszą pozostać w pakiecie aplikacji i DMG. Dystrybucja zmodyfikowanej wersji wymaga udostępnienia odpowiadającego jej kodu na warunkach AGPL. Jeżeli zmodyfikowana wersja umożliwia zdalną interakcję przez sieć, jej użytkownicy muszą otrzymać możliwość pobrania odpowiadającego kodu źródłowego zgodnie z sekcją 13. [Tekst GNU AGPL v3](https://www.gnu.org/licenses/agpl-3.0.html).

Preferujemy frameworki systemowe. Każda przyszła zależność ma przypiętą wersję, cel i informację licencyjną. Nie kopiować kodu czujników, grafiki ani elementów cudzej aplikacji wyłącznie dlatego, że repozytorium jest publiczne. Zachować wymagane notices po dodaniu rzeczywistej zależności. Biblioteki referencyjne z analizy nie są automatycznie zależnościami projektu.

CI może budować i testować na macOS, a publikację wykonywać z zaufanego tagu. Sekrety podpisywania nie są dostępne dla niezaufanych pull requestów. Automatyczny workflow publikacji nie został jeszcze utworzony; obecny proces korzysta z lokalnego skryptu wydaniowego.
