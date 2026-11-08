-- ============================================================================
-- Project: Enterprise Logistics & Warehouse Management System
-- Script 3: Programmability, Stored Procedures, Triggers & Functions
-- Author: Data & Logistics Analytics Portfolio
-- ============================================================================

USE LogisticsDB;
GO

-- ============================================================================
-- 1. Create Audit Table for Tracking Shipment Status Modifications
-- ============================================================================
IF OBJECT_ID('dbo.Shipment_Audit_Log', 'U') IS NOT NULL
    DROP TABLE dbo.Shipment_Audit_Log;
GO

CREATE TABLE dbo.Shipment_Audit_Log (
    Audit_ID           INT IDENTITY(1,1) PRIMARY KEY,
    Shipment_ID        VARCHAR(50) NOT NULL,
    Old_Status         VARCHAR(50) NULL,
    New_Status         VARCHAR(50) NOT NULL,
    Modified_By        SYSNAME DEFAULT SYSTEM_USER,
    Modified_Date      DATETIME2 DEFAULT GETDATE()
);
GO


-- ============================================================================
-- 2. Create Audit Trigger (`AFTER UPDATE`)
-- ============================================================================
-- Automatically logs any changes to a shipment's operational status into the audit table.
-- ============================================================================
IF OBJECT_ID('dbo.trg_Shipment_Status_Audit', 'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_Shipment_Status_Audit;
GO

CREATE TRIGGER dbo.trg_Shipment_Status_Audit
ON dbo.Fact_Shipments
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Only log if the Status column was actually modified
    IF UPDATE(Status)
    BEGIN
        INSERT INTO dbo.Shipment_Audit_Log (Shipment_ID, Old_Status, New_Status)
        SELECT 
            i.Shipment_ID,
            d.Status AS Old_Status,
            i.Status AS New_Status
        FROM inserted i
        INNER JOIN deleted d ON i.Shipment_ID = d.Shipment_ID
        WHERE ISNULL(d.Status, '') <> ISNULL(i.Status, '');
    END
END;
GO


-- ============================================================================
-- 3. Create User-Defined Function (UDF) for Cost Efficiency
-- ============================================================================
-- Scalar function to calculate cost per mile dynamically for route analysis.
-- ============================================================================
IF OBJECT_ID('dbo.fn_CalculateCostPerMile', 'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_CalculateCostPerMile;
GO

CREATE FUNCTION dbo.fn_CalculateCostPerMile (
    @TotalCost FLOAT,
    @DistanceMiles INT
)
RETURNS FLOAT
AS
BEGIN
    IF @DistanceMiles IS NULL OR @DistanceMiles <= 0 OR @TotalCost IS NULL
        RETURN NULL;

    RETURN ROUND(@TotalCost / @DistanceMiles, 4);
END;
GO


-- ============================================================================
-- 4. Create Stored Procedure for Inserting New Shipments (`TRY...CATCH` & Transaction)
-- ============================================================================
-- Safely inserts a new shipment record, validates foreign keys, and handles runtime errors.
-- ============================================================================
IF OBJECT_ID('dbo.sp_InsertNewShipment', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_InsertNewShipment;
GO

CREATE PROCEDURE dbo.sp_InsertNewShipment
    @Shipment_ID       VARCHAR(50),
    @Origin_Warehouse  VARCHAR(50),
    @Destination       VARCHAR(100),
    @Carrier           VARCHAR(50),
    @Shipment_Date     DATE,
    @Weight_kg         FLOAT,
    @Cost              FLOAT,
    @Status            VARCHAR(50),
    @Distance_miles    INT,
    @Transit_Days      INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Validate that referenced Warehouse exists
    IF NOT EXISTS (SELECT 1 FROM dbo.Dim_Warehouse WHERE Warehouse_Code = @Origin_Warehouse)
    BEGIN
        RAISERROR('Error: Origin Warehouse does not exist in Dim_Warehouse.', 16, 1);
        RETURN;
    END

    -- Validate that referenced Carrier exists
    IF NOT EXISTS (SELECT 1 FROM dbo.Dim_Carrier WHERE Carrier_Name = @Carrier)
    BEGIN
        RAISERROR('Error: Carrier does not exist in Dim_Carrier.', 16, 1);
        RETURN;
    END

    BEGIN TRANSACTION;

    BEGIN TRY
        -- Insert new shipment record with auto-calculated delivery date
        INSERT INTO dbo.Fact_Shipments (
            Shipment_ID,
            Origin_Warehouse,
            Destination,
            Carrier,
            Shipment_Date,
            Delivery_Date,
            Weight_kg,
            Cost,
            Status,
            Distance_miles,
            Transit_Days
        )
        VALUES (
            @Shipment_ID,
            @Origin_Warehouse,
            @Destination,
            @Carrier,
            @Shipment_Date,
            DATEADD(day, @Transit_Days, @Shipment_Date),
            @Weight_kg,
            @Cost,
            @Status,
            @Distance_miles,
            @Transit_Days
        );

        COMMIT TRANSACTION;
        PRINT 'Success: New shipment inserted successfully.';
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        PRINT 'Error executing stored procedure. Transaction rolled back.';
        PRINT ERROR_MESSAGE();
    END CATCH;
END;
GO

--Test the UDF
SELECT Shipment_ID, Cost, Distance_miles, dbo.fn_CalculateCostPerMile(Cost, Distance_miles) AS Cost_Per_Mile 
FROM dbo.Fact_Shipments WHERE Cost IS NOT NULL;

--Test the Stored Procedure & Trigger
-- Insert a test shipment
EXEC dbo.sp_InsertNewShipment 
    @Shipment_ID = 'SH_TEST_999', 
    @Origin_Warehouse = 'Warehouse_MIA', 
    @Destination = 'Chicago', 
    @Carrier = 'UPS', 
    @Shipment_Date = '2026-06-01', 
    @Weight_kg = 24.5, 
    @Cost = 150.00, 
    @Status = 'In Transit', 
    @Distance_miles = 1200, 
    @Transit_Days = 3;

-- Update its status to test the audit trigger
UPDATE dbo.Fact_Shipments 
SET Status = 'Delivered' 
WHERE Shipment_ID = 'SH_TEST_999';

-- View audit logs
SELECT * FROM dbo.Shipment_Audit_Log;