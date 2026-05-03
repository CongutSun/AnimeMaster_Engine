import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val releaseSigningKeys = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")

if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

val missingReleaseSigningKeys = if (keystorePropertiesFile.exists()) {
    releaseSigningKeys.filter { key -> keystoreProperties[key]?.toString().isNullOrBlank() }
} else {
    releaseSigningKeys
}
val releaseSigningConfigured =
    keystorePropertiesFile.exists() && missingReleaseSigningKeys.isEmpty()

gradle.taskGraph.whenReady {
    val needsReleaseSigning = allTasks.any { task ->
        task.name.contains("Release", ignoreCase = true) &&
            (task.name.startsWith("assemble", ignoreCase = true) ||
                task.name.startsWith("bundle", ignoreCase = true) ||
                task.name.startsWith("package", ignoreCase = true))
    }
    if (needsReleaseSigning && !releaseSigningConfigured) {
        val reason = if (!keystorePropertiesFile.exists()) {
            "example/android/key.properties does not exist"
        } else {
            "missing keys: ${missingReleaseSigningKeys.joinToString(", ")}"
        }
        throw GradleException(
            "Release signing is required for release builds; $reason. " +
                "Copy key.properties.example to key.properties and point it at the release keystore.",
        )
    }
}

android {
    namespace = "com.animemaster.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.animemaster.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    splits {
        abi {
            isEnable = true
            reset()
            include("arm64-v8a", "armeabi-v7a", "x86_64")
            isUniversalApk = true
        }
    }

    signingConfigs {
        if (releaseSigningConfigured) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}
