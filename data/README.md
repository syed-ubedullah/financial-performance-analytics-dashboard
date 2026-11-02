# Data

The raw data is **not included** in this repository. Download it from Kaggle:

**Dataset:** [pacificrm/financial-sheets](https://www.kaggle.com/datasets/pacificrm/financial-sheets) (Indian listed companies on BSE and NSE)

Check the license on the dataset page before reusing the data.

## Files used by this project (8 of 11)

| File | Content used |
|---|---|
| `Annual_P_L_1_final.csv` | Sales, operating profit, EBIT, interest, tax, net profit, EPS (latest and preceding year); industry, market cap, price |
| `Balance_Sheet_final.csv` | Debt, equity capital, reserves, total assets, current assets and liabilities, cash |
| `cash_flow_statments_final.csv` | Operating, investing, financing and free cash flow (two years) |
| `ratios_1_final.csv`, `ratios_2_final.csv` | ROE, ROA, ROIC, debt-to-equity, P/E, P/B, shareholding, 5-year average ROE |
| `other_metrics_final.csv` | Current ratio, interest coverage, Altman Z-score, EV/EBITDA |
| `price_final.csv`, `t1_prices.csv` | 1, 3 and 5-year price returns, T-1 price |

Not used: `Annual_P_L_2_final.csv`, `Quarter_P_L_1_final.csv`, `Quarter_P_L_2_final.csv`.

## Where to put the files

Unzip the CSVs into `data/raw/` (this folder is ignored by Git) and point `IN_DIR` in `python/01_clean_and_reshape.py` to it.

## Key facts about the data

- 4,668 companies across 107 industries; every file shares a unique `join_key`
- Wide format: each metric appears as "last year" and "preceding year" columns
- Only two annual periods are available (FY2024 and FY2023)
