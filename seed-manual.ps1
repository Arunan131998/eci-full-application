param(
    [ValidateSet('all', 'catalog-service', 'inventory-service', 'order-service', 'payment-service', 'shipping-service')]
    [string]$Service = 'all',
    [string]$ComposeFile = 'docker-compose.yml',
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

function Invoke-CheckedCommand($scriptBlock, $errorMessage) {
    & $scriptBlock
    if ($LASTEXITCODE -ne 0) {
        throw $errorMessage
    }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker CLI not found. Please install Docker Desktop or ensure docker is in PATH.'
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $root
try {
    if (-not (Test-Path $ComposeFile)) {
        throw "Compose file not found: $ComposeFile"
    }

    $servicesToSeed = if ($Service -eq 'all') { $seedServices } else { @($Service) }

    if (-not $SkipRunningCheck) {
        Write-Step 'Checking running compose services'
        $runningServices = docker compose -f $ComposeFile ps --services --status running
        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to query running services. Ensure docker compose is available and stack is up.'
        }

        foreach ($svc in $servicesToSeed) {
            if ($runningServices -notcontains $svc) {
                throw "Service '$svc' is not running. Start stack first: docker compose -f $ComposeFile up -d"
            }
        }
    }

    Write-Step 'Running manual seed commands'
    foreach ($svc in $servicesToSeed) {
        Write-Host "Seeding $svc..." -ForegroundColor Yellow
        Invoke-CheckedCommand { docker compose -f $ComposeFile exec -T $svc npm run seed } "Seeding failed for $svc"
    }

    Write-Host "`nManual seeding completed successfully." -ForegroundColor Green
    Write-Host 'Notification service is intentionally excluded (no seed dataset).' -ForegroundColor Green
}
finally {
    Pop-Location
}
