# ECI Application Documentation

## 1. Overview
ECI is a microservices-based e-commerce platform implementing order orchestration with strict database-per-service design.

Core flow: **Reserve → Pay → Ship**.

Services:
- Catalog Service (`3001`)
- Inventory Service (`3002`)
- Order Service (`3003`)
- Payment Service (`3004`)
- Shipping Service (`3005`)
- Notification Service (`3006`)

---

## 2. Architecture
- Style: Microservices, API-driven communication, loose coupling.
- Data model: Separate PostgreSQL database per service (no cross-database joins).
- API standard:
  - Versioned endpoints (`/v1`)
  - OpenAPI 3.0 contracts
  - Standard error payload (`code`, `message`, `correlationId`)
  - Pagination/filtering for list APIs
- Observability:
  - Structured JSON logs
  - Correlation ID propagation (`x-correlation-id`)
  - Prometheus-compatible `/metrics`

---

## 3. Service Responsibilities
### Catalog Service
- Product CRUD and search/filter.
- Authoritative pricing lookup for orders.

### Inventory Service
- Tracks `on_hand`, `reserved`, and warehouse-level availability.
- Reserve/release/ship operations with inventory movement logs (`RESERVE`, `RELEASE`, `SHIP`).
- Reservation TTL + reaper for expiry cleanup.

### Order Service
- Creates and cancels orders.
- Computes totals (including tax and shipping) using banker’s rounding.
- Stores totals signature to protect pricing integrity.
- Orchestrates Reserve→Pay→Ship.

### Payment Service
- Idempotent charge and refund APIs.
- Emits order callback events for charge/refund outcomes.
- Emits notification events for payment outcomes.

### Shipping Service
- Creates shipments and tracks lifecycle:
  - `PENDING → SHIPPED → DELIVERED`
  - or `CANCELLED`
- Sends shipment callbacks to Order service.
- Sends shipment notification events.

### Notification Service
- Logs notifications/events for Order/Payment/Shipping.
- Supports direct notification logging and event intake endpoint.

---

## 4. Database-per-Service Mapping
- Catalog DB → products
- Inventory DB → inventory, reservations, reserve_idempotency, inventory_movements
- Order DB → orders, order_items, order_idempotency
- Payment DB → payments
- Shipping DB → shipments
- Notification DB → notifications_log

---

## 5. Business Workflows
## 5.1 Place Order (Reserve → Pay → Ship)
1. Client calls `POST /v1/orders` with `Idempotency-Key`.
2. Order fetches authoritative pricing from Catalog.
3. Order requests stock reservation in Inventory.
4. If fully reserved, Order charges via Payment.
5. If payment succeeds, Order creates shipment via Shipping.
6. Order persists final state and emits order confirmation notification event.

Failure handling:
- Reservation failure → order cancelled as stock unavailable.
- Payment failure → reservation released + payment failed notification.

## 5.2 Fulfillment (Pack/Ship/Deliver equivalent)
- Shipping status update API marks shipment `SHIPPED`/`DELIVERED`/`CANCELLED`.
- Shipping callback updates Order status.
- On `SHIPPED`, Order now triggers Inventory `POST /v1/inventory/ship` to convert reserved stock to shipped stock movement.
- On `CANCELLED`, Order triggers inventory release.

## 5.3 Refund and Cancellation
- Payment refund API is idempotent (`POST /v1/payments/{paymentId}/refund`).
- Payment sends callback to Order with `REFUNDED` status.
- Order cancellation flow triggers:
  - refund (if paid),
  - inventory release,
  - order status update to `CANCELLED`.

---

## 6. Notification Events Logged
From Order service:
- `ORDER_CONFIRMED`
- `ORDER_CANCELLED`
- `PAYMENT_FAILED`

From Payment service:
- `PAYMENT_COMPLETED`
- `PAYMENT_FAILED`
- `PAYMENT_REFUNDED`

From Shipping service:
- `SHIPMENT_SHIPPED`
- `SHIPMENT_DELIVERED`
- `SHIPMENT_CANCELLED`

---

## 7. Idempotency and Reliability
Idempotency is implemented on critical write operations:
- Order create
- Inventory reserve
- Payment charge
- Payment refund
- Shipping create

This prevents duplicate effects under retries/timeouts.

---

## 8. Deployment
## 8.1 Docker Compose
Run all services locally:
- `docker compose -f docker-compose.yml up --build -d`

## 8.2 Minikube/Kubernetes
Automated scripts at root:
- `deploy-minikube.ps1`
- `seed-minikube.ps1`
- `clean-minikube-db.ps1`
- `reset-demo-data.ps1`

K8s manifests include:
- Deployments with readiness/liveness probes
- Services (NodePort)
- ConfigMaps/Secrets
- PersistentVolumeClaims for DB storage

---

## 9. Monitoring and Logging
Metrics implemented:
- `orders_placed_total`
- `payments_failed_total`
- `inventory_reserve_latency_ms`
- `stockouts_total`

Logging:
- Structured JSON logs
- Sensitive-field redaction (email/phone/address patterns)
- Correlation IDs propagated across services

---

## 10. API and Demo Assets
- OpenAPI specs: `api-docs/*.openapi.yaml`
- Main demo collection: `postman/eci-assignment-demo.postman_collection.json`

Demo collection includes:
- Health checks
- Place-order orchestration
- Shipment lifecycle transitions
- Inventory SHIP movement verification
- Refund and REFUNDED status verification
- Payment/notification event verification
- Metrics checks

---

## 11. Current Implementation Notes
- Core assignment workflows are implemented and demonstrable.
- Notification behavior is event-log based (not real SMTP/SMS delivery).
- Shipment state model uses practical lifecycle (`PENDING`, `SHIPPED`, `DELIVERED`, `CANCELLED`).

---

## 12. Repository Structure
- `catalog-service/`
- `inventory-service/`
- `order-service/`
- `payment-service/`
- `shipping-service/`
- `notification-service/`
- `api-docs/`
- `postman/`
- root deployment/reset scripts

---

## 13. Quick Commands
- Local full run: `docker compose -f docker-compose.yml up --build -d`
- Minikube deploy: `./deploy-minikube.ps1`
- Minikube seed: `./seed-minikube.ps1`
- Reset demo transactional data: `./reset-demo-data.ps1`
