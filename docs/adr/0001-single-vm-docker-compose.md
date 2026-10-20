# Single VM with Docker Compose

n8n, Postgres and Traefik run as Docker Compose containers on one Scaleway Instance, rather than on Scaleway Managed Database, Serverless Containers or Kapsule. This is a personal Setup: one VM keeps the monthly cost low, leaves a single thing to operate and back up, and gives full control over versions and configuration. In exchange, we give up managed high availability and automatic database backups, and n8n runs in regular execution mode (no queue mode with workers).
