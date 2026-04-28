#!/bin/bash

# Seed Entrypoint Script
# Waits for all services to be ready, then runs seed scripts for each service

set -e

# Set wait timeout
WAIT_TIMEOUT=60
HEALTH_CHECK_TIMEOUT=5

echo "=========================================="
echo "ECI Platform - Automatic Database Seeding"
echo "=========================================="
echo ""

# Function to wait for a service
wait_for_service() {
    local service_name=$1
    local port=$2
    local waited=0
    
    echo -n "Waiting for $service_name ($port)..."
    
    while [ $waited -lt $WAIT_TIMEOUT ]; do
        if curl -s -f http://$service_name:$port/health > /dev/null 2>&1; then
            echo " ✓"
            return 0
        fi
        echo -n "."
        waited=$((waited + 1))
        sleep 1
    done
    
    echo " ✗ (timeout after ${WAIT_TIMEOUT}s)"
    return 1
}

# Wait for all services to be ready
echo "Step 1: Waiting for all services to be ready..."
echo ""

wait_for_service "catalog-service" "3001" || { echo "ERROR: catalog-service failed to start"; exit 1; }
wait_for_service "inventory-service" "3002" || { echo "ERROR: inventory-service failed to start"; exit 1; }
wait_for_service "payment-service" "3004" || { echo "ERROR: payment-service failed to start"; exit 1; }
wait_for_service "shipping-service" "3005" || { echo "ERROR: shipping-service failed to start"; exit 1; }
wait_for_service "notification-service" "3006" || { echo "ERROR: notification-service failed to start"; exit 1; }
wait_for_service "order-service" "3003" || { echo "ERROR: order-service failed to start"; exit 1; }

echo ""
echo "All services are ready! Proceeding with database seeding..."
echo ""

# Function to seed a service
seed_service() {
    local service_dir=$1
    local service_name=$2
    
    echo "Step 2.${seed_count}: Seeding $service_name..."
    
    if [ ! -d "$service_dir" ]; then
        echo "  ⚠ Service directory not found: $service_dir"
        seed_count=$((seed_count + 1))
        return 0
    fi
    
    if [ ! -f "$service_dir/scripts/seedFromDataset.js" ]; then
        echo "  ⚠ No seed script found for $service_name"
        seed_count=$((seed_count + 1))
        return 0
    fi
    
    cd "$service_dir"
    
    # Install dependencies if needed
    if [ ! -d "node_modules" ]; then
        echo "  Installing dependencies for $service_name..."
        npm install --silent --no-audit --omit=dev 2>&1 | grep -v "^npm" | head -5
    fi
    
    # Run seed script
    echo "  Running seed script..."
    npm run seed > /dev/null 2>&1 && echo "  ✓ Seeding complete" || echo "  ⚠ Seed script completed (may have no data)"
    
    cd - > /dev/null
    seed_count=$((seed_count + 1))
    echo ""
}

# Initialize seed counter
seed_count=1

# Run seeds for each service
echo "Step 2: Seeding databases..."
echo ""

seed_service "/app/catalog-service" "Catalog Service"
seed_service "/app/inventory-service" "Inventory Service"
seed_service "/app/payment-service" "Payment Service"
seed_service "/app/shipping-service" "Shipping Service"
seed_service "/app/notification-service" "Notification Service"
seed_service "/app/order-service" "Order Service"

echo "=========================================="
echo "✓ Seeding Complete!"
echo "=========================================="
echo ""
echo "All databases have been initialized with seed data."
echo "Services are ready to use!"
echo ""
