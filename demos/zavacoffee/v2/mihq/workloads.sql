CREATE TABLE core.current_price_cache (
    store_id    INT NOT NULL,
    product_id  BIGINT NOT NULL,
    price       DECIMAL(19,4) NOT NULL,
    asof_utc    DATETIME2(3)  NOT NULL,
    CONSTRAINT PK_current_price_cache PRIMARY KEY (store_id, product_id)
);

CREATE OR ALTER PROCEDURE core.rebuild_current_price_cache
AS
BEGIN
  SET NOCOUNT ON;
  ;WITH candidates AS (
    SELECT p.product_id, s.store_id
    FROM core.product p
    CROSS JOIN core.store s
    WHERE p.is_active = 1 AND s.is_active = 1
  ),
  latest AS (
    SELECT c.store_id, c.product_id,
           COALESCE(
             (SELECT TOP (1) pc.new_price 
              FROM core.price_change pc
              WHERE pc.product_id = c.product_id
                AND (pc.store_id = c.store_id OR pc.store_id IS NULL)
                AND pc.effective_utc <= SYSUTCDATETIME()
              ORDER BY pc.effective_utc DESC),
             (SELECT list_price FROM core.product p WHERE p.product_id = c.product_id)
           ) AS price
    FROM candidates c
  )
  MERGE core.current_price_cache AS tgt
  USING (
    SELECT l.store_id, l.product_id, l.price, SYSUTCDATETIME() AS asof_utc
    FROM latest l
  ) AS src
  ON (tgt.store_id = src.store_id AND tgt.product_id = src.product_id)
  WHEN MATCHED AND tgt.price <> src.price THEN
      UPDATE SET price = src.price, asof_utc = src.asof_utc
  WHEN NOT MATCHED THEN
      INSERT (store_id, product_id, price, asof_utc)
      VALUES (src.store_id, src.product_id, src.price, src.asof_utc);
END
