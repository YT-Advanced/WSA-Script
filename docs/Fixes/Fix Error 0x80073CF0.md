## Issue: </br> Error 0x80073CF0 when "Run.bat" is executed to install Windows Subystem for Android (WSA)
### Preface:
##### This issue can arise due to many factors such as corruption of files when downloading the .zip files or extracting from the .zip files. This can be also caused if the folder name is too long (This is the case as MagiskOnWSA tends to generate a long string for the .zip file and the folder within the archive.)

![imageCF0](https://user-images.githubusercontent.com/68516357/232593575-20db5482-a0e3-472d-875c-37d248ccfca2.png)


---
## Solution

**1. Ensure the partition/drive you are installing from is NTFS**

**2. Redownload WSA Build .zip file from the [Releases page](https://github.com/YT-Advanced/WSA-Script/releases/latest) (sometime the files can be corrupted during download and extraction)**

**3. Rename the .zip folder to a shorter name, which can be anything to your choosing </br> (WSA_2xxx.xxxxx.xx.x_x64_Release-Nightly-with-magisk-xxxxxxx-MindTheGapps-13.0-as-Pixel-5-RemovedAmazon ----> WSAArchive2XXX)**

**4. Extract the .zip using WinRAR or a proper archive tool and not the built in Windows .zip extractor** 

**5. Rename the extracted folder to a shorter name, which can be anything to your choosing </br> (WSA_2xxx.xxxxx.xx.x_x64_Release-Nightly-with-magisk-xxxxxxx-MindTheGapps-13.0-as-Pixel-5-RemovedAmazon ----> WSAExtracted2XXX)**

**6. Ensure that 'Run.bat' is run as Administrator**

**Hope this works for you!**
