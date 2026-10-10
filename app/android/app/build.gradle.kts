plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.loomsolutions.campaign_sms"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.loomsolutions.campaign_sms"
        // Spec asks for API 23; the Flutter 3.44 engine floor is API 24, so 24 it is.
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Android generates its debug keystore per machine, and every CI run is a new
    // machine — so each build was signed with a different key and Android refused
    // to install one over another ("package conflicts with an existing package").
    // Pinning one checked-in key means every build can upgrade the last.
    //
    // This is a throwaway sideload identity with the standard public debug
    // credentials. It is NOT a release credential and must never sign a Play
    // Store upload.
    signingConfigs {
        getByName("debug") {
            storeFile = file("../ci-signing.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        release {
            // Debug keys only. No Play-Store signing until explicitly approved (spec 13).
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    lint {
        // A default SMS handler legitimately declares WRITE_SMS; don't fail the build on it.
        disable += setOf("ProtectedPermissions")
        checkReleaseBuilds = false
        abortOnError = false
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
}

flutter {
    source = "../.."
}
