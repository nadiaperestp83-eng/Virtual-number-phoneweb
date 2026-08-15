// VNumero (Fase  — push de chamada): classpath do plugin do Google
// Services. Precisa vir ANTES de tudo, é o que permite o
// `apply(plugin = "com.google.gms.google-services")` no
// android/app/build.gradle.kts funcionar.
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.google.gms:google-services:4.4.2")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Fix: Injetar namespace no Isar (Compatibilidade Kotlin DSL para AGP 8+)
subprojects {
    afterEvaluate {
        val proj = this
        val androidExt = proj.extensions.findByName("android")
        if (androidExt != null) {
            try {
                val clazz = androidExt::class.java
                val getNamespaceMethod = clazz.getMethod("getNamespace")
                val namespace = getNamespaceMethod.invoke(androidExt)
                if (namespace == null) {
                    val setNamespaceMethod = clazz.getMethod("setNamespace", String::class.java)
                    setNamespaceMethod.invoke(androidExt, proj.group.toString())
                }
            } catch (e: Exception) {
                // Ignora silenciosamente se o plugin não suportar namespace
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
