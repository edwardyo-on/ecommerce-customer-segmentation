import sqlite3
from pathlib import Path

import pandas as pd


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DATA_PATH = PROJECT_ROOT / "outputs" / "tables" / "clean_transactions.csv"
DB_PATH = PROJECT_ROOT / "database" / "ecommerce_segmentation.db"
TABLE_NAME = "online_retail"


def main() -> None:
    if not DATA_PATH.exists():
        raise FileNotFoundError(
            f"Could not find {DATA_PATH}. Run the notebook export cell first."
        )

    DB_PATH.parent.mkdir(parents=True, exist_ok=True)

    df = pd.read_csv(DATA_PATH)

    # Keep date values readable/queryable in SQLite.
    if "invoicedate" in df.columns:
        df["invoicedate"] = pd.to_datetime(df["invoicedate"], errors="coerce").dt.strftime("%Y-%m-%d %H:%M:%S")

    with sqlite3.connect(DB_PATH) as conn:
        df.to_sql(TABLE_NAME, conn, if_exists="replace", index=False)

    print("SQLite database created successfully.")
    print(f"Database file: {DB_PATH.resolve()}")
    print(f"Rows loaded: {len(df):,}")
    print(f"Table created: {TABLE_NAME}")


if __name__ == "__main__":
    main()
