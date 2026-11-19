/* ===================================================================
   Operation RouteGlass | Script 02: Creating the Raw Staging Table
   Author	: Mustapha (Sir Mustee)
   ===================================================================
   Rule: 
     - Staging holds the CSV exactly as delivered.
     - Every column is text (NVARCHAR), so no row is rejected for a bad type.
       Type conversion happens later in 04/06 with TRY_CONVERT.
     - NVARCHAR keeps accented names (e.g. Düsseldorf) intact.
     - 50 columns, in the same order as the CSV header, because BULK INSERT
       matches file fields to table columns by position.
   Rerun: safe (the table is dropped and recreated).
   ============================================================================= */

USE SorellinLivingDB;
GO

DROP TABLE IF EXISTS stg.Legacy_Extract_Raw;
GO

CREATE TABLE stg.Legacy_Extract_Raw
(
    Legacy_Row_ID               NVARCHAR(255) NULL,
    Order_No                    NVARCHAR(255) NULL,
    Order_DateTime              NVARCHAR(255) NULL,
    Customer_ID                 NVARCHAR(255) NULL,
    Customer_Name               NVARCHAR(255) NULL,
    Customer_Email              NVARCHAR(255) NULL,
    Customer_Type               NVARCHAR(255) NULL,
    Delivery_Address_Line       NVARCHAR(255) NULL,
    Delivery_City               NVARCHAR(255) NULL,
    Delivery_Postal_Code        NVARCHAR(255) NULL,
    Delivery_Country            NVARCHAR(255) NULL,
    Sales_Channel               NVARCHAR(255) NULL,
    Order_Status                NVARCHAR(255) NULL,
    Order_Line_No               NVARCHAR(255) NULL,
    Product_SKU                 NVARCHAR(255) NULL,
    Product_Name                NVARCHAR(255) NULL,
    Product_Category            NVARCHAR(255) NULL,
    Unit_Weight_kg              NVARCHAR(255) NULL,
    Unit_Price_EUR              NVARCHAR(255) NULL,
    Quantity_Ordered            NVARCHAR(255) NULL,
    Warehouse_Code              NVARCHAR(255) NULL,
    Warehouse_Name              NVARCHAR(255) NULL,
    Warehouse_City              NVARCHAR(255) NULL,
    Warehouse_Country           NVARCHAR(255) NULL,
    Shipment_No                 NVARCHAR(255) NULL,
    Shipment_Created_DateTime   NVARCHAR(255) NULL,
    Shipment_Line_Quantity      NVARCHAR(255) NULL,
    Carrier_Code                NVARCHAR(255) NULL,
    Carrier_Name                NVARCHAR(255) NULL,
    Carrier_Service_Level       NVARCHAR(255) NULL,
    Tracking_No                 NVARCHAR(255) NULL,
    Planned_Dispatch_Date       NVARCHAR(255) NULL,
    Actual_Dispatch_DateTime    NVARCHAR(255) NULL,
    Promised_Delivery_Date      NVARCHAR(255) NULL,
    Tracking_Event_ID           NVARCHAR(255) NULL,
    Event_Sequence_Legacy       NVARCHAR(255) NULL,
    Tracking_Event_Code         NVARCHAR(255) NULL,
    Tracking_Event_Description  NVARCHAR(255) NULL,
    Tracking_Event_DateTime     NVARCHAR(255) NULL,
    Event_Location              NVARCHAR(255) NULL,
    Event_City                  NVARCHAR(255) NULL,
    Event_Country               NVARCHAR(255) NULL,
    Delivery_DateTime           NVARCHAR(255) NULL,
    Exception_Code              NVARCHAR(255) NULL,
    Exception_Description       NVARCHAR(255) NULL,
    Proof_of_Delivery_Ref       NVARCHAR(255) NULL,
    Freight_Cost_EUR            NVARCHAR(255) NULL,
    Currency                    NVARCHAR(255) NULL,
    On_Time_Flag_Legacy         NVARCHAR(255) NULL,
    Delivery_Days_Legacy        NVARCHAR(255) NULL
);
GO

/*
What this does:
- Creates a table with all 50 source columns in their original order.
- Uses NVARCHAR(255) to preserve raw values before type conversion and cleansing.
- Allows NULL values because the source contains blanks and conditional fields.
*/

PRINT(N'Staging Table Created Successfully')

-- ------------------------------------------------------------
-- STEP 1: Check staging before load
-- ------------------------------------------------------------

SELECT COUNT(*) AS RowsBeforeBulkLoad
FROM stg.Legacy_Extract_Raw;
GO

-------------------------------
-- Check: should return 50
-------------------------------
SELECT COUNT(*) AS Staging_Column_Count
FROM   sys.columns
WHERE  object_id = OBJECT_ID(N'stg.Legacy_Extract_Raw');
GO
