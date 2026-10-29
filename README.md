# Newral CRM (Frappe CRM)

Two separate CRMs, one server:

| Brand | Production URL | Local URL |
|---|---|---|
| Newral (tech agency) | https://crm.newral.in | http://crm-newral.localhost:8080 |
| Synappses (white-label LMS) | https://crm.synappses.in | http://crm-synappses.localhost:8080 |

Each is its own Frappe site with its own database, users, leads, deals, pipeline and WhatsApp number. They share only the server.

Stack: Frappe Framework v16 + [Frappe CRM](https://github.com/frappe/crm) + [frappe_whatsapp](https://github.com/shridarpatil/frappe_whatsapp) (WhatsApp Business Cloud API), MariaDB 11.8, Redis, nginx, and Caddy for HTTPS in production.

## How it's built (frontend and backend)

There's no separate frontend to host. Frappe is one application: the Python backend serves the API **and** the CRM's Vue frontend (compiled into the image) from the same domain. In Docker it runs as a few containers from one image:

```
Caddy (HTTPS) → nginx "frontend" → backend (gunicorn, API + pages)
                                 → websocket (live updates)
                 queue workers + scheduler (background jobs, WhatsApp webhooks, emails)
                 MariaDB + Redis
```

**Host it on a VM (AWS EC2, Lightsail, DigitalOcean, Hetzner), not Vercel.** Vercel runs short-lived serverless functions; Frappe needs long-running workers, a database and websockets.

Recommended size: EC2 **t3.medium** (2 vCPU, 4 GB RAM) with 40 GB gp3 disk for both sites. Use t3.large if the team grows past ~15 users.

## Run locally

Needs Docker Desktop.

```bash
cp .env.example .env      # set DB_ROOT_PASSWORD and ADMIN_PASSWORD
./build.sh                # ~15 min the first time
docker compose up -d
docker compose logs -f create-sites   # wait for "Sites ready"
```

Open http://crm-newral.localhost:8080/crm and http://crm-synappses.localhost:8080/crm in Chrome (`*.localhost` needs no hosts-file entry). Log in as `Administrator` with `ADMIN_PASSWORD`.

## Deploy on EC2

1. Launch Ubuntu 24.04 on t3.medium. Security group: open 22 (your IP only), 80 and 443.
2. Install Docker: `curl -fsSL https://get.docker.com | sh && sudo usermod -aG docker $USER` (log out and back in).
3. DNS: A records `crm.newral.in` and `crm.synappses.in` → the instance's Elastic IP.
4. On the server:
   ```bash
   git clone https://github.com/manwithcodes24/CRM-SALES.git && cd CRM-SALES
   cp .env.example .env
   # set NEWRAL_SITE=crm.newral.in, SYNAPPSES_SITE=crm.synappses.in,
   # strong DB_ROOT_PASSWORD / ADMIN_PASSWORD, ACME_EMAIL
   ./build.sh
   docker compose -f compose.yml -f compose.https.yml up -d
   ```
5. Open https://crm.newral.in/crm. Caddy gets the certificates automatically on first visit.

### On a server that already runs nginx (e.g. the Synappses live-class server)

Don't use `compose.https.yml` there: the host's nginx already owns 80/443. Instead:

1. In `.env`: `HTTP_PORT=8090` (8080 is taken by Jitsi's video bridge), the production site names and passwords.
2. `./build.sh && docker compose up -d` (the CRM listens on 127.0.0.1:8090 only).
3. Add the vhost and certificates as described at the top of `deploy/nginx-crm.conf`.
4. DNS: A records `crm.newral.in` and `crm.synappses.in` → the server. If `*.synappses.in` is a wildcard for creator storefronts, the explicit `crm` record overrides it. Also reserve `crm` so no creator can claim that subdomain.

**Upgrade** (new CRM release): `git pull && ./build.sh && docker compose -f compose.yml -f compose.https.yml up -d && docker compose exec backend bench --site all migrate`

**Backups:** `docker compose exec backend bench --site all backup --with-files` writes to `sites/<site>/private/backups`. Copy them off the server daily (cron + `aws s3 sync`).

## First-time setup per CRM

Do each step on **both** sites.

1. **Users:** Settings → Members → invite the sales team. Give each person the "Sales User" role (or "Sales Manager" for whoever assigns leads).
2. **Lead sources:** add `Website form`, `Website signup`, `WhatsApp`, `Harvey (cold email)`, `LinkedIn`, `Referral`, `Brochure QR`.
3. **Lead statuses** (pipeline): New → Contacted → Qualified → Demo/Call booked → Proposal → Won / Lost.
4. **Email:** Settings → Email accounts. Connect the brand's inbox so replies are logged on the lead.
5. **WhatsApp:** see below.
6. **API key** for the website forms and the Harvey sync: Administrator → My Settings → API Access → Generate keys. Create a dedicated "integration" user for this, not a person's account.

## WhatsApp (per brand)

Each brand needs its own WhatsApp Business number on the **WhatsApp Business Cloud API** (Meta), not the WhatsApp Business phone app.

1. Meta Business Suite → verify the business (Newral). Synappses can sit under the same Business Manager with its own WhatsApp Business Account and number.
2. developers.facebook.com → create an app → add WhatsApp → add the phone number → create a **permanent** system-user access token.
3. In the CRM: WhatsApp Settings → enable, then paste the Phone Number ID, Business Account ID, App ID and token.
4. Back in Meta: set the webhook URL to `https://crm.newral.in/api/method/frappe_whatsapp.utils.webhook.webhook` (and the Synappses one), using the verify token from WhatsApp Settings. Subscribe to `messages`.
5. Create message templates in Meta for the first message you send to someone (Meta requires approved templates outside the 24-hour reply window).

Incoming WhatsApp messages then show up on the lead, and the team replies from inside the CRM.

## How leads get in

| Source | How | Status |
|---|---|---|
| Newral contact form | Website → `POST /api/resource/CRM Lead` on crm.newral.in | To build (reuse `api/contact.js` in Newral_Website) |
| Synappses signup | Backend webhook → crm.synappses.in | To build (backend change) |
| Harvey replies | Sync script: interested replies → CRM Lead with source "Harvey (cold email)" | To build (`sync/harvey_to_crm.py`) |
| WhatsApp | frappe_whatsapp webhook | Works once WhatsApp is set up |
| Manual / LinkedIn | Sales team adds leads, or the bot creates them | Works now |

Example API call (integration user's key):
```bash
curl -X POST https://crm.newral.in/api/resource/CRM%20Lead \
  -H "Authorization: token API_KEY:API_SECRET" -H "Content-Type: application/json" \
  -d '{"first_name":"Asha","email":"asha@example.com","organization":"Example Labs","source":"Website form"}'
```

## Files

```
apps.json            apps baked into the image (CRM + WhatsApp)
build.sh             builds the image
images/Containerfile vendored from frappe/frappe_docker (MIT, see resources/LICENSE.frappe_docker)
resources/core/      its entrypoint scripts
compose.yml          the stack (both sites)
compose.https.yml    production add-on: Caddy + Let's Encrypt
Caddyfile
scripts/create-sites.sh   creates the sites on first start
.env.example
```
