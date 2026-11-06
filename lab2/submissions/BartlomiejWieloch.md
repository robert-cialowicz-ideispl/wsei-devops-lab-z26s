# Lab 2 – Linux i GitHub

Login GitHub: OzzyTheHuman - Bartłomiej Wieloch

## Polecenia Linux

| Polecenie | Do czego służy | Moja obserwacja lub wynik |
|---|---|---|
| `pwd` | Pokazuje bieżący katalog. | pwd -> /c/Users/Student/wsei-devops-lab-z26s |
| `ls -la` | Wyświetla pliki, w tym ukryte. | ls -la -> total 16
drwxr-xr-x 1 Student 197121    0 Oct  9 16:00 ./
drwxr-xr-x 1 Student 197121    0 Oct  9 16:00 ../
drwxr-xr-x 1 Student 197121    0 Oct  9 16:06 .git/
-rw-r--r-- 1 Student 197121 1014 Oct  9 16:00 README.md
drwxr-xr-x 1 Student 197121    0 Oct  9 16:00 lab1/
drwxr-xr-x 1 Student 197121    0 Oct  9 16:00 lab2/ |
| `mkdir -p` | Tworzy katalogi. | $ mkdir -p lab2/submissions
-> utworzyło katalog w lokalizacji lab2 -> ~/wsei-devops-lab-z26s/lab2 (lab2/BartlomiejWieloch)
$ ls -la
total 12
drwxr-xr-x 1 Student 197121    0 Oct  9 16:06 ./
drwxr-xr-x 1 Student 197121    0 Oct  9 16:00 ../
-rw-r--r-- 1 Student 197121 8701 Oct  9 16:00 lab2.md
drwxr-xr-x 1 Student 197121    0 Oct  9 16:06 submissions/
 |
| `grep -n` | Wyszukuje tekst i pokazuje numer wiersza. | $ grep -n 'Druga' "$practice_file" ->
2:Druga linia
 |
| `wc -l` | Liczy wiersze pliku. | $ wc -l "$practice_file" ->
2 /tmp/tmp.uth50s0a8r
 |

## Git i Pull Request

- Nazwa mojej gałęzi: `lab2/BartlomiejWieloch`
