# 01 – Theory: Troubleshooting, Data Validation & RCA (40 min · Hinglish)

> **Ek hi example poore session mein:** *ShopKart* naam ki ek e-commerce company.
> Har din subah **6:00 AM** ko vendor ek file bhejta hai → `orders_YYYYMMDD.csv` → Azure Blob ke `input/orders/` folder mein.
> **7:00 AM** pe ADF pipeline `PL_20_Daily_Orders_Load` chalti hai → data Azure SQL mein load hota hai.
> **9:00 AM** pe CEO ka Power BI dashboard "Kal ki sales" dikhata hai.
>
> Agar pipeline fail hui ya galat data load hua → CEO ko galat number dikhega. Isliye troubleshooting + validation + RCA zaroori hai.

```
Vendor ──6:00 AM──► Blob: input/orders/orders_20261001.csv
                         │
                  7:00 AM Trigger (TR_Daily_Orders)
                         │
                         ▼
          ┌──────── PL_20_Daily_Orders_Load ────────┐
          │ 1. File hai ya nahi?   (Get Metadata)    │
          │ 2. Staging mein copy   (Copy → stg.Orders)│
          │ 3. Fact mein load      (SP usp_Load_Orders)│
          │ 4. Validation gate     (SP usp_Validate_Load)│
          │ 5. Log success         (SP usp_Log_Run)  │
          └──────────────────────────────────────────┘
                         │
                         ▼
             Azure SQL: dbo.FactOrders ──9:00 AM──► CEO Dashboard
```

| Time | Topic |
|---|---|
| 0–5 min | Production troubleshooting mindset |
| 5–20 min | 5 common production failures (har ek ka ShopKart example) |
| 20–30 min | SQL fundamentals for validation |
| 30–40 min | Root Cause Analysis (RCA) |

---

## Part 1 – Production troubleshooting mindset (5 min)

**Dev vs Production ka farak:** Development mein error aaya toh aap fix karke dobara chala do. Production mein error aaya toh **business ruk jaata hai**. CEO ka dashboard khaali dikhta hai, finance ki report late ho jaati hai.

**Golden rule:** Pehle **service restore** karo (data load karwao), phir **root cause** dhoondo, phir **dobara na ho** iska intezaam karo.

### Troubleshooting ke 6 steps (yaad rakhne ke liye: **D-I-L-F-V-D**)

| Step | Matlab | ShopKart example |
|---|---|---|
| 1. **D**etect | Pata kaise chala? | Alert email aaya: "PL_20 failed" |
| 2. **I**dentify | Kaunsa pipeline, kaunsi activity, kaunsa error code? | Monitor → `CheckFileExists` → Fail activity → `FILE_NOT_FOUND` |
| 3. **L**ocalize | Problem kahan hai? Source, network, auth, ADF config, ya data? | File naam galat hai – source side |
| 4. **F**ix | Turant workaround | File ko sahi naam se upload karo, rerun |
| 5. **V**erify | Kya sach mein theek hua? | Row count + amount control file se match |
| 6. **D**ocument | RCA likho | "Vendor ne naming convention badla" |

### Error ki "failure type" pehle dekho
- **User configuration issue** → aapki taraf ki galti (config, data, permission). Retry se theek **nahi** hoga.
- **System error** → Azure side ki temporary problem. **Retry** se usually theek ho jaata hai.

---

## Part 2 – 5 Common Production Failures (15 min)

### 2.1 Missing files (file nahi mili)

**Kya hota hai:** Pipeline time pe chali, lekin source file folder mein thi hi nahi. Ya file thi lekin **naam/path alag** tha.

**ShopKart example:** 3 October ko vendor ne file bheji `Orders_20261003.csv` (capital **O**). Pipeline dhoondh rahi thi `orders_20261003.csv`. **Blob storage ke naam case-sensitive hote hain**, isliye ADF ke liye yeh file exist hi nahi karti.

**Error kaisa dikhta hai:**
- Bina check ke: Copy activity → `ErrorCode=UserErrorSourceBlobNotExists` / "The required Blob is missing" / "path does not exist"
- Hamare pipeline mein (Get Metadata check ke saath): `FILE_NOT_FOUND: input/orders/orders_20261003.csv not found`

**Common causes:** vendor late hai · naming convention badal gaya · galat folder · date format galat (trigger ka parameter) · file pehle hi archive/delete ho gayi

**Kaise bachein:** Get Metadata (`exists`) se check karo → clear error message do · Storage event trigger use karo (file aane pe hi pipeline chale) · Vendor ke saath naming contract likho

---

### 2.2 Connectivity issues (network / firewall)

**Kya hota hai:** ADF ko data store tak **raasta hi nahi mil raha**. Credentials sahi hain, lekin network ne rok diya.

**ShopKart example:** Security team ne Azure SQL ke firewall mein "Allow Azure services and resources to access this server" **OFF** kar diya. Agle din 7 AM pe Copy activity fail ho gayi.

**Error kaisa dikhta hai:**
- SQL: `Cannot open server 'sql-...' requested by the login. Client with IP address 'x.x.x.x' is not allowed to access the server` (SQL error **40615**)
- Storage: `This request is not authorized to perform this operation` (403) jab storage firewall "Selected networks" pe ho
- Generic: `A network-related or instance-specific error`, `timeout`, `name could not be resolved`

**Kaise pehchaanein:** Linked service → **Test connection** fail hoga. Error mein IP / firewall / network shabd aayenge.

**Kaise bachein:** Network changes ke liye change-management · Private endpoints / Managed VNet ka sahi design · Har morning ek "health check" pipeline jo saare linked services test kare

---

### 2.3 Authentication failures (login / key / permission)

**Kya hota hai:** Network theek hai, server mil gaya, lekin **"aap kaun ho?"** ka jawab galat hai. Password, key, token ya permission galat ya expire ho gaya.

**ShopKart example:** Security policy ke hisaab se har 90 din mein storage account key **rotate (regenerate)** hoti hai. Admin ne `key1` regenerate kar di. ADF ka `LS_BlobStorage` abhi bhi **purani key** use kar raha hai, toh pipeline fail.

**Error kaisa dikhta hai:**
- Storage: `Server failed to authenticate the request. Make sure the value of Authorization header is formed correctly` (**403 AuthenticationFailed**)
- SQL: `Login failed for user 'sqladmin'` (error **18456**)
- Managed identity: `AuthorizationPermissionMismatch` (RBAC role nahi diya)

**Connectivity vs Authentication – farak samjho:**

| | Connectivity | Authentication |
|---|---|---|
| Sawaal | "Kya main pahunch sakta hoon?" | "Kya mujhe andar aane ki permission hai?" |
| Example | Darwaza band hai (firewall) | Chabi galat hai (password/key) |
| Error words | IP, firewall, network, timeout | login failed, authenticate, 403, unauthorized |

**Kaise bachein:** Secrets **Azure Key Vault** mein rakho (rotate karo toh ADF automatically naya secret le) · **Managed Identity** use karo (koi password hi nahi) · Secret expiry ka calendar/alert rakho

---

### 2.4 Trigger failures (pipeline chali hi nahi, ya galat parameter ke saath chali)

**Kya hota hai:** Pipeline ka code bilkul sahi hai, lekin **trigger** ne use start nahi kiya, ya galat values ke saath start kiya. Yeh sabse "silent" failure hai: **koi error email nahi aata kyunki koi run hi nahi hua!**

**ShopKart example:** Developer ne naya trigger `TR_Daily_Orders` banaya, lekin
1. **Publish/Start karna bhool gaya** → status `Stopped` → 7 AM pe kuch nahi chala. CEO ne 9 AM pe poocha "kal ka data kahan hai?"
2. Start karne ke baad: parameter mein date format `dd-MM-yyyy` likha → pipeline `orders_14102026.csv` dhoondhne lagi → file nahi mili.

**Common causes:**
- Trigger **Stopped** hai / publish nahi hua
- **Time zone** galat: 7:00 UTC = 12:30 PM IST (5.5 ghante late!)
- `trigger().scheduledTime` UTC mein hota hai → raat 12:00–5:30 IST ke beech **date pichle din ki** aati hai
- Storage event trigger: `Microsoft.EventGrid` provider registered nahi hai, ya path filter galat (`begins with` / `ends with`)
- Tumbling window: pichli window fail → dependent window ruk jaati hai

**Kahan dekhein:** Monitor → **Trigger runs** (trigger fire hua ya nahi?) · Manage → **Triggers** (Status: Started/Stopped) · Pipeline run → **Parameters** column (kaunsi value pass hui?)

**Kaise bachein:** "Expected run nahi hua" ka alert (missing-run detection) · Freshness check SQL mein: "kya kal ki date ka data hai?"

---

### 2.5 Data mapping errors (schema / data type problems)

**Kya hota hai:** File mili, connection theek hai, lekin **file ka structure ya values woh nahi jo pipeline expect karti hai**.

**ShopKart example – do types:**
1. **Schema drift:** 4 October ko vendor ne column ka naam `UnitPrice` se badal ke `Unit_Price` kar diya aur naya column `Discount` add kar diya. Copy activity ki mapping mein `UnitPrice` hai → error: `Column 'UnitPrice' specified in column mapping cannot be found in source data` (`UserErrorInvalidColumnMappingColumnNotFound`).
2. **Format/type mismatch:** 5 October ki file mein kuch dates `30/09/2026` (dd/MM/yyyy) format mein hain, ek Quantity `N/A` hai, ek price `12,000.00` (comma ke saath). Database `DATE`, `INT`, `DECIMAL` expect karta hai → conversion fail.

**Sabse khatarnaak case:** Agar mapping **explicit nahi** hai (by-name, automatic), toh missing column error nahi deta. Woh **chupchaap NULL** load ho jaata hai. Pipeline green ✅, data galat ❌.

**Kaise bachein:**
- Staging table mein sab `NVARCHAR` rakho (file hamesha land ho jaaye) → SQL mein `TRY_CONVERT` se convert karo → bad rows ko **reject table** mein daalo
- Get Metadata ka `structure`/`columnCount` field use karke schema check karo
- Vendor ke saath **data contract** (columns, types, formats)

---

### Quick summary table

| Failure | Kahan fail hota hai | Typical error words | First check |
|---|---|---|---|
| Missing file | Get Metadata / Copy source | not exist, missing, 404, FILE_NOT_FOUND | Container mein file ka exact naam |
| Connectivity | Copy / any SQL/Blob activity | IP not allowed, firewall, timeout, network | Linked service → Test connection |
| Authentication | Pehli activity jo store ko touch kare | login failed, authenticate, 403, unauthorized | Key/password/role recently change hua? |
| Trigger | Run hi nahi dikhta / galat parameter | (koi error nahi!) | Monitor → Trigger runs; Manage → Triggers |
| Data mapping | Copy (mapping) / SP (conversion) / Validation | column not found, convert, invalid | File ka header + rejected rows |

---

## Part 3 – SQL Fundamentals for Data Validation (10 min)

**Pipeline green hone ka matlab yeh nahi ki data sahi hai.** Validation = data ko **source se compare** karke prove karna ki woh sahi hai.

**ShopKart example:** 2 October ki pipeline **Succeeded** ✅. Lekin dashboard pe revenue ₹3,47,800 dikh raha hai, jabki actual revenue ₹3,37,300 hai. ₹10,500 zyada, kyunki do orders **duplicate** aaye. Pipeline ne koi error nahi diya, yeh sirf SQL validation se pakda gaya.

### Validation ke 4 levels

| Level | Sawaal | SQL tool | ShopKart check |
|---|---|---|---|
| 1. **Completeness** | Saari rows aayi? | `COUNT(*)` | Control file 22 rows = staging 22 = target 22 + rejected 0 |
| 2. **Accuracy** | Values same hain? | `SUM()`, `EXCEPT`, `HASHBYTES` | Control amount = target `SUM(Amount)` |
| 3. **Validity** | Data business rules follow karta hai? | `WHERE`, `GROUP BY … HAVING`, `LEFT JOIN … IS NULL` | Duplicates, NULLs, orphans, negative qty |
| 4. **Timeliness** | Data time pe aaya? | `MAX(LoadDate)` | Kal ki date ka data hai? |

### SQL building blocks (with ShopKart queries)

**1. COUNT – kitni rows?**
```sql
SELECT COUNT(*) FROM dbo.FactOrders WHERE LoadDate = '2026-10-02';
```

**2. SUM – total match? (control total / checksum)**
```sql
SELECT SUM(Amount) FROM dbo.FactOrders WHERE LoadDate = '2026-10-02';
-- Compare with audit.SourceControl.ExpectedTotalAmount
```

**3. GROUP BY + HAVING – duplicates dhoondo**
```sql
SELECT OrderID, COUNT(*) AS Copies
FROM dbo.FactOrders WHERE LoadDate = '2026-10-02'
GROUP BY OrderID
HAVING COUNT(*) > 1;      -- HAVING = GROUP ke baad filter
```

**4. LEFT JOIN … IS NULL – orphan records (master mein nahi hai)**
```sql
SELECT f.OrderID, f.CustomerID
FROM dbo.FactOrders f
LEFT JOIN dim.Customer c ON c.CustomerID = f.CustomerID
WHERE c.CustomerID IS NULL AND f.CustomerID IS NOT NULL;   -- C999 jaisa customer exist hi nahi karta
```

**5. EXCEPT – row-by-row difference**
```sql
SELECT OrderID, Quantity FROM source_table
EXCEPT
SELECT OrderID, Quantity FROM target_table;   -- jo source mein hai lekin target mein nahi
```
⚠️ `EXCEPT` distinct rows pe kaam karta hai, **duplicates nahi pakadta**. Isliye COUNT bhi zaroori hai.

**6. TRY_CONVERT – safe type conversion**
```sql
SELECT TRY_CONVERT(DATE, '30/09/2026', 23);  -- NULL (format galat) → error nahi, NULL
SELECT TRY_CONVERT(INT, 'N/A');              -- NULL
SELECT TRY_CONVERT(DECIMAL(10,2), '12,000.00'); -- NULL (comma)
```
`CONVERT` error deta hai aur poora load rok deta hai. `TRY_CONVERT` NULL deta hai, toh hum bad rows ko alag (reject) kar sakte hain.

**7. CASE – rule ke hisaab se label lagao**
```sql
SELECT OrderID,
       CASE WHEN Quantity <= 0 THEN 'Invalid qty' ELSE 'OK' END AS QtyCheck
FROM dbo.FactOrders;
```

**8. ROW_NUMBER – duplicate ka impact nikaalo / remove karo**
```sql
SELECT *, ROW_NUMBER() OVER (PARTITION BY OrderID ORDER BY FactID) AS rn
FROM dbo.FactOrders;      -- rn > 1 = extra copy
```

### Critical vs Warning checks
- **CRITICAL** (load rok do): row count mismatch, amount mismatch, rejected rows > 0
- **WARNING** (load hone do, lekin review karo): duplicates, orphan customer, negative qty, unknown status

Hamari SP `audit.usp_Validate_Load` yahi karti hai. Critical fail → `THROW` → ADF activity fail → alert.

---

## Part 4 – Root Cause Analysis (RCA) (10 min)

**RCA = "Kya hua" nahi, "KYUN hua" aur "dobara kaise nahi hoga".**

**Symptom vs Root cause:**
- Symptom: "Pipeline fail ho gayi" ❌ (yeh RCA nahi hai)
- Immediate cause: "File ka naam galat tha"
- **Root cause:** "Vendor ne apna export tool upgrade kiya jisme default naming `Orders_` (capital) hai, aur naming convention kahin likhit contract mein nahi tha"

### Technique 1: 5 Whys (ShopKart, 3 Oct incident)

| Why? | Answer |
|---|---|
| 1. Dashboard pe 3 Oct ka data kyun nahi tha? | Pipeline fail hui |
| 2. Pipeline kyun fail hui? | `FILE_NOT_FOUND`: `orders_20261003.csv` nahi mili |
| 3. File kyun nahi mili? | File `Orders_20261003.csv` naam se aayi thi (capital O), Blob case-sensitive hai |
| 4. Vendor ne naam kyun badla? | Unhone export tool upgrade kiya, naya default naam aa gaya |
| 5. Humein pehle se pata kyun nahi chala? | Naming convention ka koi written data contract nahi tha, aur file arrival ka alert nahi tha |

**Root cause → #5** (process gap), sirf #3 (technical) nahi.

### Technique 2: Fishbone (Ishikawa) – categories for data pipelines

```
 People        Process        Technology
    \             \               \
     \             \               \
      ─────────────────────────────────►  Problem: 3 Oct data missing
     /             /               /
    /             /               /
 Data/Source   Environment     Monitoring
```
Har category mein possible causes likho, phir evidence se ek-ek eliminate karo.

### Blameless culture
RCA mein **"kisne galti ki"** nahi, **"system ne galti hone kyun di"** poochte hain. "Ramesh ne key rotate kar di" ❌ → "Key rotation ka process ADF linked services ko update nahi karta tha" ✅

### RCA report ke sections (template `rca-templates/RCA-Template.md` mein)
1. Incident summary (ID, date, severity, duration)
2. **Impact** (kaunsa data, kitne users/reports, business loss)
3. **Timeline** (detect → respond → resolve, exact times)
4. Detection (kaise pata chala?)
5. Investigation steps + evidence (error message, run ID, SQL output)
6. **Root cause** (5 Whys)
7. Resolution (immediate fix)
8. **Corrective & Preventive Actions (CAPA)** (owner + due date)
9. Lessons learned

### Key metrics
- **MTTD** (Mean Time To Detect): failure se alert tak
- **MTTR** (Mean Time To Resolve): alert se fix tak
- Severity: **Sev1** (CEO dashboard down) → **Sev4** (cosmetic)

---

## Theory recap – 5 questions (2 min, class se poochho)
1. Pipeline Succeeded hai. Kya data sahi hai? → **Zaroori nahi**, validation karo.
2. "Login failed" connectivity hai ya authentication? → **Authentication**
3. Trigger Stopped tha, kaunsa error aaya? → **Koi error nahi**, run hi nahi hua (silent failure)
4. `EXCEPT` duplicates pakadta hai? → **Nahi**, `GROUP BY … HAVING COUNT(*) > 1` use karo
5. "File ka naam galat tha" root cause hai? → **Nahi**, yeh immediate cause hai. Root cause = process/contract gap.

➡️ Ab hands-on shuru: `02-Lab-Setup.md`
