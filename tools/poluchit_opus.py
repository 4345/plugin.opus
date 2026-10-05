"""Исходники Opus 1.6.1 для сборки плагина: официальный релиз Xiph.Org.

В репозитории Opus не хранится — сборки всех платформ ждут его в opus-1.6.1/ в корне.
Скрипт скачивает архив релиза, сверяет SHA-256 и распаковывает его туда.

Использование (из корня репозитория):
    python tools/poluchit_opus.py            скачать и распаковать (если ещё нет)
    python tools/poluchit_opus.py --zanovo   заменить уже распакованный

Откуда: https://downloads.xiph.org/releases/opus/opus-1.6.1.tar.gz — релиз проекта
https://opus-codec.org (репозиторий https://github.com/xiph/opus, тег v1.6.1).
Контрольная сумма — из https://downloads.xiph.org/releases/opus/SHA256SUMS.txt.

Сборкам iOS и macOS нужен ещё config.h (они компилируют Opus с -DHAVE_CONFIG_H): он
лежит в opus_config/ и подключается путём поиска заголовков, копировать его не нужно.
"""

import argparse
import hashlib
import io
import os
import shutil
import sys
import tarfile
import urllib.request

VERSIYA = "1.6.1"
URL = "https://downloads.xiph.org/releases/opus/opus-%s.tar.gz" % VERSIYA
SHA256 = "6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1"

KOREN = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KUDA = os.path.join(KOREN, "opus-%s" % VERSIYA)


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--zanovo", action="store_true", help="заменить уже распакованный opus-%s" % VERSIYA)
    a = p.parse_args()

    if os.path.exists(os.path.join(KUDA, "COPYING")) and not a.zanovo:
        print("opus-%s уже на месте: %s (--zanovo — скачать заново)" % (VERSIYA, KUDA))
        return

    print("скачиваю", URL)
    zapros = urllib.request.Request(URL, headers={"User-Agent": "plugin.opus-build"})
    with urllib.request.urlopen(zapros, timeout=300) as otvet:
        dannye = otvet.read()
    est = hashlib.sha256(dannye).hexdigest()
    if est != SHA256:
        sys.exit("SHA-256 не совпал: %s, ожидался %s — архив не распакован" % (est, SHA256))
    print("SHA-256 совпал:", est)

    if os.path.exists(KUDA):
        shutil.rmtree(KUDA)
    koren_arhiva = "opus-%s/" % VERSIYA
    with tarfile.open(fileobj=io.BytesIO(dannye), mode="r:gz") as tar:
        chleny = tar.getmembers()
        for c in chleny:
            # Только содержимое opus-<версия>/ и без выхода за его пределы.
            if not (c.name + "/").startswith(koren_arhiva) or ".." in c.name.split("/"):
                sys.exit("неожиданный путь в архиве: %s" % c.name)
            if not (c.isfile() or c.isdir()):
                sys.exit("в архиве не файл и не каталог: %s" % c.name)
        tar.extractall(KOREN, members=chleny)
    print("распакован в", KUDA)


if __name__ == "__main__":
    main()
