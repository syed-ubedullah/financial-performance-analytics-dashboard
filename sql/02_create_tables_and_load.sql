/* =====================================================================
   Step 2: Financial Performance Analytics - SQL Server schema + data load
   Run in SSMS. Check the file path in the BULK INSERT statements below first.
   ===================================================================== */

-- ---------- 1. Database ----------
IF DB_ID('FinancialAnalytics') IS NULL CREATE DATABASE FinancialAnalytics;
GO
USE FinancialAnalytics;
GO

-- ---------- 2. Tables (children pehle drop) ----------
DROP TABLE IF EXISTS fact_ratios, fact_balance_sheet, fact_cashflow, fact_pnl, dim_company;
GO

CREATE TABLE dim_company (
    join_key             VARCHAR(60),
    company_name         NVARCHAR(100),
    bse_code             FLOAT,
    nse_code             VARCHAR(30),
    industry             NVARCHAR(100),
    current_price        FLOAT,
    market_cap_cr        FLOAT,
    latest_fy            INT,
    company_id           INT NOT NULL PRIMARY KEY,
    is_financial_sector  BIT,
    size_bucket          VARCHAR(30)
);

CREATE TABLE fact_pnl (
    company_id        INT NOT NULL,
    fiscal_year       INT NOT NULL,
    sales             FLOAT, operating_profit FLOAT, other_income FLOAT, depreciation FLOAT,
    ebit              FLOAT, interest FLOAT, pbt FLOAT, tax FLOAT, net_profit FLOAT,
    eps               FLOAT, dividend FLOAT, opm_pct FLOAT, npm_pct FLOAT, interest_coverage FLOAT,
    CONSTRAINT PK_fact_pnl PRIMARY KEY (company_id, fiscal_year),
    CONSTRAINT FK_pnl_company FOREIGN KEY (company_id) REFERENCES dim_company(company_id)
);

CREATE TABLE fact_cashflow (
    company_id           INT NOT NULL,
    fiscal_year          INT NOT NULL,
    cash_from_operations FLOAT, cash_from_investing FLOAT, cash_from_financing FLOAT,
    free_cash_flow       FLOAT, net_cash_flow FLOAT, cash_end_of_year FLOAT,
    CONSTRAINT PK_fact_cf PRIMARY KEY (company_id, fiscal_year),
    CONSTRAINT FK_cf_company FOREIGN KEY (company_id) REFERENCES dim_company(company_id)
);

CREATE TABLE fact_balance_sheet (
    company_id INT NOT NULL PRIMARY KEY,
    debt FLOAT, equity_capital FLOAT, reserves FLOAT, secured_loan FLOAT, unsecured_loan FLOAT,
    total_assets FLOAT, current_assets FLOAT, current_liabilities FLOAT, net_block FLOAT,
    investments FLOAT, inventory FLOAT, trade_receivables FLOAT, trade_payables FLOAT,
    cash_equivalents FLOAT, working_capital FLOAT, lease_liabilities FLOAT, contingent_liabilities FLOAT,
    net_worth FLOAT, current_ratio_calc FLOAT, debt_to_equity_calc FLOAT,
    CONSTRAINT FK_bs_company FOREIGN KEY (company_id) REFERENCES dim_company(company_id)
);

CREATE TABLE fact_ratios (
    company_id INT NOT NULL PRIMARY KEY,
    price_to_earning FLOAT, price_to_book_value FLOAT, dividend_yield FLOAT,
    return_on_equity FLOAT, return_on_assets FLOAT, return_on_invested_capital FLOAT,
    debt_to_equity FLOAT, quick_ratio FLOAT, promoter_holding FLOAT, fii_holding FLOAT,
    dii_holding FLOAT, public_holding FLOAT, piotroski_score FLOAT, asset_turnover_ratio FLOAT,
    cash_conversion_cycle FLOAT, average_return_on_equity_5years FLOAT, return_on_capital_employed FLOAT,
    current_ratio FLOAT, interest_coverage_ratio FLOAT, altman_z_score FLOAT, evebitda FLOAT,
    return_over_1year FLOAT, return_over_3years FLOAT, return_over_5years FLOAT, t_1_price FLOAT,
    financial_health VARCHAR(20),
    CONSTRAINT FK_ratios_company FOREIGN KEY (company_id) REFERENCES dim_company(company_id)
);
GO

-- ---------- 3. Load CSVs (parent table pehle) ----------
-- NOTE: copy the 5 clean CSVs (output of python/01_clean_and_reshape.py) into C:\SQLData\
--       or change the path below. The SQL Server service account needs read access to the folder.
BULK INSERT dim_company FROM 'C:\SQLData\dim_company.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', CODEPAGE='65001', KEEPNULLS);

BULK INSERT fact_pnl FROM 'C:\SQLData\fact_pnl.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', CODEPAGE='65001', KEEPNULLS);

BULK INSERT fact_cashflow FROM 'C:\SQLData\fact_cashflow.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', CODEPAGE='65001', KEEPNULLS);

BULK INSERT fact_balance_sheet FROM 'C:\SQLData\fact_balance_sheet.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', CODEPAGE='65001', KEEPNULLS);

BULK INSERT fact_ratios FROM 'C:\SQLData\fact_ratios.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', CODEPAGE='65001', KEEPNULLS);
GO

-- ---------- 4. Validation: expected 4668 / 9336 / 9336 / 4668 / 4668 ----------
SELECT 'dim_company' AS tbl, COUNT(*) AS row_count FROM dim_company
UNION ALL SELECT 'fact_pnl', COUNT(*) FROM fact_pnl
UNION ALL SELECT 'fact_cashflow', COUNT(*) FROM fact_cashflow
UNION ALL SELECT 'fact_balance_sheet', COUNT(*) FROM fact_balance_sheet
UNION ALL SELECT 'fact_ratios', COUNT(*) FROM fact_ratios;
