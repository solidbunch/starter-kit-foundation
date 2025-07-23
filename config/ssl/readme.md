# SSL Configuration

For setup SSL put your certificate files here. Create `live/<your-app-domain.com>` folder 

And put your SSL files with names `live/<your-app-domain.com>/fullchain.pem` and `live<your-app-domain.com>/privkey.pem`

Change var `APP_PROTOCOL=https` in your `.env.type.[environment_type]`

Restart containers
