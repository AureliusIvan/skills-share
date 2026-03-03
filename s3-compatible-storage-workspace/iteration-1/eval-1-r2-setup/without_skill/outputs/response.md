# Cloudflare R2 Setup Guide: AWS CLI and rclone

## Overview

Cloudflare R2 is an S3-compatible object storage service. Because it implements the S3 API, you can use standard tools like the AWS CLI and rclone to interact with it. This guide walks through configuring both tools and uploading a test file to the `media-assets` bucket.

---

## Your R2 Credentials

| Field          | Value              |
|----------------|--------------------|
| Account ID     | `abc123def456`     |
| Access Key ID  | `AKEXAMPLE123`     |
| Secret Access Key | `SKEXAMPLE456`  |
| S3 API Endpoint | `https://abc123def456.r2.cloudflarestorage.com` |

The S3 API endpoint is derived from your account ID using the pattern:
`https://<ACCOUNT_ID>.r2.cloudflarestorage.com`

---

## Part 1: AWS CLI Setup

### 1.1 Install the AWS CLI

**On Ubuntu/Debian:**

```bash
sudo apt update
sudo apt install -y awscli
```

**Or install the latest version (v2) directly from AWS:**

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

**On macOS (via Homebrew):**

```bash
brew install awscli
```

**Verify the installation:**

```bash
aws --version
```

### 1.2 Configure a Named Profile for R2

Using a named profile keeps your R2 credentials separate from any existing AWS credentials. Run:

```bash
aws configure --profile r2
```

When prompted, enter the following:

```
AWS Access Key ID [None]: AKEXAMPLE123
AWS Secret Access Key [None]: SKEXAMPLE456
Default region name [None]: auto
Default output format [None]: json
```

The region should be set to `auto` for Cloudflare R2.

### 1.3 Verify the Configuration Files

The AWS CLI stores credentials in two files. Verify they look correct:

**~/.aws/credentials:**

```ini
[r2]
aws_access_key_id = AKEXAMPLE123
aws_secret_access_key = SKEXAMPLE456
```

**~/.aws/config:**

```ini
[profile r2]
region = auto
output = json
```

### 1.4 Using AWS CLI with R2

Every AWS CLI command targeting R2 must include the `--endpoint-url` flag and the `--profile r2` flag. You can simplify this by setting environment variables or using a shell alias.

**Option A: Use the flags directly each time:**

```bash
aws s3 ls \
  --endpoint-url https://abc123def456.r2.cloudflarestorage.com \
  --profile r2
```

**Option B: Set environment variables to reduce repetition:**

```bash
export AWS_PROFILE=r2
export AWS_ENDPOINT_URL=https://abc123def456.r2.cloudflarestorage.com
```

After exporting, you can run commands without the extra flags:

```bash
aws s3 ls
```

**Option C: Create a shell alias:**

Add the following to your `~/.bashrc` or `~/.zshrc`:

```bash
alias r2='aws --endpoint-url https://abc123def456.r2.cloudflarestorage.com --profile r2'
```

Then reload your shell configuration:

```bash
source ~/.bashrc
```

Now you can use:

```bash
r2 s3 ls
```

### 1.5 Common AWS CLI Commands for R2

**List all buckets:**

```bash
aws s3 ls \
  --endpoint-url https://abc123def456.r2.cloudflarestorage.com \
  --profile r2
```

**List objects in the media-assets bucket:**

```bash
aws s3 ls s3://media-assets/ \
  --endpoint-url https://abc123def456.r2.cloudflarestorage.com \
  --profile r2
```

**Upload a file:**

```bash
aws s3 cp myfile.txt s3://media-assets/myfile.txt \
  --endpoint-url https://abc123def456.r2.cloudflarestorage.com \
  --profile r2
```

**Download a file:**

```bash
aws s3 cp s3://media-assets/myfile.txt ./downloaded-myfile.txt \
  --endpoint-url https://abc123def456.r2.cloudflarestorage.com \
  --profile r2
```

**Sync a directory:**

```bash
aws s3 sync ./local-folder/ s3://media-assets/remote-folder/ \
  --endpoint-url https://abc123def456.r2.cloudflarestorage.com \
  --profile r2
```

**Delete a file:**

```bash
aws s3 rm s3://media-assets/myfile.txt \
  --endpoint-url https://abc123def456.r2.cloudflarestorage.com \
  --profile r2
```

---

## Part 2: rclone Setup

### 2.1 Install rclone

**On Ubuntu/Debian:**

```bash
sudo apt update
sudo apt install -y rclone
```

**Or install the latest version using the official script:**

```bash
curl https://rclone.org/install.sh | sudo bash
```

**On macOS (via Homebrew):**

```bash
brew install rclone
```

**Verify the installation:**

```bash
rclone version
```

### 2.2 Configure rclone for R2

You can configure rclone interactively or by editing the config file directly. The direct approach is simpler for R2.

**Option A: Edit the config file directly:**

Open (or create) the rclone configuration file:

```bash
mkdir -p ~/.config/rclone
nano ~/.config/rclone/rclone.conf
```

Add the following block:

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

Save and close the file.

**Option B: Interactive configuration:**

```bash
rclone config
```

Follow these prompts:
1. Choose `n` for new remote
2. Name it `r2`
3. Choose `s3` as the storage type (typically option number 5, but this may vary by version)
4. Choose `Cloudflare` as the provider
5. Enter your access key: `AKEXAMPLE123`
6. Enter your secret key: `SKEXAMPLE456`
7. Leave region blank or enter `auto`
8. Enter endpoint: `https://abc123def456.r2.cloudflarestorage.com`
9. Accept defaults for remaining options
10. Confirm and save

### 2.3 Verify the Configuration

```bash
rclone config show r2
```

This should display the configuration block you created.

### 2.4 Common rclone Commands for R2

**List all buckets:**

```bash
rclone lsd r2:
```

**List objects in the media-assets bucket:**

```bash
rclone ls r2:media-assets
```

**Upload a file:**

```bash
rclone copy myfile.txt r2:media-assets/
```

**Upload a directory:**

```bash
rclone copy ./local-folder/ r2:media-assets/remote-folder/
```

**Download a file:**

```bash
rclone copy r2:media-assets/myfile.txt ./
```

**Sync a local directory to R2 (mirror local state to remote):**

```bash
rclone sync ./local-folder/ r2:media-assets/synced-folder/
```

> **Warning:** `rclone sync` deletes files on the remote that do not exist locally. Use `rclone copy` if you only want to add files without deleting.

**Delete a file:**

```bash
rclone delete r2:media-assets/myfile.txt
```

**Check file details:**

```bash
rclone lsl r2:media-assets
```

---

## Part 3: Upload a Test File to Verify

### 3.1 Create a Test File

```bash
echo "Hello from Cloudflare R2 - test upload $(date)" > /tmp/r2-test-upload.txt
```

### 3.2 Upload with AWS CLI

```bash
aws s3 cp /tmp/r2-test-upload.txt s3://media-assets/test/r2-test-upload.txt \
  --endpoint-url https://abc123def456.r2.cloudflarestorage.com \
  --profile r2
```

**Expected output:**

```
upload: /tmp/r2-test-upload.txt to s3://media-assets/test/r2-test-upload.txt
```

**Verify the upload by listing the object:**

```bash
aws s3 ls s3://media-assets/test/ \
  --endpoint-url https://abc123def456.r2.cloudflarestorage.com \
  --profile r2
```

**Expected output (similar to):**

```
2026-03-03 12:00:00         50 r2-test-upload.txt
```

**Verify by downloading and comparing:**

```bash
aws s3 cp s3://media-assets/test/r2-test-upload.txt /tmp/r2-test-download.txt \
  --endpoint-url https://abc123def456.r2.cloudflarestorage.com \
  --profile r2

diff /tmp/r2-test-upload.txt /tmp/r2-test-download.txt
```

If `diff` produces no output, the files are identical and the round-trip was successful.

### 3.3 Upload with rclone

```bash
rclone copy /tmp/r2-test-upload.txt r2:media-assets/test-rclone/
```

**Verify the upload:**

```bash
rclone ls r2:media-assets/test-rclone/
```

**Expected output (similar to):**

```
       50 r2-test-upload.txt
```

### 3.4 Clean Up Test Files (Optional)

```bash
# Remove from R2 (AWS CLI)
aws s3 rm s3://media-assets/test/r2-test-upload.txt \
  --endpoint-url https://abc123def456.r2.cloudflarestorage.com \
  --profile r2

# Remove from R2 (rclone)
rclone delete r2:media-assets/test-rclone/r2-test-upload.txt

# Remove local temp files
rm /tmp/r2-test-upload.txt /tmp/r2-test-download.txt
```

---

## Part 4: Troubleshooting

### Common Issues

**Error: "The AWS Access Key Id you provided does not exist in our records"**
- Double-check that the access key and secret key are correct.
- Ensure you generated an R2 API token (not a general Cloudflare API token) in the Cloudflare dashboard under R2 > Manage R2 API Tokens.

**Error: "SignatureDoesNotMatch"**
- The secret access key is likely incorrect. Regenerate the token in the Cloudflare dashboard if needed.

**Error: "NoSuchBucket"**
- The bucket `media-assets` must exist before you can upload to it. Create it via the Cloudflare dashboard or with:
  ```bash
  aws s3 mb s3://media-assets \
    --endpoint-url https://abc123def456.r2.cloudflarestorage.com \
    --profile r2
  ```

**Error: "Could not connect to the endpoint URL"**
- Verify the endpoint URL uses your correct account ID.
- Ensure you have internet connectivity.
- Check that the URL uses `https://` (not `http://`).

**rclone: "Failed to create file system"**
- Run `rclone config show r2` and verify all fields are correct.
- Make sure the `provider` is set to `Cloudflare` (not `AWS` or another provider).

### Useful Debugging Flags

**AWS CLI verbose output:**

```bash
aws s3 ls s3://media-assets/ \
  --endpoint-url https://abc123def456.r2.cloudflarestorage.com \
  --profile r2 \
  --debug
```

**rclone verbose output:**

```bash
rclone ls r2:media-assets -vv
```

---

## Part 5: Security Best Practices

1. **Never commit credentials to version control.** Add `~/.aws/credentials` and `~/.config/rclone/rclone.conf` to your global gitignore.

2. **Use environment variables in CI/CD pipelines** instead of config files:
   ```bash
   export AWS_ACCESS_KEY_ID=AKEXAMPLE123
   export AWS_SECRET_ACCESS_KEY=SKEXAMPLE456
   export AWS_ENDPOINT_URL=https://abc123def456.r2.cloudflarestorage.com
   ```

3. **Scope your R2 API tokens** to only the permissions you need (e.g., read-only for a backup reader, read-write for an uploader).

4. **Rotate credentials regularly** via the Cloudflare dashboard under R2 > Manage R2 API Tokens.

5. **Protect your config files:**
   ```bash
   chmod 600 ~/.aws/credentials
   chmod 600 ~/.config/rclone/rclone.conf
   ```

---

## Quick Reference

| Task                     | AWS CLI Command                                                                 | rclone Command                          |
|--------------------------|---------------------------------------------------------------------------------|-----------------------------------------|
| List buckets             | `aws s3 ls --endpoint-url $EP --profile r2`                                     | `rclone lsd r2:`                        |
| List objects             | `aws s3 ls s3://media-assets/ --endpoint-url $EP --profile r2`                  | `rclone ls r2:media-assets`             |
| Upload file              | `aws s3 cp file.txt s3://media-assets/ --endpoint-url $EP --profile r2`         | `rclone copy file.txt r2:media-assets/` |
| Download file            | `aws s3 cp s3://media-assets/file.txt ./ --endpoint-url $EP --profile r2`       | `rclone copy r2:media-assets/file.txt ./` |
| Delete file              | `aws s3 rm s3://media-assets/file.txt --endpoint-url $EP --profile r2`          | `rclone delete r2:media-assets/file.txt`|
| Sync directory           | `aws s3 sync ./dir/ s3://media-assets/dir/ --endpoint-url $EP --profile r2`     | `rclone sync ./dir/ r2:media-assets/dir/` |
| Create bucket            | `aws s3 mb s3://new-bucket --endpoint-url $EP --profile r2`                     | `rclone mkdir r2:new-bucket`            |

Where `$EP` = `https://abc123def456.r2.cloudflarestorage.com`
