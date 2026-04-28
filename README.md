# ECI - E-Commerce Microservices Platform

A complete 6-microservice e-commerce order management system with atomic transactions, distributed tracing, and event-driven notifications.

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌────────────────┐
│   Catalog   │     │  Inventory   │     │     Order      │
│  (3001)     │     │   (3002)     │     │    (3003)      │
└─────────────┘     └──────────────┘     └────────────────┘
       △                    △                    │
       │                    │                    │ Orchestrates
       └────────┬───────────┘                    │
                │                                │
         ┌──────▼──────────────┐                 │
         │  POST /pricing/     │                 │
         │  resolve &          │         ┌───────▼────────┐
         │  POST /reserve      │         │  POST /charge  │
         └─────────────────────┘         └────────────────┘
                                               │ (Payment)
                ┌────────────────────────────┬─┴──────────────┐
                │                            │                │
         ┌──────▼─────────┐          ┌─────▼─────────┐  ┌────▼──────┐
         │ Notification   │          │   Shipping    │  │  Payment  │
         │    (3006)      │          │    (3005)     │  │  (3004)   │
         └────────────────┘          └───────────────┘  └───────────┘
                △                            △
                │← Callbacks ─────────────────┼─────────────────┐
                │                            │                 │
                └────OrderConfirmed──────────┴─────────────────┘
                     OrderCancelled
                     PaymentCompleted
                     PaymentFailed
                     ShipmentShipped
                     ShipmentDelivered
```

**Services:**
- **Catalog** (3001): Product CRUD, pricing resolution
- **Inventory** (3002): Stock management, atomic reservation with TTL
- **Order** (3003): Orchestration engine (Reserve→Pay→Ship)
- **Payment** (3004): Charge & refund with idempotency
- **Shipping** (3005): Shipment lifecycle management
- **Notification** (3006): Email/SMS notifications, event intake

**Technology Stack:**
- Node.js 24.15.0, Express.js 4.19.2
- PostgreSQL 16 (one DB per service)
- Docker + Docker Compose
- Kubernetes (Minikube ready)
- OpenAPI 3.0 specs, Swagger UI
- Prometheus metrics, structured logging, correlation IDs

---

## Quick Start

### Prerequisites

Choose one of the three deployment options below.

---

## Option 1: Docker Compose (All Services)

**Requirements:**
- Docker and Docker Compose installed
- ~2 GB free disk space
- Ports 3001-3006 and 5431-5436 available

**Health Checks & Startup Sequencing:**
- All PostgreSQL databases have health checks that verify they're ready (`pg_isready`)
- Services start after their database is healthy
- Order service waits for other services to be running
- First startup takes ~30-60 seconds for all databases and services to initialize

**Steps:**

1. **Build and start all services**:
   ```bash
   cd FullApplication
   docker compose -f docker-compose.yml up --build -d
   ```

2. **Monitor startup progress** (~60-90 seconds for full readiness):
   ```bash
   # Watch Docker logs as services start
   docker compose -f docker-compose.yml logs -f
   
   # Or check health status
   docker compose -f docker-compose.yml ps
   ```

3. **Wait until all services are running** (check the `STATUS` column):
   ```
   NAME                    STATUS
   catalog-db              Up (healthy)
   catalog-service         Up
   inventory-db            Up (healthy)
   inventory-service       Up
   order-db                Up (healthy)
   order-service           Up (running)
   payment-db              Up (healthy)
   payment-service         Up
   shipping-db             Up (healthy)
   shipping-service        Up
   notification-db         Up (healthy)
   notification-service    Up
   ```
   ```bash
   curl http://localhost:3001/health
   curl http://localhost:3002/health
   curl http://localhost:3003/health
   curl http://localhost:3004/health
   curl http://localhost:3005/health
   curl http://localhost:3006/health
   ```
   Each should return: `{"status":"ok"}`

4. **Access services**:
   - Catalog API: http://localhost:3001/docs
   - Inventory API: http://localhost:3002/docs
   - Order API: http://localhost:3003/docs
   - Payment API: http://localhost:3004/docs
   - Shipping API: http://localhost:3005/docs
   - Notification API: http://localhost:3006/docs
   - Metrics: http://localhost:3001/metrics (catalog example)

## Manual Seeding

Run seeding only when needed, after services are up:

```powershell
# Seed all seed-enabled services (recommended)
.\seed-manual.ps1

# Seed one service
.\seed-manual.ps1 -Service catalog-service
```

```bash
# Seed one service manually
docker compose -f docker-compose.yml exec catalog-service npm run seed

# Seed all seed-enabled services manually (Bash)
for service in catalog inventory order payment shipping; do
   echo "Seeding $service-service..."
   docker compose -f docker-compose.yml exec "$service-service" npm run seed
done
```

```powershell
# Seed all seed-enabled services manually (PowerShell)
$services = "catalog","inventory","order","payment","shipping"
foreach ($s in $services) {
   Write-Output "Seeding $s-service..."
   docker compose -f docker-compose.yml exec "$s-service" npm run seed
}
```

5. **View logs**:
   ```bash
   # All logs
   docker compose -f docker-compose.yml logs -f
   
   # Specific service logs
   docker compose -f docker-compose.yml logs -f order-service
   ```

6. **Stop all services**:
   ```bash
   docker compose -f docker-compose.yml down
   ```

---

## Option 2: Running Individual Services

**Requirements:**
- Docker installed
- PostgreSQL running locally (or multiple instances)
- Ports 3001-3006 available

**Steps to run each service individually:**

```bash
# From each service directory (catalog-service, inventory-service, etc.)

# 1. Build image
docker build -t eci-<service>-service:latest .

# 2. Create network (once)
docker network create eci-net

# 3. Run service (see service README.md for environment variables)
docker run -d --name <service>-service --network eci-net \
  -e DATABASE_URL=postgres://user:password@<service>-db:5432/<service>_db \
  -e APP_PORT=<port> \
  -p <port>:<port> \
  eci-<service>-service:latest
```

Refer to each service's README.md for detailed Docker commands and environment variables.

---

## Option 3: Kubernetes (Minikube)

**Requirements:**
- Minikube installed and running: `minikube start`
- kubectl configured
- ~4 GB Minikube memory
- Docker/Podman available

### One-Command PowerShell Deployment

From the `FullApplication/` root directory, run:

```powershell
.\deploy-minikube.ps1
```

Useful variants:

```powershell
# Deploy but skip rebuilding Docker images
.\deploy-minikube.ps1 -SkipBuild

# Show cluster/service status
.\deploy-minikube.ps1 -Action Status

# Delete all deployed resources
.\deploy-minikube.ps1 -Action Cleanup
```

### Full Stack Deployment (All Services)

1. **Start Minikube**:
   ```bash
   minikube start --memory=4096 --cpus=2
   ```

2. **Build all images for Minikube**:
   ```bash
   eval $(minikube docker-env)
   
   # Build all 6 service images
   for service in catalog inventory order payment shipping notification; do
     cd $service-service
     docker build -t eci-${service}-service:latest .
     cd ..
   done
   ```

3. **Deploy to Kubernetes** (from FullApplication root):
   ```bash
   # Create ConfigMaps and Secrets for all services
   for service in catalog inventory order payment shipping notification; do
     kubectl apply -f $service-service/k8s/${service}-config.yaml
     kubectl apply -f $service-service/k8s/${service}-secret.yaml 2>/dev/null || true
   done
   
   # Deploy databases
   for service in catalog inventory order payment shipping notification; do
     kubectl apply -f $service-service/k8s/${service}-db.yaml
     echo "Waiting for ${service}-db..."
     kubectl rollout status statefulset/${service}-db --timeout=60s
   done
   
   # Deploy services
   for service in catalog inventory order payment shipping notification; do
     kubectl apply -f $service-service/k8s/${service}-service.yaml
     echo "Waiting for ${service}-service..."
     kubectl rollout status deployment/${service}-service --timeout=60s
   done
   ```

4. **Verify all pods are running**:
   ```bash
   kubectl get pods
   
   # Expected output (all should be Running):
   # NAME                                 READY   STATUS    RESTARTS
   # catalog-db-0                         1/1     Running   0
   # catalog-service-xxxxxxxxxx-xxxxx     1/1     Running   0
   # inventory-db-0                       1/1     Running   0
   # inventory-service-xxxxxxxxxx-xxxxx   1/1     Running   0
   # order-db-0                           1/1     Running   0
   # order-service-xxxxxxxxxx-xxxxx       1/1     Running   0
   # payment-db-0                         1/1     Running   0
   # payment-service-xxxxxxxxxx-xxxxx     1/1     Running   0
   # shipping-db-0                        1/1     Running   0
   # shipping-service-xxxxxxxxxx-xxxxx    1/1     Running   0
   # notification-db-0                    1/1     Running   0
   # notification-service-xxxxxxxxxx-x    1/1     Running   0
   ```

5. **Access services** (port-forward in separate terminals):
   ```bash
   # Terminal 1: Catalog
   kubectl port-forward svc/catalog-service 3001:3001
   
   # Terminal 2: Inventory
   kubectl port-forward svc/inventory-service 3002:3002
   
   # Terminal 3: Order
   kubectl port-forward svc/order-service 3003:3003
   
   # Terminal 4: Payment
   kubectl port-forward svc/payment-service 3004:3004
   
   # Terminal 5: Shipping
   kubectl port-forward svc/shipping-service 3005:3005
   
   # Terminal 6: Notification
   kubectl port-forward svc/notification-service 3006:3006
   ```

   Then access:
   - Catalog: http://localhost:3001/docs
   - Inventory: http://localhost:3002/docs
   - Order: http://localhost:3003/docs
   - Payment: http://localhost:3004/docs
   - Shipping: http://localhost:3005/docs
   - Notification: http://localhost:3006/docs

6. **View logs**:
   ```bash
   kubectl logs -l app=order-service -f
   kubectl logs -l app=catalog-service -f
   ```

7. **Cleanup**:
   ```bash
   # Delete all deployments and services
   for service in catalog inventory order payment shipping notification; do
     kubectl delete -f $service-service/k8s/${service}-service.yaml
     kubectl delete -f $service-service/k8s/${service}-db.yaml
     kubectl delete -f $service-service/k8s/${service}-config.yaml
   done
   
   # Stop Minikube
   minikube stop
   ```

---

## Docker Compose Health Checks & Startup Sequencing

The docker-compose configuration includes automated health checks to ensure services start in the correct order:

### Database Health Checks
- **Test**: `pg_isready -U postgres -d {database_name}`
- **Interval**: Every 5 seconds
- **Start Period**: 10 seconds (grace period before first check)
- **Retries**: 10 attempts before marking unhealthy
- **Timeout**: 5 seconds per check

### Application Readiness
- Application containers are started after their databases are healthy
- Validate readiness with `/health` endpoints before running manual seed commands

### Service Dependencies
- **Catalog, Inventory, Payment, Shipping, Notification**: Wait for their database to be healthy (`service_healthy`)
- **Order Service**: Waits for its database to be healthy AND all other services to be started (`service_started`)

### Why This Matters
On first startup, PostgreSQL needs time to:
1. Initialize the database directory
2. Start the server
3. Create tables from init.sql
4. Accept connections

Without database health checks, services would try to connect before PostgreSQL was ready.

### Monitoring Startup
```bash
# Watch detailed logs during startup
docker compose -f docker-compose.yml logs -f

# Check current health status
docker compose -f docker-compose.yml ps

# Check specific service health
docker inspect --format='{{.State.Health.Status}}' catalog-db
```

### Health Check (All Services)
```bash
for port in 3001 3002 3003 3004 3005 3006; do
  echo "Port $port: $(curl -s http://localhost:$port/health)"
done
```

### End-to-End Order Workflow

1. **Create Product** (Catalog):
   ```bash
   curl -X POST http://localhost:3001/v1/products \
     -H "Content-Type: application/json" \
     -d '{
       "sku": "SHOE-001",
       "name": "Running Shoe",
       "category": "footwear",
       "description": "Comfortable running shoe",
       "price": 99.99,
       "quantity": 100,
       "warehouse_id": "WH-01"
     }'
   ```

2. **Check Inventory**:
   ```bash
   curl http://localhost:3002/v1/inventory
   ```

3. **Place Order** (Order orchestrates Reserve→Pay→Ship):
   ```bash
   curl -X POST http://localhost:3003/v1/orders \
     -H "Content-Type: application/json" \
     -H "Idempotency-Key: order-123" \
     -d '{
       "customer_id": "CUST-001",
       "customer_email": "customer@example.com",
       "items": [
         {
           "product_id": "1",
           "sku": "SHOE-001",
           "quantity": 2,
           "unit_price": 99.99
         }
       ],
       "tax_amount": 20.00,
       "shipping_address": {
         "street": "123 Main St",
         "city": "New York",
         "state": "NY",
         "postal_code": "10001",
         "country": "USA"
       }
     }'
   ```

4. **Check Order Status**:
   ```bash
   # Replace {orderId} with response from order creation
   curl http://localhost:3003/v1/orders/{orderId}
   ```

5. **View Notifications**:
   ```bash
   curl http://localhost:3006/v1/notifications
   ```

### OpenAPI Documentation

Each service provides interactive API documentation at `/docs`:
- Catalog: http://localhost:3001/docs
- Inventory: http://localhost:3002/docs
- Order: http://localhost:3003/docs
- Payment: http://localhost:3004/docs
- Shipping: http://localhost:3005/docs
- Notification: http://localhost:3006/docs

### Metrics (Prometheus)

Access metrics at `/metrics` endpoint:
```bash
curl http://localhost:3001/metrics  # Catalog metrics
curl http://localhost:3002/metrics  # Inventory metrics
# etc…
```

---

## Individual Service Documentation

See each service's README.md for detailed information:

- [catalog-service/README.md](catalog-service/README.md)
- [inventory-service/README.md](inventory-service/README.md)
- [order-service/README.md](order-service/README.md)
- [payment-service/README.md](payment-service/README.md)
- [shipping-service/README.md](shipping-service/README.md)
- [notification-service/README.md](notification-service/README.md)

---

## API Specifications

OpenAPI 3.0 specifications are available in the `api-docs/` directory:

- `catalog.openapi.yaml` — Product management
- `inventory.openapi.yaml` — Stock management
- `order.openapi.yaml` — Order orchestration
- `payment.openapi.yaml` — Payment processing
- `shipping.openapi.yaml` — Shipment management
- `notification.openapi.yaml` — Notification dispatch

---

## Environment Configuration

Each service requires a `.env` file. Templates are provided:

```bash
# Catalog Service
POSTGRES_USER=user
POSTGRES_PASSWORD=password
DATABASE_URL=postgres://user:password@localhost:5431/catalog_db
APP_PORT=3001

# Inventory Service
DATABASE_URL=postgres://user:password@localhost:5432/inventory_db
APP_PORT=3002

# Order Service
DATABASE_URL=postgres://user:password@localhost:5433/order_db
APP_PORT=3003
CATALOG_BASE_URL=http://localhost:3001
INVENTORY_BASE_URL=http://localhost:3002
PAYMENT_BASE_URL=http://localhost:3004
SHIPPING_BASE_URL=http://localhost:3005
NOTIFICATION_BASE_URL=http://localhost:3006

# Payment Service
DATABASE_URL=postgres://user:password@localhost:5434/payment_db
APP_PORT=3004

# Shipping Service
DATABASE_URL=postgres://user:password@localhost:5435/shipping_db
APP_PORT=3005
ORDER_CALLBACK_URL=http://localhost:3003
NOTIFICATION_BASE_URL=http://localhost:3006

# Notification Service
DATABASE_URL=postgres://user:password@localhost:5436/notification_db
APP_PORT=3006
```

---

## Troubleshooting

### Services won't start
```bash
# Docker Compose: Check logs
docker compose -f docker-compose.yml logs

# Kubernetes: Check pod status
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### Port already in use
```bash
# Find process using port
lsof -i :3001  # replace with port number

# Kill process
kill -9 <PID>
```

### Database connection errors
```bash
# Ensure database is running
# For Docker Compose:
docker compose -f docker-compose.yml ps

# For Kubernetes:
kubectl get statefulsets
```

### Inter-service communication issues
```bash
# Verify service URLs in .env match your setup
# Docker Compose: Use service name as hostname (catalog-service, etc.)
# Kubernetes: Use service.namespace.svc.cluster.local (catalog-service.default.svc.cluster.local)
```

---

## Project Structure

```
FullApplication/
├── README.md (this file)
├── docker-compose.yml
├── api-docs/
│   ├── *.openapi.yaml (6 service specs)
│   └── *.md (architecture & workflows)
├── catalog-service/
│   ├── src/
│   ├── k8s/
│   ├── data/
│   └── README.md
├── inventory-service/
├── order-service/
├── payment-service/
├── shipping-service/
└── notification-service/
```

---

## Key Features

✅ **Atomic Transactions**: Reserve→Pay→Ship orchestrated in single Order.create() call
✅ **Idempotency**: All write endpoints support Idempotency-Key headers
✅ **TTL Reservations**: Stock reservations auto-release after 15 minutes
✅ **Distributed Tracing**: Correlation IDs propagate across service calls
✅ **Event-Driven Callbacks**: Shipment/Payment status updates trigger async notifications
✅ **Structured Logging**: Pino JSON logging with sensitive field redaction
✅ **Prometheus Metrics**: Performance tracking at /metrics
✅ **OpenAPI Documentation**: Interactive Swagger UI at /docs
✅ **DB-per-Service**: Complete data isolation via separate PostgreSQL instances
✅ **Kubernetes Ready**: StatefulSets, Services, ConfigMaps, PVCs per service

---

## License

Assignment_PS4 - Scalable Services (Mtech)
