# Etap 1, krok 7d - autostart, tryb uruchomienia i testy

Data: 2026-09-08. Stan: zaimplementowany i sprawdzony lokalnie na branchu feat/stage-1. Jest to końcowa część F1-06, obejmująca punkty 5, 6 i 7 planu kroku 7.

## Autostart

- SystemLoginItemService korzysta z publicznego `SMAppService.mainApp`.
- LoginItemController rozdziela intencję zapisaną w preferencjach od rzeczywistego stanu macOS: disabled, enabled, requiresApproval, unavailable lub failed.
- Użytkownik może włączyć i wyłączyć autostart w Ustawieniach aplikacji. Stan systemowy jest pokazany osobno i odświeża się po powrocie z Ustawień systemowych.
- Stan requiresApproval udostępnia przycisk prowadzący do systemowego panelu Login Items.
- Domyślne włączenie jest podejmowane tylko raz. Trwały znacznik zapobiega ponawianiu rejestracji przy każdym starcie po późniejszej decyzji użytkownika w macOS.

## Tryb uruchomienia i cykl życia

- ApplicationLaunchContextDetector rozpoznaje `keyAELaunchedAsLogInItem` w zdarzeniu `kAEOpenApplication`.
- Zwykłe uruchomienie pokazuje główne okno.
- Uruchomienie przy logowaniu używa `defaultLaunchBehavior(.suppressed)`, więc startuje tylko proces, usługi tła i pozycja paska menu.
- AppState uruchamia ApplicationLifecycleCoordinator podczas tworzenia procesu. Start metryk, sieci, scrolla, Docka i autostartu nie zależy już od widoku ani od otwartego okna.
- Otwarcie z paska menu lub skrótem tworzy główne okno także po starcie w tle.

## Weryfikacja

- Test Core sprawdza trwałość znacznika pierwszej próby domyślnego autostartu.
- Test UI sprawdza domyślną rejestrację, prawdziwy stan adaptera testowego, wyłączenie, trwałość intencji po restarcie i requiresApproval.
- Test UI startu przy logowaniu sprawdza brak głównego okna, działanie procesu w tle, późniejsze otwarcie okna i gotową próbkę CPU zebraną przed otwarciem GUI.
- Atrapy UI nie rejestrują aplikacji testowej jako rzeczywistej pozycji logowania użytkownika.
- Pełny zestaw obejmuje 40 testów MacManagerCore i 10 scenariuszy XCTest UI.

## Granice

Rzeczywista rejestracja `SMAppService.mainApp` zależy od podpisu, położenia aplikacji i decyzji użytkownika w macOS. Próba z podpisanym pakietem umieszczonym w `/Applications`, ponowne logowanie i sprawdzenie panelu Login Items należą do macierzy odbioru kroku 9. Lokalne testy automatyczne celowo nie modyfikują autostartu na komputerze deweloperskim.

## Następny krok

Krok 8 - aktualizacje, prywatność i diagnostyka.
