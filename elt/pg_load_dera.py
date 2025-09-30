#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Load SEC DERA quarterly ZIPs from a LOCAL folder into Postgres RAW tables.

Design:
- RAW tables are a landing zone kept as TEXT; dbt handles typing/cleansing.
- Adds srcdir = 'YYYYqN' (derived from zip filename like 2019q4.zip).
- Robustness:
  * Auto-add any missing columns (e.g., 'segments') to RAW tables before insert.
  * Normalize each data row to match the header width (pad or fold extras).
- Idempotency:
  * --mode append   : default; always append rows.
  * --mode skip     : if rows exist for srcdir+table, skip loading that file/table.
  * --mode replace  : if rows exist for srcdir+table, delete them and reload.

Usage:
  python elt/pg_load_dera.py --zips-dir /absolute/path/to/dera_zips --mode replace

Environment variables (optional):
  PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD, DERA_RAW_SCHEMA
Defaults:
  PGHOST=localhost PGPORT=5432 PGDATABASE=dera PGUSER=dbt PGPASSWORD=dbt DERA_RAW_SCHEMA=raw_dera
"""

import os
import io
import zipfile
import argparse
from typing import Optional

import psycopg2
from psycopg2.extras import execute_batch


# ---- DB config from env (override via env vars as needed)
PG_HOST = os.getenv("PGHOST", "localhost")
PG_PORT = int(os.getenv("PGPORT", "5432"))
PG_DB   = os.getenv("PGDATABASE", "dera")
PG_USER = os.getenv("PGUSER", "dbt")
PG_PASS = os.getenv("PGPASSWORD", "dbt")
RAW_SCHEMA = os.getenv("DERA_RAW_SCHEMA", "raw_dera")


# Base DDL for first-time setup (kept minimal; auto-extend will add any new cols)
DDL = {
    "sub": f"""
    CREATE TABLE IF NOT EXISTS "{RAW_SCHEMA}"."sub"(
      adsh TEXT, cik TEXT, name TEXT, sic TEXT, countryba TEXT, stprba TEXT,
      cityba TEXT, zipba TEXT, bas1 TEXT, bas2 TEXT, baph TEXT,
      countryma TEXT, stprma TEXT, cityma TEXT, zipma TEXT, mas1 TEXT, mas2 TEXT,
      countryinc TEXT, stprinc TEXT, ein TEXT, former TEXT, changed TEXT, afs TEXT, wksi TEXT,
      fye TEXT, form TEXT, period TEXT, fy TEXT, fp TEXT, filed TEXT, accepted TEXT,
      prevrpt TEXT, detail TEXT, instance TEXT, nciks TEXT, aciks TEXT, srcdir TEXT
    )""",
    # include 'segments' (present in some num.txt); auto-extend still enabled for other columns
    "num": f"""
    CREATE TABLE IF NOT EXISTS "{RAW_SCHEMA}"."num"(
      adsh TEXT, tag TEXT, version TEXT, coreg TEXT, ddate TEXT,
      qtrs TEXT, uom TEXT, segments TEXT, value TEXT, footnote TEXT, srcdir TEXT
    )""",
    "tag": f"""
    CREATE TABLE IF NOT EXISTS "{RAW_SCHEMA}"."tag"(
      tag TEXT, version TEXT, custom TEXT, abstract TEXT, datatype TEXT,
      iord TEXT, crdr TEXT, tlabel TEXT, doc TEXT, srcdir TEXT
    )""",
}


# -------------------------- DB helpers --------------------------

def ensure_database():
    # Connect to postgres maintenance DB and create if missing
    conn = psycopg2.connect(f"host={PG_HOST} port={PG_PORT} dbname=postgres user={PG_USER} password={PG_PASS}")
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute(f"SELECT 1 FROM pg_database WHERE datname = %s", (PG_DB,))
        if not cur.fetchone():
            cur.execute(f'CREATE DATABASE "{PG_DB}"')
    conn.close()


def connect():
    dsn = f"host={PG_HOST} port={PG_PORT} dbname={PG_DB} user={PG_USER} password={PG_PASS}"
    return psycopg2.connect(dsn)


def ensure_schema(conn):
    with conn.cursor() as cur:
        cur.execute(f'CREATE SCHEMA IF NOT EXISTS "{RAW_SCHEMA}"')
        for ddl in DDL.values():
            cur.execute(ddl)
    conn.commit()


def get_existing_columns(conn, schema: str, table: str):
    sql = """
      select column_name
      from information_schema.columns
      where table_schema = %s and table_name = %s
      order by ordinal_position
    """
    with conn.cursor() as cur:
        cur.execute(sql, (schema, table))
        return {row[0] for row in cur.fetchall()}


def add_missing_columns(conn, schema: str, table: str, header_cols: list):
    """
    Ensure RAW table has all columns referenced in the incoming header.
    Any missing columns are added as TEXT. 'srcdir' is managed by the loader.
    """
    existing = get_existing_columns(conn, schema, table)
    missing = [c for c in header_cols if c not in existing and c != "srcdir"]
    if not missing:
        return
    with conn.cursor() as cur:
        for col in missing:
            cur.execute(f'ALTER TABLE "{schema}"."{table}" ADD COLUMN "{col}" TEXT')
    conn.commit()


def srcdir_has_rows(conn, table: str, srcdir: str) -> bool:
    sql = f'SELECT 1 FROM "{RAW_SCHEMA}"."{table}" WHERE srcdir = %s LIMIT 1'
    with conn.cursor() as cur:
        cur.execute(sql, (srcdir,))
        return cur.fetchone() is not None


def delete_srcdir(conn, table: str, srcdir: str) -> None:
    sql = f'DELETE FROM "{RAW_SCHEMA}"."{table}" WHERE srcdir = %s'
    with conn.cursor() as cur:
        cur.execute(sql, (srcdir,))
    conn.commit()


# ------------------------ Row handling -------------------------

def normalize_row(parts, expected_no_srcdir):
    """
    Ensure len(row) == expected_no_srcdir + 1 (for srcdir appended later).
    If too short -> pad with ''.
    If too long  -> collapse extras into the last field (usually 'footnote').
    """
    n = len(parts)
    target = expected_no_srcdir
    if n == target:
        return parts
    if n < target:
        return parts + [''] * (target - n)
    # n > target: fold extras into the final logical column
    head = parts[:target-1]
    tail_merged = "\t".join(parts[target-1:])  # keep original tab info together
    return head + [tail_merged]


def insert_rows(conn, table: str, header: list, rows: list):
    cols = ",".join(f'"{c}"' for c in header)
    placeholders = ",".join(["%s"] * len(header))
    sql = f'INSERT INTO "{RAW_SCHEMA}"."{table}" ({cols}) VALUES ({placeholders})'
    with conn.cursor() as cur:
        execute_batch(cur, sql, rows, page_size=5000)


def load_txt_streaming(conn, table: str, srcdir: str, zip_member_file):
    # Stream lines to avoid loading the entire file into memory
    text = io.TextIOWrapper(zip_member_file, encoding="utf-8", errors="replace", newline="")
    header_line = text.readline()
    if not header_line:
        return  # empty file
    header_line = header_line.lstrip("\ufeff")          # strip possible BOM
    header = header_line.rstrip("\r\n").split("\t")
    header.append("srcdir")

    # Ensure RAW table has every incoming column (robust to schema changes)
    add_missing_columns(conn, RAW_SCHEMA, table, header)

    expected_no_srcdir = len(header) - 1
    batch, total = [], 0
    for line in text:
        line = line.rstrip("\r\n")
        if not line:
            continue
        parts = line.split("\t")
        parts = normalize_row(parts, expected_no_srcdir)
        parts.append(srcdir)  # now total length equals len(header)
        batch.append(parts)
        if len(batch) >= 5000:
            insert_rows(conn, table, header, batch)
            total += len(batch)
            batch.clear()
    if batch:
        insert_rows(conn, table, header, batch)
        total += len(batch)
    print(f"   inserted {total:,} rows into {RAW_SCHEMA}.{table}")


# ------------------------ ZIP processing -----------------------

def process_zip_file(conn, zip_path: str, mode: str):
    if not zip_path.lower().endswith(".zip"):
        return
    srcdir = os.path.basename(zip_path).split(".")[0]  # e.g., 2019q4
    with zipfile.ZipFile(zip_path, mode="r") as z:
        # Load in a stable order
        for member in ("sub.txt", "num.txt", "tag.txt"):
            if member not in z.namelist():
                print(f"   WARN: {member} not found in {zip_path}")
                continue
            table = member.split(".")[0]

            # Idempotency handling
            if mode == "skip":
                if srcdir_has_rows(conn, table, srcdir):
                    print(f"   skip: {table} ({srcdir}) already loaded")
                    continue
            elif mode == "replace":
                if srcdir_has_rows(conn, table, srcdir):
                    print(f"   replace: deleting {table} rows for srcdir={srcdir}")
                    delete_srcdir(conn, table, srcdir)

            print(f"→ {os.path.basename(zip_path)} :: loading {member} (srcdir={srcdir})")
            with z.open(member) as fh:
                load_txt_streaming(conn, table, srcdir, fh)


# ----------------------------- main ----------------------------

def main():
    ap = argparse.ArgumentParser(description="Load local SEC DERA zip files into Postgres RAW tables")
    ap.add_argument("--zips-dir", required=True, help="Local directory containing DERA .zip files (e.g., ~/dera_zips)")
    ap.add_argument("--mode", choices=["append", "skip", "replace"], default="append",
                    help="append=default; skip=do nothing if srcdir exists; replace=delete rows for srcdir then load")
    args = ap.parse_args()

    # Normalize path (handles '~' and relative paths)
    zips_dir = os.path.abspath(os.path.expanduser(args.zips_dir))
    if not os.path.isdir(zips_dir):
        raise SystemExit(f"ERROR: directory not found: {zips_dir}")

    # ✅ Ensure DB exists before connecting
    ensure_database()

    conn = connect()
    ensure_schema(conn)

    zip_files = sorted(f for f in os.listdir(zips_dir) if f.lower().endswith(".zip"))
    if not zip_files:
        raise SystemExit(f"No .zip files found in: {zips_dir}")

    for fname in zip_files:
        process_zip_file(conn, os.path.join(zips_dir, fname), args.mode)

    conn.commit()
    conn.close()
    print("✅ Completed RAW load into Postgres.")


if __name__ == "__main__":
    main()