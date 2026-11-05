import java.io.File
import java.util.Properties

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

// Local signing credentials stay outside Git; CI environment values take precedence.
val signingEnvFile = System.getenv("KODIMALI_SIGNING_ENV_FILE")
    ?.takeIf(String::isNotBlank)?.let { file(it) }
    ?: File(System.getProperty("user.home"), "Kodimali-Signing/android-production/.envy")
val localSigningValues = Properties().apply {
    if (signingEnvFile.isFile) signingEnvFile.inputStream().use { load(it) }
}
val signingFields = linkedMapOf(
    "KODIMALI_KEYSTORE_PATH" to "CUSTOMER_KEYSTORE_FILE",
    "KODIMALI_KEY_ALIAS" to "CUSTOMER_KEY_ALIAS",
    "KODIMALI_STORE_PASSWORD" to "CUSTOMER_STORE_PASSWORD",
    "KODIMALI_KEY_PASSWORD" to "CUSTOMER_KEY_PASSWORD",
)
// A partial environment must not silently mix identities with local credentials.
val hasSigningEnvironment = signingFields.keys.any { !System.getenv(it).isNullOrBlank() }
val releaseValues = signingFields.mapValues { (envName, localName) ->
    if (hasSigningEnvironment) System.getenv(envName)?.takeIf(String::isNotBlank)
    else localSigningValues.getProperty(localName)?.takeIf(String::isNotBlank)?.let { value ->
        if (envName == "KODIMALI_KEYSTORE_PATH") {
            val keyFile = File(value)
            (if (keyFile.isAbsolute) keyFile else File(signingEnvFile.parentFile, value)).absolutePath
        } else value
    }
}
val releaseConfigured = releaseValues.values.all { it != null }
if (gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) } && !releaseConfigured) {
    throw GradleException("Production release signing is required. Restore .envy and keystores to ~/Kodimali-Signing/android-production, set KODIMALI_SIGNING_ENV_FILE, or configure all four KODIMALI signing environment variables.")
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
