#!/usr/bin/env python3
import os
import re
import sys
import json
import html
import argparse
import logging
import traceback
from typing import Dict, Any, List, Optional
from dotenv import load_dotenv
from metadata.ingestion.ometa.ometa_api import OpenMetadata, OpenMetadataConnection
from metadata.generated.schema.entity.data.glossary import Glossary
from metadata.generated.schema.entity.data.glossaryTerm import GlossaryTerm
from metadata.generated.schema.api.data.createGlossary import CreateGlossaryRequest
from metadata.generated.schema.api.data.createGlossaryTerm import CreateGlossaryTermRequest

LOG = logging.getLogger("glossary_upsert")

# -----------------------
# Logging
# -----------------------
def setup_logging(verbose: bool):
    level = logging.DEBUG if verbose else logging.INFO
    handler = logging.StreamHandler(stream=sys.stdout)
    handler.setFormatter(logging.Formatter("%(asctime)s [%(levelname)s] %(message)s"))
    LOG.setLevel(level)
    LOG.handlers.clear()
    LOG.addHandler(handler)

# -----------------------
# Utilities
# -----------------------
def slugify(value: str) -> str:
    if not value:
        return ""
    v = value.strip().lower()
    v = re.sub(r"[^a-z0-9]+", "_", v)
    v = re.sub(r"_+", "_", v)
    return v.strip("_")

def fqn_str(v) -> str:
    if isinstance(v, str):
        return v
    if hasattr(v, "root"):
        return getattr(v, "root")
    if hasattr(v, "__root__"):
        return getattr(v, "__root__")
    s = str(v)
    if s.startswith("root='") and s.endswith("'"):
        return s[6:-1]
    return s

def clean(s: Optional[str]) -> str:
    return html.unescape(s or "").strip()

def expand_path(p: str) -> str:
    return os.path.abspath(os.path.expanduser(p))

def load_terms(source: str) -> List[Dict[str, Any]]:
    candidate = expand_path(source)
    if os.path.exists(candidate):
        with open(candidate, "r", encoding="utf-8") as f:
            data = json.load(f)
    else:
        data = json.loads(source)
    if not isinstance(data, list):
        raise ValueError("Input JSON must be an array of term objects.")
    return data
load_dotenv()
# -----------------------
# OpenMetadata client
# -----------------------
def get_om_client() -> OpenMetadata:
    host_port = os.getenv("OPENMETADATA_HOST_PORT", "http://localhost:8585/api").rstrip("/")
    jwt = os.getenv("OPENMETADATA_JWT_TOKEN")
    if not jwt:
        raise EnvironmentError("OPENMETADATA_JWT_TOKEN env var is not set.")
    connection = OpenMetadataConnection(
        hostPort=host_port,
        authProvider="openmetadata",
        securityConfig={"jwtToken": jwt},
    )
    return OpenMetadata(connection)

# -----------------------
# Glossary ensure
# -----------------------
def ensure_glossary(metadata: OpenMetadata, glossary_display_name: str, dry_run: bool=False) -> Glossary:
    glossary_name = slugify(glossary_display_name)
    existing = metadata.get_by_name(entity=Glossary, fqn=glossary_name)
    if existing:
        LOG.info(f"[✓] Glossary exists: {existing.displayName} (FQN={fqn_str(existing.fullyQualifiedName)})")
        return existing

    if dry_run:
        LOG.info(f"[DRY RUN] Would create Glossary: {glossary_display_name}")
        class _G: pass
        g = _G()
        g.displayName = glossary_display_name
        g.name = glossary_name
        g.fullyQualifiedName = glossary_name
        return g

    payload = CreateGlossaryRequest(
        name=glossary_name,
        displayName=glossary_display_name,
        description=f"Glossary for {glossary_display_name}",
    )
    created = metadata.create_or_update(payload)
    LOG.info(f"[+] Created Glossary: {created.displayName} (FQN={fqn_str(created.fullyQualifiedName)})")
    return created

# -----------------------
# Term ensure (flat)
# -----------------------
def ensure_term(metadata: OpenMetadata, glossary: Glossary, term_obj: Dict[str, Any], dry_run=False):
    for k in ("tag", "label", "definition"):
        if k not in term_obj or not str(term_obj[k]).strip():
            raise ValueError(f"Term missing required field '{k}': {term_obj}")

    term_name = slugify(term_obj["tag"])
    glossary_fqn = fqn_str(getattr(glossary, "fullyQualifiedName", getattr(glossary, "name", "")))
    term_fqn = f"{glossary_fqn}.{term_name}"

    existing = metadata.get_by_name(entity=GlossaryTerm, fqn=term_fqn)

    payload = CreateGlossaryTermRequest(
        name=term_name,
        displayName=term_obj["label"],
        description=f"{term_obj['definition']} XBRL Tag: {term_obj['tag']}",
        glossary=glossary_fqn,
        parent=None,
    )

    if dry_run:
        action = "Update" if existing else "Create"
        LOG.info(f"[DRY RUN] Would {action} Term: {term_obj['label']} (FQN={term_fqn})")
        return None

    updated = metadata.create_or_update(payload)
    if existing:
        LOG.info(f"[↻] Updated Term: {updated.displayName} (FQN={term_fqn})")
    else:
        LOG.info(f"[+] Created Term: {updated.displayName} (FQN={term_fqn})")
    return updated

# -----------------------
# Executor
# -----------------------
def upsert_from_terms_json(terms: List[Dict[str, Any]], dry_run=False):
    metadata = get_om_client()
    glossaries_cache = {}
    count = 0

    for raw in terms:
        count += 1
        glossary_display = clean(raw.get("glossary", ""))
        label = clean(raw.get("label"))
        tag = clean(raw.get("tag"))
        definition = clean(raw.get("definition"))

        if not glossary_display:
            raise ValueError(f"Missing 'glossary' in term: {raw}")

        if glossary_display not in glossaries_cache:
            glossaries_cache[glossary_display] = ensure_glossary(metadata, glossary_display, dry_run=dry_run)
        glossary = glossaries_cache[glossary_display]

        term_obj = {"tag": tag, "label": label, "definition": definition}
        ensure_term(metadata, glossary, term_obj, dry_run=dry_run)

    LOG.info(f"✅ Completed upsert. Processed {count} items.")

# -----------------------
# CLI
# -----------------------
def main():
    parser = argparse.ArgumentParser(description="Upsert glossary terms into OpenMetadata (flat structure).")
    parser.add_argument("source", help="Path to JSON file or JSON string")
    parser.add_argument("--dry-run", action="store_true", help="Preview changes without applying them")
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose logs")
    args = parser.parse_args()

    setup_logging(args.verbose)
    LOG.info("——— OpenMetadata Glossary Upsert (Flat) ———")
    LOG.info(f"Source: {args.source}")
    LOG.info(f"Dry-run: {args.dry_run}")

    terms_list = load_terms(args.source)
    LOG.info(f"Loaded {len(terms_list)} term records.")

    upsert_from_terms_json(terms_list, dry_run=args.dry_run)
    LOG.info("——— Done ———")

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        LOG.error("❌ Failed: %s", e)
        LOG.debug("Traceback:\n%s", traceback.format_exc())
        sys.exit(1)