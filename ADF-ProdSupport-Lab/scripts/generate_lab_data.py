"""
generate_lab_data.py
Re-creates every CSV used in the ADF Production Support Readiness lab.
Deterministic (fixed random seed) so every learner gets identical numbers,
which makes reconciliation / health-check answers comparable across the class.

Usage:  python generate_lab_data.py  [output_root]   (default: ../data)
"""
import csv, os, random, sys

random.seed(42)
ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "data")

SALES_HDR = ["order_id", "order_date", "customer_id", "product_id", "quantity", "unit_price", "amount", "store_code"]
CUST_HDR = ["customer_id", "customer_name", "city", "segment", "signup_date"]

FIRST = ["Aarav", "Vivaan", "Aditya", "Ananya", "Diya", "Ishaan", "Kavya", "Rohan", "Saanvi", "Arjun",
         "Meera", "Kabir", "Riya", "Vihaan", "Anika", "Reyansh", "Myra", "Advik", "Tara", "Neel",
         "Zoya", "Dev"]
LAST = ["Sharma", "Verma", "Gupta", "Iyer", "Reddy", "Nair", "Mehta", "Kapoor", "Singh", "Das", "Joshi"]
CITIES = ["Gurugram", "Delhi", "Mumbai", "Bengaluru", "Pune", "Hyderabad", "Chennai", "Kolkata"]
SEGMENTS = ["Retail", "Corporate", "SMB"]
STORES = ["GGN01", "DEL02", "MUM03", "BLR04", "ONLINE"]
PRODUCTS = {f"P{100+i}": p for i, p in enumerate([199.00, 349.50, 999.00, 1499.00, 75.25, 2599.00, 120.00, 455.75, 89.90, 3999.00])}


def w(path, header, rows):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as f:
        cw = csv.writer(f)
        if header:
            cw.writerow(header)
        cw.writerows(rows)
    print("wrote", os.path.relpath(path, ROOT), len(rows), "rows")


def customers(n):
    out = []
    for i in range(n):
        cid = f"C{1001+i}"
        name = f"{FIRST[i % len(FIRST)]} {LAST[i % len(LAST)]}"
        out.append([cid, name, CITIES[i % len(CITIES)], SEGMENTS[i % len(SEGMENTS)], f"2025-{(i % 12)+1:02d}-{(i % 27)+1:02d}"])
    return out


def sales(run_date, start_id, n, max_cust):
    d = f"{run_date[:4]}-{run_date[4:6]}-{run_date[6:]}"
    out = []
    for i in range(n):
        pid = random.choice(list(PRODUCTS))
        qty = random.randint(1, 5)
        price = PRODUCTS[pid]
        out.append([f"SO{start_id+i}", d, f"C{random.randint(1001, max_cust)}", pid, qty, f"{price:.2f}", f"{qty*price:.2f}", random.choice(STORES)])
    return out


# ---------------- GOOD baseline data ----------------
cust20 = customers(20)                     # C1001..C1020
w(f"{ROOT}/good/customers_20261013.csv", CUST_HDR, cust20)
w(f"{ROOT}/good/customers_20261014.csv", CUST_HDR, cust20)
s13 = sales("20261013", 500001, 40, 1020)
s14 = sales("20261014", 510001, 50, 1020)
w(f"{ROOT}/good/sales_20261013.csv", SALES_HDR, s13)
w(f"{ROOT}/good/sales_20261014.csv", SALES_HDR, s14)

# ---------------- FAULT INJECTION files (Lab 3 scenarios) ----------------
# S1 missing file -> no file needed (we simply do not upload sales_20261016.csv)
# S1 late-arriving files (uploaded only when the "vendor" finally delivers)
late = [[r[0].replace("SO51","SO53"), "2026-10-16"] + r[2:] for r in s14]
w(f"{ROOT}/fault_injection/S1_late_sales_20261016.csv", SALES_HDR, late)
w(f"{ROOT}/fault_injection/S1_late_customers_20261016.csv", CUST_HDR, cust20)
# S7 files that arrived ON TIME for 20261017 - but the trigger was stopped, so nothing loaded them
s17 = [[r[0].replace("SO51","SO54"), "2026-10-17"] + r[2:] for r in s14]
w(f"{ROOT}/fault_injection/S7_sales_20261017.csv", SALES_HDR, s17)
w(f"{ROOT}/fault_injection/S7_customers_20261017.csv", CUST_HDR, cust20)
# S2 bad data types: 3 corrupt rows
bad = [r[:] for r in s14]
bad[4][4] = "two"           # quantity not int
bad[17][6] = "N/A"          # amount not decimal
bad[33][1] = "2026-14-10"   # invalid date (month 14)
w(f"{ROOT}/fault_injection/S2_sales_20261014_badtypes.csv", SALES_HDR, bad)
# S3 empty file (header only) - business validation must stop it
w(f"{ROOT}/fault_injection/S3_sales_20261014_empty.csv", SALES_HDR, [])
# S6 duplicate rows inside the source file
dup = s14 + [s14[2][:], s14[9][:], s14[21][:]]
w(f"{ROOT}/fault_injection/S6b_sales_20261014_duplicates.csv", SALES_HDR, dup)

# ---------------- E2E exercise (business date 20261015) ----------------
cust22 = customers(22)                     # adds new customers C1021, C1022
s15 = sales("20261015", 520001, 60, 1020)
# force some orders onto the brand-new customers so missing them = orphans
for idx, cid in [(5, "C1021"), (12, "C1021"), (30, "C1022"), (44, "C1022"), (51, "C1021")]:
    s15[idx][2] = cid
w(f"{ROOT}/e2e/sales_20261015.csv", SALES_HDR, s15)
# Stage 1 file from 'vendor': header renamed customer_id -> cust_id AND missing new customers
renamed_hdr = ["cust_id"] + CUST_HDR[1:]
w(f"{ROOT}/e2e/customers_20261015.csv", renamed_hdr, cust20)
# Stage 2 vendor re-send: header fixed, but still missing C1021/C1022
w(f"{ROOT}/e2e/customers_20261015_resend1.csv", CUST_HDR, cust20)
# Stage 3 final correct file
w(f"{ROOT}/corrected/customers_20261015.csv", CUST_HDR, cust22)
w(f"{ROOT}/corrected/sales_20261014.csv", SALES_HDR, s14)   # clean copy for recovery

# answer key numbers for instructor
def tot(rows):
    return round(sum(float(r[6]) for r in rows), 2)
with open(f"{ROOT}/EXPECTED_VALUES.md", "w", encoding="utf-8") as f:
    f.write("# Expected values (answer key for reconciliation)\n\n")
    f.write("| File | Rows | Sum(amount) |\n|---|---|---|\n")
    f.write(f"| sales_20261013.csv | {len(s13)} | {tot(s13)} |\n")
    f.write(f"| sales_20261014.csv | {len(s14)} | {tot(s14)} |\n")
    f.write(f"| sales_20261015.csv | {len(s15)} | {tot(s15)} |\n")
    f.write(f"| customers (good / resend1) | 20 | - |\n| customers (corrected 20261015) | 22 | - |\n\n")
    orphan = [r for r in s15 if r[2] in ("C1021", "C1022")]
    f.write(f"E2E stage-2 orphan sales rows (customer not in DimCustomer): **{len(orphan)}** rows, amount **{tot(orphan)}**\n\n")
    f.write("S6 duplicate scenario: after the non-idempotent load runs once more on top of the good 20261014 load, FactSales holds "
            f"**{2*len(s14)}** rows for LoadDate 20261014 (expected {len(s14)}).\n")
print("done")
