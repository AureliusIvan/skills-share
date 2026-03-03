# AWS S3 Reference

## Table of Contents

1. [Configuration](#configuration)
2. [High-level commands (aws s3)](#high-level-commands)
3. [Low-level commands (aws s3api)](#low-level-commands)
4. [CORS](#cors)
5. [Lifecycle policies](#lifecycle-policies)
6. [Versioning](#versioning)
7. [Encryption](#encryption)
8. [Multipart uploads](#multipart-uploads)
9. [Environment variables](#environment-variables)
10. [S3-specific CLI config](#s3-specific-cli-config)

## Configuration

### AWS CLI setup

```bash
# Install (if needed)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# Configure default profile
aws configure
# Prompts: Access Key ID, Secret Access Key, Region, Output format

# Configure named profile
aws configure --profile production

# Set individual values
aws configure set region us-west-2
aws configure set output json --profile production

# Verify
aws configure list
```

### Credential files

**`~/.aws/credentials`** (no `profile` keyword here):
```ini
[default]
aws_access_key_id = AKIAIOSFODNN7EXAMPLE
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

[production]
aws_access_key_id = AKIAI44QH8DHBEXAMPLE
aws_secret_access_key = je7MtGbClwBF/2Zp9Utk/h3yCo8nvbEXAMPLEKEY
```

**`~/.aws/config`**:
```ini
[default]
region = us-east-1
output = json

[profile production]
region = eu-west-1
output = table
```

### Credential resolution order

1. Command-line options (`--profile`, `--region`)
2. Environment variables
3. `~/.aws/credentials`
4. `~/.aws/config`
5. Container credentials (ECS)
6. Instance profile (EC2 IAM Role)

## High-level commands

### Bucket operations

```bash
aws s3 mb s3://my-bucket                          # Create bucket
aws s3 mb s3://my-bucket --region us-west-2        # Create in specific region
aws s3 ls                                          # List all buckets
aws s3 ls s3://my-bucket                           # List objects
aws s3 ls s3://my-bucket --recursive --human-readable --summarize
aws s3 rb s3://my-bucket                           # Delete empty bucket
aws s3 rb s3://my-bucket --force                   # Delete bucket + all objects
```

### Copy (cp)

```bash
aws s3 cp file.txt s3://bucket/file.txt            # Upload
aws s3 cp s3://bucket/file.txt ./file.txt           # Download
aws s3 cp s3://src/f.txt s3://dst/f.txt             # Copy between buckets
aws s3 cp ./dir s3://bucket/prefix/ --recursive     # Upload directory
aws s3 cp file.txt s3://bucket/ --sse AES256        # With encryption
aws s3 cp file.txt s3://bucket/ --storage-class GLACIER
aws s3 cp ./dir s3://bucket/ --recursive --dryrun   # Dry run
```

### Move (mv)

```bash
aws s3 mv file.txt s3://bucket/file.txt            # Upload and delete local
aws s3 mv s3://bucket/old s3://bucket/new           # Rename/move in S3
aws s3 mv s3://bucket/dir/ ./dir/ --recursive       # Download and delete remote
```

### Sync

```bash
aws s3 sync ./dir s3://bucket/prefix/               # Local to S3
aws s3 sync s3://bucket/prefix/ ./dir               # S3 to local
aws s3 sync s3://src s3://dst                       # Between buckets
aws s3 sync ./dir s3://bucket/ --delete             # Mirror (delete extras)
aws s3 sync . s3://bucket --exclude "*" --include "*.txt"  # Filter
aws s3 sync . s3://bucket --exclude "*.tmp" --exclude ".git/*"
aws s3 sync ./dir s3://bucket/ --dryrun             # Preview changes
```

### Presign

```bash
aws s3 presign s3://bucket/file.txt                 # 1 hour default
aws s3 presign s3://bucket/file.txt --expires-in 604800  # 7 days max
aws s3 presign s3://bucket/file.txt --region us-west-2
```

### Remove (rm)

```bash
aws s3 rm s3://bucket/file.txt                      # Single object
aws s3 rm s3://bucket/prefix/ --recursive           # All under prefix
aws s3 rm s3://bucket/ --recursive --exclude "*.log"  # With filter
```

### Common flags

| Flag | Description |
|------|-------------|
| `--recursive` | Apply to all objects under prefix |
| `--dryrun` | Preview without executing |
| `--exclude <pattern>` | Exclude matching files |
| `--include <pattern>` | Include matching files |
| `--acl <value>` | Canned ACL (private, public-read) |
| `--sse <value>` | Server-side encryption (AES256, aws:kms) |
| `--storage-class <value>` | STANDARD, STANDARD_IA, GLACIER, etc. |
| `--content-type <value>` | Set MIME type |
| `--metadata <map>` | Custom metadata |

## Low-level commands

### Bucket management

```bash
# Create (outside us-east-1 needs LocationConstraint)
aws s3api create-bucket --bucket my-bucket --region us-west-2 \
  --create-bucket-configuration LocationConstraint=us-west-2

aws s3api delete-bucket --bucket my-bucket
aws s3api list-buckets
aws s3api head-bucket --bucket my-bucket             # Check existence
```

### Object management

```bash
aws s3api put-object --bucket my-bucket --key file.txt --body ./file.txt
aws s3api get-object --bucket my-bucket --key file.txt ./downloaded.txt
aws s3api delete-object --bucket my-bucket --key file.txt
aws s3api head-object --bucket my-bucket --key file.txt
aws s3api list-objects-v2 --bucket my-bucket --prefix "logs/" --max-items 100
aws s3api copy-object --bucket dest --key new.txt --copy-source src/old.txt
```

## CORS

```bash
# Set CORS
aws s3api put-bucket-cors --bucket my-bucket --cors-configuration '{
  "CORSRules": [{
    "AllowedOrigins": ["https://example.com"],
    "AllowedMethods": ["GET", "PUT", "POST"],
    "AllowedHeaders": ["*"],
    "ExposeHeaders": ["ETag"],
    "MaxAgeSeconds": 3600
  }]
}'

# Get CORS
aws s3api get-bucket-cors --bucket my-bucket

# Delete CORS
aws s3api delete-bucket-cors --bucket my-bucket
```

## Lifecycle policies

```bash
# Set lifecycle (transition to Glacier after 90 days, expire after 365)
aws s3api put-bucket-lifecycle-configuration --bucket my-bucket \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "ArchiveAndExpire",
      "Status": "Enabled",
      "Filter": {"Prefix": "logs/"},
      "Transitions": [{"Days": 90, "StorageClass": "GLACIER"}],
      "Expiration": {"Days": 365}
    }]
  }'

# Get lifecycle
aws s3api get-bucket-lifecycle-configuration --bucket my-bucket

# Delete lifecycle
aws s3api delete-bucket-lifecycle --bucket my-bucket
```

## Versioning

```bash
# Enable
aws s3api put-bucket-versioning --bucket my-bucket \
  --versioning-configuration Status=Enabled

# Suspend
aws s3api put-bucket-versioning --bucket my-bucket \
  --versioning-configuration Status=Suspended

# Check status
aws s3api get-bucket-versioning --bucket my-bucket

# List versions
aws s3api list-object-versions --bucket my-bucket
```

## Encryption

```bash
# SSE-S3 (AES256)
aws s3api put-bucket-encryption --bucket my-bucket \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'

# SSE-KMS
aws s3api put-bucket-encryption --bucket my-bucket \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "aws:kms",
        "KMSMasterKeyID": "arn:aws:kms:us-east-1:123456789012:key/my-key"
      },
      "BucketKeyEnabled": true
    }]
  }'

# Get encryption config
aws s3api get-bucket-encryption --bucket my-bucket
```

## Multipart uploads

Useful for files larger than 100MB. The AWS CLI handles this automatically for `s3 cp`, but you can manage manually with `s3api`:

```bash
# Initiate
aws s3api create-multipart-upload --bucket my-bucket --key large-file.bin

# Upload parts (use the UploadId from above)
aws s3api upload-part --bucket my-bucket --key large-file.bin \
  --part-number 1 --body part1.bin --upload-id {upload-id}

# Complete
aws s3api complete-multipart-upload --bucket my-bucket --key large-file.bin \
  --upload-id {upload-id} --multipart-upload '{"Parts": [...]}'

# Abort
aws s3api abort-multipart-upload --bucket my-bucket --key large-file.bin \
  --upload-id {upload-id}

# List in-progress uploads
aws s3api list-multipart-uploads --bucket my-bucket
```

## Environment variables

| Variable | Description |
|----------|-------------|
| `AWS_ACCESS_KEY_ID` | Access key |
| `AWS_SECRET_ACCESS_KEY` | Secret key |
| `AWS_SESSION_TOKEN` | Temporary session token (STS) |
| `AWS_DEFAULT_REGION` | Default region |
| `AWS_DEFAULT_OUTPUT` | Output format (json/text/table/yaml) |
| `AWS_PROFILE` | Named profile to use |
| `AWS_ENDPOINT_URL` | Global custom endpoint for all services |
| `AWS_ENDPOINT_URL_S3` | S3-specific custom endpoint |
| `AWS_PAGER` | Pager program (set to "" to disable) |

**Endpoint resolution priority** (highest to lowest):
1. `--endpoint-url` on the command line
2. `AWS_ENDPOINT_URL_S3` env var
3. Service-specific config file setting
4. `AWS_ENDPOINT_URL` env var
5. Global config file `endpoint_url`
6. Default AWS endpoint

## S3-specific CLI config

In `~/.aws/config` under the `s3` key:

```ini
[default]
s3 =
  max_concurrent_requests = 10
  max_queue_size = 1000
  multipart_threshold = 64MB
  multipart_chunksize = 16MB
  max_bandwidth = 50MB/s
  use_accelerate_endpoint = true
  addressing_style = path     # path or virtual (important for non-AWS)
```

Set programmatically:
```bash
aws configure set default.s3.max_concurrent_requests 20
aws configure set default.s3.multipart_threshold 64MB
aws configure set default.s3.addressing_style path
```
