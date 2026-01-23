# 🐳 Docker Setup for RouteWhisper Backend

Quick start guide for running the RouteWhisper backend with Docker.

## Prerequisites

- Docker Desktop installed and running
- `.env` file with your Mapbox API token

## Quick Start

### 1. Start All Services

```bash
cd backend
docker-compose up -d
```

This starts:
- ✅ **Backend API** (FastAPI) on `http://localhost:8000`
- ✅ **Redis** (caching) on `localhost:6379`
- ✅ **PostgreSQL** (database) on `localhost:5432`
- ✅ **MongoDB** (flexible data) on `localhost:27017`

### 2. Check Status

```bash
docker-compose ps
```

### 3. View Logs

```bash
# All services
docker-compose logs -f

# Just backend
docker-compose logs -f backend

# Just Redis
docker-compose logs -f redis
```

### 4. Test the API

Open your browser to:
- **API Docs**: http://localhost:8000/docs
- **Health Check**: http://localhost:8000/health
- **POI Discovery**: POST to http://localhost:8000/api/v1/route/pois

### 5. Stop Services

```bash
docker-compose down
```

To also remove volumes (delete all data):
```bash
docker-compose down -v
```

## Development

### Hot Reload

The backend service has hot reload enabled. Any changes to `app/` files will automatically restart the server.

### Rebuild After Dependency Changes

If you modify `requirements.txt`:

```bash
docker-compose build backend
docker-compose up -d backend
```

### Access Container Shell

```bash
docker-compose exec backend bash
```

### View Redis Keys

```bash
docker-compose exec redis redis-cli
> KEYS *
> GET poi_cache:...
```

## Environment Variables

The backend service uses environment variables from `.env`:

```env
# Required
MAPBOX_ACCESS_TOKEN=pk.your_token_here

# Optional (auto-configured in Docker)
REDIS_URL=redis://redis:6379
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_USER=routewhisper
POSTGRES_PASSWORD=routewhisper_dev
POSTGRES_DB=routewhisper
MONGODB_URL=mongodb://routewhisper:routewhisper_dev@mongodb:27017
```

## Troubleshooting

### Port Already in Use

If port 8000, 6379, 5432, or 27017 is already in use:

1. **Option 1**: Stop the conflicting service
2. **Option 2**: Change ports in `docker-compose.yml`:
   ```yaml
   ports:
     - "8001:8000"  # Map host 8001 to container 8000
   ```

### Backend Won't Start

Check logs:
```bash
docker-compose logs backend
```

Common issues:
- Missing `.env` file → Copy from `env.example`
- Invalid Mapbox token → Check `.env` MAPBOX_ACCESS_TOKEN
- Redis not ready → Wait 10 seconds and try again

### Clear Cache

```bash
docker-compose exec redis redis-cli FLUSHALL
```

## Production Notes

For production deployment:

1. **Remove `--reload`** from Dockerfile CMD
2. **Use production-grade secrets** (not hardcoded passwords)
3. **Add nginx** reverse proxy
4. **Use Docker secrets** for sensitive data
5. **Set proper resource limits**

## Architecture

```
┌─────────────────────────────────────────────┐
│ Android Emulator (10.0.2.2)                │
│ ↓ calls http://10.0.2.2:8000               │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│ Docker Host (localhost)                     │
│ ┌─────────────────────────────────────────┐ │
│ │ Backend Container (port 8000)           │ │
│ │ - FastAPI + uvicorn                     │ │
│ │ - Connects to Redis/Postgres/MongoDB   │ │
│ └─────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────┐ │
│ │ Redis Container (port 6379)             │ │
│ └─────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────┐ │
│ │ PostgreSQL Container (port 5432)        │ │
│ └─────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────┐ │
│ │ MongoDB Container (port 27017)          │ │
│ └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

---

**Need Help?** Check logs with `docker-compose logs -f backend`
