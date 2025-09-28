/* ============================================================
   E) CUSTOMERS (idempotent-ish: seed only if small)
   ============================================================ */
IF (SELECT COUNT(*) FROM zava.Customer) < 5000
BEGIN
    INSERT zava.Customer(first_name, last_name, email, phone, marketing_opt_in)
    SELECT CONCAT(N'Cust', n.n), CONCAT(N'Last', n.n),
           CONCAT('cust', n.n, '@example.com'),
           CONCAT('+1-555-', RIGHT('0000'+CAST(n.n AS varchar(4)), 4)),
           CASE WHEN (n.n % 3)=0 THEN 1 ELSE 0 END
    FROM zava._util_GetNumbers(10000) n;
END