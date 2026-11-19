/* =============================================================================
   Operation RouteGlass | Script 04 : Profile and clean
   Author	: Mustapha (Sir Mustee)
   =============================================================================
   PART A  Profile the raw data (read-only). Run any query on its own.
   PART B  Mapping tables: one standard value for each source value
   PART C  Exception log: one row per value removed, changed or flagged
   PART D  Clean: 18,000 raw -> 17,860 unique -> 17,796 clean events
   PART E  Evidence for the report

   Tables created
     stg.Extract_Unique   raw rows with exact duplicates removed
     stg.Clean_Extract    trimmed, typed, standardised, one row per event
     map.Country, map.Carrier, map.Location
     audit.Exception_Log

   Rules
     - stg.Legacy_Extract_Raw is never changed.
     - Nothing is removed or changed without a row in audit.Exception_Log.
     - Blanks that are correct (no delivery date yet) stay NULL.

   Rerun : safe. Parts B, C and D must be run together, in order.
   ============================================================================= */

USE SorellinLivingDB;
GO
SET NOCOUNT ON;
SET NOEXEC OFF;
GO


/* #############################################################################
   PART A : PROFILE THE RAW DATA  (expected results shown in the comments)
   ############################################################################# */

-- A1. Volume and distinct business keys
SELECT  COUNT(*)                                          AS Source_Rows,      -- 18,000
        COUNT(DISTINCT Legacy_Row_ID)                     AS Legacy_Row_IDs,   -- 17,860
        COUNT(DISTINCT Tracking_Event_ID)                 AS Tracking_Events,  -- 17,860
        COUNT(DISTINCT Order_No)                          AS Orders,           -- 1,509
        COUNT(DISTINCT CONCAT(Order_No, '|', Order_Line_No))       AS Order_Lines,     -- 2,974
        COUNT(DISTINCT Shipment_No)                       AS Shipments,        -- 1,689
        COUNT(DISTINCT CONCAT(Shipment_No, '|', Order_Line_No))    AS Shipment_Lines,  -- 2,974
        COUNT(DISTINCT Customer_ID)                       AS Customers,        -- 972
        COUNT(DISTINCT Product_SKU)                       AS Products,         -- 72
        COUNT(DISTINCT Warehouse_Code)                    AS Warehouses,       -- 4
        COUNT(DISTINCT Carrier_Code)                      AS Carriers,         -- 6
        COUNT(DISTINCT Event_Location)                    AS Event_Locations,  -- 9
        COUNT(DISTINCT Tracking_Event_Code)               AS Event_Types       -- 6
FROM    stg.Legacy_Extract_Raw;

-- A2. Grain: one row = one tracking event for one shipment line.
--     Split shipments: 1,329 orders have 1 shipment, 180 have 2.
SELECT   Shipments_Per_Order, COUNT(*) AS Orders
FROM    (SELECT Order_No, COUNT(DISTINCT Shipment_No) AS Shipments_Per_Order
         FROM   stg.Legacy_Extract_Raw
         GROUP BY Order_No) AS o
GROUP BY Shipments_Per_Order
ORDER BY Shipments_Per_Order;

-- A3. Exact duplicates: 18,000 rows - 17,860 IDs = 140 extra copies.
--     Step D1 proves that a repeated Legacy_Row_ID is always a full copy.
SELECT  COUNT(*)                                 AS Source_Rows,
        COUNT(DISTINCT Legacy_Row_ID)            AS Distinct_Legacy_Row_IDs,
        COUNT(*) - COUNT(DISTINCT Legacy_Row_ID) AS Exact_Duplicate_Copies
FROM    stg.Legacy_Extract_Raw;

-- A4. Repeated scans: same shipment line, event, time and location, new event ID.
--     Expected: DISPATCHED 18, HUB_OUT 18, HUB_IN 14, OUT_FOR_DELIVERY 14 = 64
SELECT   Tracking_Event_Code,
         COUNT(DISTINCT Tracking_Event_ID)
           - COUNT(DISTINCT CONCAT(Shipment_No, '|', Order_Line_No, '|',
                                   Tracking_Event_DateTime, '|', Event_Location)) AS Extra_Scans
FROM     stg.Legacy_Extract_Raw
GROUP BY Tracking_Event_Code
ORDER BY Extra_Scans DESC;

-- A5. Blanks per column. Only 6 columns have blanks:
--     Exception_Code, Exception_Description                                 17,102
--     Delivery_DateTime, Proof_of_Delivery_Ref, On_Time_Flag_Legacy,
--     Delivery_Days_Legacy                                                  15,000
--     Every other column                                                         0
SELECT   Column_Name, 18000 - COUNT(*) AS Blank_Rows
FROM     stg.Legacy_Extract_Raw
UNPIVOT (Value FOR Column_Name IN
         (Legacy_Row_ID, Order_No, Order_DateTime, Customer_ID, Customer_Name, Customer_Email,
          Customer_Type, Delivery_Address_Line, Delivery_City, Delivery_Postal_Code, Delivery_Country,
          Sales_Channel, Order_Status, Order_Line_No, Product_SKU, Product_Name, Product_Category,
          Unit_Weight_kg, Unit_Price_EUR, Quantity_Ordered, Warehouse_Code, Warehouse_Name,
          Warehouse_City, Warehouse_Country, Shipment_No, Shipment_Created_DateTime,
          Shipment_Line_Quantity, Carrier_Code, Carrier_Name, Carrier_Service_Level, Tracking_No,
          Planned_Dispatch_Date, Actual_Dispatch_DateTime, Promised_Delivery_Date, Tracking_Event_ID,
          Event_Sequence_Legacy, Tracking_Event_Code, Tracking_Event_Description,
          Tracking_Event_DateTime, Event_Location, Event_City, Event_Country, Delivery_DateTime,
          Exception_Code, Exception_Description, Proof_of_Delivery_Ref, Freight_Cost_EUR, Currency,
          On_Time_Flag_Legacy, Delivery_Days_Legacy)
        ) AS u
WHERE    TRIM(Value) <> N''
GROUP BY Column_Name
ORDER BY Blank_Rows DESC, Column_Name;

 

-- A7. Invalid types: decimals written with a comma
SELECT  SUM(CASE WHEN Unit_Weight_kg   LIKE '%,%' THEN 1 ELSE 0 END) AS Weight_With_Comma,   -- 216
        SUM(CASE WHEN Unit_Price_EUR   LIKE '%,%' THEN 1 ELSE 0 END) AS Price_With_Comma,    -- 184
        SUM(CASE WHEN Freight_Cost_EUR LIKE '%,%' THEN 1 ELSE 0 END) AS Freight_With_Comma   -- 229
FROM    stg.Legacy_Extract_Raw;

-- A8. Values that still cannot be converted after the comma fix (all expected 0).
--     COUNT(column) counts filled values; COUNT(TRY_CONVERT) counts the ones that convert.
SELECT  COUNT(Unit_Weight_kg)   - COUNT(TRY_CONVERT(DECIMAL(8, 3),  REPLACE(Unit_Weight_kg,   ',', '.'))) AS Bad_Weight,
        COUNT(Unit_Price_EUR)   - COUNT(TRY_CONVERT(DECIMAL(10, 2), REPLACE(Unit_Price_EUR,   ',', '.'))) AS Bad_Price,
        COUNT(Freight_Cost_EUR) - COUNT(TRY_CONVERT(DECIMAL(10, 2), REPLACE(Freight_Cost_EUR, ',', '.'))) AS Bad_Freight,
        COUNT(Order_Line_No)          - COUNT(TRY_CONVERT(INT, Order_Line_No))          AS Bad_Order_Line_No,
        COUNT(Quantity_Ordered)       - COUNT(TRY_CONVERT(INT, Quantity_Ordered))       AS Bad_Quantity,
        COUNT(Shipment_Line_Quantity) - COUNT(TRY_CONVERT(INT, Shipment_Line_Quantity)) AS Bad_Shipped_Qty,
        COUNT(Order_DateTime)            - COUNT(TRY_CONVERT(DATETIME2(0), Order_DateTime, 120))            AS Bad_Order_Date,
        COUNT(Shipment_Created_DateTime) - COUNT(TRY_CONVERT(DATETIME2(0), Shipment_Created_DateTime, 120)) AS Bad_Created_Date,
        COUNT(Tracking_Event_DateTime)   - COUNT(TRY_CONVERT(DATETIME2(0), Tracking_Event_DateTime, 120))   AS Bad_Event_Date,
        COUNT(Actual_Dispatch_DateTime)  - COUNT(TRY_CONVERT(DATETIME2(0), Actual_Dispatch_DateTime, 120))  AS Bad_Dispatch_Date,
        COUNT(Delivery_DateTime)         - COUNT(TRY_CONVERT(DATETIME2(0), Delivery_DateTime, 120))         AS Bad_Delivery_Date,
        COUNT(Planned_Dispatch_Date)     - COUNT(TRY_CONVERT(DATE, Planned_Dispatch_Date, 23))              AS Bad_Planned_Date,
        COUNT(Promised_Delivery_Date)    - COUNT(TRY_CONVERT(DATE, Promised_Delivery_Date, 23))             AS Bad_Promised_Date
FROM    stg.Legacy_Extract_Raw;

-- A9. Carrier name variants. Expected: C01 has 4 spellings.
--     BIN2 makes the grouping case-sensitive; the brackets show extra spaces.
SELECT   Carrier_Code, Name_As_Stored, COUNT(*) AS Row_Count
FROM    (SELECT Carrier_Code,
                N'[' + Carrier_Name + N']' COLLATE Latin1_General_100_BIN2 AS Name_As_Stored
         FROM   stg.Legacy_Extract_Raw) AS r
GROUP BY Carrier_Code, Name_As_Stored
ORDER BY Carrier_Code, Row_Count DESC;

-- A10. Country labels. Expected: "NL" on 72 rows (59 customers)
SELECT   Delivery_Country, COUNT(*) AS Row_Count, COUNT(DISTINCT Customer_ID) AS Customers
FROM     stg.Legacy_Extract_Raw
GROUP BY Delivery_Country
ORDER BY Row_Count DESC;

-- A11. Scan locations. Expected: each of the 5 carrier hubs appears with all
--      4 countries (Event_Country is unreliable), and "Rotterdam Gateway" is
--      stored as a city name.
SELECT   Event_Location,
         MIN(Event_City)               AS Event_City_Value,
         COUNT(DISTINCT Event_City)    AS City_Values,
         COUNT(DISTINCT Event_Country) AS Country_Values,
         COUNT(*)                      AS Row_Count
FROM     stg.Legacy_Extract_Raw
GROUP BY Event_Location
ORDER BY Event_Location;

-- A12. Order_Status is a row-level value: "Delivered" appears only on DELIVERED
--      event rows, so it is derived from events, not stored.
SELECT   Order_Status, Tracking_Event_Code, COUNT(*) AS Row_Count
FROM     stg.Legacy_Extract_Raw
GROUP BY Order_Status, Tracking_Event_Code
ORDER BY Order_Status, Tracking_Event_Code;

-- A13. Sales_Channel changes inside the same order (1,507 of 1,509 orders),
--      so there is no reliable value to store.
SELECT  COUNT(*)                                      AS Orders,
        SUM(CASE WHEN Channels > 1 THEN 1 ELSE 0 END) AS Orders_With_Mixed_Channel
FROM   (SELECT Order_No, COUNT(DISTINCT Sales_Channel) AS Channels
        FROM   stg.Legacy_Extract_Raw
        GROUP BY Order_No) AS o;

-- A14. Currency is always EUR (1 value).
SELECT 
    COUNT(DISTINCT Currency) AS Currency_Values 
FROM stg.Legacy_Extract_Raw;

-- A15. Period check. Stated period is Jan-Dec 2025. Expected: 4 orders in 2026.
SELECT  MIN(Order_DateTime) AS First_Order,
        MAX(Order_DateTime) AS Last_Order,
        COUNT(DISTINCT CASE WHEN Order_DateTime >= '2026-01-01' THEN Order_No END) AS Orders_In_2026
FROM    stg.Legacy_Extract_Raw;
GO


/* #############################################################################
   PART B : MAPPING TABLES
   ############################################################################# */

-- B1. Country: maps the "NL" alias to the full name
DROP TABLE IF EXISTS map.Country;
CREATE TABLE map.Country
(
    Source_Value  NVARCHAR(50) NOT NULL PRIMARY KEY,
    Country_Name  NVARCHAR(40) NOT NULL
);
INSERT INTO map.Country (Source_Value, Country_Name)
VALUES (N'Netherlands', N'Netherlands'),
       (N'NL',          N'Netherlands'),
       (N'Belgium',     N'Belgium'),
       (N'Germany',     N'Germany'),
       (N'France',      N'France'),
       (N'Luxembourg',  N'Luxembourg'),
       (N'Austria',     N'Austria');

-- B2. Carrier: one standard name per carrier code, plus its tracking prefix
DROP TABLE IF EXISTS map.Carrier;
CREATE TABLE map.Carrier
(
    Carrier_Code     NVARCHAR(10)  NOT NULL PRIMARY KEY,
    Carrier_Name     NVARCHAR(100) NOT NULL,
    Tracking_Prefix  NVARCHAR(4)   NOT NULL
);
INSERT INTO map.Carrier (Carrier_Code, Carrier_Name, Tracking_Prefix)
VALUES (N'C01', N'NordRoute Logistics N.V.',       N'NRLG'),
       (N'C02', N'Alpina Parcel Systems GmbH',     N'APSG'),
       (N'C03', N'Veloria Express S.A.',           N'VEXS'),
       (N'C04', N'Rhenovia Freight B.V.',          N'RHNV'),
       (N'C05', N'Cedrona Delivery Partners S.A.', N'CDRP'),
       (N'C06', N'Fennora RoadLink A/S',           N'FNRA');

-- B3. Location: each scan point with its type, city and country.
--     City and country come from here, never from Event_City or Event_Country.
--     Hub countries are the real location of each hub: an assumption stated in
--     the report, because the source country for hubs is unreliable.
DROP TABLE IF EXISTS map.Location;
CREATE TABLE map.Location
(
    Location_Name  NVARCHAR(100) NOT NULL PRIMARY KEY,
    Location_Type  NVARCHAR(10)  NOT NULL,
    City_Name      NVARCHAR(60)  NOT NULL,
    Country_Name   NVARCHAR(40)  NOT NULL
);
INSERT INTO map.Location (Location_Name, Location_Type, City_Name, Country_Name)
VALUES (N'Antwerp Cross-Dock',             N'Warehouse', N'Antwerp',    N'Belgium'),
       (N'Düsseldorf Distribution Centre', N'Warehouse', N'Düsseldorf', N'Germany'),
       (N'Lille Regional Hub',             N'Warehouse', N'Lille',      N'France'),
       (N'Rotterdam Fulfilment Campus',    N'Warehouse', N'Rotterdam',  N'Netherlands'),
       (N'Cologne Hub',                    N'Hub',       N'Cologne',    N'Germany'),
       (N'Liège Hub',                      N'Hub',       N'Liège',      N'Belgium'),
       (N'Lille Hub',                      N'Hub',       N'Lille',      N'France'),
       (N'Rotterdam Gateway',              N'Hub',       N'Rotterdam',  N'Netherlands'),
       (N'Venlo Hub',                      N'Hub',       N'Venlo',      N'Netherlands');
GO


/* #############################################################################
   PART C : EXCEPTION LOG
   ############################################################################# */

DROP TABLE IF EXISTS audit.Exception_Log;
CREATE TABLE audit.Exception_Log
(
    Log_ID         INT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
    Rule_Code      VARCHAR(40)   NOT NULL,   -- e.g. EXACT_DUPLICATE, REPEATED_SCAN
    Issue_Class    VARCHAR(30)   NOT NULL
        CHECK (Issue_Class IN ('Data defect', 'Source-system rule',
                               'Legitimate repetition', 'Not applicable')),
    Action_Taken   VARCHAR(15)   NOT NULL
        CHECK (Action_Taken IN ('Rejected', 'Standardised', 'Excluded', 'Flagged')),
    Legacy_Row_ID  NVARCHAR(50)  NULL,       -- source row, when the issue is row-level
    Business_Key   NVARCHAR(200) NULL,       -- e.g. SHP-0000059-1 | line 2 | HUB_IN
    Column_Name    NVARCHAR(128) NULL,
    Source_Value   NVARCHAR(255) NULL,
    Clean_Value    NVARCHAR(255) NULL,
    Logged_At      DATETIME2(0)  NOT NULL DEFAULT (SYSDATETIME())
);
GO


/* #############################################################################
   PART D : CLEAN
   ############################################################################# */

/* -----------------------------------------------------------------------------
   D1. Remove exact duplicates  (18,000 -> 17,860)
   ----------------------------------------------------------------------------- */
-- Log the 140 extra copies
WITH Copies AS
(
    SELECT Legacy_Row_ID, Shipment_No, Order_Line_No, Tracking_Event_Code,
           ROW_NUMBER() OVER (PARTITION BY Legacy_Row_ID ORDER BY Legacy_Row_ID) AS Copy_No
    FROM   stg.Legacy_Extract_Raw
)
INSERT INTO audit.Exception_Log
       (Rule_Code, Issue_Class, Action_Taken, Legacy_Row_ID, Business_Key, Column_Name, Source_Value, Clean_Value)
SELECT 'EXACT_DUPLICATE', 'Data defect', 'Rejected', Legacy_Row_ID,
       CONCAT(Shipment_No, ' | line ', Order_Line_No, ' | ', Tracking_Event_Code),
       N'(whole row)', CONCAT(N'copy ', Copy_No), N'one copy kept'
FROM   Copies
WHERE  Copy_No > 1;

-- Keep one copy of each row
DROP TABLE IF EXISTS stg.Extract_Unique;
SELECT DISTINCT *
INTO   stg.Extract_Unique
FROM   stg.Legacy_Extract_Raw;
GO

-- Guard: one row per Legacy_Row_ID proves every repeat was a full copy.
IF (SELECT COUNT(*) FROM stg.Extract_Unique)
   <> (SELECT COUNT(DISTINCT Legacy_Row_ID) FROM stg.Extract_Unique)
BEGIN
    RAISERROR('A Legacy_Row_ID has rows with different content. Script stopped.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* -----------------------------------------------------------------------------
   D2. Build the clean table: trim text, convert types, apply the mappings.
       Src_ columns keep the original value of anything standardised, so D5 and
       D6 can log it from this one table, with no extra joins.
       Not migrated later: Order_Status (derived from events) and
       Currency (always EUR; amounts are already _EUR). Both stay in staging.
   ----------------------------------------------------------------------------- */
DROP TABLE IF EXISTS stg.Clean_Extract;

SELECT
    -- order and customer
    TRIM(u.Legacy_Row_ID)                                      AS Legacy_Row_ID,
    TRIM(u.Order_No)                                           AS Order_No,
    TRY_CONVERT(DATETIME2(0), u.Order_DateTime, 120)           AS Order_DateTime,
    TRIM(u.Customer_ID)                                        AS Customer_ID,
    TRIM(u.Customer_Name)                                      AS Customer_Name,
    TRIM(u.Customer_Email)                                     AS Customer_Email,
    TRIM(u.Customer_Type)                                      AS Customer_Type,
    NULLIF(TRIM(u.Delivery_Address_Line), N'')                 AS Delivery_Address_Line,
    NULLIF(TRIM(u.Delivery_City), N'')                         AS Delivery_City,
    NULLIF(TRIM(u.Delivery_Postal_Code), N'')                  AS Delivery_Postal_Code,
    mc.Country_Name                                            AS Delivery_Country,    -- NL -> Netherlands
    -- order line and product
    TRY_CONVERT(INT, u.Order_Line_No)                          AS Order_Line_No,
    TRIM(u.Product_SKU)                                        AS Product_SKU,
    TRIM(u.Product_Name)                                       AS Product_Name,
    TRIM(u.Product_Category)                                   AS Product_Category,
    TRY_CONVERT(DECIMAL(8, 3),  REPLACE(u.Unit_Weight_kg, ',', '.'))   AS Unit_Weight_kg,   -- "1,25" -> 1.250
    TRY_CONVERT(DECIMAL(10, 2), REPLACE(u.Unit_Price_EUR, ',', '.'))   AS Unit_Price_EUR,
    TRY_CONVERT(INT, u.Quantity_Ordered)                       AS Quantity_Ordered,
    -- warehouse
    TRIM(u.Warehouse_Code)                                     AS Warehouse_Code,
    TRIM(u.Warehouse_Name)                                     AS Warehouse_Name,
    TRIM(u.Warehouse_City)                                     AS Warehouse_City,
    TRIM(u.Warehouse_Country)                                  AS Warehouse_Country,
    -- shipment and carrier
    TRIM(u.Shipment_No)                                        AS Shipment_No,
    TRY_CONVERT(DATETIME2(0), u.Shipment_Created_DateTime, 120) AS Shipment_Created_DateTime,
    TRY_CONVERT(INT, u.Shipment_Line_Quantity)                 AS Shipment_Line_Quantity,
    TRIM(u.Carrier_Code)                                       AS Carrier_Code,
    mk.Carrier_Name                                            AS Carrier_Name,        -- one name per code
    TRIM(u.Carrier_Service_Level)                              AS Carrier_Service_Level,
    TRIM(u.Tracking_No)                                        AS Tracking_No,
    TRY_CONVERT(DATE, u.Planned_Dispatch_Date, 23)             AS Planned_Dispatch_Date,
    TRY_CONVERT(DATETIME2(0), u.Actual_Dispatch_DateTime, 120) AS Actual_Dispatch_DateTime,
    TRY_CONVERT(DATE, u.Promised_Delivery_Date, 23)            AS Promised_Delivery_Date,
    TRY_CONVERT(DECIMAL(10, 2), REPLACE(u.Freight_Cost_EUR, ',', '.')) AS Freight_Cost_EUR,
    -- tracking event
    TRIM(u.Tracking_Event_ID)                                  AS Tracking_Event_ID,
    TRY_CONVERT(INT, u.Event_Sequence_Legacy)                  AS Event_Sequence,
    TRIM(u.Tracking_Event_Code)                                AS Tracking_Event_Code,
    TRIM(u.Tracking_Event_Description)                         AS Tracking_Event_Description,
    TRY_CONVERT(DATETIME2(0), u.Tracking_Event_DateTime, 120)  AS Tracking_Event_DateTime,
    TRIM(u.Event_Location)                                     AS Event_Location,
    ml.Location_Type                                           AS Location_Type,
    ml.City_Name                                               AS Event_City,          -- from map.Location
    ml.Country_Name                                            AS Event_Country,       -- from map.Location
    -- conditional fields: blank stays NULL (not applicable yet)
    TRY_CONVERT(DATETIME2(0), u.Delivery_DateTime, 120)        AS Delivery_DateTime,
    NULLIF(TRIM(u.Exception_Code), N'')                        AS Exception_Code,
    NULLIF(TRIM(u.Exception_Description), N'')                 AS Exception_Description,
    NULLIF(TRIM(u.Proof_of_Delivery_Ref), N'')                 AS Proof_of_Delivery_Ref,
    NULLIF(TRIM(u.On_Time_Flag_Legacy), N'')                   AS On_Time_Flag_Legacy,
    TRY_CONVERT(INT, u.Delivery_Days_Legacy)                   AS Delivery_Days_Legacy,
    -- original values, used only by the exception log
    u.Unit_Weight_kg                                           AS Src_Unit_Weight_kg,
    u.Unit_Price_EUR                                           AS Src_Unit_Price_EUR,
    u.Freight_Cost_EUR                                         AS Src_Freight_Cost_EUR,
    u.Carrier_Name                                             AS Src_Carrier_Name,
    u.Delivery_Country                                         AS Src_Delivery_Country,
    u.Event_City                                               AS Src_Event_City,
    u.Event_Country                                            AS Src_Event_Country,
    u.Sales_Channel                                            AS Src_Sales_Channel
INTO    stg.Clean_Extract
FROM    stg.Extract_Unique AS u
LEFT JOIN map.Country  AS mc ON mc.Source_Value  = TRIM(u.Delivery_Country)
LEFT JOIN map.Carrier  AS mk ON mk.Carrier_Code  = TRIM(u.Carrier_Code)
LEFT JOIN map.Location AS ml ON ml.Location_Name = TRIM(u.Event_Location);
GO

-- This index keeps each shipment line's events together in journey order,
-- which is what makes the checks in D3 and D6 run in seconds.
CREATE CLUSTERED INDEX CX_Clean_Extract_Line
    ON stg.Clean_Extract (Shipment_No, Order_Line_No, Event_Sequence);
GO

/* -----------------------------------------------------------------------------
   D3. Guard: every value mapped and converted, otherwise the script stops so
       nothing is carried forward silently. (A8 shows the counts.)
   ----------------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM stg.Clean_Extract
           WHERE  Delivery_Country IS NULL OR Carrier_Name IS NULL OR Event_City IS NULL     -- not mapped
              OR  Order_DateTime IS NULL OR Shipment_Created_DateTime IS NULL                -- bad dates
              OR  Planned_Dispatch_Date IS NULL OR Tracking_Event_DateTime IS NULL
              OR  Order_Line_No IS NULL OR Quantity_Ordered IS NULL                          -- bad integers
              OR  Shipment_Line_Quantity IS NULL OR Event_Sequence IS NULL
              OR  Unit_Weight_kg IS NULL OR Unit_Price_EUR IS NULL OR Freight_Cost_EUR IS NULL)  -- bad decimals
   OR EXISTS (SELECT 1 FROM stg.Extract_Unique                                               -- bad conditional values
              WHERE  (Actual_Dispatch_DateTime IS NOT NULL AND TRY_CONVERT(DATETIME2(0), Actual_Dispatch_DateTime, 120) IS NULL)
                 OR  (Promised_Delivery_Date   IS NOT NULL AND TRY_CONVERT(DATE, Promised_Delivery_Date, 23) IS NULL)
                 OR  (Delivery_DateTime        IS NOT NULL AND TRY_CONVERT(DATETIME2(0), Delivery_DateTime, 120) IS NULL)
                 OR  (Delivery_Days_Legacy     IS NOT NULL AND TRY_CONVERT(INT, Delivery_Days_Legacy) IS NULL))
BEGIN
    RAISERROR('Unmapped or unconvertible values found. Script stopped.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* -----------------------------------------------------------------------------
   D4. Remove repeated scans  (17,860 -> 17,796)
       Same shipment line + event + time + location, different event ID.
       The lowest Tracking_Event_ID is kept. Log first, then delete what was logged.
   ----------------------------------------------------------------------------- */
WITH Scans AS
(
    SELECT Legacy_Row_ID, Shipment_No, Order_Line_No, Tracking_Event_Code, Tracking_Event_ID,
           ROW_NUMBER() OVER (PARTITION BY Shipment_No, Order_Line_No, Tracking_Event_Code,
                                           Tracking_Event_DateTime, Event_Location
                              ORDER BY Tracking_Event_ID) AS Scan_No,
           MIN(Tracking_Event_ID) OVER (PARTITION BY Shipment_No, Order_Line_No, Tracking_Event_Code,
                                                     Tracking_Event_DateTime, Event_Location) AS Kept_Event_ID
    FROM   stg.Clean_Extract
)
INSERT INTO audit.Exception_Log
       (Rule_Code, Issue_Class, Action_Taken, Legacy_Row_ID, Business_Key, Column_Name, Source_Value, Clean_Value)
SELECT 'REPEATED_SCAN', 'Data defect', 'Rejected', Legacy_Row_ID,
       CONCAT(Shipment_No, ' | line ', Order_Line_No, ' | ', Tracking_Event_Code),
       N'Tracking_Event_ID', Tracking_Event_ID, CONCAT(N'kept ', Kept_Event_ID)
FROM   Scans
WHERE  Scan_No > 1;

DELETE FROM stg.Clean_Extract
WHERE  Legacy_Row_ID IN (SELECT Legacy_Row_ID FROM audit.Exception_Log WHERE Rule_Code = 'REPEATED_SCAN');
GO

/* -----------------------------------------------------------------------------
   D5. Log every standardised value (source value vs clean value)
       Expected: COMMA_DECIMAL 622 (215 weight + 181 price + 226 freight),
       CARRIER_NAME_VARIANT 71, COUNTRY_ALIAS 71, EVENT_CITY_FIX 2,330,
       EVENT_COUNTRY_DERIVED 8,911
   ----------------------------------------------------------------------------- */
INSERT INTO audit.Exception_Log
       (Rule_Code, Issue_Class, Action_Taken, Legacy_Row_ID, Business_Key, Column_Name, Source_Value, Clean_Value)
SELECT 'COMMA_DECIMAL', 'Data defect', 'Standardised', Legacy_Row_ID, Product_SKU,
       N'Unit_Weight_kg', Src_Unit_Weight_kg, CAST(Unit_Weight_kg AS NVARCHAR(20))
FROM   stg.Clean_Extract WHERE Src_Unit_Weight_kg LIKE '%,%'
UNION ALL
SELECT 'COMMA_DECIMAL', 'Data defect', 'Standardised', Legacy_Row_ID, Product_SKU,
       N'Unit_Price_EUR', Src_Unit_Price_EUR, CAST(Unit_Price_EUR AS NVARCHAR(20))
FROM   stg.Clean_Extract WHERE Src_Unit_Price_EUR LIKE '%,%'
UNION ALL
SELECT 'COMMA_DECIMAL', 'Data defect', 'Standardised', Legacy_Row_ID, CONCAT(Shipment_No, ' | line ', Order_Line_No),
       N'Freight_Cost_EUR', Src_Freight_Cost_EUR, CAST(Freight_Cost_EUR AS NVARCHAR(20))
FROM   stg.Clean_Extract WHERE Src_Freight_Cost_EUR LIKE '%,%'
UNION ALL
-- Compared as bytes, so differences in case and spaces both count
SELECT 'CARRIER_NAME_VARIANT', 'Data defect', 'Standardised', Legacy_Row_ID, Carrier_Code,
       N'Carrier_Name', Src_Carrier_Name, Carrier_Name
FROM   stg.Clean_Extract WHERE CONVERT(VARBINARY(510), Src_Carrier_Name) <> CONVERT(VARBINARY(510), Carrier_Name)
UNION ALL
SELECT 'COUNTRY_ALIAS', 'Data defect', 'Standardised', Legacy_Row_ID, Customer_ID,
       N'Delivery_Country', Src_Delivery_Country, Delivery_Country
FROM   stg.Clean_Extract WHERE Src_Delivery_Country <> Delivery_Country
UNION ALL
-- "Rotterdam Gateway" stored as a city -> Rotterdam
SELECT 'EVENT_CITY_FIX', 'Data defect', 'Standardised', Legacy_Row_ID, Event_Location,
       N'Event_City', Src_Event_City, Event_City
FROM   stg.Clean_Extract WHERE Src_Event_City <> Event_City
UNION ALL
-- Hub country replaced by the location's real country
SELECT 'EVENT_COUNTRY_DERIVED', 'Data defect', 'Standardised', Legacy_Row_ID, Event_Location,
       N'Event_Country', Src_Event_Country, Event_Country
FROM   stg.Clean_Extract WHERE Src_Event_Country <> Event_Country;
GO

/* -----------------------------------------------------------------------------
   D6. Log what is excluded or flagged. Flagged rows are KEPT.
   ----------------------------------------------------------------------------- */

-- a) Sales_Channel conflict: one row per affected order (1,507). Excluded from core.
INSERT INTO audit.Exception_Log
       (Rule_Code, Issue_Class, Action_Taken, Business_Key, Column_Name, Source_Value, Clean_Value)
SELECT   'SALES_CHANNEL_CONFLICT', 'Data defect', 'Excluded', Order_No, N'Sales_Channel',
         CONCAT(COUNT(DISTINCT Src_Sales_Channel), N' different values on ', COUNT(*), N' rows'),
         N'not migrated; raw value kept in staging'
FROM     stg.Clean_Extract
GROUP BY Order_No
HAVING   COUNT(DISTINCT Src_Sales_Channel) > 1;

-- b) Missing milestones. Every shipment line should have all 6 events.
--    Gap before the line's last event = scan missing (46 HUB_OUT, matches the
--    legacy SCAN_GAP alert). Gap after its last event = still in transit (2).
WITH Lines AS
(
    SELECT Shipment_No, Order_Line_No, MAX(Event_Sequence) AS Last_Sequence
    FROM   stg.Clean_Extract
    GROUP BY Shipment_No, Order_Line_No
),
Milestones AS
(
    SELECT DISTINCT Tracking_Event_Code, Event_Sequence
    FROM   stg.Clean_Extract
)
INSERT INTO audit.Exception_Log
       (Rule_Code, Issue_Class, Action_Taken, Business_Key, Column_Name, Source_Value, Clean_Value)
SELECT CASE WHEN m.Event_Sequence < l.Last_Sequence THEN 'MISSING_MILESTONE' ELSE 'IN_TRANSIT' END,
       CASE WHEN m.Event_Sequence < l.Last_Sequence THEN 'Source-system rule' ELSE 'Not applicable' END,
       'Flagged',
       CONCAT(l.Shipment_No, ' | line ', l.Order_Line_No),
       N'Tracking_Event_Code', m.Tracking_Event_Code,
       CASE WHEN m.Event_Sequence < l.Last_Sequence THEN N'scan missing; not invented'
                                                    ELSE N'not reached yet; left blank' END
FROM   Lines AS l
CROSS JOIN Milestones AS m
WHERE  NOT EXISTS (SELECT 1 FROM stg.Clean_Extract AS e
                   WHERE  e.Shipment_No    = l.Shipment_No
                   AND    e.Order_Line_No  = l.Order_Line_No
                   AND    e.Event_Sequence = m.Event_Sequence);

-- c) Out-of-sequence events (613): an event earlier than the milestone before it
WITH Ordered AS
(
    SELECT Legacy_Row_ID, Shipment_No, Order_Line_No, Tracking_Event_Code, Tracking_Event_DateTime,
           LAG(Tracking_Event_Code)     OVER (PARTITION BY Shipment_No, Order_Line_No ORDER BY Event_Sequence) AS Prev_Code,
           LAG(Tracking_Event_DateTime) OVER (PARTITION BY Shipment_No, Order_Line_No ORDER BY Event_Sequence) AS Prev_DateTime
    FROM   stg.Clean_Extract
)
INSERT INTO audit.Exception_Log
       (Rule_Code, Issue_Class, Action_Taken, Legacy_Row_ID, Business_Key, Column_Name, Source_Value, Clean_Value)
SELECT 'OUT_OF_SEQUENCE', 'Data defect', 'Flagged', Legacy_Row_ID,
       CONCAT(Shipment_No, ' | line ', Order_Line_No, ' | ', Tracking_Event_Code),
       N'Tracking_Event_DateTime',
       CONVERT(NVARCHAR(19), Tracking_Event_DateTime, 120),
       CONCAT(N'earlier than ', Prev_Code, N' at ', CONVERT(NVARCHAR(19), Prev_DateTime, 120))
FROM   Ordered
WHERE  Tracking_Event_DateTime < Prev_DateTime;

-- d) Postal codes not in the national format (657 customers). Kept as text.
INSERT INTO audit.Exception_Log
       (Rule_Code, Issue_Class, Action_Taken, Business_Key, Column_Name, Source_Value, Clean_Value)
SELECT DISTINCT 'POSTCODE_FORMAT', 'Data defect', 'Flagged', Customer_ID,
       N'Delivery_Postal_Code', Delivery_Postal_Code,
       CONCAT(N'not a valid ', Delivery_Country, N' format; kept as supplied')
FROM   stg.Clean_Extract
WHERE  NOT (   (Delivery_Country = N'Netherlands'            AND Delivery_Postal_Code LIKE '[0-9][0-9][0-9][0-9] [A-Z][A-Z]')
            OR (Delivery_Country IN (N'Germany', N'France')  AND Delivery_Postal_Code LIKE '[0-9][0-9][0-9][0-9][0-9]')
            OR (Delivery_Country IN (N'Belgium', N'Austria') AND Delivery_Postal_Code LIKE '[0-9][0-9][0-9][0-9]')
            OR (Delivery_Country = N'Luxembourg'             AND Delivery_Postal_Code LIKE 'L-[0-9][0-9][0-9][0-9]'));

-- e) Orders outside the stated period Jan-Dec 2025 (4 orders). Kept.
INSERT INTO audit.Exception_Log
       (Rule_Code, Issue_Class, Action_Taken, Business_Key, Column_Name, Source_Value, Clean_Value)
SELECT   'OUT_OF_PERIOD', 'Source-system rule', 'Flagged', Order_No, N'Order_DateTime',
         CONVERT(NVARCHAR(19), MIN(Order_DateTime), 120), N'outside Jan-Dec 2025; kept for scope decision'
FROM     stg.Clean_Extract
WHERE    Order_DateTime < '2025-01-01' OR Order_DateTime >= '2026-01-01'
GROUP BY Order_No;
GO


/* #############################################################################
   PART E : EVIDENCE
   ############################################################################# */

-- E1. Control total: 18,000 - 140 = 17,860; 17,860 - 64 = 17,796
DECLARE @Source_Rows       INT = (SELECT COUNT(*) FROM stg.Legacy_Extract_Raw),
        @Exact_Duplicates  INT = (SELECT COUNT(*) FROM audit.Exception_Log WHERE Rule_Code = 'EXACT_DUPLICATE'),
        @Unique_Rows       INT = (SELECT COUNT(*) FROM stg.Extract_Unique),
        @Repeated_Scans    INT = (SELECT COUNT(*) FROM audit.Exception_Log WHERE Rule_Code = 'REPEATED_SCAN'),
        @Accepted_Events   INT = (SELECT COUNT(*) FROM stg.Clean_Extract);

SELECT  @Source_Rows      AS Source_Rows,
        @Exact_Duplicates AS Exact_Duplicates_Removed,
        @Unique_Rows      AS Unique_Rows,
        @Repeated_Scans   AS Repeated_Scans_Removed,
        @Accepted_Events  AS Accepted_Events,
        CASE WHEN @Source_Rows - @Exact_Duplicates = @Unique_Rows
              AND @Unique_Rows - @Repeated_Scans   = @Accepted_Events
             THEN 'PASS' ELSE 'FAIL' END AS Control_Total;

-- E2. Exception summary. Expected:
--     EXACT_DUPLICATE 140, REPEATED_SCAN 64             (Rejected)
--     COMMA_DECIMAL 622, CARRIER_NAME_VARIANT 71, COUNTRY_ALIAS 71,
--     EVENT_CITY_FIX 2,330, EVENT_COUNTRY_DERIVED 8,911 (Standardised)
--     SALES_CHANNEL_CONFLICT 1,507                      (Excluded)
--     MISSING_MILESTONE 46, IN_TRANSIT 2, OUT_OF_SEQUENCE 613,
--     POSTCODE_FORMAT 657, OUT_OF_PERIOD 4              (Flagged)
SELECT   Rule_Code, Issue_Class, Action_Taken, COUNT(*) AS Log_Rows
FROM     audit.Exception_Log
GROUP BY Rule_Code, Issue_Class, Action_Taken
ORDER BY Action_Taken, Rule_Code;

-- E3. Clean data is ready for 3NF (every check expected 0)
SELECT 'Carrier with more than one name' AS Check_Name, COUNT(*) AS Violations
FROM  (SELECT Carrier_Code FROM stg.Clean_Extract GROUP BY Carrier_Code
       HAVING COUNT(DISTINCT Carrier_Name) > 1) AS x
UNION ALL
SELECT 'Location with more than one country', COUNT(*)
FROM  (SELECT Event_Location FROM stg.Clean_Extract GROUP BY Event_Location
       HAVING COUNT(DISTINCT Event_Country) > 1) AS x
UNION ALL
SELECT 'Customer with more than one name/email/address', COUNT(*)
FROM  (SELECT Customer_ID FROM stg.Clean_Extract GROUP BY Customer_ID
       HAVING COUNT(DISTINCT CONCAT(Customer_Name, '|', Customer_Email, '|', Customer_Type, '|',
                                    Delivery_Address_Line, '|', Delivery_City, '|',
                                    Delivery_Postal_Code, '|', Delivery_Country)) > 1) AS x
UNION ALL
SELECT 'Product with more than one name/price/weight', COUNT(*)
FROM  (SELECT Product_SKU FROM stg.Clean_Extract GROUP BY Product_SKU
       HAVING COUNT(DISTINCT CONCAT(Product_Name, '|', Product_Category, '|',
                                    Unit_Price_EUR, '|', Unit_Weight_kg)) > 1) AS x
UNION ALL
SELECT 'Shipment with more than one order/carrier/date', COUNT(*)
FROM  (SELECT Shipment_No FROM stg.Clean_Extract GROUP BY Shipment_No
       HAVING COUNT(DISTINCT CONCAT(Order_No, '|', Warehouse_Code, '|', Carrier_Code, '|',
                                    Carrier_Service_Level, '|', Tracking_No, '|',
                                    Shipment_Created_DateTime, '|', Planned_Dispatch_Date, '|',
                                    Actual_Dispatch_DateTime, '|', Promised_Delivery_Date)) > 1) AS x
UNION ALL
SELECT 'Shipment line with more than one freight/quantity', COUNT(*)
FROM  (SELECT Shipment_No, Order_Line_No FROM stg.Clean_Extract GROUP BY Shipment_No, Order_Line_No
       HAVING COUNT(DISTINCT CONCAT(Freight_Cost_EUR, '|', Shipment_Line_Quantity)) > 1) AS x
UNION ALL
SELECT 'Same event twice on one shipment line', COUNT(*)
FROM  (SELECT Shipment_No, Order_Line_No, Tracking_Event_Code FROM stg.Clean_Extract
       GROUP BY Shipment_No, Order_Line_No, Tracking_Event_Code
       HAVING COUNT(*) > 1) AS x
UNION ALL
SELECT 'Tracking number not matching carrier prefix', COUNT(*)
FROM   stg.Clean_Extract AS c
JOIN   map.Carrier       AS m ON m.Carrier_Code = c.Carrier_Code
WHERE  LEFT(c.Tracking_No, 4) <> m.Tracking_Prefix;

-- E4. Business totals at the right grain (carried into reconciliation in 08)
SELECT  (SELECT SUM(Quantity_Ordered)
         FROM  (SELECT DISTINCT Order_No, Order_Line_No, Quantity_Ordered FROM stg.Clean_Extract) AS ol)
                                                     AS Quantity_Ordered,     -- 7,462
        (SELECT SUM(Shipment_Line_Quantity)
         FROM  (SELECT DISTINCT Shipment_No, Order_Line_No, Shipment_Line_Quantity FROM stg.Clean_Extract) AS sl)
                                                     AS Quantity_Shipped,     -- 7,462
        (SELECT SUM(Unit_Price_EUR * Quantity_Ordered)
         FROM  (SELECT DISTINCT Order_No, Order_Line_No, Unit_Price_EUR, Quantity_Ordered FROM stg.Clean_Extract) AS ol)
                                                     AS Order_Value_EUR,      -- 960,199.50
        (SELECT SUM(Freight_Cost_EUR)
         FROM  (SELECT DISTINCT Shipment_No, Order_Line_No, Freight_Cost_EUR FROM stg.Clean_Extract) AS sl)
                                                     AS Freight_EUR_Correct,  -- 40,249.18
        (SELECT SUM(TRY_CONVERT(DECIMAL(10, 2), REPLACE(Freight_Cost_EUR, ',', '.'))) FROM stg.Legacy_Extract_Raw)
                                                     AS Freight_EUR_Raw_Sum;  -- 243,578.01 (the legacy trap)
GO

SET NOEXEC OFF;   -- reset in case a guard stopped execution
GO
