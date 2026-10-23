import os
import glob

# 1. Eliminar cualquier jcenter() residual en la caché de dependencias
pub_cache = os.path.expanduser("~/.pub-cache")
for fpath in glob.glob(f"{pub_cache}/**/build.gradle*", recursive=True):
    try:
        with open(fpath, "r", encoding="utf-8") as f:
            c = f.read()
        if "jcenter()" in c:
            c = c.replace("jcenter()", "mavenCentral()")
            with open(fpath, "w", encoding="utf-8") as f:
                f.write(c)
            print(f"✔ jcenter() neutralizado en: {fpath}")
    except Exception:
        pass

# 2. Configurar minSdkVersion a 21
for gf in glob.glob("android/app/build.gradle*"):
    with open(gf, "r", encoding="utf-8") as f:
        content = f.read()
    content = content.replace("flutter.minSdkVersion", "21")
    content = content.replace("minSdkVersion flutter.minSdkVersion", "minSdkVersion 21")
    with open(gf, "w", encoding="utf-8") as f:
        f.write(content)
print("✔ MinSdkVersion configurado a 21")

# 3. Agregar permisos al AndroidManifest.xml
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
        print("✔ Permisos inyectados correctamente")
