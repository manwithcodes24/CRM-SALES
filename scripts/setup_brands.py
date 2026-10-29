"""One CRM for two brands: Newral (tech agency) and Synappses (white-label LMS).

Adds a Brand field to leads and deals, shows it on the CRM's lead/deal forms,
and adds the lead sources the sales tools use. Idempotent: safe to re-run.

Run inside the backend container, from the sites folder:
    docker compose exec -T backend bash -c 'cd sites && ../env/bin/python - SITE' < scripts/setup_brands.py
"""

import json
import sys

import frappe

BRANDS = ["Newral", "Synappses"]
SOURCES = ["LinkedIn", "WhatsApp", "Harvey (cold email)", "Website signup", "Brochure QR", "Referral"]


def add_brand_field(doctype):
    if frappe.db.exists("Custom Field", {"dt": doctype, "fieldname": "brand"}):
        return
    frappe.get_doc(
        {
            "doctype": "Custom Field",
            "dt": doctype,
            "fieldname": "brand",
            "label": "Brand",
            "fieldtype": "Select",
            "options": "\n" + "\n".join(BRANDS),
            "insert_after": "status",
            "in_list_view": 1,
            "in_standard_filter": 1,
            "description": "Newral = tech agency services. Synappses = white-label LMS.",
        }
    ).insert()


def show_on_layout(doctype, layout_type):
    """Put Brand first on the form: next to Status if the layout has it, else at the top."""
    name = f"{doctype}-{layout_type}"
    if not frappe.db.exists("CRM Fields Layout", name):
        return
    doc = frappe.get_doc("CRM Fields Layout", name)
    sections = json.loads(doc.layout or "[]")
    columns = [c for s in sections for c in s.get("columns", [])]
    if not columns or any("brand" in c.get("fields", []) for c in columns):
        return
    target = next((c for c in columns if "status" in c.get("fields", [])), columns[0])
    target["fields"].insert(0, "brand")
    doc.layout = json.dumps(sections)
    doc.save()


def add_sources():
    for source in SOURCES:
        if not frappe.db.exists("CRM Lead Source", source):
            frappe.get_doc({"doctype": "CRM Lead Source", "source_name": source}).insert()


frappe.init(site=sys.argv[1], sites_path=".")
frappe.connect()
try:
    for dt in ("CRM Lead", "CRM Deal"):
        add_brand_field(dt)
        show_on_layout(dt, "Quick Entry")
        show_on_layout(dt, "Side Panel")
    add_sources()
    frappe.db.commit()
    print(f"{sys.argv[1]}: Brand field and lead sources ready")
finally:
    frappe.destroy()
