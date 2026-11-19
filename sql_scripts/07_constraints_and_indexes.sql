/* =============================================================================
   Operation RouteGlass | Script 07 : Constraints and indexes
   Author	: Mustapha (Sir Mustee)
   -----------------------------------------------------------------------------
   Purpose  : Enforce the business rules on the migrated data:
                1. PRIMARY KEY   - the surrogate key of every table (clustered)
                2. UNIQUE        - the source business key of every table, plus
                                   any other candidate keys
                3. FOREIGN KEY   - every relationship, child -> parent surrogate
                4. CHECK         - domain and same-row business rules
                5. Indexes       - only those that support known queries
   Depends  : 05_create_3nf_schema.sql and 06_migrate_data.sql
   Rerun    : Safe. Each object is created only if it does not already exist.
              To rerun the whole migration: run 05, then 06, then 07.

   Why after 06: the brief asks for constraints to be added once the data is
   ready for enforcement. Every constraint is added WITH CHECK (the default),
   so SQL Server validates all migrated rows and marks it as trusted. If any
   row broke a rule, this script would fail and name the constraint.

   Naming
     PK_<Table>        primary key on <Table>SK
     UQ_<Table>_BK     the source business key (the candidate key from the
                       legacy file). One per table, without exception.
     UQ_<Table>_<Col>  any further candidate key
     FK_<Child>_<Parent>, CK_<Table>_<Rule>, IX_<Table>_<Columns>

   Clustered vs nonclustered
     The surrogate PK is the CLUSTERED index: a narrow, ever-increasing
     integer, so inserts append to the end of the table and every
     nonclustered index carries only a small key.
     Business-key UNIQUE constraints are NONCLUSTERED. Besides blocking
     duplicates, they make look-ups by business code fast, which is how users
     search (WHERE OrderNo = 'ORD-00000943').

   Rules that span two tables (shipment created after its order, tracking
   number starts with its carrier's prefix, order line belongs to the same
   order as its shipment, milestones in time order) cannot be CHECK
   constraints. They are tested in 08_validation_and_reconciliation.
   ============================================================================= */

USE SorellinLivingDB;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;   -- required for filtered indexes
GO

/* ===========================================================================
   1. PRIMARY KEYS: the surrogate key of every table
   =========================================================================== */
IF OBJECT_ID(N'core.PK_City', N'PK') IS NULL
    ALTER TABLE core.City           ADD CONSTRAINT PK_City           PRIMARY KEY CLUSTERED (CitySK);
IF OBJECT_ID(N'core.PK_Customer', N'PK') IS NULL
    ALTER TABLE core.Customer       ADD CONSTRAINT PK_Customer       PRIMARY KEY CLUSTERED (CustomerSK);
IF OBJECT_ID(N'core.PK_Product', N'PK') IS NULL
    ALTER TABLE core.Product        ADD CONSTRAINT PK_Product        PRIMARY KEY CLUSTERED (ProductSK);
IF OBJECT_ID(N'core.PK_Location', N'PK') IS NULL
    ALTER TABLE core.Location       ADD CONSTRAINT PK_Location       PRIMARY KEY CLUSTERED (LocationSK);
IF OBJECT_ID(N'core.PK_Warehouse', N'PK') IS NULL
    ALTER TABLE core.Warehouse      ADD CONSTRAINT PK_Warehouse      PRIMARY KEY CLUSTERED (WarehouseSK);
IF OBJECT_ID(N'core.PK_Carrier', N'PK') IS NULL
    ALTER TABLE core.Carrier        ADD CONSTRAINT PK_Carrier        PRIMARY KEY CLUSTERED (CarrierSK);
IF OBJECT_ID(N'core.PK_Event_Type', N'PK') IS NULL
    ALTER TABLE core.EventType     ADD CONSTRAINT PK_Event_Type     PRIMARY KEY CLUSTERED (EventTypeSK);
IF OBJECT_ID(N'core.PK_Exception_Type', N'PK') IS NULL
    ALTER TABLE core.ExceptionType ADD CONSTRAINT PK_Exception_Type PRIMARY KEY CLUSTERED (ExceptionTypeSK);
IF OBJECT_ID(N'core.PK_Sales_Order', N'PK') IS NULL
    ALTER TABLE core.SalesOrder    ADD CONSTRAINT PK_Sales_Order    PRIMARY KEY CLUSTERED (SalesOrderSK);
IF OBJECT_ID(N'core.PK_Order_Line', N'PK') IS NULL
    ALTER TABLE core.OrderLine     ADD CONSTRAINT PK_Order_Line     PRIMARY KEY CLUSTERED (OrderLineSK);
IF OBJECT_ID(N'core.PK_Shipment', N'PK') IS NULL
    ALTER TABLE core.Shipment       ADD CONSTRAINT PK_Shipment       PRIMARY KEY CLUSTERED (ShipmentSK);
IF OBJECT_ID(N'core.PK_Shipment_Line', N'PK') IS NULL
    ALTER TABLE core.ShipmentLine  ADD CONSTRAINT PK_Shipment_Line  PRIMARY KEY CLUSTERED (ShipmentLineSK);
IF OBJECT_ID(N'core.PK_Tracking_Event', N'PK') IS NULL
    ALTER TABLE core.TrackingEvent ADD CONSTRAINT PK_Tracking_Event PRIMARY KEY CLUSTERED (TrackingEventSK);
GO

/* ===========================================================================
   2a. BUSINESS KEYS (UQ_<Table>_BK): the identifier from the source file.
       These are what stop duplicates, because an IDENTITY never repeats.
   =========================================================================== */
IF OBJECT_ID(N'core.UQ_City_BK', N'UQ') IS NULL
    ALTER TABLE core.City           ADD CONSTRAINT UQ_City_BK           UNIQUE (CityName, CountryName);
IF OBJECT_ID(N'core.UQ_Customer_BK', N'UQ') IS NULL
    ALTER TABLE core.Customer       ADD CONSTRAINT UQ_Customer_BK       UNIQUE (CustomerID);
IF OBJECT_ID(N'core.UQ_Product_BK', N'UQ') IS NULL
    ALTER TABLE core.Product        ADD CONSTRAINT UQ_Product_BK        UNIQUE (ProductSKU);
IF OBJECT_ID(N'core.UQ_Location_BK', N'UQ') IS NULL
    ALTER TABLE core.Location       ADD CONSTRAINT UQ_Location_BK       UNIQUE (LocationName);
IF OBJECT_ID(N'core.UQ_Warehouse_BK', N'UQ') IS NULL
    ALTER TABLE core.Warehouse      ADD CONSTRAINT UQ_Warehouse_BK      UNIQUE (WarehouseCode);
IF OBJECT_ID(N'core.UQ_Carrier_BK', N'UQ') IS NULL
    ALTER TABLE core.Carrier        ADD CONSTRAINT UQ_Carrier_BK        UNIQUE (CarrierCode);
IF OBJECT_ID(N'core.UQ_Event_Type_BK', N'UQ') IS NULL
    ALTER TABLE core.EventType     ADD CONSTRAINT UQ_Event_Type_BK     UNIQUE (EventCode);
IF OBJECT_ID(N'core.UQ_Exception_Type_BK', N'UQ') IS NULL
    ALTER TABLE core.ExceptionType ADD CONSTRAINT UQ_Exception_Type_BK UNIQUE (ExceptionCode);
IF OBJECT_ID(N'core.UQ_Sales_Order_BK', N'UQ') IS NULL
    ALTER TABLE core.SalesOrder    ADD CONSTRAINT UQ_Sales_Order_BK    UNIQUE (OrderNo);
-- (OrderNo, OrderLineNo), held as (SalesOrderSK, OrderLineNo)
IF OBJECT_ID(N'core.UQ_Order_Line_BK', N'UQ') IS NULL
    ALTER TABLE core.OrderLine     ADD CONSTRAINT UQ_Order_Line_BK     UNIQUE (SalesOrderSK, OrderLineNo);
IF OBJECT_ID(N'core.UQ_Shipment_BK', N'UQ') IS NULL
    ALTER TABLE core.Shipment       ADD CONSTRAINT UQ_Shipment_BK       UNIQUE (ShipmentNo);
-- An order line appears at most once in a given shipment
IF OBJECT_ID(N'core.UQ_Shipment_Line_BK', N'UQ') IS NULL
    ALTER TABLE core.ShipmentLine  ADD CONSTRAINT UQ_Shipment_Line_BK  UNIQUE (ShipmentSK, OrderLineSK);
IF OBJECT_ID(N'core.UQ_Tracking_Event_BK', N'UQ') IS NULL
    ALTER TABLE core.TrackingEvent ADD CONSTRAINT UQ_Tracking_Event_BK UNIQUE (TrackingEventID);
GO

/* ===========================================================================
   2b. OTHER CANDIDATE KEYS
   =========================================================================== */
-- One customer per e-mail address
IF OBJECT_ID(N'core.UQ_Customer_Email', N'UQ') IS NULL
    ALTER TABLE core.Customer ADD CONSTRAINT UQ_Customer_Email UNIQUE (CustomerEmail);

-- Product names are unique (72 names for 72 SKUs)
IF OBJECT_ID(N'core.UQ_Product_Name', N'UQ') IS NULL
    ALTER TABLE core.Product ADD CONSTRAINT UQ_Product_Name UNIQUE (ProductName);

-- Warehouse is a 1:1 subtype of Location
IF OBJECT_ID(N'core.UQ_Warehouse_Location', N'UQ') IS NULL
    ALTER TABLE core.Warehouse ADD CONSTRAINT UQ_Warehouse_Location UNIQUE (LocationSK);

-- One standard name and one tracking prefix per carrier
IF OBJECT_ID(N'core.UQ_Carrier_Name', N'UQ') IS NULL
    ALTER TABLE core.Carrier ADD CONSTRAINT UQ_Carrier_Name UNIQUE (CarrierName);
IF OBJECT_ID(N'core.UQ_Carrier_Tracking_Prefix', N'UQ') IS NULL
    ALTER TABLE core.Carrier ADD CONSTRAINT UQ_Carrier_Tracking_Prefix UNIQUE (TrackingPrefix);

-- Each milestone has its own description and its own position in the journey
IF OBJECT_ID(N'core.UQ_Event_Type_Description', N'UQ') IS NULL
    ALTER TABLE core.EventType ADD CONSTRAINT UQ_Event_Type_Description UNIQUE (EventDescription);
IF OBJECT_ID(N'core.UQ_Event_Type_Sequence', N'UQ') IS NULL
    ALTER TABLE core.EventType ADD CONSTRAINT UQ_Event_Type_Sequence UNIQUE (StandardSequence);

IF OBJECT_ID(N'core.UQ_Exception_Type_Description', N'UQ') IS NULL
    ALTER TABLE core.ExceptionType ADD CONSTRAINT UQ_Exception_Type_Description UNIQUE (ExceptionDescription);

-- One tracking number per shipment
IF OBJECT_ID(N'core.UQ_Shipment_Tracking_No', N'UQ') IS NULL
    ALTER TABLE core.Shipment ADD CONSTRAINT UQ_Shipment_Tracking_No UNIQUE (TrackingNo);

-- One event per milestone per shipment line (the 64 repeated scans are
-- removed in 04 and logged in audit.Exception_Log)
IF OBJECT_ID(N'core.UQ_Tracking_Event_Line_Event', N'UQ') IS NULL
    ALTER TABLE core.TrackingEvent ADD CONSTRAINT UQ_Tracking_Event_Line_Event UNIQUE (ShipmentLineSK, EventTypeSK);

-- Every event traces back to exactly one source row
IF OBJECT_ID(N'core.UQ_Tracking_Event_Legacy_Row', N'UQ') IS NULL
    ALTER TABLE core.TrackingEvent ADD CONSTRAINT UQ_Tracking_Event_Legacy_Row UNIQUE (LegacyRowID);
GO

/* Proof of delivery is unique when present. A UNIQUE constraint would allow
   only ONE NULL, but every undelivered shipment has a NULL POD, so a filtered
   unique index is used instead. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE  name = N'UX_Shipment_Proof_of_Delivery'
               AND    object_id = OBJECT_ID(N'core.Shipment'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_Shipment_Proof_of_Delivery
        ON core.Shipment (ProofOfDeliveryRef)
        WHERE ProofOfDeliveryRef IS NOT NULL;
GO

/* ===========================================================================
   3. FOREIGN KEYS: child column -> parent surrogate key
   ON DELETE / ON UPDATE default to NO ACTION, so a parent with history
   (e.g. a carrier with shipments) cannot be deleted by accident.
   =========================================================================== */
IF OBJECT_ID(N'core.FK_Customer_City', N'F') IS NULL
    ALTER TABLE core.Customer ADD CONSTRAINT FK_Customer_City
        FOREIGN KEY (CitySK) REFERENCES core.City (CitySK);

IF OBJECT_ID(N'core.FK_Location_City', N'F') IS NULL
    ALTER TABLE core.Location ADD CONSTRAINT FK_Location_City
        FOREIGN KEY (CitySK) REFERENCES core.City (CitySK);

IF OBJECT_ID(N'core.FK_Warehouse_Location', N'F') IS NULL
    ALTER TABLE core.Warehouse ADD CONSTRAINT FK_Warehouse_Location
        FOREIGN KEY (LocationSK) REFERENCES core.Location (LocationSK);

IF OBJECT_ID(N'core.FK_Sales_Order_Customer', N'F') IS NULL
    ALTER TABLE core.SalesOrder ADD CONSTRAINT FK_Sales_Order_Customer
        FOREIGN KEY (CustomerSK) REFERENCES core.Customer (CustomerSK);

IF OBJECT_ID(N'core.FK_Order_Line_Sales_Order', N'F') IS NULL
    ALTER TABLE core.OrderLine ADD CONSTRAINT FK_Order_Line_Sales_Order
        FOREIGN KEY (SalesOrderSK) REFERENCES core.SalesOrder (SalesOrderSK);

IF OBJECT_ID(N'core.FK_Order_Line_Product', N'F') IS NULL
    ALTER TABLE core.OrderLine ADD CONSTRAINT FK_Order_Line_Product
        FOREIGN KEY (ProductSK) REFERENCES core.Product (ProductSK);

IF OBJECT_ID(N'core.FK_Shipment_Sales_Order', N'F') IS NULL
    ALTER TABLE core.Shipment ADD CONSTRAINT FK_Shipment_Sales_Order
        FOREIGN KEY (SalesOrderSK) REFERENCES core.SalesOrder (SalesOrderSK);

IF OBJECT_ID(N'core.FK_Shipment_Warehouse', N'F') IS NULL
    ALTER TABLE core.Shipment ADD CONSTRAINT FK_Shipment_Warehouse
        FOREIGN KEY (WarehouseSK) REFERENCES core.Warehouse (WarehouseSK);

IF OBJECT_ID(N'core.FK_Shipment_Carrier', N'F') IS NULL
    ALTER TABLE core.Shipment ADD CONSTRAINT FK_Shipment_Carrier
        FOREIGN KEY (CarrierSK) REFERENCES core.Carrier (CarrierSK);

IF OBJECT_ID(N'core.FK_Shipment_Line_Shipment', N'F') IS NULL
    ALTER TABLE core.ShipmentLine ADD CONSTRAINT FK_Shipment_Line_Shipment
        FOREIGN KEY (ShipmentSK) REFERENCES core.Shipment (ShipmentSK);

IF OBJECT_ID(N'core.FK_Shipment_Line_Order_Line', N'F') IS NULL
    ALTER TABLE core.ShipmentLine ADD CONSTRAINT FK_Shipment_Line_Order_Line
        FOREIGN KEY (OrderLineSK) REFERENCES core.OrderLine (OrderLineSK);

IF OBJECT_ID(N'core.FK_Tracking_Event_Shipment_Line', N'F') IS NULL
    ALTER TABLE core.TrackingEvent ADD CONSTRAINT FK_Tracking_Event_Shipment_Line
        FOREIGN KEY (ShipmentLineSK) REFERENCES core.ShipmentLine (ShipmentLineSK);

IF OBJECT_ID(N'core.FK_Tracking_Event_Event_Type', N'F') IS NULL
    ALTER TABLE core.TrackingEvent ADD CONSTRAINT FK_Tracking_Event_Event_Type
        FOREIGN KEY (EventTypeSK) REFERENCES core.EventType (EventTypeSK);

IF OBJECT_ID(N'core.FK_Tracking_Event_Location', N'F') IS NULL
    ALTER TABLE core.TrackingEvent ADD CONSTRAINT FK_Tracking_Event_Location
        FOREIGN KEY (LocationSK) REFERENCES core.Location (LocationSK);

IF OBJECT_ID(N'core.FK_Tracking_Event_Exception_Type', N'F') IS NULL
    ALTER TABLE core.TrackingEvent ADD CONSTRAINT FK_Tracking_Event_Exception_Type
        FOREIGN KEY (ExceptionTypeSK) REFERENCES core.ExceptionType (ExceptionTypeSK);
GO

/* ===========================================================================
   4. CHECK CONSTRAINTS (domain and same-row business rules)
   =========================================================================== */

-- City
IF OBJECT_ID(N'core.CK_City_Country', N'C') IS NULL
    ALTER TABLE core.City ADD CONSTRAINT CK_City_Country
        CHECK (CountryName IN (N'Netherlands', N'Belgium', N'Germany',
                               N'France', N'Luxembourg', N'Austria'));

-- Customer
IF OBJECT_ID(N'core.CK_Customer_ID_Format', N'C') IS NULL
    ALTER TABLE core.Customer ADD CONSTRAINT CK_Customer_ID_Format
        CHECK (CustomerID LIKE 'CU-[0-9][0-9][0-9][0-9][0-9][0-9]');
IF OBJECT_ID(N'core.CK_Customer_Type', N'C') IS NULL
    ALTER TABLE core.Customer ADD CONSTRAINT CK_Customer_Type
        CHECK (CustomerType IN ('Consumer', 'Trade', 'Interior Studio'));
IF OBJECT_ID(N'core.CK_Customer_Email_Format', N'C') IS NULL
    ALTER TABLE core.Customer ADD CONSTRAINT CK_Customer_Email_Format
        CHECK (CustomerEmail LIKE N'%_@_%._%' AND CustomerEmail NOT LIKE N'% %');

-- Product
IF OBJECT_ID(N'core.CK_Product_SKU_Format', N'C') IS NULL
    ALTER TABLE core.Product ADD CONSTRAINT CK_Product_SKU_Format
        CHECK (ProductSKU LIKE 'SL-[0-9][0-9][0-9][0-9]');
IF OBJECT_ID(N'core.CK_Product_Category', N'C') IS NULL
    ALTER TABLE core.Product ADD CONSTRAINT CK_Product_Category
        CHECK (ProductCategory IN (N'Home Storage', N'Kitchenware', N'Lighting',
                                   N'Textiles', N'Home Office', N'Small Furniture'));
IF OBJECT_ID(N'core.CK_Product_Weight_Positive', N'C') IS NULL
    ALTER TABLE core.Product ADD CONSTRAINT CK_Product_Weight_Positive
        CHECK (UnitWeightKg > 0);
IF OBJECT_ID(N'core.CK_Product_Price_Positive', N'C') IS NULL
    ALTER TABLE core.Product ADD CONSTRAINT CK_Product_Price_Positive
        CHECK (UnitPriceEUR > 0);

-- Location
IF OBJECT_ID(N'core.CK_Location_Type', N'C') IS NULL
    ALTER TABLE core.Location ADD CONSTRAINT CK_Location_Type
        CHECK (LocationType IN ('Warehouse', 'Hub'));

-- Warehouse
IF OBJECT_ID(N'core.CK_Warehouse_Code_Format', N'C') IS NULL
    ALTER TABLE core.Warehouse ADD CONSTRAINT CK_Warehouse_Code_Format
        CHECK (WarehouseCode LIKE 'WH-[A-Z][A-Z][A-Z]');

-- Carrier
IF OBJECT_ID(N'core.CK_Carrier_Code_Format', N'C') IS NULL
    ALTER TABLE core.Carrier ADD CONSTRAINT CK_Carrier_Code_Format
        CHECK (CarrierCode LIKE 'C[0-9][0-9]');
IF OBJECT_ID(N'core.CK_Carrier_Tracking_Prefix', N'C') IS NULL
    ALTER TABLE core.Carrier ADD CONSTRAINT CK_Carrier_Tracking_Prefix
        CHECK (TrackingPrefix LIKE '[A-Z][A-Z][A-Z][A-Z]');

-- Event_Type
IF OBJECT_ID(N'core.CK_Event_Type_Sequence', N'C') IS NULL
    ALTER TABLE core.EventType ADD CONSTRAINT CK_Event_Type_Sequence
        CHECK (StandardSequence >= 1);
IF OBJECT_ID(N'core.CK_Event_Type_Location_Type', N'C') IS NULL
    ALTER TABLE core.EventType ADD CONSTRAINT CK_Event_Type_Location_Type
        CHECK (ExpectedLocationType IN ('Warehouse', 'Hub'));

-- Sales_Order
IF OBJECT_ID(N'core.CK_Sales_Order_No_Format', N'C') IS NULL
    ALTER TABLE core.SalesOrder ADD CONSTRAINT CK_Sales_Order_No_Format
        CHECK (OrderNo LIKE 'ORD-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]');

-- Order_Line
IF OBJECT_ID(N'core.CK_Order_Line_No_Positive', N'C') IS NULL
    ALTER TABLE core.OrderLine ADD CONSTRAINT CK_Order_Line_No_Positive
        CHECK (OrderLineNo >= 1);
IF OBJECT_ID(N'core.CK_Order_Line_Quantity_Positive', N'C') IS NULL
    ALTER TABLE core.OrderLine ADD CONSTRAINT CK_Order_Line_Quantity_Positive
        CHECK (QuantityOrdered > 0);

-- Shipment
IF OBJECT_ID(N'core.CK_Shipment_No_Format', N'C') IS NULL
    ALTER TABLE core.Shipment ADD CONSTRAINT CK_Shipment_No_Format
        CHECK (ShipmentNo LIKE 'SHP-[0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9]%');
IF OBJECT_ID(N'core.CK_Shipment_Service_Level', N'C') IS NULL
    ALTER TABLE core.Shipment ADD CONSTRAINT CK_Shipment_Service_Level
        CHECK (ServiceLevel IN ('Standard', 'Economy', 'Priority'));
IF OBJECT_ID(N'core.CK_Shipment_Plan_After_Created', N'C') IS NULL
    ALTER TABLE core.Shipment ADD CONSTRAINT CK_Shipment_Plan_After_Created
        CHECK (PlannedDispatchDate >= CAST(ShipmentCreatedDateTime AS DATE));
IF OBJECT_ID(N'core.CK_Shipment_Dispatch_After_Created', N'C') IS NULL
    ALTER TABLE core.Shipment ADD CONSTRAINT CK_Shipment_Dispatch_After_Created
        CHECK (ActualDispatchDateTime IS NULL
               OR ActualDispatchDateTime >= ShipmentCreatedDateTime);
IF OBJECT_ID(N'core.CK_Shipment_Promise_After_Plan', N'C') IS NULL
    ALTER TABLE core.Shipment ADD CONSTRAINT CK_Shipment_Promise_After_Plan
        CHECK (PromisedDeliveryDate IS NULL
               OR PromisedDeliveryDate >= PlannedDispatchDate);
-- A shipment cannot have proof of delivery unless it was dispatched
IF OBJECT_ID(N'core.CK_Shipment_POD_Requires_Dispatch', N'C') IS NULL
    ALTER TABLE core.Shipment ADD CONSTRAINT CK_Shipment_POD_Requires_Dispatch
        CHECK (ProofOfDeliveryRef IS NULL OR ActualDispatchDateTime IS NOT NULL);

-- Shipment_Line
IF OBJECT_ID(N'core.CK_Shipment_Line_Quantity_Positive', N'C') IS NULL
    ALTER TABLE core.ShipmentLine ADD CONSTRAINT CK_Shipment_Line_Quantity_Positive
        CHECK (ShipmentLineQuantity > 0);
IF OBJECT_ID(N'core.CK_Shipment_Line_Freight_NonNegative', N'C') IS NULL
    ALTER TABLE core.ShipmentLine ADD CONSTRAINT CK_Shipment_Line_Freight_NonNegative
        CHECK (FreightCostEUR >= 0);

-- Tracking_Event
IF OBJECT_ID(N'core.CK_Tracking_Event_ID_Format', N'C') IS NULL
    ALTER TABLE core.TrackingEvent ADD CONSTRAINT CK_Tracking_Event_ID_Format
        CHECK (TrackingEventID LIKE 'EVT-[0-9]%');
IF OBJECT_ID(N'core.CK_Tracking_Event_Legacy_Row_Format', N'C') IS NULL
    ALTER TABLE core.TrackingEvent ADD CONSTRAINT CK_Tracking_Event_Legacy_Row_Format
        CHECK (LegacyRowID LIKE 'SCL-[0-9]%');
GO

/* ===========================================================================
   5. INDEXES
   Foreign-key columns are indexed where the join or filter is used by a
   known query. Deliberately NOT created:
     - Order_Line(SalesOrderSK): leading column of UQ_Order_Line_BK
     - Shipment_Line(ShipmentSK): leading column of UQ_Shipment_Line_BK
     - Tracking_Event(ShipmentLineSK): leading column of
       UQ_Tracking_Event_Line_Event
     - FK columns pointing at tiny lookups (City, Location, Warehouse:
       under 30 rows each), where a scan is always cheaper than a seek
   =========================================================================== */

-- Customer order history; supports the Sales_Order -> Customer join
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Sales_Order_Customer'
               AND object_id = OBJECT_ID(N'core.SalesOrder'))
    CREATE NONCLUSTERED INDEX IX_Sales_Order_Customer
        ON core.SalesOrder (CustomerSK)
        INCLUDE (OrderDateTime);

-- Product and category analysis; supports the Order_Line -> Product join
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Order_Line_Product'
               AND object_id = OBJECT_ID(N'core.OrderLine'))
    CREATE NONCLUSTERED INDEX IX_Order_Line_Product
        ON core.OrderLine (ProductSK)
        INCLUDE (QuantityOrdered);

-- Reconstruct an order's journey: order -> all of its (split) shipments
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Shipment_Sales_Order'
               AND object_id = OBJECT_ID(N'core.Shipment'))
    CREATE NONCLUSTERED INDEX IX_Shipment_Sales_Order
        ON core.Shipment (SalesOrderSK);

-- Carrier accountability: late deliveries by carrier and service level
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Shipment_Carrier'
               AND object_id = OBJECT_ID(N'core.Shipment'))
    CREATE NONCLUSTERED INDEX IX_Shipment_Carrier
        ON core.Shipment (CarrierSK)
        INCLUDE (ServiceLevel, PromisedDeliveryDate, WarehouseSK);

-- Warehouse accountability: planned vs actual dispatch by warehouse
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Shipment_Warehouse'
               AND object_id = OBJECT_ID(N'core.Shipment'))
    CREATE NONCLUSTERED INDEX IX_Shipment_Warehouse
        ON core.Shipment (WarehouseSK)
        INCLUDE (PlannedDispatchDate, ActualDispatchDateTime);

-- Order line -> the shipment line(s) that carried it
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Shipment_Line_Order_Line'
               AND object_id = OBJECT_ID(N'core.ShipmentLine'))
    CREATE NONCLUSTERED INDEX IX_Shipment_Line_Order_Line
        ON core.ShipmentLine (OrderLineSK);

-- Milestone queries: e.g. all DELIVERED events vs promise date, dispatch times
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Tracking_Event_Type_Time'
               AND object_id = OBJECT_ID(N'core.TrackingEvent'))
    CREATE NONCLUSTERED INDEX IX_Tracking_Event_Type_Time
        ON core.TrackingEvent (EventTypeSK, EventDateTime)
        INCLUDE (ShipmentLineSK, LocationSK);

-- Hub performance: events per hub, dwell time between HUB_IN and HUB_OUT
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Tracking_Event_Location'
               AND object_id = OBJECT_ID(N'core.TrackingEvent'))
    CREATE NONCLUSTERED INDEX IX_Tracking_Event_Location
        ON core.TrackingEvent (LocationSK)
        INCLUDE (EventTypeSK, EventDateTime, ShipmentLineSK);

-- Alert reconciliation (LATE, SCAN_GAP). Filtered: only about 5% of events
-- carry an exception, so the index stays small.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Tracking_Event_Exception'
               AND object_id = OBJECT_ID(N'core.TrackingEvent'))
    CREATE NONCLUSTERED INDEX IX_Tracking_Event_Exception
        ON core.TrackingEvent (ExceptionTypeSK)
        INCLUDE (ShipmentLineSK, EventTypeSK, EventDateTime)
        WHERE ExceptionTypeSK IS NOT NULL;
GO

/* ===========================================================================
   Evidence
   =========================================================================== */

-- A. Every table has a surrogate PK and a business-key UNIQUE (expect 13 rows,
--    all with Has_Surrogate_PK = 1 and Has_Business_Key = 1)
SELECT  t.name AS Table_Name,
        MAX(CASE WHEN kc.type = 'PK' AND c.is_identity = 1 THEN 1 ELSE 0 END) AS Has_Surrogate_PK,
        MAX(CASE WHEN kc.type = 'UQ' AND kc.name LIKE 'UQ[_]%[_]BK' THEN 1 ELSE 0 END) AS Has_Business_Key
FROM    sys.tables AS t
JOIN    sys.key_constraints AS kc ON kc.parent_object_id = t.object_id
JOIN    sys.index_columns   AS ic ON ic.object_id = t.object_id
                                 AND ic.index_id  = kc.unique_index_id
JOIN    sys.columns         AS c  ON c.object_id  = t.object_id
                                 AND c.column_id  = ic.column_id
WHERE   t.schema_id = SCHEMA_ID(N'core')
GROUP BY t.name
ORDER BY t.name;

-- B. Every constraint, its type, and whether SQL Server trusts it
--    (Is_Not_Trusted = 0 means all existing rows were checked against it)
SELECT  OBJECT_NAME(o.parent_object_id) AS Table_Name,
        o.name                          AS Constraint_Name,
        o.type_desc                     AS Constraint_Type,
        COALESCE(CAST(fk.is_not_trusted AS VARCHAR(5)),
                 CAST(ck.is_not_trusted AS VARCHAR(5)), 'n/a') AS Is_Not_Trusted
FROM    sys.objects AS o
LEFT JOIN sys.foreign_keys      AS fk ON fk.object_id = o.object_id
LEFT JOIN sys.check_constraints AS ck ON ck.object_id = o.object_id
WHERE   o.schema_id = SCHEMA_ID(N'core')
AND     o.type IN ('PK', 'UQ', 'F', 'C')
ORDER BY Table_Name, o.type, Constraint_Name;

-- C. Supporting indexes (excluding PK and UNIQUE constraint indexes)
SELECT  OBJECT_NAME(i.object_id) AS Table_Name,
        i.name                   AS Index_Name,
        i.type_desc              AS Index_Type,
        i.is_unique,
        i.has_filter,
        i.filter_definition
FROM    sys.indexes AS i
WHERE   OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
AND     OBJECT_SCHEMA_NAME(i.object_id) = N'core'
AND     i.is_primary_key = 0
AND     i.is_unique_constraint = 0
AND     i.name IS NOT NULL
ORDER BY Table_Name, Index_Name;
GO
