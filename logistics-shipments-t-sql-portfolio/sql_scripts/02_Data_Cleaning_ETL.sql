-- ============================================================================
-- Project: Enterprise Logistics & Warehouse Management System
-- Script 2: Data Cleaning & ETL Pipeline
-- Author: Data & Logistics Analytics Portfolio
-- ============================================================================

USE LogisticsDB;
GO

-- ============================================================================
-- STEP 1: Populate Dimension Tables from Staging
-- ============================================================================

-- Populate Dim_Warehouse with distinct origins and derive regional groups
INSERT INTO dbo.Dim_Warehouse (Warehouse_Code, Region)
SELECT DISTINCT 
    Origin_Warehouse,
    CASE 
        WHEN Origin_Warehouse LIKE '%MIA%' THEN 'Southeast'
        WHEN Origin_Warehouse LIKE '%LA%' OR Origin_Warehouse LIKE '%SF%' THEN 'West Coast'
        WHEN Origin_Warehouse LIKE '%BOS%' OR Origin_Warehouse LIKE '%NYC%' THEN 'Northeast'
        WHEN Origin_Warehouse LIKE '%CHI%' THEN 'Midwest'
        WHEN Origin_Warehouse LIKE '%ATL%' THEN 'Southeast'
        WHEN Origin_Warehouse LIKE '%HOU%' THEN 'South'
        WHEN Origin_Warehouse LIKE '%DEN%' THEN 'Mountain'
        ELSE 'General'
    END AS Region
FROM dbo.stg_Shipments
WHERE Origin_Warehouse IS NOT NULL
  AND Origin_Warehouse NOT IN (SELECT Warehouse_Code FROM dbo.Dim_Warehouse);
GO

-- Populate Dim_Carrier with distinct carriers and categorize service levels
INSERT INTO dbo.Dim_Carrier (Carrier_Name, Service_Level)
SELECT DISTINCT 
    Carrier,
    CASE 
        WHEN Carrier IN ('UPS', 'FedEx', 'DHL') THEN 'Express / Premium'
        ELSE 'Standard / Ground'
    END AS Service_Level
FROM dbo.stg_Shipments
WHERE Carrier IS NOT NULL
  AND Carrier NOT IN (SELECT Carrier_Name FROM dbo.Dim_Carrier);
GO


-- ============================================================================
-- STEP 2: Data Cleaning, Transformation & Fact Table Ingestion
-- ============================================================================
-- Wrapped in an explicit transaction with error handling to guarantee atomicity.
-- ============================================================================

BEGIN TRANSACTION;

BEGIN TRY
    -- Clear existing fact table data if re-running ETL
    TRUNCATE TABLE dbo.Fact_Shipments;

    -- Insert cleaned and transformed records into Fact_Shipments
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
    SELECT 
        s.Shipment_ID,
        s.Origin_Warehouse,
        s.Destination,
        s.Carrier,
        
        -- 1. Parse Shipment Date safely
        CAST(s.Shipment_Date AS DATE) AS Shipment_Date,
        
        -- 2. Handle missing Delivery_Dates based on shipment status
        CASE 
            WHEN TRY_CAST(s.Delivery_Date AS DATE) IS NOT NULL THEN CAST(s.Delivery_Date AS DATE)
            WHEN s.Status IN ('In Transit', 'Lost') THEN NULL
            ELSE DATEADD(day, TRY_CAST(s.Transit_Days AS INT), CAST(s.Shipment_Date AS DATE))
        END AS Delivery_Date,
        
        -- 3. Clean Weight anomalies (Handle 0.0 values and extreme outlier spikes > 1000kg)
        CASE 
            WHEN TRY_CAST(s.Weight_kg AS FLOAT) <= 0 THEN 15.0 -- Floor invalid zero weights
            WHEN TRY_CAST(s.Weight_kg AS FLOAT) > 1000.0 THEN 50.0 -- Cap extreme outlier records
            ELSE TRY_CAST(s.Weight_kg AS FLOAT)
        END AS Weight_kg,
        
        -- 4. Impute missing Costs using estimated baseline cost-per-mile ($0.18/mile)
        ISNULL(TRY_CAST(s.Cost AS FLOAT), TRY_CAST(s.Distance_miles AS INT) * 0.18) AS Cost,
        
        s.Status,
        TRY_CAST(s.Distance_miles AS INT) AS Distance_miles,
        TRY_CAST(s.Transit_Days AS INT) AS Transit_Days

    FROM dbo.stg_Shipments s
    WHERE TRY_CAST(s.Shipment_ID AS VARCHAR(50)) IS NOT NULL;

    COMMIT TRANSACTION;
    PRINT 'ETL Pipeline executed successfully: Fact_Shipments populated and cleaned.';

END TRY
BEGIN CATCH
    ROLLBACK TRANSACTION;
    PRINT 'Error occurred during ETL pipeline execution. Transaction rolled back.';
    PRINT ERROR_MESSAGE();
END CATCH;
GO


-- ============================================================================
-- STEP 3: Data Quality & Hygiene Verification Queries
-- ============================================================================

-- Query 1: Verify row count match between staging and production fact table
SELECT 
    (SELECT COUNT(*) FROM dbo.stg_Shipments) AS Staging_Total_Rows,
    (SELECT COUNT(*) FROM dbo.Fact_Shipments) AS Fact_Table_Total_Rows;
GO

-- Query 2: Audit NULL distributions and metrics by shipment status
SELECT 
    Status,
    COUNT(*) AS Total_Shipments,
    SUM(CASE WHEN Delivery_Date IS NULL THEN 1 ELSE 0 END) AS Unresolved_Delivery_Dates,
    SUM(CASE WHEN Cost IS NULL THEN 1 ELSE 0 END) AS Unbilled_Costs,
    ROUND(AVG(Weight_kg), 2) AS Avg_Weight_kg,
    ROUND(AVG(Cost), 2) AS Avg_Cost_USD
FROM dbo.Fact_Shipments
GROUP BY Status;
GO