# Newral Sales CRM (Frappe CRM)

**https://salescrm.newral.in/crm**: one CRM for both of Newral's businesses:

| Brand | What it sells |
|---|---|
| **Newral** | Tech agency services: design, apps, SaaS, AI, DevOps |
| **Synappses** | White-label LMS for coaching institutes and educators |

Every lead and deal has a **Brand** field (Newral / Synappses) on the form, in the list and as a filter. A lead's brand carries over to its deal when converted. Save a list view per brand ("Newral leads", "Synappses leads") so each team sees only its own pipeline.

Stack: Frappe Framework v16 + [Frappe CRM](https://github.com/frappe/crm) + [frappe_whatsapp](https://github.com/shridarpatil/frappe_whatsapp) (WhatsApp Business Cloud API, one WhatsApp account per brand), MariaDB 11.8, Redis, nginx.

## How it's built (frontend and backend)

There's no separate frontend to host. Frappe is one application: the Python backend serves the API **and** the CRM's Vue frontend (compiled into the image) from the same domain. In Docker it runs as a few containers from one image:

```
host nginx + certbot (HTTPS) → nginx "frontend" → backend (gunicorn, API + pages)
                                                → websocket (live updates)
                               queue workers + scheduler (background jobs, WhatsApp webhooks, emails)
                               MariaDB + Redis
```

Host it on a VM (EC2, ACE Cloud, DigitalOcean…), not Vercel: Frappe needs long-running workers, a database and websockets.

## Production (salescrm.newral.in)

Server: 45.194.3.204, folder `~/CRM-SALES`, `.env` there holds the passwords (`ADMIN_PASSWORD` is the Administrator login). The CRM listens on 127.0.0.1:8090; the host's nginx (`deploy/nginx-crm.conf`) and certbot handle HTTPS.

**Update to the latest code:**
```bash
cd ~/CRM-SALES && git pull && sudo docker compose up -d
```

**Upgrade Frappe CRM** (new release): rebuild the image (`./build.sh`, ~15 min), then `sudo docker compose up -d && sudo docker compose exec backend bench --site all migrate`. If the server's GitHub downloads are slow, build on another machine and copy it over: `docker save newral-crm:16 | gzip -1 | ssh <server> 'gunzip | sudo docker load'`.

**Backups:** `sudo docker compose exec backend bench --site all backup --with-files` writes to `sites/<site>/private/backups`. Copy them off the server daily (cron + `aws s3 sync` or rclone).

### Fresh server

1. Ubuntu 22.04/24.04, 2+ vCPU, 4+ GB RAM. Open 22 (your IP only), 80, 443.
2. Install Docker: `curl -fsSL https://get.docker.com | sh`.
3. DNS: A record for the CRM hostname → the server.
4. ```bash
   git clone https://github.com/manwithcodes24/CRM-SALES.git && cd CRM-SALES
   cp .env.example .env   # SITES=<hostname>, strong DB_ROOT_PASSWORD / ADMIN_PASSWORD
   ./build.sh
   ```
5. HTTPS, either way:
   - **Server already runs nginx:** set `HTTP_PORT=8090`, `sudo docker compose up -d`, then follow the top of `deploy/nginx-crm.conf` (vhost + certbot).
   - **Nothing else on 80/443:** set `ACME_EMAIL`, then `docker compose -f compose.yml -f compose.https.yml up -d` (Caddy gets certificates itself).

## Run locally

```bash
cp .env.example .env      # SITES=crm.localhost, set the two passwords
./build.sh
docker compose up -d
docker compose logs -f create-sites   # wait for "Sites ready"
```
Open http://crm.localhost:8080/crm in Chrome and log in as `Administrator`.

## First-time setup

`scripts/setup_brands.py` runs automatically when the site is created. It adds the Brand field and the lead sources `LinkedIn`, `WhatsApp`, `Harvey (cold email)`, `Website signup`, `Brochure QR`, `Referral`, alongside Frappe's defaults (`Website`, `Web Form`, `Email`, …). Then, in the CRM:

1. **Users:** Settings → Members → invite the sales team ("Sales User"; "Sales Manager" for whoever assigns leads).
2. **Views:** on Leads, filter Brand = Newral → save as "Newral leads"; same for Synappses, and for Deals.
3. **Assignment rules:** Settings → Assignment rules, e.g. Brand = Synappses → the Synappses sales person.
4. **Email:** Settings → Email accounts. Connect each brand's inbox so replies are logged on the lead.
5. **WhatsApp:** see below.
6. **API key** for the website forms, Harvey and the bots: create an "integration" user, then generate its API key and secret (user settings → API Access).

## WhatsApp (one number per brand)

Each brand uses its own WhatsApp Business number on the **WhatsApp Business Cloud API** (Meta), not the WhatsApp Business phone app.

1. Meta Business Suite: verify the business. Add two WhatsApp Business numbers (Newral, Synappses).
2. developers.facebook.com: create an app, add WhatsApp, add both numbers, and create a **permanent** system-user access token.
3. In the CRM: WhatsApp Account → one per number (Phone Number ID, Business Account ID, App ID, token).
4. In Meta: webhook URL `https://salescrm.newral.in/api/method/frappe_whatsapp.utils.webhook.webhook`, with the verify token from the CRM. Subscribe to `messages`.
5. Create message templates in Meta for first messages; Meta requires approved templates outside the 24-hour reply window.

## How leads get in

Always send `brand` with a lead, so it lands in the right pipeline.

| Source | How | Status |
|---|---|---|
| Newral contact form | Website → CRM API, `brand: Newral` | To build (reuse `api/contact.js` in Newral_Website) |
| Synappses signup | Backend webhook → CRM API, `brand: Synappses` | To build (backend change) |
| Harvey (two instances) | Sync script: interested replies → CRM Lead, `brand` = that Harvey's brand | To build |
| WhatsApp | frappe_whatsapp webhook | Works once WhatsApp is set up |
| LinkedIn bots / manual | newral-bot and synappses-bot, or the sales team | Works now |

```bash
curl -X POST https://salescrm.newral.in/api/resource/CRM%20Lead \
  -H "Authorization: token API_KEY:API_SECRET" -H "Content-Type: application/json" \
  -d '{"first_name":"Asha","email":"asha@example.com","organization":"Example Labs","brand":"Newral","source":"Website"}'
```

## Files

```
apps.json                 apps baked into the image (CRM + WhatsApp)
build.sh                  builds the image
images/Containerfile      vendored from frappe/frappe_docker (MIT, see resources/LICENSE.frappe_docker)
resources/core/           its entrypoint scripts
compose.yml               the stack
compose.https.yml         add-on for servers with nothing on 80/443: Caddy + Let's Encrypt
Caddyfile
deploy/nginx-crm.conf     vhost for servers that already run nginx (production)
scripts/create-sites.sh   creates the site on first start
scripts/setup_brands.py   Brand field, form layouts, lead sources
.env.example
```
