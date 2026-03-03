# Migrating 50GB of Images from AWS S3 to Cloudflare R2 with rclone

## Overview

You have:
- **Source**: AWS S3 bucket `old-images` in `us-east-1`, configured as rclone remote `aws`
- **Destination**: Cloudflare R2 bucket `new-images`, configured as rclone remote `r2`
- **Data size**: ~50GB of images

## Strategy for Maximum Speed

The fastest approach uses `rclone copy` with parallel transfers and multi-part uploads tuned for large-scale image migration. Since R2 is S3-compatible, rclone handles the protocol translation seamlessly.

### Key Performance Levers

1. **`--transfers`**: Number of files transferred in parallel (default is 4; increase significantly for many small files like images).
2. **`--checkers`**: Number of files checked in parallel before transfer (default is 8).
3. **`--s3-upload-concurrency`**: Number of parts uploaded concurrently for each multipart upload.
4. **`--s3-chunk-size`**: Size of each multipart upload chunk.
5. **`--fast-list`**: Uses fewer API calls to list objects by requesting all items in a single list operation. Reduces S3 LIST costs and speeds up the initial scan.

## Step 1: Dry Run (Verify Configuration)

Always start with a dry run to confirm rclone can see both buckets and that paths are correct.

```bash
rclone lsd aws:old-images
rclone lsd r2:new-images
```

Then do a dry-run copy to see what would be transferred without actually moving data:

```bash
rclone copy aws:old-images r2:new-images \
  --dry-run \
  --fast-list \
  -v
```

Review the output. It should list the files that would be copied and show no errors related to authentication or bucket access.

## Step 2: Execute the Migration

### Recommended Command

```bash
rclone copy aws:old-images r2:new-images \
  --transfers 32 \
  --checkers 32 \
  --s3-upload-concurrency 8 \
  --s3-chunk-size 16M \
  --fast-list \
  --progress \
  --log-file=/home/ivan/Project/ai/s3-compatible-storage-workspace/iteration-1/eval-2-migration/without_skill/outputs/migration.log \
  --log-level INFO \
  -v
```

### Explanation of Flags

| Flag | Value | Purpose |
|------|-------|---------|
| `--transfers 32` | 32 | Transfer 32 files simultaneously. For many small image files this dramatically increases throughput. |
| `--checkers 32` | 32 | Check 32 files at a time to determine what needs copying. |
| `--s3-upload-concurrency 8` | 8 | Upload 8 parts of a multipart upload in parallel per file. Helps with larger images. |
| `--s3-chunk-size 16M` | 16MB | Each multipart upload chunk is 16MB. Good balance for mixed image sizes. |
| `--fast-list` | - | Uses fewer API calls to enumerate bucket contents. Faster and cheaper for large buckets. |
| `--progress` | - | Shows real-time transfer progress with ETA. |
| `--log-file` | path | Writes detailed log to a file for post-migration review. |
| `-v` | - | Verbose output to the console. |

### Tuning Tips

- **If images are mostly small (< 1MB)**: Increase `--transfers` to 64 or even 128. The bottleneck will be per-file overhead, so more parallelism helps.
- **If images are mostly large (> 10MB)**: Keep `--transfers` at 16-32 but increase `--s3-upload-concurrency` to 16 and `--s3-chunk-size` to 32M or 64M.
- **If you hit rate limits**: Reduce `--transfers` and add `--tpslimit 100` to cap API calls per second. Cloudflare R2 is generally generous with rate limits, but AWS S3 can throttle on prefix-heavy workloads.
- **Network bandwidth**: If running from a machine with limited bandwidth (e.g., a laptop), the network will be the bottleneck regardless of parallelism. Consider running the migration from an EC2 instance in `us-east-1` to minimize egress latency from S3.

### Running from an EC2 Instance (Optional, for Maximum Speed)

For the absolute fastest transfer, launch a temporary EC2 instance in `us-east-1`:

```bash
# On an EC2 instance in us-east-1, S3 access is local and fast.
# R2 ingress is free, so the only cost is S3 egress (~$0.09/GB = ~$4.50 for 50GB).
# Using a larger instance type (e.g., c5.xlarge) gives better network throughput.

rclone copy aws:old-images r2:new-images \
  --transfers 64 \
  --checkers 64 \
  --s3-upload-concurrency 8 \
  --s3-chunk-size 16M \
  --fast-list \
  --progress \
  --log-file=migration.log \
  --log-level INFO \
  -v
```

## Step 3: Verify the Migration

Verification is critical. Use multiple methods to confirm data integrity.

### Method 1: Check File Counts

```bash
# Count files in source
rclone size aws:old-images

# Count files in destination
rclone size r2:new-images
```

Both commands return total file count and total size. These numbers should match exactly.

### Method 2: rclone check (Recommended)

`rclone check` compares the source and destination and reports any differences. By default it compares file sizes and modification times, but you can also verify checksums.

```bash
# Basic check (size + modtime)
rclone check aws:old-images r2:new-images \
  --fast-list \
  -v

# With MD5 checksum verification (slower but most thorough)
rclone check aws:old-images r2:new-images \
  --fast-list \
  --download \
  -v
```

**Important notes on checksums**:
- AWS S3 stores MD5 checksums (ETag) for single-part uploads. For multipart uploads, the ETag is not a simple MD5.
- Cloudflare R2 also stores MD5 ETags for objects.
- The `--download` flag forces rclone to download and hash both sides for comparison. This is the most reliable method but takes longer since it reads all 50GB from both sides.
- Without `--download`, rclone uses the stored checksums (ETags) when available. This works well for files that were uploaded as single-part on the source.

### Method 3: Spot-Check with rclone cryptcheck or Manual Comparison

For a quick sanity check, compare a random sample of files:

```bash
# List 10 random files from source
rclone lsf aws:old-images --max-depth 1 | shuf | head -10 > /tmp/sample_files.txt

# For each file, compare sizes
while IFS= read -r file; do
  src_size=$(rclone size "aws:old-images/$file" --json | jq '.bytes')
  dst_size=$(rclone size "r2:new-images/$file" --json | jq '.bytes')
  if [ "$src_size" = "$dst_size" ]; then
    echo "OK: $file ($src_size bytes)"
  else
    echo "MISMATCH: $file (src=$src_size, dst=$dst_size)"
  fi
done < /tmp/sample_files.txt
```

### Method 4: Generate and Compare Manifests

For a complete audit trail, generate file listings from both sides and diff them:

```bash
# Generate sorted file lists with sizes and checksums
rclone lsf aws:old-images --recursive --format "psh" | sort > /tmp/source_manifest.txt
rclone lsf r2:new-images --recursive --format "psh" | sort > /tmp/dest_manifest.txt

# Compare
diff /tmp/source_manifest.txt /tmp/dest_manifest.txt
```

The `--format "psh"` flag outputs: **p**ath, **s**ize, **h**ash for each file. If `diff` produces no output, the manifests are identical.

## Step 4: Handle Any Failures

If `rclone check` or the manifest comparison reveals missing or mismatched files, simply re-run the copy command. rclone is idempotent -- it only copies files that are missing or different at the destination:

```bash
rclone copy aws:old-images r2:new-images \
  --transfers 32 \
  --checkers 32 \
  --fast-list \
  --progress \
  -v
```

For specific files that failed, you can also use `--include` to target them:

```bash
rclone copy aws:old-images r2:new-images \
  --include "path/to/specific/file.jpg" \
  --include "another/file.png" \
  -v
```

## Cost Considerations

| Cost Item | Estimate |
|-----------|----------|
| **AWS S3 Egress** (us-east-1 to internet) | ~$0.09/GB x 50GB = **~$4.50** |
| **AWS S3 GET requests** (reading objects) | ~$0.0004 per 1,000 requests. For ~50,000 images: **~$0.02** |
| **Cloudflare R2 Ingress** | **Free** (R2 does not charge for ingress) |
| **Cloudflare R2 PUT requests** | $4.50 per million. For ~50,000 objects: **~$0.23** |
| **Cloudflare R2 Storage** | $0.015/GB/month. 50GB = **~$0.75/month** |
| **Total one-time migration cost** | **~$4.75** |

Note: If you run the migration from an EC2 instance in us-east-1, transfer to R2 will go through the public internet but the S3 reads will be intra-region (fast). AWS does not charge for S3 transfers within the same region to EC2, but egress from EC2 to the internet (to reach R2) still applies.

## Complete Migration Script

Here is a single script that combines all steps:

```bash
#!/usr/bin/env bash
set -euo pipefail

SOURCE="aws:old-images"
DEST="r2:new-images"
LOG_DIR="/home/ivan/Project/ai/s3-compatible-storage-workspace/iteration-1/eval-2-migration/without_skill/outputs"
LOG_FILE="${LOG_DIR}/migration.log"
MANIFEST_SRC="${LOG_DIR}/source_manifest.txt"
MANIFEST_DST="${LOG_DIR}/dest_manifest.txt"

echo "============================================"
echo " S3 to R2 Migration"
echo " Source: ${SOURCE}"
echo " Destination: ${DEST}"
echo "============================================"

# Step 1: Verify access to both buckets
echo ""
echo "[1/5] Verifying access to both buckets..."
echo "Source bucket contents:"
rclone lsd "${SOURCE}" 2>&1 | head -5
echo ""
echo "Destination bucket:"
rclone lsd "${DEST}" 2>&1 | head -5
echo ""

# Step 2: Dry run
echo "[2/5] Running dry-run to preview transfer..."
rclone copy "${SOURCE}" "${DEST}" \
  --dry-run \
  --fast-list \
  --stats-one-line \
  -v 2>&1 | tail -5
echo ""

read -p "Proceed with actual migration? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Migration cancelled."
  exit 0
fi

# Step 3: Execute migration
echo "[3/5] Starting migration..."
rclone copy "${SOURCE}" "${DEST}" \
  --transfers 32 \
  --checkers 32 \
  --s3-upload-concurrency 8 \
  --s3-chunk-size 16M \
  --fast-list \
  --progress \
  --log-file="${LOG_FILE}" \
  --log-level INFO \
  --stats 30s \
  -v

echo ""
echo "Migration transfer complete. Log saved to: ${LOG_FILE}"

# Step 4: Verify file counts and sizes
echo ""
echo "[4/5] Verifying file counts and total sizes..."
echo "Source:"
rclone size "${SOURCE}" --fast-list
echo ""
echo "Destination:"
rclone size "${DEST}" --fast-list
echo ""

# Step 5: Full verification with rclone check
echo "[5/5] Running rclone check for integrity verification..."
rclone check "${SOURCE}" "${DEST}" \
  --fast-list \
  -v 2>&1 | tee "${LOG_DIR}/verification.log"

echo ""

# Generate manifests for audit trail
echo "Generating file manifests for audit trail..."
rclone lsf "${SOURCE}" --recursive --format "psh" | sort > "${MANIFEST_SRC}"
rclone lsf "${DEST}" --recursive --format "psh" | sort > "${MANIFEST_DST}"

DIFF_OUTPUT=$(diff "${MANIFEST_SRC}" "${MANIFEST_DST}" || true)
if [ -z "${DIFF_OUTPUT}" ]; then
  echo "SUCCESS: All files match between source and destination."
else
  echo "WARNING: Differences found:"
  echo "${DIFF_OUTPUT}" | head -20
  echo ""
  echo "Re-run the copy command to transfer any missing files."
fi

echo ""
echo "============================================"
echo " Migration Complete"
echo " Log: ${LOG_FILE}"
echo " Source manifest: ${MANIFEST_SRC}"
echo " Dest manifest: ${MANIFEST_DST}"
echo "============================================"
```

## Summary

1. **Fastest approach**: Use `rclone copy` with `--transfers 32` (or higher for small files), `--fast-list`, and `--s3-upload-concurrency 8`. Optionally run from an EC2 instance in `us-east-1`.
2. **Verification**: Use `rclone check` for integrity verification, `rclone size` on both sides for a quick count/size comparison, and manifest diffing for a complete audit trail.
3. **Idempotent re-runs**: If anything fails, just re-run the same `rclone copy` command. It will only transfer what is missing or different.
4. **Expected cost**: Approximately $4.75 for the one-time migration (dominated by AWS egress fees).
