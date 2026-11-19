/* =============================================================================
   Operation RouteGlass | Script 06 : Migrate clean data into the 3NF tables
   Author	: Mustapha (Sir Mustee)
   =============================================================================
   Source : stg.Clean_Extract (cleaned, deduplicated and logged in script 04)
   Target : the 13 core tables (created in script 05)

   Every INSERT follows one pattern:
     1. Parents first, then children.
     2. SELECT DISTINCT gives one row per business key. Script 04 (check E3)
        proved each business key has only one set of values.
     3. A child finds its parent's surrogate key by joining on the business key.

   Rerun : run 05 first (it empties the tables), then 06, then 07.
   ============================================================================= */

USE SorellinLivingDB;
GO
SET NOCOUNT ON;
SET NOEXEC OFF;
GO

-- Stop if the tables already hold data, so rows can never be doubled
IF EXISTS (SELECT 1 FROM core.City)
BEGIN
    RAISERROR('core tables already hold data. Run 05 again, then 06.', 16, 1);
    SET NOEXEC ON;
END;
GO


/* ===========================================================================
   LEVEL 1 : tables with no parent
   =========================================================================== */

-- 1. City: every customer city plus every warehouse and hub city
INSERT INTO core.City (CityName, CountryName)
SELECT Delivery_City, Delivery_Country
FROM   stg.Clean_Extract
WHERE  Delivery_City IS NOT NULL
UNION
SELECT City_Name, Country_Name
FROM   map.Location
ORDER BY Delivery_Country, Delivery_City;

-- 2. Product
INSERT INTO core.Product (ProductSKU, ProductName, ProductCategory, UnitWeightKg, UnitPriceEUR)
SELECT DISTINCT Product_SKU, Product_Name, Product_Category, Unit_Weight_kg, Unit_Price_EUR
FROM   stg.Clean_Extract
ORDER BY Product_SKU;

-- 3. Carrier: the standard name and prefix from the mapping table
INSERT INTO core.Carrier (CarrierCode, CarrierName, TrackingPrefix)
SELECT Carrier_Code, Carrier_Name, Tracking_Prefix
FROM   map.Carrier
ORDER BY Carrier_Code;

-- 4. Event_Type: PICKED and DISPATCHED happen at a warehouse, the rest at a hub
INSERT INTO core.EventType (EventCode, EventDescription, StandardSequence, ExpectedLocationType)
SELECT DISTINCT Tracking_Event_Code, Tracking_Event_Description, Event_Sequence,
       CASE WHEN Event_Sequence <= 2 THEN 'Warehouse' ELSE 'Hub' END
FROM   stg.Clean_Extract
ORDER BY Event_Sequence;

-- 5. Exception_Type
INSERT INTO core.ExceptionType (ExceptionCode, ExceptionDescription)
SELECT DISTINCT Exception_Code, Exception_Description
FROM   stg.Clean_Extract
WHERE  Exception_Code IS NOT NULL
ORDER BY Exception_Code;


/* ===========================================================================
   LEVEL 2 : children of City
   =========================================================================== */

-- 6. Customer
INSERT INTO core.Customer (CustomerID, CustomerName, CustomerEmail, CustomerType,
                           DeliveryAddressLine, DeliveryPostalCode, CitySK)
SELECT DISTINCT c.Customer_ID, c.Customer_Name, c.Customer_Email, c.Customer_Type,
       c.Delivery_Address_Line, c.Delivery_Postal_Code, ci.CitySK
FROM   stg.Clean_Extract AS c
LEFT JOIN core.City AS ci ON ci.CityName = c.Delivery_City AND ci.CountryName = c.Delivery_Country
ORDER BY c.Customer_ID;

-- 7. Location: warehouses and hubs from the mapping table
INSERT INTO core.Location (LocationName, LocationType, CitySK)
SELECT m.Location_Name, m.Location_Type, ci.CitySK
FROM   map.Location AS m
JOIN   core.City AS ci ON ci.CityName = m.City_Name AND ci.CountryName = m.Country_Name
ORDER BY m.Location_Type DESC, m.Location_Name;


/* ===========================================================================
   LEVEL 3 : children of Location and Customer
   =========================================================================== */

-- 8. Warehouse
INSERT INTO core.Warehouse (WarehouseCode, LocationSK)
SELECT DISTINCT c.Warehouse_Code, l.LocationSK
FROM   stg.Clean_Extract AS c
JOIN   core.Location AS l ON l.LocationName = c.Warehouse_Name
ORDER BY c.Warehouse_Code;

-- 9. Sales_Order
INSERT INTO core.SalesOrder (OrderNo, CustomerSK, OrderDateTime)
SELECT DISTINCT c.Order_No, cu.CustomerSK, c.Order_DateTime
FROM   stg.Clean_Extract AS c
JOIN   core.Customer AS cu ON cu.CustomerID = c.Customer_ID
ORDER BY c.Order_No;


/* ===========================================================================
   LEVEL 4 : children of Sales_Order
   =========================================================================== */

-- 10. Order_Line
INSERT INTO core.OrderLine (SalesOrderSK, OrderLineNo, ProductSK, QuantityOrdered)
SELECT DISTINCT so.SalesOrderSK, c.Order_Line_No, p.ProductSK, c.Quantity_Ordered
FROM   stg.Clean_Extract AS c
JOIN   core.SalesOrder AS so ON so.OrderNo = c.Order_No
JOIN   core.Product     AS p  ON p.ProductSKU = c.Product_SKU
ORDER BY so.SalesOrderSK, c.Order_Line_No;

-- 11. Shipment. Proof of delivery is filled only on DELIVERED rows, so MAX picks
--     the one real value and each shipment stays one row. (SQL Server may print
--     "Null value is eliminated by an aggregate". That message is expected.)
INSERT INTO core.Shipment (ShipmentNo, SalesOrderSK, WarehouseSK, CarrierSK, ServiceLevel, TrackingNo,
                           ShipmentCreatedDateTime, PlannedDispatchDate, ActualDispatchDateTime,
                           PromisedDeliveryDate, ProofOfDeliveryRef)
SELECT   c.Shipment_No, so.SalesOrderSK, w.WarehouseSK, ca.CarrierSK, c.Carrier_Service_Level, c.Tracking_No,
         c.Shipment_Created_DateTime, c.Planned_Dispatch_Date, c.Actual_Dispatch_DateTime,
         c.Promised_Delivery_Date, MAX(c.Proof_of_Delivery_Ref)
FROM     stg.Clean_Extract AS c
JOIN     core.SalesOrder AS so ON so.OrderNo = c.Order_No
JOIN     core.Warehouse   AS w  ON w.WarehouseCode = c.Warehouse_Code
JOIN     core.Carrier     AS ca ON ca.CarrierCode = c.Carrier_Code
GROUP BY c.Shipment_No, so.SalesOrderSK, w.WarehouseSK, ca.CarrierSK, c.Carrier_Service_Level, c.Tracking_No,
         c.Shipment_Created_DateTime, c.Planned_Dispatch_Date, c.Actual_Dispatch_DateTime,
         c.Promised_Delivery_Date
ORDER BY c.Shipment_No;


/* ===========================================================================
   LEVEL 5 : Shipment_Line, the bridge between Shipment and Order_Line
   =========================================================================== */

-- 12. Shipment_Line
INSERT INTO core.ShipmentLine (ShipmentSK, OrderLineSK, ShipmentLineQuantity, FreightCostEUR)
SELECT DISTINCT s.ShipmentSK, ol.OrderLineSK, c.Shipment_Line_Quantity, c.Freight_Cost_EUR
FROM   stg.Clean_Extract AS c
JOIN   core.Shipment   AS s  ON s.ShipmentNo = c.Shipment_No
JOIN   core.OrderLine AS ol ON ol.SalesOrderSK = s.SalesOrderSK AND ol.OrderLineNo = c.Order_Line_No
ORDER BY s.ShipmentSK, ol.OrderLineSK;


/* ===========================================================================
   LEVEL 6 : Tracking_Event, one row per clean source row
   =========================================================================== */

-- 13. Tracking_Event
INSERT INTO core.TrackingEvent (TrackingEventID, ShipmentLineSK, EventTypeSK, EventDateTime,
                                 LocationSK, ExceptionTypeSK, LegacyRowID)
SELECT c.Tracking_Event_ID, sl.ShipmentLineSK, et.EventTypeSK, c.Tracking_Event_DateTime,
       l.LocationSK, ex.ExceptionTypeSK, c.Legacy_Row_ID
FROM   stg.Clean_Extract AS c
JOIN   core.Shipment      AS s  ON s.ShipmentNo = c.Shipment_No
JOIN   core.OrderLine    AS ol ON ol.SalesOrderSK = s.SalesOrderSK AND ol.OrderLineNo = c.Order_Line_No
JOIN   core.ShipmentLine AS sl ON sl.ShipmentSK = s.ShipmentSK AND sl.OrderLineSK = ol.OrderLineSK
JOIN   core.EventType    AS et ON et.EventCode = c.Tracking_Event_Code
JOIN   core.Location      AS l  ON l.LocationName = c.Event_Location
LEFT JOIN core.ExceptionType AS ex ON ex.ExceptionCode = c.Exception_Code
ORDER BY c.Tracking_Event_ID;
GO


/* ===========================================================================
   EVIDENCE : 
   =========================================================================== */

-- 1. Control total: 18,000 - 140 - 64 = 17,796 events in core
SELECT  (SELECT COUNT(*) FROM stg.Legacy_Extract_Raw)                                      AS Source_Rows,
        (SELECT COUNT(*) FROM audit.Exception_Log WHERE Rule_Code = 'EXACT_DUPLICATE')     AS Exact_Duplicates,
        (SELECT COUNT(*) FROM audit.Exception_Log WHERE Rule_Code = 'REPEATED_SCAN')       AS Repeated_Scans,
        (SELECT COUNT(*) FROM core.TrackingEvent)                                         AS Events_In_Core;

-- 2. Rows loaded into each table against the expected count
SELECT  Core_Table, Loaded, Expected,
        CASE WHEN Loaded = Expected THEN 'PASS' ELSE 'FAIL' END AS Result
FROM   (SELECT 'City' AS Core_Table, (SELECT COUNT(*) FROM core.City) AS Loaded, 21 AS Expected
        UNION ALL SELECT 'Product',        (SELECT COUNT(*) FROM core.Product),        72
        UNION ALL SELECT 'Carrier',        (SELECT COUNT(*) FROM core.Carrier),        6
        UNION ALL SELECT 'EventType',     (SELECT COUNT(*) FROM core.EventType),     6
        UNION ALL SELECT 'ExceptionType', (SELECT COUNT(*) FROM core.ExceptionType), 2
        UNION ALL SELECT 'Customer',       (SELECT COUNT(*) FROM core.Customer),       972
        UNION ALL SELECT 'Location',       (SELECT COUNT(*) FROM core.Location),       9
        UNION ALL SELECT 'Warehouse',      (SELECT COUNT(*) FROM core.Warehouse),      4
        UNION ALL SELECT 'SalesOrder',    (SELECT COUNT(*) FROM core.SalesOrder),    1509
        UNION ALL SELECT 'OrderLine',     (SELECT COUNT(*) FROM core.OrderLine),     2974
        UNION ALL SELECT 'Shipment',       (SELECT COUNT(*) FROM core.Shipment),       1689
        UNION ALL SELECT 'ShipmentLine',  (SELECT COUNT(*) FROM core.ShipmentLine),  2974
        UNION ALL SELECT 'TrackingEvent', (SELECT COUNT(*) FROM core.TrackingEvent), 17796) AS t;

-- 3. Business totals (expected: 7,462 / 7,462 / 960,199.50 / 40,249.18)
SELECT  (SELECT SUM(QuantityOrdered)      FROM core.OrderLine)    AS Quantity_Ordered,
        (SELECT SUM(ShipmentLineQuantity) FROM core.ShipmentLine) AS Quantity_Shipped,
        (SELECT SUM(ol.QuantityOrdered * p.UnitPriceEUR)
         FROM core.OrderLine AS ol
         JOIN core.Product    AS p ON p.ProductSK = ol.ProductSK)  AS Order_Value_EUR,
        (SELECT SUM(FreightCostEUR)       FROM core.ShipmentLine) AS Freight_Cost_EUR;
GO

SET NOEXEC OFF;   -- reset in case the first check stopped execution
GO
