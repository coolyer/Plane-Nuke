# Plan Nuke A plane drops a nuke
**Author:** Coolyer  
**⚠️ Please credit if used.**


---

## 📥 Installation

1. Place **zm_nuke.gsc** into your `usermaps/scripts/zm/` folder.  
2. In your main maps GSC add `#using scripts\zm\zm_nuke;`
3. If you dont have MidgetBlaster T7 Asset Pack or a veh use NUKE_USE_SCRIPT_MODEL 1 this will stop a crash happening
3. add this to your zone:
```
    xmodel,p7_zm_power_up_nuke
    vehicle,veh_bo3_dlc_mil_b17_bomber <- change this to the veh you want to use for the plane
    fx,zombie/fx_powerup_nuke_zmb
    xmodel,planemodelchangeme
    scriptparsetree,scripts/zm/zm_nuke.gsc
```
4. Open **zm_nuke.gsc** and edit the defines if you wish to change something.
```
#define NUKE_USE_SCRIPT_MODEL       1

#define NUKE_PLANE_MODEL            "Changeme" // plane model
#define NUKE_PLANE_ALT              1200 // height above target for plane to fly
#define NUKE_PLANE_DIST             2200 // distance from target for plane to start and end flight
#define NUKE_PLANE_TIME             6 // time in seconds for plane to fly from start to end
#define NUKE_BOMB_FALL_TIME         3
#define NUKE_BOMB_MODEL             "p7_zm_power_up_nuke"
#define NUKE_FX_NUKE                "zombie/fx_powerup_nuke_zmb"
#define NUKE_SOUND_FLY              "vehsoundfly" // sound of plane flying overhead
#define NUKE_SOUND_EXPLODE          "evt_nuke_flash"
#define NUKE_ANNOUNCER              "nuke" // announcer_vox_nuke Dude going kaboom
#define NUKE_PLAYER_POINTS          400
#define NUKE_KILL_DAMAGE            666 //scales with zombies health
#define NUKE_KILL_DELAY             3
#define NUKE_AIM_THRESHOLD          8 // distance from bomb center that player can shoot to detonate early
#define NUKE_SHOOT_BONUS            100
```
5. Enjoy :) 
---
Any issues please contact me on discord:
    `coolyer`
## Big Thank you to the testers
* Pepergogo
* C
