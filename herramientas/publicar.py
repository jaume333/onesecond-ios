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
    "es": "Nueva sección MINI JUEGOS: Caza al Topo, Ruta 66 y Bingo Motero, con lector de QR y código del ticket. El bingo te avisa con notificaciones si haces línea o bingo y cuando va a empezar la partida. Mejoras en el navegador y en las pantallas de las pruebas.",
    "ca": "Nova secció MINI JOCS: Caça el Talp, Ruta 66 i Bingo Motero, amb lector de QR i codi del tiquet. El bingo t'avisa amb notificacions si fas línia o bingo i quan comença la partida. Millores al navegador i a les pantalles de les proves.",
    "en": "New MINI GAMES section: Whack-a-Mole, Route 66 and Biker Bingo, with QR reader and ticket code. The bingo notifies you if you get a line or bingo and when a game is about to start. Improvements to the navigator and the event screens.",
}

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
    # 4) enviar a revisión
    s = pedir("POST", "/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
              "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})["data"]
    pedir("POST", "/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems",
          "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": s["id"]}},
                            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}})
    pedir("PATCH", f"/reviewSubmissions/{s['id']}", {"data": {"type": "reviewSubmissions", "id": s["id"], "attributes": {"submitted": True}}})
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
else:
    print("Acción desconocida"); sys.exit(1)
