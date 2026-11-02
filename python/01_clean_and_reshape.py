"""
Step 1: Clean + reshape Indian listed-company financial dataset
Input : folder with the 11 Kaggle CSVs (pacificrm/financial-sheets)
Output: SQL-ready clean CSVs (dim_company, fact_pnl, fact_cashflow,
        fact_balance_sheet, fact_ratios) + data_quality_report.txt

Run:  python 01_clean_and_reshape.py
"""
import os
import numpy as np
import pandas as pd

from pathlib import Path
BASE = Path(__file__).resolve().parent.parent      # repo root
IN_DIR = BASE / "data" / "raw"                      # put the 11 Kaggle CSVs here
OUT_DIR = BASE / "clean_output"                     # generated output
os.makedirs(OUT_DIR, exist_ok=True)

rd = lambda f: pd.read_csv(os.path.join(IN_DIR, f))
pl1, bs, cf = rd("Annual_P_L_1_final.csv"), rd("Balance_Sheet_final.csv"), rd("cash_flow_statments_final.csv")
rat1, oth, pr, t1 = rd("ratios_1_final.csv"), rd("other_metrics_final.csv"), rd("price_final.csv"), rd("t1_prices.csv")
rep = []

def snake(c):
    return (c.strip().lower().replace("%", "pct").replace("/", "_").replace("-", "_")
            .replace("(", "").replace(")", "").replace(" ", "_"))

# ---------- 1. dim_company ----------
dim = pl1[["join_key", "Name", "BSE Code", "NSE Code", "Industry", "Current Price",
           "Market Capitalization", "Last annual result date"]].copy()
dim.columns = ["join_key", "company_name", "bse_code", "nse_code", "industry",
               "current_price", "market_cap_cr", "last_result_date"]
dim["nse_code"] = dim["nse_code"].replace("__NA__", np.nan)
dim["latest_fy"] = (dim["last_result_date"] // 100).astype("Int64")          # 202403 -> 2024
dim["company_id"] = np.arange(1, len(dim) + 1)
# Banks/NBFCs/insurers: D/E, current ratio  -> flag
dim["is_financial_sector"] = dim["industry"].str.contains("Bank|Financ|Insurance", case=False, na=False).astype(int)
dim["size_bucket"] = pd.cut(dim["market_cap_cr"], [-np.inf, 500, 5000, 20000, np.inf],
                            labels=["Micro (<500 Cr)", "Small (500-5K Cr)", "Mid (5K-20K Cr)", "Large (>20K Cr)"])
dim = dim.drop(columns="last_result_date")
key_map = dim.set_index("join_key")["company_id"]

# ---------- 2. fact_pnl : wide -> long (FY latest, FY latest-1) ----------
# NOTE: 'Sales' == 'Sales last year' (97.6% rows) => current == latest FY. 'preceding year' == FY-1.
latest = pd.DataFrame({
    "join_key": pl1.join_key, "offset": 0,
    "sales": pl1["Sales last year"], "operating_profit": pl1["Operating profit last year"],
    "other_income": pl1["Other income last year"], "depreciation": pl1["Depreciation last year"],
    "ebit": pl1["EBIT last year"], "interest": pl1["Interest last year"],
    "pbt": pl1["Profit before tax last year"], "tax": pl1["Tax last year"],
    "net_profit": pl1["Net Profit last year"], "eps": pl1["EPS last year"],
    "dividend": pl1["Dividend last year"], "opm_pct": pl1["OPM last year"], "npm_pct": pl1["NPM last year"]})
prev = pd.DataFrame({
    "join_key": pl1.join_key, "offset": -1,
    "sales": pl1["Sales preceding year"], "operating_profit": pl1["Operating profit preceding year"],
    "other_income": pl1["Other income preceding year"], "depreciation": pl1["Depreciation preceding year"],
    "ebit": pl1["EBIT preceding year"], "interest": pl1["Interest preceding year"],
    "pbt": pl1["Profit before tax preceding year"], "tax": pl1["Tax preceding year"],
    "net_profit": pl1["Net Profit preceding year"], "eps": pl1["EPS preceding year"],
    "dividend": pl1["Dividend preceding year"], "opm_pct": pl1["OPM preceding year"], "npm_pct": pl1["NPM preceding year"]})
pnl = pd.concat([latest, prev], ignore_index=True)
pnl = pnl.merge(dim[["join_key", "latest_fy"]], on="join_key")
pnl["fiscal_year"] = pnl["latest_fy"] + pnl["offset"]
pnl["company_id"] = pnl["join_key"].map(key_map)
# recompute margins safely 
pnl["opm_pct"] = np.where(pnl.sales > 0, pnl.operating_profit / pnl.sales * 100, np.nan)
pnl["npm_pct"] = np.where(pnl.sales > 0, pnl.net_profit / pnl.sales * 100, np.nan)
pnl["interest_coverage"] = np.where(pnl.interest > 0, pnl.ebit / pnl.interest, np.nan)
rep.append(f"fact_pnl rows with sales<=0 or null: {(pnl.sales.fillna(0) <= 0).sum()} (margins left NULL)")
pnl = pnl.drop(columns=["join_key", "offset", "latest_fy"])
pnl = pnl[["company_id", "fiscal_year"] + [c for c in pnl.columns if c not in ("company_id", "fiscal_year")]]

# ---------- 3. fact_cashflow (2 years) ----------
def cf_year(sfx, off):
    d = pd.DataFrame({"join_key": cf.join_key, "offset": off,
        "cash_from_operations": cf[f"Cash from operations {sfx}"], "cash_from_investing": cf[f"Cash from investing {sfx}"],
        "cash_from_financing": cf[f"Cash from financing {sfx}"], "free_cash_flow": cf[f"Free cash flow {sfx}"],
        "net_cash_flow": cf[f"Net cash flow {sfx}"], "cash_end_of_year": cf[f"Cash end of {sfx}"]})
    return d
cfl = pd.concat([cf_year("last year", 0), cf_year("preceding year", -1)], ignore_index=True)
cfl = cfl.merge(dim[["join_key", "latest_fy"]], on="join_key")
cfl["fiscal_year"] = cfl["latest_fy"] + cfl["offset"]
cfl["company_id"] = cfl["join_key"].map(key_map)
cfl = cfl.drop(columns=["join_key", "offset", "latest_fy"])
cfl = cfl[["company_id", "fiscal_year"] + [c for c in cfl.columns if c not in ("company_id", "fiscal_year")]]

# ---------- 4. fact_balance_sheet (latest FY snapshot) ----------
bcols = ["Debt", "Equity capital", "Reserves", "Secured loan", "Unsecured loan", "Total Assets", "Current assets",
         "Current liabilities", "Net block", "Investments", "Inventory", "Trade receivables", "Trade Payables",
         "Cash Equivalents", "Working capital", "Lease liabilities", "Contingent liabilities"]
bsn = bs[["join_key"] + bcols].copy()
bsn.columns = ["join_key"] + [snake(c) for c in bcols]
bsn["company_id"] = bsn["join_key"].map(key_map)
bsn["net_worth"] = bsn["equity_capital"] + bsn["reserves"]
bsn["current_ratio_calc"] = np.where(bsn.current_liabilities > 0, bsn.current_assets / bsn.current_liabilities, np.nan)
bsn["debt_to_equity_calc"] = np.where(bsn.net_worth > 0, bsn.debt / bsn.net_worth, np.nan)
bsn = bsn.drop(columns="join_key")
bsn = bsn[["company_id"] + [c for c in bsn.columns if c != "company_id"]]

# ---------- 5. fact_ratios (latest snapshot) ----------
rcols = ["Price to Earning", "Price to book value", "Dividend yield", "Return on equity", "Return on assets",
         "Return on invested capital", "Debt to equity", "Quick ratio", "Promoter holding", "FII holding",
         "DII holding", "Public holding", "Piotroski score", "Asset Turnover Ratio", "Cash Conversion Cycle",
         "Average return on equity 5Years" ]
r = rat1[["join_key"] + rcols[:-1]].copy()
r = r.merge(rd("ratios_2_final.csv")[["join_key", "Average return on equity 5Years"]], on="join_key")
r = r.merge(pl1[["join_key", "Return on capital employed"]], on="join_key")
r = r.merge(oth[["join_key", "Current ratio", "Interest Coverage Ratio", "Altman Z Score", "EVEBITDA"]], on="join_key")
r = r.merge(pr[["join_key", "Return over 1year", "Return over 3years", "Return over 5years"]], on="join_key")
r = r.merge(t1, on="join_key", how="left")
r.columns = ["join_key"] + [snake(c) for c in r.columns[1:]]
r["company_id"] = r["join_key"].map(key_map)
r = r.drop(columns="join_key")
# Altman Z -> health category (standard cut-offs: <1.81 distress, 1.81-2.99 grey, >2.99 safe)
r["financial_health"] = pd.cut(r["altman_z_score"], [-np.inf, 1.81, 2.99, np.inf], labels=["Distress", "Grey Zone", "Safe"])
r = r[["company_id"] + [c for c in r.columns if c != "company_id"]]
pnl = pnl.dropna(subset=["fiscal_year"])
cfl = cfl.dropna(subset=["fiscal_year"])

# ---------- Data quality report ----------
rep.insert(0, f"Companies: {len(dim)} | Industries: {dim.industry.nunique()} | Financial-sector flagged: {dim.is_financial_sector.sum()}")
rep.append("Latest FY distribution:\n" + dim.latest_fy.value_counts().head(5).to_string())
for name, df in [("fact_pnl", pnl), ("fact_cashflow", cfl), ("fact_balance_sheet", bsn), ("fact_ratios", r)]:
    nulls = (df.isna().mean() * 100).round(1).sort_values(ascending=False).head(5)
    rep.append(f"\n{name}: {df.shape}\nTop null % columns:\n{nulls.to_string()}")

for name, df in [("dim_company", dim), ("fact_pnl", pnl), ("fact_cashflow", cfl),
                 ("fact_balance_sheet", bsn), ("fact_ratios", r)]:
    df.to_csv(os.path.join(OUT_DIR, f"{name}.csv"), index=False)
with open(os.path.join(OUT_DIR, "data_quality_report.txt"), "w", encoding="utf-8") as f:
    f.write("\n".join(rep))
print("\n".join(rep))
print(f"\nDone -> {OUT_DIR}/")
