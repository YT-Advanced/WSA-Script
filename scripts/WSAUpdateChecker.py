import base64
import os
import html
import json
import re
import requests
import logging
import subprocess

from typing import Any, OrderedDict
from xml.dom import minidom

from requests import Session
from packaging import version

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

logging.captureWarnings(True)
env_file = os.getenv('GITHUB_ENV')

#Catagory ID
cat_id = '858014f3-3934-4abe-8078-4aa193e74ca8'

release_type = "WIF"

session = Session()
session.verify = False

git = (
    "git checkout -f update || git switch --discard-changes --orphan update"
)

def MagiskandGappsChecker(type):
    # Get current version
    currentver = requests.get(f"https://raw.githubusercontent.com/YT-Advanced/WSA-Script/update/" + type + ".appversion").text.replace('\n', '')
    # Get latest version
    latestver = ""
    msg = ""
    if (type == "magisk"):
        latestver = json.loads(requests.get(f"https://github.com/topjohnwu/magisk-files/raw/master/stable.json").content)['magisk']['version'].replace('\n', '')
        msg="Update Magisk Version from `v" + currentver + "` to `v" + latestver + "`"
    elif (type == "gapps"):
        latestver = json.loads(requests.get(f"https://api.github.com/repos/YT-Advanced/MindTheGappsBuilder/releases/latest").content)['name']
        msg="Update MindTheGapps Version from `v" + currentver + "` to `v" + latestver + "`"
    # Check if version is the same or not
    if currentver != latestver:
        print("New version found: " + latestver)
        subprocess.Popen(git, shell=True, stdout=None, stderr=None, executable='/bin/bash').wait()
        with open(env_file, "a") as wr:
            wr.write("SHOULD_BUILD=yes\nMSG=" + msg)
        file = open(type + '.appversion', 'w')
        file.write(latestver)
        file.close()
        return 1;

def WSAChecker(user, release_type):
    with open("../xml/GetCookie.xml", "r") as f:
        cookie_content = f.read().format(user)
        f.close()
    try:
        out = session.post(
            'https://fe3.delivery.mp.microsoft.com/ClientWebService/client.asmx',
            data=cookie_content,
            headers={'Content-Type': 'application/soap+xml; charset=utf-8'}
        )
    except:
        print("Network Error!")
        return 1
    doc = minidom.parseString(out.text)
    cookie = doc.getElementsByTagName('EncryptedData')[0].firstChild.nodeValue
    with open("../xml/WUIDRequest.xml", "r") as f:
        cat_id_content = f.read().format(user, cookie, cat_id, release_type)
        f.close()
    try:
        out = session.post(
            'https://fe3.delivery.mp.microsoft.com/ClientWebService/client.asmx',
            data=cat_id_content,
            headers={'Content-Type': 'application/soap+xml; charset=utf-8'}
        )
    except:
        print("Network Error!")
        return 1
    doc = minidom.parseString(html.unescape(out.text))
    filenames = {}
    for node in doc.getElementsByTagName('ExtendedUpdateInfo')[0].getElementsByTagName('Updates')[0].getElementsByTagName('Update'):
        node_xml = node.getElementsByTagName('Xml')[0]
        node_files = node_xml.getElementsByTagName('Files')
        if not node_files:
            continue
        else:
            for node_file in node_files[0].getElementsByTagName('File'):
                if node_file.hasAttribute('InstallerSpecificIdentifier') and node_file.hasAttribute('FileName'):
                    filenames[node.getElementsByTagName('ID')[0].firstChild.nodeValue] = (f"{node_file.attributes['InstallerSpecificIdentifier'].value}_{node_file.attributes['FileName'].value}",
                                                                                          node_xml.getElementsByTagName('ExtendedProperties')[0].attributes['PackageIdentityName'].value)
    identities = {}
    for node in doc.getElementsByTagName('NewUpdates')[0].getElementsByTagName('UpdateInfo'):
        node_xml = node.getElementsByTagName('Xml')[0]
        if not node_xml.getElementsByTagName('SecuredFragment'):
            continue
        else:
            id = node.getElementsByTagName('ID')[0].firstChild.nodeValue
            update_identity = node_xml.getElementsByTagName('UpdateIdentity')[0]
            if id in filenames:
                fileinfo = filenames[id]
                if fileinfo[0] not in identities:
                    identities[fileinfo[0]] = ([update_identity.attributes['UpdateID'].value,
                                            update_identity.attributes['RevisionNumber'].value], fileinfo[1])
    info_list = []
    for value in filenames.values():
        if value[0].find("_neutral_") != -1:
            info_list.append(value[0])
    info_list = sorted(
        info_list,
        key=lambda x: (
            int(x.split("_")[1].split(".")[0]),
            int(x.split("_")[1].split(".")[1]),
            int(x.split("_")[1].split(".")[2]),
            int(x.split("_")[1].split(".")[3])
        ),
        reverse=True
    )
    wsa_build_ver = 0
    for filename, value in identities.items():
        if re.match(f"MicrosoftCorporationII.WindowsSubsystemForAndroid_.*.msixbundle", filename):
            tmp_wsa_build_ver = re.search(r"\d{4}.\d{5}.\d{1,}.\d{1,}", filename).group()
            if (wsa_build_ver == 0):
                wsa_build_ver = tmp_wsa_build_ver
            elif version.parse(wsa_build_ver) < version.parse(tmp_wsa_build_ver):
                wsa_build_ver = tmp_wsa_build_ver

    currentver = requests.get(f"https://raw.githubusercontent.com/YT-Advanced/WSA-Script/update/" + release_type + ".appversion").text.replace('\n', '')
    if version.parse(currentver) < version.parse(wsa_build_ver):
        print("New version found: " + wsa_build_ver)
        subprocess.Popen(git, shell=True, stdout=None, stderr=None, executable='/bin/bash').wait()
        msg = 'Update WSA Version from `v' + currentver + '` to `v' + wsa_build_ver + '`'
        file = open(release_type + '.appversion', 'w')
        file.write(wsa_build_ver)
        file.close()
        with open(env_file, "a") as wr:
            wr.write("SHOULD_BUILD=yes\nRELEASE_TYPE=" + release_type + "\nMSG=" + msg)
        return 1;

# Get user_code (Thanks to @bubbles-wow because of his repository)
users = {""}
try:
    response = requests.get("https://api.github.com/repos/bubbles-wow/MS-Account-Token/contents/token.cfg")
    if response.status_code == 200:
        content = response.json()["content"]
        content = content.encode("utf-8")
        content = base64.b64decode(content)
        text = content.decode("utf-8")
        user_code = Prop(text).get("user_code")
        updatetime = Prop(text).get("update_time")
        print("Successfully get user token from server!")
        print(f"Last update time: {updatetime}\n")
    else:
        user_code = ""
        print(f"Failed to get user token from server! Error code: {response.status_code}\n")
except:
    user_code = ""

if user_code == "":
    users = {""}
else:
    users = {"", user_code}
for user in users:
    if user == "":
        print("Checking WSA Stable version...\n")
        if WSAChecker(user, "retail") == 1:
            break
        print("Checking Magisk version...\n")
        if MagiskandGappsChecker("magisk") == 1:
            break
        print("Checking MindTheGapps version...\n")
        if MagiskandGappsChecker("gapps") == 1:
            break
    else:
        print("Checking WSA Insider version...\n")
        if WSAChecker(user, "WIF") == 1:
            break
