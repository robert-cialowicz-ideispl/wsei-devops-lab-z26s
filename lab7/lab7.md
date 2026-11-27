# Laboratorium 7 – Kubernetes w Azure

W [Lab 6](../lab6/lab6.md) wdrażaliście maszynę i sieć z kodu. Teraz wdrożycie w ten sam sposób klaster Azure Kubernetes Service (AKS), a następnie użyjecie `kubectl` do uruchomienia aplikacji z frontendem, API i bramą HTTP.

## 1. Przygotuj Cloud Shell

Otwórz [Azure Portal](https://portal.azure.com/), wybierz ikonę `>_` i ustaw **PowerShell** w menu Cloud Shell. Wykonuj polecenia w jednej sesji, ponieważ kolejne kroki korzystają z ustawionych w niej zmiennych. Jeśli Cloud Shell nie ma jeszcze Twojej kopii repozytorium, sklonuj ją.

```powershell
git clone https://github.com/robert-cialowicz-ideispl/wsei-devops-lab-z26s.git
Set-Location wsei-devops-lab-z26s/lab7
```

## 2. Wdróż własny klaster z IaC

Wybierz **Bicep lub Terraform**. Obie ścieżki tworzą klaster w warstwie Free z dwoma węzłami systemowymi Linux. Domyślny `Standard_D2als_v6` ma 2 vCPU i 4 GiB RAM na węzeł. W kroku 6 autoscaler doda trzeci węzeł, więc na całe ćwiczenie potrzebujesz 6 wolnych vCPU w limicie regionalnym i 6 w limicie rodziny VM przed wdrożeniem. W `westeurope` konfiguracja z dwoma węzłami tego rozmiaru przeszła walidację dostawcy AKS i `what-if`.

Azure for Students oferuje bezpłatne godziny dla maszyn `Standard_B1s` i `Standard_B2ats_v2` z Lab 6. Pula systemowa AKS wyklucza serię B. Warstwa Free obejmuje zarządzanie klastrem. Maszyny `Standard_D2als_v6`, dyski i sieć są rozliczane osobno. [Oferta Azure for Students](https://azure.microsoft.com/free/students/) · [Wymagania puli systemowej AKS](https://learn.microsoft.com/azure/aks/use-system-pools)

Jeśli trzeba, najpierw zmień subskrypcję poleceniem `az account set --subscription IDENTYFIKATOR`. Sprawdź rejestrację dostawców. Jeśli któryś ma status inny niż `Registered`, użyj `az provider register --namespace NAZWA --wait` lub poproś o rejestrację właściciela subskrypcji.

```powershell
foreach ($provider in 'Microsoft.ContainerService', 'Microsoft.Compute', 'Microsoft.Network') {
    az provider show --namespace $provider --query '{provider:namespace,status:registrationState}' --output table
}
```

### Wybierz region dla swojej subskrypcji

W katalogu `lab7` wstaw swój numer albumu i uruchom [select-region.ps1](select-region.ps1). Skrypt używa Azure CLI oraz Bicepa dostępnego przez `az bicep`.

```powershell
$LabStudent = '123456'
$LabVmSize = 'Standard_D2als_v6'
$LabRg = "rg-lab7-$LabStudent"
$LabAks = "aks-lab7-$LabStudent"
$LabNamespace = "lab7-$LabStudent"
$env:ARM_SUBSCRIPTION_ID = az account show --query id --output tsv

$LabLocation = $null
$LabLocation = ./select-region.ps1 -ResourceGroupName $LabRg -ClusterName $LabAks -VmSize $LabVmSize
if ($LabLocation) { "Wybrany region: $LabLocation" }
```

Przejdź do kroku 2A lub 2B, gdy zobaczysz `Wybrany region`. Obie ścieżki korzystają ze zmiennej `$LabLocation` w bieżącej sesji PowerShell. Skrypt wyświetla postęp, a do zmiennej trafia nazwa regionu.

Bez dodatkowych argumentów skrypt sprawdza fizyczne regiony aktywnej subskrypcji, zaczynając od europejskich. Jeśli chcesz ograniczyć wybór, uruchom poniższy wariant z regionami w swojej kolejności preferencji.

```powershell
$LabLocation = $null
$LabLocation = ./select-region.ps1 -ResourceGroupName $LabRg -ClusterName $LabAks -VmSize $LabVmSize `
    -Regions polandcentral, westeurope, northeurope
if ($LabLocation) { "Wybrany region: $LabLocation" }
```

Jeśli grupa `$LabRg` już istnieje, skrypt bierze pod uwagę tylko jej region. Aby sprawdzić inną lokalizację, ustaw `$LabRg` na nazwę nowej grupy.

Skrypt sprawdza dostępność AKS i wybranego SKU oraz liczniki Compute i sieci z uwzględnieniem dodatkowego węzła z kroku 6. Następnie używa [preflight.bicep](preflight.bicep), aby w `what-if` na poziomie subskrypcji zweryfikować grupę i początkową konfigurację klastra z [main.bicep](main.bicep). Ten krok wykonuje odczyty i symulację wdrożenia. Skrypt zwraca pierwszy region, który przejdzie kontrole.

Jeśli skrypt nie wybierze regionu, sprawdź komunikaty Azure przed przejściem dalej. Możesz spróbować innej listy regionów lub rozmiaru VM. `What-if` pozwala wykryć blokady zasad dla grupy i klastra. Ograniczenia dotyczące zasobów tworzonych przez AKS oraz chwilowa dostępność maszyn mogą ujawnić się dopiero przy wdrożeniu. [Walidacja wstępna Azure](https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-preflight)

### 2A. Bicep

W [main.bicep](main.bicep) znajdź definicję AKS, tożsamość zarządzaną i konfigurację puli węzłów. Utwórz grupę w regionie `$LabLocation`. Klaster domyślnie dziedziczy region grupy. Sprawdź plan przed wdrożeniem.

```powershell
if (-not $LabLocation) { throw 'Najpierw wybierz region.' }
az group create --name $LabRg --location $LabLocation --output table &&
    az deployment group what-if --resource-group $LabRg --template-file main.bicep `
        --parameters "clusterName=$LabAks" "vmSize=$LabVmSize"
```

Gdy plan pokaże oczekiwane zmiany, wdróż klaster.

```powershell
az deployment group create --resource-group $LabRg --template-file main.bicep `
    --parameters "clusterName=$LabAks" "vmSize=$LabVmSize"
```

### 2B. Terraform

Przekaż wybrany region przez `$env:TF_VAR_location`. W [terraform/main.tf](terraform/main.tf) sprawdź, jak grupa zasobów i klaster korzystają z tej wartości. Zachowaj stan Terraform do sprzątania. Jeśli wrócisz do ćwiczenia w nowej sesji, użyj Cloud Shell ze [skonfigurowanym trwałym magazynem](https://learn.microsoft.com/azure/cloud-shell/persisting-shell-storage) i zapisz katalog roboczy w `~/clouddrive`. Przed `destroy` ponownie ustaw `ARM_SUBSCRIPTION_ID` i zmienne `TF_VAR_` w PowerShell, używając wartości z wdrożenia.

```powershell
if (-not $LabLocation) { throw 'Najpierw wybierz region.' }
$env:TF_VAR_resource_group_name = $LabRg
$env:TF_VAR_cluster_name = $LabAks
$env:TF_VAR_vm_size = $LabVmSize
$env:TF_VAR_location = $LabLocation

terraform -chdir=terraform init &&
    terraform -chdir=terraform plan -out=lab7.tfplan
```

Gdy plan pokaże oczekiwaną grupę i klaster w wybranym regionie, zastosuj zapisany plan.

```powershell
terraform -chdir=terraform apply lab7.tfplan
```

### Dostęp do własnego klastra

Klaster używa Microsoft Entra ID i Azure RBAC. Po wdrożeniu przypisz swojemu kontu rolę administratora Kubernetes w tym klastrze. Potrzebujesz prawa do przypisywania ról w Azure. Jeśli go nie masz, poproś właściciela subskrypcji o przypisanie roli do Twojego konta.

```powershell
$LabAksId = az aks show --resource-group $LabRg --name $LabAks --query id --output tsv
$LabUserId = az ad signed-in-user show --query id --output tsv
if (-not $LabAksId -or -not $LabUserId) { throw 'Sprawdź nazwę klastra i zalogowane konto.' }
az role assignment create --assignee-object-id $LabUserId --assignee-principal-type User `
    --role 'Azure Kubernetes Service RBAC Cluster Admin' --scope $LabAksId
```

## 3. Połącz się z klastrem

Użyj zmiennych ustawionych w kroku 2 i pobierz `kubeconfig` do osobnego katalogu tymczasowego.

```powershell
$LabSession = Join-Path ([IO.Path]::GetTempPath()) "lab7-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $LabSession | Out-Null
$env:KUBECONFIG = Join-Path $LabSession 'kubeconfig'

if (-not (Get-Command kubelogin -ErrorAction SilentlyContinue)) {
    az aks install-cli --install-location (Join-Path $LabSession 'kubectl') `
        --kubelogin-install-location (Join-Path $LabSession 'kubelogin')
    if ($LASTEXITCODE -ne 0) { throw 'Instalacja kubelogin nie powiodła się.' }
    $env:PATH = "$LabSession$([IO.Path]::PathSeparator)$env:PATH"
}

az aks get-credentials --resource-group $LabRg --name $LabAks --file $env:KUBECONFIG --format exec &&
    kubelogin convert-kubeconfig -l azurecli &&
    kubectl config current-context
```

Sprawdź, czy węzły mają status `Ready`, i utwórz namespace. Świeżo nadane uprawnienia mogą zacząć działać po kilku minutach.

```powershell
kubectl get nodes
kubectl create namespace $LabNamespace
```

Przed wdrożeniem sprawdź, czy poniższe polecenie zwraca `yes`.

```powershell
kubectl auth can-i create deployments --namespace $LabNamespace
```

## 4. Wdróż aplikację

Otwórz [simple-demo.yaml](simple-demo.yaml) i znajdź `Deployment` o nazwie `backend`. `spec.template` opisuje jeden pod, a `spec.replicas` określa liczbę podów tworzonych z tego szablonu. Porównaj etykietę `app: backend` w szablonie z `spec.selector.matchLabels` w Deploymencie i `spec.selector` w usłudze `backend`.

```powershell
kubectl -n $LabNamespace apply -f simple-demo.yaml
kubectl -n $LabNamespace rollout status deployment/backend --timeout=180s
kubectl -n $LabNamespace rollout status deployment/frontend --timeout=180s
kubectl -n $LabNamespace rollout status deployment/gateway --timeout=180s
kubectl -n $LabNamespace get 'deployments,pods,services'
```

Wszystkie trzy usługi mają typ `ClusterIP`. Brama przekazuje żądania `/api/` do backendu, a pozostały ruch do frontendu.

## 5. Sprawdź aplikację przez `port-forward`

W tej samej sesji Cloud Shell uruchom przekierowanie w tle. Sprawdź wynik `Receive-Job`. Gdy zobaczysz `Forwarding from 127.0.0.1:8081`, wyślij żądania. Jeśli wynik jest jeszcze pusty, ponów `Receive-Job`.

```powershell
$LabForwardJob = Start-Job -ScriptBlock {
    param($Namespace)
    kubectl -n $Namespace port-forward service/gateway 8081:80
} -ArgumentList $LabNamespace

Receive-Job -Job $LabForwardJob -Keep
```

Pierwsze żądanie powinno zwrócić HTML, drugie JSON z API. Adres `127.0.0.1` wskazuje tutaj sesję Cloud Shell.

```powershell
$LabFrontend = Invoke-WebRequest -Uri 'http://127.0.0.1:8081/' -TimeoutSec 15
$LabFrontend.StatusCode
$LabFrontend.Content
Invoke-RestMethod -Uri 'http://127.0.0.1:8081/api/headers' -TimeoutSec 15 | ConvertTo-Json -Depth 5
```

Jeśli test się nie powiedzie, sprawdź log przekierowania, log bramy oraz punkty końcowe usługi backendu.

```powershell
Receive-Job -Job $LabForwardJob -Keep
kubectl -n $LabNamespace logs deployment/gateway --tail=20
kubectl -n $LabNamespace get endpointslices -l 'kubernetes.io/service-name=backend'
```

## 6. Zmień liczbę replik i odtwórz pod

Skalując backend, sprawdzisz, co robi `Deployment`, gdy potrzebuje kolejnej repliki. Zaobserwujesz też, jak Cluster Autoscaler dodaje węzeł, gdy scheduler nie może rozmieścić nowego poda.

### Przejdź z dwóch do trzech replik

Sprawdź, czy w puli `system` są dwa gotowe węzły. Dla domyślnego `Standard_D2als_v6` trzeci węzeł wymaga jeszcze 2 wolnych vCPU w regionie i w rodzinie VM. Azure rozlicza dodatkową maszynę i jej dysk. [Cluster Autoscaler w AKS](https://learn.microsoft.com/azure/aks/cluster-autoscaler-overview)

```powershell
kubectl get nodes
az aks nodepool show --resource-group $LabRg --cluster-name $LabAks --name system `
    --query '{nodes:count,vmSize:vmSize,autoscaler:enableAutoScaling}' --output table
az vm list-usage --location $LabLocation --output table
```

Ustaw dwie repliki backendu i dodaj regułę `podAntiAffinity`. Wymaga ona, aby każdy nowy pod backendu trafił na węzeł bez innego poda z etykietą `app: backend` w tym namespace. Strategia `Recreate` usuwa poprzednie pody przed uruchomieniem nowych, więc przez chwilę API będzie niedostępne. [Reguły rozmieszczania podów](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#affinity-and-anti-affinity)

```powershell
$LabPatchPath = Join-Path $LabSession 'backend-scheduling.yaml'
@'
spec:
  replicas: 2
  strategy:
    type: Recreate
    rollingUpdate: null
  template:
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchLabels:
                  app: backend
              topologyKey: kubernetes.io/hostname
'@ | Set-Content -LiteralPath $LabPatchPath -Encoding utf8

kubectl -n $LabNamespace patch deployment/backend --type=merge --patch-file $LabPatchPath
kubectl -n $LabNamespace rollout status deployment/backend --timeout=180s
kubectl -n $LabNamespace get pods -l 'app=backend' -o wide
```

Sprawdź w kolumnie `NODE`, czy dwa gotowe pody działają na różnych węzłach. Włącz Cluster Autoscaler dla puli `system` z zakresem 2–3 węzły. [Włączanie Cluster Autoscalera](https://learn.microsoft.com/azure/aks/cluster-autoscaler#enable-or-disable-the-cluster-autoscaler-on-node-pools)

```powershell
az aks nodepool update --resource-group $LabRg --cluster-name $LabAks --name system `
    --enable-cluster-autoscaler --min-count 2 --max-count 3
```

Dodaj trzecią replikę. Poszukaj poda w stanie `Pending` bez przypisanego węzła w kolumnie `NODE`. Zakończ obserwację klawiszami `Ctrl+C`. W `kubectl -n $LabNamespace describe pod NAZWA_PODA` sprawdź zdarzenie `FailedScheduling` i powód związany z regułą rozmieszczania.

```powershell
kubectl -n $LabNamespace scale deployment/backend --replicas=3
kubectl -n $LabNamespace get pods -l 'app=backend' -o wide --watch
```

Autoscaler wykryje pod, którego scheduler nie może rozmieścić, i zleci dodanie węzła, jeśli Azure ma dostępną pojemność i limit. Po uzyskaniu stanu `Ready` przez nowy węzeł scheduler może umieścić na nim oczekujący pod. Operacja może potrwać kilka minut.

```powershell
kubectl -n $LabNamespace rollout status deployment/backend --timeout=15m
kubectl get nodes
kubectl -n $LabNamespace get pods -l 'app=backend' -o wide
```

Porównaj listy sprzed i po skalowaniu. Zapisz nazwę nowego węzła i pokaż pod, który na nim działa. Jeśli pod nadal czeka, sprawdź w `kubectl -n $LabNamespace describe pod NAZWA_PODA` zdarzenia schedulera i autoscalera. Następnie przejdź do odtworzenia poda.

### Odtwórz pod i ponów żądanie API

Wybierz jeden pod backendu z listy i podstaw jego nazwę. Obserwuj listę do chwili, gdy nowy pod będzie gotowy. Zakończ obserwację klawiszami `Ctrl+C` i ponów test API.

```powershell
kubectl -n $LabNamespace delete pod NAZWA_PODA
kubectl -n $LabNamespace get pods -l 'app=backend' --watch
```

```powershell
Invoke-RestMethod -Uri 'http://127.0.0.1:8081/api/headers' -TimeoutSec 15 | ConvertTo-Json -Depth 5
```

Zapisz odpowiedź API i wynik `get pods`. Backend ma wrócić do trzech gotowych replik. Wyjaśnij, co zrobił `Deployment` i dlaczego adres usługi pozostał ten sam. Sprawdź też, czy odtworzenie poda wymagało kolejnego węzła.

## 7. Posprzątaj

Zamknij zadanie PowerShell uruchomione do przekierowania, jeśli zostało utworzone.

```powershell
if ($LabForwardJob) {
    Stop-Job -Job $LabForwardJob
    Remove-Job -Job $LabForwardJob
    $LabForwardJob = $null
}
```

Wykonaj sprzątanie odpowiadające swojej ścieżce. Przed `az group delete` sprawdź nazwę grupy oraz aktywną subskrypcję.

| Ścieżka | Polecenie |
|---|---|
| Bicep | `az group delete --name $LabRg` |
| Terraform | `terraform -chdir=terraform destroy` |

Jeśli sesja tymczasowa usunęła stan Terraform, usuń grupę zasobów przygotowaną dla tego laboratorium poleceniem `az group delete --name $LabRg`. Sprawdź w portalu, czy pod tą nazwą jest wyłącznie grupa z Twoim klastrem Lab 7.
