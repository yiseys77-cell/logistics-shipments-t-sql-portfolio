-- ============================================================================
-- Project: Enterprise Logistics & Warehouse Management System
-- Script 1: Database Architecture & DDL (Schema Setup)
-- Author: Data & Logistics Analytics Portfolio
-- ============================================================================

-- 1. Create and Use Database
CREATE DATABASE LogisticsDB;
GO

USE LogisticsDB;
GO

-- ============================================================================
-- 2. Create Staging Table (For Raw CSV Bulk Import)
-- ============================================================================
-- All columns are defined as VARCHAR to prevent bulk insert failures caused by 
-- formatting quirks, blank values, or messy strings in the raw CSV file.
-- ============================================================================
IF OBJECT_ID('dbo.stg_Shipments', 'U') IS NOT NULL
    DROP TABLE dbo.stg_Shipments;
GO

CREATE TABLE dbo.stg_Shipments (
    Shipment_ID        VARCHAR(50),
    Origin_Warehouse   VARCHAR(50),
    Destination        VARCHAR(100),
    Carrier            VARCHAR(50),
    Shipment_Date      VARCHAR(50),
    Delivery_Date      VARCHAR(50),
    Weight_kg          VARCHAR(50),
    Cost               VARCHAR(50),
    Status             VARCHAR(50),
    Distance_miles     VARCHAR(50),
    Transit_Days       VARCHAR(50)
);
GO

-- ============================================================================
-- 3. Create Normalized Dimension Tables
-- ============================================================================

-- Dimension: Warehouses
IF OBJECT_ID('dbo.Dim_Warehouse', 'U') IS NOT NULL
    DROP TABLE dbo.Dim_Warehouse;
GO

CREATE TABLE dbo.Dim_Warehouse (
    Warehouse_Code     VARCHAR(50) PRIMARY KEY,
    Region             VARCHAR(50) NULL,
    Created_At         DATETIME2 DEFAULT GETDATE()
);
GO

-- Dimension: Carriers
IF OBJECT_ID('dbo.Dim_Carrier', 'U') IS NOT NULL
    DROP TABLE dbo.Dim_Carrier;
GO

CREATE TABLE dbo.Dim_Carrier (
    Carrier_Name       VARCHAR(50) PRIMARY KEY,
    Service_Level      VARCHAR(50) DEFAULT 'Standard',
    Created_At         DATETIME2 DEFAULT GETDATE()
);
GO

-- ============================================================================
-- 4. Create Core Fact Table (Fact_Shipments)
-- ============================================================================
IF OBJECT_ID('dbo.Fact_Shipments', 'U') IS NOT NULL
    DROP TABLE dbo.Fact_Shipments;
GO

CREATE TABLE dbo.Fact_Shipments (
    Shipment_ID        VARCHAR(50) NOT NULL,
    Origin_Warehouse   VARCHAR(50) NOT NULL,
    Destination        VARCHAR(100) NOT NULL,
    Carrier            VARCHAR(50) NOT NULL,
    Shipment_Date      DATE NOT NULL,
    Delivery_Date      DATE NULL,          -- Nullable because active/lost shipments may lack delivery dates
    Weight_kg          FLOAT NOT NULL,
    Cost               FLOAT NULL,         -- Nullable for pending/unbilled shipments
    Status             VARCHAR(50) NOT NULL,
    Distance_miles     INT NOT NULL,
    Transit_Days       INT NOT NULL,
    Loaded_At          DATETIME2 DEFAULT GETDATE(),

    -- Primary Key Constraint
    CONSTRAINT PK_Fact_Shipments PRIMARY KEY CLUSTERED (Shipment_ID),

    -- Foreign Key Constraints
    CONSTRAINT FK_Shipments_Warehouse FOREIGN KEY (Origin_Warehouse) 
        REFERENCES dbo.Dim_Warehouse(Warehouse_Code),
        
    CONSTRAINT FK_Shipments_Carrier FOREIGN KEY (Carrier) 
        REFERENCES dbo.Dim_Carrier(Carrier_Name),

    -- Data Integrity CHECK Constraints
    CONSTRAINT CK_Weight_Positive CHECK (Weight_kg > 0),
    CONSTRAINT CK_Cost_NonNegative CHECK (Cost >= 0 OR Cost IS NULL),
    CONSTRAINT CK_Distance_Positive CHECK (Distance_miles > 0),
    CONSTRAINT CK_TransitDays_Positive CHECK (Transit_Days > 0),
    CONSTRAINT CK_Valid_Status CHECK (Status IN ('Delivered', 'Delayed', 'Lost', 'In Transit', 'Returned'))
);
GO

-- ============================================================================
-- 5. Create Performance Indexes
-- ============================================================================
-- Non-clustered indexes on frequently filtered or joined columns to optimize analytics
-- ============================================================================
CREATE NONCLUSTERED INDEX IX_Fact_Shipments_Date 
ON dbo.Fact_Shipments(Shipment_Date);
GO

CREATE NONCLUSTERED INDEX IX_Fact_Shipments_Status 
ON dbo.Fact_Shipments(Status);
GO

CREATE NONCLUSTERED INDEX IX_Fact_Shipments_Destination 
ON dbo.Fact_Shipments(Destination);
GO