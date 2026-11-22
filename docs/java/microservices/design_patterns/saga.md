# Saga

## 1. The problem Saga solves

In a monolith, `@Transactional` gives you ACID across everything. In microservices with **database-per-service**, one business operation (e.g. "place order") touches several databases:

```
Order DB  →  Payment DB  →  Inventory DB  →  Shipping DB
```

You can't wrap these in one local transaction. **Two-Phase Commit (2PC/XA)** is the classic answer, but it fails in practice:

- It holds locks across services, so throughput and availability suffer.
- The coordinator is a single point of failure.
- Kafka, MongoDB, most cloud services, and REST calls don't support XA.
- It couples services at runtime (CAP: you're choosing consistency over availability).

**Saga** trades atomicity for availability. It gives you _eventual consistency_ through a sequence of local transactions plus compensating actions.

## 2. Definition

> A saga is a sequence of **local transactions**. Each one commits to its own database and triggers the next step. If a step fails, the saga runs **compensating transactions** to semantically undo the earlier steps.

```
T1 → T2 → T3 → T4          (happy path)
T1 → T2 → T3(fails) → C2 → C1   (rollback by compensation)
```

Key point: a compensation is **not a rollback**. T1 has already committed and may have been visible to others. C1 is a _new_ business transaction (e.g. `cancelOrder`, `refundPayment`), not a database undo.

## 3. The two coordination styles

### A. Choreography (event-driven, no central brain)

Each service listens for events, does its work, and publishes the next event.

```
OrderService ──OrderCreated──▶ PaymentService ──PaymentCompleted──▶ InventoryService
     ▲                              │                                     │
     │◀────────PaymentFailed────────┘                                     │
     │◀────────────────────InventoryFailed (→ PaymentService refunds)─────┘
```

**Pros**

- Loose coupling, no single point of failure
- Simple for 2-3 participants
- Natural fit with Kafka

**Cons**

- The flow is implicit and scattered across services, so it is hard to see and debug
- Risk of cyclic dependencies between services
- Hard to answer "what state is order #123's saga in?"
- Gets messy beyond about 4 steps

### B. Orchestration (central coordinator)

A dedicated orchestrator tells each participant what to do via commands and reacts to replies.

```
              ┌──────────────────────┐
              │  Order Saga          │
              │  Orchestrator        │
              └─┬─────┬──────┬───────┘
     command    │     │      │    command
       ┌────────▼┐ ┌──▼─────┐ ┌▼─────────┐
       │ Payment │ │Inventory│ │ Shipping │
       └─────────┘ └────────┘ └──────────┘
```

**Pros**

- The flow lives in one place, so it is readable and testable
- Explicit saga state, easy monitoring and audit
- Participants don't know about each other
- Handles complex flows (branching, timeouts, parallel steps)

**Cons**

- The orchestrator is extra infrastructure and logic to build and keep available
- Risk of putting business logic in the orchestrator ("god service")

**Rule of thumb:** choreography for simple flows with few participants, orchestration for anything with 4+ steps, branching, or compliance and audit needs.

## 4. Running example: Order Saga

| Step | Service   | Local transaction      | Compensation           |
| ---- | --------- | ---------------------- | ---------------------- |
| 1    | Order     | Create order `PENDING` | Mark order `CANCELLED` |
| 2    | Payment   | Reserve/charge payment | Refund payment         |
| 3    | Inventory | Reserve stock          | Release stock          |
| 4    | Shipping  | Schedule shipment      | Cancel shipment        |
| 5    | Order     | Mark order `CONFIRMED` | n/a                    |

## 5. Choreography implementation (Spring Boot + Kafka)

**Events (immutable records):**

```java
public record OrderCreated(UUID eventId, UUID orderId, UUID customerId, BigDecimal amount) {}
public record PaymentCompleted(UUID eventId, UUID orderId) {}
public record PaymentFailed(UUID eventId, UUID orderId, String reason) {}
public record StockReservationFailed(UUID eventId, UUID orderId, String reason) {}
```

**Order Service: create order and publish the event atomically:**

```java
@Service
@RequiredArgsConstructor
public class OrderService {
    private final OrderRepository orders;
    private final OutboxRepository outbox;
    private final ObjectMapper mapper;

    @Transactional
    public UUID placeOrder(PlaceOrderRequest req) {
        Order order = orders.save(Order.pending(req));
        outbox.save(OutboxEvent.of(
            "order-events", order.getId().toString(),
            mapper.writeValueAsString(new OrderCreated(
                UUID.randomUUID(), order.getId(), req.customerId(), req.amount()))));
        return order.getId();
    }
}
```

Writing to an **outbox table in the same transaction** (see section 8) avoids the dual-write problem.

**Payment Service: consume, act, publish the next event:**

```java
@Component
@RequiredArgsConstructor
public class PaymentSagaListener {
    private final PaymentService paymentService;
    private final ProcessedEventRepository processed;

    @KafkaListener(topics = "order-events", groupId = "payment-service")
    @Transactional
    public void onOrderCreated(OrderCreated event) {
        if (processed.existsById(event.eventId())) return;   // idempotency
        processed.save(new ProcessedEvent(event.eventId()));

        try {
            paymentService.charge(event.orderId(), event.customerId(), event.amount());
            outbox.publish("payment-events", new PaymentCompleted(UUID.randomUUID(), event.orderId()));
        } catch (InsufficientFundsException ex) {
            outbox.publish("payment-events", new PaymentFailed(UUID.randomUUID(), event.orderId(), ex.getMessage()));
        }
    }
}
```

**Order Service: compensation on failure:**

```java
@KafkaListener(topics = {"payment-events", "inventory-events"}, groupId = "order-service")
@Transactional
public void onFailure(Object event) {
    if (event instanceof PaymentFailed f)            orders.cancel(f.orderId(), f.reason());
    if (event instanceof StockReservationFailed f)   orders.cancel(f.orderId(), f.reason());
}
```

The Payment Service also listens to `StockReservationFailed` to refund.

## 6. Orchestration implementation

The orchestrator persists **saga state**, so it survives restarts.

```java
@Entity
public class OrderSaga {
    @Id private UUID sagaId;
    private UUID orderId;
    @Enumerated(EnumType.STRING) private SagaState state;  // STARTED, PAYMENT_PENDING, INVENTORY_PENDING,
                                                            // COMPLETED, COMPENSATING, FAILED
    private String failureReason;
    @Version private Long version;                          // optimistic locking
    private Instant updatedAt;
}
```

```java
@Component
@RequiredArgsConstructor
public class OrderSagaOrchestrator {
    private final OrderSagaRepository sagas;
    private final CommandPublisher commands;   // writes to outbox → Kafka

    @Transactional
    public void start(UUID orderId, BigDecimal amount) {
        OrderSaga saga = sagas.save(OrderSaga.start(orderId));
        saga.moveTo(SagaState.PAYMENT_PENDING);
        commands.send("payment-commands", new ChargePayment(saga.getSagaId(), orderId, amount));
    }

    @KafkaListener(topics = "saga-replies", groupId = "order-saga")
    @Transactional
    public void onReply(SagaReply reply) {
        OrderSaga saga = sagas.findById(reply.sagaId()).orElseThrow();

        switch (saga.getState()) {
            case PAYMENT_PENDING -> {
                if (reply.success()) {
                    saga.moveTo(SagaState.INVENTORY_PENDING);
                    commands.send("inventory-commands", new ReserveStock(saga.getSagaId(), saga.getOrderId()));
                } else fail(saga, reply.reason());
            }
            case INVENTORY_PENDING -> {
                if (reply.success()) complete(saga);
                else {
                    saga.moveTo(SagaState.COMPENSATING);
                    commands.send("payment-commands", new RefundPayment(saga.getSagaId(), saga.getOrderId()));
                }
            }
            case COMPENSATING -> fail(saga, "Compensated: " + saga.getFailureReason());
        }
    }
}
```

For complex flows, model this with **Spring State Machine**, or use a workflow engine (section 9) instead of hand-rolling the switch.

## 7. Types of saga transactions

Understanding this separates a good design from a naive one:

- **Compensable transactions**: can be undone (create order, reserve stock).
- **Pivot transaction**: the point of no return. If it succeeds, the saga runs to completion. It is often the step that cannot be compensated (e.g. charging a card through a gateway that doesn't allow reversals, or sending an email).
- **Retriable transactions**: come after the pivot and _must eventually succeed_, so you retry them indefinitely (idempotent). Examples: update the loyalty balance, send the notification.

Design tip: order steps so the **risky, hard-to-compensate steps come late**, and the easily compensable ones come first.

## 8. The hard problems

### 8.1 Atomic "update DB + publish event" (dual write)

If you save to the DB and then call `kafkaTemplate.send()`, a crash between the two leaves the system inconsistent.

**Solution: Transactional Outbox**

1. In the same local transaction, write the business data and an `outbox` row.
2. A separate relay publishes outbox rows to Kafka, either by polling (`@Scheduled`) or via **CDC with Debezium** (preferred at scale).
3. This gives _at-least-once_ delivery.

### 8.2 Idempotency

At-least-once delivery means duplicates. Every participant must handle them:

- Store processed `eventId`/`messageId` in a `processed_events` table, inside the same transaction as the business change.
- Or use natural idempotency (`UPDATE ... WHERE status = 'PENDING'`, unique constraints on `(orderId, step)`).
- Compensations must be idempotent too: refunding twice must be harmless.

### 8.3 Lack of isolation (the "I" in ACID is gone)

Other transactions can see intermediate saga state, so you get dirty reads, lost updates, and so on. These are the countermeasures from Chris Richardson's _Microservices Patterns_:

- **Semantic lock**: set a flag like `PENDING` or `APPROVAL_PENDING` so other flows know the record is mid-saga.
- **Commutative updates**: design operations so order doesn't matter (debit/credit instead of set balance).
- **Pessimistic view**: reorder steps to reduce the dirty-read risk.
- **Reread value**: verify the data hasn't changed before overwriting (optimistic locking with `@Version`).
- **Version file / by value**: record operations and apply them in the right order, or choose the concurrency strategy by business risk.

### 8.4 Message ordering

Kafka guarantees ordering only **within a partition**. Use `orderId` as the message key so all events of one saga go to the same partition.

### 8.5 Failures of compensations

A compensation can fail too. Strategy:

- Retry with exponential backoff (Spring Retry / Resilience4j, or Kafka retry topics with `@RetryableTopic`).
- After N attempts, send to a **Dead Letter Topic** and raise an alert for manual intervention.
- Never silently drop a failed compensation.

### 8.6 Timeouts and stuck sagas

A participant that never replies leaves the saga hanging. Add a scheduler that scans for sagas stuck in a non-terminal state beyond a threshold and triggers compensation or an alert.

### 8.7 Observability

- Propagate a **correlation/saga ID** through all events and logs (MDC).
- Use Micrometer Tracing / OpenTelemetry with Zipkin or Jaeger.
- Expose a saga status endpoint (`GET /orders/{id}/saga`) for support teams.
- Monitor saga durations, failure rate, and compensation count.

## 9. Frameworks and tools

| Option                                  | When to use                                                                                                          |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| **Hand-rolled (Spring Kafka + Outbox)** | Full control, small number of sagas                                                                                  |
| **Spring State Machine**                | Explicit state/transition modelling inside the orchestrator                                                          |
| **Axon Framework**                      | Built-in Saga support (`@Saga`, `@SagaEventHandler`), best with event sourcing and CQRS                              |
| **Eventuate Tram Saga**                 | Richardson's library, orchestration DSL with outbox built in                                                         |
| **Camunda / Zeebe**                     | BPMN-based orchestration, visual modelling, business-visible workflows                                               |
| **Temporal**                            | Durable-execution workflows written as plain Java code; compensation via try/catch; very good for long-running sagas |
| **Netflix Conductor**                   | JSON-defined workflows at large scale                                                                                |

For new enterprise projects with complex flows, **Temporal** or **Camunda** often beat a hand-built orchestrator, because they handle retries, timers, persistence, and visibility for you.

## 10. When to use and when not to

**Use Saga when**

- A business process spans multiple services with separate databases
- Eventual consistency is acceptable
- You need high availability and loose coupling

**Avoid or reconsider when**

- Strong, immediate consistency is mandatory (e.g. core ledger postings). Consider keeping the data in one service.
- You find yourself needing a saga between two services that always change together. That is often a sign of **wrong service boundaries**.
- The business flow isn't tolerant of intermediate states.

## 11. Best-practice checklist

- Prefer **orchestration** beyond about 3-4 steps, **choreography** for simple flows
- Use the **Outbox pattern** (with Debezium CDC at scale)
- Make **every handler and compensation idempotent**
- Key Kafka messages by saga/aggregate ID
- Keep events as facts (`PaymentCompleted`), commands as intents (`ChargePayment`)
- Place the pivot transaction deliberately, and put retriable steps after it
- Version your event schemas (Avro/Protobuf with Schema Registry)
- Add timeouts, DLTs, and alerting for stuck sagas
- Return `202 Accepted` with a status URL to clients, since the result is asynchronous
- Test failure paths: use Testcontainers (Kafka + DB) and inject failures at each step

## 12. Questions you should be able to answer at the 10-year level

1. Why not 2PC? What are its limitations in a cloud-native setup?
2. Choreography vs orchestration: how do you decide?
3. How do you guarantee that a DB write and an event publish happen atomically?
4. What happens if a compensating transaction fails?
5. How do you deal with the lack of isolation in sagas?
6. What is a pivot transaction, and how does it influence step ordering?
7. How do you make consumers idempotent under at-least-once delivery?
8. How would you monitor and debug a saga that's stuck in production?

If you'd like, I can build a full working example next: an Order/Payment/Inventory orchestrated saga with Spring Boot, Kafka (using the compose setup from earlier), and the outbox pattern.

:::{seealso}

- [Saga Choreography | My GitHub Project](https://github.com/revanna7226/ms-design-patterns-saga-choreography)
- [Saga Choreography | JavaTechie | GitHub Project](https://github.com/Java-Techie-jt/saga-choreography-example)
  :::
