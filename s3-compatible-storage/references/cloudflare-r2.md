# Cloudflare R2 Reference

## Table of Contents

1. [Overview](#overview)
2. [Credentials setup](#credentials-setup)
3. [Using AWS CLI with R2](#using-aws-cli-with-r2)
4. [Using Wrangler CLI](#using-wrangler-cli)
5. [Using rclone](#using-rclone)
6. [CORS configuration](#cors-configuration)
7. [Public access and custom domains](#public-access-and-custom-domains)
8. [Presigned URLs](#presigned-urls)
9. [Lifecycle rules](#lifecycle-rules)
10. [S3 API compatibility notes](#s3-api-compatibility-notes)
11. [Pricing](#pricing)

## Overview

Cloudflare R2 is an S3-compatible object storage with **zero egress fees**. Key characteristics:
- S3-compatible API (most operations work out of the box)
- Region is always `auto`
- Path-style addressing only (no virtual-hosted-style)
- All data encrypted at rest by default (no manual encryption config needed)
- Two storage classes: Standard and Infrequent Access
- Max object size: 5 TB via multipart upload

## Credentials setup

### Get your Account ID

Find it in the Cloudflare dashboard: **R2 Overview > Account Details**. It's a 32-character hex string, also visible in your dashboard URL.

### Create API token

1. Go to **Storage & databases > R2 Object Storage > Overview**
2. Click **Manage R2 API Tokens**
3. Click **Create API token**
4. Choose permissions:
   - **Object Read & Write** for typical use
   - **Admin Read & Write** for full access (bucket creation/deletion)
5. Scope to specific buckets or all buckets
6. Copy the **Access Key ID** and **Secret Access Key** immediately (shown only once)

### Required information

| Field | Value |
|-------|-------|
| Endpoint URL | `https://{ACCOUNT_ID}.r2.cloudflarestorage.com` |
| Region | `auto` (or `us-east-1` as alias) |
| Access Key ID | From API token creation |
| Secret Access Key | From API token creation |

## Using AWS CLI with R2

### Configure

```bash
aws configure --profile r2
# Access Key ID: your R2 access key
# Secret Access Key: your R2 secret key
# Region: auto
# Output: json
```

Add the endpoint to `~/.aws/config`:
```ini
[profile r2]
region = auto
output = json
endpoint_url = https://{ACCOUNT_ID}.r2.cloudflarestorage.com
```

Or use environment variable:
```bash
export AWS_ENDPOINT_URL=https://{ACCOUNT_ID}.r2.cloudflarestorage.com
export AWS_PROFILE=r2
```

### Common commands

All commands need `--endpoint-url` unless set in config/env:

```bash
EP="https://{ACCOUNT_ID}.r2.cloudflarestorage.com"

# List buckets
aws s3api list-buckets --endpoint-url $EP --profile r2

# List objects
aws s3api list-objects-v2 --endpoint-url $EP --bucket my-bucket --profile r2

# Upload
aws s3 cp ./file.txt s3://my-bucket/file.txt --endpoint-url $EP --profile r2

# Download
aws s3 cp s3://my-bucket/file.txt ./file.txt --endpoint-url $EP --profile r2

# Sync
aws s3 sync ./dir s3://my-bucket/prefix/ --endpoint-url $EP --profile r2

# Presigned URL
aws s3 presign s3://my-bucket/file.txt --endpoint-url $EP --expires-in 3600 --profile r2
```

## Using Wrangler CLI

Wrangler is Cloudflare's native CLI tool. Install and auth:

```bash
npm install -g wrangler
wrangler login
```

### Bucket commands

```bash
wrangler r2 bucket create my-bucket
wrangler r2 bucket create my-bucket --storage-class InfrequentAccess
wrangler r2 bucket list
wrangler r2 bucket info my-bucket
wrangler r2 bucket delete my-bucket
```

### Object commands

```bash
wrangler r2 object put my-bucket/key --file ./local-file.txt
wrangler r2 object put my-bucket/key --file ./image.png --content-type image/png
wrangler r2 object get my-bucket/key
wrangler r2 object delete my-bucket/key
```

### Public access

```bash
# Toggle r2.dev subdomain (development only, rate-limited)
wrangler r2 bucket dev-url enable my-bucket
wrangler r2 bucket dev-url disable my-bucket

# Custom domain management
wrangler r2 bucket domain add my-bucket --domain files.example.com
wrangler r2 bucket domain list my-bucket
wrangler r2 bucket domain remove my-bucket --domain files.example.com
```

### CORS via Wrangler

```bash
# Set CORS from JSON file
wrangler r2 bucket cors set my-bucket --file cors.json

# View CORS
wrangler r2 bucket cors list my-bucket

# Delete CORS
wrangler r2 bucket cors delete my-bucket
```

### Lifecycle rules

```bash
wrangler r2 bucket lifecycle add my-bucket     # Interactive
wrangler r2 bucket lifecycle list my-bucket
wrangler r2 bucket lifecycle remove my-bucket
```

### Event notifications

```bash
wrangler r2 bucket notification create my-bucket  # Set up notifications
wrangler r2 bucket notification list my-bucket
wrangler r2 bucket notification delete my-bucket
```

### Sippy (incremental migration)

```bash
# Enable migration from AWS S3
wrangler r2 bucket sippy enable my-bucket

# Disable
wrangler r2 bucket sippy disable my-bucket
```

## Using rclone

### Configuration

Add to `~/.config/rclone/rclone.conf`:

```ini
[r2]
type = s3
provider = Cloudflare
access_key_id = {ACCESS_KEY_ID}
secret_access_key = {SECRET_ACCESS_KEY}
endpoint = https://{ACCOUNT_ID}.r2.cloudflarestorage.com
acl = private
no_check_bucket = true
```

Set `no_check_bucket = true` if using a token with object-level (not admin) permissions.

### Common commands

```bash
rclone lsd r2:                        # List buckets
rclone ls r2:my-bucket                # List objects
rclone copy ./file.txt r2:my-bucket/  # Upload
rclone copy r2:my-bucket/file.txt ./  # Download
rclone sync ./dir r2:my-bucket/dir/   # Sync

# Large file with explicit multipart settings
rclone copy large.mp4 r2:my-bucket/ --s3-upload-cutoff=100M --s3-chunk-size=100M

# Presigned URL
rclone link r2:my-bucket/file.txt --expire 1h
```

## CORS configuration

### JSON format for CORS rules

Create a `cors.json` file:

```json
[
  {
    "AllowedOrigins": ["https://example.com"],
    "AllowedMethods": ["GET", "PUT", "HEAD"],
    "AllowedHeaders": ["Content-Type", "Range"],
    "ExposeHeaders": ["ETag", "Content-Length"],
    "MaxAgeSeconds": 3600
  }
]
```

Apply with Wrangler:
```bash
wrangler r2 bucket cors set my-bucket --file cors.json
```

Or with AWS CLI:
```bash
aws s3api put-bucket-cors --bucket my-bucket --endpoint-url $EP \
  --cors-configuration '{"CORSRules": [...]}'
```

### R2 CORS specifics

- `AllowedOrigins` must use `scheme://host[:port]` format (no paths)
- R2 does **not** support wildcard `AllowedHeaders` -- list each header explicitly
- Changes can take up to 30 seconds to propagate
- `MaxAgeSeconds` max is 86,400 (24 hours)

## Public access and custom domains

### r2.dev subdomain

- Quick toggle for development/testing
- Rate-limited, not for production
- Enable: `wrangler r2 bucket dev-url enable my-bucket`

### Custom domain

- Connects your domain to the R2 bucket
- Enables Cloudflare Cache, WAF, Bot Management, Zero Trust
- Requires the domain to be on Cloudflare

**Security note**: If using WAF/Access on custom domain, disable r2.dev subdomain to prevent bypass.

**Limitation**: Public buckets don't support listing at the domain root.

## Presigned URLs

- Generated client-side using SigV4 (no API call needed)
- Support GET, HEAD, PUT, DELETE
- Expiry range: 1 second to 7 days (604,800 seconds)
- POST (multipart form uploads) is **not supported**
- Only work with the S3 API domain, not custom domains
- Configure CORS separately if accessing from a browser

## Lifecycle rules

R2 supports lifecycle rules for:
- **Expiration**: Auto-delete objects after N days
- **Transition**: Move objects to Infrequent Access storage class
- **Abort incomplete multipart uploads**: Clean up after N days

Configure via Wrangler or S3 API (`PutBucketLifecycleConfiguration`).

## S3 API compatibility notes

### Supported operations

Bucket: ListBuckets, HeadBucket, CreateBucket, DeleteBucket, GetBucketCors, PutBucketCors, DeleteBucketCors, GetBucketLifecycleConfiguration, PutBucketLifecycleConfiguration, GetBucketLocation, GetBucketEncryption

Object: HeadObject, GetObject, PutObject, DeleteObject, DeleteObjects, CopyObject, ListObjects, ListObjectsV2, full multipart upload support

### NOT supported

| Feature | Notes |
|---------|-------|
| Bucket ACLs/Policies | No GetBucketAcl, PutBucketAcl, PutBucketPolicy |
| Versioning | No version support |
| Object Tagging | Not available |
| Object Lock (WORM) | Not available |
| S3 Select | Not implemented |
| POST uploads | Multipart form-based uploads not supported |
| Bucket website hosting | No PutBucketWebsite |
| Transfer Acceleration | Not applicable |
| Custom KMS keys | R2 encrypts everything automatically |

### Behavioral differences from AWS S3

- Region is always `auto` (use `auto`, `us-east-1`, or empty string)
- Path-style URLs only
- All objects encrypted at rest automatically
- Only Standard and Infrequent Access tiers (no Glacier/Deep Archive)
- Usage billing rounds up to next whole unit

## Pricing

| Component | Standard | Infrequent Access |
|-----------|----------|-------------------|
| Storage | $0.015/GB/month | $0.01/GB/month |
| Class A ops (writes) | $4.50/million | $9.00/million |
| Class B ops (reads) | $0.36/million | $0.90/million |
| Data retrieval | Free | $0.01/GB |
| Egress | **Free** | **Free** |

**Free tier** (Standard only, monthly):
- 10 GB storage
- 1M Class A operations
- 10M Class B operations

**Infrequent Access**: Minimum 30-day storage duration billing. No free tier.
