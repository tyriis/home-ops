# MinIO

High-performance object storage server compatible with Amazon S3.

## Setup

1. Copy the example environment file:

   ```bash
   cp .env.example .env
   ```

2. Edit `.env` and set your credentials:
   - `MINIO_ROOT_USER`: Admin username
   - `MINIO_ROOT_PASSWORD`: Admin password (minimum 8 characters)

3. Start the service:

   ```bash
   docker compose up -d
   ```

## Access

- **API**: <http://localhost:9000>
- **Console**: <http://localhost:9001>

## Configuration

### Reverse Proxy

If using a reverse proxy, set:

```env
MINIO_BROWSER_REDIRECT_URL=https://minio-console.example.com
MINIO_SERVER_URL=https://minio.example.com
```

### Volume Options

Use external volume:

```env
VOLUME_EXTERNAL=true
VOLUME_NAME=my_existing_volume
```

Or use a bind mount by modifying compose.yaml volumes section.
