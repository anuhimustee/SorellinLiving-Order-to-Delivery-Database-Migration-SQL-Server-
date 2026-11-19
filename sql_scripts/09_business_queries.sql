/* =============================================================================
   Operation RouteGlass | Script 09 : Business queries
   Author	: Mustapha (Sir Mustee)
   =============================================================================
   Leadership question: can the new database reconstruct an order's journey and
   hold warehouses and carriers accountable?

     Reconstruction   Q1 journey, Q2 current status, Q3 split shipments
     Carriers         Q4 scorecard, Q5 service level, Q8 hub time, Q9 scan quality,
                      Q10 freight
     Warehouses       Q6 dispatch performance, Q7 where late deliveries started
     Trend            Q11 late deliveries by month

   Definition used throughout
     Late = delivered date is after the promised date. This matches all 843 legacy
     LATE alerts and all 2,973 legacy on-time flags (script 08, section 7).

   Depends : 01 to 07. Run each query on its own. Rerun : safe.
   ============================================================================= */

USE SorellinLivingDB;
GO
SET NOCOUNT ON;
GO

/* -----------------------------------------------------------------------------
   Shared view: one row per delivered shipment line (2,973 rows).
   Late is defined once, here, so every query below uses the same rule.
   ----------------------------------------------------------------------------- */
CREATE OR ALTER VIEW core.vw_Delivered_Line
AS
SELECT  sl.ShipmentLineSK,
        sl.ShipmentSK,
        sl.OrderLineSK,
        s.CarrierSK,
        s.WarehouseSK,
        s.ServiceLevel,
        s.PromisedDeliveryDate,
        te.EventDateTime AS DeliveredAt,
        CASE WHEN CAST(te.EventDateTime AS DATE) > s.PromisedDeliveryDate THEN 1 ELSE 0 END AS IsLate
FROM    core.TrackingEvent AS te
JOIN    core.EventType     AS et ON et.EventTypeSK = te.EventTypeSK
JOIN    core.ShipmentLine  AS sl ON sl.ShipmentLineSK = te.ShipmentLineSK
JOIN    core.Shipment       AS s  ON s.ShipmentSK = sl.ShipmentSK
WHERE   et.EventCode = 'DELIVERED';
GO


/* -----------------------------------------------------------------------------
   Q1. What happened to this order, step by step?
       Proves one order can be followed from customer to last scan.
       Change @OrderNo to follow any order. ORD-00000004 is split into 2 shipments.
       Uses: joins across all 13 tables, LAG window function
       Supported by: UQ_Sales_Order_BK, IX_Shipment_Sales_Order
   ----------------------------------------------------------------------------- */
DECLARE @OrderNo VARCHAR(15) = 'ORD-00000004';

SELECT  so.OrderNo,
        cu.CustomerName,
        so.OrderDateTime,
        sh.ShipmentNo,
        ol.OrderLineNo,
        p.ProductName,
        wl.LocationName AS Warehouse,
        ca.CarrierName,
        sh.ServiceLevel,
        sh.PromisedDeliveryDate,
        et.StandardSequence AS Step,
        et.EventCode,
        te.EventDateTime,
        l.LocationName AS Scan_Location,
        ci.CityName    AS Scan_City,
        ci.CountryName AS Scan_Country,
        DATEDIFF(MINUTE,
                 LAG(te.EventDateTime) OVER (PARTITION BY te.ShipmentLineSK ORDER BY et.StandardSequence),
                 te.EventDateTime) AS Minutes_Since_Previous_Step,
        ex.ExceptionCode AS Alert
FROM    core.SalesOrder    AS so
JOIN    core.Customer       AS cu ON cu.CustomerSK = so.CustomerSK
JOIN    core.Shipment       AS sh ON sh.SalesOrderSK = so.SalesOrderSK
JOIN    core.Warehouse      AS w  ON w.WarehouseSK = sh.WarehouseSK
JOIN    core.Location       AS wl ON wl.LocationSK = w.LocationSK
JOIN    core.Carrier        AS ca ON ca.CarrierSK = sh.CarrierSK
JOIN    core.ShipmentLine  AS sl ON sl.ShipmentSK = sh.ShipmentSK
JOIN    core.OrderLine     AS ol ON ol.OrderLineSK = sl.OrderLineSK
JOIN    core.Product        AS p  ON p.ProductSK = ol.ProductSK
JOIN    core.TrackingEvent AS te ON te.ShipmentLineSK = sl.ShipmentLineSK
JOIN    core.EventType     AS et ON et.EventTypeSK = te.EventTypeSK
JOIN    core.Location       AS l  ON l.LocationSK = te.LocationSK
JOIN    core.City           AS ci ON ci.CitySK = l.CitySK
LEFT JOIN core.ExceptionType AS ex ON ex.ExceptionTypeSK = te.ExceptionTypeSK
WHERE   so.OrderNo = @OrderNo
ORDER BY sh.ShipmentNo, ol.OrderLineNo, et.StandardSequence;
GO


/* -----------------------------------------------------------------------------
   Q2. Where is every shipment line right now?
       Order_Status was not migrated because it can be derived from the events.
       Uses: CTE, ROW_NUMBER window function
       Expected: DELIVERED 2,973 and HUB_OUT 1
   ----------------------------------------------------------------------------- */
WITH Ranked_Events AS
(
    SELECT te.ShipmentLineSK,
           et.EventCode,
           et.StandardSequence,
           ROW_NUMBER() OVER (PARTITION BY te.ShipmentLineSK ORDER BY et.StandardSequence DESC) AS Recency
    FROM   core.TrackingEvent AS te
    JOIN   core.EventType     AS et ON et.EventTypeSK = te.EventTypeSK
)
SELECT   EventCode AS Latest_Milestone,
         CASE WHEN EventCode = 'DELIVERED' THEN 'Delivered' ELSE 'In Transit' END AS Derived_Status,
         COUNT(*)  AS ShipmentLines
FROM     Ranked_Events
WHERE    Recency = 1
GROUP BY EventCode, StandardSequence
ORDER BY StandardSequence DESC;
GO


/* -----------------------------------------------------------------------------
   Q3. How often are orders split, and does a split change the warehouse or carrier?
       Uses: subquery, COUNT DISTINCT
       Expected: 1,329 single-shipment orders and 180 split orders. Every split
       order stays with one warehouse and one carrier.
   ----------------------------------------------------------------------------- */
SELECT   Shipments_Per_Order,
         Warehouses_Per_Order,
         Carriers_Per_Order,
         COUNT(*) AS Orders
FROM    (SELECT SalesOrderSK,
                COUNT(*)                    AS Shipments_Per_Order,
                COUNT(DISTINCT WarehouseSK) AS Warehouses_Per_Order,
                COUNT(DISTINCT CarrierSK)   AS Carriers_Per_Order
         FROM   core.Shipment
         GROUP BY SalesOrderSK) AS o
GROUP BY Shipments_Per_Order, Warehouses_Per_Order, Carriers_Per_Order
ORDER BY Shipments_Per_Order, Warehouses_Per_Order, Carriers_Per_Order;
GO


/* -----------------------------------------------------------------------------
   Q4. Which carriers deliver late most often? Evidence for the contract talks.
       Uses: joins, aggregation, RANK window function
       Supported by: IX_Shipment_Carrier, IX_Tracking_Event_Type_Time
       Expected: NordRoute is worst at 35.86%; Alpina is best at 22.08%
   ----------------------------------------------------------------------------- */
SELECT   c.CarrierCode,
         c.CarrierName,
         COUNT(*)                                        AS Delivered_Lines,
         SUM(d.IsLate)                                   AS Late_Lines,
         CAST(100.0 * SUM(d.IsLate) / COUNT(*) AS DECIMAL(5, 2)) AS Late_Percent,
         RANK() OVER (ORDER BY 1.0 * SUM(d.IsLate) / COUNT(*) DESC) AS Worst_Rank
FROM     core.vw_Delivered_Line AS d
JOIN     core.Carrier AS c ON c.CarrierSK = d.CarrierSK
GROUP BY c.CarrierCode, c.CarrierName
ORDER BY Worst_Rank;
GO


/* -----------------------------------------------------------------------------
   Q5. Does each carrier keep its promise on every service level?
       Shows whether a premium service actually delivers better.
       Uses: joins, aggregation
       Expected: Priority has the highest late rate at all 6 carriers (37% to 58%)
   ----------------------------------------------------------------------------- */
SELECT   c.CarrierName,
         d.ServiceLevel,
         COUNT(*)                                        AS Delivered_Lines,
         SUM(d.IsLate)                                   AS Late_Lines,
         CAST(100.0 * SUM(d.IsLate) / COUNT(*) AS DECIMAL(5, 2)) AS Late_Percent
FROM     core.vw_Delivered_Line AS d
JOIN     core.Carrier AS c ON c.CarrierSK = d.CarrierSK
GROUP BY c.CarrierName, d.ServiceLevel
ORDER BY c.CarrierName, d.ServiceLevel;
GO


/* -----------------------------------------------------------------------------
   Q6. Which warehouses dispatch after the planned date?
       Late dispatch is the warehouse's part of the journey.
       Uses: joins, aggregation, conditional counts
       Supported by: IX_Shipment_Warehouse
       Expected: Lille is highest at 57.30%; the other three are 46% to 48%
   ----------------------------------------------------------------------------- */
SELECT   w.WarehouseCode,
         l.LocationName AS Warehouse,
         COUNT(*)       AS Shipments,
         SUM(CASE WHEN CAST(s.ActualDispatchDateTime AS DATE) > s.PlannedDispatchDate THEN 1 ELSE 0 END) AS Dispatched_Late,
         CAST(100.0 * SUM(CASE WHEN CAST(s.ActualDispatchDateTime AS DATE) > s.PlannedDispatchDate THEN 1 ELSE 0 END)
              / COUNT(*) AS DECIMAL(5, 2))                                                               AS Dispatched_Late_Percent
FROM     core.Shipment  AS s
JOIN     core.Warehouse AS w ON w.WarehouseSK = s.WarehouseSK
JOIN     core.Location  AS l ON l.LocationSK = w.LocationSK
GROUP BY w.WarehouseCode, l.LocationName
ORDER BY Dispatched_Late_Percent DESC;
GO


/* -----------------------------------------------------------------------------
   Q7. Where did late deliveries start: at the warehouse or after it left?
       Dispatched on time but delivered late points to the carrier leg.
       Dispatched late points to the warehouse, at least in part.
       This shows where the delay began. It does not prove the full cause.
       Uses: CTE, joins, SUM window function
       Expected: 598 of the 843 late lines were dispatched late; 245 left on time
   ----------------------------------------------------------------------------- */
WITH Late_Lines AS
(
    SELECT c.CarrierName,
           CASE WHEN CAST(s.ActualDispatchDateTime AS DATE) > s.PlannedDispatchDate
                THEN 'Dispatched late' ELSE 'Dispatched on time' END AS Dispatch_Result
    FROM   core.vw_Delivered_Line AS d
    JOIN   core.Shipment AS s ON s.ShipmentSK = d.ShipmentSK
    JOIN   core.Carrier  AS c ON c.CarrierSK = d.CarrierSK
    WHERE  d.IsLate = 1
)
SELECT   CarrierName,
         Dispatch_Result,
         COUNT(*) AS Late_Lines,
         CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY CarrierName) AS DECIMAL(5, 2)) AS Percent_Of_Carrier_Late_Lines
FROM     Late_Lines
GROUP BY CarrierName, Dispatch_Result
ORDER BY CarrierName, Dispatch_Result;
GO


/* -----------------------------------------------------------------------------
   Q8. How long do parcels wait at each hub?
       Only lines with both scans in the right order are measured. The excluded
       column shows what the 46 missing scans and 56 out-of-order scans remove.
       Uses: CTE, conditional aggregation, joins
       Supported by: IX_Tracking_Event_Type_Time
       Expected: every hub averages about 14 hours
   ----------------------------------------------------------------------------- */
WITH Hub_Scans AS
(
    SELECT te.ShipmentLineSK,
           MAX(CASE WHEN et.EventCode = 'HUB_IN'  THEN te.LocationSK END)    AS HubSK,
           MAX(CASE WHEN et.EventCode = 'HUB_IN'  THEN te.EventDateTime END) AS Hub_In,
           MAX(CASE WHEN et.EventCode = 'HUB_OUT' THEN te.EventDateTime END) AS Hub_Out
    FROM   core.TrackingEvent AS te
    JOIN   core.EventType     AS et ON et.EventTypeSK = te.EventTypeSK
    WHERE  et.EventCode IN ('HUB_IN', 'HUB_OUT')
    GROUP BY te.ShipmentLineSK
)
SELECT   l.LocationName AS Hub,
         SUM(CASE WHEN h.Hub_Out >= h.Hub_In THEN 1 ELSE 0 END) AS Lines_Measured,
         SUM(CASE WHEN h.Hub_Out >= h.Hub_In THEN 0 ELSE 1 END) AS Lines_Excluded,
         CAST(AVG(CASE WHEN h.Hub_Out >= h.Hub_In
                       THEN DATEDIFF(MINUTE, h.Hub_In, h.Hub_Out) / 60.0 END) AS DECIMAL(6, 2)) AS Average_Hours_At_Hub
FROM     Hub_Scans AS h
JOIN     core.Location AS l ON l.LocationSK = h.HubSK
GROUP BY l.LocationName
ORDER BY Average_Hours_At_Hub DESC;
GO


/* -----------------------------------------------------------------------------
   Q9. Which carriers have the weakest scan records?
       A carrier that cannot prove the journey is an accountability risk.
       Uses: CTEs, LAG window function, joins
       Expected: all 46 missing HUB_OUT scans are on NordRoute (C01), at Liege Hub
   ----------------------------------------------------------------------------- */
WITH Line_Scans AS
(
    SELECT te.ShipmentLineSK,
           et.EventCode,
           te.ExceptionTypeSK,
           te.EventDateTime,
           LAG(te.EventDateTime) OVER (PARTITION BY te.ShipmentLineSK ORDER BY et.StandardSequence) AS Previous_Time
    FROM   core.TrackingEvent AS te
    JOIN   core.EventType     AS et ON et.EventTypeSK = te.EventTypeSK
),
Line_Summary AS
(
    SELECT ShipmentLineSK,
           COUNT(*) AS Events,
           SUM(CASE WHEN EventDateTime < Previous_Time THEN 1 ELSE 0 END) AS Out_Of_Sequence,
           SUM(CASE WHEN x.ExceptionCode = 'SCAN_GAP' THEN 1 ELSE 0 END)  AS Missing_Hub_Out
    FROM   Line_Scans AS e
    LEFT JOIN core.ExceptionType AS x ON x.ExceptionTypeSK = e.ExceptionTypeSK
    GROUP BY ShipmentLineSK
)
SELECT   c.CarrierCode,
         c.CarrierName,
         COUNT(*)               AS Shipment_Lines,
         SUM(ls.Events)         AS Events,
         SUM(ls.Missing_Hub_Out) AS Missing_Hub_Out_Scans,
         SUM(ls.Out_Of_Sequence) AS Out_Of_Sequence_Events,
         CAST(100.0 * SUM(ls.Out_Of_Sequence) / SUM(ls.Events) AS DECIMAL(5, 2)) AS Out_Of_Sequence_Percent
FROM     Line_Summary AS ls
JOIN     core.ShipmentLine AS sl ON sl.ShipmentLineSK = ls.ShipmentLineSK
JOIN     core.Shipment      AS s  ON s.ShipmentSK = sl.ShipmentSK
JOIN     core.Carrier       AS c  ON c.CarrierSK = s.CarrierSK
GROUP BY c.CarrierCode, c.CarrierName
ORDER BY Missing_Hub_Out_Scans DESC, Out_Of_Sequence_Percent DESC;
GO


/* -----------------------------------------------------------------------------
   Q10. What does Sorellin pay each carrier, per kilogram?
        Freight is summed per shipment line, the correct grain, so the legacy
        overstatement cannot happen.
        Uses: joins, aggregation, SUM window function
        Expected: 40,249.18 EUR in total, at 0.58 to 0.66 EUR per kg
   ----------------------------------------------------------------------------- */
SELECT   c.CarrierName,
         SUM(sl.FreightCostEUR)                                 AS Freight_EUR,
         SUM(sl.ShipmentLineQuantity * p.UnitWeightKg)          AS Weight_Kg,
         CAST(SUM(sl.FreightCostEUR)
              / SUM(sl.ShipmentLineQuantity * p.UnitWeightKg) AS DECIMAL(8, 2)) AS Freight_EUR_Per_Kg,
         CAST(100.0 * SUM(sl.FreightCostEUR)
              / SUM(SUM(sl.FreightCostEUR)) OVER () AS DECIMAL(5, 2))           AS Percent_Of_Total_Freight
FROM     core.ShipmentLine AS sl
JOIN     core.Shipment   AS s  ON s.ShipmentSK = sl.ShipmentSK
JOIN     core.Carrier    AS c  ON c.CarrierSK = s.CarrierSK
JOIN     core.OrderLine AS ol ON ol.OrderLineSK = sl.OrderLineSK
JOIN     core.Product    AS p  ON p.ProductSK = ol.ProductSK
GROUP BY c.CarrierName
ORDER BY Freight_EUR DESC;
GO


/* -----------------------------------------------------------------------------
   Q11. Are late deliveries getting worse? Tests the rise in complaints.
        Late is grouped by delivery date. January 2026 holds only 37 lines.
        Uses: CTE, rolling 3-month window function
        Expected: no upward trend; the rolling rate falls from 34.21% in February
        to 26.47% in December 2025
   ----------------------------------------------------------------------------- */
WITH Monthly AS
(
    SELECT YEAR(DeliveredAt)  AS Delivery_Year,
           MONTH(DeliveredAt) AS Delivery_Month,
           COUNT(*)           AS Delivered_Lines,
           SUM(IsLate)        AS Late_Lines
    FROM   core.vw_Delivered_Line
    GROUP BY YEAR(DeliveredAt), MONTH(DeliveredAt)
)
SELECT   Delivery_Year,
         Delivery_Month,
         Delivered_Lines,
         Late_Lines,
         CAST(100.0 * Late_Lines / Delivered_Lines AS DECIMAL(5, 2)) AS Late_Percent,
         CAST(100.0 * SUM(Late_Lines)      OVER (ORDER BY Delivery_Year, Delivery_Month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
                    / SUM(Delivered_Lines) OVER (ORDER BY Delivery_Year, Delivery_Month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
              AS DECIMAL(5, 2)) AS Rolling_3_Month_Late_Percent
FROM     Monthly
ORDER BY Delivery_Year, Delivery_Month;
GO
