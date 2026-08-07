# SSL Configuration

For setup SSL put your certificate files here. Create `live/<your-app-domain.com>` folder 

And put your SSL files with names `live/<your-app-domain.com>/fullchain.pem` and `live<your-app-domain.com>/privkey.pem`

Change var `APP_PROTOCOL=https` in your `.env.type.[environment_type]`

Restart containers

## Local development (mkcert)

For a local domain (e.g. `.loc`) where Let's Encrypt can't issue a certificate, run
`make local-cert` instead of placing files here by hand — it generates a locally-trusted
certificate via [`mkcert`](https://github.com/FiloSottile/mkcert) and drops it in the right place
for your active mode (this folder in single-instance/nginx mode, `kit-modules/proxy/certs/local/`
in multi-instance/Traefik mode). See `.claude/rules/config.md` for the full workflow.
