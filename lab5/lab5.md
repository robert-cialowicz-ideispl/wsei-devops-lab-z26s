# Laboratorium 5 – CI w GitHub Actions

**Cel:** samodzielnie przebudować pipeline, który buduje i testuje aplikację, oraz wykorzystać wyniki CI do kontroli pull requestów.

Punktem startowym jest działający, ale nieoptymalny workflow `CI`. Twoim zadaniem będzie przygotowanie własnego pliku `ci-optimized.yml`. Oddajesz kod workflow, dowód wykrycia błędu przez CI i krótkie uzasadnienie swoich decyzji.

## 1. Przygotuj własne repozytorium

Potrzebujesz konta GitHub, edytora i terminala z Git. Polecenia poniżej są przeznaczone dla Bash. Budowanie i testy wykonają się na runnerach GitHub — instalacja .NET i Node.js lokalnie jest opcjonalna.

1. Utwórz **publiczny fork** [repozytorium studiów stacjonarnych](https://github.com/robert-cialowicz-ideispl/wsei-devops-lab-z26s). Jeśli masz już fork z poprzednich zajęć, użyj **Sync fork**, aby pobrać aktualne materiały.
2. Zastąp `TWOJ_LOGIN` swoim loginem GitHub i sklonuj własny fork:

```bash
git clone https://github.com/TWOJ_LOGIN/wsei-devops-lab-z26s.git
cd wsei-devops-lab-z26s
git switch -c lab5/ci
```

Jeśli korzystasz z istniejącej kopii, najpierw przejdź na `main` i pobierz zmiany przez `git pull --ff-only`, a następnie utwórz gałąź roboczą.

3. Sprawdź, że `origin` wskazuje Twój fork: `git remote -v`.
4. W zakładce **Actions** swojego forka włącz workflow'y, jeśli GitHub o to poprosi.

Projekt `lab5/sample-ci` zawiera backend .NET 8, frontend JavaScript oraz testy obu części. Workflow startowy znajduje się w `.github/workflows/ci.yml`.

## 2. Uruchom pipeline i znajdź problemy

1. Otwórz `ci.yml`. Rozpoznaj zdarzenia w `on`, joby, kroki, runnery oraz zależności `needs`.
2. Zmień tytuł strony w `lab5/sample-ci/frontend/index.html`, a następnie zapisz zmianę:

```bash
git add lab5/sample-ci/frontend/index.html
git commit -m "Start lab 5 CI exercise"
git push -u origin lab5/ci
```

3. Otwórz PR z `lab5/ci` do `main` **w swoim forku**. Sprawdź pole **base repository** — powinno wskazywać Twoje konto, a nie repozytorium prowadzącego.
4. Jeśli workflow'y w forku wymagają zatwierdzenia pierwszego przebiegu, zatwierdź go w zakładce **Actions**.
5. Obejrzyj graf i logi workflow `CI`. Pobierz artefakty `backend-publish` i `frontend-dist`; sprawdź, jakie pliki zawierają.
6. Utwórz `lab5/report.md` i zapisz:
   - co najmniej trzy miejsca, w których powtarzana jest praca;
   - które joby działają równolegle, a które czekają na poprzednie;
   - czas całego przebiegu oraz czas wybranego joba.

**Pytanie do analizy:** dlaczego job `backend-test` ponownie pobiera kod i buduje projekt, mimo że wcześniejszy job wykonał już build? Każdy job otrzymuje osobnego runnera. Samo `needs` nie przekazuje plików ani zainstalowanych zależności.

## 3. Samodzielnie zbuduj zoptymalizowany workflow

Skopiuj plik startowy:

```bash
cp .github/workflows/ci.yml .github/workflows/ci-optimized.yml
```

Nadaj kopii nazwę workflow **CI - Optimized**. Przebuduj jej sekcję `jobs` zgodnie z poniższymi wymaganiami. Oryginalny `ci.yml` zachowaj do porównania.

| Element | Wymaganie |
|---|---|
| Uruchamianie | Push do `main` i PR kierowany do `main` |
| Uprawnienia | Odczyt zawartości repozytorium |
| Runner | Ubuntu 24.04 (`ubuntu-24.04`) |
| Job `backend` | Checkout, .NET 8, restore, build, test i publish |
| Job `frontend` | Checkout, Node.js 24, instalacja zależności, test i build |
| Równoległość | Backend i frontend startują niezależnie od siebie |
| Powtórzenia | SDK i zależności przygotowujesz raz w każdym jobie |
| Artefakty | Można pobrać opublikowany backend i zbudowany frontend |

Samodzielnie dobierz akcje, kolejność kroków, katalogi pracy i ścieżki artefaktów. Polecenia budowania i testowania znajdziesz w pliku startowym.

Wersje akcji pobierz z pliku startowego: `actions/checkout@v7`, `actions/setup-dotnet@v6`, `actions/setup-node@v7` i `actions/upload-artifact@v7`. Wersja akcji `setup-node` i jej parametr `node-version: 24` to różne ustawienia — parametr wybiera Node.js do budowania i testowania frontendu.

**Wskazówki:**

- W backendzie restore i build projektu testowego obejmują również projekt API, do którego odwołują się testy.
- Po wykonaniu restore użyj `--no-restore` przy buildzie, a po buildzie użyj `--no-build` przy testach i publish.
- Zachowaj tę samą konfigurację `Release` we wszystkich poleceniach .NET.
- W frontendzie wykorzystaj istniejący lockfile i `npm ci`.
- `defaults.run.working-directory` dotyczy kroków `run`; ścieżkę dla `upload-artifact` podaj względem katalogu głównego repozytorium.
- Sprawdź, czy nie pozostawiłeś `needs` wskazujących na usunięte joby.

Zacommituj nowy plik i wypchnij go na gałąź z otwartym PR-em. Oba workflow'y powinny się uruchomić. Popraw błędy YAML, ścieżek lub poleceń na podstawie logów, aż oba joby nowego workflow zakończą się sukcesem.

## 4. Dodaj cache i porównaj wyniki

Rozszerz własny workflow o cache zależności:

1. Dla backendu użyj `actions/cache@v6`, aby zapamiętać katalog `~/.nuget/packages`. Zbuduj klucz uwzględniający system runnera i hash plików `.csproj`.
2. Dla frontendu skonfiguruj cache npm w `actions/setup-node@v7`. Wskaż właściwy `cache-dependency-path` do `package-lock.json`.
   W pliku startowym cache jest celowo wyłączony przez `package-manager-cache: false`. W swoim workflow ustaw tę opcję na `true` i jawnie dodaj `cache: npm`.
3. Wypchnij zmianę i obejrzyj logi odtwarzania cache.
4. Wykonaj kolejny commit, np. uzupełniając raport, aby porównać przebieg z już zapisanym cache.
5. W raporcie zestaw czas workflow bazowego i własnego dla tego samego commita oraz zanotuj, czy cache został odtworzony.

Cache npm przechowuje pobrane pakiety, a nie gotowy katalog `node_modules` — krok `npm ci` nadal jest potrzebny. Cache i artefakt mają różne zastosowania: cache przyspiesza kolejne przebiegi, a artefakt udostępnia wynik konkretnego przebiegu.

Nie zakładaj z góry konkretnego przyspieszenia. Opisz rzeczywisty wynik, uwzględniając czas oczekiwania na runnera i pierwszy przebieg bez cache.

## 5. Wykaż, że CI wykrywa błąd w PR

1. Na tej samej gałęzi zmień **jedną oczekiwaną wartość** w `lab5/sample-ci/frontend/app.test.js`, aby istniejący test się nie powiódł.
2. Zacommituj zmianę i wypchnij ją do otwartego PR-a.
3. W logach znajdź nazwę nieudanego testu, oczekiwaną wartość oraz otrzymany wynik. Zapisz w raporcie link do przebiegu.
4. Sprawdź, które joby zakończyły się błędem, a które nadal mogły działać.
5. Napraw zmianę w kolejnym commicie i wykaż, że checki PR-a ponownie są zielone.
6. W swoim repozytorium skonfiguruj regułę dla `main`, która wymaga PR-a i pomyślnych checków obu jobów z **Twojego** workflow. Wybierz ich rzeczywiste nazwy widoczne w GitHub. Jeśli Twój plan lub uprawnienia nie pozwalają włączyć reguły, opisz ograniczenie w raporcie.

Nie usuwaj testu ani kroku testowania, aby uzyskać zielony wynik. W historii PR-a mają pozostać zarówno commit wykryty jako błędny, jak i jego poprawka.

## 6. Dodatkowe wyzwanie: wspólna bramka quality gate

Dodaj do swojego workflow trzeci job o identyfikatorze `quality-gate`, który zbiera wyniki backendu i frontendu.

Wymagane zachowanie:

- czeka na oba joby przez `needs: [backend, frontend]`;
- uruchamia się również wtedy, gdy któryś z nich zawiedzie;
- kończy się sukcesem tylko wtedy, gdy **oba** wyniki są równe `success`;
- w przypadku błędu kończy się niezerowym kodem wyjścia.

**Wskazówki:** sprawdź warunek joba `always()`, kontekst `needs.backend.result` i polecenie Bash `exit 1`. Samo dodanie `needs` nie wystarcza: po błędzie zależności kolejny job może zostać pominięty. Twoja bramka ma jawnie zgłosić błąd.

Powtórz scenariusz z błędnym testem i jego naprawą. Jeśli bramka działa poprawnie, ustaw jej check jako wymagany dla PR-a. Do raportu dołącz graf jobów i wyniki obu scenariuszy.

## 7. Oddaj pracę

Uzupełnij `lab5/report.md`, zapisz zmiany i wypchnij je na gałąź roboczą:

```bash
git add .github/workflows/ci-optimized.yml lab5/report.md
git commit -m "Complete lab 5 CI exercise"
git push
```

Przekaż prowadzącemu link do otwartego PR-a w swoim forku. PR powinien zawierać:

- **Twój plik `ci-optimized.yml`** z dwoma równoległymi jobami, cache i artefaktami;
- raport z diagnozą workflow startowego i uzasadnieniem zmian;
- czasy przebiegów oraz informację o odtworzeniu cache;
- link do przebiegu z nieudanym testem i do przebiegu po naprawie;
- dowód wymaganych checków PR-a albo opis ograniczenia ustawień;
- jeśli wykonasz wyzwanie: własny `quality-gate` i dowody jego działania.

Nie scalaj PR-a przed oddaniem pracy. Prowadzący powinien móc przejrzeć zmiany, historię commitów i wyniki CI.

## Dokumentacja pomocnicza

- [Składnia workflow, jobów i needs](https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions)
- [Cache zależności](https://docs.github.com/en/actions/using-workflows/caching-dependencies-to-speed-up-workflows)
- [Artefakty workflow](https://docs.github.com/en/actions/using-workflows/storing-workflow-data-as-artifacts)
- [Kontekst needs](https://docs.github.com/en/actions/learn-github-actions/contexts#needs-context)
