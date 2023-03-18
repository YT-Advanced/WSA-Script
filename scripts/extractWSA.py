#!/usr/bin/python3
#
# This file is part of MagiskOnWSALocal.
#
# MagiskOnWSALocal is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# MagiskOnWSALocal is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with MagiskOnWSALocal.  If not, see <https://www.gnu.org/licenses/>.
#
# Copyright (C) 2023 LSPosed Contributors
#

import sys

import warnings
import zipfile
from pathlib import Path
import re
import shutil

warnings.filterwarnings("ignore")

arch = sys.argv[1]

zip_name = ""
wsa_zip_path= Path(sys.argv[2]).resolve()
rootdir = Path(sys.argv[3]).resolve()
env_file = Path(sys.argv[4]).resolve()

workdir = rootdir / "wsa"
archdir = Path(workdir / arch)

if not Path(rootdir).is_dir():
    rootdir.mkdir()

if Path(workdir).is_dir():
    shutil.rmtree(workdir)
else:
    workdir.unlink(missing_ok=True)

if not Path(workdir).is_dir():
    workdir.mkdir()

if not Path(archdir).is_dir():
    archdir.mkdir()
with zipfile.ZipFile(wsa_zip_path) as zip:
    for f in zip.filelist:
        if arch in f.filename.lower():
            zip_name = f.filename
            output_name = zip_name[11:-5]
            if not Path(workdir / zip_name).is_file():
                zip_path = workdir / zip_name
                print(f"unzipping to {workdir}", flush=True)
                zip.extract(f, workdir)
                ver_no = zip_name.split("_")
                long_ver = ver_no[1]
                ver = long_ver.split(".")
                main_ver = ver[0]
                rel = ver_no[3].split(".")
                rel_long = str(rel[0])
                with open(env_file, 'a') as environ_file:
                    environ_file.write(f'WSA_VER={long_ver}\n')
                    environ_file.write(f'WSA_MAIN_VER={main_ver}\n')
                    environ_file.write(f'WSA_REL={rel_long}\n')
        if 'language' in f.filename.lower() or 'scale' in f.filename.lower():
            name = f.filename.split("_")[2].split(".")[0]
            zip.extract(f, workdir)
            with zipfile.ZipFile(workdir / f.filename) as l:
                for g in l.filelist:
                    if g.filename == 'resources.pri':
                        g.filename = f'resources.{name}.pri'
                        l.extract(g, workdir / archdir / 'pri')
                    elif g.filename == 'AppxManifest.xml':
                        g.filename = f'resources.{name}.xml'
                        l.extract(g, workdir / archdir / 'xml')
                    elif re.search(u'Images/.+\.png', g.filename):
                        l.extract(g, archdir)
with zipfile.ZipFile(zip_path) as zip:
    print(f"unzipping from {zip_path}", flush=True)
    zip.extractall(archdir)