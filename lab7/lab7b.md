# Laboratorium 7B – Kubernetes na współdzielonym AKS

Współprowadzący udostępni Ci klaster Azure Kubernetes Service (AKS) i przydzieli namespace. Wdrożysz w nim aplikację z frontendem, API i bramą HTTP. Sprawdzisz odpowiedzi aplikacji, zwiększysz liczbę replik backendu i zaobserwujesz odtworzenie usuniętego poda.

## 1. Przygotuj Cloud Shell

Otwórz [Azure Portal](https://portal.azure.com/), wybierz ikonę `>_` i ustaw **PowerShell** w menu Cloud Shell. Wykonuj polecenia w jednej sesji. Jeśli Cloud Shell nie ma kopii repozytorium, najpierw ją sklonuj. Następnie przejdź do katalogu `lab7`.

```powershell
git clone https://github.com/robert-cialowicz-ideispl/wsei-devops-lab-z26s.git
Set-Location wsei-devops-lab-z26s/lab7
```

## 2. Połącz się z klastrem

Uzupełnij identyfikator subskrypcji, grupę zasobów, nazwę klastra i namespace danymi od współprowadzącego.

```powershell
az account set --subscription 'IDENTYFIKATOR_SUBSKRYPCJI'
if ($LASTEXITCODE -ne 0) { throw 'Sprawdź dostęp do subskrypcji podanej przez współprowadzącego.' }
$LabRg = 'NAZWA_GRUPY'
$LabAks = 'NAZWA_KLASTRA'
$LabNamespace = 'PRZYDZIELONY_NAMESPACE'
```

Pobierz `kubeconfig` do osobnego katalogu tymczasowego i sprawdź nazwę kontekstu.

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

Współprowadzący utworzył namespace i nadał Ci dostęp. Przed wdrożeniem sprawdź, czy polecenie zwraca `yes`. Świeżo nadane uprawnienia mogą zacząć działać po kilku minutach.

```powershell
kubectl auth can-i create deployments --namespace $LabNamespace
```

## 3. Wdróż aplikację

Otwórz [simple-demo.yaml](simple-demo.yaml) i znajdź `Deployment` o nazwie `backend`. `spec.template` opisuje jeden pod, a `spec.replicas` określa liczbę podów tworzonych z tego szablonu. Porównaj etykietę `app: backend` w szablonie z `spec.selector.matchLabels` w Deploymencie i `spec.selector` w usłudze `backend`.

```powershell
kubectl -n $LabNamespace apply -f simple-demo.yaml
kubectl -n $LabNamespace rollout status deployment/backend --timeout=180s
kubectl -n $LabNamespace rollout status deployment/frontend --timeout=180s
kubectl -n $LabNamespace rollout status deployment/gateway --timeout=180s
kubectl -n $LabNamespace get 'deployments,pods,services'
```

Wszystkie trzy usługi mają typ `ClusterIP`. Brama przekazuje żądania `/api/` do backendu, a pozostały ruch do frontendu.

## 4. Sprawdź aplikację przez `port-forward`

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

## 5. Zmień liczbę replik i odtwórz pod

Zwiększ liczbę replik backendu z trzech do czterech w swoim namespace. Zapisz nazwy czterech gotowych podów.

```powershell
kubectl -n $LabNamespace scale deployment/backend --replicas=4
kubectl -n $LabNamespace rollout status deployment/backend --timeout=120s
kubectl -n $LabNamespace get pods -l 'app=backend'
```

Wybierz jeden pod backendu z listy i podstaw jego nazwę. Obserwuj listę do chwili, gdy nowy pod będzie gotowy. Zakończ obserwację klawiszami `Ctrl+C` i ponów test API.

```powershell
kubectl -n $LabNamespace delete pod NAZWA_PODA
kubectl -n $LabNamespace get pods -l 'app=backend' --watch
```

```powershell
Invoke-RestMethod -Uri 'http://127.0.0.1:8081/api/headers' -TimeoutSec 15 | ConvertTo-Json -Depth 5
```

Zapisz odpowiedź API oraz listę podów z nazwą nowej repliki. Backend ma wrócić do czterech gotowych replik. Wyjaśnij, co zrobił `Deployment` i dlaczego adres usługi pozostał ten sam. Przebieg dodawania węzła przez Cluster Autoscaler przedstawi współprowadzący na klastrze demonstracyjnym lub na wcześniej zebranych wynikach.

## 6. Posprzątaj

Zamknij zadanie PowerShell uruchomione do przekierowania. Usuń zasoby z `simple-demo.yaml` w przydzielonym namespace.

```powershell
if ($LabForwardJob) {
    Stop-Job -Job $LabForwardJob
    Remove-Job -Job $LabForwardJob
    $LabForwardJob = $null
}

kubectl -n $LabNamespace delete -f simple-demo.yaml
```

## Przygotowanie klastra dla współprowadzącego

Przygotuj jeden klaster ze ścieżki Bicep lub Terraform w [kroku 2 instrukcji Lab 7](lab7.md#2-wdróż-własny-klaster-z-iac). Połącz się z nim kontem administratora i sprawdź kontekst poleceniem `kubectl config current-context`.

Dla każdego studenta utwórz odrębny namespace. Przypisz rolę do pobrania `kubeconfig` na poziomie klastra AKS i rolę do wdrażania aplikacji w namespace tego studenta. Użyj identyfikatora obiektu użytkownika z tego samego tenanta Entra ID co subskrypcja klastra.

```powershell
$StudentNamespace = 'lab7-123456'
$StudentObjectId = 'IDENTYFIKATOR_OBIEKTU_ENTRA'
$LabAksId = az aks show --resource-group $LabRg --name $LabAks --query id --output tsv
if (-not $LabAksId) { throw 'Sprawdź grupę zasobów i nazwę klastra.' }
kubectl create namespace $StudentNamespace
kubectl label namespace $StudentNamespace 'pod-security.kubernetes.io/enforce=baseline'

az role assignment create --assignee-object-id $StudentObjectId --assignee-principal-type User `
    --role 'Azure Kubernetes Service Cluster User Role' --scope $LabAksId
az role assignment create --assignee-object-id $StudentObjectId --assignee-principal-type User `
    --role 'Azure Kubernetes Service RBAC Writer' --scope "$LabAksId/namespaces/$StudentNamespace"
```

Przekaż każdemu studentowi identyfikator subskrypcji, grupę zasobów, nazwę klastra i jego namespace. Po zakończeniu wszystkich ćwiczeń usuń klaster zgodnie z użytą ścieżką wdrożenia. [Sprzątanie w Lab 7](lab7.md#7-posprzątaj)
