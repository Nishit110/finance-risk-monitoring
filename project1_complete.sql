-- ================================================================
-- PROJECT 1: Finance Data Risk Monitoring & Control Effectiveness
-- FILE: project1_complete.sql
-- Author: Nishit Patel
-- HOW TO USE:
--   1. Open MySQL Workbench
--   2. Create a new schema called: finance_risk_db
--   3. Run this entire file (Ctrl+Shift+Enter)
-- ================================================================

CREATE DATABASE IF NOT EXISTS finance_risk_db;
USE finance_risk_db;

-- ── DROP & CREATE TABLE ─────────────────────────────────────
DROP TABLE IF EXISTS fact_shipments;

CREATE TABLE fact_shipments (
    shipment_id         VARCHAR(20)    PRIMARY KEY,
    carrier             VARCHAR(60)    NOT NULL,
    region              VARCHAR(60),
    shipment_mode       VARCHAR(20),
    product_category    VARCHAR(60),
    ship_date           DATE,
    delivery_date       DATE,
    delivery_days       INT,
    estimated_days      INT,
    freight_cost_usd    DECIMAL(10,2),
    shipment_weight_kg  DECIMAL(10,2),
    shipment_value_usd  DECIMAL(10,2),
    is_late             BOOLEAN,
    is_damaged          BOOLEAN,
    delivery_status     VARCHAR(20)
);

-- INDEX for faster queries
CREATE INDEX idx_ship_date  ON fact_shipments(ship_date);
CREATE INDEX idx_carrier    ON fact_shipments(carrier);
CREATE INDEX idx_is_late    ON fact_shipments(is_late);

-- ── LOAD DATA ───────────────────────────────────────────────
-- NOTE: Update the file path below to where you saved the CSV
-- Windows example: 'C:/Users/YourName/Downloads/finance_shipments.csv'
-- Mac example:     '/Users/YourName/Downloads/finance_shipments.csv'

LOAD DATA INFILE '/path/to/finance_shipments.csv'
INTO TABLE fact_shipments
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(shipment_id, carrier, region, shipment_mode, product_category,
 ship_date, delivery_date, delivery_days, estimated_days,
 freight_cost_usd, shipment_weight_kg, shipment_value_usd,
 @is_late, @is_damaged, delivery_status)
SET
  is_late    = IF(@is_late    = 'True', 1, 0),
  is_damaged = IF(@is_damaged = 'True', 1, 0);

SELECT CONCAT('Data loaded: ', COUNT(*), ' rows') AS status FROM fact_shipments;

-- ================================================================
-- ANALYSIS QUERIES — RUN ONE BY ONE AFTER DATA IS LOADED
-- ================================================================

-- ── QUERY 1: Platform-wide KPI Summary ──────────────────────
SELECT
    COUNT(shipment_id)                                              AS total_shipments,
    COUNT(DISTINCT carrier)                                         AS active_carriers,
    COUNT(DISTINCT region)                                          AS active_regions,
    ROUND(AVG(freight_cost_usd), 2)                                AS avg_freight_cost,
    ROUND(AVG(delivery_days), 1)                                   AS avg_delivery_days,
    ROUND(SUM(CASE WHEN NOT is_late THEN 1 ELSE 0 END) * 100.0
          / COUNT(*), 2)                                            AS on_time_rate_pct,
    ROUND(SUM(CASE WHEN is_damaged THEN 1 ELSE 0 END) * 100.0
          / COUNT(*), 2)                                            AS damage_rate_pct,
    ROUND(SUM(shipment_value_usd), 2)                              AS total_shipment_value
FROM fact_shipments;

-- ── QUERY 2: Carrier Performance Benchmark ──────────────────
SELECT
    carrier,
    COUNT(*)                                                        AS total_shipments,
    ROUND(AVG(freight_cost_usd), 2)                                AS avg_cost,
    ROUND(AVG(delivery_days), 1)                                   AS avg_delivery_days,
    ROUND(SUM(CASE WHEN NOT is_late THEN 1 ELSE 0 END) * 100.0
          / COUNT(*), 2)                                            AS on_time_rate_pct,
    ROUND(SUM(CASE WHEN is_damaged THEN 1 ELSE 0 END) * 100.0
          / COUNT(*), 2)                                            AS damage_rate_pct,
    CASE
        WHEN SUM(CASE WHEN NOT is_late THEN 1 ELSE 0 END) * 100.0
             / COUNT(*) >= 60 THEN 'Tier 1 — Preferred'
        WHEN SUM(CASE WHEN NOT is_late THEN 1 ELSE 0 END) * 100.0
             / COUNT(*) >= 45 THEN 'Tier 2 — Acceptable'
        WHEN SUM(CASE WHEN NOT is_late THEN 1 ELSE 0 END) * 100.0
             / COUNT(*) >= 30 THEN 'Tier 3 — Monitor'
        ELSE 'Tier 4 — Review Contract'
    END                                                             AS performance_tier
FROM fact_shipments
GROUP BY carrier
ORDER BY on_time_rate_pct DESC;

-- ── QUERY 3: Monthly Cost Anomaly Detection (LAG) ────────────
-- Shows month-over-month cost change per carrier
-- Flags spikes > 10% as anomalies (early warning indicator)
SELECT
    carrier,
    DATE_FORMAT(ship_date, '%Y-%m')                                AS month,
    ROUND(AVG(freight_cost_usd), 2)                                AS avg_cost,
    COUNT(*)                                                        AS shipments,
    ROUND(AVG(CASE WHEN is_late THEN 1 ELSE 0 END) * 100, 2)      AS late_rate_pct
FROM fact_shipments
GROUP BY carrier, DATE_FORMAT(ship_date, '%Y-%m')
ORDER BY carrier, month;
-- NOTE: Run the above first, then use this view for MoM delta:
-- In Google Colab (Python) we calculate LAG/LEAD using pandas shift()
-- See the Colab notebook for the full window function equivalent

-- ── QUERY 4: Regional Risk Heatmap ──────────────────────────
SELECT
    region,
    COUNT(*)                                                        AS total_shipments,
    ROUND(AVG(freight_cost_usd), 2)                                AS avg_cost,
    ROUND(AVG(delivery_days), 1)                                   AS avg_delivery_days,
    ROUND(SUM(CASE WHEN is_late THEN 1 ELSE 0 END) * 100.0
          / COUNT(*), 2)                                            AS late_rate_pct,
    ROUND(SUM(shipment_value_usd), 2)                              AS total_value,
    CASE
        WHEN SUM(CASE WHEN is_late THEN 1 ELSE 0 END) * 100.0
             / COUNT(*) <= 25 THEN 'Low Risk'
        WHEN SUM(CASE WHEN is_late THEN 1 ELSE 0 END) * 100.0
             / COUNT(*) <= 50 THEN 'Medium Risk'
        ELSE 'High Risk'
    END                                                             AS risk_level
FROM fact_shipments
GROUP BY region
ORDER BY late_rate_pct DESC;

-- ── QUERY 5: Control Effectiveness by Shipment Mode ─────────
SELECT
    shipment_mode,
    COUNT(*)                                                        AS total_shipments,
    ROUND(AVG(freight_cost_usd), 2)                                AS avg_cost,
    ROUND(SUM(CASE WHEN NOT is_late THEN 1 ELSE 0 END) * 100.0
          / COUNT(*), 2)                                            AS on_time_rate_pct,
    ROUND(SUM(CASE WHEN is_damaged THEN 1 ELSE 0 END) * 100.0
          / COUNT(*), 2)                                            AS damage_rate_pct,
    ROUND(SUM(shipment_value_usd), 2)                              AS total_value
FROM fact_shipments
GROUP BY shipment_mode
ORDER BY on_time_rate_pct DESC;

-- ── QUERY 6: Daily Ops Snapshot (SOP Tier 1) ─────────────────
CREATE OR REPLACE VIEW vw_daily_ops AS
SELECT
    ship_date,
    carrier,
    COUNT(*)                                                        AS shipments,
    SUM(CASE WHEN is_late THEN 1 ELSE 0 END)                       AS late_count,
    ROUND(AVG(freight_cost_usd), 2)                                AS avg_cost,
    ROUND(SUM(CASE WHEN is_late THEN 1 ELSE 0 END) * 100.0
          / COUNT(*), 2)                                            AS late_rate_pct
FROM fact_shipments
GROUP BY ship_date, carrier
ORDER BY ship_date DESC;

-- ── QUERY 7: Weekly Trend Report (SOP Tier 2) ────────────────
CREATE OR REPLACE VIEW vw_weekly_trend AS
SELECT
    YEAR(ship_date)                                                 AS year,
    WEEK(ship_date)                                                 AS week_num,
    MIN(ship_date)                                                  AS week_start,
    COUNT(*)                                                        AS total_shipments,
    ROUND(AVG(freight_cost_usd), 2)                                AS avg_cost,
    SUM(CASE WHEN is_late THEN 1 ELSE 0 END)                       AS late_count,
    ROUND(SUM(CASE WHEN is_late THEN 1 ELSE 0 END) * 100.0
          / COUNT(*), 2)                                            AS late_rate_pct,
    ROUND(SUM(shipment_value_usd), 2)                              AS total_value
FROM fact_shipments
GROUP BY YEAR(ship_date), WEEK(ship_date)
ORDER BY year DESC, week_num DESC;

-- ── QUERY 8: Monthly Executive Summary (SOP Tier 3) ──────────
CREATE OR REPLACE VIEW vw_monthly_executive AS
SELECT
    DATE_FORMAT(ship_date, '%Y-%m')                                AS month,
    COUNT(*)                                                        AS total_shipments,
    COUNT(DISTINCT carrier)                                         AS active_carriers,
    ROUND(AVG(freight_cost_usd), 2)                                AS avg_cost,
    ROUND(SUM(CASE WHEN NOT is_late THEN 1 ELSE 0 END) * 100.0
          / COUNT(*), 2)                                            AS on_time_rate_pct,
    ROUND(SUM(shipment_value_usd), 2)                              AS total_value,
    ROUND(100 - SUM(CASE WHEN is_late THEN 1 ELSE 0 END) * 100.0
          / COUNT(*), 2)                                            AS ops_health_score
FROM fact_shipments
GROUP BY DATE_FORMAT(ship_date, '%Y-%m')
ORDER BY month DESC;

SELECT 'All queries and views created successfully' AS final_status;
