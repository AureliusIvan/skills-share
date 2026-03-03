# Setting Up CORS and Presigned URLs for Cloudflare R2 Bucket `app-uploads`

This guide walks through configuring CORS on your R2 bucket so your frontend at `https://myapp.com` can upload files directly via the browser, and setting up presigned URLs for secure, temporary download links.

---

## Part 1: CORS Configuration

### Why CORS Is Needed

When your frontend JavaScript at `https://myapp.com` makes requests directly to the R2 S3 API endpoint (e.g., via `fetch` or `XMLHttpRequest` to upload a file), the browser enforces the Same-Origin Policy. Since the R2 endpoint (`https://<ACCOUNT_ID>.r2.cloudflarestorage.com`) is a different origin than `https://myapp.com`, the browser will block the request unless R2 responds with the appropriate CORS headers. You must configure CORS rules on the bucket to allow this.

### Step 1: Create the CORS Configuration File

Create a file called `cors.json` with the following content:

```json
[
  {
    "AllowedOrigins": ["https://myapp.com"],
    "AllowedMethods": ["GET", "PUT", "HEAD"],
    "AllowedHeaders": [
      "Content-Type",
      "Content-Length",
      "Content-MD5",
      "Authorization",
      "x-amz-content-sha256",
      "x-amz-date",
      "x-amz-security-token",
      "x-amz-user-agent"
    ],
    "ExposeHeaders": [
      "ETag",
      "Content-Length",
      "Content-Type",
      "x-amz-request-id"
    ],
    "MaxAgeSeconds": 3600
  }
]
```

**Explanation of each field:**

| Field | Value | Purpose |
|-------|-------|---------|
| `AllowedOrigins` | `["https://myapp.com"]` | Only your frontend origin can make cross-origin requests to this bucket. Use the exact scheme + host (no trailing slash, no path). |
| `AllowedMethods` | `["GET", "PUT", "HEAD"]` | `PUT` is required for direct file uploads via presigned URLs. `GET` is required for presigned download URLs. `HEAD` allows your app to check object metadata. |
| `AllowedHeaders` | *(see above)* | These are the headers your frontend will send. R2 does **not** support the wildcard `*` for `AllowedHeaders`, so each header must be listed explicitly. The `x-amz-*` headers are needed for AWS Signature V4 signing. |
| `ExposeHeaders` | *(see above)* | These headers from R2's response are made accessible to your frontend JavaScript. `ETag` is important for verifying uploads completed correctly. |
| `MaxAgeSeconds` | `3600` | The browser caches the preflight (OPTIONS) response for 1 hour, reducing repeated preflight requests. Maximum allowed by R2 is 86,400 (24 hours). |

**Important R2-specific notes:**
- `AllowedOrigins` must use the format `scheme://host[:port]` -- no paths allowed.
- R2 does **not** support wildcard `*` in `AllowedHeaders`. You must list each header explicitly.
- CORS changes can take up to 30 seconds to propagate after applying.
- POST is not included in `AllowedMethods` because R2 does not support POST-based multipart form uploads. Direct uploads to R2 use PUT with presigned URLs.

### Step 2: Apply CORS with Wrangler

Since you have Wrangler installed, apply the CORS configuration:

```bash
wrangler r2 bucket cors set app-uploads --file cors.json
```

### Step 3: Verify the CORS Configuration

Confirm the rules were applied correctly:

```bash
wrangler r2 bucket cors list app-uploads
```

This should return the JSON rules you just applied.

### Step 4: Test CORS (Optional)

You can test that CORS is working by sending a preflight request with `curl`:

```bash
curl -X OPTIONS "https://<ACCOUNT_ID>.r2.cloudflarestorage.com/app-uploads/test-key" \
  -H "Origin: https://myapp.com" \
  -H "Access-Control-Request-Method: PUT" \
  -H "Access-Control-Request-Headers: Content-Type, x-amz-content-sha256, x-amz-date, Authorization" \
  -i
```

Replace `<ACCOUNT_ID>` with your Cloudflare account ID. You should see response headers including:
- `Access-Control-Allow-Origin: https://myapp.com`
- `Access-Control-Allow-Methods: GET, PUT, HEAD`

### Adding Additional Origins

If you also need to support a local development environment, add its origin to the `AllowedOrigins` array:

```json
[
  {
    "AllowedOrigins": [
      "https://myapp.com",
      "http://localhost:3000"
    ],
    "AllowedMethods": ["GET", "PUT", "HEAD"],
    "AllowedHeaders": [
      "Content-Type",
      "Content-Length",
      "Content-MD5",
      "Authorization",
      "x-amz-content-sha256",
      "x-amz-date",
      "x-amz-security-token",
      "x-amz-user-agent"
    ],
    "ExposeHeaders": [
      "ETag",
      "Content-Length",
      "Content-Type",
      "x-amz-request-id"
    ],
    "MaxAgeSeconds": 3600
  }
]
```

Then re-apply with `wrangler r2 bucket cors set app-uploads --file cors.json`.

---

## Part 2: Presigned URLs for Downloads

Presigned URLs let you generate temporary, shareable links to private objects in your R2 bucket. The URL embeds the authentication signature and an expiration time, so anyone with the link can download the file without needing R2 credentials -- but only until the URL expires.

### Key Facts About R2 Presigned URLs

- Generated client-side using AWS Signature V4 (no API call to R2 is needed to generate them).
- Support `GET`, `HEAD`, `PUT`, and `DELETE` operations.
- Expiry range: 1 second to 7 days (604,800 seconds).
- POST (multipart form uploads) is **not** supported.
- Presigned URLs only work with the S3 API domain (`https://<ACCOUNT_ID>.r2.cloudflarestorage.com`), **not** with custom domains.
- If the presigned URL will be accessed from a browser, CORS must be configured on the bucket (which we did in Part 1).

### Generating Presigned Download URLs with AWS CLI

Since you have the AWS CLI configured with profile `r2`, you can generate presigned download URLs as follows.

**Basic presigned URL (default 1-hour expiry):**

```bash
aws s3 presign s3://app-uploads/path/to/file.pdf \
  --profile r2 \
  --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com
```

**Custom expiry (e.g., 24 hours = 86400 seconds):**

```bash
aws s3 presign s3://app-uploads/path/to/file.pdf \
  --profile r2 \
  --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com \
  --expires-in 86400
```

**Maximum expiry (7 days = 604800 seconds):**

```bash
aws s3 presign s3://app-uploads/path/to/file.pdf \
  --profile r2 \
  --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com \
  --expires-in 604800
```

**Tip:** If you have `endpoint_url` set in your `~/.aws/config` under the `[profile r2]` section, you can omit the `--endpoint-url` flag:

```ini
# ~/.aws/config
[profile r2]
region = auto
output = json
endpoint_url = https://<ACCOUNT_ID>.r2.cloudflarestorage.com
```

Then the command simplifies to:

```bash
aws s3 presign s3://app-uploads/path/to/file.pdf --profile r2 --expires-in 86400
```

### Generating Presigned URLs Programmatically (Node.js)

For a web app backend, you will most likely generate presigned URLs in your server code. Here is an example using the AWS SDK for JavaScript v3:

```javascript
import { S3Client, GetObjectCommand, PutObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

const s3Client = new S3Client({
  region: "auto",
  endpoint: "https://<ACCOUNT_ID>.r2.cloudflarestorage.com",
  credentials: {
    accessKeyId: process.env.R2_ACCESS_KEY_ID,
    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
  },
});

// Generate a presigned download URL (GET)
async function getDownloadUrl(key, expiresInSeconds = 3600) {
  const command = new GetObjectCommand({
    Bucket: "app-uploads",
    Key: key,
  });

  const url = await getSignedUrl(s3Client, command, {
    expiresIn: expiresInSeconds,
  });

  return url;
}

// Generate a presigned upload URL (PUT)
async function getUploadUrl(key, contentType, expiresInSeconds = 3600) {
  const command = new PutObjectCommand({
    Bucket: "app-uploads",
    Key: key,
    ContentType: contentType,
  });

  const url = await getSignedUrl(s3Client, command, {
    expiresIn: expiresInSeconds,
  });

  return url;
}

// Usage examples:
// const downloadUrl = await getDownloadUrl("user-files/report.pdf", 86400);
// const uploadUrl = await getUploadUrl("user-files/avatar.png", "image/png", 900);
```

**Install the required packages:**

```bash
npm install @aws-sdk/client-s3 @aws-sdk/s3-request-presigner
```

### Using Presigned URLs on the Frontend

**Downloading a file** -- redirect the user or use an anchor tag:

```javascript
// Your backend API returns a presigned download URL
const response = await fetch("/api/download-url?file=report.pdf");
const { url } = await response.json();

// Option 1: Open in new tab
window.open(url, "_blank");

// Option 2: Create a download link
const link = document.createElement("a");
link.href = url;
link.download = "report.pdf";
link.click();
```

**Uploading a file directly from the browser** -- use the presigned PUT URL:

```javascript
async function uploadFile(file) {
  // 1. Get a presigned upload URL from your backend
  const response = await fetch("/api/upload-url", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      filename: file.name,
      contentType: file.type,
    }),
  });
  const { url } = await response.json();

  // 2. Upload directly to R2 using the presigned URL
  const uploadResponse = await fetch(url, {
    method: "PUT",
    headers: {
      "Content-Type": file.type,
    },
    body: file,
  });

  if (!uploadResponse.ok) {
    throw new Error(`Upload failed: ${uploadResponse.status}`);
  }

  // 3. Verify upload succeeded by checking the ETag
  const etag = uploadResponse.headers.get("ETag");
  console.log("Upload complete, ETag:", etag);

  return { success: true, etag };
}

// Usage with a file input element:
// document.getElementById("fileInput").addEventListener("change", (e) => {
//   uploadFile(e.target.files[0]);
// });
```

---

## Part 3: Recommended Backend API Endpoints

To tie everything together, your backend should expose two API endpoints that generate presigned URLs. This keeps your R2 credentials on the server and only gives the frontend short-lived, scoped URLs.

### Example API Design

| Endpoint | Method | Purpose | Parameters |
|----------|--------|---------|------------|
| `/api/upload-url` | POST | Generate presigned PUT URL | `filename`, `contentType` |
| `/api/download-url` | GET | Generate presigned GET URL | `file` (object key) |

**Security considerations for your backend:**

1. **Authenticate the user** before generating any presigned URLs. Do not expose these endpoints publicly.
2. **Validate the file key/path** to prevent directory traversal or access to other users' files. A common pattern is to prefix the key with the user's ID: `users/{userId}/{filename}`.
3. **Validate content type and file size** on the backend to restrict what types and sizes of files can be uploaded.
4. **Set short expiry times** for upload URLs (e.g., 5-15 minutes) since the user should upload immediately after requesting the URL. Download URLs can have longer expiry (e.g., 1-24 hours) depending on your use case.
5. **Never expose your R2 credentials** to the frontend. All presigned URL generation must happen server-side.

---

## Summary of Commands

| Action | Command |
|--------|---------|
| Apply CORS | `wrangler r2 bucket cors set app-uploads --file cors.json` |
| Verify CORS | `wrangler r2 bucket cors list app-uploads` |
| Remove CORS | `wrangler r2 bucket cors delete app-uploads` |
| Presigned download URL (1hr) | `aws s3 presign s3://app-uploads/file.pdf --profile r2 --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com` |
| Presigned download URL (24hr) | `aws s3 presign s3://app-uploads/file.pdf --profile r2 --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com --expires-in 86400` |

---

## Troubleshooting

### CORS Errors in Browser Console

- **"No 'Access-Control-Allow-Origin' header is present"** -- Verify `AllowedOrigins` includes your exact origin (scheme + host, no trailing slash). Check with `wrangler r2 bucket cors list app-uploads`.
- **"Method not allowed"** -- Ensure the HTTP method used (GET, PUT, etc.) is listed in `AllowedMethods`.
- **"Request header field X is not allowed"** -- The header your frontend sends is not in `AllowedHeaders`. Add it explicitly (R2 does not support wildcard headers).
- **Changes not taking effect** -- CORS rule updates can take up to 30 seconds to propagate. Wait and retry.

### Presigned URL Issues

- **"SignatureDoesNotMatch"** -- Ensure the `--endpoint-url` matches your R2 endpoint exactly. Also verify the credentials in your `r2` profile are correct and have not been rotated.
- **"AccessDenied"** -- Your R2 API token may not have the necessary permissions. Ensure it has "Object Read & Write" access for the `app-uploads` bucket.
- **"Request has expired"** -- The presigned URL has passed its expiration time. Generate a new one.
- **Presigned URL works with curl but not in browser** -- This is a CORS issue. Ensure CORS is configured correctly (Part 1 above).
- **URL does not work with custom domain** -- Presigned URLs only work with the S3 API endpoint (`https://<ACCOUNT_ID>.r2.cloudflarestorage.com`), not custom domains attached to the bucket.
