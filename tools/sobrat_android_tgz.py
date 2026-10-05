"""Архив Solar2D для Android (plugins_tgz/android.tgz) из собранного AAR плагина.

Использование (из корня репозитория):
    cd android && ./gradlew :plugin:assembleRelease && cd ..
    python tools/sobrat_android_tgz.py                    -> plugins_tgz/android.tgz
    python tools/sobrat_android_tgz.py --kuda <файл.tgz>  -> в другое место

Что в архиве:
    plugin.opus.jar        классы из classes.jar AAR и нативные библиотеки
                           jni/<abi>/libplugin_opus.so, переложенные в lib/<abi>/ —
                           так сборщик Solar2D кладёт их в приложение;
    metadata.lua           из plugin.opus/android/ (формат 'jar');
    resources/package.txt  из plugin.opus/android/resources/ (имя пакета Java).

Проверка: все четыре ABI на месте и в каждом jar есть plugin/opus/LuaLoader.class —
иначе архив не собирается.
"""

import argparse
import io
import os
import sys
import tarfile
import time
import zipfile

KOREN = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AAR = os.path.join(KOREN, "android", "plugin", "build", "outputs", "aar", "plugin-release.aar")
METADATA = os.path.join(KOREN, "plugin.opus", "android", "metadata.lua")
PACKAGE = os.path.join(KOREN, "plugin.opus", "android", "resources", "package.txt")
ABI = ["arm64-v8a", "armeabi-v7a", "x86", "x86_64"]


def sobrat_jar(aar_bytes):
    aar = zipfile.ZipFile(io.BytesIO(aar_bytes))
    imena = aar.namelist()
    so = sorted(n for n in imena if n.startswith("jni/") and n.endswith("/libplugin_opus.so"))
    est_abi = sorted(n.split("/")[1] for n in so)
    if est_abi != sorted(ABI):
        sys.exit("в AAR не все ABI: %s (нужны %s)" % (est_abi, ABI))
    if "classes.jar" not in imena:
        sys.exit("в AAR нет classes.jar")
    klassy = zipfile.ZipFile(io.BytesIO(aar.read("classes.jar")))
    if "plugin/opus/LuaLoader.class" not in klassy.namelist():
        sys.exit("в classes.jar нет plugin/opus/LuaLoader.class")

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as jar:
        for n in so:
            jar.writestr("lib/" + n[len("jni/"):], aar.read(n))
        for n in sorted(klassy.namelist()):
            if n.endswith(".class"):
                jar.writestr(n, klassy.read(n))
    return buf.getvalue()


def dobavit(tar, imya, dannye, mtime):
    info = tarfile.TarInfo(imya)
    info.size = len(dannye)
    info.mode = 0o644
    info.mtime = mtime
    tar.addfile(info, io.BytesIO(dannye))


def dobavit_katalog(tar, imya, mtime):
    info = tarfile.TarInfo(imya)
    info.type = tarfile.DIRTYPE
    info.mode = 0o755
    info.mtime = mtime
    tar.addfile(info)


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--kuda", default=os.path.join(KOREN, "plugins_tgz", "android.tgz"))
    a = p.parse_args()

    if not os.path.exists(AAR):
        sys.exit("нет %s — сначала cd android && ./gradlew :plugin:assembleRelease" % AAR)
    jar = sobrat_jar(open(AAR, "rb").read())
    mtime = int(time.time())
    with tarfile.open(a.kuda, "w:gz") as tar:
        dobavit_katalog(tar, "./", mtime)
        dobavit(tar, "./metadata.lua", open(METADATA, "rb").read(), mtime)
        dobavit(tar, "./plugin.opus.jar", jar, mtime)
        dobavit_katalog(tar, "./resources/", mtime)
        dobavit(tar, "./resources/package.txt", open(PACKAGE, "rb").read(), mtime)
    print("%s: %d байт (plugin.opus.jar %d байт, ABI %s)" % (a.kuda, os.path.getsize(a.kuda), len(jar), ", ".join(ABI)))


if __name__ == "__main__":
    main()
