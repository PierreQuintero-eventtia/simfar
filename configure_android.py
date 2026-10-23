import os
import glob

# 1. Detectar el NDK que YA viene preinstalado en el servidor de GitHub
installed_ndk = None
ndk_base_dirs = [
    "/usr/local/lib/android/sdk/ndk",
    os.path.expanduser("~/Android/Sdk/ndk"),
    os.environ.get("ANDROID_HOME", "") + "/ndk",
    os.environ.get("ANDROID_SDK_ROOT", "") + "/ndk"
]

for base in ndk_base_dirs:
    if os.path.exists(base):
        subdirs = [d for d in os.listdir(base) if os.path.isdir(os.path.join(base, d))]
        if subdirs:
            installed_ndk = sorted(subdirs)[-1]
            print(f"✔ NDK preinstalado encontrado en el servidor: {installed_ndk}")
            break

if not installed_ndk:
    installed_ndk = "26.3.11579264"

# 2. Fijar el NDK local y minSdkVersion 21 en build.gradle.kts / build.gradle
for gf in glob.glob("android/app/build.gradle*"):
    with open(gf, "r", encoding="utf-8") as f:
        content = f.read()
    
    # Usar el NDK local para no descargar 1.3GB de internet
    content = content.replace("flutter.ndkVersion", f'"{installed_ndk}"')
    content = content.replace("flutter.minSdkVersion", "21")
    content = content.replace("minSdkVersion flutter.minSdkVersion", "minSdkVersion 21")
    
    with open(gf, "w", encoding="utf-8") as f:
        f.write(content)

print(f"✔ ndkVersion fijado a '{installed_ndk}' (0 MB de descarga, instantáneo)")
print("✔ MinSdkVersion configurado a 21")

# 3. Eliminar llamadas a jcenter() en la caché de librerías
pub_cache = os.path.expanduser("~/.pub-cache")
for fpath in glob.glob(f"{pub_cache}/**/build.gradle*", recursive=True):
    try:
        with open(fpath, "r", encoding="utf-8") as f:
            c = f.read()
        if "jcenter()" in c:
            c = c.replace("jcenter()", "mavenCentral()")
            with open(fpath, "w", encoding="utf-8") as f:
                f.write(c)
    except Exception:
        pass

# 4. Asegurar permisos de micrófono en AndroidManifest.xml
manifest_file = "android/app/src/main/AndroidManifest.xml"
if os.path.exists(manifest_file):
    with open(manifest_file, "r", encoding="utf-8") as f:
        manifest = f.read()
    
    if "RECORD_AUDIO" not in manifest:
        perms = """
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
    <uses-permission android:name="android.permission.BLUETOOTH"/>
        """
        queries = """
    <queries>
        <intent>
            <action android:name="android.speech.RecognitionService" />
        </intent>
    </queries>
        """
        manifest = manifest.replace("<application", perms + "\n    <application")
        manifest = manifest.replace("</application>", "</application>\n" + queries)
        with open(manifest_file, "w", encoding="utf-8") as f:
            f.write(manifest)
        print("✔ Permisos de audio inyectados")
