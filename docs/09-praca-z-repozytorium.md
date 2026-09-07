# Praca z repozytorium i Conventional Commits

Wszystkie nowe commity muszą stosować projektową konwencję opartą na [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/). Dotyczy to także zmian dokumentacji i konfiguracji. Zalecany język wiadomości: angielski. Rozdzielać niezależne zmiany na osobne, logiczne commity.

## Instalacja lokalna

Po każdym nowym klonowaniu, przed pierwszym commitem:

~~~sh
./scripts/install-git-hooks.sh
~~~

Skrypt ustawia wyłącznie lokalne core.hooksPath na .githooks. Nie zmienia globalnej konfiguracji, nie instaluje pakietów i nie korzysta z GitHub Actions. Można uruchomić go ponownie. Odmawia zastąpienia innego hooksPath lub wyłączenia istniejących aktywnych hooków; w takim przypadku należy najpierw połączyć ich działanie.

Mechanizm: wersjonowany [commit-msg](../.githooks/commit-msg), uruchamiany przez Git przed utworzeniem commita. Implementacja używa systemowego /bin/sh, awk i Gita. Nie wymaga Node.js, Husky, Pythona, Swift Package ani Homebrew.

Sprawdzenie aktywacji:

~~~sh
git config --local --get core.hooksPath
~~~

Oczekiwany wynik: .githooks. Hook i skrypty mają zapisany w repozytorium bit wykonywalności. Nie wystarczy pobrać samej zawartości hooka jako pliku bez prawa wykonania.

## Format

~~~text
<type>[(scope)][!]: <description>

[optional body]

[optional footers]
~~~

Akceptowane typy: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert. Typ i scope rozpoznawane bez rozróżniania wielkości liter; zalecany zapis małymi literami.

Scope jest opcjonalny; zawiera litery ASCII, cyfry, kropkę, podkreślenie, ukośnik lub myślnik i zaczyna się literą/cyfrą. Przykłady: metrics, scroll, clipboard, ui, network, release. Lista typów i gramatyka scope to polityka tego repozytorium, a nie pełna lista narzucona przez sam standard.

Po dwukropku jedna spacja i niepusty opis. Treść i stopki oddzielone od nagłówka pustym wierszem. Zmiana niekompatybilna może użyć ! po typie/scope lub stopki BREAKING CHANGE: z opisem; BREAKING-CHANGE: jest równoważnym zapisem.

~~~text
docs: add project specification
feat(metrics): add CPU monitoring
fix(scroll): preserve trackpad gestures
test(clipboard): cover retention limits
chore(git): enforce conventional commit messages
refactor(core)!: replace the metrics interface
~~~

Hook waliduje strukturę nagłówka, separator treści oraz niepusty opis jawnej stopki BREAKING CHANGE/BREAKING-CHANGE. Nie ocenia, czy autor wybrał semantycznie właściwy typ, czy zmiana faktycznie jest breaking ani całej gramatyki dowolnych stopek. Za to odpowiada autor i review.

Nie ma wyjątków dla domyślnych wiadomości Merge, Revert, fixup! czy squash!. Jeśli tworzysz takie commity, nadaj im zgodną wiadomość, np. chore(merge): integrate a feature lub revert: undo the scroll change. Nie zmieniamy wstecz istniejącego Initial commit.

## Testowanie

~~~sh
./scripts/test-git-hooks.sh
~~~

Testy tworzą tymczasowe repozytorium i sprawdzają:
- prawidłowe typy, scope, !, treść, stopki i komentarze edytora;
- odrzucanie błędnych nagłówków, pustych opisów i złego separatora;
- rzeczywisty git commit: odrzucenie nie zmienia HEAD;
- ponowną instalację i ochronę już istniejących hooków;
- działanie w ścieżce zawierającej spacje.

Historia roboczego repozytorium i konfiguracja globalna nie są zmieniane przez testy.

## Granice lokalnego wymuszania

Git nie aktywuje wersjonowanych hooków automatycznie po clone. Każdy współtwórca musi wykonać skrypt instalacyjny. Klient GUI musi rzeczywiście uruchamiać hooki Gita; należy sprawdzić go błędną wiadomością w repozytorium testowym.

Hook commit-msg można świadomie ominąć opcją --no-verify lub zmianą konfiguracji. Operacje odtwarzające istniejące commity nie zawsze uruchamiają ten hook. Jest to lokalna kontrola normalnego tworzenia commitów, nie nieusuwalna polityka serwera. Nie obiecujemy blokowania zmian tworzonych w interfejsie GitHub lub w klonie bez aktywacji. W tym projekcie nie dodajemy do tego celu GitHub Actions ani globalnych hooków.

Źródła: [Git hooks](https://git-scm.com/docs/githooks), [core.hooksPath](https://git-scm.com/docs/git-config#Documentation/git-config.txt-corehooksPath).
