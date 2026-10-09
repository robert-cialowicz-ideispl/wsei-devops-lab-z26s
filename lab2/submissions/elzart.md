# Lab 2 – Linux i GitHub

Login GitHub: elzart

## Polecenia Linux

| Polecenie | Do czego służy | Moja obserwacja lub wynik |
|---|---|---|
| `pwd` | Pokazuje bieżący katalog. | `/c/Users/Student/Documents/lab2/wsei-devops-lab-z26s` – Git Bash na Windows pokazuje dysk `C:` jako `/c/`. |
| `ls -la` | Wyświetla pliki, w tym ukryte. | Widać ukryty katalog `.git` oraz `README.md`, `lab1/`, `lab2/`; dla każdego wpisu uprawnienia, właściciela, rozmiar i datę. |
| `mkdir -p` | Tworzy katalogi. | Utworzyło katalog `lab2/submissions` (wcześniej go nie było – `git status` pokazał go jako nowy, `??`). Z `-p` polecenie nie zgłosiłoby błędu, gdyby katalog już istniał. |
| `grep -n` | Wyszukuje tekst i pokazuje numer wiersza. | Wynik `2:Druga linia` – szukany tekst jest w drugim wierszu pliku tymczasowego. |
| `wc -l` | Liczy wiersze pliku. | Wynik `2 /tmp/tmp.IaD2afmW1L` – plik z `mktemp` ma 2 wiersze. |

## Git i Pull Request

- Nazwa mojej gałęzi: `lab2/elzart`
