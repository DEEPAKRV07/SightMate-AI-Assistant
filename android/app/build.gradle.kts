// android/app/build.gradle.kts
// Updated build configuration for SightMate refactoring
//
// Changes from baseline:
//   • NDK version pinned to 25.1.8937393 (stable with OpenCV4Android)
//   • externalNativeBuild: CMakeLists.txt wired in (builds sightmate_cv.so)
//   • ONNX Runtime: onnxruntime-android added as dependency
//   • abiFilters: arm64-v8a primary, armeabi-v7a secondary (drop x86 for APK size)
//   • minSdk: 24 (NNAPI requires API 27+; 24 allows graceful fallback)
//   • proguard: disabled for debug; ONNX keep rules in release

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace  = "com.sightmate.blindassist"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_21.toString()
    }

    defaultConfig {
        applicationId = "com.sightmate.blindassist"
        minSdk        = 24
        targetSdk     = flutter.targetSdkVersion
        versionCode   = flutter.versionCode
        versionName   = flutter.versionName

        // NDK ABI filters: arm64-v8a is modern Android (2017+); armeabi-v7a for older devices
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }

        // TFLite and ONNX Runtime require this for large model files
        multiDexEnabled = true
    }

    // ── NDK / C++ build ────────────────────────────────────────────────────────
    externalNativeBuild {
        cmake {
            path    = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    // ── Build types ────────────────────────────────────────────────────────────
    buildTypes {
        release {
            isMinifyEnabled   = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            isDebuggable    = true
            isMinifyEnabled = false
        }
    }

    // ── Packaging: strip duplicate native libs ─────────────────────────────────
    packaging {
        jniLibs {
            keepDebugSymbols += listOf("**/libsightmate_cv.so")
        }
        resources {
            excludes += listOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/NOTICE",
                "**/libc++_shared.so",   // Use Android's built-in libc++
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ── ONNX Runtime for PaddleOCR ─────────────────────────────────────────────
    // Version 1.16+ supports NNAPI execution provider
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.17.3")

    // ── ML Kit (OCR fallback) ──────────────────────────────────────────────────
    implementation("com.google.mlkit:text-recognition:16.0.1")

    // ── Kotlin coroutines (used by MLKitOcrHelper) ─────────────────────────────
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

    // ── Core Kotlin ────────────────────────────────────────────────────────────
    implementation("androidx.core:core-ktx:1.13.1")
}
