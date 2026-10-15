# Etap 3D - krok 4: Apple Music

Data: 2026-10-13. Zakres zatwierdzony przez właściciela: Apple Music; Spotify odłożone do czasu jego instalacji.

## Implementacja

Wyspa ma dwie sekcje: Schowek i Muzyka. Odtwarzacz pokazuje tytuł, wykonawcę, album, lokalną okładkę (lub placeholder), postęp, czas oraz poprzedni/odtwórz-pauza/następny. Enter i Spacja w sekcji Muzyka przełączają odtwarzanie. Długie teksty mają ograniczenie linii; brak okładki lub czasu nie blokuje przycisków.

`MusicService` w Core ma jeden widocznościowy cykl odczytu, bramkowanie poleceń i tokeny generacji. `AppleMusicAdapter` używa publicznych Apple Events na osobnym actorze, kierowanych do już uruchomionego Music. Nie używa MusicKit, MediaRemote, osascript, kont OAuth ani sieciowego pobierania okładek. Otwarcie Music i zgoda Automatyzacji są jawnymi akcjami użytkownika.

Sprawdzono słownik `/System/Applications/Music.app/Contents/Resources/com.apple.Music.sdef` z Music 1.7 (1.7.0): `hook/PlPs`, `hook/Prev`, `hook/Next`; właściwości stanu, bieżącego utworu, identyfikatora, metadanych, czasu i surowej okładki. Czas jest w sekundach. Pojedyncze zdarzenie ma timeout 2 s, a błędy zgody, procesu i timeoutu są mapowane na stany UI. Po odczycie identyfikator jest ponownie sprawdzany, aby zmiana utworu nie połączyła starych metadanych z nowym postępem.

Okładka jest cache’owana dla jednego utworu w RAM; wejście ograniczono do 8 MB, miniaturę do 256 px i wynik PNG do 1 MB. Brak okładki ponawia próbę co najwyżej co 15 s aktywnej pracy. Ukrycie sekcji usuwa metadane i okładkę z prezentacji oraz zleca zwolnienie cache. Anuluje też cykl i akcje; już rozpoczęte synchroniczne Apple Event może kończyć się do timeoutu. Spóźniona odpowiedź nie trafia do UI. Powiadomienia Music/NSWorkspace odświeżają tylko widoczną sekcję.

## Weryfikacja

- 128 testów Core przeszło, w tym widoczność, zatrzymanie odczytów, zwolnienie okładki, odrzucanie późnej odpowiedzi, zgody, bramkowanie poleceń i sanitizacja czasu.
- Testy GUI z kontrolowaną atrapą sprawdziły odtwórz/pauzę, poprzedni/następny, odmowę i akcję naprawczą, wspólny schowek oraz stan bez aktywnej pracy po zmianie sekcji i zamknięciu.
- Regresja GUI wielokrotnego ukrywania i hover przeszła. Buildy Debug i Release przeszły.
- Rzeczywista podpisana instalacja poprawnie rozpoznała nieuruchomione Music; jawny przycisk otworzył aplikację. Po zgodzie Automatyzacji odczytała stan gotowy bez bieżącego utworu, z aktywnym Odtwórz i wyłączonymi poprzedni/następny.
- Po uruchomieniu utworu przez właściciela potwierdzono rzeczywisty odczyt tytułu, wykonawcy, albumu, okładki i czasu trwania. Postęp wzrósł z 0:13 do 0:18; przycisk poprawnie wskazywał Pauzę. Wygląd okładki i układu sprawdzono na ekranie.
- Na prośbę właściciela wykonano dodatkowy test przycisków wyspy na prawdziwym Apple Music: Pauza zatrzymała odtwarzanie przy 2:32 (potwierdzone również w natywnym miniodtwarzaczu `isPlaying=false`); Odtwórz wznowił utwór i przywrócił etykietę Pauza. Następny zmienił utwór, metadane, długość, postęp i okładkę. Poprzedni po kilkunastu sekundach wrócił najpierw na początek bieżącego utworu; dwa szybkie kliknięcia cofnęły do poprzedniego i przywróciły jego okładkę. Test zakończono z odtwarzaniem utworu, na którym sprawdzano pauzę, od początku; nie edytowano playlisty ani kolejki.
- Przy szybkim przełączaniu widoczny był krótki stan Odczyt Apple Music przed publikacją spójnego zestawu metadanych; następny odczyt pokazał właściwy utwór. Radio i pełna macierz błędów natywnych pozostają do potwierdzenia.

## Instalacja i dalszy odbiór

Nowa wersja w `/Applications/MacManager.app` ma ten sam Developer ID, bundle ID i designated requirement. Dodano entitlement Apple Events oraz opis zgody PL/EN. Installer weryfikuje tożsamość przed zamknięciem poprzedniej aplikacji, zachowuje poprzedni pakiet w Koszu i nie resetuje TCC, UserDefaults, Keychain ani Application Support.

Spotify, dwa równoczesne źródła i wybór odtwarzacza pozostają odłożone. Profil Instruments, pełny odbiór dostępności oraz ekranów/sesji nadal należą do otwartej macierzy 3C/3D. Publiczna notaryzacja/DMG pozostaje osobnym zadaniem.
