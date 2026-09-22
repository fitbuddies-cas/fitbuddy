# Certificate Pinning

> Umsetzung von #153 (TD-4, [ADR-004](adr/ADR-004-no-backend-proxy-poc.md)). Stand der Herleitung: **2026-09-20**.
> Dieses Dokument ist die Referenz für Rotation und Notfall: Wer einen Pin ändern muss, findet hier
> die Herleitung, die Prüfung und den manuellen Testablauf.

## 1. Warum

Jede Anfrage von FitBuddy trägt ein Geheimnis des Nutzers als Header: den Hevy-API-Key, den LLM-Key
(Claude/Gemini/Mistral), das Strava- bzw. Polar-Access-Token — und beim Token-Exchange das Client
Secret seiner Strava- bzw. Polar-Application. TLS schützt das nur, solange die Gegenstelle die echte
ist. Im offenen WLAN genügt ein MITM-Proxy mit installiertem Root-Zertifikat (Charles, mitmproxy),
um alle Geheimnisse und die Gesundheitsdaten im Klartext mitzulesen. Im BYO-Key-Modell gibt es
keinen serverseitigen Kill-Switch: Ein abgegriffener Key gilt, bis der Nutzer ihn rotiert.

## 2. Mechanismus

Das Pinning ist **deklarativ** in `FitBuddy/App/Info.plist` hinterlegt (`NSAppTransportSecurity` →
`NSPinnedDomains`, iOS 14+). Das System wertet die Pins vor jedem TLS-Handshake aus; es gibt keinen
Code-Pfad, der sie vergessen könnte, und sie gelten für jede `URLSession` im Prozess — also für
`URLSession.fitBuddy` **und** `.fitBuddyStreaming`.

**Gepinnt wird die Root-CA** (`NSPinnedCAIdentities`, SPKI-SHA256 des öffentlichen Schlüssels),
nicht das Leaf- und nicht das Intermediate-Zertifikat:

- Ein **Leaf-Pin** bricht bei jeder Zertifikatserneuerung — bei den CDN-Hosts alle paar Wochen.
- Ein **Intermediate-Pin** bricht bei Let's Encrypt (Hevy) und Google Trust Services (Anthropic,
  Mistral, Gemini) ebenfalls: Beide wählen bei jeder Ausstellung aus einem Pool von Intermediates
  (R10–R14/E5–E9 bzw. WR1–WR5/WE1–WE5) und rotieren diese.
- Ein **Root-Pin** ist über Jahre stabil. Apple prüft eine CA-Identity an jeder Stelle der Kette
  («A pinned CA public key must appear in a certificate chain either in an intermediate or root
  certificate»), und der SPKI-Hash ist bei einem cross-signierten Root identisch mit dem
  selbstsignierten — egal, welchen Pfad das System aufbaut.

**Backup-Pins:** Jeder Host listet alle Roots, zu denen seine CA verketten kann. Für die beiden
Hosts hinter **Cloudflare** (Anthropic, Mistral) zusätzlich alle CA-Familien, aus denen Cloudflare
Universal SSL bei einer Erneuerung ausstellen kann (Let's Encrypt, Google Trust Services, SSL.com).
Ein CA-Wechsel auf Anbieterseite führt so nicht zum Totalausfall.

`NSIncludesSubdomains` ist nirgends gesetzt: Alle sieben Hosts sind exakt die, die der Code anspricht.

## 3. Hosts und Pins

| Host | Trägt | Hinter | Beobachtete Kette (2026-09-20) | Gepinnte Roots (SPKI-SHA256) |
|---|---|---|---|---|
| `api.hevyapp.com` | Hevy-API-Key, Trainingsdaten | Heroku | Leaf → Let's Encrypt **YR2** → **ISRG Root YR** (cross-signiert von ISRG Root X1) | ISRG Root X1 `C5+lpZ7t…HFr8M=` · ISRG Root X2 `diGVwiVY…mgzI=` · ISRG Root YR (wie serviert) `fk6IOKit…hhi88=` |
| `api.anthropic.com` | Claude-Key, Prompt mit Trainingsdaten | Cloudflare | Leaf → GTS **WE1** → **GTS Root R4** | GTS Root R1 `hxqRlPTu…p63Gc=` · R2 `Vfd95BwD…Ox78=` · R3 `QXnt2YHv…3Q0g=` · R4 `mEflZT5e…YQ0c=` · ISRG Root X1/X2 · SSL.com TLS RSA Root CA 2022 `K89VOmb1…r3VQ=` · SSL.com TLS ECC Root CA 2022 `G/ANXI8T…G4yE=` |
| `generativelanguage.googleapis.com` | Gemini-Key, Prompt mit Trainingsdaten | Google | Leaf → GTS **WR2** → **GTS Root R1** | GTS Root R1–R4 |
| `api.mistral.ai` | Mistral-Key, Prompt mit Trainingsdaten | Cloudflare | Leaf → GTS **WE1** → **GTS Root R4** | identisch mit `api.anthropic.com` |
| `www.strava.com` | Client Secret, Access-/Refresh-Token, Aktivitäten | — | Leaf → GoDaddy TLS Intermediate CA DV R1v1 → **GoDaddy TLS Root CA - R1** (cross-signiert von Go Daddy Root G2) | GoDaddy TLS Root CA - R1 (wie serviert) `gKjJIacZ…nKZA=` · Go Daddy Root Certificate Authority - G2 `Ko8tivDr…GNdA=` |
| `www.polaraccesslink.com` | Access-Token, Trainingsdaten | AWS | Leaf → Amazon RSA 2048 M01 → **Amazon Root CA 1** | Amazon Root CA 1 `++MBgDH5…X1aI=` · CA 2 `f0KW/Ftq…qJGE=` · CA 3 `NqvDJlas…Xq8k=` · CA 4 `9+ze1cZg…4U8U=` · Starfield Services Root CA G2 `KwccWaCg…oP5I=` |
| `polarremote.com` | Client Secret, Access-Token (Token-Exchange) | AWS | Leaf → Amazon RSA 2048 M01 → **Amazon Root CA 1** | identisch mit `www.polaraccesslink.com` |

Die vollständigen Hashes stehen in `FitBuddy/App/Info.plist`; `CertificatePinningConfigurationTests`
prüft im gebauten Bundle, dass genau diese sieben Hosts gepinnt sind, jeder mindestens zwei gültige
Root-Pins hat und die Paare (Polar, Cloudflare) identische Pin-Sets tragen.

**Bewusst nicht gepinnt:** `flow.polar.com` und `www.strava.com/oauth/authorize` als Web-Sheet.
Beide laufen in `ASWebAuthenticationSession`, einem System-Browser-Kontext ausserhalb des
App-Prozesses, den die App nicht pinnen kann. Die `state`-Prüfung im Callback (#138) deckt diesen
Weg ab; der Token-Exchange mit dem Secret läuft danach wieder über die gepinnte `URLSession`.

## 4. Herleitung

Root aus der servierten Kette oder aus dem System-Trust-Store holen, dann den SPKI-Hash bilden:

```bash
# Kette anzeigen (Subject/Issuer pro Glied)
openssl s_client -connect api.hevyapp.com:443 -servername api.hevyapp.com -showcerts </dev/null 2>/dev/null \
  | grep -E '^ *[0-9]+ s:|^ *i:'

# SPKI-SHA256 eines PEM-Zertifikats (Leaf, Intermediate oder Root)
openssl x509 -in root.pem -pubkey -noout \
  | openssl pkey -pubin -outform der \
  | openssl dgst -sha256 -binary | base64

# Root aus dem macOS-Trust-Store (Name wie im Zertifikat)
security find-certificate -c "ISRG Root X1" -p /System/Library/Keychains/SystemRootCertificates.keychain
```

Die Roots in Abschnitt 3 wurden am 2026-09-20 so hergeleitet: die als «wie serviert» markierten aus
dem letzten Glied der servierten Kette, alle anderen aus dem macOS-Trust-Store (Xcode 26 / macOS 26).

## 5. Prüfung ohne Gerät

Bevor ein TestFlight-Build geht, einmal prüfen, dass jede live servierte Kette mindestens einen
gepinnten Schlüssel enthält. Das ist kein Ersatz für Abschnitt 6, fängt aber einen Tippfehler oder
einen CA-Wechsel auf Anbieterseite ab:

```bash
for h in api.hevyapp.com api.anthropic.com generativelanguage.googleapis.com api.mistral.ai \
         www.strava.com www.polaraccesslink.com polarremote.com; do
  served=$(openssl s_client -connect $h:443 -servername $h -showcerts </dev/null 2>/dev/null \
    | awk '/-----BEGIN CERT/{c=""} {c=c $0 "\n"} /-----END CERT/{print c; print "@@"}' \
    | awk -v RS='@@\n' '{ print $0 > "/tmp/cert.pem"; close("/tmp/cert.pem");
        cmd="openssl x509 -in /tmp/cert.pem -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64";
        cmd | getline h; close(cmd); print h }')
  pinned=$(plutil -extract "NSAppTransportSecurity.NSPinnedDomains.$h.NSPinnedCAIdentities" json -o - FitBuddy/App/Info.plist \
    | grep -o '"[A-Za-z0-9+/=]\{44\}"' | tr -d '"')
  if grep -qxF -f <(echo "$pinned") <(echo "$served"); then echo "OK   $h"; else echo "MISS $h"; fi
done
```

Ergebnis am 2026-09-20: alle sieben Hosts `OK` (je ein Root-Pin in der servierten Kette, Strava zwei).

## 6. Manuelle Verifikation (vor jedem TestFlight-Build)

Unit-Tests erreichen TLS nicht (`StubURLProtocol` umgeht den Stack). Das Pinning selbst ist deshalb
manuell zu prüfen — einmal **fail closed** mit Proxy, einmal **funktioniert** ohne Proxy.

**Mit mitmproxy (muss scheitern):**

1. `brew install mitmproxy`, `mitmproxy --listen-port 8080` starten.
2. Simulator: Der Simulator übernimmt den System-Proxy des Mac. Unter *Systemeinstellungen → Netzwerk
   → Details → Proxies* den Web-Proxy (HTTP und HTTPS) auf `127.0.0.1:8080` setzen.
3. Im Simulator Safari öffnen, `http://mitm.it` aufrufen, das mitmproxy-Root-Zertifikat installieren
   (*Einstellungen → Allgemein → VPN & Geräteverwaltung → Profil installieren*) und unter
   *Einstellungen → Allgemein → Info → Zertifikatsvertrauenseinstellungen* voll vertrauen.
4. App starten und je einmal auslösen: Hevy-Key-Check (Onboarding oder Settings-Editor), eine Analyse
   pro Provider (Claude, Gemini, Mistral), Strava-Connect (Token-Exchange), Polar-Connect
   (Token-Exchange) und einen Pull-to-Refresh mit verbundenem Strava/Polar.
5. Erwartet: mitmproxy zeigt für jeden der sieben Hosts einen abgebrochenen TLS-Handshake
   (`Client TLS handshake failed`), **kein** Request mit Header wird sichtbar. Die App zeigt
   «connection not trusted» bzw. «Connection to … not trusted» — nicht «no connection».
6. Proxy in den Systemeinstellungen wieder deaktivieren, Profil im Simulator entfernen.

**Ohne Proxy (muss funktionieren):** Onboarding mit echtem Hevy-Key, eine Analyse, ein Strava-Connect
und ein Polar-Connect gegen die echten Hosts.

## 7. Fehlerbild in der App

Ein Pin-Fehler kommt aus `URLSession` als `URLError` mit einem Zertifikats-Code an
(`.serverCertificateUntrusted` und Verwandte, siehe `Error+UntrustedConnection.swift`). Jede
Transport-Stelle (`HevyConnector`, `StravaConnector`, `StravaOAuthService`, `PolarHTTP`,
`LLMStreamTransport`, `HevyKeyValidator`) bildet ihn auf einen eigenen Fall `untrustedConnection`
ab — nie auf `networkUnavailable`. Der Nutzer sieht:

| Stelle | Text |
|---|---|
| Dashboard-Banner | «connection not trusted» |
| Refresh-Toast | «The secure connection could not be verified. Check the device's date and time or switch networks, then try again.» |
| Key-Eingabe (Hevy) | «Connection to Hevy not trusted» + Hinweis, Datum & Uhrzeit zu prüfen oder das Netz zu wechseln |
| Analyse | «Connection not trusted» + Hinweis, dass nichts gesendet wurde |
| Strava-/Polar-Connect | «Connection to Strava/Polar not trusted» |

Die Aussage «nichts wurde gesendet» stimmt: Das System bricht den Handshake ab, bevor ein Request
mit Header die Leitung erreicht.

Die Texte behaupten bewusst keine Interception. Nur `.serverCertificateUntrusted` und
`.serverCertificateHasUnknownRoot` sind das, was ein fehlgeschlagener Pin-Check tatsächlich auslöst.
`.serverCertificateHasBadDate` und `.serverCertificateNotYetValid` entstehen in der Praxis meist durch
eine verstellte Geräteuhr — ein iPhone mit falscher Zeit hält jedes gültige Zertifikat für abgelaufen,
und ein Netzwechsel hilft dann nicht. `.secureConnectionFailed` ist der generische TLS-Fehler
(Protokoll- oder Cipher-Mismatch, Captive Portal, abgebrochener Handshake). Alle fünf bleiben
klassifiziert, weil «nicht vertrauen, nichts gesendet» für jeden gilt; der Text sagt deshalb «could not
verify» und nennt Datum & Uhrzeit als zweite Handlungsoption neben dem Netzwechsel.

## 8. Debug-Builds

Das Pinning gilt in **allen** Build-Konfigurationen, auch Debug. Eine `Info.plist` kennt keine
Konfiguration; eine zweite plist pro Konfiguration würde die `CFBundleURLTypes` duplizieren und
auseinanderlaufen. Konsequenz: Charles/mitmproxy funktionieren beim Entwickeln nicht mehr gegen die
sieben Hosts. Wer Traffic debuggen muss, entfernt den `NSPinnedDomains`-Block **lokal** und committet
das nicht — `CertificatePinningConfigurationTests` schlägt in dem Fall fehl und verhindert, dass ein
solcher Stand versehentlich grün durch die CI geht.

## 9. Rotation und Notfall

**Risiko:** Ein falscher oder abgelaufener Pin sperrt alle Tester aus einer Quelle aus; ein
Server-Fix ist unmöglich, nur ein neuer Build hilft. Deshalb Root statt Intermediate, mehrere Roots
pro Host, und Abschnitt 5/6 vor jedem TestFlight-Build.

**Symptom:** Die App zeigt für genau einen Anbieter «connection not trusted», obwohl kein Proxy
aktiv ist und derselbe Host im Browser funktioniert.

**Ablauf:**

1. Abschnitt 5 laufen lassen — der betroffene Host meldet `MISS`.
2. Kette des Hosts anzeigen (Abschnitt 4), das neue Root identifizieren.
3. SPKI-Hash bilden, in `Info.plist` beim betroffenen Host **ergänzen** (alte Pins vorerst
   behalten — der Anbieter kann zurückwechseln), bei Paar-Hosts (Polar, Cloudflare) an beiden Stellen.
4. Tabelle in Abschnitt 3 und das Datum oben nachziehen, `CertificatePinningConfigurationTests`
   laufen lassen, Abschnitt 6 durchspielen, neuen TestFlight-Build ausliefern.

Die Roots laufen frühestens 2035 ab (ISRG Root X1); die übrigen 2036–2046.
