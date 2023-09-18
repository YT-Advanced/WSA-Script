   <summary><h2>Issue:<h2><h3> &nbsp; Install.ps1 is not recognized/missing<h3></summary>

<img src="https://media.discordapp.net/attachments/1044322950725259274/1068243571544690719/9Qf3veK.png" />
<img src="https://user-images.githubusercontent.com/68516357/215262023-89e0e0fa-3dd7-4d6d-b93a-224169f61971.png" />
   
## Solution

If the popup windows disappear without asking administrative permission and Windows Subsystem For Android™ is not installed successfully, you should manually run Install.ps1 as administrator:

&nbsp;  
**1. Redownload the WSA Build and rename the extracted folder to a shorter name, which can be anything to your choosing** </br> 

- For example:

   - **Before:** WSA_2XXX.XXXXXXX_XXXX_Release-Nightly-with-magisk-XXXXXXX-XXXXXX-MindTheGapps-XX.X-RemovedAmazon 

   - **After:** WSAArchive2XXX

<br>

**2. Copy the path of the folder by right clicking on the folder and select "Show More Options" and click on "Copy as path"**

<br>

**3. Press Win + X on your keyboard and select Windows™ Terminal (Admin) or Powershell (Admin) depending on the version of Windows™ you are running**

|||
|--------|------|
|<img src="https://upload.wikimedia.org/wikipedia/commons/e/e6/Windows_11_logo.svg" style="width: 200px;"/> |<img src="https://upload.wikimedia.org/wikipedia/commons/0/05/Windows_10_Logo.svg" style="width: 200px;"/> |
|![215262254-7466d964-3956-4d71-8014-e2c5869ca4d4](https://user-images.githubusercontent.com/68516357/215263173-500591dd-c6d5-4c2d-9d38-58bc065fff28.png)|![winx_editor-1](https://user-images.githubusercontent.com/68516357/215263348-022dc031-802f-4e93-8999-05d0aa6744b9.png)|

&nbsp;    
**4. Input the command below and press enter, replacing {X:\path\to\your\extracted\folder} including the {} with the path of the extracted folder**
    
```Powershell
  cd "{X:\path\to\your\extracted\folder}"
```
&nbsp; 
**5. Input the command below and press Enter**

```Powershell
  PowerShell.exe -ExecutionPolicy Bypass -File .\Install.ps1
```
&nbsp;  
**6. The script will run and Windows Subsystem For Android™ will be installed**

</details>  
