/* ============================================================
   STORES
   ============================================================ */
-- Clear existing (dev only). Comment out in prod-like env.
DELETE FROM zava.Store;

;WITH zCity AS (
    -- 50 cities & time zones roughly distributed (you can edit names)
    SELECT * FROM (VALUES
    (N'NYC-01', N'Zava Coffee Manhattan',  N'New York',        N'USA', N'Eastern Standard Time'),
    (N'BOS-01', N'Zava Coffee Boston',     N'Boston',          N'USA', N'Eastern Standard Time'),
    (N'DC-01',  N'Zava Coffee DC',         N'Washington',      N'USA', N'Eastern Standard Time'),
    (N'MIA-01', N'Zava Coffee Miami',      N'Miami',           N'USA', N'Eastern Standard Time'),
    (N'ATL-01', N'Zava Coffee Atlanta',    N'Atlanta',         N'USA', N'Eastern Standard Time'),
    (N'CLT-01', N'Zava Coffee Charlotte',  N'Charlotte',       N'USA', N'Eastern Standard Time'),
    (N'CHI-01', N'Zava Coffee Chicago',    N'Chicago',         N'USA', N'Central Standard Time'),
    (N'DAL-01', N'Zava Coffee Dallas',     N'Dallas',          N'USA', N'Central Standard Time'),
    (N'HOU-01', N'Zava Coffee Houston',    N'Houston',         N'USA', N'Central Standard Time'),
    (N'AUS-01', N'Zava Coffee Austin',     N'Austin',          N'USA', N'Central Standard Time'),
    (N'STL-01', N'Zava Coffee St Louis',   N'St. Louis',       N'USA', N'Central Standard Time'),
    (N'MSP-01', N'Zava Coffee Minneapolis',N'Minneapolis',     N'USA', N'Central Standard Time'),
    (N'DEN-01', N'Zava Coffee Denver',     N'Denver',          N'USA', N'Mountain Standard Time'),
    (N'PHX-01', N'Zava Coffee Phoenix',    N'Phoenix',         N'USA', N'Mountain Standard Time'),
    (N'SLC-01', N'Zava Coffee Salt Lake',  N'Salt Lake City',  N'USA', N'Mountain Standard Time'),
    (N'SEA-01', N'Zava Coffee Seattle',    N'Seattle',         N'USA', N'Pacific Standard Time'),
    (N'PDX-01', N'Zava Coffee Portland',   N'Portland',        N'USA', N'Pacific Standard Time'),
    (N'SFO-01', N'Zava Coffee SF',         N'San Francisco',   N'USA', N'Pacific Standard Time'),
    (N'SJC-01', N'Zava Coffee San Jose',   N'San Jose',        N'USA', N'Pacific Standard Time'),
    (N'LA-01',  N'Zava Coffee Los Angeles',N'Los Angeles',     N'USA', N'Pacific Standard Time'),
    (N'SD-01',  N'Zava Coffee San Diego',  N'San Diego',       N'USA', N'Pacific Standard Time'),
    (N'SAC-01', N'Zava Coffee Sacramento', N'Sacramento',      N'USA', N'Pacific Standard Time'),
    (N'LV-01',  N'Zava Coffee Las Vegas',  N'Las Vegas',       N'USA', N'Pacific Standard Time'),
    (N'OKC-01', N'Zava Coffee OKC',        N'Oklahoma City',   N'USA', N'Central Standard Time'),
    (N'KC-01',  N'Zava Coffee KC',         N'Kansas City',     N'USA', N'Central Standard Time'),
    (N'NOR-01', N'Zava Coffee New Orleans',N'New Orleans',     N'USA', N'Central Standard Time'),
    (N'NA-01',  N'Zava Coffee Nashville',  N'Nashville',       N'USA', N'Central Standard Time'),
    (N'ORL-01', N'Zava Coffee Orlando',    N'Orlando',         N'USA', N'Eastern Standard Time'),
    (N'TPA-01', N'Zava Coffee Tampa',      N'Tampa',           N'USA', N'Eastern Standard Time'),
    (N'PHI-01', N'Zava Coffee Philly',     N'Philadelphia',    N'USA', N'Eastern Standard Time'),
    (N'PIT-01', N'Zava Coffee Pittsburgh', N'Pittsburgh',      N'USA', N'Eastern Standard Time'),
    (N'RDU-01', N'Zava Coffee Raleigh',    N'Raleigh',         N'USA', N'Eastern Standard Time'),
    (N'CLE-01', N'Zava Coffee Cleveland',  N'Cleveland',       N'USA', N'Eastern Standard Time'),
    (N'CMH-01', N'Zava Coffee Columbus',   N'Columbus',        N'USA', N'Eastern Standard Time'),
    (N'IND-01', N'Zava Coffee Indy',       N'Indianapolis',    N'USA', N'Eastern Standard Time'),
    (N'DET-01', N'Zava Coffee Detroit',    N'Detroit',         N'USA', N'Eastern Standard Time'),
    (N'ATL-02', N'Zava Coffee Midtown ATL',N'Atlanta',         N'USA', N'Eastern Standard Time'),
    (N'NYC-02', N'Zava Coffee Brooklyn',   N'New York',        N'USA', N'Eastern Standard Time'),
    (N'BOS-02', N'Zava Coffee Cambridge',  N'Cambridge',       N'USA', N'Eastern Standard Time'),
    (N'CHI-02', N'Zava Coffee River North',N'Chicago',         N'USA', N'Central Standard Time'),
    (N'DAL-02', N'Zava Coffee Uptown',     N'Dallas',          N'USA', N'Central Standard Time'),
    (N'AUS-02', N'Zava Coffee Domain',     N'Austin',          N'USA', N'Central Standard Time'),
    (N'DEN-02', N'Zava Coffee LoDo',       N'Denver',          N'USA', N'Mountain Standard Time'),
    (N'SEA-02', N'Zava Coffee Ballard',    N'Seattle',         N'USA', N'Pacific Standard Time'),
    (N'LA-02',  N'Zava Coffee Venice',     N'Los Angeles',     N'USA', N'Pacific Standard Time'),
    (N'PDX-02', N'Zava Coffee Pearl',      N'Portland',        N'USA', N'Pacific Standard Time'),
    (N'SF-02',  N'Zava Coffee SOMA',       N'San Francisco',   N'USA', N'Pacific Standard Time'),
    (N'SD-02',  N'Zava Coffee La Jolla',   N'San Diego',       N'USA', N'Pacific Standard Time')
    ) v(code,name,city,country,timezone)
)
INSERT zava.Store(store_code, store_name, city, country, timezone, open_date, status, footfall_index)
SELECT TOP (@StoreCount)
       code, name, city, country, timezone,
       DATEADD(DAY, -ABS(CHECKSUM(code)) % 1200, CAST(SYSDATETIME() AS date)) AS open_date,
       'OPEN' AS status,
       CAST(0.80 + (ABS(CHECKSUM(code)) % 60)/100.0 AS decimal(5,2)) AS footfall_index;
GO