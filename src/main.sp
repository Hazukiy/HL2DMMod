#include <sourcemod>
#include <sdktools>
#include <morecolors>

#pragma semicolon 1
#pragma newdecls required

//Server/Plugin related globals
//TODO: Make these disgusting hardcoded values configurable in a .cfg
char DatabaseName[] = "Roleplay";
char PlayerTableName[] = "Players";
char DoorTableName[] = "Doors";
char SpawnPath[];
static Handle RPDMDatabase;
static float[] PlayerSpawnPos = {-1015474985, -1007978495, 1143341568};
static float[] CopSpawnPos = {1157682742, 1149416807, 1147666944};
static char PlayerModels[][50] = {
"models/humans/group01/female_01.mdl",
"models/humans/group01/female_02.mdl",
"models/humans/group01/female_03.mdl",
"models/humans/group01/female_04.mdl",
"models/humans/group01/female_05.mdl",
"models/humans/group01/female_06.mdl",
"models/humans/group01/female_07.mdl",
"models/humans/group01/male_01.mdl",	
"models/humans/group01/male_02.mdl",
"models/humans/group01/male_03.mdl",
"models/humans/group01/male_04.mdl",
"models/humans/group01/male_05.mdl",
"models/humans/group01/male_06.mdl",
"models/humans/group01/male_07.mdl",
"models/humans/group01/male_08.mdl",
"models/humans/group01/male_09.mdl"};
static char PoliceModel[50] = "models/police.mdl";
char PLUGIN_VERSION[] = "1.0.1";
char AdvertArr[] = {
	"Type {green}!cmds{default} or {green}/cmds{default} for a list of commands.", 
	"Your salary increases every minute.", 
	"You can buy a door by looking at it and typing {green}!buydoor{default}" };
char CmdArr[][20] = { "sm_uptime", "sm_cmds", "sm_buydoor" };
float[] HudPosition = {0.015, -0.50, 1.0}; //X,Y,Holdtime
int HudColor[4] = {72, 117, 212, 255}; //RGBA 
int TotalUptime;
int CurrentAdvertPos;
int CurrentPlayerCount;
Handle UptimeTimer;
Handle AdvertTimer;

//Player Database Globals
//We'll perform actions on these then save to SQL database
char PlySteamAuth[MAXPLAYERS + 1][255];
int PlyWallet[MAXPLAYERS + 1];
int PlyBank[MAXPLAYERS + 1];
int PlySalary[MAXPLAYERS + 1];
int PlyDebt[MAXPLAYERS + 1];
int PlyKills[MAXPLAYERS + 1];
int PlyLevel[MAXPLAYERS + 1];
int PlyIsCop[MAXPLAYERS + 1];
float PlyXP[MAXPLAYERS + 1];
int PlyNextRaise[MAXPLAYERS + 1];

//Player non-database globals
int PlySalaryCount[MAXPLAYERS + 1];
Handle PlySalaryTimer[MAXPLAYERS + 1];
Handle PlyHudTimer[MAXPLAYERS + 1];
Handle PlyLookHit[MAXPLAYERS + 1];

//Door globals
int DoorRelationID[4096];
char DoorOwnerAuthID[4096][32];
char DoorNotice[4096][255];
int DoorIsPolice[4096];
int DoorIsOwned[4096];
int DoorCanBuy[4096];
int DoorPrice[4096];
int DoorIsStore[4096];
char DoorOwnerName[4096][32];

public Plugin myinfo = {
	name        = "RP-DM Mod",
	author      = "SirTiggs",
	description = "A mod that combines DM & RP in one.",
	version     = PLUGIN_VERSION,
	url         = "N/A"
};

//===FORWARDS===
public void OnPluginStart() {
	//Register commands
	RegConsoleCmd("sm_uptime", Command_GetUptime, "Returns the uptime of the server.");
	RegConsoleCmd("sm_cmds", Command_GetCommands, "Returns a list of commands.");
	RegConsoleCmd("sm_buydoor", Command_BuyDoor, "Buy a door.");

	RegAdminCmd("sm_reload", Command_ReloadServer, ADMFLAG_ROOT, "Reloads server on current map.");
	RegAdminCmd("sm_setwallet", Command_SetPlayerWallet, ADMFLAG_ROOT, "Sets the players wallet.");
	RegAdminCmd("sm_fakeclient", Command_CreateFakeClient, ADMFLAG_ROOT, "Creates and connects a fake client.");
	RegAdminCmd("sm_getcords", Command_GetPlayerCords, ADMFLAG_ROOT, "Returns players current vector cords");
	RegAdminCmd("sm_testdisplay", Command_TestDisplay, ADMFLAG_ROOT, "DEBUG: Used for testing hud cords");
	RegAdminCmd("sm_setcop", Command_SetPlayerCop, ADMFLAG_ROOT, "Gives the player cop.");
	RegAdminCmd("sm_strip", Command_StripWeapons, ADMFLAG_ROOT, "Strips a targets weapons");
	RegAdminCmd("sm_giveweapons", Command_GivePlayerWeapons, ADMFLAG_ROOT, "Gives the target weapons.");
	RegAdminCmd("sm_changemodel", Command_ChangePlayerModel, ADMFLAG_ROOT, "Changes the players model.");
	RegAdminCmd("sm_givedoor", Command_GiveDoor, ADMFLAG_ROOT, "Gives a target door permissions");
	RegAdminCmd("sm_setcopdoor", Command_SetCopDoor, ADMFLAG_ROOT, "Sets a cop door.");
	RegAdminCmd("sm_setnotice", Command_SetDoorNotice, ADMFLAG_ROOT, "Sets a door's notice.");
	RegAdminCmd("sm_setstore", Command_SetDoorStore, ADMFLAG_ROOT, "Sets a door as a store.");
	RegAdminCmd("sm_setprice", Command_SetDoorPrice, ADMFLAG_ROOT, "Sets the price of a door.");
	RegAdminCmd("sm_setdoor", Command_SetDoor, ADMFLAG_ROOT, "Sets the door as buyable");

	//Register forwards
	HookEvent("player_connect_client", Event_PlayerConnectClient, EventHookMode_Pre);
	HookEvent("player_connect", Event_PlayerConnect, EventHookMode_Pre);
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	HookEvent("player_activate", Event_PlayerActivate, EventHookMode_Pre);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Pre);
	HookEvent("player_class", Event_PlayerClass, EventHookMode_Pre);
	
	//Add listener for chat to override
	AddCommandListener(Event_PlayerChat, "say");

	//Load database
	SQL_Initialise();

	//Timers
	UptimeTimer = CreateTimer(1.0, Timer_CalculateUptime, _, TIMER_REPEAT);
	AdvertTimer = CreateTimer(600.0, Timer_ProcessAdvert, _, TIMER_REPEAT); //10 minutes

	PrintToServer("HL2DM Mod - v%s loaded.", PLUGIN_VERSION);
}

public void OnPluginEnd() {
	KillTimer(UptimeTimer);
	KillTimer(AdvertTimer);
}

public void OnMapStart() {
	PrecacheModel("models/police.mdl", true);
	PrecacheSound("Friends/friend_join.wav", true);

	//Dynamic precaching
	for(int i = 0; i < sizeof(PlayerModels); i++) {
		int result = PrecacheModel(PlayerModels[i], true);
		if(result == 0) {
			PrintToServer("[RPDM] - Failed to precache model: %s", PlayerModels[i]);
		}
	}

	//Dynamic get of all doors on map
	for(int i = 0; i < 4096; i++) {
		if(IsValidEntity(i)) {
			char classname[32];
			if(GetEntityClassname(i, classname, sizeof(classname))) {
				if(IsValidDoor(classname)) {
					SQL_LoadDoors(i);
				}
			}
		}
	}

	char mapName[50];
	GetCurrentMap(mapName, sizeof(mapName));

	//Load file system
	BuildPath(Path_SM, SpawnPath, 256, "data/roleplay/" + mapName + "player_spawns.txt");
	if(!FileExists(SpawnPath)) PrintToServer("[RPDM] - Warning, cannot find path " + SpawnPath);
}

//Use this to setup timers ect
public void OnClientPostAdminCheck(int client) {
	char authID[255];
	GetClientAuthId(client, AuthId_Steam3, authID, sizeof(authID));
	PlySteamAuth[client] = authID;
	
	SQL_Load(client);
	CurrentPlayerCount++;
}

public void OnClientDisconnect(int client) {
	SQL_Save(client);

	if(PlySalaryTimer[client] != null) {
		KillTimer(PlySalaryTimer[client]);
		PlySalaryTimer[client] = null;
	}

	if(PlyHudTimer[client] != null) {
		KillTimer(PlyHudTimer[client]);
		PlyHudTimer[client] = null;
	}

	if(PlyLookHit[client] != null) {
		KillTimer(PlyLookHit[client]);
		PlyLookHit[client] = null;
	}

	PlySteamAuth[client] = "";
	PlyWallet[client] = 0;
	PlyBank[client] = 0;
	PlySalary[client] = 0;
	PlyDebt[client] = 0;
	PlyKills[client] = 0;
	PlyLevel[client] = 0;
	PlyIsCop[client] = 0;
	PlyXP[client] = 0.00;
	PlyNextRaise[client] = 0;
	PlySalaryCount[client] = 0;
	CurrentPlayerCount--;	
}

//This doesn't work for some reason...probs not supported
public Action OnGetGameDescription(char gameDesc[64]) {
	gameDesc = "HL2 Roleplay";
	return Plugin_Changed; 
}

//==EVENTS
public Action Event_PlayerConnect(Event event, const char[] name, bool dontBroadcast) {
	char playerName[32], networkID[32];
	event.GetString("name", playerName, sizeof(playerName));
	event.GetString("networkid", networkID, sizeof(networkID));
	PrintToAllClients("{green}%s{default} (%s) has connected.", playerName, networkID);
	event.BroadcastDisabled = true;
	dontBroadcast = true;
	return Plugin_Continue;
}

public Action Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	char playerName[32], reason[32], networkID[32];
	event.GetString("name", playerName, sizeof(playerName));
	event.GetString("reason", reason, sizeof(reason));
	event.GetString("networkID", networkID, sizeof(networkID));

	PrintToAllClients("{green}%s{default} (%s) has disconnected. Reason: ({fullred}%s{default})", playerName, networkID, reason);
	LogMessage("RPDM - Client Disconnect: %s", networkID);

	event.BroadcastDisabled = true;
	dontBroadcast = true;
	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	static int victim = 0, attacker = 0, amount = 0;
	char victimName[32], attackerName[32];

	victim = GetClientOfUserId(event.GetInt("userid", 0));
	attacker = GetClientOfUserId(event.GetInt("attacker", 0));

	if(victim == 0) return Plugin_Handled;
	if(attacker == 0) return Plugin_Handled;

	if(victim == attacker) { PrintToClientEx(victim, "You killed yourself."); return Plugin_Handled; }

	if(IsClientConnected(victim) && IsClientInGame(victim) && victim != 0) {
		if(!IsClientConnected(attacker)) {
			PrintToClientEx(victim, "You've been killed by an unknown entity.");
		}
		GetClientName(victim, attackerName, sizeof(attackerName));
		PrintToClientEx(victim, "You've been killed by: {fullred}%s{default}", attackerName);
	}

	if(IsClientConnected(attacker) && IsClientInGame(attacker) && attacker != 0) {
		GetClientName(victim, victimName, sizeof(victimName));
		amount = GetKillAmount(attacker);
		PlyKills[attacker]++;
		PlyWallet[attacker]+= amount;
		PrintToClientEx(attacker, "You've killed {fullred}%s{default} and earned {green}$%i{default}", victimName, amount);
		SQL_Save(attacker);
	}
	return Plugin_Handled;
}

public Action Event_PlayerChat(int client, const char[] command, int argc) {
	char buffer[256], prefix[32], playerName[32], authID[32];

	GetCmdArg(1, buffer, sizeof(buffer));
	GetClientName(client, playerName, sizeof(playerName));
	GetClientAuthId(client, AuthId_Steam3, authID, sizeof(authID));

	if(buffer[0] == '/') return Plugin_Handled;

	for(int i = 1; i < MaxClients + 1; i++){
		if(IsClientConnected(i) && IsClientInGame(i)){
			ClientCommand(i, "play %s", "Friends/friend_join.wav");
		}
	}

	if(GetUserAdmin(client) != INVALID_ADMIN_ID) {
		prefix = "{fullred}Admin{default}";
	}
	else {
		prefix = "Player";
	}

	//(Admin) SirTiggs: hello
	//(Player) SirTiggs: hello
	ChatToAll("(%s) {green}%s{default}: {ghostwhite}%s{default}", prefix, playerName, buffer);
	return Plugin_Handled;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int player = GetClientOfUserId(event.GetInt("userid", 0));
	//if(IsFakeClient(player)) return Plugin_Continue;

	if(PlyIsCop[player] == 1 && GetClientTeam(player) != 2) {
		ChangeClientTeam(player, 2);
	}
	else if(PlyIsCop[player] != 1 && GetClientTeam(player) != 3) {
		ChangeClientTeam(player, 3);
	}
	
	if(PlyIsCop[player] == 1 && GetClientTeam(player) == 2 && IsPlayerAlive(player)) {
		CreateTimer(0.1, Timer_StripWeapons, player);
		CreateTimer(0.2, Timer_ProcessOutfit, player);
	}

	if(PlyIsCop[player] != 1 && GetClientTeam(player) == 3 && IsPlayerAlive(player)) {
		CreateTimer(0.1, Timer_StripWeapons, player);
		CreateTimer(0.2, Timer_ProcessOutfit, player);
	}

	return Plugin_Continue;
}

public Action Event_PlayerConnectClient(Event event, const char[] name, bool dontBroadcast) {
	event.BroadcastDisabled = true;
	dontBroadcast = true;
	return Plugin_Continue;
}

public Action Event_PlayerScore(Event event, const char[] name, bool dontBroadcast) {
	event.BroadcastDisabled = true;
	dontBroadcast = true;
	return Plugin_Handled;
}

public Action Event_PlayerActivate(Event event, const char[] name, bool dontBroadcast) {
	event.BroadcastDisabled = true;
	dontBroadcast = true;
	return Plugin_Handled;
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast) {
	int teamIndex = event.GetInt("team", 0);
	int player = GetClientOfUserId(event.GetInt("userid", 0));

	if(!PlyIsCop[player] && teamIndex == 2) {
		PrintToClientEx(player, "You cannot change to cop if you are not cop.");
		return Plugin_Handled;
	}

	event.BroadcastDisabled = true;
	return Plugin_Handled;
}

public Action Event_PlayerClass(Event event, const char[] name, bool dontBroadcast) {
	event.BroadcastDisabled = true;
	return Plugin_Handled;
}

//Called on movement controls 
public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	if(buttons == IN_USE) {
		//Are we looking at a door?
		Use_ProcessDoorFunc(client);

		//Are we looking at a player?
		Use_ProcessPlayerFunc(client);
	}

	if(buttons == IN_SPEED) {
		Shift_ProcessDoorFunc(client);
	}
	return Plugin_Continue;
}

public void Use_ProcessDoorFunc(int client) {
	int entity = GetClientAimTarget(client, false);
	if(entity == -1 || entity == -2) return;
	if(!IsValidEntity(entity)) return;

	char entClassname[32];
	bool result = GetEntityClassname(entity, entClassname, sizeof(entClassname));

	if(!result) return;
	if(IsValidDoor(entClassname)) {
		int distance = FloatToInt(GetEntityDistance(client, entity));
		if(distance <= 80) {
			if(GetUserAdmin(client) != INVALID_ADMIN_ID || PlyIsCop[client]) {
				AcceptEntityInput(entity, "Toggle");
			}
		}
	}
}

static float[MAXPLAYERS + 1] shiftButtonDelay = 0.0;
public void Shift_ProcessDoorFunc(int client) {
	int entity = GetClientAimTarget(client, false);
	if(entity == -1 || entity == -2) return;
	if(!IsValidEntity(entity)) return;

	char entClassname[32];
	bool result = GetEntityClassname(entity, entClassname, sizeof(entClassname));

	if(!result) return;
	if(IsValidDoor(entClassname)) {
		int distance = FloatToInt(GetEntityDistance(client, entity));
		if(distance <= 80 && GetGameTime() > shiftButtonDelay[client]) {
			if(HasUserGotDoor(client, entity)) {
				PrintToClientEx(client, "Trying to lock/unlock");
				if(GetEntProp(entity, Prop_Data, "m_bLocked") == false) {
					AcceptEntityInput(entity, "Lock");
					PrintToClientEx(client, "You locked your door.");
				}
				else {
					AcceptEntityInput(entity, "Unlock");
					PrintToClientEx(client, "You unlocked your door.");
				}
				shiftButtonDelay[client] = GetGameTime() + 2.0;
			}
		}
	}
}

public void Use_ProcessPlayerFunc(int client) {
	int player = GetClientAimTarget(client, true);
	if(player == -1 || player == -2) return;

	//TODO: Add IsFakeClient check
	if(IsClientConnected(player) && IsClientInGame(player)) {
		//Menu_OpenPlayer(client);
	}
}

//==MENUS==

public int Menu_PlayerHandler(Menu menu, MenuAction action, int param1, int param2)
{
	/* If an option was selected, tell the client about the item. */
	if (action == MenuAction_Select)
	{
		char info[32];
		bool found = menu.GetItem(param2, info, sizeof(info));
		PrintToConsole(param1, "You selected item: %d (found? %d info: %s)", param2, found, info);
	}
	/* If the menu was cancelled, print a message to the server about it. */
	else if (action == MenuAction_Cancel)
	{
		PrintToServer("Client %d's menu was cancelled.  Reason: %d", param1, param2);
	}
	/* If the menu has ended, destroy it */
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}
 
public void Menu_OpenPlayer(int client)
{
	Menu menu = new Menu(Menu_PlayerHandler);
	menu.SetTitle("Do you like apples?");
	menu.AddItem("yes", "Yes");
	menu.AddItem("no", "No");
	menu.ExitButton = false;
	menu.Display(client, 20);
}









//==TIMERS==
public Action Timer_CalculateUptime(Handle timer) {
	TotalUptime++;
	return Plugin_Continue;
}

public Action Timer_CalculateSalary(Handle timer, any client) {
	if(PlySalaryCount[client] <= 0) {
		if(PlyNextRaise[client] == 0) {
			PlyNextRaise[client] = (60 * PlySalary[client]);
			PlySalary[client]++;
			PrintToClientEx(client, "Congratulations! You've received a payrise of {green}$%i{default}", PlySalary[client]);
		}
		else {
			PlyNextRaise[client]--;
		}

		PlySalaryCount[client] = 60;
		PlyBank[client] += PlySalary[client];
		SQL_Save(client);
	}
	PlySalaryCount[client]--;
	return Plugin_Continue;
}

public Action Timer_ProcessHud(Handle timer, any client) {
	if(IsClientInGame(client)) {
		char hudText[512], goodGrammar[32];

		//Lel
		if(PlySalaryCount[client] == 1) {
			goodGrammar = "Second";
		}
		else {
			goodGrammar = "Seconds";
		}

		//HUD PARAMS
		//float x, float y, float holdtime, int r, int g, int b, int a, int effect=0, float fxtime=1.0, float fadein =0.0, float fadeout =0.0

		//MAIN HUD
		char reWallet[32], reBank[32], reDebt[32], reSalary[32], reKills[32], isCop[32];
		FormatNumber(PlyWallet[client], reWallet, sizeof(reWallet));
		FormatNumber(PlyBank[client], reBank, sizeof(reBank));
		FormatNumber(PlyDebt[client], reDebt, sizeof(reDebt));
		FormatNumber(PlySalary[client], reSalary, sizeof(reSalary));
		FormatNumber(PlyKills[client], reKills, sizeof(reKills));

		if(PlyIsCop[client] == 1) 
		{
			isCop = "Yes";
		}
		else {
			isCop = "No";
		}

		Format(hudText, sizeof(hudText), "Wallet: $%s\nBank: $%s\nDebt: $%s\nSalary: $%s\nNext Pay: %i %s\nKills: %s\nLevel: %i\nXP: %d/100\nNext Raise: %i Minutes", 
			reWallet, reBank, reDebt, reSalary, PlySalaryCount[client], goodGrammar, reKills, PlyLevel[client], PlyXP[client], PlyNextRaise[client]);
		SetHudTextParams(HudPosition[0], HudPosition[1], HudPosition[2], HudColor[0], HudColor[1], HudColor[2], HudColor[3], 0, 1.0, 0.1, 0.1);
		ShowHudText(client, -1, hudText);

		//Top hud
		char buffer[255];
		FormatTime(buffer, sizeof(buffer), "Server Uptime: %H Hours %M Minutes %S Seconds", TotalUptime);
		SetHudTextParams(-1.0, 0.01, 1.0, 0, 255, 255, 255, 0, 1.0, 0.1, 0.1);
		ShowHudText(client, -1, buffer);
	}
	return Plugin_Continue;
}

public Action Timer_ProcessAdvert(Handle timer) {
	if(CurrentAdvertPos != 0) {
		CurrentAdvertPos++;
	}

	if(CurrentAdvertPos > sizeof(AdvertArr)) {
		CurrentAdvertPos = 0;
	}

	PrintToAllClients(AdvertArr[CurrentAdvertPos]);
}

public Action Timer_StripWeapons(Handle timer, any client) {
	int offset = FindDataMapInfo(client, "m_hMyWeapons") - 4;
	for(int i = 0; i < 48; i++) {
		offset += 4;
		int weapon = GetEntDataEnt2(client, offset);
		if(weapon <= 0) return Plugin_Continue;
		if(RemovePlayerItem(client, weapon)) AcceptEntityInput(weapon, "Kill");
	}
	return Plugin_Continue;
}

public Action Timer_GiveWeapons(Handle timer, any client) {
	GivePlayerItem(client, "weapon_357");
	GivePlayerItem(client, "weapon_crossbow");
	GivePlayerItem(client, "weapon_rpg");
	GivePlayerItem(client, "weapon_ar2");
	GivePlayerItem(client, "weapon_crowbar");
	GivePlayerItem(client, "weapon_pistol");
	GivePlayerItem(client, "weapon_smg1");
	GivePlayerItem(client, "weapon_stunstick");
	GivePlayerItem(client, "weapon_shotgun");

	for(int i = 0; i < 3; i++) {
		GivePlayerItem(client, "weapon_frag");
		GivePlayerItem(client, "weapon_slam");
	}
	return Plugin_Continue;
}

public Action Timer_AwaitTeleport(Handle timer, any client) {
	if(PlyIsCop[client] == 1) {
		TeleportEntity(client, CopSpawnPos, NULL_VECTOR, NULL_VECTOR);
	}
	else {
		TeleportEntity(client, PlayerSpawnPos, NULL_VECTOR, NULL_VECTOR);
	}
	return Plugin_Handled;
}

public Action Timer_ProcessOutfit(Handle timer, any client) {
	if(PlyIsCop[client] == 1) {
		ProcessCopOutfit(client);
	}
	else {
		ProcessPlayerOutfit(client);
	}
	CreateTimer(0.1, Timer_AwaitTeleport, client);
	return Plugin_Handled;
}

public Action Timer_ProcessLookHit(Handle timer, any client) {
	ProcessDoor(client);
	ProcessPlayer(client);
	return Plugin_Continue;
}

public void ProcessDoor(int client) {
	int entity = GetClientAimTarget(client, false);
	if(entity == -1 || entity == -2) return;
	if(!IsValidEntity(entity)) return; 

	char entClassname[32];
	bool result = GetEntityClassname(entity, entClassname, sizeof(entClassname));
	if(!result) return;

	if(IsValidDoor(entClassname)) {
		int distance = FloatToInt(GetEntityDistance(client, entity));
		if(distance <= 110) {
			char buffer[255];

			//Is for sale
			if(DoorCanBuy[entity] == 1) {
				Format(buffer, sizeof(buffer), "<Property #%i For Sale!>\nDoor Price: $%i", entity, DoorPrice[entity]);
				SetHudTextParams(-1.0, -1.0, 1.0, 255, 255, 0, 255, 0, 0.0, 0.0, 0.0);
			}
			
			if(DoorCanBuy[entity] == 0 && DoorIsOwned[entity] == 0) {
				if(StrEqual(DoorNotice[entity], "", false)) {
					Format(buffer, sizeof(buffer), "<Property #%i Not For Sale>", entity);
					SetHudTextParams(-1.0, -1.0, 1.0, 255, 255, 0, 255, 0, 0.0, 0.0, 0.0);
				}
				else {
					Format(buffer, sizeof(buffer), "<Property #%i Not For Sale>\nNotice: %s", entity, DoorNotice[entity]);
					SetHudTextParams(-1.0, -1.0, 1.0, 255, 0, 0, 255, 0, 0.0, 0.0, 0.0);
				}
			}

			//Is store
			if(DoorIsStore[entity] == 1) {
				Format(buffer, sizeof(buffer), "<Store #%i>\nSells: %s", entity, DoorNotice[entity]);
				SetHudTextParams(-1.0, -1.0, 1.0, 0, 255, 0, 255, 0, 0.0, 0.0, 0.0);
			}

			//Is police door
			if(DoorIsPolice[entity] == 1) {
				if(PlyIsCop[client]) {
					Format(buffer, sizeof(buffer), "<Police Property #%i>", entity);
					SetHudTextParams(-1.0, -1.0, 1.0, 0, 0, 255, 255, 0, 0.0, 0.0, 0.0);
				}
				else {
					Format(buffer, sizeof(buffer), "<Police Property #%i>\nNo Entry", entity);
					SetHudTextParams(-1.0, -1.0, 1.0, 0, 0, 255, 255, 0, 0.0, 0.0, 0.0);
				}
			}

			//Is owned
			if(DoorIsOwned[entity]) {
				if(HasUserGotDoor(client, entity)) {
					Format(buffer, sizeof(buffer), "<Property #%i>\nYou own this property.", entity);
					SetHudTextParams(-1.0, -1.0, 1.0, 255, 255, 0, 255, 0, 0.0, 0.0, 0.0);
				}
				else {
					Format(buffer, sizeof(buffer), "<Property #%i>\nThis property is owned.", entity);
					SetHudTextParams(-1.0, -1.0, 1.0, 255, 0, 0, 255, 0, 0.0, 0.0, 0.0);
				}
			}
			ShowHudText(client, -1, buffer);
		}
	}
}

public void ProcessPlayer(int client) {
	int entity = GetClientAimTarget(client, true);
	if(entity == -1 || entity == -2 || entity == 0) return;
	if(!IsValidEntity(entity)) return;

	if(IsClientConnected(entity) && IsClientInGame(entity)) {
		int distance = FloatToInt(GetEntityDistance(client, entity));
		if(distance <= 100) {
			char buffer[255], reWallet[32], reSalary[32], reKills[32];
			FormatNumber(PlyWallet[entity], reWallet, sizeof(reWallet));
			FormatNumber(PlySalary[entity], reSalary, sizeof(reSalary));
			FormatNumber(PlyKills[entity], reKills, sizeof(reKills));

			if(PlyIsCop[entity] == 1 && GetUserAdmin(entity) == INVALID_ADMIN_ID) {
				Format(buffer, sizeof(buffer), "<Cop>\nWallet: $%s\nSalary: $%s\nKills: %s", reWallet, reSalary, reKills);
			}
			else if(PlyIsCop[entity] == 1 && GetUserAdmin(entity) != INVALID_ADMIN_ID) {
				Format(buffer, sizeof(buffer), "<Admin>\nPrivate Profile");
			}
			else {
				Format(buffer, sizeof(buffer), "<Player>\nWallet: $%s\nSalary: $%s\nKills: %s", reWallet, reSalary, reKills);
			}		
			SetHudTextParams(-1.0, -1.0, 1.0, 255, 255, 0, 255, 0, 0.0, 0.0, 0.0);
			ShowHudText(client, -1, buffer);
		}
	}
}

public void ProcessCopOutfit(int client) {
	SetEntityModel(client, PoliceModel);
	SetEntityHealth(client, 150);
	GivePlayerItem(client, "weapon_pistol");
	GivePlayerItem(client, "weapon_stunstick");
	GivePlayerItem(client, "weapon_physcannon");
}

public void ProcessPlayerOutfit(int client) {
	int index = GetRandomInt(0, sizeof(PlayerModels) - 1);
	SetEntityModel(client, PlayerModels[index]);
	SetEntityHealth(client, 100);
	GivePlayerItem(client, "weapon_physcannon");
}



//==COMMANDS==
public Action Command_ReloadServer(int client, int args) {
	char mapName[32], playerName[32], format[255], ip[12], auth[32];

	GetCurrentMap(mapName, sizeof(mapName));
	GetClientName(client, playerName, sizeof(playerName));
	GetClientIP(client, ip, sizeof(ip), false);
	GetClientAuthId(client, AuthId_Steam3, auth, sizeof(auth));

	//Maybe in future add a ~5 second delay before restarting
	Format(format, sizeof(format), "Server reloaded by user %s(%s): %s", playerName, ip, auth);
	LogMessage(format);
	ForceChangeLevel(mapName, format);
	return Plugin_Handled;
}

public Action Command_GetUptime(int client, int args) {
	char buffer[255];
	FormatTime(buffer, sizeof(buffer), "%H Hours %M Minutes %S Seconds", TotalUptime);
	PrintToClientEx(client, "Server uptime: {green}%s{default}", buffer);
	return Plugin_Handled;
}

public Action Command_GetCommands(int client, int args) {
	PrintToClientEx(client, "See console {grey}(` button by default){default} for command list.");
	for(int i = 0; i < sizeof(CmdArr); i++)  {
		if(i == 0) PrintToConsole(client, "===COMMAND LIST===");
		PrintToConsole(client, "%i. %s", i, CmdArr[i]);
	}
	return Plugin_Handled;
}

public Action Command_GetPlayerCords(int client, int args) {
	float pos[3];
	GetClientAbsOrigin(client, pos);
	PrintToClientEx(client, "Cords: X:{green}%d{default} Y:{green}%d{default} Z:{green}%d{default}", pos[0], pos[1], pos[2]);
	return Plugin_Handled;
}

public Action Command_TestDisplay(int client, int args) {
	char xBuffer[5], yBuffer[5];
	float x = 0.0, y = 0.0;

	GetCmdArg(1, xBuffer, sizeof(xBuffer));
	GetCmdArg(2, yBuffer, sizeof(yBuffer));

	x = StringToFloat(xBuffer);
	y = StringToFloat(yBuffer);

	SetHudTextParams(x, y, 1.0, 255, 0, 0, 255, 1, 4.0, 4.0, 4.0);
	ShowHudText(client, -1, "[This is a test]");
	return Plugin_Handled;
}

public Action Command_StripWeapons(int client, int args) {
	char arg1[32], playerName[32];
	GetCmdArg(1, arg1, sizeof(arg1));

	if(args != 1) { PrintToClientEx(client, "Command takes 1 command."); return Plugin_Handled; }

	int target = FindTarget(client, arg1, true, false);
	if (target == -1) { PrintToClientEx(client, "Could not find player."); return Plugin_Handled; }

	GetClientName(target, playerName, sizeof(playerName));
	PrintToClientEx(client, "You've stripped {green}%s{default}'s weapons", playerName);
	PrintToClientEx(target, "Your weapons have been stripped.");

	CreateTimer(0.3, Timer_StripWeapons, target);
	return Plugin_Handled;
}

public Action Command_SetPlayerCop(int client, int args) {
	char arg1[32], arg2[32], playerName[32];
	GetCmdArg(1, arg1, sizeof(arg1));
	GetCmdArg(2, arg2, sizeof(arg2));

	if(args != 2) { PrintToClientEx(client, "Command takes 2 arguments."); return Plugin_Handled; }
	int target = FindTarget(client, arg1, true, false);
	if (target == -1) { PrintToClientEx(client, "Could not find player."); return Plugin_Handled; }

	GetClientName(target, playerName, sizeof(playerName));
	if(StrEqual(arg2, "true", false)) {
		PlyIsCop[target] = 1;
		PrintToClientEx(client, "{green}%s{default} has been given cop status.", playerName);
		PrintToClientEx(target, "You've been given {blue}COP{default} status.");
	}
	else if(StrEqual(arg2, "false", false)) {
		PlyIsCop[target] = 0;
		PrintToClientEx(client, "Removed {green}%s{default}'s cop status.", playerName);
		PrintToClientEx(target, "Your {blue}Cop{default} status has been removed.");
	}

	SQL_Save(target);
	ForcePlayerSuicide(target);
	return Plugin_Handled;
}

public Action Command_SetPlayerWallet(int client, int args) {
	char arg1[32], arg2[9], targetName[32];
	GetCmdArg(1, arg1, sizeof(arg1));
	GetCmdArg(2, arg2, sizeof(arg2));

	int amount = StringToInt(arg2);
	if(amount == 0) { PrintToClientEx(client, "Failed to convert 2nd arguement to int."); return Plugin_Handled; }

	int target = FindTarget(client, arg1, true, false);
	if(target == -1) { PrintToClientEx(client, "Failed to find target."); return Plugin_Handled; }

	GetClientName(target, targetName, sizeof(targetName));

	PlyWallet[target] = amount;

	char amountVal[32];
	FormatNumber(amount, amountVal, sizeof(amountVal));

	PrintToClientEx(target, "Your wallet has been set to {green}$%s{default}", amountVal);
	PrintToClientEx(client, "You've set %s's wallet to {green}$%s{default}", targetName, amountVal);
	SQL_Save(target);
	return Plugin_Handled;
}

public Action Command_CreateFakeClient(int client, int args) {
	char name[32];	
	if(args == 1) {
		GetCmdArg(1, name, sizeof(name));
		CreateFakeClient(name);
	}
	else {
		PrintToClientEx(client, "Command only takes 1 argument (name)");
	}
	return Plugin_Handled;
}

public Action Command_GivePlayerWeapons(int client, int args) {
	char arg1[32], playerName[32];
	GetCmdArg(1, arg1, sizeof(arg1));

	if(args != 1) { PrintToClientEx(client, "Command takes 1 command."); return Plugin_Handled; }

	int target = FindTarget(client, arg1, true, false);
	if (target == -1) { PrintToClientEx(client, "Could not find player."); return Plugin_Handled; }

	GetClientName(target, playerName, sizeof(playerName));
	PrintToClientEx(client, "You've given {green}%s{default} weapons", playerName);
	PrintToClientEx(target, "You've been given weapons.");
	CreateTimer(0.3, Timer_GiveWeapons, target);
	return Plugin_Handled;
}

public Action Command_ChangePlayerModel(int client, int args) {
	if(args != 1) { PrintToClientEx(client, "Command takes 1 argument (modelname)"); return Plugin_Handled; }

	char arg1[64];
	GetCmdArg(1, arg1, sizeof(arg1));

	//TODO: Add validation checks against input argument
	if(!IsModelPrecached(arg1)) {
		PrecacheModel(arg1, true);
	}

	SetEntityModel(client, arg1);
	PrintToClientEx(client, "You've changed your skin to: {green}%s{default}", arg1);
	return Plugin_Handled;
}

public Action Command_GiveDoor(int client, int args) {
	if(args != 1) { PrintToClientEx(client, "Command takes 1 argument (playername)"); return Plugin_Handled; }

	char arg1[32], targetName[32];
	GetCmdArg(1, arg1, sizeof(arg1));

	int target = FindTarget(client, arg1);
	if (target == -1) { PrintToClientEx(client, "Could not find player."); return Plugin_Handled; }

	int entity = GetClientAimTarget(client, false);
	if(entity == -1 || entity == -2) { PrintToClientEx(client, "Entity was invalid"); return Plugin_Handled; }
	if(!IsValidEntity(entity)) { PrintToClientEx(client, "Not a valid entity"); return Plugin_Handled; }

	char entClassname[32];
	bool result = GetEntityClassname(entity, entClassname, sizeof(entClassname));
	if(!result) { PrintToClientEx(client, "Failed to get classname"); return Plugin_Handled; }

	if(IsValidDoor(entClassname)) {
		int distance = FloatToInt(GetEntityDistance(client, entity));
		if(distance <= 100) {
			GetClientName(target, targetName, sizeof(targetName));
			SetPlayerDoor(target, entity);
			PrintToClientEx(client, "You've given {green}%s{default} door {fullred}%i{default}", targetName, entity);
			PrintToClientEx(target, "You've been given access to door {green}%i{default} by {fullred}%s{default}", entity, targetName);
		}
	}
	return Plugin_Handled;
}

public Action Command_SetCopDoor(int client, int args) {
	int entity = GetClientAimTarget(client, false);
	if(entity == -1 || entity == -2) { PrintToClientEx(client, "Entity was invalid"); return Plugin_Handled; }
	if(!IsValidEntity(entity)) { PrintToClientEx(client, "Not a valid entity"); return Plugin_Handled; }

	char entClassname[32];
	bool result = GetEntityClassname(entity, entClassname, sizeof(entClassname));
	if(!result) { PrintToClientEx(client, "Failed to get classname"); return Plugin_Handled; }

	if(IsValidDoor(entClassname)) {
		int distance = FloatToInt(GetEntityDistance(client, entity));
		if(distance <= 100) {
			SetCopDoor(entity);
			PrintToClientEx(client, "Door {green}#%i{default} has been set as a cop door.", entity);
		}
	}
	return Plugin_Handled;
}

public Action Command_SetDoorStore(int client, int args) {
	if(args != 1) { PrintToClientEx(client, "Command takes 1 argument (notice)"); return Plugin_Handled; }
	char arg1[32];
	GetCmdArg(1, arg1, sizeof(arg1));
	int entity = GetClientAimTarget(client, false);
	if(entity == -1 || entity == -2) { PrintToClientEx(client, "Entity was invalid"); return Plugin_Handled; }
	if(!IsValidEntity(entity)) { PrintToClientEx(client, "Not a valid entity"); return Plugin_Handled; }

	char entClassname[32];
	bool result = GetEntityClassname(entity, entClassname, sizeof(entClassname));
	if(!result) { PrintToClientEx(client, "Failed to get classname"); return Plugin_Handled; }

	if(IsValidDoor(entClassname)) {
		int distance = FloatToInt(GetEntityDistance(client, entity));
		if(distance <= 100) {
			SetStoreDoor(entity, arg1);
			PrintToClientEx(client, "Door {green}#%i{default} has been set as a store.", entity);
		}
	}
	return Plugin_Handled;
}

public Action Command_SetDoorNotice(int client, int args) {
	if(args != 1) { PrintToClientEx(client, "Command takes 1 argument (notice)"); return Plugin_Handled; }

	char arg1[32];
	GetCmdArg(1, arg1, sizeof(arg1));

	int entity = GetClientAimTarget(client, false);
	if(entity == -1 || entity == -2) { PrintToClientEx(client, "Entity was invalid"); return Plugin_Handled; }
	if(!IsValidEntity(entity)) { PrintToClientEx(client, "Not a valid entity"); return Plugin_Handled; }

	char entClassname[32];
	bool result = GetEntityClassname(entity, entClassname, sizeof(entClassname));
	if(!result) { PrintToClientEx(client, "Failed to get classname"); return Plugin_Handled; }

	if(IsValidDoor(entClassname)) {
		int distance = FloatToInt(GetEntityDistance(client, entity));
		if(distance <= 100) {
			if(DoorIsPolice[entity] != 1) {
				DoorNotice[entity] = arg1;
				SQL_SaveDoor(entity);
				PrintToClientEx(client, "Door {green}#%i{default} notice set to {green}%s{default}", entity, arg1);
			}
			else {
				PrintToClientEx(client, "You cannot set notices for police doors.");
			}
		}
	}
	return Plugin_Handled;
}

public Action Command_SetDoorPrice(int client, int args) {
	if(args != 1) { PrintToClientEx(client, "Command takes 1 argument (price)"); return Plugin_Handled; }

	char arg1[32];
	GetCmdArg(1, arg1, sizeof(arg1));

	int entity = GetClientAimTarget(client, false);
	if(entity == -1 || entity == -2) { PrintToClientEx(client, "Entity was invalid"); return Plugin_Handled; }
	if(!IsValidEntity(entity)) { PrintToClientEx(client, "Not a valid entity"); return Plugin_Handled; }

	char entClassname[32];
	bool result = GetEntityClassname(entity, entClassname, sizeof(entClassname));
	if(!result) { PrintToClientEx(client, "Failed to get classname"); return Plugin_Handled; }

	if(IsValidDoor(entClassname)) {
		int distance = FloatToInt(GetEntityDistance(client, entity));
		if(distance <= 100) {
			if(DoorIsPolice[entity] != 1 && DoorIsStore[entity] != 1) {
				char formatted[32];
				int value = StringToInt(arg1, 10);
				DoorPrice[entity] = value;
				FormatNumber(value, formatted, sizeof(formatted));
				SQL_SaveDoor(entity);
				PrintToClientEx(client, "Changed price of door {green}#%i{default} to {green}$%s{default}", entity, formatted);
			}
			else {
				PrintToClientEx(client, "You cannot set prices on police doors or store doors.");
			}
		}
	}
	return Plugin_Handled;
}

public Action Command_BuyDoor(int client, int args) {
	int entity = GetClientAimTarget(client, false);
	if(entity == -1 || entity == -2) { PrintToClientEx(client, "Entity was invalid"); return Plugin_Handled; }
	if(!IsValidEntity(entity)) { PrintToClientEx(client, "Not a valid entity"); return Plugin_Handled; }

	char entClassname[32];
	bool result = GetEntityClassname(entity, entClassname, sizeof(entClassname));
	if(!result) { PrintToClientEx(client, "Failed to get classname"); return Plugin_Handled; }

	if(IsValidDoor(entClassname)) {
		int distance = FloatToInt(GetEntityDistance(client, entity));
		if(distance <= 100) {
			if(DoorIsOwned[entity] == 0 && DoorIsPolice[entity] == 0 && DoorIsStore[entity] == 0 && DoorCanBuy[entity] == 1) {
				if(PlyWallet[client] >= DoorPrice[entity]) {
					PlyWallet[client] -= DoorPrice[entity];
					char amount[32];
					FormatNumber(DoorPrice[entity], amount, sizeof(amount));
					PrintToClientEx(client, "Congratulations! You've purchased property {green}#%i{default} for {green}$%s{default}", entity, amount);
					SetPlayerDoor(client, entity);
				}
				else {
					PrintToClientEx(client, "You cannot afford this door.");
				}
			}
			else {
				PrintToClientEx(client, "You cannot buy this door.");
			}
		}
	}
	return Plugin_Handled;
}

public Action Command_SetDoor(int client, int args) {
	if(args != 2) { PrintToClientEx(client, "Command takes 2 arguments (notice, price)"); return Plugin_Handled; }
	char arg1[32], arg2[32];

	GetCmdArg(1, arg1, sizeof(arg1));
	GetCmdArg(2, arg2, sizeof(arg2));

	int entity = GetClientAimTarget(client, false);
	if(entity == -1 || entity == -2) { PrintToClientEx(client, "Entity was invalid"); return Plugin_Handled; }
	if(!IsValidEntity(entity)) { PrintToClientEx(client, "Not a valid entity"); return Plugin_Handled; }

	char entClassname[32];
	bool result = GetEntityClassname(entity, entClassname, sizeof(entClassname));
	if(!result) { PrintToClientEx(client, "Failed to get classname"); return Plugin_Handled; }

	if(IsValidDoor(entClassname)) {
		int distance = FloatToInt(GetEntityDistance(client, entity));
		if(distance <= 100) {
			SetServerDoor(entity, arg1, StringToInt(arg2, 10));
			PrintToClientEx(client, "Set door {green}#%i{default} to price {green}$%i{default} and notice {green}%s{default}", entity, StringToInt(arg2, 10), arg1);
		}
	}
	return Plugin_Handled;
}






static void SQL_InsertNewPlayer(int client) {
	char query[250], playerAuth[32];
	GetClientAuthId(client, AuthId_Steam3, playerAuth, sizeof(playerAuth));
	Format(query, sizeof(query), "INSERT INTO %s ('ID') VALUES ('%s')", PlayerTableName, playerAuth);
	SQL_TQuery(RPDMDatabase, SQL_InsertCallback, query, client);
	PrintToServer("[RPDM] Successfully inserted new profile: %s", playerAuth);
}

static void SQL_Load(int client) {
	char query[200], playerAuth[32];
	GetClientAuthId(client, AuthId_Steam3, playerAuth, sizeof(playerAuth));
	Format(query, sizeof(query), "SELECT * FROM `%s` WHERE `ID` = '%s'", PlayerTableName, playerAuth);
	SQL_TQuery(RPDMDatabase, SQL_LoadCallback, query, client);
	PrintToServer("[RPDM] Profile %s loaded.", playerAuth);
}

static void SQL_Save(int client) {
	char query[200], playerAuth[32];
	//int client = GetClientUserId(clientIndex);

	if(IsClientInGame(client)) {
		GetClientAuthId(client, AuthId_Steam3, playerAuth, sizeof(playerAuth));
		Format(query, sizeof(query), "UPDATE %s SET Wallet = '%i', Bank = '%i', Salary = '%i', Debt = '%i', Kills = '%i', Level = '%i', IsCop = '%i', XP = '%d', NextRaise = '%i' WHERE ID = '%s'", PlayerTableName, PlyWallet[client], PlyBank[client], PlySalary[client], PlyDebt[client], PlyKills[client], PlyLevel[client], PlyIsCop[client], PlyXP[client], PlyNextRaise[client], playerAuth);
		SQL_TQuery(RPDMDatabase, SQL_GenericTQueryCallback, query);
	}
}

static void SQL_LoadDoors(int entity) {
	char query[200];
	Format(query, sizeof(query), "SELECT * FROM %s WHERE DoorID = %i", DoorTableName, entity);
	SQL_TQuery(RPDMDatabase, SQL_LoadDoorCallback, query, entity);
}

static void SQL_SaveDoor(int entity) {
	char query[200];
	Format(query, sizeof(query), "UPDATE %s SET RelationID = %i, OwnerAuthID = '%s', Notice = '%s', IsPolice = %i, IsOwned = %i, CanBuy = %i, Price = %i, IsStore = %i, OwnerName = '%s' WHERE DoorID = %i", DoorTableName, DoorRelationID[entity], DoorOwnerAuthID[entity], DoorNotice[entity], DoorIsPolice[entity], DoorIsOwned[entity], DoorCanBuy[entity], DoorPrice[entity], DoorIsStore[entity], DoorOwnerName[entity], entity);
	SQL_TQuery(RPDMDatabase, SQL_SaveDoorCallback, query, entity);
}


//Inital database call
static void SQL_Initialise() {
	char error[200], mapName[32], name[255];
	GetCurrentMap(mapName, sizeof(mapName));
	Format(name, sizeof(name), "%s-%s", DatabaseName, mapName);

	RPDMDatabase = SQLite_UseDatabase(name, error, sizeof(error));
	if(RPDMDatabase == null) {
		PrintToServer("[RPDM] Error at SQL_Initialise: %s", error);
		LogError("[RPDM] Error at SQL_Initialise: %s", error);
	}
	else {
		SQL_CreatePlayerTable();
		SQL_CreateDoorTable();
	}
}

//Creates or loads database
static Action SQL_CreatePlayerTable() {
	char query[600];
	Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS '%s' ('ID' VARCHAR(32), Wallet INT(9) NOT NULL DEFAULT 0,Bank INT(9) NOT NULL DEFAULT 100,Salary INT(9) NOT NULL DEFAULT 1,Debt INT(9) NOT NULL DEFAULT 0,Kills INT(9) NOT NULL DEFAULT 0,Level INT(9) NOT NULL DEFAULT 1, IsCop INT(9) NOT NULL DEFAULT 0, XP DECIMAL(10,5) NOT NULL DEFAULT 0, NextRaise INT(9) NOT NULL DEFAULT 60)", PlayerTableName);
	SQL_TQuery(RPDMDatabase, SQL_GenericTQueryCallback, query);
	return Plugin_Handled;
}

//Creates or loads database
static Action SQL_CreateDoorTable() {
	char query[600];
	Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS '%s' ('DoorID' INT(9), RelationID INT(9) DEFAULT 0, OwnerAuthID VARCHAR(32), Notice VARCHAR(32), IsPolice INT(9) DEFAULT 0, IsOwned INT(9) DEFAULT 0, CanBuy INT(9) DEFAULT 0, Price INT(9) DEFAULT 0, IsStore INT(9) DEFAULT 0, OwnerName VARCHAR(32))", DoorTableName);
	SQL_TQuery(RPDMDatabase, SQL_GenericTQueryCallback, query);
	return Plugin_Handled;
}

static void SQL_InsertNewDoor(int entity) {
	char query[250];
	Format(query, sizeof(query), "INSERT INTO %s ('DoorID') VALUES ('%i')", DoorTableName, entity);
	SQL_TQuery(RPDMDatabase, SQL_InsertDoorCallback, query, entity);
	PrintToServer("[RPDM] Successfully inserted new door: %i", entity);
}

//Load door callback function
static void SQL_LoadDoorCallback(Handle owner, Handle hndl, const char[] error, any data) {
	if(hndl != null) {
		if(!SQL_GetRowCount(hndl)) {
			SQL_InsertNewDoor(data);
		}
		else {
			DoorRelationID[data] = SQL_FetchInt(hndl, 1);
			SQL_FetchString(hndl, 2, DoorOwnerAuthID[data], 32);
			SQL_FetchString(hndl, 3, DoorNotice[data], 255);
			DoorIsPolice[data] = SQL_FetchInt(hndl, 4);
			DoorIsOwned[data] = SQL_FetchInt(hndl, 5);
			DoorCanBuy[data] = SQL_FetchInt(hndl, 6);
			DoorPrice[data] = SQL_FetchInt(hndl, 7);
			DoorIsStore[data] = SQL_FetchInt(hndl, 8);
			SQL_FetchString(hndl, 9, DoorOwnerName[data], 32);
		}
	}
	else {
		PrintToServer("[RPDM] Found error on SQL_LoadDoorCallback: %s", error);
		LogError("[RPDM] Found error on SQL_LoadDoorCallback: %s", error);
		return;
	}
}

static void SQL_SaveDoorCallback(Handle owner, Handle hndl, const char[] error, any data) {
	if(hndl != null) {
		SQL_LoadDoors(data);
	}
	else {
		PrintToServer("[RPDM] Found error on SQL_SaveDoorCallback: %s", error);
		LogError("[RPDM] Found error on SQL_SaveDoorCallback: %s", error);
	}
}

//Load callback function
static void SQL_LoadCallback(Handle owner, Handle hndl, const char[] error, any data) {
	if(hndl != null) {
		if(!SQL_GetRowCount(hndl)) {
			SQL_InsertNewPlayer(data);
		}
		else {
			PlyWallet[data] = SQL_FetchInt(hndl, 1);
			PlyBank[data] = SQL_FetchInt(hndl, 2);
			PlySalary[data] = SQL_FetchInt(hndl, 3);
			PlyDebt[data] = SQL_FetchInt(hndl, 4);
			PlyKills[data] = SQL_FetchInt(hndl, 5);
			PlyLevel[data] = SQL_FetchInt(hndl, 6);
			PlyIsCop[data] = SQL_FetchInt(hndl, 7);
			PlyXP[data] = SQL_FetchFloat(hndl, 8);
			PlyNextRaise[data] = SQL_FetchInt(hndl, 9);

			//Timers
			PlySalaryTimer[data] = CreateTimer(1.0, Timer_CalculateSalary, data, TIMER_REPEAT);
			PlyHudTimer[data] = CreateTimer(1.0, Timer_ProcessHud, data, TIMER_REPEAT);
			PlyLookHit[data] = CreateTimer(1.0, Timer_ProcessLookHit, data, TIMER_REPEAT);
		}
	}
	else {
		PrintToServer("[RPDM] Found error on LoadPlayer: %s", error);
		LogError("[RPDM] Found error on LoadPlayer: %s", error);
		return;
	}
}

//Insert callback function
static void SQL_InsertCallback(Handle owner, Handle hndl, const char[] error, any data) {
	if(hndl != null) {
		SQL_Load(data);
	}
	else {
		PrintToServer("[RPDM] Error at SQL_InsertCallback: %s", error);
		LogError("[RPDM] Error at SQL_InsertCallback: %s", error);
	}
}

//Insert Door callback
static void SQL_InsertDoorCallback(Handle owner, Handle hndl, const char[] error, any data) {
	if(hndl != null) {
		SQL_LoadDoors(data);
	}
	else {
		PrintToServer("[RPDM] Error at SQL_InsertCallback: %s", error);
		LogError("[RPDM] Error at SQL_InsertCallback: %s", error);
	}
}

//Creating door database callback
static void SQL_GenericTQueryCallback(Handle owner, Handle hndl, const char[] error, any data) {
	if(hndl == null) {
		PrintToServer("[RPDM] Error at SQL_GenericTQueryCallback: %s", error);
		LogError("[RPDM] Error at SQL_GenericTQueryCallback: %s", error);
	}
}


//===FILES===
public void File_SetPlayerSpawn(float pos[3]) {
	static Handle keyStore



}





//OVERRIDES & NATIVES?
public void PrintToClientEx(int client, const char[] arg, any ...) {
	if(IsNullString(arg)) return;
	if(IsClientInGame(client)) {
		char preBuffer[512], buffer[512]; //Maybe figure out a better solution than hardcoding size, maybe using sizeof
		VFormat(preBuffer, sizeof(preBuffer), arg, 3);
		Format(buffer, sizeof(buffer), "{crimson}RPDM{default}| %s", preBuffer);
		CPrintToChat(client, buffer);
	}
}

public void PrintToAllClients(const char[] arg, any ...) {
	if(IsNullString(arg)) return;

	if(CurrentPlayerCount == 0) {
		return;
	}

	char preBuffer[512], buffer[512];
	VFormat(preBuffer, sizeof(preBuffer), arg, 2);
	Format(buffer, sizeof(buffer), "{crimson}RPDM{default}| %s", preBuffer);
	CPrintToChatAll(buffer);
}

public void ChatToAll(const char[] arg, any ...) {
	if(IsNullString(arg)) return;
	char buffer[512];
	VFormat(buffer, sizeof(buffer), arg, 2);
	CPrintToChatAll(buffer);
}

public int GetKillAmount(int client) {
	return (PlySalary[client] + GetRandomInt(1, 10));
}

public float GetXpAmount(int client) {
	return (PlyLevel[client] * 2.0);
}

public int FloatToInt(float value) {
	char strVal[10];
	FloatToString(value, strVal, sizeof(strVal));
	return StringToInt(strVal);
}

public bool HasUserGotDoor(int client, int entity) {
	char authID[32];
	bool retVal = false;

	GetClientAuthId(client, AuthId_Steam3, authID, sizeof(authID));
	if(StrEqual(DoorOwnerAuthID[entity], authID, false)) {
		retVal = true;
	}
	return retVal;
}

public void SetServerDoor(int entity, char notice[32], int price) {
	DoorIsOwned[entity] = 0;
	DoorOwnerAuthID[entity] = "";
	DoorCanBuy[entity] = 1;
	DoorIsStore[entity] = 0;
	DoorIsPolice[entity] = 0;
	DoorPrice[entity] = price;
	DoorNotice[entity] = notice;
	DoorOwnerName[entity] = "SERVER";
	SQL_SaveDoor(entity);
}

public void SetPlayerDoor(int client, int entity) {
	char auth[32], notice[255], name[32];
	GetClientName(client, name, sizeof(name));
	GetClientAuthId(client, AuthId_Steam3, auth, sizeof(auth));
	Format(notice, sizeof(notice), "Owned by %s", name);

	DoorIsOwned[entity] = 1;
	DoorOwnerAuthID[entity] = auth;
	DoorCanBuy[entity] = 0;
	DoorIsStore[entity] = 0;
	DoorIsPolice[entity] = 0;
	DoorNotice[entity] = notice;
	DoorOwnerName[entity] = name;
	SQL_SaveDoor(entity);
}

public void SetCopDoor(int entity) {
	DoorIsOwned[entity] = 0;
	DoorOwnerAuthID[entity] = "";
	DoorCanBuy[entity] = 0;
	DoorNotice[entity] = "";
	DoorPrice[entity] = 0;
	DoorOwnerName[entity] = "SERVER";
	DoorIsStore[entity] = 0;
	DoorIsPolice[entity] = 1;
	SQL_SaveDoor(entity);
}

public void SetStoreDoor(int entity, char notice[32]) {
	DoorIsOwned[entity] = 0;
	DoorOwnerAuthID[entity] = "";
	DoorCanBuy[entity] = 0;
	DoorNotice[entity] = notice;
	DoorPrice[entity] = 0;
	DoorOwnerName[entity] = "SERVER";
	DoorIsStore[entity] = 1;
	DoorIsPolice[entity] = 0;
	SQL_SaveDoor(entity);
}

public bool IsValidDoor(char entClassname[32]) {
	bool retVal = false;
	if(StrEqual(entClassname, "func_door_rotating", false) || StrEqual(entClassname, "func_door", false) || StrEqual(entClassname, "prop_door_rotating", false)) {
		retVal = true;
	}
	return retVal;
}

public void IntToStringBool(int num, char retVal[32], int size) {
	if(num == 1) retVal = "True";
	if(num == 0) retVal = "False";
}

public void FormatNumber(int Number, char Output[32], int MaxLen) {
	IntToString(Number, Output, MaxLen);
	
	int pos = strlen(Output	);
	int count = 1;
	while(pos > 0) {
		if(count == 4) {
			count = 0;
			int len = strlen(Output);

			for(int i = len; i >= pos; i--) {
				Output[i+1] = Output[i];
			}

			Output[pos] = ',';
			Output[len+2] = 0;
			pos++;
		}
		count++;
		pos--;
	}
}

public float GetEntityDistance(int client, int entity) {
	float playerPos[3], entityPos[3], retVal;
	GetClientAbsOrigin(client, playerPos);
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", entityPos);
	retVal = GetVectorDistance(playerPos, entityPos, false);
	return retVal;
}