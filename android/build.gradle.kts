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

// Fix para injetar o namespace nos módulos legados (como o isar_flutter_libs) no AGP 8+
subprojects {
    afterEvaluate { project ->
        if (project.hasProperty("android")) {
            project.extensions.configure("android") {
                val namespaceProp = this.javaClass.getMethod("getNamespace").invoke(this)
                if (namespaceProp == null) {
                    val group = project.group.toString()
                    this.javaClass.getMethod("setNamespace", String::class.java).invoke(this, group)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
