plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.mela"
    // API 36 — required for modern FGS types + permission_handler symbols
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.mela"
        // Pinned at 24 (was flutter.minSdkVersion = 21): ffmpeg_kit min-gpl
        // requires API 24+. 24+ covers 99%+ of active devices.
        minSdk = 24
        // targetSdk 34+ required for FOREGROUND_SERVICE_DATA_SYNC
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Keep ONE universal APK (no --split-per-abi): ship 32-bit arm + 64-bit
        // arm only. x86 / x86_64 are emulator-only ABIs — no consumer phone runs
        // them. Dropping them removes a third+fourth copy of every .so
        // (~50 MB combined in the last build) from the unified APK.
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")

            isMinifyEnabled = true
            isShrinkResources = true

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )

            // Strip native debug symbols from packaged .so files. The NDK keeps
            // a copy in build/app/intermediates/stripped_native_libs for
            // symbolicating crash traces (upload to Play Console instead of
            // shipping them inside the APK).
            ndk {
                debugSymbolLevel = "SYMBOL_TABLE"
            }
        }
    }

    packaging {
        jniLibs {
            // .so files are already zip-page-aligned by AGP; keep compression
            // off for them (default) and avoid duplicate-ABI merge surprises.
            useLegacyPackaging = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
