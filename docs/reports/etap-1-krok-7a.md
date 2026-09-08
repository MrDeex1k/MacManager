# Etap 1, krok 7a - model ustawień i koordynator cyklu życia

Data: 2026-09-08. Stan: zaimplementowany i sprawdzony lokalnie na branchu feat/stage-1. Jest to pierwsza część F1-06, bez gotowego panelu paska menu, zmiany widoczności Docka i rejestracji `SMAppService`.

## Zakres

- `AppIntegrationPreferences` przechowuje widoczność ikony Docka, intencję autostartu oraz niezależną widoczność CPU, RAM i mocy w pasku menu.
- Domyślne wartości odpowiadają wymaganiom produktu: Dock i autostart włączone, wszystkie wartości liczbowe paska menu wyłączone.
- `LaunchAtLoginState` rozdziela zapis intencji od rzeczywistego stanu macOS: unknown, disabled, enabled, requiresApproval, unavailable i failed.
- `PreferencesStore` zapisuje model w osobnych, stabilnych kluczach `UserDefaults` i odtwarza bezpieczne wartości domyślne przy braku kluczy.
- `ApplicationLifecycleCoordinator` uruchamia uczestników dokładnie raz i po zakończeniu procesu zatrzymuje uruchomione usługi w odwrotnej kolejności.
- `AppState` przekazuje koordynatorowi kontrolery scrolla, sieci i metryk. Jedna obserwacja `NSApplication.willTerminateNotification` zastępuje zakończenie obsługiwane wcześniej tylko przez scroll.
- Kontrolery usuwają obserwatorów, anulują pętle i zawieszają lub kończą własne usługi podczas zatrzymania.

## Granice tej części

Model `requestsLaunchAtLogin` wyraża intencję użytkownika. Nie jest prezentowany jako dowód, że autostart działa. Następna część doda adapter `SMAppService.mainApp`, odczyt `status`, obsługę `requiresApproval` i jawne błędy rejestracji. Dopiero adapter Docka wywoła zmianę polityki aktywacji aplikacji. Ustawienia nie są jeszcze pokazane w GUI i nie sterują paskiem menu.

Uruchamianie usług nadal rozpoczyna się wraz z zadaniem głównego okna. Przeniesienie startu do poziomu procesu oraz rozróżnienie uruchomienia ręcznego i przy logowaniu należą do dalszej integracji kroku 7.

## Weryfikacja

- 37 testów MacManagerCore przechodzi, w tym dwa testy koordynatora oraz dwa testy domyślnych i odtwarzanych ustawień integracji.
- Debug build aplikacji dla arm64 i macOS 26 przechodzi.
- Istniejące testy UI pozostają bramką po dodaniu kontrolek i adapterów systemowych.

## Następna część

Adaptery AppKit dla Docka i otwierania okna, następnie rzeczywisty stan autostartu przez `SMAppService`, panel paska menu i testy pełnego cyklu życia F1-06.
