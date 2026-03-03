# Setting Up AWS CLI and rclone for Cloudflare R2

This guide walks you through configuring the AWS CLI and rclone to work with your Cloudflare R2 account, then uploading a test file to verify everything is working.

## Your R2 Connection Details

Based on your credentials, here is what we are working with:

| Field | Value |
|-------|-------|
| Account ID | `abc123def456` |
| Access Key ID | `AKEXAMPLE123` |
| Secret Access Key | `SKEXAMPLE456` |
| Endpoint URL | `https://abc123def456.r2.cloudflarestorage.com` |
| Region | `auto` |
| Target Bucket | `media-assets` |

> **Security reminder:** Never hardcode credentials in scripts or commit them to version control. After setup, restrict file permissions on credential files (shown below).

---

## Part 1: AWS CLI Setup

### Step 1: Verify AWS CLI is installed

```bash
aws --version
```

If it is not installed, install it:

```bash
# Linux (x86_64)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# macOS
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /
```

### Step 2: Configure a named profile for R2

Run the interactive configuration command:

```bash
aws configure --profile r2
```

When prompted, enter the following values:

```
AWS Access Key ID [None]: AKEXAMPLE123
AWS Secret Access Key [None]: SKEXAMPLE456
Default region name [None]: auto
Default output format [None]: json
```

This creates entries in two files:

**`~/.aws/credentials`** will contain:
```ini
[r2]
aws_access_key_id = AKEXAMPLE123
aws_secret_access_key = SKEXAMPLE456
```

**`~/.aws/config`** will contain:
```ini
[profile r2]
region = auto
output = json
```

### Step 3: Set the R2 endpoint URL

The AWS CLI needs to know the R2 endpoint. You have two options:

**Option A: Add the endpoint to `~/.aws/config` (recommended)**

Edit `~/.aws/config` so the `[profile r2]` section includes the endpoint:

```ini
[profile r2]
region = auto
output = json
endpoint_url = https://abc123def456.r2.cloudflarestorage.com
```

With this approach, you do not need to pass `--endpoint-url` on every command.

**Option B: Use environment variables**

```bash
export AWS_ENDPOINT_URL="https://abc123def456.r2.cloudflarestorage.com"
export AWS_PROFILE="r2"
```

You can add these lines to your `~/.bashrc` or `~/.zshrc` to make them persist across shell sessions.

### Step 4: Secure the credential files

```bash
chmod 600 ~/.aws/credentials
chmod 600 ~/.aws/config
```

### Step 5: Verify the AWS CLI connection

List your buckets to confirm the connection works:

```bash
aws s3 ls --profile r2
```

If you used Option A (endpoint in config), this should work as-is. If you did not set the endpoint in the config, add it explicitly:

```bash
aws s3 ls --profile r2 --endpoint-url https://abc123def456.r2.cloudflarestorage.com
```

You should see the `media-assets` bucket in the output (assuming it already exists). If it does not exist yet, create it:

```bash
aws s3 mb s3://media-assets --profile r2
```

---

## Part 2: rclone Setup

### Step 1: Verify rclone is installed

```bash
rclone version
```

If it is not installed, install it:

```bash
# Linux / macOS (official install script)
curl https://rclone.org/install.sh | sudo bash

# Or via package manager
# Debian/Ubuntu: sudo apt install rclone
# macOS: brew install rclone
```

### Step 2: Configure rclone for R2

You can either use the interactive configurator or write the config file directly.

**Option A: Interactive setup**

```bash
rclone config
```

Follow the prompts:
1. Choose `n` for new remote
2. Name it `r2`
3. Select `s3` as the storage type
4. Select `Cloudflare` as the provider
5. Enter your Access Key ID: `AKEXAMPLE123`
6. Enter your Secret Access Key: `SKEXAMPLE456`
7. Set the endpoint: `https://abc123def456.r2.cloudflarestorage.com`
8. Accept defaults for the remaining options

**Option B: Write the config file directly (recommended)**

Create or edit the rclone config file at `~/.config/rclone/rclone.conf`:

```bash
mkdir -p ~/.config/rclone
```

Add the following to `~/.config/rclone/rclone.conf`:

```ini
[r2]
type = s3
provider = Cloudflare
access_key_id = AKEXAMPLE123
secret_access_key = SKEXAMPLE456
endpoint = https://abc123def456.r2.cloudflarestorage.com
acl = private
no_check_bucket = true
```

The `no_check_bucket = true` setting is useful if your API token has object-level permissions only (not admin). It tells rclone to skip the bucket existence check, which requires `ListBuckets` permission.

### Step 3: Secure the config file

```bash
chmod 600 ~/.config/rclone/rclone.conf
```

### Step 4: Verify the rclone connection

List your buckets:

```bash
rclone lsd r2:
```

List objects in the `media-assets` bucket:

```bash
rclone ls r2:media-assets
```

---

## Part 3: Upload a Test File

### Create a test file

```bash
echo "Hello from Cloudflare R2! Test upload at $(date)" > /tmp/test-upload.txt
```

### Upload with AWS CLI

```bash
aws s3 cp /tmp/test-upload.txt s3://media-assets/test-upload.txt --profile r2
```

Verify it was uploaded:

```bash
aws s3 ls s3://media-assets/ --profile r2
```

### Upload with rclone

```bash
rclone copy /tmp/test-upload.txt r2:media-assets/
```

Verify it was uploaded:

```bash
rclone ls r2:media-assets
```

### Download the file back to verify round-trip

```bash
# Using AWS CLI
aws s3 cp s3://media-assets/test-upload.txt /tmp/test-download-aws.txt --profile r2
cat /tmp/test-download-aws.txt

# Using rclone
rclone copy r2:media-assets/test-upload.txt /tmp/test-download-rclone/
cat /tmp/test-download-rclone/test-upload.txt
```

If the file contents match, both tools are configured correctly and working.

### Clean up the test file (optional)

```bash
aws s3 rm s3://media-assets/test-upload.txt --profile r2
```

---

## Quick Reference: Common Commands

Once setup is complete, here are the commands you will use most often with the `media-assets` bucket:

### Uploading files

```bash
# Single file (AWS CLI)
aws s3 cp ./image.png s3://media-assets/images/image.png --profile r2

# Single file (rclone)
rclone copy ./image.png r2:media-assets/images/

# Entire directory (AWS CLI)
aws s3 cp ./assets/ s3://media-assets/assets/ --recursive --profile r2

# Entire directory (rclone - faster for many small files)
rclone copy ./assets/ r2:media-assets/assets/ --transfers 16 --progress
```

### Syncing a directory

```bash
# Sync local to R2 (only transfers changed files)
aws s3 sync ./assets/ s3://media-assets/assets/ --profile r2

# Same with rclone (typically faster)
rclone sync ./assets/ r2:media-assets/assets/ --transfers 16 --progress

# Dry run first to see what would change
aws s3 sync ./assets/ s3://media-assets/assets/ --dryrun --profile r2
```

### Listing files

```bash
# List all objects with sizes (AWS CLI)
aws s3 ls s3://media-assets/ --recursive --human-readable --summarize --profile r2

# List all objects (rclone)
rclone ls r2:media-assets
```

### Generating presigned URLs

```bash
# 1-hour URL (AWS CLI)
aws s3 presign s3://media-assets/images/photo.jpg --profile r2 --expires-in 3600

# 1-hour URL (rclone)
rclone link r2:media-assets/images/photo.jpg --expire 1h
```

Note: R2 presigned URLs only work via the S3 API domain (`abc123def456.r2.cloudflarestorage.com`), not custom domains. Maximum expiry is 7 days (604,800 seconds).

### Downloading files

```bash
# Single file
aws s3 cp s3://media-assets/images/photo.jpg ./photo.jpg --profile r2

# Entire prefix
aws s3 cp s3://media-assets/images/ ./images/ --recursive --profile r2
```

---

## Performance Tips

- **Many small files:** Use rclone with `--transfers 16` (or higher). rclone can be 6-9x faster than the AWS CLI for bulk small-file operations.
- **Large files:** Both tools handle multipart uploads automatically. For rclone, you can tune chunk size: `--s3-upload-cutoff=100M --s3-chunk-size=100M`.
- **Sync vs Copy:** Use `sync` when you want the destination to mirror the source. Use `cp`/`copy` when you just want to add files without removing anything from the destination.
- **Always dry-run first:** Before running `sync --delete` or any destructive operation, use `--dryrun` (AWS CLI) or `--dry-run` (rclone) to preview changes.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `SignatureDoesNotMatch` | Double-check your Access Key and Secret Key. Ensure there are no extra spaces. |
| `AccessDenied` on `ListBuckets` | Your API token may be scoped to specific buckets. Use `aws s3 ls s3://media-assets/ --profile r2` to list objects directly. |
| `Could not connect to the endpoint URL` | Verify the Account ID in the endpoint URL. It should be `https://abc123def456.r2.cloudflarestorage.com`. |
| `NoSuchBucket` | The bucket `media-assets` may not exist yet. Create it with `aws s3 mb s3://media-assets --profile r2` or via the Cloudflare dashboard. |
| rclone `AccessDenied` on bucket check | Set `no_check_bucket = true` in the rclone config (already included above). |
| Region errors | R2 uses `auto` as the region. If a tool complains, try `us-east-1` as an alias (R2 accepts both). |

---

## Summary

You now have two fully configured tools for working with your Cloudflare R2 `media-assets` bucket:

1. **AWS CLI** -- configured via the `r2` named profile with the endpoint set in `~/.aws/config`. Use with `--profile r2` on all commands.
2. **rclone** -- configured via the `r2` remote in `~/.config/rclone/rclone.conf`. Use as `r2:media-assets` in commands.

Both tools are ready to upload, download, sync, and manage files in your R2 bucket. The test file upload procedure above confirms that credentials, endpoint, and bucket access are all working correctly.
