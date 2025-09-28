/* ===========================================================
   Edge / Smart Store – Seed Data Generator
   - Stores + Terminals (incl. KIOSK)
   - Products (Contoso Sneakers)
   - Inventory (per store)
   - Product Embeddings (JSON demo vectors, 64 dims)
   - Local AI Model Registry (Ollama mxbai-embed-large)
   Idempotent: Safe to re-run.
   =========================================================== */

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
DECLARE @EmbeddingDim INT = 64;                       -- Change to 128 if desired
DECLARE @EmbeddingModel NVARCHAR(100) = N'mxbai-embed-large'; -- Demo/model tag
DECLARE @MaxQty INT = 40;                             -- Inventory cap per (store,product)

/* ------------------------------
   Optional: Light reset of demo rows
   (Keeps master data if you comment this out)
   ------------------------------ */
-- DELETE FROM edge.kiosk_search_result;
-- DELETE FROM edge.kiosk_search_query;
-- DELETE FROM edge.kiosk_event;
-- DELETE FROM edge.kiosk_basket_item;
-- DELETE FROM edge.kiosk_session;
-- DELETE FROM edge.pos_txn_line;
-- DELETE FROM edge.pos_txn;
-- DELETE FROM edge.outbox_event;
-- DELETE FROM edge.product_embedding;
-- DELETE FROM edge.inventory;

/* ------------------------------
   1) Stores
   ------------------------------ */
INSERT INTO edge.store (store_code, store_name, time_zone, is_active)
SELECT v.store_code, v.store_name, v.time_zone, 1
FROM (VALUES
   ('DAL01','Contoso Sneakers – Dallas','America/Chicago'),
   ('AUS01','Contoso Sneakers – Austin','America/Chicago'),
   ('SEA01','Contoso Sneakers – Seattle','America/Los_Angeles')
) v(store_code, store_name, time_zone)
WHERE NOT EXISTS (SELECT 1 FROM edge.store s WHERE s.store_code = v.store_code);

/* ------------------------------
   2) Terminals (1 Register + 1 Kiosk per store)
   ------------------------------ */
;WITH st AS (
  SELECT store_id, store_code FROM edge.store WHERE is_active = 1
)
INSERT INTO edge.pos_terminal (store_id, terminal_code, terminal_type, is_active)
SELECT st.store_id, 'REG-01', 'REGISTER', 1
FROM st
WHERE NOT EXISTS (
  SELECT 1 FROM edge.pos_terminal t 
  WHERE t.store_id = st.store_id AND t.terminal_code = 'REG-01'
);

;WITH st AS (
  SELECT store_id, store_code FROM edge.store WHERE is_active = 1
)
INSERT INTO edge.pos_terminal (store_id, terminal_code, terminal_type, is_active)
SELECT st.store_id, 'KSK-01', 'KIOSK', 1
FROM st
WHERE NOT EXISTS (
  SELECT 1 FROM edge.pos_terminal t 
  WHERE t.store_id = st.store_id AND t.terminal_code = 'KSK-01'
);

/* ------------------------------
   3) Products (Contoso Sneakers)
   ------------------------------ */
INSERT INTO edge.product (product_id, product_sku, product_name, category, list_price, tax_rate, is_active)
SELECT v.product_id, v.product_sku, v.product_name, v.category, v.list_price, v.tax_rate, 1
FROM (VALUES
    (1000, 'CS-RUN-001', 'Contoso Runner Lite',         N'Running',   89.99,  0.0825),
    (1001, 'CS-RUN-002', 'Contoso Runner Pro',          N'Running',  129.99,  0.0825),
    (1002, 'CS-RUN-003', 'Contoso Runner Trail',        N'Trail',    119.99,  0.0825),
    (1003, 'CS-RUN-004', 'Contoso Runner Speed',        N'Running',  149.99,  0.0825),
    (1004, 'CS-TRL-001', 'Contoso Trail Grip',          N'Trail',     99.99,  0.0825),
    (1005, 'CS-TRL-002', 'Contoso Trail Max',           N'Trail',    139.99,  0.0825),
    (1006, 'CS-CSL-001', 'Contoso Casual Breeze',       N'Casual',    69.99,  0.0825),
    (1007, 'CS-CSL-002', 'Contoso Casual Canvas',       N'Casual',    59.99,  0.0825),
    (1008, 'CS-CSL-003', 'Contoso Casual Knit',         N'Casual',    79.99,  0.0825),
    (1009, 'CS-CSL-004', 'Contoso Casual Leather',      N'Casual',    99.99,  0.0825),
    (1010, 'CS-BBK-001', 'Contoso Bounce (BBall)',      N'Basketball',119.99, 0.0825),
    (1011, 'CS-BBK-002', 'Contoso Court Pro',           N'Basketball',139.99, 0.0825),
    (1012, 'CS-SKT-001', 'Contoso Street Skater',       N'Skate',      84.99, 0.0825),
    (1013, 'CS-SKT-002', 'Contoso Deck Classic',        N'Skate',      74.99, 0.0825),
    (1014, 'CS-TRN-001', 'Contoso Trainer Flex',        N'Training',   89.99, 0.0825),
    (1015, 'CS-TRN-002', 'Contoso Trainer Power',       N'Training',  109.99, 0.0825),
    (1016, 'CS-TRN-003', 'Contoso Trainer Studio',      N'Training',   99.99, 0.0825),
    (1017, 'CS-ELT-001', 'Contoso Elite Racer',         N'Running',   179.99, 0.0825),
    (1018, 'CS-ELT-002', 'Contoso Elite Carbon',        N'Running',   199.99, 0.0825),
    (1019, 'CS-HIK-001', 'Contoso Hike Mid',            N'Hiking',    129.99, 0.0825),
    (1020, 'CS-HIK-002', 'Contoso Hike Waterproof',     N'Hiking',    149.99, 0.0825),
    (1021, 'CS-SND-001', 'Contoso Sandal Glide',        N'Sandals',    39.99, 0.0825),
    (1022, 'CS-SND-002', 'Contoso Sandal Trek',         N'Sandals',    49.99, 0.0825),
    (1023, 'CS-LIM-001', 'Contoso Limited Edition 2025',N'Special',   249.99, 0.0825)
) v(product_id, product_sku, product_name, category, list_price, tax_rate)
WHERE NOT EXISTS (SELECT 1 FROM edge.product p WHERE p.product_id = v.product_id OR p.product_sku = v.product_sku);

/* ------------------------------
   4) Inventory (per store/product)
      - Deterministic "random" qty
      - Some items set to 0 to simulate OOS
   ------------------------------ */
;WITH s AS (SELECT store_id FROM edge.store WHERE is_active = 1),
      p AS (SELECT product_id FROM edge.product WHERE is_active = 1)
MERGE edge.inventory AS tgt
USING (
  SELECT s.store_id, p.product_id,
         CAST(
           CASE WHEN ABS(CHECKSUM(s.store_id*13 + p.product_id*7)) % 7 = 0 
                THEN 0
                ELSE (ABS(CHECKSUM(s.store_id, p.product_id)) % @MaxQty) + 1
           END AS DECIMAL(18,3)
         ) AS on_hand_qty
  FROM s CROSS JOIN p
) AS src
ON (tgt.store_id = src.store_id AND tgt.product_id = src.product_id)
WHEN MATCHED THEN 
  UPDATE SET tgt.on_hand_qty = src.on_hand_qty, tgt.last_updated_at = @NowUtc
WHEN NOT MATCHED THEN
  INSERT (store_id, product_id, on_hand_qty, last_updated_at)
  VALUES (src.store_id, src.product_id, src.on_hand_qty, @NowUtc);

/* ------------------------------
   5) Product Embeddings (JSON for demo)
      - 64-dim cosine vectors, deterministic per product
      - Good for pure T-SQL vector demo via OPENJSON
   ------------------------------ */

-- Prepare a small dimension table #dim with values 0..(@EmbeddingDim-1)
IF OBJECT_ID('tempdb..#dim') IS NOT NULL DROP TABLE #dim;
CREATE TABLE #dim (n INT NOT NULL PRIMARY KEY);
WITH nums AS (
  SELECT 0 AS n
  UNION ALL SELECT n + 1 FROM nums WHERE n + 1 < @EmbeddingDim
)
INSERT INTO #dim(n) SELECT n FROM nums OPTION (MAXRECURSION 0);

-- Insert embeddings only if not present for the model
INSERT INTO edge.product_embedding (product_id, embedding_json, embedding_dim, embedding_model, created_at_utc)
SELECT p.product_id,
       CONCAT(
         '[',
         STRING_AGG(
           CAST(ROUND(SIN( (p.product_id * 131 + d.n) * 0.37 ), 6) AS NVARCHAR(32))
           , ','
         ) WITHIN GROUP (ORDER BY d.n),
         ']'
       ) AS embedding_json,
       @EmbeddingDim, @EmbeddingModel, @NowUtc
FROM edge.product p
CROSS JOIN #dim d
WHERE NOT EXISTS (
  SELECT 1 FROM edge.product_embedding pe 
  WHERE pe.product_id = p.product_id AND pe.embedding_model = @EmbeddingModel
)
GROUP BY p.product_id;

-- Optional: sanity check
-- SELECT TOP 1 product_id, embedding_dim, embedding_model, LEFT(embedding_json, 120) AS sample_json 
-- FROM edge.product_embedding ORDER BY created_at_utc DESC;

/* ------------------------------
   6) Local AI Model Registry (Ollama)
   ------------------------------ */
INSERT INTO edge.local_ai_model (model_name, provider, model_version, params_json, installed_at)
SELECT @EmbeddingModel, N'ollama', N'latest', N'{"notes":"demo-only embeddings stored as JSON; production should use app-side scoring and VARBINARY vectors."}', @NowUtc
WHERE NOT EXISTS (
  SELECT 1 FROM edge.local_ai_model m WHERE m.model_name = @EmbeddingModel
);

/* ------------------------------
   7) Summary
   ------------------------------ */
PRINT '=== Seed Complete ===';
SELECT 'stores' AS entity, COUNT(*) AS cnt FROM edge.store
UNION ALL SELECT 'terminals', COUNT(*) FROM edge.pos_terminal
UNION ALL SELECT 'products', COUNT(*) FROM edge.product
UNION ALL SELECT 'inventory', COUNT(*) FROM edge.inventory
UNION ALL SELECT 'embeddings', COUNT(*) FROM edge.product_embedding
UNION ALL SELECT 'ai_models', COUNT(*) FROM edge.local_ai_model
ORDER BY entity;