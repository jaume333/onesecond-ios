"""Publicar (versión aprobada) o enviar a revisión una versión de One Second en App Store Connect."""
import json, os, sys, time
import jwt, requests

APP, ACCION, VER = os.environ["APP"], os.environ["ACCION"], os.environ["VERSION"]
API = "https://api.appstoreconnect.apple.com/v1"

def cab():
    t = jwt.encode({"iss": os.environ["ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 900, "aud": "appstoreconnect-v1"},
                   os.environ["P8"], algorithm="ES256", headers={"kid": os.environ["KEY_ID"], "typ": "JWT"})
    return {"Authorization": "Bearer " + t, "Content-Type": "application/json"}

def pedir(metodo, ruta, cuerpo=None, ok=(200, 201, 204)):
    r = requests.request(metodo, API + ruta, headers=cab(), data=json.dumps(cuerpo) if cuerpo else None)
    if r.status_code not in ok:
        print("ERROR", metodo, ruta, r.status_code, r.text[:2000]); sys.exit(1)
    return r.json() if r.text else {}

def version():
    for v in pedir("GET", f"/apps/{APP}/appStoreVersions?filter[platform]=IOS&limit=20")["data"]:
        if v["attributes"]["versionString"] == VER:
            return v
    return None

NOVEDADES = {
    "es": "One Second Rally Classics pasa a llamarse One Second Legends, con logo y etiqueta nuevos. La clasificación (los 25 primeros) aparece justo debajo de EMITIR y PARAR. Los enlaces llevan a la nueva web onesecond.es/legends. Pequeñas mejoras.",
    "ca": "One Second Rally Classics passa a dir-se One Second Legends, amb logo i etiqueta nous. La classificació (els 25 primers) apareix just sota EMETRE i ATURAR. Els enllaços porten al nou web onesecond.es/legends. Petites millores.",
    "en": "One Second Rally Classics is now One Second Legends, with a new logo and label. The standings (top 25) now appear right below START and STOP. Links take you to the new onesecond.es/legends site. Small improvements.",
}

def arreglar01(v):
    """Sustituye la 1ª captura (subida dañada en la 1.59) por la buena de la rama «capturas» (solo en versiones editables)."""
    # Sustituye la 1ª captura (subida dañada) por la buena de la rama «capturas». Sube primero la nueva,
    # luego borra la mala y la deja en primer lugar.
    import hashlib
    URL = "https://raw.githubusercontent.com/jaume333/onesecond-ios/capturas/01_iphone.png"
    datos = requests.get(URL, timeout=60).content
    md5 = hashlib.md5(datos).hexdigest(); print("ARCHIVO", len(datos), md5)
    if md5 != "e5a2c908ffb44a69ea09c10e16a52d43": print("ERROR el archivo no es el esperado"); return False
    loc = [l for l in pedir("GET", f"/appStoreVersions/{v['id']}/appStoreVersionLocalizations")["data"] if l["attributes"]["locale"] == "es-ES"][0]
    ss = [x for x in pedir("GET", f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"] if x["attributes"]["screenshotDisplayType"] == "APP_IPHONE_67"][0]
    antes = pedir("GET", f"/appScreenshotSets/{ss['id']}/appScreenshots?limit=20")["data"]
    mala = [c for c in antes if c["attributes"]["fileName"] == "01_iphone.png" and c["attributes"]["fileSize"] < 500000]
    if not mala: print("ERROR no encuentro la captura mala"); return False
    res = pedir("POST", "/appScreenshots", {"data": {"type": "appScreenshots", "attributes": {"fileName": "01_iphone.png", "fileSize": len(datos)},
                 "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": ss["id"]}}}}})["data"]
    for op in res["attributes"]["uploadOperations"]:
        h = {x["name"]: x["value"] for x in op["requestHeaders"]}
        r = requests.request(op["method"], op["url"], headers=h, data=datos[op["offset"]:op["offset"] + op["length"]], timeout=120)
        if r.status_code >= 300: print("ERROR subida", r.status_code, r.text[:500]); return False
    pedir("PATCH", f"/appScreenshots/{res['id']}", {"data": {"type": "appScreenshots", "id": res["id"], "attributes": {"uploaded": True, "sourceFileChecksum": md5}}})
    for i in range(30):
        a = pedir("GET", f"/appScreenshots/{res['id']}")["data"]["attributes"]; st = (a.get("assetDeliveryState") or {}).get("state")
        print("ESTADO", st)
        if st == "COMPLETE": break
        if st == "FAILED": print("ERROR", a.get("assetDeliveryState")); return False
        time.sleep(5)
    else:
        print("ERROR no terminó de procesarse"); return False
    for c in mala: pedir("DELETE", f"/appScreenshots/{c['id']}"); print("BORRADA", c["id"])
    resto = [c["id"] for c in antes if c not in mala]
    pedir("PATCH", f"/appScreenshotSets/{ss['id']}/relationships/appScreenshots", {"data": [{"type": "appScreenshots", "id": i} for i in [res["id"]] + resto]})
    for sc in pedir("GET", f"/appScreenshotSets/{ss['id']}/appScreenshots?limit=20")["data"]:
        a = sc["attributes"]; print("    CAP", a.get("fileName"), a.get("fileSize"), (a.get("assetDeliveryState") or {}).get("state"))
    return True

def poner_capturas(v, rama="capturas", n=6):   # 1.64: la rama «capturas» (la última que hace la ficha), no la de la 1.60
    """Cambia todas las capturas de iPhone (es-ES, 6,9") de la versión por 01..06_iphone.png de la rama indicada."""
    import hashlib
    loc = [l for l in pedir("GET", f"/appStoreVersions/{v['id']}/appStoreVersionLocalizations")["data"] if l["attributes"]["locale"] == "es-ES"][0]
    ss = [x for x in pedir("GET", f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"] if x["attributes"]["screenshotDisplayType"] == "APP_IPHONE_67"][0]
    antes = [c["id"] for c in pedir("GET", f"/appScreenshotSets/{ss['id']}/appScreenshots?limit=20")["data"]]
    # comprobar antes que las nuevas se pueden descargar y no están vacías
    datos_todos = {}
    for i in range(1, n + 1):
        nom = f"{i:02d}_iphone.png"
        d = requests.get(f"https://raw.githubusercontent.com/jaume333/onesecond-ios/{rama}/{nom}", timeout=60).content
        if len(d) < 100000: print("ERROR captura sospechosa", nom, len(d)); return False
        datos_todos[nom] = d
    for i in antes: pedir("DELETE", f"/appScreenshots/{i}")   # máximo 10 por juego: primero se quitan las viejas
    antes = []
    nuevas = []
    for i in range(1, n + 1):
        nom = f"{i:02d}_iphone.png"
        datos = datos_todos[nom]
        md5 = hashlib.md5(datos).hexdigest()
        res = pedir("POST", "/appScreenshots", {"data": {"type": "appScreenshots", "attributes": {"fileName": nom, "fileSize": len(datos)},
                     "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": ss["id"]}}}}})["data"]
        for op in res["attributes"]["uploadOperations"]:
            h = {x["name"]: x["value"] for x in op["requestHeaders"]}
            r = requests.request(op["method"], op["url"], headers=h, data=datos[op["offset"]:op["offset"] + op["length"]], timeout=120)
            if r.status_code >= 300: print("ERROR subida", nom, r.status_code); return False
        pedir("PATCH", f"/appScreenshots/{res['id']}", {"data": {"type": "appScreenshots", "id": res["id"], "attributes": {"uploaded": True, "sourceFileChecksum": md5}}})
        nuevas.append(res["id"]); print("SUBIDA", nom, len(datos))
    for k in range(40):
        est = [(pedir("GET", f"/appScreenshots/{i}")["data"]["attributes"].get("assetDeliveryState") or {}).get("state") for i in nuevas]
        if all(e == "COMPLETE" for e in est): break
        if any(e == "FAILED" for e in est): print("ERROR procesando", est); return False
        time.sleep(5)
    else:
        print("ERROR no terminaron de procesarse"); return False
    for i in antes: pedir("DELETE", f"/appScreenshots/{i}")
    pedir("PATCH", f"/appScreenshotSets/{ss['id']}/relationships/appScreenshots", {"data": [{"type": "appScreenshots", "id": i} for i in nuevas]})
    for sc in pedir("GET", f"/appScreenshotSets/{ss['id']}/appScreenshots?limit=20")["data"]:
        a = sc["attributes"]; print("    CAP", a.get("fileName"), a.get("fileSize"), (a.get("assetDeliveryState") or {}).get("state"))
    return True

def poner_notas(v):
    """1.65 (24): las notas para el revisor (fastlane/metadata/review_information/notes.txt) en la versión."""
    import os
    ruta = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "fastlane", "metadata", "review_information", "notes.txt")
    txt = open(ruta, encoding="utf-8").read().strip()[:3990]
    r = requests.get(API + f"/appStoreVersions/{v['id']}/appStoreReviewDetail", headers=cab())
    d = r.json().get("data") if r.status_code == 200 else None
    if d:
        pedir("PATCH", f"/appStoreReviewDetails/{d['id']}", {"data": {"type": "appStoreReviewDetails", "id": d["id"], "attributes": {"notes": txt}}})
    else:
        pedir("POST", "/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": {"notes": txt},
              "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}})
    print("Notas para el revisor puestas:", len(txt), "caracteres")

if ACCION == "publicar":
    v = version()
    if not v: print("No existe la versión", VER); sys.exit(1)
    st = v["attributes"].get("appStoreState")
    print("Estado:", st)
    if st != "PENDING_DEVELOPER_RELEASE": print("No está esperando publicación; no se hace nada."); sys.exit(1)
    pedir("POST", "/appStoreVersionReleaseRequests", {"data": {"type": "appStoreVersionReleaseRequests",
          "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}})
    print("PUBLICADA", VER)

elif ACCION == "enviar":
    # 1) la compilación más nueva de esa versión, ya procesada
    for i in range(60):
        bs = pedir("GET", f"/builds?filter[app]={APP}&filter[preReleaseVersion.version]={VER}&sort=-uploadedDate&limit=1")["data"]
        if bs and bs[0]["attributes"]["processingState"] == "VALID": break
        print("Esperando a que Apple procese la compilación...", bs[0]["attributes"]["processingState"] if bs else "sin compilación"); time.sleep(30)
    else:
        print("La compilación no está lista"); sys.exit(1)
    b = bs[0]; print("Compilación", b["attributes"]["version"])
    if b["attributes"].get("usesNonExemptEncryption") is None:
        pedir("PATCH", f"/builds/{b['id']}", {"data": {"type": "builds", "id": b["id"], "attributes": {"usesNonExemptEncryption": False}}})
    # 2) la versión (se crea si no existe; hereda los textos de la anterior)
    v = version()
    if not v:
        # 1.61: si hay otra versión sin publicar (p. ej. la 1.60 esperando revisión), se retira de revisión y se convierte en esta
        otra = None
        for x in pedir("GET", f"/apps/{APP}/appStoreVersions?filter[platform]=IOS&limit=20")["data"]:
            if x["attributes"].get("appStoreState") not in ("READY_FOR_SALE", "REPLACED_WITH_NEW_VERSION", "REMOVED_FROM_SALE", "DEVELOPER_REMOVED_FROM_SALE"):
                otra = x; break
        if otra:
            print("Versión sin publicar:", otra["attributes"]["versionString"], otra["attributes"].get("appStoreState"))
            for rs in pedir("GET", f"/apps/{APP}/reviewSubmissions?filter[platform]=IOS&limit=10")["data"]:
                if rs["attributes"].get("state") in ("WAITING_FOR_REVIEW", "READY_FOR_REVIEW"):
                    pedir("PATCH", f"/reviewSubmissions/{rs['id']}", {"data": {"type": "reviewSubmissions", "id": rs["id"], "attributes": {"canceled": True}}})
                    print("RETIRADA de revisión", rs["id"])
            for k in range(40):
                otra = pedir("GET", f"/appStoreVersions/{otra['id']}")["data"]
                if otra["attributes"].get("appStoreState") in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"): break
                time.sleep(10)
            pedir("PATCH", f"/appStoreVersions/{otra['id']}", {"data": {"type": "appStoreVersions", "id": otra["id"], "attributes": {"versionString": VER}}})
            print("Versión", otra["attributes"]["versionString"], "->", VER)
            v = version()
    if not v:
        v = pedir("POST", "/appStoreVersions", {"data": {"type": "appStoreVersions",
              "attributes": {"platform": "IOS", "versionString": VER, "releaseType": "AFTER_APPROVAL"},
              "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})["data"]
        print("Versión creada", VER)
    else:
        pedir("PATCH", f"/appStoreVersions/{v['id']}", {"data": {"type": "appStoreVersions", "id": v["id"], "attributes": {"releaseType": "AFTER_APPROVAL"}}})
    pedir("PATCH", f"/appStoreVersions/{v['id']}/relationships/build", {"data": {"type": "builds", "id": b["id"]}})
    # 3) novedades en cada idioma
    for loc in pedir("GET", f"/appStoreVersions/{v['id']}/appStoreVersionLocalizations")["data"]:
        l = loc["attributes"]["locale"]
        txt = NOVEDADES["ca"] if l.startswith("ca") else NOVEDADES["es"] if l.startswith("es") else NOVEDADES["en"]
        pedir("PATCH", f"/appStoreVersionLocalizations/{loc['id']}", {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": {"whatsNew": txt}}})
        print("Novedades", l)
    # 3b) la 1ª captura de la 1.59 se subió dañada: en la versión nueva se cambia por la buena
    try:
        print("Capturas nuevas:", poner_capturas(v))
    except SystemExit:
        print("Captura 01: no se ha podido cambiar (se envía igual)")
    poner_notas(v)
    # 4) enviar a revisión. 1.65 (24): si la versión fue rechazada, se reutiliza su envío (UNRESOLVED_ISSUES) en vez de crear otro
    s = None
    for rs in pedir("GET", f"/apps/{APP}/reviewSubmissions?filter[platform]=IOS&limit=10")["data"]:
        print("Envío existente", rs["id"], rs["attributes"].get("state"))
        if rs["attributes"].get("state") in ("UNRESOLVED_ISSUES", "READY_FOR_REVIEW") and s is None: s = rs
    if s is None:
        s = pedir("POST", "/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                  "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})["data"]
    items = pedir("GET", f"/reviewSubmissions/{s['id']}/items?include=appStoreVersion")
    tiene = any(((it.get("relationships") or {}).get("appStoreVersion") or {}).get("data", {}) and it["relationships"]["appStoreVersion"]["data"]["id"] == v["id"] for it in items.get("data", []))
    if not tiene:
        pedir("POST", "/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems",
              "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": s["id"]}},
                                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}})
    pedir("PATCH", f"/reviewSubmissions/{s['id']}", {"data": {"type": "reviewSubmissions", "id": s["id"], "attributes": {"submitted": True}}})
    print("ENVIADA A REVISION", VER, "envío", s["id"])
elif ACCION == "reenviar":
    # 1.65 (24): solo vuelve a enviar a revisión la versión tal como está (build, notas y capturas ya puestos), con reintentos
    v = version(); print("Estado", v["attributes"].get("appStoreState"))
    s = None
    for rs in pedir("GET", f"/apps/{APP}/reviewSubmissions?filter[platform]=IOS&limit=10")["data"]:
        if rs["attributes"].get("state") in ("UNRESOLVED_ISSUES", "READY_FOR_REVIEW") and s is None: s = rs
    print("Envío", s and s["id"], s and s["attributes"].get("state"))
    for k in range(20):
        r = requests.patch(API + f"/reviewSubmissions/{s['id']}", headers=cab(), data=json.dumps({"data": {"type": "reviewSubmissions", "id": s["id"], "attributes": {"submitted": True}}}))
        if r.status_code in (200, 201, 204): print("ENVIADA A REVISION", VER, "envío", s["id"]); break
        print("Aún no se puede (", r.status_code, "):", (r.json().get("errors") or [{}])[0].get("meta", {}).get("associatedErrors", r.text[:300]) if r.text else ""); time.sleep(60)
    else:
        print("ERROR no se ha podido enviar"); sys.exit(1)
elif ACCION == "reenviar_nuevo":
    # 1.65 (24): el envío rechazado (UNRESOLVED_ISSUES) no deja reenviar: se cancela y se hace un envío nuevo
    v = version(); print("Estado", v["attributes"].get("appStoreState"))
    for rs in pedir("GET", f"/apps/{APP}/reviewSubmissions?filter[platform]=IOS&limit=10")["data"]:
        st = rs["attributes"].get("state")
        if st in ("UNRESOLVED_ISSUES", "READY_FOR_REVIEW"):
            its = pedir("GET", f"/reviewSubmissions/{rs['id']}/items")
            for it in its.get("data", []): print("  item", it["id"], it["attributes"].get("state"))
            r = requests.patch(API + f"/reviewSubmissions/{rs['id']}", headers=cab(), data=json.dumps({"data": {"type": "reviewSubmissions", "id": rs["id"], "attributes": {"canceled": True}}}))
            print("Cancelar envío", rs["id"], st, r.status_code, r.text[:300])
    time.sleep(20)
    for k in range(15):
        r = requests.post(API + "/reviewSubmissions", headers=cab(), data=json.dumps({"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                          "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}}))
        if r.status_code in (200, 201): s = r.json()["data"]; break
        print("Crear envío:", r.status_code, r.text[:300]); time.sleep(30)
    else:
        print("ERROR no se pudo crear el envío"); sys.exit(1)
    r = requests.post(API + "/reviewSubmissionItems", headers=cab(), data=json.dumps({"data": {"type": "reviewSubmissionItems",
          "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": s["id"]}},
                            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}}))
    print("Item:", r.status_code, r.text[:500])
    for k in range(10):
        r = requests.patch(API + f"/reviewSubmissions/{s['id']}", headers=cab(), data=json.dumps({"data": {"type": "reviewSubmissions", "id": s["id"], "attributes": {"submitted": True}}}))
        if r.status_code in (200, 201, 204): print("ENVIADA A REVISION", VER, "envío", s["id"]); break
        print("Aún no se puede:", r.status_code, r.text[:600]); time.sleep(60)
    else:
        print("ERROR no se ha podido enviar"); sys.exit(1)
elif ACCION == "recapturas":
    # Retira la versión de revisión (si está esperando), pone las capturas buenas y la vuelve a enviar.
    v = version()
    print("Estado", v["attributes"].get("appStoreState"))
    for rs in pedir("GET", f"/apps/{APP}/reviewSubmissions?filter[platform]=IOS&limit=10")["data"]:
        st = rs["attributes"].get("state")
        print("Envío", rs["id"], st)
        if st in ("WAITING_FOR_REVIEW", "READY_FOR_REVIEW"):
            pedir("PATCH", f"/reviewSubmissions/{rs['id']}", {"data": {"type": "reviewSubmissions", "id": rs["id"], "attributes": {"canceled": True}}})
            print("RETIRADO", rs["id"])
    for k in range(40):
        v = version(); st = v["attributes"].get("appStoreState")
        if st in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"): break
        time.sleep(10)
    print("Estado ahora", st)
    if not poner_capturas(v): print("ERROR capturas: no se vuelve a enviar"); sys.exit(1)
    s2 = pedir("POST", "/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
              "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})["data"]
    pedir("POST", "/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems",
          "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": s2["id"]}},
                            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}})
    pedir("PATCH", f"/reviewSubmissions/{s2['id']}", {"data": {"type": "reviewSubmissions", "id": s2["id"], "attributes": {"submitted": True}}})
    print("ENVIADA A REVISION", VER)
elif ACCION == "mirar":
    # solo mira: disponibilidad por países, precio y datos de la ficha
    app = pedir("GET", f"/apps/{APP}")["data"]["attributes"]
    print("APP", app.get("name"), app.get("bundleId"), "contentRights:", app.get("contentRightsDeclaration"))
    for ruta in [f"/apps/{APP}/appAvailabilityV2", f"/apps/{APP}/appPriceSchedule"]:
        r = requests.get(API + ruta, headers=cab()); print("GET", ruta, r.status_code, r.text[:600])
    V2 = "https://api.appstoreconnect.apple.com/v2"
    rr = requests.get(V2 + f"/appAvailabilities/{APP}?include=territoryAvailabilities&limit[territoryAvailabilities]=50", headers=cab())
    print("RAW2", rr.status_code, rr.text[:300].replace(chr(10), " "))
    inc = rr.json().get("included", []) if rr.ok else []
    print("TERRITORIOS (primeros 50)", len(inc), "disponibles", sum(1 for t in inc if t["attributes"].get("available")))
    import base64, collections
    todos, url = [], V2 + f"/appAvailabilities/{APP}/territoryAvailabilities?include=territory&limit=200"
    while url:
        rr = requests.get(url, headers=cab())
        if not rr.ok: print("ERR terr", rr.status_code, rr.text[:200].replace(chr(10)," ")); break
        jj = rr.json(); todos += jj.get("data", []); url = jj.get("links", {}).get("next")
    if not todos:
        todos = inc
    est = collections.defaultdict(list)
    for t in todos:
        ter = (t.get("relationships", {}).get("territory", {}).get("data") or {}).get("id")
        if not ter:
            try: ter = json.loads(base64.b64decode(t["id"] + "==").decode()).get("t")
            except Exception: ter = t["id"][:12]
        est[",".join(t["attributes"].get("contentStatuses") or [])].append(str(ter))
    for k, v in est.items(): print("ESTADO", k, len(v), " ".join(sorted(v))[:900])
    rr = requests.get(API + f"/apps/{APP}/availableTerritories?limit=200", headers=cab())
    print("V1 availableTerritories", rr.status_code, len(rr.json().get("data", [])) if rr.ok else rr.text[:200].replace(chr(10), " "))
    j = requests.get(API + f"/appPriceSchedules/{APP}/manualPrices?include=appPricePoint", headers=cab()).json()
    print("PRECIOS", len(j.get("data", [])), [x.get("attributes") for x in j.get("included", [])][:2])
    for v in pedir("GET", f"/apps/{APP}/appStoreVersions?limit=5")["data"]:
        print("VERSION", v["attributes"]["versionString"], v["attributes"].get("appStoreState"), v["attributes"].get("earliestReleaseDate"))
elif ACCION == "capturas":
    # solo mira: las capturas de cada idioma de la versión y su estado
    v = version()
    if not v: print("No existe la versión", VER); sys.exit(1)
    for loc in pedir("GET", f"/appStoreVersions/{v['id']}/appStoreVersionLocalizations")["data"]:
        print("IDIOMA", loc["attributes"]["locale"])
        for ss in pedir("GET", f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]:
            print("  SET", ss["attributes"]["screenshotDisplayType"])
            for sc in pedir("GET", f"/appScreenshotSets/{ss['id']}/appScreenshots?limit=20")["data"]:
                a = sc["attributes"]; ad = a.get("assetDeliveryState") or {}
                im = a.get("imageAsset") or {}
                print("    CAP", a.get("fileName"), a.get("fileSize"), im.get("width"), im.get("height"), ad.get("state"), ad.get("errors"), sc["id"])
elif ACCION == "cambiar01":
    arreglar01(version())
elif ACCION == "mover01":
    # Pasa la 1ª captura (la que no se ve) al final; no sube ni borra nada.
    v = version(); loc = [l for l in pedir("GET", f"/appStoreVersions/{v['id']}/appStoreVersionLocalizations")["data"] if l["attributes"]["locale"] == "es-ES"][0]
    ss = [x for x in pedir("GET", f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"] if x["attributes"]["screenshotDisplayType"] == "APP_IPHONE_67"][0]
    ids = [c["id"] for c in pedir("GET", f"/appScreenshotSets/{ss['id']}/appScreenshots?limit=20")["data"]]
    nuevo = ids[1:] + ids[:1]
    pedir("PATCH", f"/appScreenshotSets/{ss['id']}/relationships/appScreenshots", {"data": [{"type": "appScreenshots", "id": i} for i in nuevo]})
    for sc in pedir("GET", f"/appScreenshotSets/{ss['id']}/appScreenshots?limit=20")["data"]:
        print("    CAP", sc["attributes"].get("fileName"), sc["attributes"].get("fileSize"))
else:
    print("Acción desconocida"); sys.exit(1)
