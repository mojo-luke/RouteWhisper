# 🚀 RouteWhisper App Setup Overview

## 🎯 Goal

Build a mobile-first navigation app in **Flutter** called **RouteWhisper** that:

- Uses **Mapbox** for real-time GPS navigation  
- Narrates interesting **facts about towns and landmarks** as the user drives  
- **Scans ahead** on the route to alert the user about upcoming POIs or events  
- Speaks aloud via **TTS (Text-to-Speech)**

---

## 🧱 Architecture Summary

### 📱 Client App (Flutter)

- Framework: Flutter  
- Map/Navigation SDK: `mapbox_navigation` plugin  
- TTS: Flutter TTS plugin or native bindings  
- Route tracking: Mapbox Navigation SDK's real-time location + route steps  
- Triggers narration based on distance and position

### 🧠 Backend (Route Discovery Engine)

- Language: Python - FastAPI
- Exposes API:  
  - `/upcoming-facts?lat=..&lng=..&route=..`  
- Responsibilities:  
  - Match geo-coordinates to points of interest or facts (landmarks, town history)  
  - Look up local events  
  - Return structured list of narratable items

### 📦 Data Sources

- 📍 Town Facts: Wikipedia, Wikidata, GeoNames  
- 🛍️ POIs: Yelp Fusion API, Google Places API (optionally)  
- 📅 Events: Eventbrite API, local event boards  
- 🧰 Custom curated DB of quirky/fun facts (optional)

---

## 🔧 Detailed Design Decisions

### 🗺️ **Route Pre-Analysis Strategy**

**Trigger: When User Sets Destination**
1. **Get Full Route** from Mapbox Directions API
2. **Extract Route Corridor** - All coordinates + buffer zone (1-2 miles each side)
3. **Batch Query All POIs** along the entire route upfront
4. **Pre-rank & Organize** facts by priority and location
5. **Cache Everything** for offline narration during drive

**Benefits:**
- ✅ No real-time API calls during navigation (faster, more reliable)
- ✅ Better fact selection - can see whole journey and pick best ones
- ✅ Smarter timing - can space out narrations optimally
- ✅ Offline capable - works with poor cell service while driving
- ✅ Cost efficient - batch API calls vs. continuous polling

### 🎯 **Fact Selection & Delivery Strategy**

**Per POI:**
- **1 "Best" fact** → Auto-narrated as you approach/pass
- **2-5 additional facts** → Available on-demand (tap screen, voice command)

**Fact Ranking Criteria:**
- **Uniqueness** - Quirky/surprising facts over common knowledge
- **Historical significance** - Major events over minor trivia  
- **Local relevance** - Town-specific vs. generic info
- **Brevity** - 10-15 second narrations vs. long stories

**User Experience Flow:**
```
Approaching POI → Auto-narrate top fact
↓
If user wants more → "Say 'more facts' or tap for 4 additional stories"
↓
User can browse/listen to additional facts
```

**Spacing Controls:**
- **Minimum gap** between auto-narrations (30-60 seconds)
- **Density controls** - limit to X facts per mile in dense areas
- **Speed adaptive** - longer gaps at highway speeds vs. city driving

### 🔍 **Hierarchical POI Strategy**

**Trip Context Detection:**
- **Cross-state/Long distance** (100+ miles): High-level landmarks only
- **Regional** (20-100 miles): Mix of major landmarks + significant towns  
- **Local/City** (< 20 miles): Granular details, local businesses, neighborhood history

**POI Categories by Trip Scale:**

**🛣️ Long Distance (Highway Focus):**
- State borders & welcome signs
- Major rivers, mountains, national parks
- Historic battlefields, monuments
- Significant cities (population > 50k)
- Famous roadside attractions

**🏙️ Regional (Mixed):**
- County seats, local landmarks
- Regional history (founding stories, local industries)
- Notable architecture, bridges
- Local festivals, cultural sites

**📍 Local/City (Granular):**
- Historic buildings, local businesses
- Neighborhood stories, street origins
- Local restaurants, art installations
- Small parks, community centers

### 🛣️ **Road Trip Stop Recommendations**

**Feature: Proactive Stop Suggestions**
- Periodically scan route for interesting stops that match user interests
- Present as optional detours with estimated time impact
- Allow users to add stops to their route seamlessly

**Stop Categories:**
- **🍷 Food & Drink**: Wineries, craft breweries, local diners, farmers markets
- **🛍️ Shopping**: Antique stores, local artisans, outlet malls, unique boutiques  
- **🏕️ Outdoor**: Campsites, hiking trails, scenic overlooks, state parks
- **🎭 Entertainment**: Museums, live music venues, festivals, local events
- **⛽ Practical**: Rest stops, gas stations, EV charging, lodging
- **📸 Photo Ops**: Instagram-worthy spots, scenic vistas, roadside attractions

**User Personalization:**
- **Interest Profiles**: Adventure, Foodie, History Buff, Shopper, Family Travel
- **Travel Style**: Fast route vs. Scenic route vs. Discovery mode
- **Time Budget**: Quick stops (15 min) vs. Extended visits (1+ hour)
- **Group Preferences**: Solo, couple, family with kids, seniors

**Recommendation Logic:**
- **Proximity**: Within 5-15 minutes off main route
- **Ratings**: High-rated establishments (4+ stars)
- **Timing**: Open when user will arrive
- **Uniqueness**: Local specialties, "hidden gems"
- **Seasonal**: Seasonal attractions, harvest times, weather-dependent

**User Experience:**
```
During route calculation → Pre-scan for stops matching user interests
↓
Periodically during trip → "In 20 miles: Award-winning winery, 8 min detour?"
↓
User accepts → Update route to include stop
↓
Approaching stop → Provide context/facts about the location
```

**Integration with Existing POI System:**
- **Narration POIs**: Historical facts, landmarks (passive listening)
- **Stop Recommendations**: Interactive suggestions requiring user decision
- **Hierarchy**: Stop suggestions respect trip scale (fewer on long trips, more on local)

### ⏰ **Time Budget Awareness**

**Concept: Adaptive Experience Based on Available Time**
- Users set their **time flexibility** at trip start or during journey
- App adjusts suggestion frequency and types based on time budget
- Creates personalized experience that respects user's schedule

**Time Budget Levels:**

**🏃 **In a Hurry** (Strict Schedule):**
- **Focus**: Passive narration only - POI facts and trivia as you pass
- **No stop suggestions**: Skip detour recommendations entirely
- **Quick essentials**: Only suggest gas/food if critically needed
- **Streamlined route**: Fastest path, minimal interruptions
- **Example**: "Passing through historic Gettysburg, site of the famous Civil War battle..."

**🚗 **Moderate Pace** (Some Flexibility):**
- **Focus**: Select high-value suggestions only
- **Limited stops**: Only "must-see" or highly-rated places (4.5+ stars)
- **Quick stops**: 15-30 minute experiences max
- **Strategic timing**: Suggestions aligned with meal times, rest stops
- **Example**: "Award-winning BBQ joint, 5 min detour - perfect for lunch?"

**🎒 **Plenty of Time** (Discovery Mode):**
- **Focus**: Full discovery experience with multiple options
- **Rich suggestions**: Antique stores, wineries, scenic detours, local events
- **Extended experiences**: Museums, hiking trails, multi-hour activities
- **Adventure mode**: "Hidden gem" recommendations, scenic routes
- **Example**: "Local farmers market + antique district + scenic overlook - 2 hour detour worth it?"

**Dynamic Adjustment:**
- **Real-time changes**: "Running late? Switch to hurry mode?" 
- **Smart detection**: App notices if user consistently skips suggestions
- **Contextual switching**: Auto-suggest time mode changes based on delays
- **Schedule awareness**: Integrate with calendar appointments if permitted

**Integration with Existing Features:**
- **Trip scale + Time budget**: Cross-country + hurry = major landmarks only
- **Companion mode**: Both users can adjust time preferences
- **Learning system**: Remember user patterns for future trips
- **Override options**: Quick toggle between modes during journey

**User Experience:**
```
Trip Planning → Set time budget → App customizes entire experience
↓
During trip → "Running ahead of schedule, switch to discovery mode?"
↓
Real-time adjustments → More/fewer suggestions based on current pace
```

### 🛏️ **Multi-Day Trip Planning**

**Concept: Break Long Journeys into Manageable Days**
- **Automatic detection**: Trips over 8-10 hours suggest multi-day options
- **Flexible segmentation**: Let users choose how to split their journey
- **Accommodation integration**: Suggest hotels/motels at optimal stopping points
- **Day-by-day itinerary**: Plan each day's route with appropriate POIs and stops

**Trip Segmentation Options:**

**📅 **Equal Days** (Balanced Approach):**
- **12-hour trip → 2 days**: ~6 hours driving per day
- **20-hour trip → 3 days**: ~7 hours driving per day
- **Optimal rest**: Factor in meal breaks, sightseeing time
- **Example**: "Split your 14-hour drive into 2 relaxed 7-hour days?"

**🎯 **Destination-Based** (Strategic Stops):**
- **Major cities**: "Stop in Nashville for the night, explore music scene"
- **Scenic areas**: "Overnight in Yellowstone, morning wildlife viewing"
- **Interest-based**: "Wine country overnight, multiple tastings"
- **Family-friendly**: "Stop at theme park city, kid-friendly hotel"

**🏨 **Accommodation Integration:**
- **Smart timing**: Suggest hotels when user will be tired (6-8 hours driving)
- **POI alignment**: Hotels near interesting evening activities
- **Price ranges**: Budget motels to luxury resorts based on preferences
- **Real-time booking**: Direct integration with hotel booking APIs
- **Backup options**: Multiple hotel choices in case of cancellations

**Day-by-Day Experience:**

**Day 1 Planning:**
- **Morning departure**: Start with full energy, can handle dense POI areas
- **Midday**: Lunch stop + local exploration
- **Afternoon**: Scenic route or major attractions
- **Evening**: Arrive at hotel, dinner recommendations nearby

**Day 2+ Planning:**
- **Morning**: Hotel checkout, breakfast recommendations
- **Route continuation**: Fresh POI discoveries for new day
- **Energy management**: Adjust suggestion intensity based on multi-day fatigue

**User Control:**
- **Flexible splits**: "Actually, let's do 3 days instead of 2"
- **Hotel preferences**: Chain hotels vs. boutique vs. camping
- **Activity level**: Relaxed vs. action-packed daily itineraries
- **Budget awareness**: Adjust accommodation and activity suggestions

**Integration with Existing Features:**
- **Time budget**: Multi-day trips naturally have more discovery time
- **Companion mode**: Both users can discuss overnight plans
- **Trip scale**: Cross-country trips often need multiple days
- **POI hierarchy**: Spread major attractions across multiple days

**Technical Considerations:**
- **Hotel APIs**: Integration with Booking.com, Hotels.com, Expedia
- **Route optimization**: Minimize backtracking across multiple days
- **Reservation management**: Track and reminder system for bookings
- **Weather planning**: Multi-day weather forecasting for outdoor activities

**User Experience Flow:**
```
Long trip detected → "Break into 2-3 days?" → User chooses split
↓
Suggest overnight cities → Show hotel options → User selects
↓
Plan Day 1 route → Day 1 POIs → Evening activities
↓
Plan Day 2 route → Day 2 POIs → Continue to destination
```

### 🚽 **Essential Travel Services**

**Concept: Practical Necessities for Road Trip Success**
- **Proactive suggestions** based on route, time, and user needs
- **Seamless integration** with existing POI and stop recommendation system
- **Emergency awareness** - Critical when traveling through remote areas

**Core Services:**

**⛽ **Gas Station Integration:**
- **Fuel level monitoring** - Remind users when tank is getting low
- **Price comparison** - Show cheapest gas along route
- **Brand preferences** - Filter for preferred stations (Shell, BP, etc.)
- **Amenities awareness** - Clean restrooms, food options, car wash
- **Strategic timing** - "Gas up now, next station is 80 miles"

**🚽 **Restroom Finder:**
- **Family-friendly** - Clean, safe facilities prioritized
- **Accessibility** - ADA compliant restrooms when needed
- **Emergency mode** - "Nearest restroom: 2 miles ahead at McDonald's"
- **Quality ratings** - User-generated cleanliness scores
- **24/7 availability** - Gas stations vs. rest stops vs. restaurants

**Integration with Existing Features:**

**Time Budget Awareness:**
- **In a hurry**: Only suggest when truly necessary
- **Plenty of time**: Include gas/restroom with other stop recommendations
- **Moderate pace**: Strategic combinations "Gas + lunch stop ahead"

**Multi-Day Planning:**
- **Morning departures**: "Gas up and restroom break before hitting the road"
- **End of day**: "Fill up near hotel for tomorrow's early start"

**Companion Mode:**
- **Passenger research**: "Next gas station has great reviews for cleanliness"
- **Driver alerts**: Voice notification when fuel is low

**Smart Suggestions:**
- **Combo opportunities**: "Shell station ahead - gas, restrooms, and Subway"
- **Route optimization**: Don't suggest detours when better options are ahead
- **Context awareness**: More frequent suggestions with kids in car

**Technical Integration:**
- **Fuel level APIs** - OBD-II integration where available
- **GasBuddy integration** - Real-time pricing data
- **Google Places API** - Restroom availability and ratings
- **User learning** - Remember preferred gas brands and restroom standards

### 👥 **Road Trip Buddy Mode**

**Concept: Equal Travel Companions**
- **Driver Mode**: Voice-controlled route updates, hands-free interaction for safety
- **Passenger Mode**: Full touch interface for browsing, planning, and route management
- **Equal decision-making**: Both can add/remove stops, just different interaction methods

**Both Companions Can:**
- **Add/remove stops**: Equal authority to modify the route
- **Browse recommendations**: See upcoming stops and opportunities
- **Share discoveries**: Point out interesting places to each other
- **Set preferences**: Influence what types of stops get suggested
- **Save favorites**: Build shared trip memory for future travels

**Driver Interaction (Safety-Optimized):**
- **Large touch targets**: Big, easy-to-tap buttons for quick decisions
- **Minimal taps**: Single tap to add/skip suggested stops
- **Voice commands**: Optional hands-free operation when preferred
- **Smart timing**: Suggestions appear during safe moments (straight roads, stopped)
- **Auto-dismiss**: Suggestions disappear after few seconds if not acted upon
- **Audio + Visual**: Both sound and visual cues for recommendations

**Passenger Interaction (Full Research Mode):**
- **Detailed browsing**: Full app access for in-depth research
- **Advanced features**: Read reviews, check hours, view photos, compare options
- **Route management**: Visual drag-and-drop for stops, complex reordering
- **Notification control**: Can customize what alerts the driver sees/hears

**Collaborative Features:**
- **Shared preferences**: Combined interest profiles influence suggestions
- **Real-time sync**: Changes from either person update instantly
- **Companion notifications**: "Alex added a lunch stop in 20 minutes"
- **Role flexibility**: Easy switching when driver/passenger roles change
- **Trip memory**: Shared history of successful stops and preferences

**Technical Implementation:**
- **Dual UI modes**: Driver interface vs. Passenger interface
- **Real-time sync**: Route changes instantly update navigation
- **Offline capability**: Passenger can browse cached recommendations without data
- **Multi-device**: Passenger can use their own phone/tablet

**User Experience Scenarios:**
```
Scenario 1: Discovery Mode
Passenger browses recommendations → Finds interesting winery → Adds to route
→ Driver gets voice notification → Confirms → Route updates automatically

Scenario 2: Research Mode  
App suggests antique store → Passenger reads reviews & checks inventory
→ Decides it's worth the stop → Adds to route → Shares photos with driver

Scenario 3: Group Decision
Multiple passengers see restaurant suggestion → Vote on it → Driver gets
group consensus → Makes final call via voice
```

---

## 🛠️ Core Flutter Packages

| Function          | Package                                            |
| ----------------- | -------------------------------------------------- |
| Map & navigation  | `mapbox_navigation`                                |
| Location tracking | `geolocator`, `location`                           |
| Text-to-Speech    | `flutter_tts` or `just_audio` + pre-rendered voice |
| HTTP API calls    | `http`, `dio`                                      |

---

## 🔁 Flow Overview

```plaintext
User enters destination
↓
Calculate route + POI corridor
↓
Batch fetch all facts along route
↓
Rank & organize by route position
↓
During navigation: trigger pre-loaded facts by GPS position
```

---

## 📱 Phase 2 Core Features

*Essential features to implement after core functionality is complete*

### **🚗 Vehicle Integration**

**Android Auto & Apple CarPlay Support:**
- **Essential for adoption** - Most users expect car integration for navigation apps
- **Safety compliance** - Built-in car systems are safer than handheld phones
- **Voice-first experience** - Natural fit for our hands-free design
- **Large screen optimization** - Better visibility for driver-friendly UI

**Implementation Priority:**
1. **Core app functionality first** - Ensure all features work perfectly on mobile
2. **CarPlay/Android Auto integration** - Adapt UI and interactions for car systems  
3. **Testing and refinement** - Extensive real-world driving tests

**Key Considerations:**
- **Simplified UI** - Car systems have strict interface guidelines
- **Voice optimization** - Even more critical in car environment
- **Connectivity handling** - Seamless handoff between phone and car
- **Performance** - Car systems have different resource constraints

---

## 🔮 Future Feature Considerations

*Features to consider for future versions and enhancements*

### **🚗 Car Integration & Ecosystem**
- **Voice assistant integration** - "Hey Google, add that winery to RouteWhisper"
- **Smart watch integration** - Quick glances at upcoming stops
- **OBD-II integration** - Fuel level awareness for gas station suggestions

### **⚡ Practical Travel Essentials**
- **Weather awareness** - "Storm ahead, indoor activity suggestions?"
- **Parking info** - Availability and cost at suggested stops
- **EV charging stations** - Growing necessity for electric vehicles

### **🌐 Offline & Connectivity**
- **Robust offline mode** - Download entire trip data for poor signal areas
- **Data usage controls** - Important for users with limited data plans
- **Progressive sync** - Smart background updates when connectivity returns

### **📱 User Experience Enhancements**
- **Accessibility features** - Voice navigation for visually impaired users
- **Multi-language support** - Local facts in user's preferred language
- **Battery optimization** - Long trips drain phones quickly
- **Emergency features** - Roadside assistance integration

### **💰 Business Model & Monetization**
- **Premium features** - Advanced POI data, unlimited stops, ad-free experience
- **Partner integrations** - Revenue from restaurant/hotel bookings
- **Local business partnerships** - Featured recommendations and sponsorships

### **📊 Technical & Community Features**
- **Error handling** - Robust fallbacks if APIs fail mid-trip
- **Trip memory/journals** - Save and share amazing discoveries
- **Community features** - User-generated content, trip sharing
- **Analytics dashboard** - Trip statistics and personal travel insights