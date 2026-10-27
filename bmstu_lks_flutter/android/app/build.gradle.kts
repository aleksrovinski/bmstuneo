import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Release signing comes from android/key.properties (see key.properties.example) or,
// on Codemagic, from its CM_KEYSTORE_* variables. Neither the file nor the keystore is committed.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}

fun signingValue(propertyKey: String, envKey: String): String? =
    keystoreProperties.getProperty(propertyKey) ?: System.getenv(envKey)

val releaseStoreFile = signingValue("storeFile", "CM_KEYSTORE_PATH")
val releaseStorePassword = signingValue("storePassword", "CM_KEYSTORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "CM_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "CM_KEY_PASSWORD")
val hasReleaseSigning = listOf(releaseStoreFile, releaseStorePassword, releaseKeyAlias, releaseKeyPassword)
    .all { !it.isNullOrBlank() }

android {
    namespace = "ru.bmstu.neo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications (java.time on older Android)
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "ru.bmstu.neo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                // Relative paths are resolved against the android/ directory
                storeFile = rootProject.file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                // Lets `flutter run --release` work locally; such a build can't be published
                logger.warn("BMSTU neo: android/key.properties not found, release build is signed with the DEBUG key")
                signingConfigs.getByName("debug")
            }
        }
    }
}

// An app bundle exists only to be uploaded to Google Play, so never produce a debug-signed one
gradle.taskGraph.whenReady {
    if (!hasReleaseSigning && allTasks.any { it.name == "bundleRelease" }) {
        throw GradleException(
            "Release signing is not configured: create android/key.properties " +
                "(see android/key.properties.example) or set CM_KEYSTORE_* variables",
        )
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
    // Silent pushes only; no Analytics or other Firebase products
    implementation(platform("com.google.firebase:firebase-bom:35.1.0"))
    implementation("com.google.firebase:firebase-messaging")
    // Same version as the workmanager plugin, whose BackgroundWorker runs the Dart sync
    implementation("androidx.work:work-runtime-ktx:2.11.2")
    // NotificationCompat.ProgressStyle and promoted ongoing (Live Update) notifications
    implementation("androidx.core:core-ktx:1.17.0")
}
