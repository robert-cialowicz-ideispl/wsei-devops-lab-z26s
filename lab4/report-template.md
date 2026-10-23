# Lab 4 – Docker Compose

- Imię i nazwisko:
- Login GitHub:
- Numer albumu:
- Numer maszyny `N`:
- Wersja Docker Compose:

## 1. Uruchomienie i porty

Wstaw zrzut działającej strony i `docker compose ps`.

- Jakie parametry powtarzały się przy ręcznym uruchamianiu usług?
- Co oznacza `8080:80`? Który port zmieniłeś w eksperymencie z 8081?
- Dlaczego zmiana portu gateway nie zmienia adresu bazy w backendzie?

## 2. Trwałość danych

Przewidywania wpisz przed testem. W ostatnim wierszu podaj tylko przewidywanie; usunięcie wolumenu jest zadaniem dodatkowym po ocenie.

| Konfiguracja | Operacja | Przewidywany wynik | Zaobserwowany wynik |
|---|---|---|---|
| Bez nazwanego wolumenu | `stop` → `start` | | |
| Bez nazwanego wolumenu | `down` → `up -d` | | |
| Z nazwanym wolumenem | `down` → `up -d` | | |
| Z nazwanym wolumenem | `down -v` → `up -d` | | Nie wykonywano / zadanie dodatkowe |

Podaj nazwę produktu kontrolnego i dołącz dowód jego obecności po `down/up` z wolumenem.

## 3. Gotowość usług

- Co sprawdza healthcheck SQL Server?
- Czym różnią się `running`, `healthy` i polityka `restart`?
- Dlaczego krótkie `depends_on` nie wystarcza do potwierdzenia gotowości bazy?

## 4. Izolacja sieci

Wklej polecenia i wyniki obu testów TCP, w tym kod zakończenia nieudanego testu.

| Sieć kontenera diagnostycznego | Wynik połączenia z `db:1433` |
|---|---|
| `lab4_backend-network` | |
| `lab4_app-network` | |

- Dlaczego backend należy do obu sieci?
- Dlaczego korzystamy z nazwy `db`, a nie IP kontenera?

## 5. Compose Watch

Wstaw zrzut zmienionego nagłówka i zdarzenie synchronizacji z terminala.

- Czy trzeba było ręcznie przebudować frontend?
- Czy produkty pozostały w bazie?
- Czym synchronizacja HTML różni się od przebudowania obrazu?

## 6. Weryfikacja końcowa

- Wynik `docker compose config --quiet`:
- Czy po końcowym `down` i `up -d --build` działają strona i API?
- Czy produkty zapisane z wolumenem nadal istnieją?
- Czy gateway ponownie używa portu 8080?

## Zadania dodatkowe

Opisz wyłącznie, jeśli zostały wykonane.
