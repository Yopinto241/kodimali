plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val admobAndroidAppId =
    System.getenv("ADMOB_ANDROID_APP_ID")
        ?.takeIf { it.isNotBlank() }
        ?: "ca-app-pub-3940256099942544~3347511713"

val releaseValues = listOf("KODIMALI_KEYSTORE_PATH", "KODIMALI_KEY_ALIAS", "KODIMALI_STORE_PASSWORD", "KODIMALI_KEY_PASSWORD").associateWith { System.getenv(it)?.takeIf(String::isNotBlank) }
val releaseConfigured = releaseValues.values.all { it != null }
if (gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) } && !releaseConfigured) {
    throw GradleException("Production release signing is required. Configure the KODIMALI signing environment or use the protected mobile-release workflow.")
}

android {
    namespace = "co.kodimali.customer_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "co.kodimali.customer_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["ADMOB_ANDROID_APP_ID"] = admobAndroidAppId
    }

    signingConfigs {
        if (releaseConfigured) {
            create("production") {
                storeFile = file(releaseValues.getValue("KODIMALI_KEYSTORE_PATH")!!)
                keyAlias = releaseValues.getValue("KODIMALI_KEY_ALIAS")
                storePassword = releaseValues.getValue("KODIMALI_STORE_PASSWORD")
                keyPassword = releaseValues.getValue("KODIMALI_KEY_PASSWORD")
            }
        }
    }
    buildTypes {
        release {
            if (releaseConfigured) signingConfig = signingConfigs.getByName("production")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
