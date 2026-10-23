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
    Plane-drop Nuke — shootable bomb, staggered kills, stock kill logic.
    Credit: coolyer

    Zone file:
    xmodel,p7_zm_power_up_nuke
    vehicle,veh_bo3_dlc_mil_b17_bomber
    fx,zombie/fx_powerup_nuke_zmb
    scriptparsetree,scripts/zm/zm_nuke.gsc
*/

#define NUKE_USE_SCRIPT_MODEL        0
#define NUKE_PLANE_MODEL            "veh_bo3_dlc_mil_b17_bomber"
#define NUKE_PLANE_ALT              1200
#define NUKE_PLANE_DIST             2200
#define NUKE_PLANE_TIME             6
#define NUKE_BOMB_FALL_TIME         3
#define NUKE_BOMB_MODEL             "p7_zm_power_up_nuke"
#define NUKE_FX_NUKE                "zombie/fx_powerup_nuke_zmb"
#define NUKE_SOUND_FLY              "veh_dlc_b17_bomber"
#define NUKE_SOUND_EXPLODE          "evt_nuke_flash"
#define NUKE_ANNOUNCER              "nuke"
#define NUKE_PLAYER_POINTS          400
#define NUKE_KILL_DAMAGE            666
#define NUKE_KILL_DELAY             3
#define NUKE_AIM_THRESHOLD          8
#define NUKE_SHOOT_BONUS            100

#precache( "xmodel", NUKE_PLANE_MODEL );
#precache( "xmodel", NUKE_BOMB_MODEL );
#precache( "fx", NUKE_FX_NUKE );
#using_animtree( "mp_vehicles" );

// ===========================================================================
// Init
// ===========================================================================
function autoexec __init__sytem__()
{
    system::register( "zm_nuke", &__init__, undefined, undefined );
}

function __init__()
{
    //thread powerup_cmd_think(); // Uncomment to enable dev command for spawning nuke powerup
    level._custom_powerups[ "nuke" ].grab_powerup = &nuke_grab_override;
    if( !isdefined( level._effect[ "nuke_plane_nuke" ] ) )
    {
        level._effect[ "nuke_plane_nuke" ] = NUKE_FX_NUKE;
    }
}

// ===========================================================================
// Grab override — called when player touches nuke powerup
// ===========================================================================
function nuke_grab_override( player )
{
    if( !isdefined( self ) || !isdefined( player ) )
        return true;
    if( IS_TRUE( self.claimed ) )
        return true;

    self.claimed = 1;

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

// ===========================================================================
// Powerup helpers
// ===========================================================================
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

// ===========================================================================
// Plane strike — fly path and drop bomb
// ===========================================================================
function nuke_plane_strike( v_target, player_team )
{
    level endon( "game_ended" );
    level endon( "nuke_complete" );

    path = nuke_plane_calc_path( v_target );

    owner_info = nuke_plane_get_owner();
    plane = nuke_plane_spawn( path.start, path.yaw, owner_info.owner );
    if( !isdefined( plane ) )
    {
        thread nuke_detonate_and_kill( v_target, player_team );
        nuke_plane_cleanup( undefined, owner_info.owner, owner_info.temp );
        return;
    }

    nuke_plane_fly( plane, path, v_target, player_team );

    nuke_plane_cleanup( plane, owner_info.owner, owner_info.temp );
}

function nuke_plane_calc_path( v_target )
{
    path = spawnstruct();
    path.yaw = randomFloat( 360 );
    forward = anglestoforward( ( 0, path.yaw, 0 ) );
    v_overhead = ( v_target[ 0 ], v_target[ 1 ], v_target[ 2 ] + NUKE_PLANE_ALT );
    path.start = v_overhead - ( forward * NUKE_PLANE_DIST );
    path.end = v_overhead + ( forward * NUKE_PLANE_DIST );
    return path;
}

function nuke_plane_get_owner()
{
    info = spawnstruct();
    info.temp = 0;
    players = getplayers();
    if( isdefined( players ) && players.size > 0 )
    {
        info.owner = players[ 0 ];
    }
    else
    {
        info.owner = spawn( "script_origin", ( 0, 0, 0 ) );
        info.temp = 1;
    }
    return info;
}

function nuke_plane_spawn( v_start, yaw, owner )
{
    plane = undefined;
    if( NUKE_USE_SCRIPT_MODEL )
    {
        plane = spawn( "script_model", v_start );
        if( isdefined( plane ) )
        {
            plane setmodel( NUKE_PLANE_MODEL );
            plane.angles = ( 0, yaw, 0 );
        }
    }
    else
    {
        plane = spawnhelicopter( owner, v_start, ( 0, yaw, 0 ), NUKE_PLANE_MODEL, NUKE_PLANE_MODEL );
        if( isdefined( plane ) )
        {
            plane SetRotorSpeed( 1 );
        }
    }
    if( isdefined( plane ) )
    {
        plane playsound( NUKE_SOUND_FLY );
    }
    return plane;
}

function nuke_plane_fly( plane, path, v_target, player_team )
{
    begin = gettime();
    released = 0;
    while( isdefined( plane ) )
    {
        elapsed = ( gettime() - begin ) / 1000.0;
        if( elapsed >= NUKE_PLANE_TIME )
            break;

        t = elapsed / NUKE_PLANE_TIME;
        plane.origin = path.start + ( path.end - path.start ) * t;
        plane.angles = ( 0, path.yaw, 0 );

        if( !released && t >= 0.5 )
        {
            released = 1;
            v_bomb_start = ( plane.origin[ 0 ], plane.origin[ 1 ], plane.origin[ 2 ] - 40 );
            thread nuke_bomb_fall( v_bomb_start, v_target, player_team );
        }
        wait( 0.02 );
    }
}

// ===========================================================================
// Bomb fall — drops from plane, sways, lands at target
// ===========================================================================
function nuke_bomb_fall( v_start, v_target, player_team )
{
    level endon( "game_ended" );
    level endon( "nuke_complete" );

    level.nuke_bomb_shot = 0;
    bomb = nuke_bomb_spawn( v_start );
    if( !isdefined( bomb ) )
    {
        thread nuke_detonate_and_kill( v_target, player_team );
        return;
    }

    bomb thread nuke_bomb_watch_aim( player_team );
    nuke_bomb_animate( bomb, v_start, v_target );

    if( !level.nuke_bomb_shot )
    {
        if( isdefined( bomb ) )
            bomb delete();
        thread nuke_detonate_and_kill( v_target, player_team );
    }
}

function nuke_bomb_spawn( v_start )
{
    bomb = spawn( "script_model", v_start );
    if( !isdefined( bomb ) )
        return undefined;
    bomb setmodel( NUKE_BOMB_MODEL );
    bomb.angles = ( 90, randomFloat( 360 ), 0 );
    return bomb;
}

function nuke_bomb_animate( bomb, v_start, v_target )
{
    begin = gettime();
    for( ;; )
    {
        elapsed = ( gettime() - begin ) / 1000.0;
        if( elapsed >= NUKE_BOMB_FALL_TIME || !isdefined( bomb ) )
            break;

        t = elapsed / NUKE_BOMB_FALL_TIME;
        t = t * t;
        v_base = v_start + ( v_target - v_start ) * t;

        sway = 1 - t;
        bomb.origin = v_base + ( sin( elapsed * 360 ) * 18 * sway, cos( elapsed * 280 ) * 12 * sway, 0 );
        bomb.angles = ( 90 + sin( elapsed * 450 ) * 6, bomb.angles[ 1 ] + sin( elapsed * 320 ) * 1.5, cos( elapsed * 380 ) * 8 );
        wait( 0.02 );
    }
}

// ===========================================================================
// Aim detection — shoot bomb to detonate early + bonus
// ===========================================================================
function nuke_bomb_watch_aim( player_team )
{
    self endon( "death" );
    while( isdefined( self ) )
    {
        players = getplayers();
        foreach( player in players )
        {
            if( nuke_check_player_aim( player, self.origin ) )
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

function nuke_check_player_aim( player, v_bomb )
{
    if( !zm_utility::is_player_valid( player ) )
        return false;
    if( !player AttackButtonPressed() )
        return false;

    eye = player GetEye();
    forward = AnglesToForward( player GetPlayerAngles() );
    to_bomb = v_bomb - eye;
    dot = VectorDot( to_bomb, forward );
    if( dot < 0 )
        return false;

    closest = eye + forward * dot;
    return Distance( closest, v_bomb ) < NUKE_AIM_THRESHOLD;
}

// ===========================================================================
// Detonation — FX + staggered kills + points
// ===========================================================================
function nuke_detonate_and_kill( v_boom, player_team )
{
    level endon( "game_ended" );
    level endon( "nuke_complete" );

    level thread zm_powerup_nuke::nuke_delay_spawning( NUKE_KILL_DELAY );
    nuke_detonate_vfx( v_boom, player_team );
    wait( 0.5 );

    zombies_nuked = nuke_mark_zombies( v_boom );
    nuke_kill_zombies( zombies_nuked );

    level notify( "nuke_complete" );
    level.nuke_plane_active = 0;

    nuke_award_points( player_team );
}

function nuke_detonate_vfx( v_boom, player_team )
{
    if( isdefined( level._effect[ "nuke_plane_nuke" ] ) )
        playfx( level._effect[ "nuke_plane_nuke" ], v_boom );
    else if( isdefined( level._effect[ "powerup_nuke" ] ) )
        playfx( level._effect[ "powerup_nuke" ], v_boom );

    PlaySoundAtPosition( NUKE_SOUND_EXPLODE, v_boom );
    level thread zm_audio::sndannouncerplayvox( NUKE_ANNOUNCER );
    earthquake( 0.6, 1.0, v_boom, 2000 );
    level thread zm_powerup_nuke::nuke_flash( player_team );
}

function nuke_mark_zombies( v_boom )
{
    zombies = GetAiTeamArray( level.zombie_team );
    zombies = ArraySort( zombies, v_boom );
    zombies_nuked = [];

    for( i = 0; i < zombies.size; i++ )
    {
        if( IS_TRUE( zombies[ i ].ignore_nuke ) )
            continue;
        if( IsDefined( zombies[ i ].marked_for_death ) && zombies[ i ].marked_for_death )
            continue;
        if( IsDefined( zombies[ i ].nuke_damage_func ) )
        {
            zombies[ i ] thread [[ zombies[ i ].nuke_damage_func ]]();
            continue;
        }
        if( zm_utility::is_magic_bullet_shield_enabled( zombies[ i ] ) )
            continue;

        zombies[ i ].marked_for_death = true;
        if( !IS_TRUE( zombies[ i ].nuked ) && !zm_utility::is_magic_bullet_shield_enabled( zombies[ i ] ) )
        {
            zombies[ i ].nuked = true;
            zombies_nuked[ zombies_nuked.size ] = zombies[ i ];
            zombies[ i ] clientfield::increment( "zm_nuked" );
        }
    }
    return zombies_nuked;
}

function nuke_kill_zombies( zombies_nuked )
{
    for( i = 0; i < zombies_nuked.size; i++ )
    {
        wait( randomfloatrange( 0.1, 0.7 ) );
        if( !IsDefined( zombies_nuked[ i ] ) )
            continue;
        if( zm_utility::is_magic_bullet_shield_enabled( zombies_nuked[ i ] ) )
            continue;

        nuke_zombie_death_fx( zombies_nuked[ i ] );
        zombies_nuked[ i ] dodamage( zombies_nuked[ i ].health + NUKE_KILL_DAMAGE, zombies_nuked[ i ].origin );
        level thread zm_daily_challenges::increment_nuked_zombie();
    }
}

function nuke_zombie_death_fx( zombie )
{
    if( IS_TRUE( zombie.isdog ) )
        return;
    if( !IS_TRUE( zombie.no_gib ) )
    {
        zombie zombie_utility::zombie_head_gib();
    }
    zombie playsound( "evt_nuked" );
}

function nuke_award_points( player_team )
{
    players = GetPlayers( player_team );
    if( !isdefined( players ) || players.size == 0 )
        players = GetPlayers();

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

// ===========================================================================
// Dev command — uncomment in __init__ to enable
// ===========================================================================
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
            IPrintLnBold( "^1 powerup_cmd: unknown '" + cmd_value + "' try 'nuke'" );
        }
    }
}

function powerup_cmd_spawn_nuke()
{
    player = powerup_cmd_find_player();
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

function powerup_cmd_find_player()
{
    players = GetPlayers();
    for( i = 0; i < players.size; i++ )
    {
        if( !isdefined( players[ i ] ) || !isalive( players[ i ] ) )
            continue;
        if( players[ i ].sessionstate != "playing" )
            continue;
        return players[ i ];
    }
    return undefined;
}
