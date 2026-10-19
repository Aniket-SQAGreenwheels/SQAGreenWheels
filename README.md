# Greenwheels Billing Cycle - Senior QA Engineering Challenge

## Overview

This repository contains a risk-based quality strategy and API test suite for the Greenwheels Billing Cycle feature. The feature generates weekly billing cycles, applies discounts, records payment facts, returns cycle history, and calculates driver-level billing summaries.

The solution focuses on financial correctness, payment idempotency, lease-state enforcement, immutable facts, projection consistency, failure recovery, and CI repeatability.

## Repository structure

.
├── README.md
├── TEST_PLAN.md
├── DEFECTS.md
├── AI_USAGE.md
├── postman
│   ├── collection.json
│   └── env.json
├── features
│   ├── lease_state_billing.feature
│   └── payment_idempotency.feature
└── .github
    └── workflows
        └── qa.yml
```

## Deliverables

### `TEST_PLAN.md`

Contains:

- Scope and out-of-scope items
- Quality objectives
- Assumptions and contract questions
- Risk assessment and prioritization
- Functional, integration, negative, boundary, concurrency, resilience, security, and regression approaches
- Coverage for all five business rules
- Event-sourced system validation strategy
- Entry and exit criteria
- Release sign-off expectations
- Scale considerations for 500,000 drivers

### `postman/collection.json`

A Postman Collection v2.1 test suite containing:

- Happy-path coverage for all five endpoints
- Distinct test folders for all five business rules
- Negative and boundary scenarios
- Status-code assertions
- JSON response checks
- Business-rule-specific assertions
- Response-time assertions
- Dynamic collection variables

### `postman/env.json`

A non-secret Postman environment containing:

- `base_url`
- `auth_token` placeholder
- Driver fixture identifiers
- Invoice fixture identifiers
- Expected idempotency totals

### `features/`

Contains two Cucumber-compatible Gherkin feature files:

1. Billing-cycle generation based on lease state
2. Payment idempotency by payment reference

Each feature contains a `Background`, a `Scenario Outline`, and at least three data variants.

### `DEFECTS.md`

Contains two structured candidate defect reports. The reports are intentionally marked unverified because the executable stub service was not available when the repository artifacts were authored.

### `.github/workflows/qa.yml`

Runs the Postman collection through Newman on every pull request. The workflow:

- Starts the stub using Docker Compose
- Uses a five-second service-response timeout
- Fails when a Newman request or assertion fails
- Publishes a pass/fail summary
- Uploads a JUnit report
- Captures service logs on failure
- Cleans up the Compose environment

### `AI_USAGE.md`

Documents:

- AI tools used
- Areas where AI accelerated the work
- AI output that was corrected or rejected
- Manually emphasized test cases
- Human validation performed
- Validation still required before submission

## Prerequisites

The following tools are required:

- Docker with Docker Compose v2
- Node.js and npm
- Newman
- Git

The challenge-provided `docker-compose.yml` must be placed in the repository root.

## Setup

### 1. Clone the repository

```bash
git clone <repository-url>
cd <repository-directory>
```

### 2. Add the supplied stub configuration

Place the challenge-provided file at:

```
./docker-compose.yml
```

### 3. Start the stub service

```bash
docker compose up -d --build
```

### 4. Check container state

```bash
docker compose ps
```

If the service exposes the assumed health endpoint, verify it with:

```bash
curl --fail --max-time 5 http://localhost:8000/health
```

If the actual Compose configuration uses another port or health path, update `base_url` in `postman/env.json` and the health check in `.github/workflows/qa.yml`.

## Configure the Postman environment

Before running the suite, reconcile `postman/env.json` with the seeded test data supplied by the stub.

The placeholder values include:

| Variable | Purpose |
|---|---|
| `base_url` | Billing API base URL |
| `auth_token` | Local test token placeholder |
| `driver_id` | Active driver used for shared setup |
| `happy_driver_id` | Separate active driver used by the happy path |
| `paused_driver_id` | Driver with a paused lease |
| `terminated_driver_id` | Driver with a terminated lease |
| `idempotency_driver_id` | Driver used for duplicate-payment validation |
| `idempotency_invoice_id` | Pending invoice used for duplicate-payment validation |
| `idempotency_expected_total_paid` | Expected total after one accepted logical payment |
| `two_missed_driver_id` | Driver with two consecutive misses |
| `three_missed_driver_id` | Driver with at least three consecutive misses |
| `nonconsecutive_missed_driver_id` | Driver with three total but non-consecutive misses |
| `discount_driver_id` | Active, discount-eligible driver |

Do not commit a real authentication token. For local execution, update the local environment value or pass it through Newman using `--env-var`.

## Install Newman

```bash
npm install --global newman newman-reporter-junitfull
```

Confirm installation:

```bash
newman --version
```

## Run the API suite

From the repository root:

```bash
newman run postman/collection.json \
  --environment postman/env.json \
  --timeout-request 5000 \
  --timeout-script 5000 \
  --bail failure \
  --reporters cli,junitfull \
  --reporter-junitfull-export newman-results.xml
```

To pass the token without storing it in the environment file:

```bash
newman run postman/collection.json \
  --environment postman/env.json \
  --env-var "auth_token=$QA_AUTH_TOKEN" \
  --timeout-request 5000 \
  --timeout-script 5000 \
  --bail failure \
  --reporters cli,junitfull \
  --reporter-junitfull-export newman-results.xml
```

## Expected execution order

The collection is organized so that setup executes before dependent requests:

1. Shared active-driver cycle creation
2. Happy paths for all five endpoints
3. Paused and terminated lease rules
4. Payment idempotency
5. Three-consecutive-missed-payment rule
6. Discount lifecycle
7. KES validation
8. Negative and boundary cases

Independent scenarios should use separate seeded drivers. Recreate or reset the stub database before each complete suite run to avoid contamination from previous invoices, payments, or discounts.

## Run selected folders

Examples:

```bash
newman run postman/collection.json \
  --environment postman/env.json \
  --folder "BR-02 - Payment Idempotency"
```

```bash
newman run postman/collection.json \
  --environment postman/env.json \
  --folder "BR-05 - KES Validation on Every Write"
```

A folder that depends on a previously created invoice may require an appropriate seeded `invoice_id` or execution of the setup folder first.

## Import into Postman

1. Import `postman/collection.json` as a collection.
2. Import `postman/env.json` as an environment.
3. Select `Greenwheels Billing - Local Stub`.
4. Replace placeholder fixture values with values from the supplied stub.
5. Set the authentication token locally.
6. Run the entire collection using the Postman Collection Runner.

## CI execution

The workflow is located at:

```text
.github/workflows/qa.yml
```

It runs on every pull request and can also be started manually.

The workflow expects an optional GitHub Actions repository secret:

```text
QA_AUTH_TOKEN
```

If the local stub does not require authentication, align the collection and workflow with the actual contract rather than storing a dummy production-like secret.

The workflow fails when:

- Required files are missing
- Docker Compose cannot start the service
- The health endpoint does not become responsive
- A service request exceeds the configured five-second timeout
- Newman cannot execute
- Any Newman request or assertion fails

The workflow writes passed, failed, skipped, and total test counts to the GitHub job summary and uploads `newman-results.xml` as an artifact.

## BDD scenarios

The feature files can be linted or reviewed using a Cucumber-compatible tool. Step definitions are intentionally not included because the challenge evaluates the Gherkin scenarios rather than their implementation.

```text
features/lease_state_billing.feature
features/payment_idempotency.feature
```

The scenarios include event/fact assertions that may require test-only access to the event store, logs, or a diagnostic API in a full implementation.

## API contract assumptions

The challenge provides endpoint purposes and selected rules but does not provide complete request/response schemas. This solution currently assumes:

- Bearer-token authentication
- JSON request and response bodies
- KES as the only permitted currency on write endpoints
- Week numbers represented as integers
- `amount` used for payment and discount values
- Error bodies containing `error`, `message`, or `detail`
- The service running at `http://localhost:8000`
- A health endpoint at `/health`

The following behavior must be confirmed from the stub definition:

- Exact success and error status codes
- Authentication requirements
- Request-field names and numeric formats
- Discount eligibility and maximum amount
- Policy for a second unconsumed discount
- Partial-payment and overpayment behavior
- Due-date calculation and timezone
- Representation of overdue status in the summary
- Scope of `payment_reference` uniqueness
- Acceptable projection-lag window

## Event-sourcing test approach

API success alone is not sufficient for financial correctness. Where diagnostic access exists, verification should include:

1. An accepted command creates the intended immutable fact exactly once.
2. A rejected command creates no financial fact.
3. Projected cycle and summary views match an independent fold of ordered facts.
4. Duplicate and out-of-order event delivery does not corrupt totals.
5. Projection restart and replay produce equivalent canonical state.
6. Facts, invoices, payments, and summaries reconcile after retries and failures.

## Defect-report status

`DEFECTS.md` currently contains two candidate hypotheses:

1. A duplicate payment reference may produce duplicate credit.
2. A discount may stack or carry into later cycles.

These are not claimed as confirmed defects. After the stub is available:

1. Run the complete collection against a clean environment.
2. Identify the two actual failing behaviors.
3. Keep the existing reports only if the evidence matches them.
4. Otherwise replace them with reports for the observed defects.
5. Populate status codes, responses, logs, correlation IDs, facts, and projected totals.
6. Reassess severity and priority based on observed scope and impact.

## Scale-design summary

The scale exercise is documented in `TEST_PLAN.md`. Key points include:

- 500,000 invoices in four hours requires an average completion rate of approximately 34.7 invoices per second.
- Load testing should include sustained traffic, bursts, endurance, and failure recovery.
- Idempotency-at-scale testing should inject exactly 500 duplicate payments in a 500,000-payment workload to represent a 0.1% duplicate rate.
- Financial reconciliation must detect any lost or duplicate invoice/payment.
- Country-specific billing behavior should use parameterized policy fixtures rather than copied suites.

Performance targets in the test plan are proposals and require approval from product, engineering, and SRE stakeholders.

## Known gaps

1. The executable stub service and `docker-compose.yml` were not available while authoring these artifacts.
2. The Postman payloads and response assertions have not been reconciled with an executable OpenAPI contract.
3. The placeholder fixture identifiers may not match the stub's seeded data.
4. The two intentional defects have not been executed or confirmed.
5. The CI workflow has been syntax-validated but not run against the actual Compose service.
6. Event-store and projection-level assertions require access not defined in the challenge document.
7. Performance tests are described but not implemented, as requested by the design-only scale exercise.


## Cleanup

Stop and remove the local Compose environment:

```bash
docker compose down --volumes --remove-orphans
```

Remove generated reports if they should not be committed:

```bash
rm -f newman-results.xml
```
