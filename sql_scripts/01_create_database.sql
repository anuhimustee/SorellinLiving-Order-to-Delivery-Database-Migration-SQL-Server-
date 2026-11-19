/* ============================================================
   SORELLIN LIVING B.V DATABASE - DDL IMLEMENTATION
   Operation RouteGlass
   ============================================================
   Purpose  : Replace Excel-based system with enterprise SQL database and its schemas.
   Platform : Microsoft SQL Server 2019
              2019+ is needed because staging uses a UTF-8 collation (script 02).
   Author	: Mustapha (Sir Mustee)
   
   Database Structure:
   - 6 Core Tables (Customers, Product, ProductCategory,Warehouse, 
                        Carrier, Exception)
   - Full referential integrity with foreign keys
   - Business rule enforcement via constraints
   - Optimized indexes for common queries
   - Audit trail with timestamps
   - Soft delete capability with IsActive flags
   
   Design Principles:
   - Third Normal Form (3NF)
   - No redundant data
   - Enforced data integrity
   - Scalable architecture
   - Real-world business logic
   ============================================================ */

-- ============================================================
--                  SECTION 1: DATABASE CREATION
-- ============================================================

-- Drop Database if exists (for clean rebuild during development)

IF EXISTS (SELECT name FROM sys.databases WHERE name = 'SorellinLivingDB')
BEGIN
	USE Master;
	ALTER DATABASE SorellinLivingDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
	DROP DATABASE SorellinLivingDB;
    PRINT 'Existing Database SorellinLivingDB Dropped.';
END
GO

-- Creating the Database called SorellinLivingDB

CREATE DATABASE SorellinLivingDB;
PRINT 'Database SorellinLivingDB Created.';
GO

-- Uses the Database
USE SorellinLivingDB;
GO

-- ============================================================
--                  SECTION 1.1: SCHEMA CREATION
-- ============================================================
-- Creating Four Schemas in the Database SorellinLivingDB
-- ============================================================

-- Staging Schema to house our Staging Tables
IF SCHEMA_ID(N'stg') IS NULL EXEC(N'CREATE SCHEMA stg');

-- Core Schema to hold our 3NF Tables
IF SCHEMA_ID(N'core') IS NULL EXEC(N'CREATE SCHEMA core');

-- Map Schema to hold the mapping tables that standardise aliases
IF SCHEMA_ID(N'map') IS NULL EXEC(N'CREATE SCHEMA map');

-- Audit Schema to hold the exception log
IF SCHEMA_ID(N'audit') IS NULL EXEC(N'CREATE SCHEMA audit');
GO

PRINT('Four (4) Schemas Created Successfully')
