param(
    [ValidateSet('all', 'catalog-service', 'inventory-service', 'order-service', 'payment-service', 'shipping-service')]
    [string]$Service = 'all',
    [string]$Namespace = 'default',
    [switch]$SkipRunningCheck
)

$ErrorActionPreference = 'Stop'

$seedServices = @(
    'catalog-service',
    'inventory-service',
    'order-service',
    'payment-service',
    'shipping-service'
)

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

Test-CommandExists kubectl

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $root
try {
    $servicesToSeed = if ($Service -eq 'all') { $seedServices } else { @($Service) }

    if (-not $SkipRunningCheck) {
        Write-Step "Checking deployment availability in namespace '$Namespace'"
        foreach ($svc in $servicesToSeed) {
            Invoke-CheckedCommand { kubectl get deployment $svc -n $Namespace > $null } "Deployment '$svc' not found in namespace '$Namespace'."
            Invoke-CheckedCommand { kubectl rollout status "deployment/$svc" -n $Namespace --timeout=180s } "Deployment '$svc' is not ready."
        }
    }

    Write-Step 'Running Kubernetes seed commands'
    foreach ($svc in $servicesToSeed) {
        Write-Host "Seeding $svc..." -ForegroundColor Yellow
        Invoke-CheckedCommand { kubectl exec -n $Namespace "deployment/$svc" -- npm run seed } "Seeding failed for $svc"
    }

    Write-Host "`nKubernetes seeding completed successfully." -ForegroundColor Green
    Write-Host 'Notification service is intentionally excluded (no seed dataset).' -ForegroundColor Green
}
finally {
    Pop-Location
}
