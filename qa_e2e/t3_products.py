"""E2E batch 3 — Products CRUD, media uploads, ownership/IDOR, draft, video. Real HTTP."""
import os, time
from qa import Client, record, S, B, django_setup

PWD = "ChangeMe123!"
SUP = "supplier@marche-cm.local"
WHO = "wholesaler@marche-cm.local"
BUY = "buyer@marche-cm.local"


def f(n):
    return os.path.join("media", n)


def base_supplier_fields(title):
    return {
        "title": title, "description": "Produit de test QA, description complete.",
        "brand": "QA Brand", "category_name": "QA Catégorie",
        "weight_kg": "2.5", "min_order_qty": "10", "max_order_qty": "100",
        "price_for_min_qty": "5000", "price_for_max_qty": "4500",
    }


def main():
    sup = Client("supplier"); sup.login(SUP, PWD)
    who = Client("wholesaler"); who.login(WHO, PWD)
    buy = Client("buyer"); buy.login(BUY, PWD)
    created = {}

    # --- T3.1 Buyer cannot create product ---
    with open(f("product1.jpg"), "rb") as fp:
        r = buy.req("POST", "/api/products/", files={"image": ("p.jpg", fp, "image/jpeg")},
                    data=base_supplier_fields("Buyer tries"), note="buyer create product")
    record("T3.1", "Acheteur ne peut pas publier un produit", "critical",
           S(r) == 403, "403 (réservé fournisseur/grossiste)", f"status={S(r)} body={B(r,140)}",
           endpoint="POST /api/products/", be_file="apps/catalog/views.py:ProductViewSet.perform_create")

    # --- T3.2 Supplier create product with real image ---
    with open(f("product1.jpg"), "rb") as fp:
        r = sup.req("POST", "/api/products/", files={"image": ("p1.jpg", fp, "image/jpeg")},
                    data=base_supplier_fields(f"Sac de riz QA {int(time.time())}"), note="supplier create")
    ok = S(r) == 201
    pid = r.json().get("id") if ok else None
    img_url = r.json().get("image") if ok else None
    created["sup_product"] = pid
    record("T3.2", "Fournisseur crée un produit avec image réelle", "critical",
           ok and pid is not None, "201 + id + image stockée",
           f"status={S(r)} id={pid} image={img_url} body={B(r,120)}",
           endpoint="POST /api/products/")

    # --- T3.3 image served (media URL reachable) ---
    if img_url:
        full = img_url if img_url.startswith("http") else ("http://127.0.0.1:8000" + img_url)
        r = sup.req("GET", full, auth=False, note="fetch product image")
        record("T3.3", "Image produit servie/accessible (URL générée)", "major",
               S(r) == 200 and (r.headers.get("Content-Type","").startswith("image") if r is not None else False),
               "200 + Content-Type image/*",
               f"status={S(r)} ctype={r.headers.get('Content-Type') if r is not None else 'NA'}",
               endpoint="GET <media image url>")

    # --- T3.4 Wholesaler create product ---
    with open(f("product2.png"), "rb") as fp:
        r = who.req("POST", "/api/products/", files={"image": ("p2.png", fp, "image/png")},
                    data={"title": f"Carton savon QA {int(time.time())}",
                          "description": "Lot grossiste QA.", "brand": "QA Whole",
                          "category_name": "QA Catégorie", "weight_kg": "5",
                          "available_qty": "50", "unit_price": "3000"}, note="wholesaler create")
    okw = S(r) == 201
    created["who_product"] = r.json().get("id") if okw else None
    record("T3.4", "Grossiste crée un produit (available_qty/unit_price)", "critical",
           okw, "201", f"status={S(r)} body={B(r,150)}", endpoint="POST /api/products/")

    # --- T3.5 Missing category -> 400 ---
    fields = base_supplier_fields("Sans categorie"); fields.pop("category_name")
    r = sup.req("POST", "/api/products/", json_body=fields, note="missing category")
    record("T3.5", "Création produit sans catégorie rejetée", "minor",
           S(r) == 400, "400", f"status={S(r)} body={B(r,140)}", endpoint="POST /api/products/")

    # --- T3.6 min>max -> 400 ---
    fields = base_supplier_fields("Qty invalide"); fields["min_order_qty"]="100"; fields["max_order_qty"]="10"
    r = sup.req("POST", "/api/products/", json_body=fields, note="min>max")
    record("T3.6", "Création produit min_qty>max_qty rejetée", "minor",
           S(r) == 400, "400", f"status={S(r)} body={B(r,140)}", endpoint="POST /api/products/")

    # --- T3.7 Oversized image (16MB) — distinguishes middleware(413) vs serializer(400) ---
    with open(f("big.jpg"), "rb") as fp:
        r = sup.req("POST", "/api/products/", files={"image": ("big.jpg", fp, "image/jpeg")},
                    data=base_supplier_fields("Image lourde"), note="oversized image")
    st = S(r)
    # Either rejection is acceptable for the user; we record which layer caught it.
    rejected = st in (400, 413)
    layer = "middleware(413)" if st == 413 else ("serializer(400)" if st == 400 else f"non rejeté ({st})")
    record("T3.7", "Image >5MB rejetée (et par quelle couche)", "major",
           rejected, "rejet (413 middleware OU 400 serializer)",
           f"status={st} -> {layer}. NB: /api/products/ absent de _UPLOAD_PATH_PREFIXES (qui liste /api/catalog/ inexistant) => le cap 5MB middleware ne s'applique pas, c'est le serializer qui rejette.",
           endpoint="POST /api/products/",
           be_file="config/middleware.py:172 _UPLOAD_PATH_PREFIXES (/api/catalog/ != route réelle /api/products/)")

    # --- T3.8 List public (no auth), only active ---
    r = Client("anon").req("GET", "/api/products/", auth=False, note="public list")
    body = r.json() if S(r) == 200 else {}
    count = body.get("count") if isinstance(body, dict) else (len(body) if isinstance(body, list) else None)
    record("T3.8", "Liste produits publique accessible sans auth", "major",
           S(r) == 200, "200 + liste", f"status={S(r)} count={count}", endpoint="GET /api/products/")

    # --- T3.9 mine endpoint ---
    r = sup.req("GET", "/api/products/mine/", note="mine")
    record("T3.9", "Endpoint /products/mine/ renvoie les produits du vendeur", "minor",
           S(r) == 200, "200", f"status={S(r)}", endpoint="GET /api/products/mine/")

    # --- T3.10 IDOR update: wholesaler edits supplier's product ---
    if created.get("sup_product"):
        r = who.req("PATCH", f"/api/products/{created['sup_product']}/",
                    json_body={"title": "HACKED BY OTHER SELLER"}, note="IDOR update")
        record("T3.10", "IDOR: un vendeur ne peut pas modifier le produit d'un autre", "critical",
               S(r) in (403, 404), "403/404",
               f"status={S(r)} body={B(r,120)}", endpoint="PATCH /api/products/{id}/",
               be_file="apps/catalog/views.py:ProductViewSet.perform_update")

        # --- T3.11 IDOR delete ---
        r = who.req("DELETE", f"/api/products/{created['sup_product']}/", note="IDOR delete")
        record("T3.11", "IDOR: un vendeur ne peut pas supprimer le produit d'un autre", "critical",
               S(r) in (403, 404), "403/404", f"status={S(r)}", endpoint="DELETE /api/products/{id}/")

    # --- T3.12 publish-video with real mp4 ---
    with open(f("clip.mp4"), "rb") as fp:
        r = sup.req("POST", "/api/products/publish-video/",
                    files={"video": ("clip.mp4", fp, "video/mp4")},
                    data={"description": "Démo produit en vidéo QA.", "tags": "demo,qa,promo", "weight_kg": "1.2"},
                    note="publish video")
    okv = S(r) == 201
    vid_url = r.json().get("video") if okv else None
    record("T3.12", "Publication vidéo (mp4 réel + description + tags + poids)", "critical",
           okv, "201 + vidéo stockée", f"status={S(r)} video={vid_url} body={B(r,120)}",
           endpoint="POST /api/products/publish-video/", be_file="apps/catalog/views.py:publish_video")

    # --- T3.13 publish-video missing description -> 400 ---
    with open(f("clip.mp4"), "rb") as fp:
        r = sup.req("POST", "/api/products/publish-video/",
                    files={"video": ("clip.mp4", fp, "video/mp4")},
                    data={"tags": "x", "weight_kg": "1"}, note="video no desc")
    record("T3.13", "Publication vidéo sans description rejetée", "minor",
           S(r) == 400, "400", f"status={S(r)} body={B(r,120)}", endpoint="POST /api/products/publish-video/")

    # --- T3.14 Draft (is_active=false) hidden from public list, owner can flip ---
    with open(f("product2.png"), "rb") as fp:
        r = sup.req("POST", "/api/products/", files={"image": ("d.png", fp, "image/png")},
                    data={**base_supplier_fields(f"Brouillon QA {int(time.time())}"), "is_active": "false"},
                    note="create draft")
    draft_id = r.json().get("id") if S(r) == 201 else None
    draft_active = r.json().get("is_active") if S(r) == 201 else None
    # check it's NOT in public list
    in_public = False
    if draft_id:
        rl = Client("anon2").req("GET", f"/api/products/{draft_id}/", auth=False, note="get draft public")
        in_public = S(rl) == 200
    record("T3.14", "Produit brouillon (is_active=false) masqué du public", "major",
           draft_id is not None and draft_active is False and not in_public,
           "is_active=false + invisible publiquement (404)",
           f"id={draft_id} is_active={draft_active} public_retrieve={S(rl) if draft_id else 'NA'}",
           endpoint="POST /api/products/ (is_active=false)")

    return created


if __name__ == "__main__":
    out = main()
    print("CREATED:", out)
