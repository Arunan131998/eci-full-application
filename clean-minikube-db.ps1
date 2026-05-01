param(
    [ValidateSet('all', 'catalog', 'inventory', 'order', 'payment', 'shipping', 'notification')]
    [string]$Service = 'all',
    [string]$Namespace = 'default',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$allServices = @('catalog', 'inventory', 'order', 'payment', 'shipping', 'notification')
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Step($message) {
    Write-Host "`n==> $message" -ForegroundColor Cyan
}

function Test-CommandExists($name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $name"
    }
}

function Invoke-CheckedCommand($scriptBlock, $errorMessage) {
    & $scriptBlock
    if ($LASTEXITCODE -ne 0) {
        throw $errorMessage
    }
}

function Wait-For-Delete($kind, $name, $namespace, $timeoutSeconds) {
    $elapsed = 0
    while ($elapsed -lt $timeoutSeconds) {
        $existingResource = kubectl get $kind $name -n $namespace --ignore-not-found -o name 2>$null
        if ([string]::IsNullOrWhiteSpace($existingResource)) {
            return
        }

        Start-Sleep -Seconds 2
        $elapsed += 2
    }

    throw "Timed out waiting for deletion of $kind/$name in namespace '$namespace'."
}

Test-CommandExists kubectl

$targets = if ($Service -eq 'all') { $allServices } else { @($Service) }

if (-not $Force) {
    $targetLabel = ($targets -join ', ')
    $confirmation = Read-Host "This will DELETE and RECREATE DB data for [$targetLabel] in namespace '$Namespace'. Type RESET to continue"
    if ($confirmation -ne 'RESET') {
        throw 'DB cleanup cancelled by user.'
    }
}

Push-Location $root
try {
    foreach ($svc in $targets) {
        $dbDeployment = "$svc-db"
        $dbPvc = "$svc-db-pvc"
        $dbManifestPath = Join-Path $root "$svc-service\k8s\$svc-db.yaml"

        if (-not (Test-Path $dbManifestPath)) {
            throw "DB manifest not found: $dbManifestPath"
        }

        Write-Step "Resetting database for $svc"

        kubectl delete deployment $dbDeployment -n $Namespace --ignore-not-found | Out-Null
        Wait-For-Delete -kind 'deployment' -name $dbDeployment -namespace $Namespace -timeoutSeconds 120

        kubectl delete pvc $dbPvc -n $Namespace --ignore-not-found | Out-Null
        Wait-For-Delete -kind 'pvc' -name $dbPvc -namespace $Namespace -timeoutSeconds 120

        Invoke-CheckedCommand { kubectl apply -f $dbManifestPath -n $Namespace } "Failed to apply DB manifest for $svc."
        Invoke-CheckedCommand { kubectl rollout status "deployment/$dbDeployment" -n $Namespace --timeout=180s } "Database rollout failed for $dbDeployment."
    }

    Write-Host "`nDatabase cleanup completed successfully." -ForegroundColor Green
    Write-Host 'Tip: run .\seed-minikube.ps1 to repopulate seed data.' -ForegroundColor Yellow
}
finally {
    Pop-Location
}
