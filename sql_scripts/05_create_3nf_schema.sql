/* =============================================================================
   Operation RouteGlass | Script 05:    Create 3NF Schema
   Author	: Mustapha (Sir Mustee)
   -----------------------------------------------------------------------------
   Purpose  : Create the 13 normalised (3NF) target tables in schema core.
   Depends  : 01_create_database.sql
   Rerun    : Safe. All core tables are dropped child-first and recreated.
              This deletes migrated data, so rerun 06 and 07 afterwards.

   Key design (the rule applied to every table)
     1. Each table has its own surrogate key, written as <Table>SK, an IDENTITY number
        that means nothing outside this database. It becomes the PRIMARY KEY
        in 07 and is the only column other tables point to.
     2. The original business key from the source file (CustomerID,
        OrderNo, ShipmentNo, ProductSKU, TrackingEventID, ...) is kept
        as an ordinary NOT NULL column and becomes a UNIQUE constraint in 07.
        It is the candidate (alternate) key that people search by.
     3. Foreign keys always reference the parent's surrogate key.

   Why the UNIQUE business key is compulsory, not optional
     An IDENTITY column never repeats, so it cannot detect a duplicate. If the
     same OrderNo were inserted twice it would simply receive two different
     SalesOrderSK values. The UNIQUE constraint on the business key is what
     stops that. It is also what keeps the table in 3NF: with OrderNo unique,
     both SalesOrderSK and OrderNo are candidate keys, and every other
     column depends on a key. Without it, OrderNo would be a non-key column
     and SalesOrderSK -> OrderNo -> OrderDateTime would be a transitive
     dependency.

   Why surrogate keys here (the brief asks for "a clear purpose")
     - Stability: business keys come from the legacy system and can change
       (e.g. a carrier re-coded after a merger, a customer number reissued).
       Changing a business key updates one row; no child rows are touched.
     - Integration: a second source system may reuse the same OrderNo or
       CustomerID values. Surrogates keep the two apart.
     - Narrow, consistent joins: every join is on a small integer, and every
       foreign key follows the same <Parent>SK naming pattern.
     - Clustering: an ever-increasing IDENTITY makes a narrow clustered key,
       so new rows are appended at the end of the table.
     Trade-off: 06 must look up each parent's surrogate by joining on its
     business key, and queries need one extra join to show business codes.

   What is defined HERE vs in 07
     Here (05) : columns, data types, NULL / NOT NULL, IDENTITY, DEFAULT.
     07        : PRIMARY KEY, UNIQUE, FOREIGN KEY, CHECK and indexes, added
                 after 06 has loaded the data, as the brief requires.

   Surrogate key sizes (smallest type that leaves ample room for growth)
     TINYINT  (max 255)    Event_Type, Exception_Type: closed code lists
     SMALLINT (max 32,767) City, Location, Warehouse, Carrier: small masters
     INT      (max 2.1 bn) Customer, Product and all transaction tables
   A foreign key must have the same data type as the key it references.
   ============================================================================= */

USE SorellinLivingDB;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;   -- needed for the filtered unique index in 07
GO

/* ---------------------------------------------------------------------------
   Drop child tables first, then parents
   --------------------------------------------------------------------------- */
DROP TABLE IF EXISTS core.TrackingEvent;
DROP TABLE IF EXISTS core.ShipmentLine;
DROP TABLE IF EXISTS core.Shipment;
DROP TABLE IF EXISTS core.OrderLine;
DROP TABLE IF EXISTS core.SalesOrder;
DROP TABLE IF EXISTS core.Customer;
DROP TABLE IF EXISTS core.Warehouse;
DROP TABLE IF EXISTS core.Location;
DROP TABLE IF EXISTS core.City;
DROP TABLE IF EXISTS core.Product;
DROP TABLE IF EXISTS core.Carrier;
DROP TABLE IF EXISTS core.EventType;
DROP TABLE IF EXISTS core.ExceptionType;
GO

/* ===========================================================================
   REFERENCE TABLES
   =========================================================================== */

/* City: removes the transitive dependency  X -> City -> Country.
   Business key: (CityName, CountryName). The source has no city code. */
CREATE TABLE core.City
(
    CitySK       SMALLINT IDENTITY(1, 1) NOT NULL,   -- surrogate PK
    CityName     NVARCHAR(60)            NOT NULL,   -- business key (part 1)
    CountryName  NVARCHAR(40)            NOT NULL,   -- business key (part 2)

    -- Status and Metadata
    IsActive BIT NOT NULL DEFAULT 1,
    RegistrationDate DATETIME NOT NULL DEFAULT GETDATE(),

    -- Audit Fields
    CreatedAt DATETIME NOT NULL DEFAULT GETDATE(),
    UpdatedAt DATETIME NOT NULL DEFAULT GETDATE()
);
GO

/* Customer: CustomerID -> name, email, type, address.
   Address fields are "Conditional" in the data dictionary, so they allow NULL. */
CREATE TABLE core.Customer
(
    CustomerSK           INT IDENTITY(1, 1) NOT NULL,   -- surrogate PK
    CustomerID           VARCHAR(12)        NOT NULL,   -- business key, e.g. CU-000240
    CustomerName         NVARCHAR(100)      NOT NULL,
    CustomerEmail        NVARCHAR(254)      NOT NULL,   -- second candidate key
    CustomerType         VARCHAR(20)        NOT NULL,
    DeliveryAddressLine  NVARCHAR(150)      NULL,
    DeliveryPostalCode   VARCHAR(12)        NULL,
    CitySK               SMALLINT           NULL,       -- FK -> City

    -- Status and Metadata
    IsActive BIT NOT NULL DEFAULT 1,
    RegistrationDate DATETIME NOT NULL DEFAULT GETDATE(),

    -- Audit Fields
    CreatedAt DATETIME NOT NULL DEFAULT GETDATE(),
    UpdatedAt DATETIME NOT NULL DEFAULT GETDATE()
);
GO

/* Product: ProductSKU -> name, category, weight, price. */
CREATE TABLE core.Product
(
    ProductSK        INT IDENTITY(1, 1) NOT NULL,   -- surrogate PK
    ProductSKU       VARCHAR(12)        NOT NULL,   -- business key, e.g. SL-1056
    ProductName      NVARCHAR(100)      NOT NULL,
    ProductCategory  NVARCHAR(40)       NOT NULL,
    UnitWeightKg     DECIMAL(8, 3)      NOT NULL,
    UnitPriceEUR     DECIMAL(10, 2)     NOT NULL,

    -- Status and Metadata
    IsActive BIT NOT NULL DEFAULT 1,
    RegistrationDate DATETIME NOT NULL DEFAULT GETDATE(),

    -- Audit Fields
    CreatedAt DATETIME NOT NULL DEFAULT GETDATE(),
    UpdatedAt DATETIME NOT NULL DEFAULT GETDATE()
);
GO

/* Location: every physical scan point (4 warehouses + 5 carrier hubs).
   Supertype of Warehouse. Country comes from City, never from the source
   Event_Country column, which is unreliable for hubs.
   Business key: LocationName. The source has no location code. */
CREATE TABLE core.Location
(
    LocationSK    SMALLINT IDENTITY(1, 1) NOT NULL,   -- surrogate PK
    LocationName  NVARCHAR(100)           NOT NULL,   -- business key
    LocationType  VARCHAR(10)             NOT NULL,   -- Warehouse | Hub
    CitySK        SMALLINT                NOT NULL,   -- FK -> City

    -- Status and Metadata
    IsActive BIT NOT NULL DEFAULT 1,
    RegistrationDate DATETIME NOT NULL DEFAULT GETDATE(),

    -- Audit Fields
    CreatedAt DATETIME NOT NULL DEFAULT GETDATE(),
    UpdatedAt DATETIME NOT NULL DEFAULT GETDATE()
);
GO

/* Warehouse: subtype of Location (1:1). Name and city are stored once, on
   Location; Warehouse holds only the business code used by shipments. */
CREATE TABLE core.Warehouse
(
    WarehouseSK    SMALLINT IDENTITY(1, 1) NOT NULL,   -- surrogate PK
    WarehouseCode  VARCHAR(10)             NOT NULL,   -- business key, e.g. WH-LIL
    LocationSK     SMALLINT                NOT NULL,   -- FK -> Location (unique: 1:1)

    -- Status and Metadata
    IsActive BIT NOT NULL DEFAULT 1,
    RegistrationDate DATETIME NOT NULL DEFAULT GETDATE(),

    -- Audit Fields
    CreatedAt DATETIME NOT NULL DEFAULT GETDATE(),
    UpdatedAt DATETIME NOT NULL DEFAULT GETDATE()
);
GO

/* Carrier: CarrierCode -> standardised name, tracking-number prefix. */
CREATE TABLE core.Carrier
(
    CarrierSK       SMALLINT IDENTITY(1, 1) NOT NULL,   -- surrogate PK
    CarrierCode     VARCHAR(5)              NOT NULL,   -- business key, C01 .. C06
    CarrierName     NVARCHAR(100)           NOT NULL,
    TrackingPrefix  VARCHAR(4)              NOT NULL,

    -- Status and Metadata
    IsActive BIT NOT NULL DEFAULT 1,
    RegistrationDate DATETIME NOT NULL DEFAULT GETDATE(),

    -- Audit Fields
    CreatedAt DATETIME NOT NULL DEFAULT GETDATE(),
    UpdatedAt DATETIME NOT NULL DEFAULT GETDATE()
);
GO

/* Event_Type: EventCode -> description, standard sequence, location type.
   Removes Event_Sequence_Legacy and Tracking_Event_Description from the
   event rows (they depend on the code, not on the event). */
CREATE TABLE core.EventType
(
    EventTypeSK           TINYINT IDENTITY(1, 1) NOT NULL,   -- surrogate PK
    EventCode             VARCHAR(20)            NOT NULL,   -- business key, PICKED .. DELIVERED
    EventDescription      NVARCHAR(100)          NOT NULL,
    StandardSequence      TINYINT                NOT NULL,   -- 1 .. 6
    ExpectedLocationType  VARCHAR(10)            NOT NULL,   -- Warehouse | Hub

    -- Status and Metadata
    IsActive BIT NOT NULL DEFAULT 1,
    RegistrationDate DATETIME NOT NULL DEFAULT GETDATE(),

    -- Audit Fields
    CreatedAt DATETIME NOT NULL DEFAULT GETDATE(),
    UpdatedAt DATETIME NOT NULL DEFAULT GETDATE()
);
GO

/* Exception_Type: ExceptionCode -> description (LATE, SCAN_GAP). */
CREATE TABLE core.ExceptionType
(
    ExceptionTypeSK       TINYINT IDENTITY(1, 1) NOT NULL,   -- surrogate PK
    ExceptionCode         VARCHAR(20)            NOT NULL,   -- business key
    ExceptionDescription  NVARCHAR(200)          NOT NULL,

    -- Status and Metadata
    IsActive BIT NOT NULL DEFAULT 1,
    RegistrationDate DATETIME NOT NULL DEFAULT GETDATE(),

    -- Audit Fields
    CreatedAt DATETIME NOT NULL DEFAULT GETDATE(),
    UpdatedAt DATETIME NOT NULL DEFAULT GETDATE()
);
GO

/* ===========================================================================
   TRANSACTION TABLES
   MigratedAt records when each row was written by 06 (lineage).
   =========================================================================== */

/* Sales_Order: OrderNo -> customer, order time.
   Not stored: Order_Status (derived from tracking events) and Sales_Channel
   (varies inside the same order in the source, so no reliable value exists;
   it is logged as an exception and kept in staging for audit). */
CREATE TABLE core.SalesOrder
(
    SalesOrderSK   INT IDENTITY(1, 1) NOT NULL,   -- surrogate PK
    OrderNo        VARCHAR(15)        NOT NULL,   -- business key, e.g. ORD-00000943
    CustomerSK     INT                NOT NULL,   -- FK -> Customer
    OrderDateTime  DATETIME2(0)       NOT NULL,
    MigratedAt     DATETIME2(0)       NOT NULL
        CONSTRAINT DF_Sales_Order_MigratedAt DEFAULT (SYSDATETIME()),

    -- Status and Metadata
    IsActive BIT NOT NULL DEFAULT 1,
    RegistrationDate DATETIME NOT NULL DEFAULT GETDATE(),

    -- Audit Fields
    CreatedAt DATETIME NOT NULL DEFAULT GETDATE(),
    UpdatedAt DATETIME NOT NULL DEFAULT GETDATE()
);
GO

/* Order_Line: one product line within an order.
   Business key: (OrderNo, OrderLineNo), stored here as
   (SalesOrderSK, OrderLineNo) because OrderNo lives on Sales_Order. */
CREATE TABLE core.OrderLine
(
    OrderLineSK      INT IDENTITY(1, 1) NOT NULL,   -- surrogate PK
    SalesOrderSK     INT                NOT NULL,   -- FK -> Sales_Order, business key part 1
    OrderLineNo      TINYINT            NOT NULL,   -- business key part 2 (1, 2, 3)
    ProductSK        INT                NOT NULL,   -- FK -> Product
    QuantityOrdered  SMALLINT           NOT NULL,
    MigratedAt       DATETIME2(0)       NOT NULL
        CONSTRAINT DF_Order_Line_MigratedAt DEFAULT (SYSDATETIME()),

    -- Status and Metadata
    IsActive BIT NOT NULL DEFAULT 1,
    RegistrationDate DATETIME NOT NULL DEFAULT GETDATE(),

    -- Audit Fields
    CreatedAt DATETIME NOT NULL DEFAULT GETDATE(),
    UpdatedAt DATETIME NOT NULL DEFAULT GETDATE()
);
GO

/* Shipment: ShipmentNo -> order, warehouse, carrier, service level,
   tracking number, dates and proof of delivery.
   An order can have several shipments (split shipments).
   Conditional fields allow NULL and are never filled with invented values. */
CREATE TABLE core.Shipment
(
    ShipmentSK               INT IDENTITY(1, 1) NOT NULL,   -- surrogate PK
    ShipmentNo               VARCHAR(20)        NOT NULL,   -- business key, e.g. SHP-0000002-1
    SalesOrderSK             INT                NOT NULL,   -- FK -> Sales_Order
    WarehouseSK              SMALLINT           NOT NULL,   -- FK -> Warehouse
    CarrierSK                SMALLINT           NOT NULL,   -- FK -> Carrier
    ServiceLevel             VARCHAR(10)        NOT NULL,   -- Standard | Economy | Priority
    TrackingNo               VARCHAR(30)        NOT NULL,   -- second candidate key
    ShipmentCreatedDateTime  DATETIME2(0)       NOT NULL,
    PlannedDispatchDate      DATE               NOT NULL,
    ActualDispatchDateTime   DATETIME2(0)       NULL,       -- NULL until dispatched
    PromisedDeliveryDate     DATE               NULL,       -- "Conditional" in dictionary
    ProofOfDeliveryRef       VARCHAR(20)        NULL,       -- NULL until delivered
    MigratedAt               DATETIME2(0)       NOT NULL
        CONSTRAINT DF_Shipment_MigratedAt DEFAULT (SYSDATETIME()),

    -- Status and Metadata
    IsActive BIT NOT NULL DEFAULT 1,
    RegistrationDate DATETIME NOT NULL DEFAULT GETDATE(),

    -- Audit Fields
    CreatedAt DATETIME NOT NULL DEFAULT GETDATE(),
    UpdatedAt DATETIME NOT NULL DEFAULT GETDATE()
);
GO

/* Shipment_Line: ASSOCIATIVE (bridge) entity between Shipment and Order_Line.
   Business key: (ShipmentSK, OrderLineSK).
   Freight lives here because it is unique only at this grain; summing it per
   raw source row overstates freight about six times.
   Rule tested in 08, not stored: the order line must belong to the same
   order as the shipment. Storing SalesOrderSK here to enforce it with a
   key would break 2NF (it depends on ShipmentSK alone). */
CREATE TABLE core.ShipmentLine
(
    ShipmentLineSK        INT IDENTITY(1, 1) NOT NULL,   -- surrogate PK
    ShipmentSK            INT                NOT NULL,   -- FK -> Shipment, business key part 1
    OrderLineSK           INT                NOT NULL,   -- FK -> Order_Line, business key part 2
    ShipmentLineQuantity  SMALLINT           NOT NULL,
    FreightCostEUR        DECIMAL(10, 2)     NOT NULL,
    MigratedAt            DATETIME2(0)       NOT NULL
        CONSTRAINT DF_Shipment_Line_MigratedAt DEFAULT (SYSDATETIME()),

    -- Status and Metadata
    IsActive BIT NOT NULL DEFAULT 1,
    RegistrationDate DATETIME NOT NULL DEFAULT GETDATE(),

    -- Audit Fields
    CreatedAt DATETIME NOT NULL DEFAULT GETDATE(),
    UpdatedAt DATETIME NOT NULL DEFAULT GETDATE()
);
GO

/* Tracking_Event: one scan of one shipment line.
   Events attach to the shipment LINE, not the shipment: lines in the same
   parcel were scanned at different times and hubs in the source.
   Three candidate keys besides the surrogate:
     TrackingEventID                 the source event identifier
     (ShipmentLineSK, EventTypeSK) one event per milestone per line
     LegacyRowID                     traceability to the source row */
CREATE TABLE core.TrackingEvent
(
    TrackingEventSK  INT IDENTITY(1, 1) NOT NULL,   -- surrogate PK
    TrackingEventID  VARCHAR(20)        NOT NULL,   -- business key, e.g. EVT-000005086
    ShipmentLineSK   INT                NOT NULL,   -- FK -> Shipment_Line
    EventTypeSK      TINYINT            NOT NULL,   -- FK -> Event_Type
    EventDateTime    DATETIME2(0)       NOT NULL,
    LocationSK       SMALLINT           NOT NULL,   -- FK -> Location
    ExceptionTypeSK  TINYINT            NULL,       -- FK -> Exception_Type; NULL = no exception
    LegacyRowID      VARCHAR(20)        NOT NULL,   -- source row, e.g. SCL-00005086
    MigratedAt       DATETIME2(0)       NOT NULL
        CONSTRAINT DF_Tracking_Event_MigratedAt DEFAULT (SYSDATETIME()),

    -- Status and Metadata
    IsActive BIT NOT NULL DEFAULT 1,
    RegistrationDate DATETIME NOT NULL DEFAULT GETDATE(),

    -- Audit Fields
    CreatedAt DATETIME NOT NULL DEFAULT GETDATE(),
    UpdatedAt DATETIME NOT NULL DEFAULT GETDATE()
);
GO

/* Evidence: tables, columns and nullability created in core */
SELECT  t.name                                       AS Table_Name,
        c.column_id                                  AS Column_Order,
        c.name                                       AS Column_Name,
        TYPE_NAME(c.user_type_id)
          + CASE
                WHEN TYPE_NAME(c.user_type_id) IN ('varchar', 'char')
                    THEN '(' + CAST(c.max_length AS VARCHAR(10)) + ')'
                WHEN TYPE_NAME(c.user_type_id) IN ('nvarchar', 'nchar')
                    THEN '(' + CAST(c.max_length / 2 AS VARCHAR(10)) + ')'
                WHEN TYPE_NAME(c.user_type_id) = 'decimal'
                    THEN '(' + CAST(c.precision AS VARCHAR(5)) + ',' + CAST(c.scale AS VARCHAR(5)) + ')'
                WHEN TYPE_NAME(c.user_type_id) = 'datetime2'
                    THEN '(' + CAST(c.scale AS VARCHAR(5)) + ')'
                ELSE ''
            END                                      AS Data_Type,
        CASE WHEN c.is_nullable = 1 THEN 'NULL' ELSE 'NOT NULL' END AS Nullability,
        CASE WHEN c.is_identity = 1 THEN 'IDENTITY (surrogate)' ELSE '' END AS Key_Role
FROM    sys.tables  AS t
JOIN    sys.columns AS c ON c.object_id = t.object_id
WHERE   t.schema_id = SCHEMA_ID(N'core')
ORDER BY t.name, c.column_id;

-- Expected: 13 tables, and 13 identity columns (one surrogate per table)
SELECT  COUNT(DISTINCT t.object_id)                            AS Core_Table_Count,
        SUM(CASE WHEN c.is_identity = 1 THEN 1 ELSE 0 END)     AS Surrogate_Key_Count
FROM    sys.tables  AS t
JOIN    sys.columns AS c ON c.object_id = t.object_id
WHERE   t.schema_id = SCHEMA_ID(N'core');
GO
