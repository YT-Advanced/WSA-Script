## Issue: </br> Error stating that "Path is too long" when extracting files from .zip archive, needed to install Windows Subystem for Android (WSA)
### Preface:
##### This issue is caused if the folder name is too long. This is the typically the case as MagiskOnWSALocal script tends to generate a long string for the .zip file and the folder within the archive.

<img src="https://user-images.githubusercontent.com/68516357/219853616-154615b8-125c-4b68-b2f7-43fc2f7b1f74.png" style="width: 600px;"/>  

---
## Solution

The solution is simple, all you have to do is:

**1. Rename the .zip folder to a shorter name, which can be anything to your choosing </br> (WSA_2xxx.xxxxx.xx.x_x64_Release-Nightly-with-magisk-xxxxxxx-MindTheGapps-13.0-as-Pixel-5-RemovedAmazon ----> WSAArchive2XXX)**

**2. Rename the extracted folder to a shorter name, which can be anything to your choosing </br> (WSA_2xxx.xxxxx.xx.x_x64_Release-Nightly-with-magisk-xxxxxxx-MindTheGapps-13.0-as-Pixel-5-RemovedAmazon ----> WSAExtracted2XXX)**
