# Greenwheels Billing Cycle - Test Plan

## 1. Purpose
This test plan defines the risk-based quality strategy for the Greenwheels Billing Cycle service. The objective is to demonstrate that billing commands, immutable facts, and projected account views remain financially correct, deterministic, auditable, secure, and recoverable under normal operations, retries, concurrency, invalid input, and partial failure.

## 2. Quality objectives
- Prevent duplicate invoices and duplicate payment credits.
- Prevent billing for paused or terminated leases.
- Calculate weekly charges and one-cycle discounts correctly.
- Accept only KES on write endpoints.
- Keep event facts and read-model projections reconcilable.
- Detect projection lag, event loss, replay errors, and ordering defects.
- Provide repeatable release evidence through Newman in CI.

## 3. Scope
### In scope
- `POST /billing/cycles`
- `POST /billing/payments`
- `GET /billing/cycles/{driver_id}`
- `POST /billing/discounts`
- `GET /billing/summary/{driver_id}`
- Authentication and authorization behavior for the API surface.
- Request/response contracts, validation, error handling, status transitions, totals, due dates, and currency.
- All five stated business rules.
- Event creation, duplicate delivery, ordering, projection, replay, and recovery behavior.
- Functional, integration, negative, boundary, regression, concurrency, resilience, and security-focused tests.
- CI execution against the provided Docker Compose stub.[File is not provided in the email.]
### Out of scope
- Motorcycle intake and QC inspection.
- Customer onboarding
- Lease ownership-transfer workflow beyond billing effects.
- Payment-provider internals not exposed by the stub.
- Driver-facing UI and mobile applications.
- Country tax or accounting rules not provided.
- Full penetration testing and AWS infrastructure certification.
- Implementing the 500,000-driver performance test, because the scale exercise is design-only.

## 4. Assumptions and questions requiring confirmation
1. KES is the only supported currency on every write endpoint.
2. Week numbers follow ISO-8601 and valid values are normally 1-53. <-----------------
3. A billing cycle should be unique for a driver, year, and week. This is a proposed financial invariant, not an explicitly stated rule.
4. The scope of `payment_reference` uniqueness must be confirmed: global, country, provider, or tenant.
5. The exact weekly amount formula, rounding mode, due-date timezone, and discount eligibility rules are not supplied.
6. Expected handling of partial payments, overpayments, refunds, disputed invoices, and late payments is not supplied.
7. The acceptable projection-lag service level is not supplied.
8. Multi lang support in the future for the application.

These items will remain documented assumptions rather than being silently treated as confirmed requirements.

## 5. Risk assessment
| ID | Quality risk | Impact | Likelihood | Priority | Primary controls |
|---|---|---:|---:|---:|---|
| R1 | Duplicate payment credit during client, broker, or worker retries | Critical | High | P0 | Sequential and concurrent idempotency tests; unique fact and balance reconciliation |
| R2 | Incorrect invoice amount, discount, or rounding | Critical | Medium | P0 | Calculation decision table, boundaries, golden values, invariant checks |
| R3 | Weekly job replay generates duplicate invoices | Critical | Medium | P0 | Same driver/week replay and concurrent cycle-generation tests |
| R4 | Paused or terminated lease is billed | High | Medium | P0 | Lease-state matrix and lifecycle race tests |
| R5 | Three-missed-payment rule is evaluated incorrectly | High | Medium | P1 | Consecutive and non-consecutive sequence tests; reset after payment |
| R6 | Non-KES or missing currency enters ledger | High | Medium | P1 | Currency matrix on all three write endpoints |
| R7 | Event loss, duplicate delivery, or ordering changes balance | High | Medium | P1 | Duplicate/out-of-order delivery, checkpoint, restart, and replay tests |
| R8 | Unauthorized caller accesses or changes another driver's billing data | Critical | Medium | P0 | Missing/invalid token and driver-scope authorization tests |
| R9 | Peak day batch overload causes timeouts, backlog, retries, or partial completion | Critical | Medium | P0 at scale | Load, endurance, recovery, queue-lag, and reconciliation testing |

## Business-rule coverage

### BR-01: Lease state controls cycle generation
- Active lease: cycle accepted and exactly one billing fact created.
- Paused lease: request rejected and no invoice/fact created.
- Terminated lease: request rejected and no invoice/fact created.
- State changes while request is in flight: result follows the defined ordering/concurrency policy.

### BR-02: Payments are idempotent by payment reference
- Same reference and identical payload submitted twice sequentially.
- Same reference submitted many times concurrently.
- Same reference reused with a different amount or invoice.
- Retry after client timeout.
- Verify one durable fact and one increase to `total_paid`.

### BR-03: Three consecutive missed payments cause overdue status
- Zero, one, and two consecutive misses do not trigger the rule.
- Exactly three consecutive misses trigger overdue.
- Four misses remain overdue.
- A paid week breaks the consecutive sequence.
- Three total but non-consecutive misses do not trigger the consecutive rule.
- A late payment's effect follows the agreed business policy.

### BR-04: Discount applies to the following cycle only and does not stack
- Eligible discount reduces only the immediately following cycle.
- A second discount before cycle generation is rejected or replaces the first, but never sums with it.
- The next cycle after consumption returns to the normal amount.
- Failed cycle generation does not accidentally consume a discount unless specified.
- Ineligible, zero, negative, excessive, and high-precision discounts are rejected.

### BR-05: Every write validates KES
- Cycle, payment, and discount writes accept `KES`.
- Each write rejects missing, null, empty, `USD`, `GHS`, `UGX`, lowercase `kes`, and whitespace variants unless normalization is explicitly required.
- Rejected currency commands create no financial fact.


## 6. Test approach
### 6.1 Functional and contract testing
- Validate success behavior for each endpoint.
- Validate status code, content type, mandatory properties, data types, allowed enums, and date formats.
- Confirm status transitions including pending, paid, overdue, and disputed where fixtures support them.
- Reconcile summary totals with cycle and payment records.

### 6.2 Negative and boundary testing
- Missing, null, empty, malformed, and wrong-type fields.
- Week numbers 0, 1, 52, 53, and 54, including year combinations where supported.
- Zero, negative, excessive, and high-precision monetary values.
- Missing, lowercase, whitespace-padded, and unsupported currency values.
- Empty, very long, Unicode, and reused payment references.
- Missing, expired, malformed, and unauthorized tokens.

### 6.3 Integration testing
- Lease-state lookup and lifecycle changes.
- Event-store append behavior and aggregate versioning.
- Projection consumer, checkpointing, and PostgreSQL persistence.
- Payment integration boundaries where represented by the stub.
- Database migrations and uniqueness constraints.

### 6.4 Concurrency and resilience testing
- Concurrent duplicate payment submissions.
- Concurrent cycle generation for the same driver/week.
- Lease pause/termination racing cycle creation.
- Client timeout after command acceptance followed by retry.
- Service restart after fact append but before projection.
- Database/broker delay, worker restart, poison event, and recovery.

### 6.5 Security-focused testing
- Authentication and driver-level authorization.
- Sensitive token and customer-data maskig in logs.
- Rate-limit or abuse behavior if included in the service contract.
- Append-only access enforcement for immutable facts.

### 6.6 Regression strategy
- Run all P0 API checks on every pull request.
- Run the complete functional, state-sequence, and negative suite nightly or before release.
- Run performance and recovery tests before production-impacting billing changes.
- Quarantine no test silently. Every flaky test requires an owner, defect link, and removal deadline.


## 7. Endpoint scenario inventory
### POST /billing/cycles
Happy path, inactive lease, duplicate week, concurrent generation, invalid driver, invalid week, missing currency, invalid currency, due-date boundary, discount application, retry after timeout, and unauthorized caller.

### POST /billing/payments
Happy-path full payment, sequential/concurrent duplicates, conflicting payload with same reference, unknown invoice, missing reference, invalid amount, invalid currency, partial/overpayment subject to policy, late payment, timeout/retry, and unauthorized caller.

### GET /billing/cycles/{driver_id}
Empty history, all supported statuses, deterministic ordering, invalid/unknown driver, response isolation between drivers, pagination if supported, and projection consistency after commands.

### POST /billing/discounts
Eligible discount, ineligible driver, duplicate discount, non-stacking behavior, consumption after one cycle, invalid amount, missing/invalid currency, invalid driver, and unauthorized caller.

### GET /billing/summary/{driver_id}
Empty account, billed/paid/outstanding reconciliation, missed-payment sequences, overdue flag, disputed cycle, projection lag, replay consistency, invalid/unknown driver, and authorization.

## 8. Event-sourced system validation
1. Capture correlation ID, causation ID, aggregate ID, expected aggregate version, and command input.
2. Confirm an accepted command appends the correct immutable fact exactly once.
3. Confirm a rejected command appends no financial fact.
4. Build an independent oracle that folds ordered facts into expected cycles, totals, and statuses.
5. Compare the oracle state with cycle and summary projections.
6. Poll projected reads only within a defined consistency window. Report SLA breach separately from incorrect final state.
7. Rebuild the projection from an empty read store and compare canonical before/after state.
8. Deliver duplicate and out-of-order events and validate deduplication or deterministic ordering.
9. Restart the consumer around append/checkpoint boundaries and verify no loss or double application.
10. Verify schema versioning/upcasting and snapshot equivalence when those mechanisms exist.
11. Verify immutable facts cannot be updated or deleted by application credentials.
12. Reconcile counts and financial totals across command responses, facts, projections, and database constraints.

## 9. Test data and isolation
- Use deterministic seeded drivers for active, paused, terminated, three-missed-payment, and discount-eligible states.
- Generate unique payment references per logical test except explicit idempotency cases.
- Give each test ownership of its driver/invoice data where possible.
- Reset the database or recreate the Compose stack for a clean run.
- Do not make independent tests depend on execution order.
- Capture request ID, driver ID, invoice ID, payment reference, event ID/version, and projection checkpoint in test evidence without logging secrets.

## 10. Environment strategy
### Pull-request environment
- Disposable Docker Compose stack.
- Deterministic fixtures and database reset.
- Newman collection executed with a five-second request timeout.

### Pre-release environment
- Production-compatible database, broker, and service versions.
- Synthetic but production-shaped data.
- Event-store/projection observability and failure-injection support.
- Restricted access and no real customer payment data.

## 11. Entry criteria
- API and event contracts are available and reviewed.
- Open business decisions in Section 4 are resolved or explicitly accepted as test assumptions.
- Service, database, migrations, and fixtures start successfully through Docker Compose.
- Required dependent services are healthy.
- Unit/component checks pass.
- Test identities and authorization scopes are available.
- Correlation, event, and projection telemetry is accessible.

## 12. Exit criteria and release sign-off
- 100% of P0 and P1 scenarios executed.
- All five stated business rules pass.
- Newman reports zero failed assertions in the release candidate.
- No unresolved Critical or High defect.
- Medium defects have documented business acceptance, owner, and workaround.
- No unexplained test flakiness across three clean executions.
- Performance and recovery targets pass for the agreed release profile.
- Monitoring, alerting, rollback, and rerun procedures are verified.
- QA publishes tested scope, evidence, known gaps, residual risks, and a recommendation. Product and engineering retain final business-risk acceptance.

## 13. Scale considerations
### 13.1 Capacity and likely first failures
Generating 500,000 invoices in four hours requires an average completion rate of approximately 34.7 invoices per second. The test must include burst and recovery headroom because a flat average hides operational peaks.

Likely early constraints:
- Scheduler partition skew and duplicate job dispatch.
- PostgreSQL connection-pool, index, lock, I/O, and transaction contention.
- Event-broker partition throughput and consumer lag.
- Projection backlog and hot driver/tenant partitions.
- Downstream throttling and retry amplification.
- Memory growth, dead-letter accumulation, and insufficient observability.

### 13.2 Performance-test structure
Use k6 for HTTP workload generation and a purpose-built reconciliation probe for event-store/database validation.

Suggested load shape, subject to SRE approval:
- Ramp from 0 to 50 requests/second.
- Hold 50 requests/second to provide headroom above the 34.7/second average.
- Burst to 100 requests/second to model delayed scheduler recovery.
- Run a four-hour endurance profile.
- Inject database/broker latency, restart workers, and slow one partition to test recovery.

Provisional success criteria to be ratified:
- 500,000 unique commands complete within four hours.
- Zero lost or duplicate invoices.
- Financial reconciliation mismatch equals zero.
- HTTP p95 below 2 seconds and p99 below 5 seconds at target load.
- Unexpected error rate below 0.1%.
- Projection backlog returns to baseline within 15 minutes after peak.
- No sustained database or worker-pool exhaustion.

### 13.3 Idempotency at 0.1% duplicate rate
Inject exactly 500 duplicate submissions into a 500,000-payment workload. Split duplicates between sequential retries and concurrent races. Tag each logical payment with an oracle identifier.

Required results:
- 500,000 unique logical credits.
- All 500 duplicates recognized as replayed or rejected according to contract.
- Zero duplicate balance increase.
- Exactly one durable payment fact per unique reference.
- Report duplicate-detection rate, false positives, false negatives, and reconciliation mismatches.

### 13.4 Five-country regression strategy
Avoid copying the full suite per country. Use one parameterized contract and state-machine suite driven by country policy fixtures containing currency, timezone, billing calendar, tax/fee rules, discount rules, rounding, and eligibility. Run common financial/event invariants for every country, targeted country-specific examples, pairwise combinations, and approved golden calculations. Version country policy data independently while preserving common API and event contracts.

## 14. Deliverables and evidence
- Newman CLI and JUnit reports.
- Request/response evidence with secrets removed.
- Event and projection reconciliation output.
- Defect reports with correlation identifiers and reproducible fixtures.
- CI run link and job summary.
- Release test summary with residual risks and recommendation.

## 15. Known gaps for this draft
The challenge document does not include the executable stub, Docker Compose file, exact schemas, discount eligibility rules, seeded fixture values, or projection-lag SLA. Those items must be validated against the supplied service before claiming execution results or final defect findings.
