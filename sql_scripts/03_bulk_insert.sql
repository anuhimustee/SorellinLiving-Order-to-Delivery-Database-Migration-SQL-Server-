/* =============================================================================
   Operation RouteGlass | Script 03 : Load the CSV into staging
   Author	: Mustapha (Sir Mustee)
   =============================================================================
 */

USE SorellinLivingDB;
GO

-- Empty staging so a rerun never doubles the rows
TRUNCATE TABLE stg.Legacy_Extract_Raw;
GO

BULK INSERT stg.Legacy_Extract_Raw
-- Change it to your own file path
FROM 'C:\Users\musta\Desktop\ANUHI\02_Sorellin_Legacy_Order_Delivery_Extract.csv'
WITH
(
    FORMAT          = 'CSV',     -- proper CSV parsing: "12,48" stays one field
    FIELDQUOTE      = '"',       -- quote character used in the file
    FIELDTERMINATOR = ',',       -- columns are comma-separated
    ROWTERMINATOR   = '0x0a',    -- rows end with LF (the file has no CR)
    FIRSTROW        = 2,         -- skip the header row
    CODEPAGE        = '65001',   -- file is UTF-8 (keeps accented characters)
    KEEPNULLS,                   -- empty fields load as NULL
    MAXERRORS       = 0,         -- stop on any bad row; never skip silently
    TABLOCK                      -- faster load
);
GO

/* ---------------------------------------------------------------------------
   Validation Checks...
   --------------------------------------------------------------------------- */

-- 1. Row count must equal the 18,000 data rows in the file
SELECT 'Staging Bulk Load Execution Verification' AS CheckName,
        COUNT(*) AS Staged_Rows,
       CASE WHEN COUNT(*) = 18000 THEN 'PASSED (18,000 Rows Exact)' ELSE 'WARNING: Row Count Mistmatch'
            END AS LoadStatus
FROM   stg.Legacy_Extract_Raw;


-- 2. Columns lined up correctly (first and last columns hold expected values)
SELECT COUNT(*) AS Misaligned_Rows   -- ex  pected: 0
FROM   stg.Legacy_Extract_Raw
WHERE  Legacy_Row_ID NOT LIKE 'SCL-%'
   OR  Tracking_Event_ID NOT LIKE 'EVT-%'
   OR  Currency IS NULL;

-- 3. Accents decoded correctly (should show Düsseldorf, not DÃ¼sseldorf)
SELECT DISTINCT Warehouse_Name
FROM   stg.Legacy_Extract_Raw
WHERE  Warehouse_Name LIKE N'D%sseldorf%';

-- 4. Quick look at the first rows
SELECT TOP (5) *
FROM   stg.Legacy_Extract_Raw;
GO


PRINT '============================================================';
PRINT 'CSV LOADING INTO STAGING COMPLETE';
PRINT 'BULK INSERT';
PRINT '============================================================';
GO