param(
    [string]$Namespace = 'default'
)

$ErrorActionPreference = 'Stop'

function Write-Step($message) {
    Write-Host "`n==> $message" -ForegroundColor Cyan
}

function Test-CommandExists($name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $name"
    }
}

Test-CommandExists kubectl

Write-Step "Resetting demo data for order, payment, and shipping services"

# Reset order service data
Write-Step "Clearing order service data..."
$prevErrorAction = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'
kubectl exec deploy/order-db -n $Namespace -- psql -U postgres -d order_db -c "
  TRUNCATE TABLE order_items CASCADE;
  TRUNCATE TABLE orders CASCADE;
  TRUNCATE TABLE order_idempotency CASCADE;
  ALTER SEQUENCE orders_order_id_seq RESTART WITH 1;
" 2>&1 | Where-Object { $_ -notmatch 'NOTICE' } | Out-Null
$ErrorActionPreference = $prevErrorAction

if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Cleared orders, order_items, order_idempotency" -ForegroundColor Green
}

# Reset payment service data
Write-Step "Clearing payment service data..."
$prevErrorAction = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'
kubectl exec deploy/payment-db -n $Namespace -- psql -U postgres -d payment_db -c "
  TRUNCATE TABLE payments CASCADE;
  ALTER SEQUENCE payments_charge_id_seq RESTART WITH 1;
" 2>&1 | Where-Object { $_ -notmatch 'NOTICE' } | Out-Null
$ErrorActionPreference = $prevErrorAction

if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Cleared payments" -ForegroundColor Green
}

# Reset shipping service data
Write-Step "Clearing shipping service data..."
$prevErrorAction = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'
kubectl exec deploy/shipping-db -n $Namespace -- psql -U postgres -d shipping_db -c "
  TRUNCATE TABLE shipments CASCADE;
  ALTER SEQUENCE shipments_shipment_id_seq RESTART WITH 1;
" 2>&1 | Where-Object { $_ -notmatch 'NOTICE' } | Out-Null
$ErrorActionPreference = $prevErrorAction

if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Cleared shipments" -ForegroundColor Green
}

# Release all inventory reservations
Write-Step "Releasing all inventory reservations..."
$prevErrorAction = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'
kubectl exec deploy/inventory-db -n $Namespace -- psql -U postgres -d inventory_db -c "
  UPDATE inventory SET reserved = 0 WHERE reserved > 0;
  TRUNCATE TABLE inventory_movements CASCADE;
  TRUNCATE TABLE reservations CASCADE;
  ALTER SEQUENCE reservations_reservation_id_seq RESTART WITH 1;
  ALTER SEQUENCE inventory_movements_movement_id_seq RESTART WITH 1;
" 2>&1 | Where-Object { $_ -notmatch 'NOTICE' } | Out-Null
$ErrorActionPreference = $prevErrorAction

if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Released all reservations and cleared inventory movements" -ForegroundColor Green
}

Write-Step "Demo data reset complete! You can now re-run the Postman collection."
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "1. Open Postman and import postman/eci-assignment-demo.postman_collection.json"
Write-Host "2. Run the requests in sequence (1-20)"
Write-Host "3. Run this script again to reset for another demo run"
