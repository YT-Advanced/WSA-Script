# WSA Sideloader Usage Guide
#### With WSA Sideloader, you can install any APK file onto WSA. 
#### This guide will show you how to use it.

</br>

</br>

## How to Download and Install WSA-Sideloader

#### You can download WSA Sideloader in 3 different ways:
Operating System|Downloads
|---------|---------|
|<img src="https://upload.wikimedia.org/wikipedia/commons/e/e6/Windows_11_logo.svg" style="width: 150px;"/></br><img src="https://upload.wikimedia.org/wikipedia/commons/0/05/Windows_10_Logo.svg" style="width: 150px;"/> |[<img src="https://user-images.githubusercontent.com/49786146/159123331-729ae9f2-4cf9-439b-8515-16a4ef991089.png" style="width: 200px;"/>](https://winget.run/pkg/infinitepower18/WSASideloader)|
|<img src="https://upload.wikimedia.org/wikipedia/commons/e/e6/Windows_11_logo.svg" style="width: 150px;"/></br><img src="https://upload.wikimedia.org/wikipedia/commons/0/05/Windows_10_Logo.svg" style="width: 150px;"/> |[<img src="https://user-images.githubusercontent.com/68516357/226141505-c93328f9-d6ae-4838-b080-85b073bfa1e0.png" style="width: 200px;"/>](https://github.com/infinitepower18/WSA-Sideloader/releases/latest)|
|<img src="https://upload.wikimedia.org/wikipedia/commons/e/e6/Windows_11_logo.svg" style="width: 150px;"/>|[<img src="https://get.microsoft.com/images/en-GB%20dark.svg" style="width: 200px;"/>](https://www.microsoft.com/store/apps/9NMFSJB25QJR)|

## Setup

***Step 1.  Once installed, you should see this screen:***

![image](https://user-images.githubusercontent.com/44692189/226059063-9148821a-8661-4f38-9089-bfd6bb72b135.png)

>**Note** :
> If you get a message that says WSA is not installed, check that you have downloaded and installed WSA correctly as per the WSABuilds instructions.

</br>

***Step 2. Next, open WSA Settings from the start menu or by typing wsa-settings:// in your browser's address bar, select Developer and enable Developer mode. Most likely the IP address shown is 127.0.0.1:58526 which is already entered by default in WSA Sideloader, however if the IP address is different for you make sure to change it in the sideloader.***

![image](https://user-images.githubusercontent.com/44692189/226059697-9d54c122-8674-46f4-871a-4937805498ef.png)

</br>

***Step 3. Now, you can click the Browse button to select your APK file. You can also double click a file in File Explorer to automatically open WSA Sideloader with the APK file already selected.***

<img width="1157" alt="image" src="https://user-images.githubusercontent.com/44692189/226060206-ffc9a9af-42b2-4281-859d-bb83c3e8b019.png">

</br>

***Step 4. The first time you install an APK, it will ask to allow ADB debugging. Allow it and attempt the installation again. Check the always allow box if you don't want to manually accept the permission every time you install an app.***

<img width="485" alt="image" src="https://user-images.githubusercontent.com/44692189/226060674-233a60b5-56d7-4dcf-a626-295d21a4c464.png">

</br>

***Step 5. It should take a few seconds to install the APK. Once it says `The application has been successfully installed`, you can click Open app.***

>**Note** : 
> If WSA is off, WSA Sideloader will start it for you. After 30 seconds, the installation will automatically continue.

<img width="314" alt="image" src="https://user-images.githubusercontent.com/44692189/226061387-f0126c32-3a2f-49c4-8ecf-83ad5809ab38.png">

</br>

***You can find all your installed WSA apps on the start menu, as well as via the "Installed apps" button in WSA Sideloader:***

<img width="962" alt="image" src="https://user-images.githubusercontent.com/44692189/226061500-c210ded3-5342-483d-b4b8-c4b683b138a7.png">

## Updating WSA Sideloader
From time to time, there may be updates that improve the reliability of the app, as well as ensuring it works properly with future releases of WSA. 

Therefore, it's highly recommended you keep it up to date. 

- If you installed WSA Sideloader using MS Store, you can update the app via the store. 
- If you installed through other methods, the sideloader will notify you of an update the next time you launch it.

## Troubleshooting
If you get an error like the one below, check that you have allowed the ADB authorization and enabled Developer Mode.

<img width="446" alt="image" src="https://user-images.githubusercontent.com/44692189/226061768-61743f6c-2ed3-401a-a561-8754c297ad74.png">
