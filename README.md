# HomeCheck_KratosX_Edition !!ONLY for-Whitemane-Frostmourne-3.3.5a!!


# HomeCheck - KratosX Edition (For Whitemane Frostmourne WOTLK 3.3.5a)

Welcome to the **KratosX Edition** of HomeCheck. This version introduces crucial performance optimizations, automated tank filtering, dynamic talent tracking, and visual raid status indicators.
Please note: This specific addon version only works on Whitemane Frostmourne WOTLK 3.3.5a. If you want to use a version that works on all servers, please download my regular version here:

   Features & Enhancements

# 1. Performance Loop Optimization
- The core background loop for range checks and frame updates has been optimized.
- The Benefit:** This dramatically reduces CPU utilization and eliminates micro-stutters during heavy raid encounters while still offering precise tracking.

# 2. Dynamic Hammer of Justice (HoJ) Tracking
- Full support added for the *Improved Hammer of Justice
  0/2 Points:** 60 Seconds
  1/2 Points:** 50 Seconds
  2/2 Points:** 40 Seconds

# 3. Lay on Hands (LoH) Overhaul
- Dedicated Visibility Button: Added a dedicated toggle button specifically for *Improved Lay on Hands*, allowing users to filter and show only this specific tracker if desired.
- Fixed CD Timers & Glyph Support: Completely fixed the LoH cooldown calculation. The addon now natively tracks the Holy talent tree and properly includes the *Glyph of Lay on Hands* for accurate cooldown tracking.

- <img width="1465" height="949" alt="1 1" src="https://github.com/user-attachments/assets/071d7458-265b-441e-afa4-66915135931a" />


# 4. Dual Spec Talent Desync & Tank Cooldown Sync Button
- Automated Profile Sync: Added a brand-new custom action button to fully resolve talent caching issues caused by swapping specs via Dual Specialization system.
- The Benefit: Clicking this button forces an instant, hard reset of the local talent cache. It immediately synchronizes your personal *Lay on Hands* cooldown timer based on your newly activated talent tree and completely refreshes/resets all active "Tank-only" frames to prevent ghost bars or incorrect mitigation trackers after changing specs.

- <img width="892" height="600" alt="1 2" src="https://github.com/user-attachments/assets/e222b245-e01e-4581-a29d-2863b6283846" />


# 5. New Tank Cooldowns & "Tanks Only" Filtering
- Expanded Spell Database: Added full tracking support for essential defensive Tank cooldowns across multiple classes:
        Warrior: Shield Block
          Druid: Survival Instincts
   Death Knight: Unbreakable Armor
- Tanks Only Filter: Integrated these newly added defensive abilities, with the "Tanks only Toggle"

# 6.  Dead Player Indicators & Desaturation
- Raid Status Sync: Whenever a tracked raid member dies, their respective cooldown frame is automatically desaturated (grayed out) on your interface.
- Visual Anchor: A Skull icon is displayed directly before the name of the deceased player, giving you a immediate visual confirmation that the cooldown is currently unusable due to death of the Player.

- <img width="805" height="523" alt="3" src="https://github.com/user-attachments/assets/99b676d8-d116-4cd2-bae1-34f1a83ef64a" />


# 7. Native DBM Boss Kill/Wipe Reset Hook (THIS WORKS ONLY ON SERVERS WITH A KILL/WIPE COOLDOWN RESET + DBM INSTALLED)
- Raid Cooldown Reset: Fully restored and fixed the automatic raid cooldown cleanup functionality integrated with Deadly Boss Mods (DBM).
- Instant Availability: Upon detecting a boss kill or a raid wipe via DBM, the addon instantly resets all active cooldown frames. This immediately updates the UI to show that all tracked abilities and major cooldowns are fully ready and available for the next pull, completely clearing out all ghost bars.

# 8. Visuall changes
<img width="869" height="586" alt="2" src="https://github.com/user-attachments/assets/dda41ede-03a3-4730-afea-c4e75ac9566a" />



---

     Installation

1. Download this repository as a `.zip` file.
2. Extract only the "Homecheck" folder into your World of Warcraft directory: `Interface\AddOns\`.
3. Crucial: Ensure the folder is named exactly HomeCheck
4. If you had previous versions installed try deleting settings file: WTF\Account\\<ACCOUNT_NAME\>\SavedVariables\HomeCheck.lua

# Credits & License
Based on the original Author Homerocker *HomeCheck*  core functionality. Modified by Kratosx, optimized, and heavily expanded with advanced tracking mechanics and server-side fixes. All bundled libraries (Ace3, LibGroupTalents) belong to their respective authors.

