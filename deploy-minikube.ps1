param(
    [ValidateSet('Deploy', 'Status', 'Cleanup')]
    [string]$Action = 'Deploy',
    [switch]$SkipMinikubeStart,
    [switch]$SkipBuild,
    [int]$Memory = 4096,
    [int]$Cpus = 2
)

$ErrorActionPreference = 'Stop'

$services = @('catalog', 'inventory', 'order', 'payment', 'shipping', 'notification')
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

function Start-MinikubeIfNeeded {
    $statusOutput = ''
    try {
        $statusOutput = minikube status --format '{{.Host}}|{{.Kubelet}}|{{.APIServer}}' 2>$null
    } catch {
        $statusOutput = ''
    }

    if ($statusOutput -match 'Running\|Running\|Running') {
        Write-Host 'Minikube is already running.' -ForegroundColor Green
        return
    }

    Write-Step "Starting Minikube (memory=${Memory}MB, cpus=${Cpus})"
    Invoke-CheckedCommand { minikube start --memory=$Memory --cpus=$Cpus } 'Failed to start Minikube.'
}

function Use-MinikubeDocker {
    Write-Step 'Configuring shell to use Minikube Docker daemon'
    $envScript = minikube -p minikube docker-env --shell powershell | Out-String
    if (-not $envScript) {
        throw 'Failed to get Minikube Docker environment.'
    }
    Invoke-Expression $envScript
}

function Build-Images {
    Write-Step 'Building service images inside Minikube'
    foreach ($service in $services) {
        $serviceDir = Join-Path $root "$service-service"
        Push-Location $serviceDir
        try {
            Write-Host "Building eci-$service-service:latest"
            Invoke-CheckedCommand { docker build -t "eci-$service-service:latest" . } "Failed to build image for $service-service."
        }
        finally {
            Pop-Location
        }
    }
}

function Apply-Config {
    Write-Step 'Applying ConfigMaps'
    foreach ($service in $services) {
        $configPath = Join-Path $root "$service-service\k8s\$service-config.yaml"
        Invoke-CheckedCommand { kubectl apply -f $configPath } "Failed to apply config for $service-service."
    }
}

function Apply-Databases {
    Write-Step 'Deploying databases'
    foreach ($service in $services) {
        $dbPath = Join-Path $root "$service-service\k8s\$service-db.yaml"
        Invoke-CheckedCommand { kubectl apply -f $dbPath } "Failed to apply DB manifest for $service-service."
        Invoke-CheckedCommand { kubectl rollout status "deployment/$service-db" --timeout=180s } "Database rollout failed for $service-db."
    }
}

function Apply-Services {
    Write-Step 'Deploying application services'
    foreach ($service in $services) {
        $svcPath = Join-Path $root "$service-service\k8s\$service-service.yaml"
        Invoke-CheckedCommand { kubectl apply -f $svcPath } "Failed to apply service manifest for $service-service."
        Invoke-CheckedCommand { kubectl rollout status "deployment/$service-service" --timeout=180s } "Deployment rollout failed for $service-service."
    }
}

function Show-Status {
    Write-Step 'Current Kubernetes status'
    kubectl get pods
    Write-Host ''
    kubectl get svc
    Write-Host ''
    Write-Host 'Swagger URLs after port-forward:' -ForegroundColor Yellow
    Write-Host '  catalog:      http://localhost:3001/docs'
    Write-Host '  inventory:    http://localhost:3002/docs'
    Write-Host '  order:        http://localhost:3003/docs'
    Write-Host '  payment:      http://localhost:3004/docs'
    Write-Host '  shipping:     http://localhost:3005/docs'
    Write-Host '  notification: http://localhost:3006/docs'
    Write-Host ''
    Write-Host 'Port-forward commands:' -ForegroundColor Yellow
    foreach ($service in $services) {
        $port = switch ($service) {
            'catalog' { 3001 }
            'inventory' { 3002 }
            'order' { 3003 }
            'payment' { 3004 }
            'shipping' { 3005 }
            'notification' { 3006 }
        }
        Write-Host "  kubectl port-forward svc/$service-service ${port}:${port}"
    }
}

function Cleanup-Resources {
    Write-Step 'Deleting Kubernetes resources'
    foreach ($service in $services) {
        $svcPath = Join-Path $root "$service-service\k8s\$service-service.yaml"
        $dbPath = Join-Path $root "$service-service\k8s\$service-db.yaml"
        $configPath = Join-Path $root "$service-service\k8s\$service-config.yaml"

        kubectl delete -f $svcPath --ignore-not-found
        kubectl delete -f $dbPath --ignore-not-found
        kubectl delete -f $configPath --ignore-not-found
    }

    Write-Host 'Cleanup complete.' -ForegroundColor Green
}

Push-Location $root
try {
    Test-CommandExists minikube
    Test-CommandExists kubectl
    if ($Action -eq 'Deploy' -and -not $SkipBuild) {
        Test-CommandExists docker
    }

    switch ($Action) {
        'Deploy' {
            if (-not $SkipMinikubeStart) {
                Start-MinikubeIfNeeded
            }
            Use-MinikubeDocker
            if (-not $SkipBuild) {
                Build-Images
            }
            Apply-Config
            Apply-Databases
            Apply-Services
            Show-Status
            Write-Host ''
            Write-Host 'Deployment complete.' -ForegroundColor Green
            Write-Host 'Note: notification-service is not seeded by design.' -ForegroundColor Yellow
        }
        'Status' {
            Show-Status
        }
        'Cleanup' {
            Cleanup-Resources
        }
    }
}
finally {
    Pop-Location
}
