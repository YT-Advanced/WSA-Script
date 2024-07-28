import base64
import html
import logging
import os
import re
import subprocess

from abc import ABC, abstractmethod
from pathlib import Path
from typing import Final, Literal

import requests
import xmltodict

from requests import Session


logging.captureWarnings(True)

session = Session()
session.verify = False


ENV_FILE_PATH: Final[Path] = Path(str(os.getenv("GITHUB_ENV")))

GIT_COMMAND: Final[str] = (
    "git checkout -f update || git switch --discard-changes --orphan update"
)

CATEGORY_ID: Final[str] = "858014f3-3934-4abe-8078-4aa193e74ca8"


# Thanks to bubbles-wow's repository
def get_usercode() -> str:
    response = requests.get(
        "https://api.github.com/repos/bubbles-wow/WSAUpdateChecker/contents/token.conf"
    )

    content = response.json()["content"]
    content = content.encode()
    content = base64.b64decode(content)
    content = content.decode()

    user_code: str = re.search("(?<=user_code=).*", content).group()  # type: ignore

    return user_code


class UpdateChecker(ABC):
    def __init__(self, app_name: str):
        self.app_name = app_name

        self.current_version: str
        self.latest_version: str

    @property
    def update_msg(self) -> str:
        return f"Update {self.app_name} Version from 'v{self.current_version}' to 'v{self.latest_version}'"

    @abstractmethod
    def get_current_version(self) -> str: ...

    @abstractmethod
    def get_latest_version(self) -> str: ...

    def get_update(self) -> None:
        if self.is_up_to_date():
            return

        self.update()
        self.write_to_github_environment()
        self.overwrite_current_version()

    def is_up_to_date(self) -> bool:
        return self.current_version == self.latest_version

    def update(self) -> None:
        print(f"New version found: {self.latest_version}")

        subprocess.Popen(
            GIT_COMMAND,
            shell=True,
            stdout=None,
            stderr=None,
            executable="/bin/bash",
        ).wait()

    @abstractmethod
    def write_to_github_environment(self) -> None: ...

    @abstractmethod
    def overwrite_current_version(self) -> None: ...


class UtilUpdateChecker(UpdateChecker):
    def __init__(
        self,
        app_id: str,
        app_name: str,
        latest_version_url: str,
        json_keys: tuple[str, ...],
    ) -> None:

        super().__init__(app_name)

        self.app_id = app_id
        self.latest_version_url = latest_version_url
        self.json_keys = json_keys

        self.current_version = self.get_current_version()
        self.latest_version = self.get_latest_version()

    @property
    def current_version_url(self) -> str:
        return f"https://raw.githubusercontent.com/YT-Advanced/WSA-Script/update/{self.app_id}.appversion"

    @property
    def current_version_file_path(self) -> Path:
        return Path(f"../{self.app_id}.appversion")

    def get_current_version(self) -> str:
        response = requests.get(self.current_version_url)

        return response.text

    def get_latest_version(self) -> str:
        response = requests.get(self.latest_version_url)
        content = response.json()

        for key in self.json_keys:
            content = content.get(key)

        return content

    def write_to_github_environment(self) -> None:
        with open(ENV_FILE_PATH, "a") as env_file:
            env_file.write(
                f"""
                SHOULD_BUILD=yes
                MSG={self.update_msg}
                """.strip()
            )

    def overwrite_current_version(self) -> None:
        with open(self.current_version_file_path, "w") as current_version_file:
            current_version_file.write(self.latest_version)


class WSAUpdateChecker(UpdateChecker):
    def __init__(self, app_name: str, update_channel: Literal["retail", "WIF"]) -> None:
        super().__init__(app_name)

        self.update_channel = update_channel

        self.current_version = self.get_current_version()
        self.latest_version = self.get_latest_version()

    @property
    def current_version_url(self) -> str:
        return f"https://raw.githubusercontent.com/YT-Advanced/WSA-Script/update/{self.update_channel}.appversion"

    @property
    def current_version_file_path(self) -> Path:
        return Path(f"../{self.update_channel}.appversion")

    @property
    def product_id(self) -> str: # type: ignore
        if self.update_channel == "retail":
            return "301870114"
        elif self.update_channel == "WIF":
            return "301870124"

    def get_current_version(self) -> str:
        response = requests.get(self.current_version_url)

        return response.text

    def get_latest_version(self) -> str: # type: ignore
        # user_code: str = get_usercode()
        # retail: 301870105
        # WIF:    301870107

        user_code: str = ""
        # retail: 301870114
        # WIF:    301870124

        with open("../xml/GetCookie.xml", "r") as cookie_file:
            cookie = cookie_file.read()
            cookie = cookie.format(user_code)

        response = session.post(
            "https://fe3.delivery.mp.microsoft.com/ClientWebService/client.asmx",
            headers={"Content-Type": "application/soap+xml; charset=utf-8"},
            data=cookie,
        )

        content = xmltodict.parse(response.text)
        token = content["s:Envelope"]["s:Body"]["GetCookieResponse"] \
                       ["GetCookieResult"]["EncryptedData"].strip("'")

        with open("../xml/WUIDRequest.xml", "r") as cookie_file:
            cookie = cookie_file.read()
            cookie = cookie.format(user_code, token, CATEGORY_ID, "WIF")

        response = session.post(
            "https://fe3.delivery.mp.microsoft.com/ClientWebService/client.asmx",
            headers={"Content-Type": "application/soap+xml; charset=utf-8"},
            data=cookie,
        )

        content = xmltodict.parse(html.unescape(response.text))
        product_list = content["s:Envelope"]["s:Body"]["SyncUpdatesResponse"] \
                              ["SyncUpdatesResult"]["ExtendedUpdateInfo"]["Updates"]["Update"] 

        for product in product_list:
            if product["ID"] == self.product_id:
                package = product["Xml"]["Files"]["File"][0] \
                                ["@InstallerSpecificIdentifier"]
                version = re.search("(?<=Android_).*(?=_neutral)", package).group()  # type: ignore

                return version

    def write_to_github_environment(self) -> None:
        with open(ENV_FILE_PATH, "a") as env_file:
            env_file.write(
                f"""
                SHOULD_BUILD=yes
                RELEASE_TYPE={self.update_channel}
                MSG={self.update_msg}
                """.strip()
            )

    def overwrite_current_version(self) -> None:
        with open(self.current_version_file_path, "w") as current_version_file:
            current_version_file.write(self.latest_version)


magisk_update_checker = UtilUpdateChecker(
    app_id="magisk",
    app_name="Magisk",
    latest_version_url="https://github.com/topjohnwu/magisk-files/raw/master/stable.json",
    json_keys=("magisk", "version"),
)

gapps_update_checker = UtilUpdateChecker(
    app_id="gapps",
    app_name="MindTheGapps",
    latest_version_url="https://api.github.com/repos/YT-Advanced/MindTheGappsBuilder/releases/latest",
    json_keys=("name",),
)

kernelsu_update_checker = UtilUpdateChecker(
    app_id="kernelsu",
    app_name="KernelSU",
    latest_version_url="https://api.github.com/repos/tiann/KernelSU/releases/latest",
    json_keys=("name",),
)

wsa_retail_update_checker = WSAUpdateChecker(
    app_name="WSA",
    update_channel="retail",
)

wsa_wif_update_checker = WSAUpdateChecker(
    app_name="WSA Insider Preview",
    update_channel="WIF",
)


def main() -> None:

    print("Checking WSA Stable version...", end="\n")
    if not wsa_retail_update_checker.is_up_to_date():
        wsa_retail_update_checker.get_update()
        return

    print("Checking WSA Insider version...", end="\n")
    if not wsa_wif_update_checker.is_up_to_date():
        wsa_retail_update_checker.get_update()
        return

    print("Checking Magisk version...", end="\n")
    if not magisk_update_checker.is_up_to_date():
        magisk_update_checker.get_update()
        return

    print("Checking MindTheGapps version...", end="\n")
    if not gapps_update_checker.is_up_to_date():
        gapps_update_checker.get_update()
        return

    print("Checking KernelSU version...", end="\n")
    if not kernelsu_update_checker.is_up_to_date():
        kernelsu_update_checker.get_update()
        return


if __name__ == "__main__":
    main()
