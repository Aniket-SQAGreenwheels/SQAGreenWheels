@billing @lease-state @business-rule-01
Feature: Prevent billing cycle generation for inactive leases
  To avoid charging drivers who are not permitted to use their motorcycles
  the billing service must generate a weekly billing cycle only when the driver's lease is active.

  Background:
    Given the Greenwheels billing API is available
    And I am authenticated as an authorized fleet operations user
    And the test driver data is reset to a known state

  Scenario Outline: Billing cycle generation is controlled by the current lease state
    Given driver "<driver_id>" has a lease in the "<lease_state>" state
    And driver "<driver_id>" has no billing cycle for ISO week <week_number>
    When I request a billing cycle for driver "<driver_id>" with week <week_number> and currency "KES"
    Then the request outcome should be "<expected_outcome>"
    And the response should have the expected HTTP classification "<http_classification>"
    And the number of new billing cycle facts for the driver and week should be <expected_fact_count>
    And the number of new invoices for the driver and week should be <expected_invoice_count>

    Examples:
      | driver_id          | lease_state | week_number | expected_outcome | http_classification | expected_fact_count | expected_invoice_count |
      | drv-active-001     | active      | 42          | accepted         | success             | 1                   | 1                      |
      | drv-paused-001     | paused      | 42          | rejected         | client-error        | 0                   | 0                      |
      | drv-terminated-001 | terminated  | 42          | rejected         | client-error        | 0                   | 0                      |

  Scenario: A rejected paused-lease request has no financial side effects
    Given driver "drv-paused-002" has a lease in the "paused" state
    And the driver's billed total and invoice count are recorded
    When I request a billing cycle for the driver with week 43 and currency "KES"
    Then the billing cycle request should be rejected
    And no billing cycle fact should be appended
    And no invoice should be created
    And the driver's billed total should remain unchanged
    And the driver's billing summary should remain unchanged after projection processing

  Scenario: A rejected terminated-lease request has no financial side effects
    Given driver "drv-terminated-002" has a lease in the "terminated" state
    And the driver's billed total and invoice count are recorded
    When I request a billing cycle for the driver with week 43 and currency "KES"
    Then the billing cycle request should be rejected
    And no billing cycle fact should be appended
    And no invoice should be created
    And the driver's billed total should remain unchanged
    And the driver's billing summary should remain unchanged after projection processing

  Scenario: Lease pause and billing commands are resolved using fact order
    Given driver "drv-state-race-001" initially has an active lease
    And no billing cycle exists for week 44
    When a lease pause command and a week 44 billing cycle command are submitted concurrently
    Then the resulting decision should follow the authoritative order of committed facts
    And if the lease pause fact is committed first, no billing cycle fact should be appended
    And if the billing cycle fact is committed first, no duplicate billing cycle should be created
    And the projected lease and billing views should match the committed fact order

  Scenario: Retrying an inactive-lease request remains side-effect free
    Given driver "drv-paused-retry-001" has a lease in the "paused" state
    And no billing cycle exists for week 45
    When I submit the same week 45 billing cycle request three times
    Then every request should be rejected
    And no billing cycle fact should be appended
    And no invoice should be created
    And the driver's billing summary should remain unchanged
