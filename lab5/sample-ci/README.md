# Aplikacja do ćwiczeń CI

Przykładowy menedżer produktów z backendem .NET i frontendem JavaScript. Projekt zawiera testy jednostkowe dla obu części. Workflow'y GitHub Actions z katalogu `.github/workflows` budują i testują aplikację.

## Wymagania lokalne

- .NET 8 SDK
- Node.js 20

## Testy backendu

```bash
dotnet test lab5/sample-ci/backend/ProductApi.Tests/ProductApi.Tests.csproj
```

## Testy frontendu

```bash
cd lab5/sample-ci/frontend
npm ci
npm test
npm run build
```

Workflow startowy `CI` buduje i testuje aplikację. W [instrukcji lab5](../lab5.md) samodzielnie przygotujesz zoptymalizowany workflow z cache, artefaktami i kontrolą PR. Dodatkowym wyzwaniem jest własny job `quality-gate`.
