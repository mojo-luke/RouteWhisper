# Mapbox Navigation SDK for Android - Overview

## Current Version
v3.18.0-beta.1

## Overview
The Navigation SDK is an all-in-one solution for building a navigation experience in your car or in your mobile application.

## Key Features
- **Raw location signal enhancement** - GPS filtering and dead reckoning
- **Routing and rerouting** (online and offline)
- **Traffic, incidents, and closures avoidance**
- **Alternative routes generation** during drives
- **Route line rendering**
- **Navigation camera controls**
- **Voice instructions playback**

## System Requirements
- **Kotlin**: 1.7.0 or higher
- **Android SDK**: 21 or higher
- **NDK**: 23 (default) or NDK 27 (available since v3.11.0)
- **Java**: 8 for sourceCompatibility and targetCompatibility

## NDK Support Details

### NDK 23 (Default)
Default artifacts without 16 KB page size support

### NDK 27 (Available since v3.11.0)
With 16 KB page size support.
**Implementation format**: `com.mapbox.navigationcore:android-ndk27:3.18.0-beta.1`

## Language Support
- SDK is **built with Kotlin**
- **100% interoperable with Java** - Java applications can use all public APIs

## Integrated Services
The SDK pre-integrates with:
- Mapbox Maps SDK
- Navigation APIs
- Search
- MapGPT (AI voice assistant)
- EV routing capabilities

## Usage Conditions
- **Attribution required** per Mapbox Maps SDK documentation
- Distributed under **Mapbox Terms of Service**
- Subject to **Mapbox pricing** structure

## Documentation
- Main Guide: https://docs.mapbox.com/android/navigation/guides/
- Installation: https://docs.mapbox.com/android/navigation/guides/get-started/install/
- UI Components: https://docs.mapbox.com/android/navigation/guides/ui-components/
