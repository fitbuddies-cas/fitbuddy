# Strava mit FitBuddy verbinden — Einrichtungsanleitung

> Anleitung für Nutzerinnen und Nutzer, die ihre Strava-Aktivitäten im FitBuddy-Dashboard sehen
> wollen. Stand: September 2026, geprüft gegen das damalige Strava-Formular. Wenn Strava Felder
> umbenennt, gilt sinngemäss das Feld mit der ähnlichsten Bezeichnung.
>
> Hintergrund für das Team: [ADR-010](adr/ADR-010-strava-oauth-byo-app.md) (BYO-App-Modell), US-5 in
> [REQUIREMENTS.md](REQUIREMENTS.md).
>
> **In der App:** Weil das Repository privat ist, erreicht dieses Dokument keine Testerin. Dieselbe
> Anleitung steht deshalb auf Englisch in der App unter **Settings → Strava → Setup guide**
> (`StravaSetupGuideView`). Wer hier etwas ändert, zieht die View nach — und umgekehrt.

## Warum braucht es diese Anleitung?

FitBuddy hat kein Backend und bringt keine eigene Strava-Anbindung mit. Stattdessen läuft die
Verbindung über eine **Strava-API-Application, die dir gehört** — genau wie beim Hevy-API-Key und
beim Claude-Key. Du legst diese Application einmalig auf strava.com an und trägst ihre
**Client ID** und ihr **Client Secret** in FitBuddy ein. Danach autorisierst du FitBuddy in einem
Strava-Login-Fenster, und die App liest deine Aktivitäten.

Das Anlegen dauert etwa fünf Minuten und setzt ein Strava-Abo voraus (siehe unten). Es gibt genau
eine Stolperfalle: die **Authorization Callback Domain** muss `localhost` lauten. Alles andere ist
Ausfüllen von Pflichtfeldern.

## Was du brauchst

- Ein Strava-Konto **mit aktivem Strava-Abo**. Strava nennt das Abo ausdrücklich als
  Voraussetzung für das Anlegen einer API-Application («A Strava subscription is a prerequisite
  for creating an app», [Getting Started](https://developers.strava.com/docs/getting-started/)).
  Mit einem Gratis-Konto lässt sich keine Application anlegen — und damit auch FitBuddy nicht
  verbinden.
- Einen Browser, am besten auf dem Mac oder PC — das Formular ist auf dem Handy unübersichtlich.
- FitBuddy auf dem iPhone, Onboarding abgeschlossen (Hevy-Key und AI-Key sind hinterlegt).
- Ein beliebiges quadratisches Bild als App-Icon (PNG oder JPG). Strava verlangt eines; der Inhalt ist egal.

## Schritt 1 — Strava-Einstellungen öffnen

1. Melde dich im Browser bei [strava.com](https://www.strava.com) an.
2. Öffne **Settings → My API Application** oder direkt
   **<https://www.strava.com/settings/api>**.
3. Hast du noch keine Application, zeigt Strava das Formular «Create an App». Hast du schon eine,
   siehst du deren Daten — du kannst sie für FitBuddy weiterverwenden, sofern die Callback Domain
   stimmt (siehe Schritt 3).

> Strava erlaubt **eine** API-Application pro Konto. Wer sie schon für ein anderes Tool nutzt, kann
> sie trotzdem für FitBuddy verwenden: Client ID und Secret sind dieselben, nur die Callback Domain
> muss zu beiden Tools passen. Das ist bei `localhost` meistens der Fall.

## Schritt 2 — Application anlegen

Fülle das Formular so aus. Alle Felder sind Pflicht, ausser wo «optional» steht.

| Feld bei Strava | Was eintragen | Hinweis |
|---|---|---|
| **Application Name** | z. B. `FitBuddy` | Darf nicht «Strava» enthalten. Erscheint im Consent-Fenster und unter «My Apps». |
| **Category** | `Training` oder `Data Importer` | Reine Verwaltungsangabe, hat keinen Einfluss auf die Funktion. |
| **Club** | leer lassen | Optional. Nur für Club-Integrationen relevant. |
| **Website** | z. B. `https://github.com/fitbuddies-cas/fitbuddy` | Pflichtfeld, wird nicht geprüft. Jede gültige `https://`-URL funktioniert. |
| **Application Description** | z. B. `Private FitBuddy-Verbindung, nur für mein eigenes Konto` | Freitext, mindestens ein paar Wörter. |
| **Authorization Callback Domain** | **`localhost`** | **Exakt so, kleingeschrieben, ohne `http://`, ohne Pfad, ohne Port.** Siehe Schritt 3. |

Setze den Haken bei der Strava-API-Vereinbarung («I have read and agree to the API Agreement») und
klicke auf **Create**.

Nach dem Anlegen fragt Strava nach einem **App-Icon** («Upload an icon»). Lade das vorbereitete
quadratische Bild hoch. Erst danach zeigt Strava die vollständigen Daten der Application inklusive
Client Secret an.

## Schritt 3 — Authorization Callback Domain: `localhost`

Dieser Wert entscheidet, ob die Verbindung funktioniert.

**Warum `localhost`?** Nach der Freigabe schickt Strava den Browser an die Adresse
`fitbuddy://localhost/strava` zurück — dort fängt FitBuddy die Antwort ab. Strava prüft dabei
nicht das Schema (`fitbuddy://`), sondern nur den **Host** dieser Adresse, und der lautet
`localhost`. Strava führt `localhost` ausdrücklich als zulässigen Wert für Apps ohne eigene
Web-Domain; FitBuddy braucht keine Website und kein Backend.

**Was passiert bei einem anderen Wert?** Steht dort etwas anderes — `fitbuddy`, `fitbuddy.app`,
`www.strava.com`, `localhost/strava`, `http://localhost` oder ein Leerzeichen zu viel —, bricht
Strava den Login ab, bevor überhaupt die Freigabe-Seite erscheint. Im Fenster steht dann
**«invalid redirect_uri»** oder FitBuddy meldet «Strava did not send FitBuddy back correctly».

Du kannst die Callback Domain jederzeit auf strava.com ändern und in FitBuddy einfach erneut auf
**Connect** tippen. Die eingetragenen Client-Daten bleiben gültig.

## Schritt 4 — Client ID und Client Secret in FitBuddy eintragen

1. Auf strava.com siehst du jetzt unter «My API Application» die Felder **Client ID** (eine Zahl,
   z. B. `123456`) und **Client Secret** (klicke auf **Show**, ein 40-stelliger Hex-String).
2. Öffne in FitBuddy **Settings → Strava**.
3. Tippe auf **Enter API application credentials**.
4. Trage **CLIENT ID** und **CLIENT SECRET** ein. Am einfachsten kopierst du beide Werte per
   iCloud-Zwischenablage vom Mac aufs iPhone oder tippst sie ab — achte beim Secret auf jedes Zeichen.
5. Tippe auf **Save credentials**. FitBuddy speichert beide Werte im Keychain deines iPhones und
   springt zurück auf den Strava-Screen.

Das Client Secret wird danach nie mehr im Klartext angezeigt, nur noch maskiert («Stored application»).
Wer es später ersetzt, tippt erneut auf **API application credentials** und speichert ein neues Paar.

## Schritt 5 — Verbinden und Freigabe bestätigen

1. Tippe auf **Connect with Strava**. Es öffnet sich ein Strava-Login-Fenster.
2. Melde dich an, falls nötig.
3. Strava zeigt die Freigabe-Seite deiner Application. Lass **«View data about your private
   activities»** angehakt — das ist die Berechtigung `activity:read_all`, mit der FitBuddy auch
   Aktivitäten liest, die bei Strava auf «Only You» stehen. Ohne diesen Haken meldet FitBuddy
   «Activity access was not granted», und du musst neu verbinden.
4. Tippe auf **Authorize**. Das Fenster schliesst sich, FitBuddy zeigt **Connected** mit der
   Gültigkeitsdauer des aktuellen Access-Tokens.
5. Zurück im Dashboard: Beim nächsten Sync erscheinen deine Strava-Aktivitäten der letzten 90 Tage
   neben den Hevy-Workouts, mit Strava als Quelle markiert.

FitBuddy verlangt nur Lesezugriff auf Aktivitäten. Sie liest keine Profildaten und schreibt nie
etwas zu Strava zurück.

## Muss ich die Application bei Strava freischalten lassen?

**Nein.** Jede neue Strava-Application startet im «single-player mode»: Nur das Strava-Konto, das
die Application angelegt hat, kann sie autorisieren. Für FitBuddy ist das genau richtig, denn deine
Application verbindet ausschliesslich dein eigenes Konto. Beantrage also **keine** Freigabe für
mehr Nutzer — das ist ein Prüfprozess für öffentliche Apps und für dich ohne Nutzen.

Die Rate-Limits gelten pro Application: 200 Anfragen pro 15 Minuten, 2 000 pro Tag. Ein
FitBuddy-Sync braucht davon eine Handvoll; niemand ausser dir teilt sich dieses Kontingent.

## Wie geht es weiter?

- Der **Access-Token** ist sechs Stunden gültig. FitBuddy erneuert ihn beim Sync automatisch über
  den Refresh-Token — du merkst davon nichts.
- Strava gibt bei jeder Erneuerung einen **neuen Refresh-Token** aus; FitBuddy speichert ihn ab.
- Nur wenn auch der Refresh-Token nicht mehr gilt (Schritt «Renew your Strava connection» unten),
  musst du einmal neu verbinden.

## Troubleshooting

| Was du siehst | Ursache | Lösung |
|---|---|---|
| Im Strava-Fenster: **«invalid redirect_uri»** — oder in FitBuddy: **«Strava did not send FitBuddy back correctly»** | Die **Authorization Callback Domain** deiner Application ist nicht `localhost`. | Auf <https://www.strava.com/settings/api> die Callback Domain auf `localhost` setzen (Schritt 3), dann in FitBuddy **Try again**. |
| **«Strava rejected the application credentials»** | Client ID oder Client Secret passen zu keiner Application: Tippfehler, Zeichen vergessen, oder du hast das Secret auf strava.com neu generiert. | Auf strava.com **Show** beim Client Secret klicken und beide Werte vergleichen. In FitBuddy **Check the application credentials →** antippen und das Paar neu speichern, dann erneut verbinden. |
| **«Activity access was not granted»** | Beim Autorisieren war «View data about your private activities» abgewählt. | **Try again** und den Haken diesmal stehen lassen. |
| **«Strava access was declined»** | Du hast auf der Freigabe-Seite **Cancel** gewählt. | Nichts wurde gespeichert. **Connect with Strava** erneut antippen. |
| Dashboard-Hinweis **«Renew your Strava connection»**, Strava-Screen zeigt **«Connection expired»** | Der Refresh-Token ist ungültig: Du hast FitBuddy auf strava.com unter **Settings → My Apps** widerrufen, das Client Secret neu generiert, oder Strava hat den Token gesperrt. | Im Dashboard auf den Hinweis tippen (führt direkt zum Strava-Screen) und **Reconnect** antippen. Wurde das Secret neu generiert, vorher das neue Secret speichern. |
| **«Could not reach Strava»** | Kein Internet, DNS- oder Timeout-Problem. | Verbindung prüfen, dann **Try again**. |
| **«Strava is currently unavailable»** | Strava antwortet mit einem unerwarteten Fehler; nichts wurde abgelehnt. | Etwas später **Try again**. |
| **«Could not update the Strava connection»** | Der Keychain des iPhones hat den Zugriff verweigert. | iPhone entsperren und erneut versuchen. |
| Das Login-Fenster bleibt leer oder hängt | Strava-Seite lädt nicht, meist Netzwerk. | Fenster schliessen (gilt als Abbruch, nichts wird gespeichert) und erneut verbinden. |

### Verbindung trennen und neu aufbauen

Auf **Settings → Strava** tippt **Disconnect** die Verbindung weg. FitBuddy löscht dabei die
Access- und Refresh-Tokens, die gespeicherte Client ID samt Secret **und** alle zwischengespeicherten
Strava-Aktivitäten aus dem Dashboard. Die Application auf strava.com bleibt bestehen — für einen
Neuaufbau trägst du das Paar erneut ein (Schritt 4) und verbindest (Schritt 5).

Willst du FitBuddy auch auf Strava-Seite entziehen, geht das unter
**<https://www.strava.com/settings/apps>** («Revoke Access»). Danach meldet FitBuddy beim nächsten
Sync «Renew your Strava connection».

Auch **Settings → Delete all data** entfernt alle Strava-Daten vom Gerät.

## Datenschutz

- **Client Secret und Tokens verlassen dein iPhone nicht.** Sie liegen im iOS Keychain mit der
  Schutzklasse «nur auf diesem Gerät, wenn entsperrt», werden nicht in iCloud gesichert und nur für
  deine eigenen Anfragen an strava.com verwendet. Kein Server des FitBuddy-Teams ist beteiligt.
- **Strava als Datenempfänger** ist in der Datenschutzerklärung der App und im Einwilligungstext
  (Consent v2, #145) aufgeführt: Strava, Inc. (USA) ist die Quelle deiner Aktivitäten; FitBuddy
  überträgt an Strava nur die Autorisierungsanfrage deiner eigenen Application. Deine Aktivitäten
  fliessen in v0 nicht in die AI-Analyse ein.
- **Du bleibst Vertragspartner von Strava.** Mit dem Anlegen der Application akzeptierst du Stravas
  API Agreement selbst; das FitBuddy-Team hat keinen Zugriff auf deine Application oder deine Daten.
- **Löschen:** «Disconnect» oder «Delete all data» entfernt alles Strava-Bezogene vom Gerät; «Revoke
  Access» auf strava.com beendet die Berechtigung auf Strava-Seite.

## Für das Team: Gegentest

Die Anleitung gilt als abgenommen, wenn eine Person aus dem Team, die den Strava-Connector **nicht**
gebaut hat, nur mit diesem Dokument eine Application anlegt und FitBuddy erfolgreich verbindet
(Akzeptanzkriterium in #168). Abweichungen im Strava-Formular bitte direkt hier nachführen.
Screenshots gehören nach `docs/images/` und müssen Client ID und Client Secret geschwärzt zeigen.
