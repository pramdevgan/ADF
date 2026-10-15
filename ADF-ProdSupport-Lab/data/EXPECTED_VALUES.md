# Expected values (answer key for reconciliation)

| File | Rows | Sum(amount) |
|---|---|---|
| sales_20261013.csv | 40 | 126957.5 |
| sales_20261014.csv | 50 | 144809.95 |
| sales_20261015.csv | 60 | 186667.3 |
| customers (good / resend1) | 20 | - |
| customers (corrected 20261015) | 22 | - |

E2E stage-2 orphan sales rows (customer not in DimCustomer): **5** rows, amount **11320.9**

S6 duplicate scenario: after the non-idempotent load runs once more on top of the good 20261014 load, FactSales holds **100** rows for LoadDate 20261014 (expected 50).
