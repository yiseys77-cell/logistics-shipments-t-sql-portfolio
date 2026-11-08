-- ============================================================================
-- Project: Enterprise Logistics & Warehouse Management System
-- Script 4: Advanced Analytical Queries, Views & Supply Chain KPIs
-- Author: Data & Logistics Analytics Portfolio
-- ============================================================================

USE LogisticsDB;
GO

-- ============================================================================
-- 1. Create Analytics View: Executive Summary Dashboard KPI View
-- ============================================================================
-- Consolidates high-level logistics metrics across warehouses and carriers.
-- ============================================================================
IF OBJECT_ID('dbo.vw_Executive_Logistics_Summary', 'V') IS NOT NULL
    DROP VIEW dbo.vw_Executive_Logistics_Summary;
GO

CREATE VIEW dbo.vw_Executive_Logistics_Summary AS
SELECT 
    Origin_Warehouse,
    Carrier,
    COUNT(Shipment_ID) AS Total_Shipments,
    SUM(CASE WHEN Status = 'Delivered' THEN 1 ELSE 0 END) AS Delivered_Count,
    SUM(CASE WHEN Status = 'Delayed' THEN 1 ELSE 0 END) AS Delayed_Count,
    SUM(CASE WHEN Status = 'Lost' THEN 1 ELSE 0 END) AS Lost_Count,
    ROUND(CAST(SUM(CASE WHEN Status = 'Delivered' THEN 1 ELSE 0 END) AS FLOAT) * 100.0 / COUNT(Shipment_ID), 2) AS On_Time_Delivery_Rate_Pct,
    ROUND(AVG(Weight_kg), 2) AS Avg_Weight_kg,
    ROUND(SUM(Cost), 2) AS Total_Shipping_Cost,
    ROUND(AVG(Cost), 2) AS Avg_Shipment_Cost,
    ROUND(AVG(CAST(Transit_Days AS FLOAT)), 2) AS Avg_Transit_Days
FROM dbo.Fact_Shipments
GROUP BY Origin_Warehouse, Carrier;
GO


-- ============================================================================
-- 2. Advanced Window Functions: Carrier Cost Ranking by Distance Tier
-- ============================================================================
-- Uses CTEs and window ranking functions (DENSE_RANK, ROW_NUMBER) to evaluate
-- carrier efficiency across different distance brackets.
-- ============================================================================
WITH DistanceTierCTE AS (
    SELECT 
        Shipment_ID,
        Carrier,
        Origin_Warehouse,
        Destination,
        Distance_miles,
        Cost,
        dbo.fn_CalculateCostPerMile(Cost, Distance_miles) AS Cost_Per_Mile,
        CASE 
            WHEN Distance_miles < 500 THEN '1. Short-Haul (<500 mi)'
            WHEN Distance_miles BETWEEN 500 AND 1500 THEN '2. Medium-Haul (500-1500 mi)'
            ELSE '3. Long-Haul (>1500 mi)'
        END AS Distance_Tier
    FROM dbo.Fact_Shipments
    WHERE Cost IS NOT NULL AND Distance_miles > 0
),
RankedCarriers AS (
    SELECT 
        Distance_Tier,
        Carrier,
        COUNT(Shipment_ID) AS Total_Shipments,
        ROUND(AVG(Cost_Per_Mile), 4) AS Avg_Cost_Per_Mile,
        DENSE_RANK() OVER (PARTITION BY Distance_Tier ORDER BY AVG(Cost_Per_Mile) ASC) AS Cost_Rank
    FROM DistanceTierCTE
    GROUP BY Distance_Tier, Carrier
)
SELECT 
    Distance_Tier,
    Cost_Rank,
    Carrier,
    Total_Shipments,
    Avg_Cost_Per_Mile
FROM RankedCarriers
ORDER BY Distance_Tier, Cost_Rank;
GO


-- ============================================================================
-- 3. Warehouse Operational Bottleneck Analysis (Conditional Aggregation)
-- ============================================================================
-- Analyzes transit delays and risk profiles per origin warehouse.
-- ============================================================================
SELECT 
    Origin_Warehouse,
    COUNT(*) AS Total_Shipments,
    SUM(CASE WHEN Status = 'Delayed' THEN 1 ELSE 0 END) AS Delayed_Shipments,
    SUM(CASE WHEN Status = 'Lost' THEN 1 ELSE 0 END) AS Lost_Shipments,
    ROUND(SUM(CASE WHEN Status IN ('Delayed', 'Lost') THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS Risk_Failure_Rate_Pct,
    ROUND(AVG(Distance_miles), 2) AS Avg_Distance_Miles,
    ROUND(AVG(Transit_Days), 2) AS Avg_Transit_Days
FROM dbo.Fact_Shipments
GROUP BY Origin_Warehouse
ORDER BY Risk_Failure_Rate_Pct DESC;
GO


-- ============================================================================
-- 4. Running Totals & Cumulative Cost Analysis Over Time
-- ============================================================================
-- Demonstrates running sums and moving calculations partitioned by warehouse.
-- ============================================================================
SELECT 
    Origin_Warehouse,
    Shipment_Date,
    Shipment_ID,
    Cost,
    SUM(Cost) OVER (
        PARTITION BY Origin_Warehouse 
        ORDER BY Shipment_Date, Shipment_ID 
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS Cumulative_Warehouse_Spend
FROM dbo.Fact_Shipments
WHERE Cost IS NOT NULL AND Shipment_Date >= '2023-01-01'
ORDER BY Origin_Warehouse, Shipment_Date;
GO