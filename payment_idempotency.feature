@billing @payments @idempotency @business-rule-02
Feature: Record a logical payment exactly once
  To prevent duplicate credits when callers or message handlers retry a payment
  the billing service must treat payment_reference as an idempotency key.

  Background:
    Given the Greenwheels billing API is available
    And I am authenticated as an authorized payment operations user
    And the payment test data is reset to a known state
    And driver "drv-payment-001" has an active lease
    And invoice "inv-payment-001" is pending for driver "drv-payment-001"
    And invoice "inv-payment-001" has an outstanding amount of 1000 KES
    And the driver's starting total paid and outstanding values are recorded

  Scenario Outline: Repeated identical payment submissions produce one credit
    When I submit a payment of 1000 KES to invoice "inv-payment-001" using reference "<payment_reference>" <submission_count> times with "<delivery_mode>" delivery
    Then exactly <expected_payment_fact_count> durable payment fact should exist for reference "<payment_reference>"
    And invoice "inv-payment-001" should be credited by exactly <expected_credit> KES
    And the driver's total paid should increase by exactly <expected_credit> KES
    And the driver's total outstanding should decrease by exactly <expected_credit> KES
    And invoice "inv-payment-001" should have status "paid"
    And every duplicate response should follow the documented idempotency response contract

    Examples:
      | payment_reference | submission_count | delivery_mode | expected_payment_fact_count | expected_credit |
      | pay-idem-seq-001  | 2                | sequential    | 1                           | 1000            |
      | pay-idem-seq-002  | 3                | sequential    | 1                           | 1000            |
      | pay-idem-conc-001 | 10               | concurrent    | 1                           | 1000            |

  Scenario: Reusing a payment reference with a different amount is rejected
    Given payment reference "pay-conflict-amount-001" has credited 1000 KES to invoice "inv-payment-001"
    When I submit a payment of 900 KES to invoice "inv-payment-001" using reference "pay-conflict-amount-001"
    Then the payment command should be rejected as an idempotency conflict
    And no additional payment fact should be appended for reference "pay-conflict-amount-001"
    And invoice "inv-payment-001" should receive no additional credit
    And the driver's total paid and outstanding values should remain unchanged

  Scenario: Reusing a payment reference for a different invoice is rejected
    Given payment reference "pay-conflict-invoice-001" has credited 1000 KES to invoice "inv-payment-001"
    And invoice "inv-payment-002" is pending for the same driver
    When I submit a payment to invoice "inv-payment-002" using reference "pay-conflict-invoice-001"
    Then the payment command should be rejected as an idempotency conflict
    And no payment fact should be appended for invoice "inv-payment-002"
    And invoice "inv-payment-002" should receive no credit
    And exactly one durable payment fact should exist for reference "pay-conflict-invoice-001"

  Scenario: A client retry after an ambiguous timeout does not duplicate credit
    Given the service commits payment reference "pay-timeout-001" for 1000 KES
    And the client does not receive the first response because the connection times out
    When the client retries the identical payment command using reference "pay-timeout-001"
    Then the client should receive the documented idempotent replay response
    And exactly one durable payment fact should exist for reference "pay-timeout-001"
    And the invoice should be credited by exactly 1000 KES
    And the driver's total paid should increase by exactly 1000 KES

  Scenario: Projection replay does not apply the same payment fact twice
    Given one durable payment fact exists for reference "pay-replay-001"
    And that payment fact has already been included in the billing summary projection
    When the projection consumer receives the same payment fact again
    Then the duplicate event delivery should not increase total paid
    And the duplicate event delivery should not decrease total outstanding
    And the projection checkpoint should remain consistent
    And the projected invoice status should remain "paid"
