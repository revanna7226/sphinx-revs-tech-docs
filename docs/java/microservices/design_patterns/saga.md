# Saga

## The problem

In a monolith, "place order, charge card, reserve stock" is one `@Transactional` method. In microservices each service owns its database, so there is no single ACID transaction across them.

A **saga** replaces one distributed transaction with a **sequence of local transactions**. Each step commits in its own service and triggers the next. If a step fails, the saga runs **compensating transactions** to undo the earlier steps.

```
Happy path:   Create Order → Charge Payment → Reserve Inventory → Approve Order

Failure path: Create Order → Charge Payment → Reserve Inventory ✗
                                  ↓ compensate
              Reject Order ← Refund Payment
```

Compensation is a new business action, not a rollback. A charge that already committed is undone by issuing a refund, not by erasing the row.

## Two styles

|            | Choreography                                    | Orchestration                                  |
| ---------- | ----------------------------------------------- | ---------------------------------------------- |
| Control    | Services react to each other's events           | A central orchestrator sends commands          |
| Coupling   | Services must know which events to listen for   | Services only know the orchestrator's commands |
| Visibility | Flow is spread across services, harder to trace | Flow lives in one place                        |
| Best for   | 2 to 4 steps, simple flows                      | Longer or branching flows                      |
| Risk       | Cyclic dependencies, "event spaghetti"          | Orchestrator becomes a coordination bottleneck |

### Example: Order, Payment, Inventory

### [Choreography Saga](saga/choreography.md)

### [Choreography Saga](saga/choreography.md)
