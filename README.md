# n8n on Scaleway

A personal, self-hosted [n8n](https://n8n.io) on a single Scaleway VM, with Postgres, Traefik (HTTPS via Let's Encrypt) and daily Backups to Object Storage.

It is rolled out in two stages:

1. **Infrastructure** (`infrastructure/`, OpenTofu): VM, IPs, firewall, Backup bucket and a write-only backup key. The VM comes up hardened, with a `deploy` user.
2. **Provisioning** (`provisioning/`, Ansible): secrets onto the VM, then Traefik, Postgres and n8n as Docker Compose projects, an optional Dump import, and the Backup timer.

Terms such as Setup, Secrets file and Dump import are defined in [GLOSSARY.md](GLOSSARY.md). The design is in [docs/SPEC.md](docs/SPEC.md), and the main architectural choice in [ADR 0001](docs/adr/0001-single-vm-docker-compose.md).

## Prerequisites

- A Scaleway project with an SSH key registered in IAM.
- An existing State bucket (Object Storage), in the same region as the Setup. Keep it private: the state holds the backup key's secret.
- The `scw` CLI, configured. The Scaleway provider reads `~/.config/scw/config.yaml`.
- A Scaleway API key for the State bucket, as `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` in the Secrets file. The backend talks S3 to Scaleway Object Storage; AWS is not involved.
- OpenTofu and Ansible. With [mise](https://mise.jdx.dev), `mise install` installs the pinned versions from `mise.toml`.
- A domain where you can create A and AAAA records.

## Configure

Two local files, both gitignored:

```sh
cp .env.example .env                                              # Secrets file
cp infrastructure/terraform.tfvars.example infrastructure/terraform.tfvars
```

**`.env`** holds every secret, for both stages. Notes on the less obvious keys:

| Key | Notes |
|---|---|
| `TF_VAR_operator_access_key` | Your own access key (`scw config get access-key`). Keeps you in the Backup bucket policy. |
| `N8N_ENCRYPTION_KEY` | Always set it yourself. It must match the key of any Dump you import, or saved credentials can't be decrypted. Generate a new one with `openssl rand -hex 32`. |
| `EDITOR_ALLOWLIST` | Comma-separated CIDRs that may reach the editor and API. `0.0.0.0/0,::/0` allows everyone. Webhooks and forms are always public. |
| `BACKUP_ACCESS_KEY`, `BACKUP_SECRET_KEY` | Leave empty for now; they come out of the Infrastructure stage. |

Values may be quoted, but must not contain a single quote. The playbook checks this, and lists any missing key, before it changes anything.

**`terraform.tfvars`** holds the Infrastructure settings: State bucket, project, name prefix, SSH key name and SSH allowlist. See [variables.tf](infrastructure/variables.tf) for every option and its default.

**`provisioning/group_vars/all.yml`** holds the non-secret Provisioning settings: remote directory, backup time (default `03:00`, in `GENERIC_TIMEZONE`) and the pinned rclone image.

## Run

### 1. Infrastructure

Load the Secrets file into your shell, then run OpenTofu:

```sh
set -a; source .env; set +a      # or the oh-my-zsh dotenv plugin, which loads .env when you cd into the repo root

cd infrastructure
tofu init                        # state_bucket and name_prefix come from terraform.tfvars
tofu apply
tofu output next_steps
```

`tofu apply` also writes `provisioning/inventory.ini`, with the VM address and the Backup bucket.

### 2. Between the stages

1. Create an **A** record and an **AAAA** record for your domain, pointing at `tofu output ipv4_address` / `ipv6_address`.
2. Copy the backup key into `.env`:
   ```sh
   tofu output -raw backup_access_key   # -> BACKUP_ACCESS_KEY
   tofu output -raw backup_secret_key   # -> BACKUP_SECRET_KEY
   ```

Wait until the domain resolves to the VM: Let's Encrypt can only issue the certificate then.

### 3. Provisioning

Run from `provisioning/`. Ansible reads `.env` itself, so the shell doesn't need it loaded.

```sh
cd provisioning
ansible-playbook site.yml
```

n8n is then live at `https://<your domain>`, and HTTP redirects to HTTPS. Running the playbook again is always safe: it only changes what differs, and never imports a Dump into a database that has data.

## Dump import

To move an existing n8n install over, import a Dump on the **first** run:

```sh
# On the old install (custom format, the same format the Backups use):
pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc > n8n.dump

# Put it in provisioning/dumps/ (gitignored), then:
ansible-playbook site.yml -e dump_file=dumps/n8n.dump
```

- **Empty database only.** The import runs only when the database has no tables, and it runs before n8n's first start, because n8n creates its tables when it starts. If the database already has data, the playbook skips the import with a warning.
- **Same encryption key.** `N8N_ENCRYPTION_KEY` must be the old install's key, or saved credentials won't decrypt.
- The import is a single transaction: if it fails, the database stays empty and you can run it again. The Dump is removed from the VM afterwards.

## Backups

A systemd timer on the VM dumps the database daily and uploads it to the Backup bucket as `n8n-<UTC timestamp>.dump`. The bucket deletes Backups after `backup_retention_days` (default 30).

The backup key can only upload. Someone who takes over the VM cannot read or delete existing Backups with it.

```sh
ssh deploy@<ip>
systemctl list-timers n8n-backup.timer      # next run
sudo systemctl start n8n-backup             # back up now
journalctl -u n8n-backup -n 20              # result
```

### Restoring from a Backup

1. Download a Backup with your own credentials (the backup key cannot read). Use the Scaleway console, or rclone:
   ```sh
   export RCLONE_CONFIG_SCW_TYPE=s3 RCLONE_CONFIG_SCW_PROVIDER=Scaleway \
     RCLONE_CONFIG_SCW_REGION=<region> RCLONE_CONFIG_SCW_ENDPOINT=s3.<region>.scw.cloud \
     RCLONE_CONFIG_SCW_ACCESS_KEY_ID=$(scw config get access-key) \
     RCLONE_CONFIG_SCW_SECRET_ACCESS_KEY=$(scw config get secret-key)
   # <region> and <backup bucket>: tofu output backup_region / backup_bucket
   rclone ls scw:<backup bucket>
   rclone copyto scw:<backup bucket>/n8n-<timestamp>.dump provisioning/dumps/restore.dump
   ```
2. Import it with a [Dump import](#dump-import) into an empty database, with the same `N8N_ENCRYPTION_KEY`:
   - **Fresh Setup:** run the playbook with `-e dump_file=dumps/restore.dump`.
   - **Existing VM:** empty the database first. This **deletes all current n8n data**, so take a Backup first if you might need it:
     ```sh
     ssh deploy@<ip> 'cd /opt/compose/n8n && docker compose down && docker volume rm n8n_postgres_data'
     ansible-playbook site.yml -e dump_file=dumps/restore.dump
     ```

### Backup key expiry

Scaleway gives the backup key a one-year expiry, and Backups fail with 403 after it expires. Check the date with `scw iam api-key get $(tofu output -raw backup_access_key)`, and rotate the key before it expires:

```sh
cd infrastructure
tofu apply -replace=scaleway_iam_api_key.backup
# copy the new backup_access_key / backup_secret_key into .env, then:
cd ../provisioning && ansible-playbook site.yml
```

## Good to know

- **Hardening happens on first boot only.** cloud-init creates the `deploy` user, turns off root and password login over SSH, and enables unattended upgrades, once. Changing `cloud-init.yaml.tftpl` later does not touch a running VM; rebuild it instead.
- **The VM is protected against replacement.** It holds the live database, so `instance.tf` sets `prevent_destroy = true` and ignores changes to the image and cloud-init. To rebuild on purpose:
  1. Take a Backup and download it (see [Restoring from a Backup](#restoring-from-a-backup)).
  2. Set `prevent_destroy = false` in `infrastructure/instance.tf`.
  3. Run `tofu apply -replace=scaleway_instance_server.n8n`, then set `prevent_destroy` back to `true`. The flexible IPs survive, so DNS stays valid.
  4. The VM has a new SSH host key: run `ssh-keygen -R <ip>`.
  5. Run the playbook with `-e dump_file=dumps/restore.dump`.
- **Keep the State bucket private.** The OpenTofu state contains the backup key's secret.
- **Versions are pinned** (n8n, Postgres, Traefik and rclone images, plus the tools in `mise.toml`). Upgrade on purpose: change the tag, then run the playbook again.
- **Editor allowlist:** with `EDITOR_ALLOWLIST` narrowed, the editor and API return 403 from other addresses, while `/webhook...` and `/form...` paths stay public.

## Repository layout

```
infrastructure/          OpenTofu (Infrastructure stage)
provisioning/            Ansible (Provisioning stage)
  site.yml                 the playbook
  group_vars/all.yml       Settings
  files/compose/           compose files for n8n and Traefik, copied to the VM
  templates/               secrets files and backup units rendered onto the VM
  dumps/                   local Dumps (gitignored)
  inventory.ini            generated by OpenTofu (gitignored)
.env.example             template of the Secrets file
```

## License

See [LICENSE](LICENSE).
