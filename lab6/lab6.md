# Laboratorium 6 – Azure VM, zależności i Terraform

Na Lab 3 uruchamialiście Nginx na przygotowanej maszynie. Teraz zbudujecie środowisko dla tego kontenera od sieci Azure po gotową odpowiedź HTTP.

## 1. Otwórz Azure Cloud Shell i sprawdź subskrypcję

Zaloguj się do [Azure Portal](https://portal.azure.com/), otwórz **Cloud Shell** ikoną `>_` i wybierz **PowerShell**. Jeśli widzisz Bash, użyj opcji **Switch to PowerShell** na pasku Cloud Shell. Azure CLI i Terraform są już dostępne, a Cloud Shell korzysta z logowania do portalu. [Narzędzia i logowanie Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/features)

Jeśli Cloud Shell zapyta o magazyn, użyj istniejącego magazynu wskazanego przez prowadzącego lub wybierz sesję bez konta Storage. W sesji bez magazynu pliki znikają po jej zakończeniu. W tym trybie po każdym `terraform apply` pobierz przez **Manage files → Download** pliki `terraform.tfstate`, `main.tf` i `~/.ssh/lab6_rsa.pub`. Trzymaj je poza repozytorium. Po przerwaniu sesji sklonuj ponownie repozytorium, odtwórz pliki w ich katalogach, ustaw te same zmienne i wykonaj `terraform init` przed sprzątaniem. [Sesja bez magazynu](https://learn.microsoft.com/azure/cloud-shell/get-started/ephemeral) · [Pobieranie plików z Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/use-the-shell-window#manage-files-menu)

Sprawdź, czy aktywna subskrypcja w Cloud Shell jest tą wskazaną przez prowadzącego. Potrzebujesz uprawnień do zarządzania zasobami Compute i Network oraz do wykonania Run Command w swojej VM.

```powershell
$env:ARM_SUBSCRIPTION_ID = az account show --query id --output tsv
az account show --query '{name:name,id:id}' --output table
terraform version
```

Sprawdź rejestrację providerów w wybranej subskrypcji. Skrypt zaczeka na rejestrację tych, które nie mają statusu `Registered`. Jeśli Azure odmówi dostępu, poproś prowadzącego o rejestrację. [Polecenia az provider](https://learn.microsoft.com/cli/azure/provider#az-provider-register)

```powershell
foreach ($provider in 'Microsoft.Compute', 'Microsoft.Network') {
    $state = az provider show -n $provider --subscription $env:ARM_SUBSCRIPTION_ID `
        --query registrationState -o tsv
    if ($LASTEXITCODE -ne 0) { throw "Nie udało się sprawdzić providera $provider." }
    Write-Host "${provider}: $state"
    if ($state -ne 'Registered') {
        az provider register -n $provider --subscription $env:ARM_SUBSCRIPTION_ID --wait
        if ($LASTEXITCODE -ne 0) { throw "Nie udało się zarejestrować providera $provider." }
    }
}
```

Utwórz klucz SSH dla labu.

```powershell
$sshDir = Join-Path $HOME '.ssh'
New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
$sshKey = Join-Path $sshDir 'lab6_rsa'
if (-not (Test-Path -LiteralPath "$sshKey.pub" -PathType Leaf)) {
    ssh-keygen -t rsa -b 3072 -f $sshKey
}
```

Sklonuj repozytorium studiów stacjonarnych i przejdź do katalogu `lab6/`. Jeśli masz już aktualny klon, otwórz w nim katalog `lab6/`.

```powershell
Set-Location $HOME
git clone https://github.com/robert-cialowicz-ideispl/wsei-devops-lab-z26s.git
Set-Location 'wsei-devops-lab-z26s/lab6'
```

Przekaż Azure tylko klucz publiczny (`.pub`). Karta VM ma wyłącznie prywatny adres. W podsieci jawnie włączamy domyślne wyjście do Internetu. NSG przy podsieci nie otwiera portów dla Internetu, a Nginx nasłuchuje tylko na `127.0.0.1:8080` w VM. Do testu użyjemy Azure Run Command. [Azure Run Command](https://learn.microsoft.com/azure/virtual-machines/linux/run-command)

### Znajdź dostępny rozmiar VM i region

```powershell
$freeSizes = @('Standard_B1s', 'Standard_B2ats_v2')
$sub = $env:ARM_SUBSCRIPTION_ID
$assignmentsJson = az policy assignment list --subscription $sub --filter 'atScope()' -o json
if ($LASTEXITCODE -ne 0) { throw 'Nie można odczytać polityk subskrypcji.' }
$locationPolicies = $assignmentsJson | ConvertFrom-Json | Where-Object {
    $_.displayName -in 'Allowed locations', 'Allowed locations for resource groups' -and
    $_.enforcementMode -ne 'DoNotEnforce' -and $_.parameters.listOfAllowedLocations
}

$regions = if ($locationPolicies) {
    @($locationPolicies)[0].parameters.listOfAllowedLocations.value
} else {
    az account list-locations --subscription $sub --query "[?metadata.regionType=='Physical'].name" -o tsv
    if ($LASTEXITCODE -ne 0) { throw 'Nie można odczytać listy regionów.' }
}
$regions = @($regions | Where-Object {
    $region = $_
    -not ($locationPolicies | Where-Object { $region -notin $_.parameters.listOfAllowedLocations.value })
} | Sort-Object -Property @{ Expression = { $_ -ne 'denmarkeast' } }, @{ Expression = { $_ } } -Unique)

$sizeFilter = ($freeSizes | ForEach-Object { "name=='$_'" }) -join ' || '
$query = "{nextLink:nextLink,skus:value[?resourceType=='virtualMachines' && ($sizeFilter)].{name:name,family:family,restrictions:restrictions}}"
$candidates = @()
$labChoice = $null
foreach ($region in $regions) {
    Write-Host "Sprawdzam $region..."
    $usageJson = az vm list-usage -l $region --subscription $sub -o json
    if ($LASTEXITCODE -ne 0) { throw "Nie można odczytać limitów w $region." }
    $usage = $usageJson | ConvertFrom-Json
    $regional = $usage | Where-Object { $_.name.value -eq 'cores' }
    if (-not $regional -or $regional.limit -le $regional.currentValue) { continue }

    $filter = [uri]::EscapeDataString("location eq '$region'")
    $url = 'https://management.azure.com/subscriptions/{0}/providers/Microsoft.Compute/skus?api-version=2021-07-01&$filter={1}' -f $sub, $filter
    $skus = do {
        $pageJson = az rest --method get --url $url --subscription $sub --query $query -o json
        if ($LASTEXITCODE -ne 0) { throw "Nie można odczytać rozmiarów VM w $region." }
        $page = $pageJson | ConvertFrom-Json
        $page.skus
        $url = $page.nextLink
    } while ($url)

    $candidates = @(foreach ($size in $freeSizes) {
        $sku = $skus | Where-Object { $_.name -eq $size } | Select-Object -First 1
        if (-not $sku) { continue }
        $blocked = $sku.restrictions | Where-Object {
            $_.type -eq 'Location' -and ($region -in $_.restrictionInfo.locations -or $region -in $_.values)
        }
        if ($blocked) { continue }
        $family = $usage | Where-Object { $_.name.value -eq $sku.family }
        $needed = if ($size -eq 'Standard_B1s') { 1 } else { 2 }
        if ($family -and ($regional.limit - $regional.currentValue) -ge $needed -and
            ($family.limit - $family.currentValue) -ge $needed) {
            [pscustomobject]@{ Region = $region; Size = $size; Family = $sku.family }
        }
    })
    if ($candidates.Count -gt 0) { break }
}

if ($candidates.Count -eq 0) { throw 'Brak zgodnej pary region–rozmiar. Zgłoś wynik prowadzącemu.' }
$candidates | Format-Table Region, Size, Family
$labChoice = $candidates[0]
$labChoice | Format-Table Region, Size
```

Skrypt sprawdza oba rozmiary i kończy na pierwszym regionie, w którym można wybrać co najmniej jeden z nich. Zaczyna od `denmarkeast`, jeśli polityki na to pozwalają. Oba warianty wdrożenia używają rozmiaru wybranego w `$labChoice`. Jeśli tabela pokazuje dwa rozmiary, możesz wybrać drugi poleceniem `$labChoice = $candidates[1]`. Skan sprawdza dostępność rozmiaru dla subskrypcji i limity vCPU. Pojemność Azure jest weryfikowana przy wdrożeniu.

## 2. Demonstracja – kolejność w Azure CLI

Prowadzący uruchamia skrypt w osobnej grupie z końcówką `-cli`. Chętni mogą uruchomić go we własnej grupie, jeśli subskrypcja i czas pozwalają na utworzenie dodatkowej VM.

```powershell
./deploy-cli.ps1 -ResourceGroupName 'rg-lab6-123456-cli' -Location $labChoice.Region `
    -PublicKeyPath (Join-Path $HOME '.ssh/lab6_rsa.pub') -VmSize $labChoice.Size
```

| Etap | Czego potrzebuje |
| --- | --- |
| Utworzenie podsieci z NSG | Sieć i grupa zabezpieczeń muszą już istnieć. |
| Utworzenie karty sieciowej VM | Potrzebuje ID podsieci z przypisanym NSG. |
| Utworzenie VM | Potrzebuje ID karty sieciowej. |
| Instalacja Dockera i uruchomienie Nginx | Rozszerzenie instaluje się na istniejącej VM. |
| Niezależny test HTTP przez Run Command | Rozszerzenie musi zdążyć uruchomić kontener. |

Wyszukaj w skrypcie dwa użycia `--no-wait`. Te wywołania przesyłają żądanie i oddają sterowanie w trakcie operacji Azure. Następne `az vm wait --created` i `az vm extension wait --created` sprawdzają stan do `Succeeded`, a po 900 sekundach kończą się błędem. PowerShell zatrzyma skrypt, gdy `az` zwróci błąd. Przy zwykłych wywołaniach CLI bez `--no-wait` polecenia wdrożeniowe same czekają na zakończenie swojej operacji. [Skrypt CLI](deploy-cli.ps1) · [Oczekiwanie na rozszerzenie](https://learn.microsoft.com/cli/azure/vm/extension#az-vm-extension-wait)

**Pytanie do grupy.** Które dwie operacje można zlecić równolegle? Tworzenie sieci i NSG może rozpocząć się równolegle po utworzeniu grupy zasobów.

## 3. Wdrożenie – zależności w Terraformie

Otwórz `main.tf`. Znajdź odwołanie prowadzące z rozszerzenia do VM, z VM do karty oraz z karty do podsieci zabezpieczonej przez NSG. Ostatnie odwołanie wskazuje wynik **powiązania** podsieci z NSG, żeby Terraform wykonał to powiązanie przed utworzeniem karty. W obu wariantach rozszerzenie uruchamia `bootstrap.sh` wewnątrz Ubuntu. [Konfiguracja Terraform](main.tf) · [Skrypt inicjalizacji VM](bootstrap.sh)

```mermaid
flowchart LR
    RG["Grupa zasobów"] --> VNet["Sieć"] --> Subnet["Podsieć"]
    RG --> NSG["NSG"]
    Subnet --> Secure["Powiązanie podsieci z NSG"]
    NSG --> Secure
    Secure --> NIC["Karta sieciowa"]
    NIC --> VM["Ubuntu VM"]
    VM --> Ext["Rozszerzenie: Docker i Nginx"]
    Ext --> Test["Test HTTP przez Run Command"]
```

Wpisz własny numer albumu i ustawienia ustalone na zajęciach. Grupa z końcówką `-tf` musi być nowa. Komunikat `true` z `az group exists` oznacza, że trzeba wybrać inną własną nazwę albo wrócić do stanu, który już zarządza tą grupą.

```powershell
$env:TF_VAR_resource_group_name = 'rg-lab6-123456-tf'
$env:TF_VAR_location = $labChoice.Region
$env:TF_VAR_vm_size = $labChoice.Size
$env:TF_VAR_ssh_public_key_path = Join-Path $HOME '.ssh/lab6_rsa.pub'
az group exists --name $env:TF_VAR_resource_group_name --subscription $env:ARM_SUBSCRIPTION_ID

terraform init
terraform validate
terraform plan
```

W planie sprawdź, czy Terraform proponuje utworzenie zasobów w Twojej grupie. Uruchom `terraform apply` i obserwuj kolejność komunikatów `Creating...` oraz `Creation complete`. Terraform może tworzyć niezależne zasoby równolegle. Tam, gdzie zasób potrzebuje ID innego zasobu, graf wymusza kolejność. Provider obsługuje oczekiwanie na operacje Azure, w tym zakończenie działania rozszerzenia. [Zależności zasobów w Terraformie](https://developer.hashicorp.com/terraform/language/resources/behavior)

Po zakończeniu `apply` uruchom niezależny test HTTP. W wyniku znajdź tekst `Lab 6: Nginx na Azure VM` i sprawdź, czy część `stderr` nie zawiera błędów. W ten sposób potwierdzisz, że aplikacja faktycznie odpowiada.

```powershell
az vm run-command invoke --resource-group $env:TF_VAR_resource_group_name `
    --name lab6-vm --command-id RunShellScript `
    --scripts 'curl -fsS http://127.0.0.1:8080/' `
    --query 'value[].message' --output tsv --subscription $env:ARM_SUBSCRIPTION_ID
```

## 4. Dodaj regułę sieciową i wykryj zmianę w portalu

### Dodaj regułę w Terraformie

Dodaj samodzielnie osobny blok zasobu `azurerm_network_security_rule` w `main.tf`. Reguła ma blokować przychodzące próby połączenia SSH z sieci wirtualnej. Wskaż istniejącą grupę zabezpieczeń `azurerm_network_security_group.lab` przez odwołanie w HCL. [Argumenty zasobu Terraform](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_rule) · [Reguły NSG w Azure](https://learn.microsoft.com/azure/virtual-network/network-security-groups-overview)

| Ustawienie | Oczekiwana wartość |
| --- | --- |
| Nazwa reguły w Azure | `deny-vnet-ssh` |
| Kierunek i akcja | `Inbound`, `Deny` |
| Protokół | `Tcp` |
| Źródło i port źródłowy | `VirtualNetwork`, dowolny port (`*`) |
| Cel i port docelowy | dowolny adres (`*`), port `22` |
| Priorytet | `300` |

Uruchom `terraform plan`. Oczekiwany wynik to utworzenie jednej reguły. Jeśli plan zawiera inne operacje, sprawdź ich przyczynę przed zatwierdzeniem. Wykonaj `terraform apply` i potwierdź w Azure Portal, że reguła ma priorytet `300`.

### Zmień priorytet w Azure Portal

W portalu otwórz własną grupę zasobów z końcówką `-tf`. Wejdź do `lab6-nsg` → **Inbound security rules** → `deny-vnet-ssh`. Zmień priorytet na `310` i zapisz regułę. W `main.tf` zostaw `300`.

Przed wykonaniem `terraform plan` zapisz, jakiej operacji się spodziewasz. Porównaj odpowiedź z wynikiem planu. Oczekiwana zmiana to `~ priority = 310 -> 300`, czyli aktualizacja reguły w miejscu. Taka różnica między rzeczywistym ustawieniem a konfiguracją to *drift*. [Jak działa terraform plan](https://developer.hashicorp.com/terraform/cli/commands/plan)

### Zdecyduj, którą wartość zachować

- **Przywróć `300`.** Wykonaj `terraform apply` i sprawdź priorytet w Azure Portal.
- **Zachowaj `310`.** Zmień priorytet w `main.tf` na `310` i sprawdź, czy konfiguracja zgadza się z Azure.

Uzasadnij wybór jednym zdaniem. Pokaż końcowy `terraform plan` bez zmian i ponów test HTTP Nginx z kroku 3.

## 5. Zapisz wynik i posprzątaj

W raporcie porównaj dwa punkty oczekiwania z CLI z odpowiadającymi im zależnościami w Terraformie i wskaż parę zasobów, które mogą powstać równolegle. Dołącz własny blok HCL reguły, fragment planu po zmianie w portalu, uzasadnienie decyzji, końcowy plan bez zmian i wynik testu HTTP.

W katalogu `lab6/` uruchom `terraform destroy`. Zanim potwierdzisz, sprawdź nazwę swojej grupy `-tf` i zakres planu. Prowadzący usuwa grupę `-cli` z demonstracji przez `az group delete`. Jeśli sam wykonałeś wariant CLI, usuń również swoją grupę `-cli`, po sprawdzeniu jej nazwy i subskrypcji. Stan Terraforma zachowaj do zakończenia sprzątania i trzymaj poza Gitem.

Na Lab 7 te same pojęcia przełożymy na pracę z klastrem: obraz Nginx trafi do `Deployment`, a `Service` skieruje ruch do Podów. W Lab 6 uruchomienie skryptu jest jednorazową operacją wdrożenia. Kubernetes pokazuje, jak kontroler utrzymuje zadaną liczbę instancji także po wdrożeniu. [Harmonogram](../README.md)

Przed zajęciami przeprowadź pilotaż obu wariantów na uprawnionej subskrypcji z parą wybraną przez skrypt. Sprawdź domyślne wyjście do Internetu, czas pracy rozszerzenia, uprawnienia do Run Command i plan po zmianie priorytetu reguły w portalu. Jeśli operacje Azure trwają dłużej, rozpocznij wdrożenie demonstracyjne przed zajęciami.
