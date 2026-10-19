# Greenwheels Billing Cycle - Defect Report

## Evidence status

The challenge states that the stub service contains two intentional defects. However, the executable stub service and `docker-compose.yml` were not included with the available challenge document. Therefore, the defects below are documented as **candidate defect hypotheses**, not confirmed findings.

Before submission, each `Actual result` section must be replaced with evidence captured from the supplied service. A defect must not be marked as confirmed or open until the stated behavior has been reproduced against a clean test environment.

---

## GW-BILL-001 - Duplicate payment reference may create duplicate credit

### Status
Unverified candidate defect. Execution is blocked until the stub service is available.

### Requirement
Payment facts must be idempotent by `payment_reference`. Submitting the same payment reference more than once must not create duplicate credit.

### Preconditions
1. The stub service is running using the supplied Docker Compose configuration.
2. The database is reset to a known seed state.
3. An authorized API token is available.
4. Driver `drv-idem-001` has an active lease.
5. Invoice `inv-idem-001` is pending and has an outstanding amount of 1,000 KES.
6. The driver's starting `total_paid` and `total_outstanding` values are recorded.
7. No payment fact currently uses reference `qa-idem-001`.

### Test data

| Field | Value |
|---|---|
| Driver ID | `drv-idem-001` |
| Invoice ID | `inv-idem-001` |
| Amount | `1000` |
| Currency | `KES` |
| Payment reference | `qa-idem-001` |

### Steps to reproduce
1. Send the following payment request:

```http
POST /billing/payments
Authorization: Bearer <test-token>
Content-Type: application/json
```

```json
{
  "invoice_id": "inv-idem-001",
  "amount": 1000,
  "currency": "KES",
  "payment_reference": "qa-idem-001"
}
```

2. Record the HTTP status, response body, correlation ID, and returned payment identifier.
3. Send the identical request again using the same `payment_reference`.
4. Record the second HTTP status, response body, correlation ID, and returned payment identifier.
5. Call `GET /billing/summary/drv-idem-001`.
6. Call `GET /billing/cycles/drv-idem-001`.
7. If test access is available, query the event store for payment facts with reference `qa-idem-001`.
8. Compare the driver's final totals with the recorded starting values.

### Expected result
- Only one durable payment fact exists for `qa-idem-001`.
- The invoice is credited by exactly 1,000 KES.
- `total_paid` increases by exactly 1,000 KES.
- `total_outstanding` decreases by exactly 1,000 KES.
- The second request returns the service's documented idempotent replay or duplicate response.
- If both requests return a payment identifier, the identifiers refer to the same logical payment.
- The invoice reaches `paid` status once and no duplicate financial side effect occurs.

### Actual result
**Not yet captured.** Replace this section with:
- First response status and body
- Second response status and body
- Summary before and after
- Cycle/invoice state before and after
- Number of matching payment facts
- Correlation IDs and relevant service logs

### Severity
**Critical**, if confirmed.

### Severity justification
A duplicated credit directly corrupts the driver's financial balance. It could incorrectly clear outstanding debt, suppress collection action, change missed-payment calculations, or contribute to an incorrect lease-to-own balance. Retries are expected in distributed systems, so the failure can occur during ordinary operation rather than only through unusual input.

### Priority
**P0**, if confirmed.

### Priority justification
The defect affects financial integrity and must block release until duplicate credit is prevented and existing duplicate records can be detected or reconciled.

### Suggested root cause
The payment command handler may perform a non-atomic lookup-and-insert operation without a durable unique constraint on `payment_reference`.

### Recommended technical investigation
- Check for a database or event-store uniqueness constraint on `payment_reference`.
- Check whether idempotency is evaluated before or after appending the payment fact.
- Check whether concurrent requests can pass the duplicate check in separate transactions.
- Check whether projection consumers deduplicate by event ID.
- Check whether the idempotency key is scoped consistently across API, event, and database layers.

### Required regression coverage
1. Two identical sequential submissions.
2. Ten identical concurrent submissions.
3. Retry after the server commits the payment but the client times out.
4. Same reference with a different amount.
5. Same reference with a different invoice.
6. Duplicate event delivery to the summary projection.

---

## GW-BILL-002 - Weekly discount may stack or carry into multiple billing cycles

### Status
Unverified candidate defect. Execution is blocked until the stub service is available.

### Requirement
A discount must apply only to the following week's billing cycle. Discounts must not stack and must not carry over into later cycles.

### Preconditions
1. The stub service is running using the supplied Docker Compose configuration.
2. The database is reset to a known seed state.
3. An authorized API token is available.
4. Driver `drv-discount-001` has an active lease and is eligible for a discount.
5. The driver's normal weekly billing amount is known and recorded as `BASE_AMOUNT`.
6. No unconsumed discount exists for the driver.
7. No billing cycles exist for weeks 43 and 44.

### Test data

| Field | First request | Second request |
|---|---:|---:|
| Driver ID | `drv-discount-001` | `drv-discount-001` |
| Discount amount | `100` | `200` |
| Currency | `KES` | `KES` |
| Target behavior | Next cycle only | Must not stack |

### Steps to reproduce
1. Record the driver's normal weekly `BASE_AMOUNT`.
2. Submit the first discount:

```json
{
  "driver_id": "drv-discount-001",
  "amount": 100,
  "currency": "KES"
}
```

3. Before generating the next cycle, submit a second discount:

```json
{
  "driver_id": "drv-discount-001",
  "amount": 200,
  "currency": "KES"
}
```

4. Record both discount responses and correlation IDs.
5. Generate the driver's billing cycle for week 43.
6. Record the week 43 `amount_due` and invoice ID.
7. Without submitting another discount, generate the driver's billing cycle for week 44.
8. Record the week 44 `amount_due` and invoice ID.
9. Call the cycle-history and summary endpoints.
10. If test access is available, inspect discount and billing-cycle facts for the driver.

### Expected result
- The two discounts are never added together.
- The service either rejects the second unconsumed discount or replaces the first according to a documented rule.
- Exactly one permitted discount affects week 43.
- Week 44 returns to `BASE_AMOUNT` because no new discount was submitted.
- The discount is consumed exactly once.
- The cycle history, summary, and event facts show no stacked or carried discount.

### Expected calculation examples
The exact result depends on the confirmed second-discount policy:

- If the second discount is rejected, week 43 should equal `BASE_AMOUNT - 100`.
- If the second discount replaces the first, week 43 should equal `BASE_AMOUNT - 200`.
- Week 43 must never equal `BASE_AMOUNT - 300`.
- Week 44 should equal `BASE_AMOUNT` in either permitted policy.

### Actual result
**Not yet captured.** Replace this section with:
- Normal weekly amount
- First and second discount responses
- Week 43 and week 44 invoice responses
- Cycle history and summary after both cycles
- Discount and billing facts, if accessible
- Correlation IDs and relevant service logs

### Severity
**High**, if confirmed.

### Severity justification
Stacking or carrying discounts causes systematic under-billing, inaccurate invoices, and revenue leakage. The result also makes the immutable fact history and customer account projection financially incorrect. The impact is serious but normally limited to drivers receiving repeated or overlapping discounts, making it lower than a general duplicate-payment-credit defect.

### Priority
**P1**, if confirmed.

### Priority justification
The issue should block release of the discount workflow. Priority may be raised to P0 if the defect affects all discounted drivers, cannot be detected through reconciliation, or has already produced incorrect invoices.

### Suggested root cause
The projection or billing calculation may aggregate all active discount facts without marking the selected discount as consumed after the next cycle is generated.

### Recommended technical investigation
- Check whether a discount fact includes a target week or consumption status.
- Check whether generating a cycle atomically records discount consumption.
- Check how multiple unconsumed discounts are resolved.
- Check whether replay rebuilds the same discount-consumption state.
- Check retry behavior when the cycle fact is committed but discount consumption is not projected.

### Required regression coverage
1. One eligible discount applied to the next cycle.
2. Two discounts submitted before the next cycle.
3. Cycle immediately after the discounted cycle.
4. Cycle-generation retry after timeout.
5. Failed cycle generation followed by retry.
6. Projection rebuild from discount and billing facts.

---

## Evidence checklist for confirmed defects

For each confirmed defect, attach or link:

- Stub service image/build identifier
- Docker Compose configuration or commit
- Date and environment of execution
- Clean seed/reset procedure
- Sanitized request and response payloads
- HTTP status codes
- Correlation or request IDs
- Relevant service logs
- Event-store records, when accessible
- Projected summary before and after
- Reproduction frequency
- Newman test name and result
- Screenshot only when it adds evidence not already available as machine-readable output

## Defect finalization rule

Before final submission:

1. Run the complete Postman collection against the supplied stub.
2. Identify the two behaviors that actually fail.
3. Keep these reports only if the observed failures match the hypotheses.
4. Otherwise, replace the candidate reports with the two observed defects.
5. Populate every `Actual result` section with objective execution evidence.
6. Reassess severity and priority using the observed scope and impact.
7. Remove the `Unverified candidate defect` status only after reproducible confirmation.
