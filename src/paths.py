"""Project paths, resolved from this file's location so scripts work from any current directory."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"                    # generated input files (generator.py)
SQL = ROOT / "sql"
DB_DIR = ROOT / "db"                    # SQLite files (generated, not versioned)
REJECTS_DIR = ROOT / "rejects"          # rows/lines refused by the loaders (generated, not versioned)

DB = DB_DIR / "marketplace.db"
SCHEMA = SQL / "schema.sql"
