---
name: s3-compatible-storage
description: >-
  Manage S3-compatible object storage services including AWS S3, Cloudflare R2,
  MinIO, Backblaze B2, DigitalOcean Spaces, Wasabi, and others. Handles
  configuration, credential setup, bucket and object operations, uploading,
  downloading, syncing directories, presigned URLs, CORS setup, lifecycle
  policies, versioning, encryption, and migrations between providers. Use this
  skill whenever the user mentions S3, R2, object storage, buckets, cloud
  storage, file uploads to cloud, presigned URLs, storage migration, backup to
  cloud, or wants to configure, manage, or interact with any S3-compatible
  service. Also trigger when users mention specific tools like aws s3, aws
  s3api, rclone, mc (MinIO Client), wrangler r2, or s3cmd in the context of
  storage operations. Trigger even when the user is troubleshooting S3 errors
  like AccessDenied, SignatureDoesNotMatch, or CORS issues with object storage.
compatibility: Requires at least one of aws-cli, rclone, mc (minio-client), wrangler, or s3cmd installed
metadata:
  author: community
  version: "1.0"
  openclaw:
    requires:
      anyBins: ["aws", "rclone", "mc", "wrangler", "s3cmd"]
    emoji: "\U0001FAA3"
---

# S3-Compatible Storage

This skill helps you configure and manage S3-compatible object storage across multiple providers. It covers the full lifecycle: credential setup, bucket management, object operations, syncing, and advanced features like CORS, lifecycle policies, and cross-provider migration.

## Identifying the provider

Before taking action, determine which provider the user is working with. Ask if unclear. The most common ones:

| Provider | Endpoint Format | Region |
|----------|----------------|--------|
| **AWS S3** | Default (no endpoint needed), or `s3.{region}.amazonaws.com` | User's chosen region |
| **Cloudflare R2** | `https://{ACCOUNT_ID}.r2.cloudflarestorage.com` | `auto` |
| **MinIO** | `http(s)://{host}:{port}` (often port 9000) | Not applicable |
| **Backblaze B2** | `https://s3.{region}.backblazeb2.com` | e.g. `us-west-004` |
| **DigitalOcean Spaces** | `https://{region}.digitaloceanspaces.com` | e.g. `nyc3`, `sfo3` |
| **Wasabi** | `https://s3.{region}.wasabisys.com` | e.g. `us-east-1` |

For detailed provider-specific information, read:
- [AWS S3 reference](references/aws-s3.md) - Full AWS CLI commands, configuration, advanced features
- [Cloudflare R2 reference](references/cloudflare-r2.md) - R2 setup, Wrangler CLI, S3 API differences
- [Other providers reference](references/other-providers.md) - MinIO, Backblaze B2, DigitalOcean Spaces, Wasabi, and more

## Choosing a tool

Pick the right tool based on what's installed and the task at hand:

| Tool | Best for | Install check |
|------|----------|---------------|
| **AWS CLI** (`aws`) | Standard S3 operations, AWS-native workflows | `aws --version` |
| **rclone** | Multi-provider sync, migration, mounting, many small files | `rclone version` |
| **MinIO Client** (`mc`) | Large file ops, MinIO admin, fast batch deletes | `mc --version` |
| **Wrangler** (`wrangler`) | Cloudflare R2-native operations | `wrangler --version` |
| **s3cmd** | Legacy scripts, simple operations | `s3cmd --version` |

**Performance guidance**: rclone is fastest for many small files (6-9x faster than AWS CLI). mc is fastest for single large file uploads. AWS CLI is the reference standard but slowest for bulk operations.

Start by checking which tools are available:
```bash
which aws rclone mc wrangler s3cmd 2>/dev/null
```

## Configuration workflow

When a user needs to set up credentials, follow this flow:

### 1. Gather required information

Every S3-compatible provider needs at minimum:
- **Access Key ID**
- **Secret Access Key**
- **Endpoint URL** (except AWS S3 which uses defaults)
- **Region** (provider-dependent; R2 uses `auto`)

### 2. Configure with AWS CLI

The AWS CLI is the most universal tool. Use named profiles to manage multiple providers:

```bash
# Configure a profile
aws configure --profile {profile_name}
# Enter: Access Key ID, Secret Access Key, Region, Output format (json)
```

For non-AWS providers, set the endpoint URL. Since `--endpoint-url` must be passed per-command with `aws`, suggest using a shell alias or the `AWS_ENDPOINT_URL` environment variable:

```bash
# Environment variable approach (cleanest)
export AWS_ENDPOINT_URL="https://{ACCOUNT_ID}.r2.cloudflarestorage.com"
export AWS_PROFILE="r2"
```

Or configure in `~/.aws/config`:
```ini
[profile r2]
region = auto
output = json
endpoint_url = https://{ACCOUNT_ID}.r2.cloudflarestorage.com
```

### 3. Configure with rclone

rclone has built-in support for many providers:

```bash
# Interactive setup
rclone config

# Or write directly to ~/.config/rclone/rclone.conf
```

See the provider-specific reference files for exact rclone config examples.

### 4. Verify the connection

Always verify after setup:
```bash
# AWS CLI
aws s3 ls --profile {profile} --endpoint-url {endpoint}

# rclone
rclone lsd {remote}:

# mc
mc ls {alias}
```

## Common operations

These commands work across all S3-compatible providers. For AWS CLI, add `--endpoint-url {url}` for non-AWS providers. For rclone/mc, use the configured remote/alias name.

### Bucket operations

```bash
# Create bucket
aws s3 mb s3://{bucket} --profile {profile}

# List buckets
aws s3 ls --profile {profile}

# Delete empty bucket
aws s3 rb s3://{bucket} --profile {profile}

# Delete bucket and all contents (DESTRUCTIVE - confirm with user first)
aws s3 rb s3://{bucket} --force --profile {profile}
```

### Upload and download

```bash
# Upload single file
aws s3 cp {local_file} s3://{bucket}/{key} --profile {profile}

# Download single file
aws s3 cp s3://{bucket}/{key} {local_path} --profile {profile}

# Upload directory recursively
aws s3 cp {local_dir} s3://{bucket}/{prefix}/ --recursive --profile {profile}

# Download directory recursively
aws s3 cp s3://{bucket}/{prefix}/ {local_dir} --recursive --profile {profile}
```

### Sync

Sync is one of the most useful operations. It only transfers changed files:

```bash
# Sync local to S3
aws s3 sync {local_dir} s3://{bucket}/{prefix}/ --profile {profile}

# Sync S3 to local
aws s3 sync s3://{bucket}/{prefix}/ {local_dir} --profile {profile}

# Sync and delete files in destination not in source
aws s3 sync {local_dir} s3://{bucket}/ --delete --profile {profile}

# Sync with filters
aws s3 sync . s3://{bucket}/ --exclude "*.tmp" --exclude ".git/*" --profile {profile}

# Dry run (see what would change)
aws s3 sync {local_dir} s3://{bucket}/ --dryrun --profile {profile}
```

For rclone (faster with many files):
```bash
rclone sync {local_dir} {remote}:{bucket}/{prefix}/ --transfers 16 --progress
```

### Presigned URLs

Generate temporary, shareable URLs for objects:

```bash
# Default: 1 hour expiry
aws s3 presign s3://{bucket}/{key} --profile {profile}

# Custom expiry (max 7 days = 604800 seconds)
aws s3 presign s3://{bucket}/{key} --expires-in 86400 --profile {profile}
```

For rclone:
```bash
rclone link {remote}:{bucket}/{key} --expire 1h
```

### Delete objects

```bash
# Delete single object
aws s3 rm s3://{bucket}/{key} --profile {profile}

# Delete all objects with a prefix
aws s3 rm s3://{bucket}/{prefix}/ --recursive --profile {profile}
```

### List objects

```bash
# List objects in bucket
aws s3 ls s3://{bucket}/ --profile {profile}

# Recursive listing with human-readable sizes
aws s3 ls s3://{bucket}/ --recursive --human-readable --summarize --profile {profile}
```

## Advanced operations

For CORS, lifecycle policies, versioning, encryption, and other advanced S3 API operations, consult the provider-specific reference files:

- **AWS S3**: [references/aws-s3.md](references/aws-s3.md) - covers `aws s3api` commands for CORS, lifecycle, versioning, encryption, multipart uploads
- **Cloudflare R2**: [references/cloudflare-r2.md](references/cloudflare-r2.md) - covers Wrangler commands, R2-specific CORS setup, public buckets, custom domains
- **Others**: [references/other-providers.md](references/other-providers.md) - provider-specific configuration and limitations

## Migration between providers

When migrating data between S3-compatible providers, rclone is the recommended tool because it handles cross-provider transfers natively:

```bash
# Copy from provider A to provider B (safe - doesn't delete source)
rclone copy {source_remote}:{bucket} {dest_remote}:{bucket} \
  --transfers 32 --checkers 64 --fast-list --progress

# Verify object counts match
rclone size {source_remote}:{bucket} --json
rclone size {dest_remote}:{bucket} --json
```

The `scripts/s3-migrate.sh` helper script automates this with verification. Run it with:
```bash
bash {baseDir}/scripts/s3-migrate.sh {source_remote}:{bucket} {dest_remote}:{bucket}
```

## Security reminders

- Never hardcode credentials in scripts or commit them to version control
- Use named profiles (`--profile`) instead of embedding keys in commands
- Prefer temporary credentials (IAM roles, STS) over long-lived access keys where possible
- Set `chmod 600` on `~/.aws/credentials` and `~/.config/rclone/rclone.conf`
- Always use `--dryrun` before destructive sync or delete operations
- Ask the user for confirmation before any delete or `--force` operations
