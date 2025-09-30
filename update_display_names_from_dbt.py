#!/usr/bin/env python3
"""
Update OpenMetadata displayName from dbt manifest.json

Supports:
- models
- seeds
- sources

Requirements:
  - Python 3.9+
  - pip install requests
"""

import json
import os
import sys
import argparse
from urllib.parse import quote
from typing import Dict, Any, Optional, List

try:
    import requests
except ImportError:
    print("This script requires the 'requests' package. Install with: pip install requests", file=sys.stderr)
    sys.exit(1)

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Patch OpenMetadata displayName from dbt manifest.json")
    p.add_argument("--host", default=os.getenv("OM_HOST", "http://localhost:8585/api"))
    p.add_argument("--token", default=os.getenv("OPENMETADATA_JWT_TOKEN", ""))
    p.add_argument("--service", default=os.getenv("OM_SERVICE_NAME", ""))
    p.add_argument("--manifest", default=os.getenv("DBT_MANIFEST_PATH", "./target/manifest.json"))
    p.add_argument("--dry-run", action="store_true")
    return p.parse_args()

def headers(token: str, content_type: Optional[str] = None) -> Dict[str, str]:
    h = {}
    if token:
        h["Authorization"] = f"Bearer {token}"
    if content_type:
        h["Content-Type"] = content_type
    return h

def load_manifest(path: str) -> Dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def get_table_by_fqn(base: str, token: str, fqn: str) -> Optional[Dict[str, Any]]:
    url = f"{base}/v1/tables/name/{quote(fqn, safe='')}"
    params = {"fields": "columns,displayName"}
    resp = requests.get(url, headers=headers(token), params=params, timeout=20)
    if resp.status_code == 200:
        return resp.json()
    else:
        print(f"[WARN] Table not found or error {resp.status_code} for FQN={fqn} -> {resp.text}", file=sys.stderr)
        return None

def patch_table(base: str, token: str, table_id: str, patch_ops: List[Dict[str, Any]]) -> bool:
    if not patch_ops:
        return True
    url = f"{base}/v1/tables/{table_id}"
    resp = requests.patch(
        url,
        headers=headers(token, "application/json-patch+json"),
        data=json.dumps(patch_ops),
        timeout=30
    )
    if resp.status_code in (200, 201):
        return True
    print(f"[ERROR] Patch failed ({resp.status_code}): {resp.text}", file=sys.stderr)
    return False

def safe_get(d: Dict[str, Any], path: List[str], default=None):
    cur = d
    for key in path:
        if not isinstance(cur, dict) or key not in cur:
            return default
        cur = cur[key]
    return cur

def process_node(node: Dict[str, Any], resource_type: str, args: argparse.Namespace) -> int:
    database = node.get("database")
    schema = node.get("schema")
    name = node.get("alias") or node.get("name")

    if not (database and schema and name):
        print(f"[SKIP] Missing database/schema/name for {resource_type} node")
        return 0

    fqn = f"{args.service}.{database}.{schema}.{name}"

    model_display = safe_get(node, ["config", "meta", "openmetadata", "displayName"])
    columns_meta = node.get("columns", {}) or {}

    table = get_table_by_fqn(args.host, args.token, fqn)
    if not table:
        return 0

    table_id = table.get("id")
    table_display_current = table.get("displayName")
    table_columns = table.get("columns") or []

    patch_ops: List[Dict[str, Any]] = []

    if model_display and model_display != table_display_current:
        patch_ops.append({"op": "add", "path": "/displayName", "value": model_display})

    name_to_index = { (c.get("name") or ""): idx for idx, c in enumerate(table_columns) }

    for col_name, col_obj in columns_meta.items():
        col_display = safe_get(col_obj, ["config", "meta", "openmetadata", "displayName"])
        if col_display is None:
            col_display = safe_get(col_obj, ["meta", "openmetadata", "displayName"])
        if not col_display:
            continue

        idx = name_to_index.get(col_name)
        if idx is None:
            print(f"[WARN] Column '{col_name}' not found on OM table {fqn}; skipping column displayName", file=sys.stderr)
            continue

        current_display = table_columns[idx].get("displayName")
        if current_display != col_display:
            patch_ops.append({
                "op": "add",
                "path": f"/columns/{idx}/displayName",
                "value": col_display
            })

    if not patch_ops:
        return 0

    if args.dry_run:
        print(f"[DRY-RUN] Would PATCH {fqn} with ops:\n{json.dumps(patch_ops, indent=2)}")
        return len(patch_ops)

    if patch_table(args.host, args.token, table_id, patch_ops):
        print(f"[OK] Patched {fqn}: {len(patch_ops)} change(s)")
        return len(patch_ops)
    else:
        print(f"[FAIL] Patch failed for {fqn}", file=sys.stderr)
        return 0

def main():
    args = parse_args()
    if not args.service:
        print("ERROR: --service (or OM_SERVICE_NAME env) is required.", file=sys.stderr)
        sys.exit(2)

    try:
        manifest = load_manifest(args.manifest)
    except FileNotFoundError:
        print(f"ERROR: manifest.json not found at {args.manifest}", file=sys.stderr)
        sys.exit(2)

    all_nodes = {}
    all_nodes.update(manifest.get("nodes", {}))
    all_nodes.update(manifest.get("sources", {}))

    total_ops = 0
    for key, node in all_nodes.items():
        resource_type = node.get("resource_type")
        if resource_type not in ("model", "seed", "source"):
            continue
        total_ops += process_node(node, resource_type, args)

    print(f"\nDone. Total displayName updates applied: {total_ops}")

if __name__ == "__main__":
    main()
