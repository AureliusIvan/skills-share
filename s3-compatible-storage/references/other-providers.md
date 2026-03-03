# Other S3-Compatible Providers

## Table of Contents

1. [MinIO](#minio)
2. [Backblaze B2](#backblaze-b2)
3. [DigitalOcean Spaces](#digitalocean-spaces)
4. [Wasabi](#wasabi)
5. [Other providers quick reference](#other-providers-quick-reference)
6. [rclone configuration examples](#rclone-configuration-examples)

## MinIO

### Overview

Open-source, self-hosted S3-compatible object storage. High-performance, written in Go. Common for local development, on-premises, and private cloud.

### Endpoint

Self-hosted, typically: `http://localhost:9000` or `https://minio.yourdomain.com:9000`

### AWS CLI setup

```bash
aws configure --profile minio
# Access Key: minioadmin (default) or your configured key
# Secret Key: minioadmin (default) or your configured key
# Region: us-east-1 (or any string, MinIO ignores it)
# Output: json

# Force path-style addressing (required for MinIO)
aws configure set profile.minio.s3.addressing_style path
```

Usage:
```bash
aws --profile minio --endpoint-url http://localhost:9000 s3 ls
aws --profile minio --endpoint-url http://localhost:9000 s3 mb s3://test-bucket
aws --profile minio --endpoint-url http://localhost:9000 s3 cp file.txt s3://test-bucket/
```

### MinIO Client (mc)

mc is MinIO's native CLI tool, optimized for S3-compatible storage:

```bash
# Install
# Linux: wget https://dl.min.io/client/mc/release/linux-amd64/mc && chmod +x mc
# Mac: brew install minio/stable/mc
# Or: go install github.com/minio/mc@latest

# Add an alias
mc alias set local http://localhost:9000 minioadmin minioadmin
mc alias set mycloud https://minio.example.com ACCESS_KEY SECRET_KEY

# Bucket operations
mc mb local/my-bucket
mc ls local
mc rb local/my-bucket --force

# Object operations
mc cp file.txt local/my-bucket/
mc cp local/my-bucket/file.txt ./downloaded.txt
mc cat local/my-bucket/file.txt           # Print to stdout
mc stat local/my-bucket/file.txt          # Object metadata

# Mirror (sync)
mc mirror ./local-dir local/my-bucket/prefix/
mc mirror local/my-bucket/ ./backup/ --overwrite

# Admin (MinIO servers only)
mc admin info local
mc admin user list local
mc admin policy list local
```

### rclone config

```ini
[minio]
type = s3
provider = Minio
access_key_id = minioadmin
secret_access_key = minioadmin
endpoint = http://localhost:9000
```

## Backblaze B2

### Overview

Very affordable storage at $0.006/GB/month. Free egress up to 3x stored data volume per month. S3-compatible API alongside native B2 API.

### Endpoint

`https://s3.{region}.backblazeb2.com`

Find your region in the B2 dashboard (e.g., `us-west-004`, `eu-central-003`).

### AWS CLI setup

```bash
aws configure --profile b2
# Access Key: B2 application key ID
# Secret Key: B2 application key
# Region: us-west-004 (your bucket's region)
# Output: json
```

Usage:
```bash
EP="https://s3.us-west-004.backblazeb2.com"
aws --profile b2 --endpoint-url $EP s3 ls
aws --profile b2 --endpoint-url $EP s3 cp file.txt s3://my-bucket/
aws --profile b2 --endpoint-url $EP s3 sync ./dir s3://my-bucket/dir/
```

### rclone config

```ini
[b2]
type = s3
provider = Backblaze
access_key_id = {KEY_ID}
secret_access_key = {APP_KEY}
endpoint = s3.us-west-004.backblazeb2.com
region = us-west-004
```

### B2-specific notes

- Bucket names are globally unique (like AWS)
- Supports lifecycle rules for auto-deletion
- File versioning supported (called "file versions")
- CORS supported via S3 API
- Large file threshold: 100MB (parts must be >= 5MB)
- Free egress: 3x monthly stored data (then $0.01/GB)

## DigitalOcean Spaces

### Overview

Simple object storage with built-in CDN. Flat pricing: $5/month includes 250GB storage + 1TB transfer.

### Endpoint

`https://{region}.digitaloceanspaces.com`

Regions: `nyc3`, `sfo3`, `ams3`, `sgp1`, `fra1`, `syd1`

### AWS CLI setup

```bash
aws configure --profile do-spaces
# Access Key: Spaces access key (from API > Tokens/Keys)
# Secret Key: Spaces secret key
# Region: nyc3
# Output: json
```

Usage:
```bash
EP="https://nyc3.digitaloceanspaces.com"
aws --profile do-spaces --endpoint-url $EP s3 ls
aws --profile do-spaces --endpoint-url $EP s3 cp file.txt s3://my-space/
```

### rclone config

```ini
[do-spaces]
type = s3
provider = DigitalOcean
access_key_id = {KEY}
secret_access_key = {SECRET}
endpoint = nyc3.digitaloceanspaces.com
region = nyc3
acl = private
```

### Spaces-specific notes

- Called "Spaces" not "buckets" in DO terminology (but S3 API uses bucket terminology)
- Built-in CDN toggle (edge caching)
- Supports CORS configuration
- Max object size: 5 GB (single upload), 5 TB (multipart)
- Virtual-hosted-style URLs: `https://{space-name}.{region}.digitaloceanspaces.com`
- CDN URL: `https://{space-name}.{region}.cdn.digitaloceanspaces.com`

## Wasabi

### Overview

Hot cloud storage with no egress fees. Claims up to 80% cheaper than AWS S3. All data is "hot" (no storage tiers).

### Endpoint

`https://s3.{region}.wasabisys.com`

Regions: `us-east-1`, `us-east-2`, `us-central-1`, `us-west-1`, `eu-central-1`, `eu-central-2`, `eu-west-1`, `eu-west-2`, `ap-northeast-1`, `ap-northeast-2`, `ap-southeast-1`, `ap-southeast-2`

### AWS CLI setup

```bash
aws configure --profile wasabi
# Access Key: Wasabi access key
# Secret Key: Wasabi secret key
# Region: us-east-1
# Output: json
```

Usage:
```bash
EP="https://s3.us-east-1.wasabisys.com"
aws --profile wasabi --endpoint-url $EP s3 ls
aws --profile wasabi --endpoint-url $EP s3 sync ./dir s3://my-bucket/
```

### rclone config

```ini
[wasabi]
type = s3
provider = Wasabi
access_key_id = {KEY}
secret_access_key = {SECRET}
endpoint = s3.us-east-1.wasabisys.com
region = us-east-1
```

### Wasabi-specific notes

- No egress fees
- No API request fees
- Minimum storage duration: 90 days (billed for 90 days even if deleted sooner)
- Supports versioning, lifecycle rules, CORS
- Supports object lock / immutability (compliance and governance modes)
- 11 nines (99.999999999%) durability

## Other providers quick reference

| Provider | Endpoint | Region | Notes |
|----------|----------|--------|-------|
| **Scaleway** | `s3.{region}.scw.cloud` | `fr-par`, `nl-ams`, `pl-waw` | European cloud |
| **Linode/Akamai** | `{region}.linodeobjects.com` | `us-east-1`, `eu-central-1`, etc. | Part of Akamai |
| **Vultr** | `{region}.vultrobjects.com` | `ewr1`, `sgp1`, `ams1`, etc. | Global VPS provider |
| **Hetzner** | Hetzner Object Storage endpoints | European regions | Affordable European hosting |
| **Tigris** (Fly.io) | `fly.storage.tigris.dev` | `auto` | Globally distributed |
| **Filebase** | `s3.filebase.com` | Not applicable | Decentralized backend (IPFS/Sia) |
| **Supabase** | `{project}.supabase.co/storage/v1/s3` | Project-dependent | Postgres-centric platform |
| **Oracle Cloud** | `{namespace}.compat.objectstorage.{region}.oraclecloud.com` | OCI regions | Enterprise |
| **IDrive e2** | IDrive endpoints | Various | Budget option |

## rclone configuration examples

rclone supports 60+ S3-compatible providers natively. Use `rclone config` for interactive setup, or add entries to `~/.config/rclone/rclone.conf`.

### Generic S3-compatible provider

For any provider not explicitly listed:

```ini
[my-provider]
type = s3
provider = Other
access_key_id = {KEY}
secret_access_key = {SECRET}
endpoint = https://s3.example.com
region = us-east-1
acl = private
force_path_style = true
```

### Key rclone settings for S3-compatible storage

| Setting | Description |
|---------|-------------|
| `provider` | Named provider (AWS, Cloudflare, Minio, Wasabi, etc.) or `Other` |
| `endpoint` | Custom S3 endpoint URL |
| `region` | Region string (set to `auto` or empty if not applicable) |
| `force_path_style` | `true` for most self-hosted/non-AWS providers |
| `no_check_bucket` | `true` if token lacks bucket-level admin permissions |
| `chunk_size` | Multipart chunk size (default 5M, increase for large files) |
| `upload_cutoff` | Size above which multipart upload is used |
| `disable_checksum` | Some providers don't support checksums |
