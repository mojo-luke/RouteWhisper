# 🚀 RouteWhisper

**The intelligent road trip companion that narrates interesting facts and suggests stops along your journey.**

RouteWhisper combines real-time navigation with AI-powered storytelling to transform your road trips into discovery adventures. Get fascinating facts about landmarks as you drive by, discover hidden gems along your route, and collaborate with your travel companions to create the perfect journey.

## 🎯 Features

- **🗣️ AI Narration**: Hear interesting facts about towns, landmarks, and POIs as you drive
- **🎯 Smart Recommendations**: Get personalized stop suggestions based on your interests and time budget
- **👥 Companion Mode**: Collaborate with passengers to plan stops and discoveries
- **🗓️ Multi-Day Planning**: Break long trips into manageable days with hotel suggestions
- **⛽ Essential Services**: Find gas stations, restrooms, and other travel necessities
- **📱 Safety-First Design**: Driver-optimized UI with voice controls and large touch targets

## 📁 Project Structure

```
RouteWhisper/
├── frontend/          # Flutter mobile app + native Android (Mapbox Navigation SDK)
│   ├── lib/                # Dart source (services, widgets, screens)
│   ├── android/            # Native Android (Kotlin) — MapActivity, FlutterEngine
│   ├── integration_test/   # Dart integration tests
│   └── UX.md               # UX rules
├── backend/           # Python FastAPI + Redis + Postgres + MongoDB (via Docker)
│   ├── app/                # Application code
│   ├── tests/              # pytest tests
│   └── DOCKER_SETUP.md     # Quick start
├── docs/mapbox/       # 21-file local Mapbox SDK reference library
├── Claude.md          # Instructions for Claude Code sessions
├── Overview.md        # Product vision and design decisions
└── Development-Roadmap.md  # Single source of truth for status
```

## 🛠️ Development Setup

### Prerequisites

- **Flutter SDK**: ^3.3.2
- **Python**: ^3.9
- **Node.js**: ^18 (for development tools)
- **PostgreSQL**: ^13 (for backend database)
- **Redis**: ^6 (for caching)

### Backend Setup (Docker — preferred)

```bash
cd backend
cp env.example .env  # add your MAPBOX_ACCESS_TOKEN
docker-compose up -d
```

Starts FastAPI (`:8000`), Redis (`:6379`), Postgres (`:5432`), MongoDB (`:27017`). See `backend/DOCKER_SETUP.md` for details.

API docs at http://localhost:8000/docs.

### Backend Setup (without Docker)

```bash
cd backend
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
cp env.example .env  # add your keys
cd app && python main.py
```

### Frontend Setup

1. **Navigate to frontend directory**
   ```bash
   cd frontend
   ```

2. **Install Flutter dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the Flutter app**
   ```bash
   flutter run
   ```

## 📊 Status

See [Development-Roadmap.md](Development-Roadmap.md) for the canonical list.

**The headline feature is shipped.** Both the per-POI Wikipedia-driven
narration and the authored drive monologue (v1, six slices A–F) are
running. The companion speaks during the drive, anchored to facts and
to towns; vibe controls let the user shape what it talks about.

Also working today: turn-by-turn navigation (Mapbox), route calculation,
POI discovery along route and during active navigation, multi-stop
waypoint management, trip CRUD + new-trip wizard, trip canvas v1
(route viewer), Discoveries timeline, narration mode preferences,
"Take me there" mid-nav re-routing.

Deferred until there's a real reason to build them: lodging integration
(awaiting partnership), buddy mode, polygon-aware region narration, voice
talkback (STT), multi-day trip handling, iOS port, and everything in
Phase 2 (CarPlay / Android Auto) and Phase 3.

## 🔧 API Documentation

With the backend running:
- Interactive: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc
- Health: http://localhost:8000/health

## 📝 Contributing

Private project. See [Development-Roadmap.md](Development-Roadmap.md) for the development plan and [Claude.md](Claude.md) for codebase conventions.

## 📄 License

Private Project - All Rights Reserved

---

**Ready to start your intelligent road trip? Let's build something amazing! 🚗💨** 