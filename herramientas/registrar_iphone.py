"""1.67: registra un iPhone (por su UDID) en la cuenta de desarrollador para poder instalarle una versión Ad Hoc."""
import os, sys, time
import jwt, requests

p8 = open(sys.argv[1]).read()
udid = sys.argv[2].strip().lower()
tok = jwt.encode({"iss": os.environ["ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 900, "aud": "appstoreconnect-v1"},
                 p8, algorithm="ES256", headers={"kid": os.environ["KEY_ID"], "typ": "JWT"})
H = {"Authorization": "Bearer " + tok, "Content-Type": "application/json"}
API = "https://api.appstoreconnect.apple.com/v1/devices"
r = requests.get(API, headers=H, params={"filter[udid]": udid, "limit": 5})
r.raise_for_status()
ya = r.json()["data"]
if ya:
    d = ya[0]["attributes"]
    print("Ya registrado:", d.get("name"), d.get("status"), d.get("model"))
    if d.get("status") != "ENABLED":
        rr = requests.patch(API + "/" + ya[0]["id"], headers=H, json={"data": {"type": "devices", "id": ya[0]["id"], "attributes": {"status": "ENABLED"}}})
        print("Activado:", rr.status_code)
    sys.exit(0)
r = requests.post(API, headers=H, json={"data": {"type": "devices", "attributes": {"name": "iPhone 7 pruebas", "udid": udid, "platform": "IOS"}}})
print(r.status_code, r.text[:400])
r.raise_for_status()
print("Registrado")
