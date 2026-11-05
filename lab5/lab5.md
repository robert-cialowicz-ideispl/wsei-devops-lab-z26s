# Laboratorium 5 – CI w GitHub Actions

**Cel:** automatycznie budować i testować aplikację, porównać prosty i zoptymalizowany workflow oraz sprawdzić, jak wyniki CI kontrolują pull request.

W tym laboratorium używamy GitHub Actions. Pipeline kończy się na zbudowaniu i sprawdzeniu aplikacji — wdrażanie będzie omawiane później.

## 1. Przygotuj repozytorium

Sklonuj własny fork repozytorium i przejdź do katalogu:

```bash
git clone https://github.com/<twoj-login>/wsei-devops-lab-z26s.git
cd wsei-devops-lab-z26s
git switch main
git pull
git switch -c lab5/<twoj-login>
```

Zastąp `<twoj-login>` swoim loginem GitHub. Pracuj na tej gałęzi i w swoim forku.

Projekt do ćwiczeń znajduje się w `lab5/sample-ci`. Zawiera backend .NET, frontend JavaScript oraz testy obu części. Workflow'y są w `.github/workflows/ci.yml` i `.github/workflows/ci-optimized.yml`.

## 2. Uruchom i przeanalizuj podstawowy workflow

Workflow `CI` uruchamia się po pushu do `main` oraz przy pull requeście kierowanym do `main`.

1. Otwórz `.github/workflows/ci.yml`.
2. Rozpoznaj sekcje `on`, `permissions`, `jobs`, `steps` oraz `needs`.
3. Wykonaj zmianę w `lab5/sample-ci/frontend/index.html`, a następnie zapisz ją, commitując i wysyłając na swoją gałąź:

```bash
git add lab5/sample-ci/frontend/index.html
git commit -m "Trigger lab 5 CI"
git push -u origin lab5/<twoj-login>
```

4. W GitHub otwórz PR z tej gałęzi do `main`; uruchomią się workflow'y CI.
5. W zakładce **Actions** sprawdź kolejność jobów, logi oraz artefakty `backend-publish` i `frontend-dist`.

Zwróć uwagę, że każdy job działa na osobnym runnerze. Następny job nie otrzymuje plików z poprzedniego automatycznie; potrzebuje własnego checkoutu albo artefaktu.

## 3. Zoptymalizuj workflow

Otwórz `.github/workflows/ci-optimized.yml`. Ten workflow łączy kroki backendu w jeden job i kroki frontendu w drugi. Oba joby mogą działać równolegle.

1. Otwórz PR z gałęzi roboczej do `main`; uruchomią się oba workflow'y.
2. Porównaj czas wykonania oraz widok grafu jobów dla **CI** i **CI - Optimized**.
3. W workflow zoptymalizowanym odszukaj:
   - cache NuGet i npm;
   - `npm ci` oraz flagi `--no-restore` i `--no-build`;
   - równoległe joby `backend` i `frontend`;
   - artefakty dostępne do pobrania po zakończeniu workflow.
4. Zapisz czasy obu przebiegów i wyjaśnij, które zmiany wpłynęły na wynik.

Workflow `CI - Optimized` dodaje też job `quality-gate`. Jego `needs: [backend, frontend]` oznacza, że wystartuje dopiero po pomyślnym zakończeniu obu kontroli. Jeśli którykolwiek test nie przejdzie, bramka również nie przejdzie.

## 4. Sprawdź działanie quality gate i PR

1. W gałęzi z otwartym PR-em edytuj `lab5/sample-ci/frontend/app.test.js` i tymczasowo zmień oczekiwaną wartość w jednym asercie, aby test nie przechodził.
2. Zacommituj zmianę i wypchnij ją na tę samą gałąź.
3. Sprawdź, że job frontendu oraz `quality-gate` zakończyły się błędem.
4. Przywróć poprawną wartość, wypchnij poprawkę i sprawdź zielony wynik workflow.
5. Jeśli ustawienia repozytorium na to pozwalają, w **Settings → Rules** skonfiguruj regułę dla `main`, która wymaga PR-a oraz przejścia checku **Quality gate** przed scaleniem.

Po zakończeniu zamknij testowy PR albo zmerguj poprawiony PR, zgodnie z ustaleniami prowadzącego.

## 5. Zapisz i oddaj pracę

Wyślij zmiany na swoją gałąź i utwórz PR do `main` w swoim repozytorium:

```bash
git add .github/workflows/ci-optimized.yml lab5
git commit -m "Complete lab 5 CI exercise"
git push
```

W opisie PR podaj:

- wynik i czasy dwóch workflow'ów;
- co zmieniło optymalizację;
- zrzut ekranu pokazujący zielony `quality-gate` dla poprawnego PR.

## Dodatkowe pytania

- Dlaczego testy backendu i frontendu mogą działać równolegle?
- Kiedy warto użyć `needs`, a kiedy zależność między jobami tylko wydłuża pipeline?
- Do czego służą artefakty i czym różnią się od cache?
- Dlaczego publikowanie obrazu lub wdrożenie aplikacji powinno nastąpić dopiero po przejściu wymaganych testów?
