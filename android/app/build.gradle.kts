import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 正式签名：android/key.properties 存在时启用（CI 注入），否则回退 debug 签名
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.jianju.jianju"
    compileSdk = 36
    ndkVersion = "26.3.11579264"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.jianju.jianju"
        // 需求：Android 8.0 及以上
        minSdk = 26
        targetSdk = 35
        // versionCode 由 versionName 推导，每段占 3 位：2.1.0 → 2_001_000。
        // 版本号递增则 versionCode 必然递增，pubspec 无需写 build-number。
        versionCode = run {
            val seg = (flutter.versionName ?: "0.0.0").split(".")
            fun num(i: Int) = seg.getOrNull(i)?.filter { it.isDigit() }?.toIntOrNull() ?: 0
            num(0) * 1_000_000 + num(1) * 1_000 + num(2)
        }
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // 有 key.properties 用正式签名，否则 debug 签名（本地 flutter run --release 可用）
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
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
