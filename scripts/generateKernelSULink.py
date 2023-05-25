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

from datetime import datetime
import sys
import os
from typing import Any, OrderedDict

import requests
import json
import re
from pathlib import Path


class Prop(OrderedDict):
    def __init__(self, props: str = ...) -> None:
        super().__init__()
        for i, line in enumerate(props.splitlines(False)):
            if '=' in line:
                k, v = line.split('=', 1)
                self[k] = v
            else:
                self[f".{i}"] = line

    def __setattr__(self, __name: str, __value: Any) -> None:
        self[__name] = __value

    def __repr__(self):
        return '\n'.join(f'{item}={self[item]}' for item in self)


arch = sys.argv[1]
arg2 = sys.argv[2]
download_dir = Path.cwd().parent / "download" if arg2 == "" else Path(arg2)
tempScript = sys.argv[3]
kernelVersion = sys.argv[4]
file_name = sys.argv[5]
abi_map = {"x64": "x86_64", "arm64": "arm64"}
print(f"Generating KernelSU download link: arch={abi_map[arch]}, kernel version={kernelVersion}", flush=True)
res = requests.get(f"https://api.github.com/repos/tiann/KernelSU/releases/latest")
json_data = json.loads(res.content)
headers = res.headers
x_ratelimit_remaining = headers["x-ratelimit-remaining"]
if res.status_code == 200:
    link = ""
    apk = ""
    assets = json_data["assets"]
    release_name = json_data["tag_name"]
    for asset in assets:
        if re.match(f'kernel-WSA-{abi_map[arch]}-{kernelVersion}.*\.zip$', asset["name"]) and asset["content_type"] == "application/zip":
            link = asset["browser_download_url"]
        if re.match(f'KernelSU_{release_name}_.*-release.*\.apk$', asset["name"]) and asset["content_type"] == "application/vnd.android.package-archive":
            apk = asset["browser_download_url"]
            break
    if link == "":
        print(f"Error: No KernelSU release found for arch={abi_map[arch]}, kernel version={kernelVersion}", flush=True)
        exit(1)
    elif apk == "":
        print(f"Error: No KernelSU Manager release found", flush=True)
        exit(1)
    with open(os.environ['WSA_WORK_ENV'], 'r') as environ_file:
        env = Prop(environ_file.read())
        env.KERNELSU_VER = release_name
    with open(os.environ['WSA_WORK_ENV'], 'w') as environ_file:
        environ_file.write(str(env))
elif res.status_code == 403 and x_ratelimit_remaining == '0':
    message = json_data["message"]
    print(f"Github API Error: {message}", flush=True)
    ratelimit_reset = headers["x-ratelimit-reset"]
    ratelimit_reset = datetime.fromtimestamp(int(ratelimit_reset))
    print(f"The current rate limit window resets in {ratelimit_reset}", flush=True)
    exit(1)

print(f"download link: {link}", flush=True)

with open(download_dir/tempScript, 'a') as f:
    f.writelines(f'{link}\n')
    f.writelines(f'  dir={download_dir}\n')
    f.writelines(f'  out={file_name}\n')
    f.writelines(f'{apk}\n')
    f.writelines(f'  dir={download_dir}\n')
    f.writelines(f'  out=KernelSU.apk\n')
