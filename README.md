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
├── frontend/          # Flutter mobile app
│   ├── lib/           # Dart source code
│   ├── assets/        # Images, icons, and other assets
│   └── pubspec.yaml   # Flutter dependencies
├── backend/           # Python FastAPI backend
│   ├── app/           # Application code
│   ├── tests/         # Test files
│   ├── requirements.txt # Python dependencies
│   └── env.example    # Environment variables template
├── docs/              # Documentation
├── Overview.md        # Detailed feature specifications
└── Development-Roadmap.md # Step-by-step development plan
```

## 🛠️ Development Setup

### Prerequisites

- **Flutter SDK**: ^3.3.2
- **Python**: ^3.9
- **Node.js**: ^18 (for development tools)
- **PostgreSQL**: ^13 (for backend database)
- **Redis**: ^6 (for caching)

### Backend Setup

1. **Navigate to backend directory**
   ```bash
   cd backend
   ```

2. **Create virtual environment**
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

3. **Install dependencies**
   ```bash
   pip install -r requirements.txt
   ```

4. **Set up environment variables**
   ```bash
   cp env.example .env
   # Edit .env with your actual API keys and database URLs
   ```

5. **Run the backend**
   ```bash
   cd app
   python main.py
   ```

   The API will be available at `http://localhost:8000`
   API Documentation: `http://localhost:8000/docs`

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

## 📊 Development Progress

Current Status: **Step 1 - Project Setup & Architecture** ✅

See [Development-Roadmap.md](Development-Roadmap.md) for detailed progress tracking.

## 🔧 API Documentation

Once the backend is running, visit:
- **Interactive API Docs**: http://localhost:8000/docs
- **ReDoc Documentation**: http://localhost:8000/redoc
- **Health Check**: http://localhost:8000/health

## 🎯 Next Steps

1. **Complete Step 1**: Finish project setup and architecture
2. **Step 2**: Implement basic navigation foundation with Mapbox
3. **Step 3**: Build POI data pipeline
4. **Step 4**: Add core narration system

## 📝 Contributing

This is currently a private development project. See [Development-Roadmap.md](Development-Roadmap.md) for the complete development plan.

## 📄 License

Private Project - All Rights Reserved

---

**Ready to start your intelligent road trip? Let's build something amazing! 🚗💨** 