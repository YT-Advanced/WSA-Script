# How to getting latest Insider Build
#### **1. Check the Insider Build from [Release](https://github.com/YT-Advanced/WSA-Script/releases/tag/WSA-Insider-Version) first. If it does not have the version you want, continue to follow this guide. If it does, then feel free to use those prebuild WSA builds**
#### **2. Open the home page, click on the button (shown below) and select "import a repository" or go to [this page directly](https://github.com/new/import)**
   ***Step 2.1:***
   
   <img src="https://user-images.githubusercontent.com/68516357/221636520-78d0716a-247b-4034-aa9d-bdbe2277950c.png" style="width: 350px;"/>
   
   ***Step 2.2:***
   
   ![image](https://user-images.githubusercontent.com/68516357/221641202-e3ef4deb-f2dd-46e6-82c8-fb4767f82e99.png)
   
---   
#### **3. [Copy the URL of this Repo](https://github.com/YT-Advanced/WSA-Script) and paste it into the the text box below and press "Import"** 

![image](https://user-images.githubusercontent.com/68516357/221643582-72d71f68-8f53-48d9-a940-692a54d42098.png)

---
#### **4. Go to the **Setting** tab in your newly imported repo and enable "Github Actions"**
   ***Step 4.1:***
   
![Settings](https://user-images.githubusercontent.com/68516357/222214308-b52b1c6f-a60b-44ef-9ce0-bc335087e3a2.png)

   ***Step 4.2:***
   
![MRq9WD3SO2](https://user-images.githubusercontent.com/68516357/222215598-30d68ad3-9700-4061-bba4-815b3befcb10.png)

---
#### **5. Then, scroll down until you reach the section titled "Workflow Permission" and follow the steps as shown in the image below**
![image](https://user-images.githubusercontent.com/68516357/224546417-a82249b4-3864-42bd-8a29-32350b8b0c97.png)

---
#### **6. Open [this link](https://github.com/settings/tokens/new) in new tab, then follow the step below. FINALLY, SCROLL DOWN AND CLICK GENERATE TOKEN**
![image](https://user-images.githubusercontent.com/70064328/231184720-0d3b4ce7-0b82-4b1f-b337-5f0fd0ceb632.png)

---
#### **7. The key will appear. Then click the copy button at right side of the key.**
![image](https://user-images.githubusercontent.com/70064328/231189492-cf3b407e-708b-4224-ba4e-11f3e27012a1.png)

---
#### **8. Now, back to your repository **Setting** tab, and open Secret and Variable, then click Action. Next click **New reporistory secret** button**
![image](https://user-images.githubusercontent.com/70064328/231191605-1e3c4b53-6d17-49f5-8e7f-c752ae12aee8.png)

---
#### **9. In the name boxes, type PAT. Next, paste your copied Secret key to Secret boxes, then click **Add Secrets** button**
![image](https://user-images.githubusercontent.com/70064328/231192376-16aa194c-07ae-4262-857f-d9d86701a110.png)

---
#### **10. Now, Go to the **Action** tab**
![CvYhP0B0CI](https://user-images.githubusercontent.com/68516357/222221960-f48ab9c3-eb77-4cb0-b932-5cd343381048.png)

---
#### **11. In the left sidebar, click the **Custom Build** workflow.**
![image](https://user-images.githubusercontent.com/68516357/222221307-8a4571d2-ac3e-410b-b999-0eb62b14d8d5.png)

---
#### **12. Above the list of workflow runs, select **Run workflow****
![image](https://user-images.githubusercontent.com/68516357/222222850-f991890c-5a80-4cc2-b83d-0ef35c24a79e.png)

---
#### **13. Select your desired options such as ***WSA Release Channel***, ***Magisk Version***, ***WSA Archetecture*** , ***GApps Varient*** and ***Compression Format*** then click **Run workflow****
> **Note** : 
> In WSA Release Channel option, you must choose Insider Private or specific Microsoft User Code for getting latest WSA Insider Version

![image](https://user-images.githubusercontent.com/68516357/222224185-abcfa0cf-c8c6-46e3-bc38-871c968b86f2.png)

---    
#### **14. Wait for the action to complete and download the artifact**
**DO NOT download it via multithread downloaders like IDM**
![image](https://user-images.githubusercontent.com/68516357/222224469-5748b78a-158e-46ff-9f65-317dbb519aac.png)

---
#### **15. Install like normal using [the instructions](https://github.com/YT-Advanced/WSA-Script#--installation) in this repository** and most important of all....
</details>
