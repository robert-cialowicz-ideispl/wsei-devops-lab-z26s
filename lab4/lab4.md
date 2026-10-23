# Laboratorium 4 – Docker Compose: usługi, sieci i wolumeny

Zbudujesz i uruchomisz aplikację z czterech usług, a następnie sprawdzisz trwałość danych, gotowość bazy i izolację sieci. Na koniec zmienisz stronę działającą w kontenerze przez Compose Watch.

## Prerekwizyty i dostęp

1. Korzystaj z tej samej maszyny Ubuntu i bramy WWW co na [lab3](../lab3/lab3.md). Adres IP bramy, numer maszyny `N` i dane logowania podaje prowadzący.
2. Otwórz `https://20.166.92.179/terminal/N`, np. `https://20.166.92.179/terminal/23`, i zaloguj się jako `studentN`. Wszystkie polecenia poniżej wykonuj w **Bash na zdalnym Ubuntu**.
3. Aplikację otwieraj w osobnej karcie pod **`https://20.166.92.179/site/N`**. Brama kieruje ten adres na port **8080** Twojej maszyny. Nie zmieniaj `N`, aby korzystać z cudzej maszyny.
4. Sprawdź narzędzia:

   ```bash
   docker --version
   docker compose version
   docker ps
   free -h
   df -h /
   ```

**Schowek w terminalu WWW:** `Ctrl` + `Alt` + `Shift` otwiera menu Guacamole z polem „Clipboard”. Ten sam skrót zamyka menu.
Przy pracy na własnym komputerze z Dockerem używaj `http://localhost:8080/`. Alternatywny dostęp SSH opisuje lab3.

## 0. Przygotuj własny katalog pracy

```bash
git clone https://github.com/robert-cialowicz-ideispl/wsei-devops-lab-z26s.git ~/wsei-devops-lab-z26s-lab4
cd ~/wsei-devops-lab-z26s-lab4
git status --short
```

Zastąp **`twoj-login` swoim loginem GitHub** we wszystkich dalszych poleceniach:

```bash
git switch -c lab4/twoj-login
mkdir -p lab4/submissions/twoj-login
cp -R lab4/sample-app lab4/submissions/twoj-login/
cp lab4/report-template.md lab4/submissions/twoj-login/README.md
cd lab4/submissions/twoj-login/sample-app
```

Edytuj wyłącznie swoją kopię w `lab4/submissions/twoj-login/`. Wszystkie dalsze polecenia Docker wykonuj w jej katalogu `sample-app`, chyba że instrukcja mówi inaczej. Sprawozdanie jest o katalog wyżej: `../README.md`.

```text
sample-app/
├── backend/             # API .NET 8; zapis i odczyt produktów
├── frontend/            # strona HTML/JS w Nginx
├── gateway/             # Nginx kierujący żądania do frontendu i API
└── docker-compose.yml   # konfiguracja STARTOWA do rozbudowania
```

Droga żądania:

```text
przeglądarka → brama uczelniana /site/N/ → gateway :8080
                                          ├── /           → frontend :80
                                          └── /api/...    → backend :8080 → db :1433
```

Przeglądarka komunikuje się z gateway. Backend korzysta z bazy pod nazwą `db`. Port bazy nie jest publikowany na hoście. Frontend używa względnego adresu `api/products`, dzięki czemu działa również pod `/site/N/`.

Zweryfikuj plik i przygotuj obrazy:

```bash
docker compose config --quiet
docker compose pull db
docker compose build
docker pull python:3.12-alpine
```

Pierwsze pobieranie SQL Server i budowanie .NET może potrwać kilka minut.

Projekt Compose ma nazwę **`lab4`**. Uruchamiaj jedną jego wersję naraz na swojej maszynie. Jawne tagi `lab4-backend:local`, `lab4-frontend:local` i `lab4-gateway:local` pozwalają wykorzystać te same obrazy przy uruchamianiu ręcznym.

Hasło `Lab4Compose!2026` jest wspólną, demonstracyjną wartością do tej bazy laboratoryjnej. Nie używaj tutaj prawdziwych haseł ani danych osobowych; strona pod `/site/N/` jest publiczna.

## 1. Uruchom aplikację ręcznie

**Cel:** zobacz, co Compose za chwilę zrobi za Ciebie. Obrazy są już zbudowane — nie powtarzamy ćwiczenia z Dockerfile z lab3.

### 1.1 Utwórz sieć i uruchom bazę

```bash
docker network create lab4-manual
docker run -d --name lab4-manual-db --network lab4-manual --network-alias db \
  -e ACCEPT_EULA=Y -e MSSQL_PID=Express -e 'MSSQL_SA_PASSWORD=Lab4Compose!2026' \
  mcr.microsoft.com/mssql/server:2022-latest
docker logs --tail 30 lab4-manual-db
```

Poczekaj na komunikat `SQL Server is now ready for client connections`. Sprawdź, czy baza rzeczywiście przyjmuje zapytania:

```bash
docker exec lab4-manual-db /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'Lab4Compose!2026' -C -Q 'SELECT 1' -b
```

Jeśli baza jeszcze startuje, powtórz sprawdzenie po chwili. Dopiero poprawny wynik zapytania oznacza gotowość do kolejnego kroku.

### 1.2 Uruchom pozostałe usługi

```bash
docker run -d --name lab4-manual-backend --network lab4-manual --network-alias backend \
  -e ASPNETCORE_ENVIRONMENT=Development \
  -e 'ConnectionStrings__DefaultConnection=Server=db;Database=ProductsDB;User Id=sa;Password=Lab4Compose!2026;TrustServerCertificate=True;' \
  lab4-backend:local
docker run -d --name lab4-manual-frontend --network lab4-manual --network-alias frontend \
  lab4-frontend:local
docker run -d --name lab4-manual-gateway --network lab4-manual -p 8080:80 \
  lab4-gateway:local
docker ps --filter network=lab4-manual
curl -fsS http://localhost:8080/api/products
```

Jeśli API jeszcze startuje, sprawdź `docker logs lab4-manual-backend` i ponów żądanie po chwili. Otwórz `https://20.166.92.179/site/N/` i dodaj produkt `Test ręczny`.

**Zapisz w sprawozdaniu:** jakie nazwy i parametry trzeba było powtórzyć, aby połączyć cztery usługi?

### 1.3 Zwolnij port i usuń wyłącznie zasoby tego ćwiczenia

```bash
docker stop lab4-manual-gateway lab4-manual-frontend lab4-manual-backend lab4-manual-db
docker rm lab4-manual-gateway lab4-manual-frontend lab4-manual-backend lab4-manual-db
docker network rm lab4-manual
```

Obrazy zachowaj — wykorzysta je Compose. Produkt z ręcznie uruchomionej bazy nie jest przenoszony do nowego zestawu kontenerów.

## 2. Uruchom aplikację przez Compose i zmień port

### 2.1 Odczytaj konfigurację i uruchom projekt

```bash
cat docker-compose.yml
docker compose up -d
docker compose ps -a
docker compose logs --tail 30 backend db
```

Wersja startowa ma cztery usługi, jedną automatyczną sieć i `restart: unless-stopped`. **Nie ma jeszcze wolumenu bazy, healthchecka ani podziału sieci.** Krótkie `depends_on: [db]` określa kolejność uruchamiania, ale nie czeka na gotowość SQL Server. Backend może zakończyć się błędem podczas startu; polityka restartu pozwoli mu spróbować ponownie. Nie musi to wystąpić przy każdym uruchomieniu.

Jeśli baza jest gotowa, ale backend jeszcze nie odpowiada, podejrzyj logi i poczekaj na jego wznowienie. W razie potrzeby po potwierdzeniu gotowości bazy wykonaj `docker compose restart backend gateway`.

```bash
curl -fsS http://localhost:8080/api/products
```

Oczekiwany wynik dla nowej bazy to `[]`. Otwórz stronę i dodaj produkt `Compose start`.

### 2.2 Zmień port hosta

Otwórz plik w edytorze, np. `nano docker-compose.yml`. W usłudze `gateway` zmień **`"8080:80"` na `"8081:80"`**:

```bash
docker compose config --quiet
docker compose up -d
docker compose port gateway 80
curl -fsS http://localhost:8081/api/products
```

Brama uczelniana nadal kieruje `/site/N/` na port **8080**, więc podczas tego eksperymentu strona przez bramę będzie niedostępna. Test wykonujemy z terminala Ubuntu przez `curl`. Przy pracy lokalnej możesz otworzyć `http://localhost:8081/`.

**Przywróć `"8080:80"`**, wykonaj `docker compose up -d` i sprawdź stronę przez bramę. Port wewnątrz gateway cały czas wynosi `80`.

**Odpowiedz:** dlaczego zmiana mapowania gateway nie wymaga zmiany adresu `db` w backendzie?

## 3. Sprawdź trwałość danych i dodaj wolumen

**Przed każdym testem przewidź wynik.** Obserwacje zapisuj w tabeli w sprawozdaniu. Po uruchomieniu usług poczekaj na dostępność API i odśwież stronę.

### 3.1 Zatrzymanie istniejących kontenerów

Dodaj produkt `Przed stop`, a następnie wykonaj:

```bash
docker compose stop
docker compose start
```

Sprawdź, czy produkt nadal istnieje. `stop/start` wykorzystuje te same kontenery i zachowuje ich warstwę zapisywalną. Przy `start` ponownie może wystąpić oczekiwanie backendu na bazę.

### 3.2 Usunięcie i odtworzenie kontenerów

```bash
docker compose down
docker compose up -d
```

Sprawdź produkty ponownie. Bez trwałego montowania danych nowy kontener bazy nie odzyskuje produktów z usuniętego kontenera. To jest **odtworzenie kontenera**, a nie zwykły restart tego samego procesu.

### 3.3 Dodaj nazwany wolumen

Zatrzymaj projekt przez `docker compose down`. W swoim `docker-compose.yml` dopisz do **istniejącej usługi `db`**:

```yaml
    volumes:
      - db-data:/var/opt/mssql
```

Na końcu pliku, **na poziomie `services:`**, dodaj deklarację wolumenu:

```yaml
volumes:
  db-data:
```

Fragmenty należy włączyć do istniejącej konfiguracji. Nie twórz drugiego klucza `services:` ani drugiej definicji `db`. W YAML używaj spacji, nie tabulatorów.

```bash
docker compose config --quiet
docker compose up -d
docker volume inspect lab4_db-data
```

Dodaj produkt **`Z wolumenem`**, a następnie powtórz:

```bash
docker compose down
docker compose up -d
```

Produkt powinien nadal istnieć. Zapisz dowód w sprawozdaniu. Dodanie wolumenu nie odzyskuje danych utraconych w kroku 3.2.

Zwykłe `down` pozostawia nazwany wolumen. Opcja **`down -v` usunęłaby także wolumen i dane tego projektu** — na tym etapie jej nie wykonuj. Wyjaśnij przewidywany wynik w tabeli. Więcej: [dokumentacja `docker compose down`](https://docs.docker.com/reference/cli/docker/compose/down/).

## 4. Poczekaj na gotowość bazy

Zatrzymaj projekt przez `docker compose down`, zachowując wolumen. Do usługi `db` dodaj:

```yaml
    healthcheck:
      test: ["CMD", "/opt/mssql-tools18/bin/sqlcmd", "-S", "localhost", "-U", "sa", "-P", "Lab4Compose!2026", "-C", "-Q", "SELECT 1", "-b"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 30s
```

`sqlcmd` wykonuje rzeczywiste zapytanie. `-b` ustawia niezerowy kod zakończenia przy błędzie SQL, a `-C` pozwala użyć certyfikatu demonstracyjnej bazy.

W usłudze `backend` **zastąp dotychczasowe `depends_on`**:

```yaml
    depends_on:
      db:
        condition: service_healthy
```

```bash
docker compose config --quiet
docker compose up -d
docker compose ps
docker compose logs --tail 30 db backend
```

Oczekiwany rezultat: baza osiąga stan `healthy`, po czym Compose uruchamia backend. Dodany wcześniej produkt powinien pozostać w bazie. Zapisz wynik `docker compose ps`.

**Odpowiedz:** czym różnią się stan `running`, pozytywny healthcheck bazy i `restart: unless-stopped`? Healthcheck sam nie restartuje kontenera, który jest `unhealthy`. Endpoint aplikacji `/health` potwierdza działanie procesu API; nie zastępuje zapytania do bazy.

Więcej: [gotowość i kolejność uruchamiania w Compose](https://docs.docker.com/compose/how-tos/startup-order/).

## 5. Podziel sieć i sprawdź izolację

Zatrzymaj projekt przez `docker compose down`. Dopisz na poziomie głównym pliku:

```yaml
networks:
  app-network:
  backend-network:
    internal: true
```

Przypisz każdej usłudze pole `networks` według tabeli. Przykład dla backendu:

```yaml
    networks:
      - app-network
      - backend-network
```

| Usługa | `app-network` | `backend-network` |
|---|---|---|
| `gateway` | tak | nie |
| `frontend` | tak | nie |
| `backend` | tak | tak |
| `db` | nie | tak |

```bash
docker compose config --quiet
docker compose up -d
docker network inspect lab4_app-network lab4_backend-network
```

Nazwy zasobów zawierają prefiks `lab4`, ponieważ tak nazywa się projekt. `internal: true` tworzy sieć izolowaną od zewnętrznej komunikacji. Oddzielenie frontendu od bazy wynika również z tego, że nie współdzielą żadnej sieci.

### 5.1 Połączenie z sieci bazy

Uruchom jednorazowy kontener diagnostyczny. Sprawdza on TCP pod nazwą usługi `db`, bez logowania do SQL Server:

```bash
docker run --rm --network lab4_backend-network python:3.12-alpine \
  python -c "import socket; s=socket.create_connection(('db',1433),3); print('OK: db:1433'); s.close()"
```

Oczekiwane: **`OK: db:1433`**.

### 5.2 To samo połączenie z sieci aplikacji

```bash
docker run --rm --network lab4_app-network python:3.12-alpine \
  python -c "import socket; s=socket.create_connection(('db',1433),3); print('OK: db:1433'); s.close()"
echo "Kod zakończenia: $?"
```

Oczekiwany jest **błąd wyszukania nazwy lub połączenia i niezerowy kod zakończenia**. To poprawny rezultat testu izolacji. Zachowaj oba wyniki.

Otwórz aplikację i dodaj kolejny produkt. Backend ma dostęp do obu sieci, dlatego aplikacja nadal działa.

**Odpowiedz:** dlaczego używamy nazwy `db`, a nie zapamiętanego IP kontenera? Dlaczego frontend i gateway nie potrzebują sieci bazy? Więcej: [sieci w Compose](https://docs.docker.com/compose/how-tos/networking/).

## 6. Aktualizuj frontend przez Compose Watch

W usłudze `frontend`, obok `build` i `networks`, dodaj:

```yaml
    develop:
      watch:
        - action: sync
          path: ./frontend/index.html
          target: /usr/share/nginx/html/index.html
```

Ścieżka `path` wskazuje plik w Twojej kopii projektu na Ubuntu. `target` wskazuje plik w kontenerze frontendu. Nie zmieniaj pliku bezpośrednio wewnątrz kontenera.

```bash
docker compose config --quiet
docker compose up -d
docker compose watch
```

Ostatnie polecenie działa na pierwszym planie i pokazuje zdarzenia synchronizacji. Otwórz **drugi terminal na tej samej maszynie Ubuntu**, np. drugie połączenie Guacamole, i przejdź do swojej kopii projektu:

```bash
cd ~/wsei-devops-lab-z26s-lab4/lab4/submissions/twoj-login/sample-app
nano frontend/index.html
```

Zmień widoczny nagłówek `Lista produktów — lab4` na **`Lista produktów — Imię Nazwisko — Watch`**. Zapisz plik, sprawdź zdarzenie w pierwszym terminalu i odśwież stronę. Używaj wyłącznie fikcyjnych nazw produktów.

Sprawdź:

- Czy nowy nagłówek jest widoczny bez `docker compose build`?
- Czy produkty dodane w ćwiczeniach 3–5 nadal istnieją?
- Czy zmiana frontendu wymagała odtworzenia bazy?

Zapisz zrzut strony i zdarzenie synchronizacji. `Ctrl+C` w terminalu z `docker compose watch` kończy obserwowanie; usługi uruchomione wcześniej przez `up -d` pozostają uruchomione.

`sync` kopiuje plik do działającego kontenera. Nginx odczytuje HTML przy kolejnym żądaniu, dlatego wystarcza odświeżenie strony. Samo kopiowanie źródła C# nie przebudowałoby skompilowanego backendu. Zmiany synchronizowane przez Watch nie zmieniają również wcześniej zbudowanego obrazu; przy kolejnym odtworzeniu frontendu zaktualizuj obraz przez `docker compose build frontend` lub ponownie uruchom Watch.

Więcej: [Compose Watch i wymagania wersji](https://docs.docker.com/compose/how-tos/file-watch/).

## 7. Sprawdź wynik i oddaj pracę

Zakończ Watch przez `Ctrl+C`. Zweryfikuj kompletny projekt, odtwarzając go z aktualnego kodu i zachowując wolumen:

```bash
docker compose config --quiet
docker compose down
docker compose up -d --build
docker compose ps
curl -fsS http://localhost:8080/api/products
```

Odśwież stronę. Powinien pozostać zmieniony nagłówek oraz produkty zapisane po dodaniu wolumenu.

Uzupełnij `../README.md`. Do oddania wymagane są:

1. Własna działająca kopia aplikacji i `docker-compose.yml`: wolumen, healthcheck bazy, oczekiwanie backendu, dwie sieci i Watch; gateway na porcie 8080.
2. Zrzut `docker compose ps` i działającej strony z produktami.
3. Tabela obserwacji trwałości danych, z dowodem zachowania produktu po `down/up` z wolumenem.
4. Wyniki dwóch testów sieci: dostęp z `backend-network` i brak dostępu z `app-network`.
5. Dowód synchronizacji Watch i odpowiedzi na pytania ze skryptu.

Zrzuty zapisz we własnym katalogu oddania, np. `../screenshots/`, i podlinkuj w sprawozdaniu. Nie dołączaj haseł do bramy, tokenów, wyników `docker inspect` zawierających prywatne dane ani plików kompilacji `bin/` i `obj/`.

Z katalogu `sample-app` wróć do katalogu głównego repozytorium:

```bash
cd ../../../..
git status --short
git add lab4/submissions/twoj-login
git diff --cached --stat
```

Sprawdź, czy podsumowanie zawiera **wyłącznie Twój katalog `lab4/submissions/twoj-login/`**. Następnie:

```bash
git commit -m "Add Lab 4 submission for twoj-login"
git push --set-upstream origin lab4/twoj-login
```

Na GitHub utwórz Pull Request do `main` repozytorium kursowego z tytułem **`Lab 4 – twoj-login`**. Korzystaj z własnego konta. Przekaż prowadzącemu URL PR w miejscu wskazanym na zajęciach i pozostaw go otwartego do oceny. Przy braku uprawnień do push zgłoś to prowadzącemu.

Po zebraniu dowodów możesz zatrzymać projekt przez `docker compose down`, będąc ponownie w swojej kopii `sample-app`. Wolumen pozostaw do czasu oceny.

## Zadania dodatkowe

- **Kontekst budowania:** przenieś Dockerfile backendu do katalogu `docker/` we własnej kopii i ustaw `build.context: ./backend` oraz `build.dockerfile: ../docker/backend.Dockerfile`. Sprawdź `docker compose build backend` i wyjaśnij, względem czego Docker interpretuje `COPY`.
- **Świadome usunięcie danych:** po ocenie i wyłącznie dla demonstracyjnej bazy tego projektu wykonaj `docker compose down -v`, uruchom projekt ponownie i porównaj wynik z wcześniejszym przewidywaniem.

## Gdy coś nie działa

| Objaw | Co sprawdzić |
|---|---|
| `port is already allocated` | `docker ps --filter publish=8080`; zatrzymaj swój poprzedni kontener lab3 lub ręczny gateway. |
| Brama zwraca 502/503 | Przywróć port `8080:80`, sprawdź `docker compose ps -a` i żądanie `curl` na Ubuntu; sprawdź końcowy ukośnik w `/site/N/`. |
| Strona się otwiera, ale API nie działa | `docker compose logs --tail 50 backend gateway db`; poczekaj na bazę. Nie dodawaj początkowego `/` do `api/products` we frontendzie. |
| Baza ma status `unhealthy` | `docker compose logs --tail 50 db`; sprawdź pamięć, hasło, ścieżkę `sqlcmd` i parametr `-C`. |
| Nginx zgłasza brak hosta upstream | Sprawdź przypisanie usług do sieci; po poprawieniu wykonaj `docker compose down` i `docker compose up -d`, bez `-v`. |
| Watch nie widzi zmian | Sprawdź wersję Compose, działającą sesję Watch i edycję pliku w tej samej kopii projektu na Ubuntu. |
| YAML nie przechodzi walidacji | Sprawdź wcięcia i powtórzone klucze. `volumes` i `networks` występują zarówno przy usłudze, jak i jako deklaracje na poziomie głównym. |
