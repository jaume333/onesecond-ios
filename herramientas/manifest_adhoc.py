"""1.67: manifest.plist + página para instalar la versión Ad Hoc desde Safari (itms-services)."""
import sys
c, v, b, out = sys.argv[1:5]
base = "https://onesecond.es/revision/" + c
open(out + "/manifest.plist", "w").write(f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>items</key><array><dict>
<key>assets</key><array><dict><key>kind</key><string>software-package</string><key>url</key><string>{base}/OneSecond.ipa</string></dict></array>
<key>metadata</key><dict>
<key>bundle-identifier</key><string>es.onesecond.rallygps</string>
<key>bundle-version</key><string>{v}</string>
<key>kind</key><string>software</string>
<key>title</key><string>One Second {v} ({b})</string>
</dict></dict></array></dict></plist>
""")
open(out + "/index.html", "w").write(f"""<!doctype html><html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex">
<title>One Second {v}</title>
<style>body{{font-family:-apple-system,sans-serif;background:#0c1a2b;color:#fff;text-align:center;padding:40px 18px}}
a{{display:inline-block;background:#ffd257;color:#0c1a2b;font-weight:800;padding:16px 26px;border-radius:12px;text-decoration:none;font-size:18px}}
p{{color:#b8c4d3;line-height:1.5}}</style></head><body>
<h1>One Second {v} ({b})</h1>
<p>Instalación de prueba solo para el iPhone registrado.<br>Instal·lació de prova només per a l'iPhone registrat.<br>Test install for the registered iPhone only.</p>
<p><a href="itms-services://?action=download-manifest&amp;url={base}/manifest.plist">Instalar / Instal·lar / Install</a></p>
<p>Ábrelo con Safari · Obre-ho amb Safari · Open it in Safari</p>
</body></html>
""")
print("manifest y página hechos en", out)
