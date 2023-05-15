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

import requests
import json
import re
from pathlib import Path

arch = sys.argv[1]
arg4 = sys.argv[2]
download_dir = Path.cwd().parent / "download" if arg4 == "" else Path(arg4)
tempScript = sys.argv[3]
android_api = sys.argv[4]
file_name = sys.argv[5]
print(f"Generating MindTheGapps download link: arch={arch}", flush=True)
abi_map = {"x64": "x86_64", "arm64": "arm64"}
android_api_map = {"33": "13.0"}
release = android_api_map[android_api]
res = requests.get(
    f'https://sourceforge.net/projects/wsa-mtg/rss?path=/{abi_map[arch]}&limit=100')
matched = re.search(f'https://.*{release}.*{abi_map[arch]}.*\.zip/download', res.text)
if matched:
    link = matched.group().replace(
        '.zip/download', '.zip').replace('sourceforge.net/projects/wsa-mtg/files', 'downloads.sourceforge.net/project/wsa-mtg')
else:
    print(f"Failed to fetch from SourceForge RSS, fallbacking to Github API...", flush=True)
    res = requests.get(f"https://api.github.com/repos/Howard20181/MindTheGappsBuilder/releases/latest")
    json_data = json.loads(res.content)
    headers = res.headers
    x_ratelimit_remaining = headers["x-ratelimit-remaining"]
    if res.status_code == 200:
        assets = json_data["assets"]
        for asset in assets:
            if re.match(f'.*{release}.*{abi_map[arch]}.*\.zip$', asset["name"]) and asset["content_type"] == "application/zip":
                link = asset["browser_download_url"]
                break
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
