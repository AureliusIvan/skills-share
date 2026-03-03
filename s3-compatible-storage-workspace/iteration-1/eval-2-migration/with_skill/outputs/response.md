# Migrating 50GB of Images from AWS S3 to Cloudflare R2

## Recommended Tool: rclone

For cross-provider migration, **rclone** is the best tool. It handles S3-to-R2 transfers natively, supports high parallelism, automatic retries, and has built-in verification. It is significantly faster than AWS CLI for bulk operations (6-9x faster for many small files). Since you already have both remotes (`aws` and `r2`) configured in rclone, you are ready to go.

---

## Step 1: Verify Your Remotes Are Working

Before starting the migration, confirm that rclone can reach both buckets:

```bash
# Verify the AWS remote can list the source bucket
rclone lsd aws:

# Verify you can see objects in the source bucket
rclone ls aws:old-images --max-depth 1 | head -20

# Verify the R2 remote is accessible
rclone lsd r2:

# Verify the destination bucket exists (create it if it doesn't)
rclone lsd r2: | grep new-images
```

If the `new-images` bucket does not exist yet on R2, create it:

```bash
rclone mkdir r2:new-images
```

## Step 2: Check the Source Bucket Size

Get an exact count of objects and total size so you have a baseline for verification:

```bash
rclone size aws:old-images --json
```

This returns JSON with `count` (number of objects) and `bytes` (total size). Record these numbers -- you will compare them against the destination after migration.

For a human-readable summary:

```bash
rclone size aws:old-images
```

## Step 3: Do a Dry Run First

Always preview what will be transferred before committing:

```bash
rclone copy aws:old-images r2:new-images \
  --transfers 32 \
  --checkers 64 \
  --fast-list \
  --dry-run \
  --progress
```

This shows you every file that would be copied without actually transferring anything. Review the output to make sure it looks correct.

## Step 4: Run the Migration

### Option A: Direct rclone Command (Recommended for Control)

```bash
rclone copy aws:old-images r2:new-images \
  --transfers 32 \
  --checkers 64 \
  --fast-list \
  --progress \
  --log-file /tmp/s3-migration.log \
  --log-level INFO \
  --retries 5 \
  --retries-sleep 10s
```

**What each flag does:**

| Flag | Purpose |
|------|---------|
| `--transfers 32` | Run 32 file transfers in parallel. For 50GB of images, this provides excellent throughput. Increase to 64 if your network can handle it. |
| `--checkers 64` | Run 64 checker threads to compare source and destination in parallel. |
| `--fast-list` | Uses fewer API calls to list objects by fetching entire directory listings at once. Significantly faster for large buckets. |
| `--progress` | Shows real-time transfer progress (speed, ETA, files transferred). |
| `--log-file` | Writes detailed logs to a file for later review. |
| `--log-level INFO` | Logs each file transferred. Use `DEBUG` if you need to troubleshoot. |
| `--retries 5` | Retry failed transfers up to 5 times (handles transient network errors). |
| `--retries-sleep 10s` | Wait 10 seconds between retries to let temporary issues resolve. |

**Why `copy` and not `sync`:** The `copy` command only adds files to the destination and never deletes anything. This is safer for migration. Use `sync` only if you want to mirror and delete files in the destination that are not in the source.

### Option B: Use the Migration Helper Script

There is a helper script that automates the migration with built-in verification:

```bash
bash /home/ivan/Project/ai/s3-compatible-storage/scripts/s3-migrate.sh \
  aws:old-images r2:new-images --transfers 32
```

This script:
1. Verifies both rclone remotes exist
2. Checks source size before starting
3. Runs the migration with retries and logging
4. Automatically verifies object counts match after completion
5. Writes a timestamped log file to `/tmp/s3-migrate-YYYY-MM-DD_HH-MM-SS.log`

## Step 5: Performance Tuning

For 50GB of images, the default settings above should complete in roughly 15-45 minutes depending on your network. Here are ways to go faster:

### If You Have Many Small Files (e.g., Thumbnails)

```bash
rclone copy aws:old-images r2:new-images \
  --transfers 64 \
  --checkers 128 \
  --fast-list \
  --progress \
  --log-file /tmp/s3-migration.log \
  --log-level INFO \
  --retries 5 \
  --retries-sleep 10s
```

Higher parallelism helps when individual files are small since transfer overhead dominates.

### If You Have Large Files (e.g., High-Res Images > 100MB)

```bash
rclone copy aws:old-images r2:new-images \
  --transfers 16 \
  --checkers 32 \
  --fast-list \
  --progress \
  --s3-upload-cutoff 100M \
  --s3-chunk-size 100M \
  --log-file /tmp/s3-migration.log \
  --log-level INFO \
  --retries 5 \
  --retries-sleep 10s
```

Larger chunk sizes reduce the number of multipart upload parts and API calls for big files.

### If You Want to Limit Bandwidth

To avoid saturating your network connection:

```bash
rclone copy aws:old-images r2:new-images \
  --transfers 32 \
  --checkers 64 \
  --fast-list \
  --progress \
  --bwlimit 100M \
  --log-file /tmp/s3-migration.log \
  --log-level INFO
```

`--bwlimit 100M` caps bandwidth at 100 MB/s.

### Running the Migration in the Background

If you want to run the migration in a terminal and disconnect without stopping it:

```bash
nohup rclone copy aws:old-images r2:new-images \
  --transfers 32 \
  --checkers 64 \
  --fast-list \
  --log-file /tmp/s3-migration.log \
  --log-level INFO \
  --retries 5 \
  --retries-sleep 10s \
  > /tmp/s3-migration-stdout.log 2>&1 &

echo "Migration running in background. PID: $!"
echo "Monitor with: tail -f /tmp/s3-migration.log"
```

Or use `tmux` / `screen` to keep an interactive session alive.

---

## Step 6: Verify Everything Copied Correctly

Verification is critical. Use multiple methods to ensure data integrity.

### 6a. Compare Object Counts and Total Size

```bash
echo "=== Source (AWS S3) ==="
rclone size aws:old-images --json

echo "=== Destination (Cloudflare R2) ==="
rclone size r2:new-images --json
```

Both should return the same `count` and `bytes` values. If the byte counts differ slightly, it could be due to metadata differences, but the object count must match exactly.

### 6b. Use rclone check for File-by-File Verification

This is the most thorough verification method. It compares every file between source and destination:

```bash
rclone check aws:old-images r2:new-images \
  --fast-list \
  --one-way \
  --log-file /tmp/s3-migration-check.log \
  --log-level INFO
```

**What `rclone check` does:**
- Compares file sizes between source and destination
- Compares checksums/hashes where available (MD5 for S3/R2)
- `--one-way` checks that every file in the source exists in the destination (use this for migration verification)
- Reports any missing or mismatched files

If you want a bidirectional check (also reports extra files in the destination):

```bash
rclone check aws:old-images r2:new-images \
  --fast-list \
  --log-file /tmp/s3-migration-check.log \
  --log-level INFO
```

### 6c. Spot-Check Individual Files

Pick a few random files and verify them manually:

```bash
# List some files from source
rclone ls aws:old-images | head -5

# Check the same files exist in destination with matching sizes
rclone ls r2:new-images | head -5

# Compare metadata of a specific file
rclone lsl aws:old-images/path/to/specific-image.jpg
rclone lsl r2:new-images/path/to/specific-image.jpg
```

### 6d. Check the Migration Log for Errors

```bash
# Look for any errors in the log
grep -i "error" /tmp/s3-migration.log

# Count transferred files
grep -c "Copied" /tmp/s3-migration.log

# Look for retried transfers
grep -i "retry" /tmp/s3-migration.log
```

### 6e. Generate a File Listing Diff (Most Thorough)

For absolute certainty, generate full file listings from both sides and diff them:

```bash
# Generate sorted file listings (name and size)
rclone lsl aws:old-images | sort > /tmp/source-listing.txt
rclone lsl r2:new-images | sort > /tmp/dest-listing.txt

# Compare the listings
diff /tmp/source-listing.txt /tmp/dest-listing.txt
```

If `diff` produces no output, every file matches in name, size, and modification time.

---

## Step 7: Re-Run for Any Missed Files

If verification reveals missing files (due to network errors, timeouts, etc.), simply re-run the same `rclone copy` command. It is idempotent -- it only transfers files that are missing or different in the destination:

```bash
rclone copy aws:old-images r2:new-images \
  --transfers 32 \
  --checkers 64 \
  --fast-list \
  --progress \
  --log-file /tmp/s3-migration-retry.log \
  --log-level INFO \
  --retries 5 \
  --retries-sleep 10s
```

This will skip all files that already exist and match, and only transfer what is missing.

---

## Cost Considerations

- **AWS S3 egress**: Transferring 50GB out of AWS S3 (us-east-1) costs approximately $4.50 at $0.09/GB. This is the main cost.
- **AWS S3 GET requests**: Listing and reading objects incurs Class B operation charges ($0.0004 per 1,000 requests). For 50GB of images, this is typically under $1.
- **Cloudflare R2 ingress**: Free. R2 has zero egress fees and free data ingress.
- **R2 storage**: $0.015/GB/month for Standard storage. 50GB would cost $0.75/month.
- **R2 write operations**: $4.50 per million Class A operations. Typically under $1 for a 50GB image migration.

---

## Alternative: Cloudflare Sippy (Incremental Migration)

If you prefer a gradual migration where R2 pulls objects from S3 on-demand (lazy migration), Cloudflare offers **Sippy**:

```bash
wrangler r2 bucket sippy enable new-images
```

Sippy works by:
1. Serving requests from R2 if the object exists there
2. Fetching from the origin S3 bucket if not, then caching it in R2
3. Gradually migrating your data as it is accessed

This is useful if you want to cut over your application immediately without waiting for a full copy, but it does not guarantee all objects are migrated until they are each accessed at least once. For a complete, verified migration, the `rclone copy` approach described above is more reliable.

---

## Summary Checklist

1. [ ] Verify both rclone remotes work (`rclone lsd aws:` and `rclone lsd r2:`)
2. [ ] Record source bucket size (`rclone size aws:old-images --json`)
3. [ ] Dry run to preview (`rclone copy ... --dry-run`)
4. [ ] Run the migration (`rclone copy aws:old-images r2:new-images --transfers 32 ...`)
5. [ ] Compare object counts and sizes (`rclone size` on both)
6. [ ] Run `rclone check` for file-by-file verification
7. [ ] Check the log file for errors (`grep -i error /tmp/s3-migration.log`)
8. [ ] Re-run `rclone copy` if any files were missed
9. [ ] Update your application to point to the R2 bucket
10. [ ] Keep the AWS S3 source bucket around for a grace period before deleting
