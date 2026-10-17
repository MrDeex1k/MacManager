# Ustawienia domyślne i autostart - 2026-10-14

W `/Applications` znaleziono jeden pakiet: MacManager 0.8.3 (build 11), bundle ID `dev.macmanager.MacManager.Development`. Drugie uruchamianie pochodziło z włączonego wpisu logowania starego MacManager 0.8.0 (build 8, `dev.macmanager.MacManager`) w katalogu Xcode DerivedData.

Autostart starej kopii wyłączono w jej własnych ustawieniach, co wyrejestrowało jej SMAppService. Następnie aplikację zamknięto i przeniesiono wyłącznie stary pakiet do Kosza. Jej pozostałe dane i ustawienia zachowano. Końcowy odczyt BTM potwierdza stary wpis jako disabled i bieżący wpis `/Applications` jako enabled. Nie resetowano całej bazy elementów logowania. Nie wykonywano restartu systemu podczas zadania.

Z rozwijanego panelu paska menu usunięto Otwórz wyspę. Dostęp przez hover, menu Widok i ustawienia pozostaje.

Domyślne ustawienia: historia schowka włączona; launcher włączony na Option+Q (keyCode 12, modifier 2048); pomiary co 2 s; adaptacja do oszczędzania energii włączona; wyspa włączona. Zapisane wybory są odtwarzane, bez migracji wymuszającej reset. Ustawienia bieżącej instalacji sprawdzono przez UI: wszystkie pięć opcji już odpowiada poleceniu właściciela; historia jest zaznaczona, skrót to ⌥Q. Nie było potrzeby nadpisania pozostałych preferencji.

129 testów Core przeszło, w tym nowy test fabrycznych ustawień oraz zachowania zapisanych wyborów. Dwa testy GUI przeszły: rzeczywisty skrót Option+Q i uruchomienie aplikacji/polecenia przez launcher oraz panel paska menu bez przycisku wyspy. Release przeszedł. Po podmianie działa jedna kopia z `/Applications`; podpis zachował certyfikat i designated requirement. UI diagnostyki potwierdziło aktywny Scroll i przyznane zgody. Keychain, historia, ustawienia Scrolla i TCC nie zostały resetowane.
