import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

if (file("google-services.json").isFile) {
    apply(plugin = "com.google.gms.google-services")
}

val allowUnsignedRelease = providers.gradleProperty("smartBillingUnsignedRelease").orNull == "true"
val uploadKeyProperties = Properties()
val uploadKeyPropertiesFile = rootProject.file("key.properties")
if (uploadKeyPropertiesFile.isFile && !allowUnsignedRelease) {
    uploadKeyPropertiesFile.inputStream().use { uploadKeyProperties.load(it) }
}
val uploadKeystore = uploadKeyProperties.getProperty("storeFile")
    ?.takeIf { it.isNotBlank() }?.let { rootProject.file(it) }
val releaseSigningReady = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .all { !uploadKeyProperties.getProperty(it).isNullOrBlank() } && uploadKeystore?.isFile == true
val useReleaseSigning = releaseSigningReady && !allowUnsignedRelease
val releaseSigningMessage = "Release signing is not configured. Complete android/key.properties with your upload keystore. " +
    "For unsigned compile checks only, pass -PsmartBillingUnsignedRelease=true."

if (gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) } &&
    !releaseSigningReady && !allowUnsignedRelease) {
    throw GradleException(releaseSigningMessage)
}

android {
    namespace = "com.smartbilling.smart_billing"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.smartbilling.smart_billing"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (useReleaseSigning) {
            create("release") {
                storeFile = uploadKeystore
                storePassword = uploadKeyProperties.getProperty("storePassword")
                keyAlias = uploadKeyProperties.getProperty("keyAlias")
                keyPassword = uploadKeyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (useReleaseSigning) signingConfigs.getByName("release") else null
        }
    }
}

// Also guard aggregate tasks such as `assemble`, which can include release work.
tasks.configureEach {
    if (name.endsWith("Release") && listOf("package", "assemble", "bundle", "sign").any { name.startsWith(it) }) {
        doFirst {
            if (!releaseSigningReady && !allowUnsignedRelease) {
                throw GradleException(releaseSigningMessage)
            }
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
