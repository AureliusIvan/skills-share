# Setting Up CORS on Cloudflare R2 and Presigned URLs for Downloads

## Overview

This guide covers two tasks:

1. Configuring CORS on your R2 bucket `app-uploads` so your frontend at `https://myapp.com` can upload files directly from the browser.
2. Generating presigned URLs for secure, time-limited file downloads.

---

## Part 1: CORS Configuration

### Why CORS Is Needed

When your frontend at `https://myapp.com` makes a direct upload request to your R2 bucket, the browser enforces the Same-Origin Policy. Since R2's endpoint is on a different origin, the browser will block the request unless the R2 bucket responds with the appropriate CORS headers. Configuring CORS on the bucket tells R2 to include `Access-Control-Allow-Origin` and related headers in its responses.

### Method A: Using the AWS CLI (S3-Compatible API)

R2 is S3-compatible, so you can use the AWS CLI with the `--endpoint-url` flag and your `r2` profile to set the CORS configuration.

#### Step 1: Create the CORS Configuration File

Create a file named `cors-config.json`:

```json
{
  "CORSRules": [
    {
      "AllowedOrigins": ["https://myapp.com"],
      "AllowedMethods": ["GET", "PUT", "POST", "DELETE", "HEAD"],
      "AllowedHeaders": ["*"],
      "ExposeHeaders": ["ETag", "Content-Length", "Content-Type", "x-amz-request-id", "x-amz-meta-*"],
      "MaxAgeSeconds": 3600
    }
  ]
}
```

**Explanation of each field:**

| Field | Purpose |
|---|---|
| `AllowedOrigins` | Only `https://myapp.com` is permitted to make cross-origin requests. Use `["*"]` during development if needed, but restrict in production. |
| `AllowedMethods` | `PUT` and `POST` are needed for uploads. `GET` and `HEAD` for downloads and metadata checks. `DELETE` if you want to allow client-side deletion. |
| `AllowedHeaders` | `"*"` allows all headers. This is required because upload libraries often send custom headers like `Content-Type`, `x-amz-meta-*`, etc. |
| `ExposeHeaders` | Headers that the browser is allowed to read from the response. `ETag` is important for multipart upload verification. |
| `MaxAgeSeconds` | How long the browser caches the preflight (OPTIONS) response. 3600 seconds (1 hour) reduces preflight requests. |

#### Step 2: Apply the CORS Configuration

```bash
aws s3api put-bucket-cors \
  --bucket app-uploads \
  --cors-configuration file://cors-config.json \
  --profile r2 \
  --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com
```

Replace `<ACCOUNT_ID>` with your Cloudflare account ID. You can find this in the Cloudflare dashboard under **R2 > Overview**.

#### Step 3: Verify the CORS Configuration

```bash
aws s3api get-bucket-cors \
  --bucket app-uploads \
  --profile r2 \
  --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com
```

Expected output:

```json
{
    "CORSRules": [
        {
            "AllowedHeaders": ["*"],
            "AllowedMethods": ["GET", "PUT", "POST", "DELETE", "HEAD"],
            "AllowedOrigins": ["https://myapp.com"],
            "ExposeHeaders": ["ETag", "Content-Length", "Content-Type", "x-amz-request-id", "x-amz-meta-*"],
            "MaxAgeSeconds": 3600
        }
    ]
}
```

### Method B: Using Wrangler

As of Wrangler v3+, you can manage R2 bucket CORS via the `wrangler` CLI.

#### Step 1: Create a CORS Policy File

Create a file named `cors-policy.json`:

```json
[
  {
    "allowedOrigins": ["https://myapp.com"],
    "allowedMethods": ["GET", "PUT", "POST", "DELETE", "HEAD"],
    "allowedHeaders": ["*"],
    "exposeHeaders": ["ETag", "Content-Length", "Content-Type"],
    "maxAgeSeconds": 3600
  }
]
```

> **Note:** Wrangler uses camelCase keys rather than the PascalCase used by the S3 API.

#### Step 2: Apply with Wrangler

```bash
wrangler r2 bucket cors put app-uploads --rules ./cors-policy.json
```

#### Step 3: Verify with Wrangler

```bash
wrangler r2 bucket cors list app-uploads
```

### Testing CORS Manually

You can verify CORS is working by sending a preflight request with `curl`:

```bash
curl -i -X OPTIONS \
  -H "Origin: https://myapp.com" \
  -H "Access-Control-Request-Method: PUT" \
  -H "Access-Control-Request-Headers: Content-Type" \
  "https://<ACCOUNT_ID>.r2.cloudflarestorage.com/app-uploads/test-key"
```

A successful response should include:

```
HTTP/2 200
access-control-allow-origin: https://myapp.com
access-control-allow-methods: GET, PUT, POST, DELETE, HEAD
access-control-allow-headers: *
access-control-max-age: 3600
```

---

## Part 2: Presigned URLs for Downloads

Presigned URLs allow you to grant temporary, time-limited access to private objects in your R2 bucket without exposing your credentials. The URL contains a signature that authorizes the request for a specified duration.

### Prerequisites

You need an R2 API token with read permissions. Go to **Cloudflare Dashboard > R2 > Manage R2 API Tokens** and create a token with **Object Read** permission for the `app-uploads` bucket. Note the **Access Key ID** and **Secret Access Key**.

Make sure your AWS CLI profile `r2` is configured with these credentials:

```bash
aws configure --profile r2
# AWS Access Key ID: <your R2 access key>
# AWS Secret Access Key: <your R2 secret key>
# Default region name: auto
# Default output format: json
```

### Method A: Presigned URLs via AWS CLI

#### Generate a Presigned Download URL

```bash
aws s3 presign \
  "s3://app-uploads/path/to/your-file.pdf" \
  --expires-in 3600 \
  --profile r2 \
  --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com
```

- `--expires-in 3600` sets the URL to expire after 1 hour (3600 seconds). Maximum is 604800 seconds (7 days).
- The output is a full URL with query parameters containing the signature.

**Example output:**

```
https://<ACCOUNT_ID>.r2.cloudflarestorage.com/app-uploads/path/to/your-file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=...&X-Amz-Date=...&X-Amz-Expires=3600&X-Amz-Signature=...&X-Amz-SignedHeaders=host
```

### Method B: Presigned URLs in a Cloudflare Worker (Recommended for Production)

For production use, generate presigned URLs server-side using a Cloudflare Worker. This keeps your R2 credentials secure and lets you add authorization logic.

#### Step 1: Install the AWS SDK for Signing

```bash
npm install @aws-sdk/client-s3 @aws-sdk/s3-request-presigner
```

#### Step 2: Worker Code

Create `src/index.ts`:

```typescript
import { S3Client, GetObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

interface Env {
  R2_ACCESS_KEY_ID: string;
  R2_SECRET_ACCESS_KEY: string;
  R2_ENDPOINT: string;
  R2_BUCKET: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    // Add your own authentication check here
    // e.g., verify a JWT, check a session cookie, etc.
    const url = new URL(request.url);
    const key = url.searchParams.get("key");

    if (!key) {
      return new Response(JSON.stringify({ error: "Missing 'key' parameter" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const s3Client = new S3Client({
      region: "auto",
      endpoint: env.R2_ENDPOINT,
      credentials: {
        accessKeyId: env.R2_ACCESS_KEY_ID,
        secretAccessKey: env.R2_SECRET_ACCESS_KEY,
      },
    });

    const command = new GetObjectCommand({
      Bucket: env.R2_BUCKET,
      Key: key,
    });

    try {
      const presignedUrl = await getSignedUrl(s3Client, command, {
        expiresIn: 3600, // 1 hour
      });

      return new Response(JSON.stringify({ url: presignedUrl }), {
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "https://myapp.com",
        },
      });
    } catch (err) {
      return new Response(JSON.stringify({ error: "Failed to generate URL" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }
  },
};
```

#### Step 3: Wrangler Configuration

In your `wrangler.toml`:

```toml
name = "r2-presign-worker"
main = "src/index.ts"
compatibility_date = "2024-01-01"

[vars]
R2_BUCKET = "app-uploads"
R2_ENDPOINT = "https://<ACCOUNT_ID>.r2.cloudflarestorage.com"

# Store secrets using wrangler secret:
# wrangler secret put R2_ACCESS_KEY_ID
# wrangler secret put R2_SECRET_ACCESS_KEY
```

#### Step 4: Deploy Secrets and Worker

```bash
# Set secrets (you will be prompted to enter the values)
wrangler secret put R2_ACCESS_KEY_ID
wrangler secret put R2_SECRET_ACCESS_KEY

# Deploy the worker
wrangler deploy
```

#### Step 5: Usage from Your Frontend

```typescript
async function getDownloadUrl(fileKey: string): Promise<string> {
  const response = await fetch(
    `https://r2-presign-worker.<your-subdomain>.workers.dev?key=${encodeURIComponent(fileKey)}`,
    {
      headers: {
        // Include your auth token
        Authorization: `Bearer ${authToken}`,
      },
    }
  );

  if (!response.ok) {
    throw new Error("Failed to get download URL");
  }

  const data = await response.json();
  return data.url;
}

// Usage
const downloadUrl = await getDownloadUrl("uploads/report-2026.pdf");
window.open(downloadUrl); // or use in an <a> tag
```

### Method C: Presigned URLs with Node.js (Standalone Script)

If you need to generate presigned URLs from a Node.js backend:

```typescript
import { S3Client, GetObjectCommand, PutObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

const s3Client = new S3Client({
  region: "auto",
  endpoint: "https://<ACCOUNT_ID>.r2.cloudflarestorage.com",
  credentials: {
    accessKeyId: process.env.R2_ACCESS_KEY_ID!,
    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY!,
  },
});

// Generate a presigned URL for DOWNLOADING a file
async function getPresignedDownloadUrl(key: string, expiresInSeconds = 3600): Promise<string> {
  const command = new GetObjectCommand({
    Bucket: "app-uploads",
    Key: key,
  });
  return getSignedUrl(s3Client, command, { expiresIn: expiresInSeconds });
}

// Generate a presigned URL for UPLOADING a file (bonus)
async function getPresignedUploadUrl(
  key: string,
  contentType: string,
  expiresInSeconds = 3600
): Promise<string> {
  const command = new PutObjectCommand({
    Bucket: "app-uploads",
    Key: key,
    ContentType: contentType,
  });
  return getSignedUrl(s3Client, command, { expiresIn: expiresInSeconds });
}

// Example usage
const downloadUrl = await getPresignedDownloadUrl("documents/invoice.pdf");
console.log("Download URL:", downloadUrl);

const uploadUrl = await getPresignedUploadUrl("uploads/photo.jpg", "image/jpeg");
console.log("Upload URL:", uploadUrl);
```

---

## Part 3: Frontend Direct Upload Using Presigned URLs

To complete the picture, here is how your frontend at `https://myapp.com` would perform a direct upload to R2 using a presigned PUT URL:

```typescript
// 1. Request a presigned upload URL from your backend
const response = await fetch("/api/get-upload-url", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    filename: file.name,
    contentType: file.type,
  }),
});
const { uploadUrl } = await response.json();

// 2. Upload the file directly to R2
const uploadResponse = await fetch(uploadUrl, {
  method: "PUT",
  headers: {
    "Content-Type": file.type,
  },
  body: file, // The File object from an <input type="file">
});

if (uploadResponse.ok) {
  console.log("Upload successful!");
} else {
  console.error("Upload failed:", uploadResponse.status);
}
```

This works because:
- The presigned URL authorizes the PUT request without exposing credentials.
- The CORS configuration on the bucket allows `https://myapp.com` to make the cross-origin PUT request.
- The browser sends a preflight OPTIONS request first, R2 responds with the CORS headers, and then the browser proceeds with the actual PUT.

---

## Part 4: Security Considerations

### CORS

- **Restrict origins in production.** Never use `"*"` for `AllowedOrigins` in production. Only allow your exact domain(s).
- **Limit methods.** If your frontend only uploads (PUT) and downloads (GET), remove `DELETE` and `POST` from `AllowedMethods`.
- **Audit regularly.** Periodically check your CORS config to ensure it reflects your current frontend domains.

### Presigned URLs

- **Keep expiration short.** Use the shortest practical expiration. For downloads, 15-60 minutes is typical. For uploads, match your upload timeout.
- **Generate server-side only.** Never expose your R2 API credentials to the frontend. Always generate presigned URLs on a backend or Worker.
- **Add authentication.** Protect your presigned URL generation endpoint with authentication (JWT, session cookies, API keys) so only authorized users can request download/upload URLs.
- **Use per-object keys.** Generate presigned URLs for specific object keys. Do not create wildcard or bucket-level presigned URLs.
- **Log access.** Consider logging which users request presigned URLs for which objects for audit purposes.

### R2 API Token Permissions

When creating your R2 API token for presigned URL generation:

| Permission | When Needed |
|---|---|
| Object Read | For generating presigned download URLs (GetObject) |
| Object Read & Write | For generating both upload and download presigned URLs |
| Admin Read & Write | For managing bucket settings like CORS (put-bucket-cors) |

Create separate tokens with minimal permissions: one admin token for CORS management, and one read/write token for presigned URL generation.

---

## Quick Reference: All Commands

```bash
# --- CORS Setup (AWS CLI) ---
# Apply CORS
aws s3api put-bucket-cors \
  --bucket app-uploads \
  --cors-configuration file://cors-config.json \
  --profile r2 \
  --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com

# Verify CORS
aws s3api get-bucket-cors \
  --bucket app-uploads \
  --profile r2 \
  --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com

# Delete CORS (if needed)
aws s3api delete-bucket-cors \
  --bucket app-uploads \
  --profile r2 \
  --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com

# --- CORS Setup (Wrangler) ---
wrangler r2 bucket cors put app-uploads --rules ./cors-policy.json
wrangler r2 bucket cors list app-uploads

# --- Presigned URL (AWS CLI) ---
# Download URL
aws s3 presign \
  "s3://app-uploads/path/to/file.pdf" \
  --expires-in 3600 \
  --profile r2 \
  --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com

# --- Test CORS (curl) ---
curl -i -X OPTIONS \
  -H "Origin: https://myapp.com" \
  -H "Access-Control-Request-Method: PUT" \
  -H "Access-Control-Request-Headers: Content-Type" \
  "https://<ACCOUNT_ID>.r2.cloudflarestorage.com/app-uploads/test-key"

# --- Worker Deployment ---
wrangler secret put R2_ACCESS_KEY_ID
wrangler secret put R2_SECRET_ACCESS_KEY
wrangler deploy
```

---

## Troubleshooting

| Issue | Cause | Fix |
|---|---|---|
| `No 'Access-Control-Allow-Origin' header` in browser console | CORS not configured or wrong origin | Verify CORS config with `get-bucket-cors`. Check that `AllowedOrigins` matches your frontend URL exactly (including protocol and no trailing slash). |
| Preflight (OPTIONS) returns 403 | Missing CORS rule or wrong endpoint | Ensure CORS is applied to the correct bucket. Verify endpoint URL. |
| Presigned URL returns `SignatureDoesNotMatch` | Clock skew or wrong credentials | Ensure your system clock is synchronized. Verify the API token credentials match. |
| Presigned URL returns `AccessDenied` | Token lacks required permissions | Ensure the R2 API token has Object Read permission for the bucket. |
| Upload works in Postman but not in browser | CORS issue (Postman does not enforce CORS) | This confirms a CORS misconfiguration. Re-check `AllowedOrigins` and `AllowedMethods`. |
| `ExpiredToken` or `RequestTimeTooSkewed` | URL expired or clock drift | Generate a fresh presigned URL. Sync your server clock with NTP. |
