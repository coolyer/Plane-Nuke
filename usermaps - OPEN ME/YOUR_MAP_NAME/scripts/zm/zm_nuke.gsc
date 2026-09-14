#using scripts\shared\array_shared;
#using scripts\shared\clientfield_shared;
#using scripts\shared\ai\zombie_utility;
#using scripts\shared\system_shared;

#using scripts\zm\_zm_powerups;
#using scripts\zm\_zm_powerup_nuke;
#using scripts\zm\_zm_utility;
#using scripts\zm\_zm_score;
#using scripts\zm\_zm_audio;
#using scripts\zm\_zm_daily_challenges;

#insert scripts\shared\shared.gsh;
#insert scripts\shared\version.gsh;

#namespace zm_nuke;

/*
    Instructions for zm_nuke.gsc:

    Add this line to the top of your main script:
    #using scripts\zm\zm_nuke;


    Add these to your zone file:
    xmodel,p7_zm_power_up_nuke
    vehicle,changemetoveh <- change this to the veh you want to use for the plane dont need to add if you are using NUKE_USE_SCRIPT_MODEL 1 for the plane
    fx,zombie/fx_powerup_nuke_zmb
    xmodel,planemodelchangeme <- if you have added vehicle to your zone file you dont need the xmodel as its included with the vehicle
    scriptparsetree,scripts/zm/zm_nuke.gsc

    If NUKE_USE_SCRIPT_MODEL == 1 (no vehicle needed):
        Just add the model you want to use for the plane in 
        NUKE_PLANE_MODEL add xmodel to your zone file for that model.
    If NUKE_USE_SCRIPT_MODEL == 0 (vehicle needed):
        Also add to your zone file:
        vehicle,veh_bo3_dlc_mil_b17_bomber <- change this to the vehicle you want to use for the plane
*/

// ---------------------------------------------------------------------------
// Plane-drop Nuke
// Credit if used: coolyer
// ---------------------------------------------------------------------------

// Set to 1 to use a script_model (no vehicle asset needed)
// Set to 0 to use spawnhelicopter (requires vehicle in zone)
#define NUKE_USE_SCRIPT_MODEL       1

#define NUKE_PLANE_MODEL            "Changeme" // plane model (used for both modes)
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

#precache( "xmodel", NUKE_PLANE_MODEL );
#precache( "xmodel", NUKE_BOMB_MODEL );
#precache( "fx", NUKE_FX_NUKE );
#using_animtree( "mp_vehicles" );

function autoexec __init__sytem__()
{
    system::register( "zm_nuke", &__init__, undefined, undefined );
}

function __init__()
{
    level thread nuke_override_init();
    //level thread powerup_cmd_think(); // uncomment for dev testing, comment out for release
}

// ---------------------------------------------------------------------------
// Init — keep stock nuke grab overwritten
// ---------------------------------------------------------------------------
function nuke_override_init()
{
    while( !isdefined( level._custom_powerups ) || !isdefined( level._custom_powerups[ "nuke" ] ) )
    {
        wait( 0.5 );
    }
    wait( 1 );
    while( 1 )
    {
        level._custom_powerups[ "nuke" ].grab_powerup = &nuke_grab_override;
        if( !isdefined( level._effect[ "nuke_plane_nuke" ] ) )
        {
            level._effect[ "nuke_plane_nuke" ] = NUKE_FX_NUKE;
        }
        wait( 2 );
    }
}

// ---------------------------------------------------------------------------
// Grab override — called when player touches nuke powerup
// ---------------------------------------------------------------------------
function nuke_grab_override( player )
{
    if( !isdefined( self ) || !isdefined( player ) )
        return true;
    if( IS_TRUE( self.claimed ) )
        return true;

    self.claimed = 1;

    // another nuke plane already in flight — just clean up this powerup
    if( IS_TRUE( level.nuke_plane_active ) )
    {
        nuke_cleanup_powerup( self );
        return true;
    }

    level.nuke_plane_active = 1;

    v_impact = self.origin;
    if( !isdefined( v_impact ) )
        v_impact = player.origin;

    team = player.team;

    // sort zombies by distance for staggered kills
    zombies = getaiteamarray( level.zombie_team );
    if( isdefined( zombies ) )
    {
        player.zombie_nuked = arraysort( zombies, v_impact );
    }

    player notify( "nuke_triggered" );
    nuke_play_grab_fx( self );
    nuke_cleanup_powerup( self );

    level thread nuke_plane_strike( v_impact, team );
    return true;
}

// ---------------------------------------------------------------------------
// Helpers cut code down from main functions for clarity
// ---------------------------------------------------------------------------
function nuke_cleanup_powerup( powerup )
{
    if( !isdefined( powerup ) )
        return;
    powerup stoploopsound();
    powerup hide();
    powerup thread zm_powerups::powerup_delete_delayed( 0.1 );
}

function nuke_play_grab_fx( powerup )
{
    if( !isdefined( powerup ) )
        return;
    if( isdefined( level._effect[ "powerup_grabbed" ] ) )
        PlayFX( level._effect[ "powerup_grabbed" ], powerup.origin );
    else if( isdefined( level._effect[ "powerup_grabbed_solo" ] ) )
        PlayFX( level._effect[ "powerup_grabbed_solo" ], powerup.origin );
    PlaySoundAtPosition( "zmb_powerup_grabbed", powerup.origin );
}

function nuke_plane_cleanup( plane, owner, temp_owner )
{
    if( isdefined( plane ) )
        plane delete();
    if( temp_owner && isdefined( owner ) )
        owner delete();
}

// ---------------------------------------------------------------------------
// Plane strike
// ---------------------------------------------------------------------------
function nuke_plane_strike( v_target, player_team )
{
    level endon( "game_ended" );

    flight_yaw = randomFloat( 360 );
    forward = anglestoforward( ( 0, flight_yaw, 0 ) );
    v_overhead = ( v_target[ 0 ], v_target[ 1 ], v_target[ 2 ] + NUKE_PLANE_ALT );
    v_start = v_overhead - ( forward * NUKE_PLANE_DIST );
    v_end = v_overhead + ( forward * NUKE_PLANE_DIST );

    players = getplayers();
    temp_owner = 0;
    if( isdefined( players ) && players.size > 0 )
    {
        owner = players[ 0 ];
    }
    else
    {
        owner = spawn( "script_origin", v_start );
        temp_owner = 1;
    }

    if( NUKE_USE_SCRIPT_MODEL )
    {
        plane = spawn( "script_model", v_start );
        if( isdefined( plane ) )
        {
            plane setmodel( NUKE_PLANE_MODEL );
            plane.angles = ( 0, flight_yaw, 0 );
        }
    }
    else
    {
        plane = spawnhelicopter( owner, v_start, ( 0, flight_yaw, 0 ), NUKE_PLANE_MODEL, NUKE_PLANE_MODEL );
    }

    if( !isdefined( plane ) )
    {
        thread nuke_detonate_and_kill( v_target, player_team );
        nuke_plane_cleanup( undefined, owner, temp_owner );
        return;
    }

    if( !NUKE_USE_SCRIPT_MODEL )
    {
        plane SetRotorSpeed( 1 );
    }
    plane playsound( NUKE_SOUND_FLY );

    begin = gettime();
    released = 0;
    while( isdefined( plane ) )
    {
        elapsed = ( gettime() - begin ) / 1000.0;
        if( elapsed >= NUKE_PLANE_TIME )
            break;

        t = elapsed / NUKE_PLANE_TIME;
        plane.origin = v_start + ( v_end - v_start ) * t;
        plane.angles = ( 0, flight_yaw, 0 );

        if( !released && t >= 0.5 )
        {
            released = 1;
            thread nuke_bomb_fall( ( plane.origin[ 0 ], plane.origin[ 1 ], plane.origin[ 2 ] - 40 ), v_target, player_team );
        }
        wait( 0.02 );
    }

    nuke_plane_cleanup( plane, owner, temp_owner );
}

// ---------------------------------------------------------------------------
// Bomb fall
// ---------------------------------------------------------------------------
function nuke_bomb_fall( v_start, v_target, player_team )
{
    level endon( "game_ended" );

    level.nuke_bomb_shot = 0;
    bomb = spawn( "script_model", v_start );
    bomb setmodel( NUKE_BOMB_MODEL );
    bomb.angles = ( 90, randomFloat( 360 ), 0 );
    bomb thread nuke_bomb_watch_aim( player_team );

    begin = gettime();
    for( ;; )
    {
        elapsed = ( gettime() - begin ) / 1000.0;
        if( elapsed >= NUKE_BOMB_FALL_TIME || !isdefined( bomb ) )
            break;

        t = elapsed / NUKE_BOMB_FALL_TIME;
        t = t * t;
        v_base = v_start + ( v_target - v_start ) * t;

        sway_scale = 1 - t;
        bomb.origin = v_base + ( sin( elapsed * 360 ) * 18 * sway_scale, cos( elapsed * 280 ) * 12 * sway_scale, 0 );
        bomb.angles = ( 90 + sin( elapsed * 450 ) * 6, bomb.angles[ 1 ] + sin( elapsed * 320 ) * 1.5, cos( elapsed * 380 ) * 8 );
        wait( 0.02 );
    }

    if( !level.nuke_bomb_shot )
    {
        if( isdefined( bomb ) )
        {
            bomb delete();
        }
        thread nuke_detonate_and_kill( v_target, player_team );
    }
}

// ---------------------------------------------------------------------------
// Aim detection — if player shoots bomb, detonate early + reward
// ---------------------------------------------------------------------------
function nuke_bomb_watch_aim( player_team )
{
    self endon( "death" );
    while( isdefined( self ) )
    {
        players = getplayers();
        foreach( player in players )
        {
            if( !zm_utility::is_player_valid( player ) )
                continue;
            if( !player AttackButtonPressed() )
                continue;

            eye = player GetEye();
            forward = AnglesToForward( player GetPlayerAngles() );
            to_bomb = self.origin - eye;
            dot = VectorDot( to_bomb, forward );
            if( dot < 0 )
                continue;

            closest = eye + forward * dot;
            if( Distance( closest, self.origin ) < NUKE_AIM_THRESHOLD )
            {
                level.nuke_bomb_shot = 1;
                level.nuke_bomb_shooter = player;
                thread nuke_detonate_and_kill( self.origin, player_team );
                self delete();
                return;
            }
        }
        wait( 0.05 );
    }
}

// ---------------------------------------------------------------------------
// Detonation — flash + FX + pause spawns + staggered kills + points
// ---------------------------------------------------------------------------
function nuke_detonate_and_kill( v_boom, player_team )
{
    level endon( "game_ended" );

    level thread zm_powerup_nuke::nuke_delay_spawning( NUKE_KILL_DELAY );

    if( isdefined( level._effect[ "nuke_plane_nuke" ] ) )
        playfx( level._effect[ "nuke_plane_nuke" ], v_boom );
    else if( isdefined( level._effect[ "powerup_nuke" ] ) )
        playfx( level._effect[ "powerup_nuke" ], v_boom );

    PlaySoundAtPosition( NUKE_SOUND_EXPLODE, v_boom );
    level thread zm_audio::sndannouncerplayvox( NUKE_ANNOUNCER );
    earthquake( 0.6, 1.0, v_boom, 2000 );
    level thread zm_powerup_nuke::nuke_flash( player_team );

    wait( 0.5 );

    zombies = GetAiTeamArray( level.zombie_team );
    zombies = ArraySort( zombies, v_boom );
    zombies_nuked = [];

    for( i = 0; i < zombies.size; i++ )
    {
        if( IS_TRUE( zombies[ i ].ignore_nuke ) )
        {
            continue;
        }
        if( IsDefined( zombies[ i ].marked_for_death ) && zombies[ i ].marked_for_death )
        {
            continue;
        }
        if( IsDefined( zombies[ i ].nuke_damage_func ) )
        {
            zombies[ i ] thread [[ zombies[ i ].nuke_damage_func ]]();
            continue;
        }
        if( zm_utility::is_magic_bullet_shield_enabled( zombies[ i ] ) )
        {
            continue;
        }
        zombies[ i ].marked_for_death = true;
        if( !IS_TRUE( zombies[ i ].nuked ) && !zm_utility::is_magic_bullet_shield_enabled( zombies[ i ] ) )
        {
            zombies[ i ].nuked = true;
            zombies_nuked[ zombies_nuked.size ] = zombies[ i ];
            zombies[ i ] clientfield::increment( "zm_nuked" );
        }
    }

    for( i = 0; i < zombies_nuked.size; i++ )
    {
        wait( randomfloatrange( 0.1, 0.7 ) );
        if( !IsDefined( zombies_nuked[ i ] ) )
        {
            continue;
        }
        if( zm_utility::is_magic_bullet_shield_enabled( zombies_nuked[ i ] ) )
        {
            continue;
        }
        if( !( IS_TRUE( zombies_nuked[ i ].isdog ) ) )
        {
            if( !IS_TRUE( zombies_nuked[ i ].no_gib ) )
            {
                zombies_nuked[ i ] zombie_utility::zombie_head_gib();
            }
            zombies_nuked[ i ] playsound( "evt_nuked" );
        }
        zombies_nuked[ i ] dodamage( zombies_nuked[ i ].health + NUKE_KILL_DAMAGE, zombies_nuked[ i ].origin );
        level thread zm_daily_challenges::increment_nuked_zombie();
    }

    level notify( "nuke_complete" );
    level.nuke_plane_active = 0;

    players = GetPlayers( player_team );
    if( !isdefined( players ) || players.size == 0 )
    {
        players = GetPlayers();
    }
    for( i = 0; i < players.size; i++ )
    {
        players[ i ] zm_score::player_add_points( "nuke_powerup", NUKE_PLAYER_POINTS );
    }

    if( IS_TRUE( level.nuke_bomb_shot ) && isdefined( level.nuke_bomb_shooter ) && isalive( level.nuke_bomb_shooter ) )
    {
        level.nuke_bomb_shooter zm_score::player_add_points( "nuke_powerup", NUKE_SHOOT_BONUS );
    }
    level.nuke_bomb_shooter = undefined;
}

// ---------------------------------------------------------------------------
// Dev command — uncomment for testing,
// Console: powerup_cmd "nuke"
// Spawns a nuke powerup in front of the playing player.
// ---------------------------------------------------------------------------

function powerup_cmd_think()
{
    level endon( "game_ended" );
    ModVar( "powerup_cmd", "" );
    for( ;; )
    {
        WAIT_SERVER_FRAME;
        cmd_value = GetDvarString( "powerup_cmd", "" );
        if( !isdefined( cmd_value ) || cmd_value == "" )
            continue;
        ModVar( "powerup_cmd", "" );
        command = ToLower( cmd_value );
        if( command == "nuke" )
        {
            level thread powerup_cmd_spawn_nuke();
        }
        else
        {
            IPrintLnBold( "^1powerup_cmd: unknown '" + cmd_value + "' try 'nuke'" );
        }
    }
}

function powerup_cmd_spawn_nuke()
{
    players = GetPlayers();
    player = undefined;
    for( i = 0; i < players.size; i++ )
    {
        if( !isdefined( players[ i ] ) || !isalive( players[ i ] ) )
            continue;
        if( players[ i ].sessionstate != "playing" )
            continue;
        player = players[ i ];
        break;
    }
    if( !isdefined( player ) )
    {
        IPrintLnBold( "^1powerup_cmd: no playing player found" );
        return;
    }
    forward = anglestoforward( player.angles );
    v_drop = player.origin + ( forward * 80 ) + ( 0, 0, 20 );
    trace = GroundTrace( v_drop + ( 0, 0, 500 ), v_drop + ( 0, 0, -10000 ), false, undefined, false );
    if( isdefined( trace ) && trace[ "fraction" ] < 1 )
    {
        v_drop = trace[ "position" ];
    }
    zm_powerups::specific_powerup_drop( "nuke", v_drop );
    IPrintLnBold( "^3powerup_cmd: nuke spawned in front of " + player.name );
}
