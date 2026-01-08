# Android Navigation SDK Installation & Setup

## 1. Configure Credentials

### Secret Token Setup (Downloads)
Store your secret token with `Downloads:Read` scope in `~/.gradle/gradle.properties`:

```properties
MAPBOX_DOWNLOADS_TOKEN=YOUR_SECRET_MAPBOX_ACCESS_TOKEN
```

**Important**: This token is for downloading SDK dependencies from Mapbox Maven.

### Public Token Setup (Runtime)
Create `app/src/main/res/values/developer-config.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources xmlns:tools="http://schemas.android.com/tools">
    <string name="mapbox_access_token" translatable="false"
            tools:ignore="UnusedResources">YOUR_MAPBOX_ACCESS_TOKEN</string>
</resources>
```

## 2. Add Required Permissions

Add to `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

## 3. Configure Maven Repository

### For Android Studio Arctic Fox+ (Gradle v6.0+)

Configure `settings.gradle`:

```gradle
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven {
            url 'https://api.mapbox.com/downloads/v2/releases/maven'
            authentication {
                basic(BasicAuthentication)
            }
            credentials {
                username = "mapbox"
                password = MAPBOX_DOWNLOADS_TOKEN
            }
        }
    }
}
```

**Alternative**: Can also configure in project-level `build.gradle` under `allprojects.repositories`.

## 4. Module-Level Configuration

In `app/build.gradle`:

```gradle
android {
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    defaultConfig {
        minSdkVersion 21
    }
}

dependencies {
    // Core Navigation SDK
    implementation 'com.mapbox.navigationcore:android:3.18.0-beta.1'

    // UI Components (optional, but recommended)
    implementation 'com.mapbox.navigationcore:ui-components:3.18.0-beta.1'
}
```

### For NDK 27 Support (16 KB page size)

```gradle
dependencies {
    implementation 'com.mapbox.navigationcore:android-ndk27:3.18.0-beta.1'
    implementation 'com.mapbox.navigationcore:ui-components-ndk27:3.18.0-beta.1'
}
```

## 5. Sync Gradle

After configuration, sync Gradle files to download dependencies.

## Common Issues

### 401 Unauthorized Error
- Verify `MAPBOX_DOWNLOADS_TOKEN` is set correctly in `gradle.properties`
- Ensure token has `downloads:read` scope
- Check token is a **secret token** (starts with `sk.`), not public token

### Dependency Conflicts
- Navigation SDK and Maps SDK must use compatible NDK versions
- If using Flutter's `mapbox_maps_flutter`, it may conflict with native Navigation SDK
- Ensure consistent NDK version across all Mapbox dependencies

## Next Steps
After installation:
1. Initialize MapboxNavigation in your Activity
2. Request location permissions at runtime
3. Set up NavigationView or custom UI components
4. Request routes using Directions API
5. Start navigation session
