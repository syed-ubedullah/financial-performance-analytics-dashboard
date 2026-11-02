/* =====================================================================
   Step 3: SQL Analysis + Power BI Views  (SQL Server / SSMS)
   Units: sales, profit, debt etc. = Rs Crore (market_cap_cr bhi Crore me)
   NOTE: Banks/NBFCs (is_financial_sector = 1) ke liye D/E, current ratio,
         OPM jaise ratios meaningful nahi hote -> margins/leverage queries
         me inhe exclude kiya hai.
   Har query ko alag select karke chalao (Execute selected). Last me VIEWS
   hain - wo poora block ek saath chalana.
   ===================================================================== */
USE FinancialAnalytics;
GO

/* ---------------- A. DATA SANITY CHECKS ---------------- */

-- A1. Latest FY distribution (zyadatar 2024 honi chahiye)
SELECT latest_fy, COUNT(*) AS companies
FROM dim_company
GROUP BY latest_fy
ORDER BY latest_fy DESC;

-- A2. Kitni companies financial sector me hain
SELECT is_financial_sector, COUNT(*) AS companies
FROM dim_company
GROUP BY is_financial_sector;

-- A3. Har company ke paas kitne years ka P&L hai (sab 2 hone chahiye)
SELECT years_available, COUNT(*) AS companies
FROM (SELECT company_id, COUNT(*) AS years_available FROM fact_pnl GROUP BY company_id) t
GROUP BY years_available;


/* ---------------- B. ANALYSIS QUERIES ---------------- */

-- B1. Executive KPIs (FY2024 reporters)
SELECT
    COUNT(DISTINCT d.company_id)                         AS companies,
    ROUND(SUM(p.sales), 0)                               AS total_sales_cr,
    ROUND(SUM(p.net_profit), 0)                          AS total_net_profit_cr,
    ROUND(SUM(p.net_profit) / NULLIF(SUM(p.sales),0) * 100, 2) AS overall_net_margin_pct
FROM dim_company d
JOIN fact_pnl p ON p.company_id = d.company_id AND p.fiscal_year = d.latest_fy
WHERE d.latest_fy = 2024 AND d.is_financial_sector = 0;

-- B2. Sales aur profit YoY growth per company  (LAG window function)
WITH yoy AS (
    SELECT company_id, fiscal_year, sales, net_profit,
           LAG(sales)      OVER (PARTITION BY company_id ORDER BY fiscal_year) AS prev_sales,
           LAG(net_profit) OVER (PARTITION BY company_id ORDER BY fiscal_year) AS prev_profit
    FROM fact_pnl
)
SELECT TOP 20
    d.company_name, d.industry, y.fiscal_year,
    y.sales, y.prev_sales,
    ROUND((y.sales - y.prev_sales) / y.prev_sales * 100, 2) AS sales_yoy_pct
FROM yoy y
JOIN dim_company d ON d.company_id = y.company_id
WHERE y.fiscal_year = d.latest_fy
  AND y.prev_sales > 0 AND y.sales >= 1000          -- chhoti base wali companies skip
ORDER BY sales_yoy_pct DESC;

-- B3. Industry-wise performance + RANK()   (non-financial, FY2024)
WITH ind AS (
    SELECT d.industry,
           COUNT(*)                                          AS companies,
           SUM(p.sales)                                      AS total_sales,
           SUM(p.net_profit)                                 AS total_profit,
           SUM(p.net_profit) / NULLIF(SUM(p.sales),0) * 100  AS net_margin_pct
    FROM dim_company d
    JOIN fact_pnl p ON p.company_id = d.company_id AND p.fiscal_year = d.latest_fy
    WHERE d.latest_fy = 2024 AND d.is_financial_sector = 0
    GROUP BY d.industry
)
SELECT industry, companies,
       ROUND(total_sales,0)  AS total_sales_cr,
       ROUND(total_profit,0) AS total_profit_cr,
       ROUND(net_margin_pct,2) AS net_margin_pct,
       RANK() OVER (ORDER BY total_sales  DESC) AS sales_rank,
       RANK() OVER (ORDER BY net_margin_pct DESC) AS margin_rank
FROM ind
WHERE companies >= 5
ORDER BY sales_rank;

-- B4. Top 10 companies by net profit (FY2024)
SELECT TOP 10 d.company_name, d.industry,
       ROUND(p.sales,0) AS sales_cr, ROUND(p.net_profit,0) AS net_profit_cr,
       ROUND(p.npm_pct,2) AS net_margin_pct
FROM dim_company d
JOIN fact_pnl p ON p.company_id = d.company_id AND p.fiscal_year = d.latest_fy
WHERE d.latest_fy = 2024
ORDER BY p.net_profit DESC;

-- B5. Industry ke andar top company by profit  (ROW_NUMBER + PARTITION BY)
WITH ranked AS (
    SELECT d.industry, d.company_name, p.net_profit,
           ROW_NUMBER() OVER (PARTITION BY d.industry ORDER BY p.net_profit DESC) AS rn
    FROM dim_company d
    JOIN fact_pnl p ON p.company_id = d.company_id AND p.fiscal_year = d.latest_fy
    WHERE d.latest_fy = 2024
)
SELECT industry, company_name, ROUND(net_profit,0) AS net_profit_cr
FROM ranked WHERE rn = 1
ORDER BY net_profit DESC;

-- B6. Risky leveraged companies: high D/E + weak interest coverage (non-financial)
SELECT TOP 25 d.company_name, d.industry,
       ROUND(b.debt_to_equity_calc,2)     AS debt_to_equity,
       ROUND(r.interest_coverage_ratio,2) AS interest_coverage,
       ROUND(r.altman_z_score,2)          AS altman_z,
       r.financial_health
FROM dim_company d
JOIN fact_balance_sheet b ON b.company_id = d.company_id
JOIN fact_ratios r        ON r.company_id = d.company_id
WHERE d.is_financial_sector = 0
  AND d.market_cap_cr >= 500
  AND b.debt_to_equity_calc > 2
  AND r.interest_coverage_ratio < 1.5
ORDER BY b.debt_to_equity_calc DESC;

-- B7. Financial health (Altman Z) distribution by size bucket
SELECT d.size_bucket, r.financial_health, COUNT(*) AS companies
FROM dim_company d
JOIN fact_ratios r ON r.company_id = d.company_id
WHERE d.is_financial_sector = 0 AND r.financial_health IS NOT NULL
GROUP BY d.size_bucket, r.financial_health
ORDER BY d.size_bucket, r.financial_health;

-- B8. Earnings quality red flag: profit dikha raha hai par operating cash flow negative
SELECT TOP 20 d.company_name, d.industry,
       ROUND(p.net_profit,0)             AS net_profit_cr,
       ROUND(c.cash_from_operations,0)   AS cfo_cr
FROM dim_company d
JOIN fact_pnl p      ON p.company_id = d.company_id AND p.fiscal_year = d.latest_fy
JOIN fact_cashflow c ON c.company_id = d.company_id AND c.fiscal_year = d.latest_fy
WHERE d.latest_fy = 2024 AND d.is_financial_sector = 0
  AND p.net_profit > 100 AND c.cash_from_operations < 0
ORDER BY p.net_profit DESC;

-- B9. Industry average ROE / ROCE (kam se kam 10 companies wali industries)
SELECT d.industry, COUNT(*) AS companies,
       ROUND(AVG(r.return_on_equity),2)          AS avg_roe_pct,
       ROUND(AVG(r.return_on_capital_employed),2) AS avg_roce_pct
FROM dim_company d
JOIN fact_ratios r ON r.company_id = d.company_id
WHERE d.is_financial_sector = 0
  AND r.return_on_equity IS NOT NULL
GROUP BY d.industry
HAVING COUNT(*) >= 10
ORDER BY avg_roe_pct DESC;
GO


/* ---------------- C. VIEWS FOR POWER BI ---------------- */

-- C1. Ek row = ek company (latest FY snapshot + YoY + ratios)
CREATE OR ALTER VIEW vw_company_summary AS
WITH pnl_yoy AS (
    SELECT company_id, fiscal_year, sales, operating_profit, net_profit, ebit,
           interest, eps, opm_pct, npm_pct, interest_coverage,
           LAG(sales)      OVER (PARTITION BY company_id ORDER BY fiscal_year) AS prev_sales,
           LAG(net_profit) OVER (PARTITION BY company_id ORDER BY fiscal_year) AS prev_net_profit
    FROM fact_pnl
)
SELECT
    d.company_id, d.company_name, d.nse_code, d.industry, d.size_bucket,
    d.is_financial_sector, d.latest_fy AS fiscal_year,
    d.current_price, d.market_cap_cr,
    p.sales, p.operating_profit, p.net_profit, p.eps, p.opm_pct, p.npm_pct,
    CASE WHEN p.prev_sales > 0
         THEN (p.sales - p.prev_sales) / p.prev_sales * 100 END      AS sales_yoy_pct,
    CASE WHEN p.prev_net_profit > 0
         THEN (p.net_profit - p.prev_net_profit) / p.prev_net_profit * 100 END AS profit_yoy_pct,
    CASE WHEN p.net_profit > 0 THEN 'Profit' ELSE 'Loss' END         AS profit_status,
    b.debt, b.net_worth, b.total_assets, b.current_ratio_calc, b.debt_to_equity_calc,
    c.cash_from_operations, c.cash_from_investing, c.cash_from_financing, c.free_cash_flow,
    r.price_to_earning, r.price_to_book_value, r.dividend_yield,
    r.return_on_equity, r.return_on_assets, r.return_on_capital_employed,
    r.interest_coverage_ratio, r.altman_z_score, r.financial_health,
    r.promoter_holding, r.fii_holding, r.dii_holding, r.public_holding,
    r.return_over_1year, r.return_over_3years, r.return_over_5years
FROM dim_company d
JOIN pnl_yoy p                 ON p.company_id = d.company_id AND p.fiscal_year = d.latest_fy
LEFT JOIN fact_balance_sheet b ON b.company_id = d.company_id
LEFT JOIN fact_cashflow c      ON c.company_id = d.company_id AND c.fiscal_year = d.latest_fy
LEFT JOIN fact_ratios r        ON r.company_id = d.company_id;
GO

-- C2. Company x Year P&L + cash flow (trend charts ke liye)
CREATE OR ALTER VIEW vw_financial_trend AS
SELECT d.company_id, d.company_name, d.industry, d.size_bucket, d.is_financial_sector,
       p.fiscal_year, p.sales, p.operating_profit, p.net_profit, p.eps,
       p.opm_pct, p.npm_pct, p.interest_coverage,
       c.cash_from_operations, c.cash_from_investing, c.cash_from_financing, c.free_cash_flow
FROM dim_company d
JOIN fact_pnl p           ON p.company_id = d.company_id
LEFT JOIN fact_cashflow c ON c.company_id = p.company_id AND c.fiscal_year = p.fiscal_year;
GO

-- C3. Industry level summary (latest FY, non-financial)
CREATE OR ALTER VIEW vw_industry_summary AS
SELECT industry,
       COUNT(*)                                             AS companies,
       SUM(sales)                                           AS total_sales,
       SUM(net_profit)                                      AS total_net_profit,
       SUM(net_profit) / NULLIF(SUM(sales),0) * 100         AS net_margin_pct,
       AVG(return_on_equity)                                AS avg_roe_pct,
       AVG(debt_to_equity_calc)                             AS avg_debt_to_equity,
       SUM(CASE WHEN profit_status = 'Loss' THEN 1 ELSE 0 END) AS loss_making_companies
FROM vw_company_summary
WHERE is_financial_sector = 0
GROUP BY industry;
GO

-- Quick test
SELECT TOP 5 * FROM vw_company_summary ORDER BY market_cap_cr DESC;
SELECT COUNT(*) AS rows_in_company_summary FROM vw_company_summary;
SELECT COUNT(*) AS rows_in_trend FROM vw_financial_trend;
SELECT COUNT(*) AS industries FROM vw_industry_summary;
