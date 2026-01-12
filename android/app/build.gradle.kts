plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.nvapp_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Kotlin DSL'de 'is' eki ve '=' kullanımı zorunludur
        isCoreLibraryDesugaringEnabled = true 
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        // Hata veren jvmTarget kısmını bu şekilde güncelledik
        jvmTarget = "1.8"
    }

    defaultConfig {
        applicationId = "com.example.nvapp_mobile"
        minSdk = flutter.minSdkVersion 
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Kotlin DSL'de parantez ve tırnak kullanımı
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")
}
