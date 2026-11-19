/* =============================================================================
   Operation RouteGlass | Script 08 : Validation and reconciliation
   Author	: Mustapha (Sir Mustee)
   =============================================================================
   Purpose : To Prove the migrated data is complete, unique and traceable.

   How it works
     Every check is one row in the temporary table #Checks:
       Source_Value  what the source or the rule says it should be
       Target_Value  what the database holds
     Equal values pass. The last two queries show every result on one screen.

   Result
     PASS         source and target agree
     KNOWN ISSUE  the count matches the known figure, but the issue remains open
                  and belongs in the go/no-go recommendation
     FAIL         source and target disagree: investigate before go-live

   Depends : 01 to 07. Changes no data. Rerun : safe.
   ============================================================================= */

USE SorellinLivingDB;
GO
SET NOCOUNT ON;

DROP TABLE IF EXISTS #Checks;
CREATE TABLE #Checks
(
    Check_ID      INT IDENTITY(1, 1) NOT NULL,
    Section       VARCHAR(40)    NOT NULL,
    Check_Name    VARCHAR(90)    NOT NULL,
    Source_Value  DECIMAL(14, 2) NULL,
    Target_Value  DECIMAL(14, 2) NULL
);


/* ===========================================================================
   SOURCE FILE CONTROL (recorded before migration)
   Confirm your copy in PowerShell and screenshot the result:
       Get-FileHash .\02_Sorellin_Legacy_Order_Delivery_Extract.csv -Algorithm SHA256
   =========================================================================== */
SELECT  '02_Sorellin_Legacy_Order_Delivery_Extract.csv' AS Source_File,
        18000                                           AS Data_Rows,
        50                                              AS Columns_In_File,
        9511209                                         AS File_Bytes,
        '42B58D32D0FE4BB455A6E26CB43C78302B1248AD970312B3845D6F5AD32E176D' AS SHA256_Checksum;


/* ===========================================================================
   1. CONTROL TOTAL: every source row is accounted for exactly once
   =========================================================================== */
INSERT INTO #Checks (Section, Check_Name, Source_Value, Target_Value)
SELECT '1. Control total', 'Rows in the CSV = rows in staging',
       18000,
       (SELECT COUNT(*) FROM stg.Legacy_Extract_Raw)
UNION ALL
SELECT '1. Control total', 'Staging - exact duplicates = unique rows',
       (SELECT COUNT(*) FROM stg.Legacy_Extract_Raw)
         - (SELECT COUNT(*) FROM audit.Exception_Log WHERE Rule_Code = 'EXACT_DUPLICATE'),
       (SELECT COUNT(*) FROM stg.Extract_Unique)
UNION ALL
SELECT '1. Control total', 'Unique rows - repeated scans = accepted rows',
       (SELECT COUNT(*) FROM stg.Extract_Unique)
         - (SELECT COUNT(*) FROM audit.Exception_Log WHERE Rule_Code = 'REPEATED_SCAN'),
       (SELECT COUNT(*) FROM stg.Clean_Extract)
UNION ALL
SELECT '1. Control total', 'Accepted rows = tracking events in core',
       (SELECT COUNT(*) FROM stg.Clean_Extract),
       (SELECT COUNT(*) FROM core.TrackingEvent)
UNION ALL
SELECT '1. Control total', 'Every core event traces back to an accepted row',
       (SELECT COUNT(*) FROM core.TrackingEvent),
       (SELECT COUNT(*) FROM core.TrackingEvent AS te
        JOIN   stg.Clean_Extract AS c ON c.Legacy_Row_ID = te.LegacyRowID)
UNION ALL
SELECT '1. Control total', 'Rejected repeated scans present in core',
       0,
       (SELECT COUNT(*) FROM core.TrackingEvent
        WHERE  LegacyRowID IN (SELECT Legacy_Row_ID FROM audit.Exception_Log WHERE Rule_Code = 'REPEATED_SCAN'));


/* ===========================================================================
   2. ENTITY COUNTS: distinct values in the source vs rows in each core table
   =========================================================================== */
INSERT INTO #Checks (Section, Check_Name, Source_Value, Target_Value)
SELECT '2. Entity counts', 'Customers',
       (SELECT COUNT(DISTINCT Customer_ID) FROM stg.Legacy_Extract_Raw),
       (SELECT COUNT(*) FROM core.Customer)
UNION ALL
SELECT '2. Entity counts', 'Products',
       (SELECT COUNT(DISTINCT Product_SKU) FROM stg.Legacy_Extract_Raw),
       (SELECT COUNT(*) FROM core.Product)
UNION ALL
SELECT '2. Entity counts', 'Warehouses',
       (SELECT COUNT(DISTINCT Warehouse_Code) FROM stg.Legacy_Extract_Raw),
       (SELECT COUNT(*) FROM core.Warehouse)
UNION ALL
SELECT '2. Entity counts', 'Carriers',
       (SELECT COUNT(DISTINCT Carrier_Code) FROM stg.Legacy_Extract_Raw),
       (SELECT COUNT(*) FROM core.Carrier)
UNION ALL
SELECT '2. Entity counts', 'Locations',
       (SELECT COUNT(DISTINCT Event_Location) FROM stg.Legacy_Extract_Raw),
       (SELECT COUNT(*) FROM core.Location)
UNION ALL
SELECT '2. Entity counts', 'Cities',
       (SELECT COUNT(*) FROM (SELECT Delivery_City, Delivery_Country FROM stg.Clean_Extract
                              UNION
                              SELECT City_Name, Country_Name FROM map.Location) AS c),
       (SELECT COUNT(*) FROM core.City)
UNION ALL
SELECT '2. Entity counts', 'Event types',
       (SELECT COUNT(DISTINCT Tracking_Event_Code) FROM stg.Legacy_Extract_Raw),
       (SELECT COUNT(*) FROM core.EventType)
UNION ALL
SELECT '2. Entity counts', 'Exception types',
       (SELECT COUNT(DISTINCT Exception_Code) FROM stg.Legacy_Extract_Raw),
       (SELECT COUNT(*) FROM core.Exception_Type)
UNION ALL
SELECT '2. Entity counts', 'Orders',
       (SELECT COUNT(DISTINCT Order_No) FROM stg.Legacy_Extract_Raw),
       (SELECT COUNT(*) FROM core.SalesOrder)
UNION ALL
SELECT '2. Entity counts', 'Order lines',
       (SELECT COUNT(DISTINCT CONCAT(Order_No, '|', Order_Line_No)) FROM stg.Legacy_Extract_Raw),
       (SELECT COUNT(*) FROM core.OrderLine)
UNION ALL
SELECT '2. Entity counts', 'Shipments',
       (SELECT COUNT(DISTINCT Shipment_No) FROM stg.Legacy_Extract_Raw),
       (SELECT COUNT(*) FROM core.Shipment)
UNION ALL
SELECT '2. Entity counts', 'Shipment lines',
       (SELECT COUNT(DISTINCT CONCAT(Shipment_No, '|', Order_Line_No)) FROM stg.Legacy_Extract_Raw),
       (SELECT COUNT(*) FROM core.ShipmentLine)
UNION ALL
SELECT '2. Entity counts', 'Tracking events (distinct IDs - repeated scans)',
       (SELECT COUNT(DISTINCT Tracking_Event_ID) FROM stg.Legacy_Extract_Raw)
         - (SELECT COUNT(*) FROM audit.Exception_Log WHERE Rule_Code = 'REPEATED_SCAN'),
       (SELECT COUNT(*) FROM core.TrackingEvent);


/* ===========================================================================
   3. REFERENTIAL INTEGRITY: child rows with no parent (all expected 0)
   =========================================================================== */
INSERT INTO #Checks (Section, Check_Name, Source_Value, Target_Value)
SELECT '3. Orphan records', 'Customer -> City', 0,
       (SELECT COUNT(*) FROM core.Customer WHERE CitySK IS NOT NULL AND CitySK NOT IN (SELECT CitySK FROM core.City))
UNION ALL
SELECT '3. Orphan records', 'Location -> City', 0,
       (SELECT COUNT(*) FROM core.Location WHERE CitySK NOT IN (SELECT CitySK FROM core.City))
UNION ALL
SELECT '3. Orphan records', 'Warehouse -> Location', 0,
       (SELECT COUNT(*) FROM core.Warehouse WHERE LocationSK NOT IN (SELECT LocationSK FROM core.Location))
UNION ALL
SELECT '3. Orphan records', 'Sales_Order -> Customer', 0,
       (SELECT COUNT(*) FROM core.SalesOrder WHERE CustomerSK NOT IN (SELECT CustomerSK FROM core.Customer))
UNION ALL
SELECT '3. Orphan records', 'Order_Line -> Sales_Order', 0,
       (SELECT COUNT(*) FROM core.OrderLine WHERE SalesOrderSK NOT IN (SELECT SalesOrderSK FROM core.SalesOrder))
UNION ALL
SELECT '3. Orphan records', 'Order_Line -> Product', 0,
       (SELECT COUNT(*) FROM core.OrderLine WHERE ProductSK NOT IN (SELECT ProductSK FROM core.Product))
UNION ALL
SELECT '3. Orphan records', 'Shipment -> Sales_Order', 0,
       (SELECT COUNT(*) FROM core.Shipment WHERE SalesOrderSK NOT IN (SELECT SalesOrderSK FROM core.SalesOrder))
UNION ALL
SELECT '3. Orphan records', 'Shipment -> Warehouse', 0,
       (SELECT COUNT(*) FROM core.Shipment WHERE WarehouseSK NOT IN (SELECT WarehouseSK FROM core.Warehouse))
UNION ALL
SELECT '3. Orphan records', 'Shipment -> Carrier', 0,
       (SELECT COUNT(*) FROM core.Shipment WHERE CarrierSK NOT IN (SELECT CarrierSK FROM core.Carrier))
UNION ALL
SELECT '3. Orphan records', 'Shipment_Line -> Shipment', 0,
       (SELECT COUNT(*) FROM core.ShipmentLine WHERE ShipmentSK NOT IN (SELECT ShipmentSK FROM core.Shipment))
UNION ALL
SELECT '3. Orphan records', 'Shipment_Line -> Order_Line', 0,
       (SELECT COUNT(*) FROM core.ShipmentLine WHERE OrderLineSK NOT IN (SELECT OrderLineSK FROM core.OrderLine))
UNION ALL
SELECT '3. Orphan records', 'Tracking_Event -> Shipment_Line', 0,
       (SELECT COUNT(*) FROM core.TrackingEvent WHERE ShipmentLineSK NOT IN (SELECT ShipmentLineSK FROM core.ShipmentLine))
UNION ALL
SELECT '3. Orphan records', 'Tracking_Event -> Event_Type', 0,
       (SELECT COUNT(*) FROM core.TrackingEvent WHERE EventTypeSK NOT IN (SELECT EventTypeSK FROM core.EventType))
UNION ALL
SELECT '3. Orphan records', 'Tracking_Event -> Location', 0,
       (SELECT COUNT(*) FROM core.TrackingEvent WHERE LocationSK NOT IN (SELECT LocationSK FROM core.Location))
UNION ALL
SELECT '3. Orphan records', 'Tracking_Event -> Exception_Type', 0,
       (SELECT COUNT(*) FROM core.TrackingEvent WHERE ExceptionTypeSK IS NOT NULL
        AND ExceptionTypeSK NOT IN (SELECT ExceptionTypeSK FROM core.Exception_Type))
UNION ALL
-- Parents with no children: the journey must be complete from order to event
SELECT '3. Orphan records', 'Orders with no order line', 0,
       (SELECT COUNT(*) FROM core.SalesOrder WHERE SalesOrderSK NOT IN (SELECT SalesOrderSK FROM core.OrderLine))
UNION ALL
SELECT '3. Orphan records', 'Orders with no shipment', 0,
       (SELECT COUNT(*) FROM core.SalesOrder WHERE SalesOrderSK NOT IN (SELECT SalesOrderSK FROM core.Shipment))
UNION ALL
SELECT '3. Orphan records', 'Order lines never shipped', 0,
       (SELECT COUNT(*) FROM core.OrderLine WHERE OrderLineSK NOT IN (SELECT OrderLineSK FROM core.ShipmentLine))
UNION ALL
SELECT '3. Orphan records', 'Shipment lines with no tracking event', 0,
       (SELECT COUNT(*) FROM core.ShipmentLine WHERE ShipmentLineSK NOT IN (SELECT ShipmentLineSK FROM core.TrackingEvent))
UNION ALL
-- Foreign keys SQL Server has not fully checked or has switched off
SELECT '3. Orphan records', 'Foreign keys not trusted or disabled', 0,
       (SELECT COUNT(*) FROM sys.foreign_keys
        WHERE  schema_id = SCHEMA_ID(N'core') AND (is_not_trusted = 1 OR is_disabled = 1));


/* ===========================================================================
   4. DUPLICATE BUSINESS KEYS: rows minus distinct keys (all expected 0)
   =========================================================================== */
INSERT INTO #Checks (Section, Check_Name, Source_Value, Target_Value)
SELECT '4. Duplicate keys', 'City name and country', 0,
       (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(CityName, '|', CountryName)) FROM core.City)
UNION ALL
SELECT '4. Duplicate keys', 'CustomerID', 0, (SELECT COUNT(*) - COUNT(DISTINCT CustomerID) FROM core.Customer)
UNION ALL
SELECT '4. Duplicate keys', 'CustomerEmail', 0, (SELECT COUNT(*) - COUNT(DISTINCT CustomerEmail) FROM core.Customer)
UNION ALL
SELECT '4. Duplicate keys', 'ProductSKU', 0, (SELECT COUNT(*) - COUNT(DISTINCT ProductSKU) FROM core.Product)
UNION ALL
SELECT '4. Duplicate keys', 'LocationName', 0, (SELECT COUNT(*) - COUNT(DISTINCT LocationName) FROM core.Location)
UNION ALL
SELECT '4. Duplicate keys', 'WarehouseCode', 0, (SELECT COUNT(*) - COUNT(DISTINCT WarehouseCode) FROM core.Warehouse)
UNION ALL
SELECT '4. Duplicate keys', 'CarrierCode', 0, (SELECT COUNT(*) - COUNT(DISTINCT CarrierCode) FROM core.Carrier)
UNION ALL
SELECT '4. Duplicate keys', 'EventCode', 0, (SELECT COUNT(*) - COUNT(DISTINCT EventCode) FROM core.EventType)
UNION ALL
SELECT '4. Duplicate keys', 'ExceptionCode', 0, (SELECT COUNT(*) - COUNT(DISTINCT ExceptionCode) FROM core.Exception_Type)
UNION ALL
SELECT '4. Duplicate keys', 'OrderNo', 0, (SELECT COUNT(*) - COUNT(DISTINCT OrderNo) FROM core.SalesOrder)
UNION ALL
SELECT '4. Duplicate keys', 'Order and line number', 0,
       (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(SalesOrderSK, '|', OrderLineNo)) FROM core.OrderLine)
UNION ALL
SELECT '4. Duplicate keys', 'ShipmentNo', 0, (SELECT COUNT(*) - COUNT(DISTINCT ShipmentNo) FROM core.Shipment)
UNION ALL
SELECT '4. Duplicate keys', 'TrackingNo', 0, (SELECT COUNT(*) - COUNT(DISTINCT TrackingNo) FROM core.Shipment)
UNION ALL
SELECT '4. Duplicate keys', 'Shipment and order line', 0,
       (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(ShipmentSK, '|', OrderLineSK)) FROM core.ShipmentLine)
UNION ALL
SELECT '4. Duplicate keys', 'TrackingEventID', 0, (SELECT COUNT(*) - COUNT(DISTINCT TrackingEventID) FROM core.TrackingEvent)
UNION ALL
SELECT '4. Duplicate keys', 'LegacyRowID', 0, (SELECT COUNT(*) - COUNT(DISTINCT LegacyRowID) FROM core.TrackingEvent)
UNION ALL
SELECT '4. Duplicate keys', 'One event per milestone per shipment line', 0,
       (SELECT COUNT(*) - COUNT(DISTINCT CONCAT(ShipmentLineSK, '|', EventTypeSK)) FROM core.TrackingEvent);


/* ===========================================================================
   5. MANDATORY AND CONDITIONAL VALUES
   =========================================================================== */
INSERT INTO #Checks (Section, Check_Name, Source_Value, Target_Value)
SELECT '5. Mandatory and conditional', 'Customers missing name, email or type', 0,
       (SELECT COUNT(*) FROM core.Customer
        WHERE  CustomerName = N'' OR CustomerEmail = N'' OR CustomerType = '')
UNION ALL
SELECT '5. Mandatory and conditional', 'Products with no positive price or weight', 0,
       (SELECT COUNT(*) FROM core.Product WHERE UnitPriceEUR <= 0 OR UnitWeightKg <= 0)
UNION ALL
SELECT '5. Mandatory and conditional', 'Shipments missing a tracking number', 0,
       (SELECT COUNT(*) FROM core.Shipment WHERE TrackingNo = '')
UNION ALL
-- Blanks that are correct must still be blank, never filled with invented values
SELECT '5. Mandatory and conditional', 'Shipments with no proof of delivery stay blank',
       (SELECT COUNT(DISTINCT Shipment_No) - COUNT(DISTINCT CASE WHEN Proof_of_Delivery_Ref IS NOT NULL THEN Shipment_No END)
        FROM   stg.Legacy_Extract_Raw),
       (SELECT COUNT(*) FROM core.Shipment WHERE ProofOfDeliveryRef IS NULL)
UNION ALL
SELECT '5. Mandatory and conditional', 'Events with no exception stay blank',
       (SELECT COUNT(*) FROM stg.Clean_Extract WHERE Exception_Code IS NULL),
       (SELECT COUNT(*) FROM core.TrackingEvent WHERE ExceptionTypeSK IS NULL)
UNION ALL
-- No milestone was invented: 2,974 lines x 6 milestones, less the ones that do not exist
SELECT '5. Mandatory and conditional', 'Lines x 6 milestones - missing = events in core',
       (SELECT COUNT(*) * 6 FROM core.ShipmentLine)
         - (SELECT COUNT(*) FROM audit.Exception_Log WHERE Rule_Code IN ('MISSING_MILESTONE', 'IN_TRANSIT')),
       (SELECT COUNT(*) FROM core.TrackingEvent);


/* ===========================================================================
   6. CROSS-TABLE RULES AND CHRONOLOGY: rows breaking the rule (all expected 0)
   =========================================================================== */
INSERT INTO #Checks (Section, Check_Name, Source_Value, Target_Value)
SELECT '6. Business rules', 'Order line belongs to a different order than its shipment', 0,
       (SELECT COUNT(*) FROM core.ShipmentLine AS sl
        JOIN   core.Shipment   AS s  ON s.ShipmentSK = sl.ShipmentSK
        JOIN   core.OrderLine AS ol ON ol.OrderLineSK = sl.OrderLineSK
        WHERE  ol.SalesOrderSK <> s.SalesOrderSK)
UNION ALL
SELECT '6. Business rules', 'Quantity shipped differs from quantity ordered', 0,
       (SELECT COUNT(*) FROM core.OrderLine AS ol
        WHERE  ol.QuantityOrdered <> (SELECT SUM(sl.ShipmentLineQuantity) FROM core.ShipmentLine AS sl
                                      WHERE  sl.OrderLineSK = ol.OrderLineSK))
UNION ALL
SELECT '6. Business rules', 'Tracking number does not start with the carrier prefix', 0,
       (SELECT COUNT(*) FROM core.Shipment AS s
        JOIN   core.Carrier AS c ON c.CarrierSK = s.CarrierSK
        WHERE  LEFT(s.TrackingNo, 4) <> c.TrackingPrefix)
UNION ALL
SELECT '6. Business rules', 'Event at the wrong type of location', 0,
       (SELECT COUNT(*) FROM core.TrackingEvent AS te
        JOIN   core.EventType AS et ON et.EventTypeSK = te.EventTypeSK
        JOIN   core.Location   AS l  ON l.LocationSK = te.LocationSK
        WHERE  l.LocationType <> et.ExpectedLocationType)
UNION ALL
SELECT '6. Business rules', 'PICKED or DISPATCHED away from the shipment warehouse', 0,
       (SELECT COUNT(*) FROM core.TrackingEvent AS te
        JOIN   core.EventType    AS et ON et.EventTypeSK = te.EventTypeSK
        JOIN   core.ShipmentLine AS sl ON sl.ShipmentLineSK = te.ShipmentLineSK
        JOIN   core.Shipment      AS s  ON s.ShipmentSK = sl.ShipmentSK
        JOIN   core.Warehouse     AS w  ON w.WarehouseSK = s.WarehouseSK
        WHERE  et.ExpectedLocationType = 'Warehouse' AND te.LocationSK <> w.LocationSK)
UNION ALL
SELECT '6. Business rules', 'Shipment created before its order', 0,
       (SELECT COUNT(*) FROM core.Shipment AS s
        JOIN   core.SalesOrder AS o ON o.SalesOrderSK = s.SalesOrderSK
        WHERE  s.ShipmentCreatedDateTime < o.OrderDateTime)
UNION ALL
SELECT '6. Business rules', 'Tracking event earlier than its order', 0,
       (SELECT COUNT(*) FROM core.TrackingEvent AS te
        JOIN   core.ShipmentLine AS sl ON sl.ShipmentLineSK = te.ShipmentLineSK
        JOIN   core.OrderLine    AS ol ON ol.OrderLineSK = sl.OrderLineSK
        JOIN   core.SalesOrder   AS o  ON o.SalesOrderSK = ol.SalesOrderSK
        WHERE  te.EventDateTime < o.OrderDateTime)
UNION ALL
SELECT '6. Business rules', 'DISPATCHED event differs from the shipment dispatch time', 0,
       (SELECT COUNT(*) FROM core.TrackingEvent AS te
        JOIN   core.EventType    AS et ON et.EventTypeSK = te.EventTypeSK
        JOIN   core.ShipmentLine AS sl ON sl.ShipmentLineSK = te.ShipmentLineSK
        JOIN   core.Shipment      AS s  ON s.ShipmentSK = sl.ShipmentSK
        WHERE  et.EventCode = 'DISPATCHED' AND te.EventDateTime <> s.ActualDispatchDateTime)
UNION ALL
SELECT '6. Business rules', 'DELIVERED before the shipment was dispatched', 0,
       (SELECT COUNT(*) FROM core.TrackingEvent AS te
        JOIN   core.EventType    AS et ON et.EventTypeSK = te.EventTypeSK
        JOIN   core.ShipmentLine AS sl ON sl.ShipmentLineSK = te.ShipmentLineSK
        JOIN   core.Shipment      AS s  ON s.ShipmentSK = sl.ShipmentSK
        WHERE  et.EventCode = 'DELIVERED' AND te.EventDateTime < s.ActualDispatchDateTime);


/* ===========================================================================
   7. BUSINESS TOTALS BEFORE AND AFTER MIGRATION
   "Before" is read from raw staging at the correct grain, with no use of 04.
   =========================================================================== */
INSERT INTO #Checks (Section, Check_Name, Source_Value, Target_Value)
SELECT '7. Totals before and after', 'Quantity ordered',
       (SELECT SUM(Qty) FROM (SELECT DISTINCT Order_No, Order_Line_No,
                                     TRY_CONVERT(INT, Quantity_Ordered) AS Qty
                              FROM   stg.Legacy_Extract_Raw) AS r),
       (SELECT SUM(QuantityOrdered) FROM core.OrderLine)
UNION ALL
SELECT '7. Totals before and after', 'Quantity shipped',
       (SELECT SUM(Qty) FROM (SELECT DISTINCT Shipment_No, Order_Line_No,
                                     TRY_CONVERT(INT, Shipment_Line_Quantity) AS Qty
                              FROM   stg.Legacy_Extract_Raw) AS r),
       (SELECT SUM(ShipmentLineQuantity) FROM core.ShipmentLine)
UNION ALL
SELECT '7. Totals before and after', 'Order value (EUR)',
       (SELECT SUM(Price * Qty) FROM (SELECT DISTINCT Order_No, Order_Line_No,
                                             TRY_CONVERT(DECIMAL(10, 2), REPLACE(Unit_Price_EUR, ',', '.')) AS Price,
                                             TRY_CONVERT(INT, Quantity_Ordered) AS Qty
                                      FROM   stg.Legacy_Extract_Raw) AS r),
       (SELECT SUM(ol.QuantityOrdered * p.UnitPriceEUR) FROM core.OrderLine AS ol
        JOIN   core.Product AS p ON p.ProductSK = ol.ProductSK)
UNION ALL
SELECT '7. Totals before and after', 'Freight cost (EUR)',
       (SELECT SUM(Freight) FROM (SELECT DISTINCT Shipment_No, Order_Line_No,
                                         TRY_CONVERT(DECIMAL(10, 2), REPLACE(Freight_Cost_EUR, ',', '.')) AS Freight
                                  FROM   stg.Legacy_Extract_Raw) AS r),
       (SELECT SUM(FreightCostEUR) FROM core.ShipmentLine)
UNION ALL
SELECT '7. Totals before and after', 'LATE alerts (distinct source rows)',
       (SELECT COUNT(DISTINCT Legacy_Row_ID) FROM stg.Legacy_Extract_Raw WHERE Exception_Code = 'LATE'),
       (SELECT COUNT(*) FROM core.TrackingEvent AS te
        JOIN   core.Exception_Type AS x ON x.ExceptionTypeSK = te.ExceptionTypeSK
        WHERE  x.ExceptionCode = 'LATE')
UNION ALL
SELECT '7. Totals before and after', 'SCAN_GAP alerts (distinct source rows)',
       (SELECT COUNT(DISTINCT Legacy_Row_ID) FROM stg.Legacy_Extract_Raw WHERE Exception_Code = 'SCAN_GAP'),
       (SELECT COUNT(*) FROM core.TrackingEvent AS te
        JOIN   core.Exception_Type AS x ON x.ExceptionTypeSK = te.ExceptionTypeSK
        WHERE  x.ExceptionCode = 'SCAN_GAP')
UNION ALL
SELECT '7. Totals before and after', 'Legacy late flags = deliveries recalculated as late',
       (SELECT COUNT(*) FROM stg.Clean_Extract WHERE On_Time_Flag_Legacy = 'No'),
       (SELECT COUNT(*) FROM core.TrackingEvent AS te
        JOIN   core.EventType    AS et ON et.EventTypeSK = te.EventTypeSK
        JOIN   core.ShipmentLine AS sl ON sl.ShipmentLineSK = te.ShipmentLineSK
        JOIN   core.Shipment      AS s  ON s.ShipmentSK = sl.ShipmentSK
        WHERE  et.EventCode = 'DELIVERED' AND CAST(te.EventDateTime AS DATE) > s.PromisedDeliveryDate)
UNION ALL
SELECT '7. Totals before and after', 'Legacy delivery days = days recalculated (sum)',
       (SELECT SUM(Delivery_Days_Legacy) FROM stg.Clean_Extract),
       (SELECT SUM(DATEDIFF(DAY, o.OrderDateTime, te.EventDateTime)) FROM core.TrackingEvent AS te
        JOIN   core.EventType    AS et ON et.EventTypeSK = te.EventTypeSK
        JOIN   core.ShipmentLine AS sl ON sl.ShipmentLineSK = te.ShipmentLineSK
        JOIN   core.OrderLine    AS ol ON ol.OrderLineSK = sl.OrderLineSK
        JOIN   core.SalesOrder   AS o  ON o.SalesOrderSK = ol.SalesOrderSK
        WHERE  et.EventCode = 'DELIVERED');

-- Events per milestone: accepted source rows vs core
INSERT INTO #Checks (Section, Check_Name, Source_Value, Target_Value)
SELECT '7. Totals before and after', CONCAT('Events: ', et.EventCode),
       (SELECT COUNT(*) FROM stg.Clean_Extract AS c WHERE c.Tracking_Event_Code = et.EventCode),
       (SELECT COUNT(*) FROM core.TrackingEvent AS te WHERE te.EventTypeSK = et.EventTypeSK)
FROM   core.EventType AS et;


/* ===========================================================================
   8. KNOWN ISSUES: real problems in the source, kept and not hidden.
   The first four are compared with the exception log. The last two were found
   by this script and are not in the log, so their known figure is written here.
   =========================================================================== */
INSERT INTO #Checks (Section, Check_Name, Source_Value, Target_Value)
SELECT '8. Known issues', 'Events earlier than the milestone before them',
       (SELECT COUNT(*) FROM audit.Exception_Log WHERE Rule_Code = 'OUT_OF_SEQUENCE'),
       (SELECT COUNT(*)
        FROM  (SELECT te.EventDateTime,
                      LAG(te.EventDateTime) OVER (PARTITION BY te.ShipmentLineSK ORDER BY et.StandardSequence) AS Previous_Time
               FROM   core.TrackingEvent AS te
               JOIN   core.EventType AS et ON et.EventTypeSK = te.EventTypeSK) AS e
        WHERE  e.EventDateTime < e.Previous_Time)
UNION ALL
SELECT '8. Known issues', 'Shipment lines with a missing HUB_OUT scan',
       (SELECT COUNT(*) FROM audit.Exception_Log WHERE Rule_Code = 'MISSING_MILESTONE'),
       (SELECT COUNT(*) FROM core.ShipmentLine
        WHERE  ShipmentLineSK NOT IN (SELECT te.ShipmentLineSK FROM core.TrackingEvent AS te
                                      JOIN   core.EventType AS et ON et.EventTypeSK = te.EventTypeSK
                                      WHERE  et.EventCode = 'HUB_OUT')
        AND    ShipmentLineSK IN     (SELECT te.ShipmentLineSK FROM core.TrackingEvent AS te
                                      JOIN   core.EventType AS et ON et.EventTypeSK = te.EventTypeSK
                                      WHERE  et.EventCode = 'OUT_FOR_DELIVERY'))
UNION ALL
SELECT '8. Known issues', 'Shipment lines not yet delivered',
       (SELECT COUNT(DISTINCT Business_Key) FROM audit.Exception_Log WHERE Rule_Code = 'IN_TRANSIT'),
       (SELECT COUNT(*) FROM core.ShipmentLine
        WHERE  ShipmentLineSK NOT IN (SELECT te.ShipmentLineSK FROM core.TrackingEvent AS te
                                      JOIN   core.EventType AS et ON et.EventTypeSK = te.EventTypeSK
                                      WHERE  et.EventCode = 'DELIVERED'))
UNION ALL
SELECT '8. Known issues', 'Orders outside January to December 2025',
       (SELECT COUNT(*) FROM audit.Exception_Log WHERE Rule_Code = 'OUT_OF_PERIOD'),
       (SELECT COUNT(*) FROM core.SalesOrder
        WHERE  OrderDateTime < '2025-01-01' OR OrderDateTime >= '2026-01-01')
UNION ALL
-- All 63 are exactly 60 minutes before the shipment was created (36 shipments)
SELECT '8. Known issues', 'PICKED earlier than the shipment was created',
       63,
       (SELECT COUNT(*) FROM core.TrackingEvent AS te
        JOIN   core.EventType    AS et ON et.EventTypeSK = te.EventTypeSK
        JOIN   core.ShipmentLine AS sl ON sl.ShipmentLineSK = te.ShipmentLineSK
        JOIN   core.Shipment      AS s  ON s.ShipmentSK = sl.ShipmentSK
        WHERE  et.EventCode = 'PICKED' AND te.EventDateTime < s.ShipmentCreatedDateTime)
UNION ALL
-- 475 HUB_OUT and 147 HUB_IN scans carry a time later than the delivery
SELECT '8. Known issues', 'Hub scans timed after the DELIVERED event',
       622,
       (SELECT COUNT(*) FROM core.TrackingEvent AS te
        JOIN   core.EventType AS et ON et.EventTypeSK = te.EventTypeSK
        JOIN  (SELECT d.ShipmentLineSK, d.EventDateTime AS Delivered_At
               FROM   core.TrackingEvent AS d
               JOIN   core.EventType AS dt ON dt.EventTypeSK = d.EventTypeSK
               WHERE  dt.EventCode = 'DELIVERED') AS x ON x.ShipmentLineSK = te.ShipmentLineSK
        WHERE  et.EventCode IN ('HUB_IN', 'HUB_OUT') AND te.EventDateTime > x.Delivered_At);


/* ===========================================================================
   RESULTS: 
   =========================================================================== */

-- A. Scorecard. Expected: no FAIL anywhere, and 6 KNOWN ISSUE rows in section 8.
SELECT   Section,
         COUNT(*) AS Checks,
         SUM(CASE WHEN Source_Value = Target_Value AND Section NOT LIKE '8%' THEN 1 ELSE 0 END) AS Passed,
         SUM(CASE WHEN Source_Value = Target_Value AND Section LIKE '8%'     THEN 1 ELSE 0 END) AS Known_Issues,
         SUM(CASE WHEN Source_Value = Target_Value                           THEN 0 ELSE 1 END) AS Failed
FROM     #Checks
GROUP BY Section
ORDER BY Section;

-- B. Every check in detail
SELECT   Section, Check_Name, Source_Value, Target_Value,
         CASE WHEN Source_Value <> Target_Value OR Source_Value IS NULL OR Target_Value IS NULL THEN 'FAIL'
              WHEN Section LIKE '8%' THEN 'KNOWN ISSUE'
              ELSE 'PASS' END AS Result
FROM     #Checks
ORDER BY Check_ID;

-- C. The legacy report trap: freight summed per raw row counts each shipment line
--    once per event. Expected: 243,578.01 against 40,249.18, about 6 times too high.
SELECT  SUM(TRY_CONVERT(DECIMAL(10, 2), REPLACE(Freight_Cost_EUR, ',', '.')))  AS Legacy_Freight_Sum_EUR,
        (SELECT SUM(FreightCostEUR) FROM core.ShipmentLine)                   AS Correct_Freight_EUR,
        CAST(SUM(TRY_CONVERT(DECIMAL(10, 2), REPLACE(Freight_Cost_EUR, ',', '.')))
             / (SELECT SUM(FreightCostEUR) FROM core.ShipmentLine) AS DECIMAL(6, 2)) AS Times_Overstated
FROM    stg.Legacy_Extract_Raw;

DROP TABLE #Checks;
GO
