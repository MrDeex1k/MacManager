# Etap 3A: lokalna historia schowka

Data: 2026-09-23. Branch: `feat/stage-3a-clipboard`, baza `main` po scaleniu etapu 2. Implementacja gotowa do ręcznego odbioru. Nie jest to odbiór całego etapu 3 ani opublikowane wydanie.

## Zachowanie

- Osobna sekcja Schowek z listą tekstów i obrazów, wyszukiwaniem tekstu, podglądem, przywracaniem, usuwaniem pojedynczym i czyszczeniem z potwierdzeniem. Interfejs PL/EN, natywne kontrolki SwiftUI/Liquid Glass.
- Domyślnie wyłączona historia. Włączenie i systemowy dostęp są osobnymi stanami. Odczyt w tle wymaga `NSPasteboard.accessBehavior == .alwaysAllow`; przy odmowie nie powtarzamy systemowych próśb. Przycisk kontroli dostępu wykonuje jeden jawny odczyt tekstu i odrzuca wynik.
- Co 500 ms jeden procesowy poller sprawdza licznik zmian. Przy starcie, wznowieniu, odzyskaniu dostępu i odblokowaniu ustala nową bazę, bez importowania zastanego schowka. Po normalizacji odrzucone zostają wyniki unieważnione pauzą/blokadą/wyłączeniem.
- Obsługiwany jest jeden element schowka: preferencja PNG/TIFF, następnie zwykły tekst UTF-8. Wiele reprezentacji jednego elementu nie tworzy duplikatów. Zestawy wielu elementów i file URL są pomijane; aplikacja nie odczytuje wskazanych plików. Szybkie wielokrotne kopiowanie pomiędzy odczytami może pominąć pośrednie kopie.
- Obraz jest normalizowany do PNG z uwzględnieniem orientacji i miniaturą do 320 px. Limity: tekst 1 MB UTF-8, wejściowy obraz 40 MB, 40 MP, PNG po normalizacji 20 MB. Przekroczenie daje komunikat, bez modyfikacji systemowego schowka.
- Poufne, tymczasowe i automatyczne kopie są filtrowane według znaczników NSPasteboard.org oraz kompatybilnych oznaczeń. Lista wykluczeń obejmuje bundle ID wskazanych aplikacji. Źródło deklarowane i aktualnie aktywna aplikacja to wskazówki, nie niezawodne poświadczenie pochodzenia. Brak znacznika poufności nie pozwala rozpoznać każdego hasła.
- Przywracanie zapisuje treść z `currentHostOnly` i znacznikiem własnego odtworzenia. Nie symuluje Cmd+V, nie otwiera URL i nie przechwytuje Cmd+C. Kolejna identyczna kopia nie odmładza istniejącego wpisu.

## Magazyn i cykl życia

`ClipboardController` jest uczestnikiem cyklu życia aplikacji. `ClipboardService` udostępnia jeden model dla obecnego okna i przyszłego launchera/wyspy. Zamknięcie okna nie zatrzymuje historii. Zdarzenia sleep/wake, zmiany sesji i blokady ekranu wstrzymują odczyt i usuwają podglądy z modelu RAM. Retencja jest niezależna od pauzy nagrywania.

Katalog: `Application Support/<bundle identifier>/Clipboard`. SQLite zawiera UUID, rodzaj, czas i liczbę bajtów. Treść, miniatura i bundle ID źródła pozostają w plikach AES-GCM. Powiązanie UUID, roli pliku i wersji przez authenticated data wykrywa podmianę szyfrogramów. Szyfrowanie poprzedza zapis na dysku. Pliki `.pending` są synchronizowane i przemianowywane; osierocone pliki usuwa kolejne otwarcie magazynu. Katalog ma uprawnienia 0700, pliki 0600 i wyłączenie z systemowych backupów.

Klucz AES-256 jest odtwarzany przez ECDH P-256 i HKDF-SHA256. Keychain zawiera niesynchronizowaną kopertę z chronioną sprzętowo reprezentacją klucza Secure Enclave i publicznym kluczem partnera; prywatny klucz partnera nie jest zapisywany. W ten sposób działamy także z domyślnym podpisem developerskim ad-hoc bez polegania na ignorowanych atrybutach dostępności plikowego Keychain. Secure Enclave wymaga odblokowanego urządzenia, bez promptów biometrycznych. Utrata/odmowa klucza nie uruchamia zapisu plaintext ani automatycznego resetu. Uszkodzony wpis nie blokuje zdrowych wpisów. Jawne czyszczenie usuwa magazyn historii, nie zawartość systemowego schowka ani klucz w Keychain.

Domyślne ograniczenia: 50 wpisów, 7 dni, 200 MB (dziesiętnych). Dostępne zakresy to 1-1000 wpisów, 1-365 dni i 1-2000 MB. Narzut SQLite jest podany osobno. Limity obejmują zaszyfrowane payloady i podglądy. Zmniejszenie limitów pokazuje liczbę pozycji do usunięcia. Kontrola następuje przed wyświetleniem historii, przy zapisie/przywracaniu/zmianie ustawień, po wznowieniu i co minutę. Brak sieci nie wpływa na schowek; moduł nie wykonuje żądań sieciowych ani nie loguje treści.

## Weryfikacja

- 74 testy Core: retencja wieku/liczby/bajtów, dokładne Unicode i nowe linie, restart repozytorium, brak tekstu i źródła w plikach, brak klucza, uszkodzony podgląd, podmiana szyfrogramów, osierocony zapis, poufne znaczniki i wykluczenia, tekst/PNG przez izolowany NSPasteboard, pauza/odmowa/blokada, własne odtworzenie i anulowanie pracy.
- Osobny test w tym zestawie tworzy tymczasowy klucz Secure Enclave/Keychain, odtwarza identyczny klucz i sprawdza, że Keychain nie zawiera jawnego klucza AES. Usuwa wyłącznie własny wpis o losowej nazwie.
- Dwa testy GUI: wyszukiwanie, przywracanie, zmniejszenie limitu z potwierdzeniem i czyszczenie; domyślnie wyłączona historia i przełączenie EN/PL. Testy korzystają z osobnych ustawień, katalogu tymczasowego i nazwanego schowka; nie czytają `NSPasteboard.general`.
- Zrzuty ekranu XCTest nie działały w bieżącej konfiguracji ekranów. Testy ukończono przez kontrolę interfejsu dostępności bez zrzutów. Pełny audyt wizualny i dostępności nowej sekcji pozostaje do odbioru.

### Ręczny odbiór P05

Na podpisanej kopii docelowej pozostaje sprawdzić:

1. Pierwsze włączenie i macOS: odmowa, jednorazowa zgoda, ustawienie stałej zgody i jej cofnięcie. Brak odczytów w tle do uzyskania stałej zgody.
2. Zwykłe kopiowanie tekstu/obrazu z dwóch aplikacji, przywrócenie i ręczne Cmd+V; wykluczenie jednej aplikacji i prywatny wpis menedżera haseł.
3. Blokada/odblokowanie oraz sleep/wake: ukrycie podglądów, brak importu treści skopiowanej podczas przerwy, odtworzenie wcześniejszej historii.
4. Restart i aktualizacja podpisanego buildu: dostęp do tego samego Keychain bez ponownego tworzenia historii. Sprawdzenie braku propagacji własnego odtworzenia przez Universal Clipboard wymaga drugiego urządzenia.
5. Koszt pollera/normalizacji przy dużych obrazach i pełnym limicie historii. Nie przenosimy pomiarów etapu 2 na nowy moduł.

Nie podmieniano instalacji w `/Applications`, nie zmieniano systemowych zgód i nie opublikowano zmian z tego brancha. Następny moduł to 3B: launcher lokalny; wyspa i muzyka następują później.

## Źródła API

- [NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard/) i [currentHostOnly](https://developer.apple.com/documentation/appkit/nspasteboard/contentsoptions/currenthostonly).
- [Konwencje znaczników schowka](https://nspasteboard.org/).
- [Secure Enclave](https://developer.apple.com/documentation/cryptokit/secureenclave), [AES.GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm).
- [Zakres działania kSecAttrAccessible na macOS](https://developer.apple.com/documentation/security/ksecattraccessible).
