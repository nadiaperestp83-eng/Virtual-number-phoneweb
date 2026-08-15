plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "cloud.manaos.mnscloud.phoneweb"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {

        // com.nvirtual.labs), como combinado. `namespace` acima NÃO foi
        // tocado — não precisa bater com o applicationId, e mexer nele
        // arriscaria quebrar referências de pacote no código nativo
        // (MainActivity etc.).
        applicationId = "com.nvirtual.labs"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Release signing is configured by the distribution pipeline.
            signingConfig = signingConfigs.getByName("debug")
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

// VNumero (Fase 3 — push de chamada): aplica o plugin do Google
// Services via a forma clássica `apply(plugin = ...)`, que funciona em
// cima do `classpath` declarado no `android/build.gradle.kts` sem
// precisar mexer no `settings.gradle.kts` (que não vi ainda).
apply(plugin = "com.google.gms.google-services")
