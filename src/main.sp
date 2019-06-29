#include <sourcemod>
#include <sdktools>
#include <morecolors>

#pragma semicolon 1
#pragma newdecls required

//PLUGIN INFO
static char PLUGIN_NAME[] = "KillboxDM";
static char PLUGIN_DESC[] = "Enchances base gameplay of HL2DM.";
static char PLUGIN_VERSION[] = "1.0.0";
static char PLUGIN_PREFIX[] = "[KillboxDM]";

//DATABASE
static Handle DMDatabase;
static char DatabaseName[] = "KillboxDM";
static char Table_Player[] = "Players";
//SERVER
static bool IsMapRunning = false;
static char CommandList[][255] = {
	"sm_uptime",
	"sm_bet",
	"sm_played"
};
static char PlayerModels[][255] = {
	"models/player/alyx.mdl",
	"models/player/barney.mdl",
	"models/player/breen.mdl",
	"models/player/eli.mdl",
	"models/player/kleiner.mdl",
	"models/player/monk.mdl",
	"models/player/mossman.mdl",
	"models/player/odessa.mdl"
};
static char RespectedModels[][255] = {
	"models/player/combine_soldier.mdl",
	"models/player/combine_soldier_prisonguard.mdl",
	"models/player/combine_super_soldier.mdl"
};
static int TotalUptime;
static Handle UptimeTimer;

//GLOBAL HUD SETTINGS
static float[] HudPos = {0.015, -0.50, 1.0};
static int DefaultHudColor[4] = {72, 117, 212, 255};

//PLAYER
int PlyMoney[MAXPLAYERS + 1];
int PlyKills[MAXPLAYERS + 1];
int PlyDeaths[MAXPLAYERS + 1];
int PlyLevel[MAXPLAYERS + 1];
int PlyXP[MAXPLAYERS + 1];
int PlyBounty[MAXPLAYERS + 1];
Handle PlyHudTimer[MAXPLAYERS + 1];

public Plugin myinfo = {
	name        = PLUGIN_NAME,
	author      = "SirTiggs",
	description = PLUGIN_DESC,
	version     = PLUGIN_VERSION,
	url         = "N/A"
};

public void OnPluginStart() {
	//Player commands
	RegConsoleCmd("sm_uptime", Command_GetUptime, "Returns the uptime of the server.");
	RegConsoleCmd("sm_cmds", Command_GetCommands, "Returns a list of commands.");

	//Debug commands
	RegAdminCmd("sm_reload", Command_ReloadServer, ADMFLAG_ROOT, "DEBUG: Reloads server on current map.");
	RegAdminCmd("sm_fakeclient", Command_CreateFakeClient, ADMFLAG_ROOT, "DEBUG: Creates and connects a fake client.");
	RegAdminCmd("sm_testdisplay", Command_TestDisplay, ADMFLAG_ROOT, "DEBUG: Used for testing hud cords");

	//Setting player accounts
	RegAdminCmd("sm_setmoney", Command_SetPlayerMoney, ADMFLAG_ROOT, "Sets the players money.");

	RegAdminCmd("sm_changemodel", Command_ChangePlayerModel, ADMFLAG_ROOT, "Changes the players model.");
	RegAdminCmd("sm_giveweapons", Command_GivePlayerWeapons, ADMFLAG_ROOT, "Gives the target weapons.");

	//Register events
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

	PrintToServer("%s %s - v%s loaded.", PLUGIN_PREFIX, PLUGIN_NAME, PLUGIN_VERSION);
}

public void OnPluginEnd() {
	if(UptimeTimer != null) {
		KillTimer(UptimeTimer);
		UptimeTimer = null;
	}
}

public void OnMapStart() {
	//Dynamic precaching
	Engine_DynamicPrecache();
	PrecacheSound("Friends/friend_join.wav", true);
	IsMapRunning = true;
}

public void OnMapEnd() {
	IsMapRunning = false;
}

//Use this to setup timers ect
public void OnClientPostAdminCheck(int client) {
	Engine_ResetPlayerGlobals(client);
	LoadPlayer(client);
}

public void OnClientDisconnect(int client) {
	SavePlayer(client);
	Engine_ResetPlayerGlobals(client);
}

//Gametype info changer
public Action OnGetGameDescription(char gameDesc[64]) {
	if(IsMapRunning) {
		gameDesc = "KillboxDM";
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

//EVENTS
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
	PrintToServer("%s - Client disconnected: [%s] reason: %s", PLUGIN_PREFIX, networkID, reason);
	LogMessage("%s - Client disconnected: [%s] reason: %s", PLUGIN_PREFIX, networkID, reason);

	event.BroadcastDisabled = true;
	dontBroadcast = true;
	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
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
	event.BroadcastDisabled = true;
	return Plugin_Handled;
}

public Action Event_PlayerClass(Event event, const char[] name, bool dontBroadcast) {
	event.BroadcastDisabled = true;
	return Plugin_Handled;
}

//Called on movement controls 
public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	return Plugin_Continue;
}







//TIMERS
public Action Timer_CalculateUptime(Handle timer) {
	TotalUptime++;
	return Plugin_Continue;
}


public Action Timer_ProcessHud(Handle timer, any client) {
	if(IsClientInGame(client)) {
		char hudText[255], newMoney[32], newKills[32], newDeaths[32], newBounty[32];
		Engine_FormatNumber(PlyMoney[client], newMoney, sizeof(newMoney));
		Engine_FormatNumber(PlyKills[client], newKills, sizeof(newKills));
		Engine_FormatNumber(PlyDeaths[client], newDeaths, sizeof(newDeaths));
		Engine_FormatNumber(PlyBounty[client], newBounty, sizeof(newBounty));
		Format(hudText, sizeof(hudText), "Money: $%s\nKills: %s\nDeaths: %s\nLevel: %i\nXP: %i\100", 
			newMoney, 
			newKills, 
			newDeaths, 
			PlyLevel[client],
			PlyXP[client]);

		//float x, float y, float holdtime, int r, int g, int b, int a, int effect=0, float fxtime=1.0, float fadein =0.0, float fadeout =0.0
		SetHudTextParams(HudPos[0], HudPos[1], HudPos[2], DefaultHudColor[0], DefaultHudColor[1], DefaultHudColor[2], DefaultHudColor[3], 0, 1.0, 0.1, 0.1);
		ShowHudText(client, -1, hudText);

		//Top hud
		char buffer[255];
		FormatTime(buffer, sizeof(buffer), "Server Uptime: %H Hours %M Minutes %S Seconds", TotalUptime);
		SetHudTextParams(-1.0, 0.01, 1.0, 0, 255, 255, 255, 0, 1.0, 0.1, 0.1);
		ShowHudText(client, -1, buffer);
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


//==DEBUG COMMANDS==
//Reloads server
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

//Used to test hud positions
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

//Creates a fake client that joins the server
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




//Returns server uptime
public Action Command_GetUptime(int client, int args) {
	char buffer[255];
	FormatTime(buffer, sizeof(buffer), "%H Hours %M Minutes %S Seconds", TotalUptime);
	PrintToClientEx(client, "Server uptime: {green}%s{default}", buffer);
	return Plugin_Handled;
}

//Returns a list of palyer commands
public Action Command_GetCommands(int client, int args) {
	PrintToClientEx(client, "See console {grey}(` button by default){default} for command list.");
	for(int i = 0; i <= sizeof(CommandList); i++)  {
		if(i == 0) PrintToConsole(client, "===COMMAND LIST===");
		PrintToConsole(client, "%i. %s", i, CommandList[i]);
	}
	return Plugin_Handled;
}

//Set a players money
public Action Command_SetPlayerMoney(int client, int args) {
	char arg1[32], arg2[9], targetName[32];
	GetCmdArg(1, arg1, sizeof(arg1));
	GetCmdArg(2, arg2, sizeof(arg2));

	int amount = StringToInt(arg2);
	if(amount == 0) { PrintToClientEx(client, "Failed to convert 2nd arguement to int."); return Plugin_Handled; }

	int target = FindTarget(client, arg1, true, false);
	if(target == -1) { PrintToClientEx(client, "Failed to find target."); return Plugin_Handled; }

	GetClientName(target, targetName, sizeof(targetName));

	PlyMoney[target] = amount;

	char amountVal[32];
	Engine_FormatNumber(amount, amountVal, sizeof(amountVal));

	PrintToClientEx(target, "Your money has been set to {green}$%s{default}", amountVal);
	PrintToClientEx(client, "You've set %s's money to {green}$%s{default}", targetName, amountVal);
	SavePlayer(target);
	return Plugin_Handled;
}

//Give a player weapons
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

//Change a players model
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








//Inital database call
static void SQL_Initialise() {
	char error[200], mapName[32], name[255];
	GetCurrentMap(mapName, sizeof(mapName));
	Format(name, sizeof(name), "%s-%s", DatabaseName, mapName);

	DMDatabase = SQLite_UseDatabase(name, error, sizeof(error));
	if(DMDatabase == null) {
		Engine_Error("SQL_Initialise", "Database handle was found to be null");
	}
	else {
		SQL_CreatePlayerTable();
	}
}

static Action SQL_CreatePlayerTable() {
	char query[400];
	Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS '%s' ('ID' VARCHAR(50) NOT NULL PRIMARY KEY, Money INT(20) NOT NULL DEFAULT 0, Kills INT(6) NOT NULL DEFAULT 0, Deaths INT(6) NOT NULL DEFAULT 0, Level INT(3) NOT NULL DEFAULT 1, XP INT(2) NOT NULL DEFAULT 0, Bounty INT(20) NOT NULL DEFAULT 0)", Table_Player);
	SQL_TQuery(DMDatabase, SQL_GenericTQueryCallback, query);
	return Plugin_Handled;
}

//Generic TQuery callback.
static void SQL_GenericTQueryCallback(Handle owner, Handle hndl, const char[] error, any data) {
	if(hndl == null) {
		Engine_Error("SQL_GenericTQueryCallback", "hndl was found to be null");
	}
}

//Loads a player
static void LoadPlayer(int client) {
	char query[200], playerAuth[32];
	GetClientAuthId(client, AuthId_Steam3, playerAuth, sizeof(playerAuth));
	Format(query, sizeof(query), "SELECT * FROM `%s` WHERE `ID` = '%s'", Table_Player, playerAuth);
	SQL_TQuery(DMDatabase, SQL_LoadCallback, query, client);
	PrintToServer("%s Profile %s loaded.", PLUGIN_PREFIX, playerAuth);
}

//Load callback function
static void SQL_LoadCallback(Handle owner, Handle hndl, const char[] error, any data) {
	if(hndl != null) {
		if(!SQL_GetRowCount(hndl)) { //If no row can be found, insert one
			SQL_InsertNewPlayer(data);
		}
		else {
			PlyMoney[data] = SQL_FetchInt(hndl, 1);
			PlyKills[data] = SQL_FetchInt(hndl, 2);
			PlyDeaths[data] = SQL_FetchInt(hndl, 3);
			PlyLevel[data] = SQL_FetchInt(hndl, 4);
			PlyXP[data] = SQL_FetchInt(hndl, 5);
			PlyBounty[data] = SQL_FetchInt(hndl, 6);
			PlyHudTimer[data] = CreateTimer(1.0, Timer_ProcessHud, data, TIMER_REPEAT);
		}
	}
	else {
		Engine_Error("SQL_LoadCallback", "hndl was found to be null");
	}
}

//Inserts a new player into the database
static void SQL_InsertNewPlayer(int client) {
	char query[250], playerAuth[32];
	GetClientAuthId(client, AuthId_Steam3, playerAuth, sizeof(playerAuth));
	Format(query, sizeof(query), "INSERT INTO %s ('ID') VALUES ('%s')", Table_Player, playerAuth);
	SQL_TQuery(DMDatabase, SQL_InsertCallback, query, client);
}

//Insert callback function
static void SQL_InsertCallback(Handle owner, Handle hndl, const char[] error, any data) {
	if(hndl != null) {
		LoadPlayer(data);
		PrintToServer("%s Inserted new profile: %s", PLUGIN_PREFIX, data);
	}
	else {
		Engine_Error("SQL_InsertCallback", "hndl was found to be null.");
	}
}

static void SavePlayer(int client) {
	char query[255], playerAuth[32];
	if(IsClientInGame(client)) {
		GetClientAuthId(client, AuthId_Steam3, playerAuth, sizeof(playerAuth));	
		Format(query, sizeof(query), "UPDATE %s SET Money = '%i', Kills = '%i', Deaths = '%i', Level = '%i', XP = '%i', Bounty = '%i' WHERE ID = '%s'", 
			Table_Player,
			PlyKills[client],
			PlyDeaths[client],
			PlyLevel[client],
			PlyXP[client],
			PlyBounty[client],
			playerAuth);
		SQL_TQuery(DMDatabase, SQL_GenericTQueryCallback, query);
	}
}




static void PrintToClientEx(int client, const char[] arg, any ...) {
	if(IsNullString(arg)) return;
	if(IsClientInGame(client)) {
		char preBuffer[512], buffer[512]; //Maybe figure out a better solution than hardcoding size, maybe using sizeof
		VFormat(preBuffer, sizeof(preBuffer), arg, 3);
		Format(buffer, sizeof(buffer), "{crimson}Killbox-DM{default}| %s", preBuffer);
		CPrintToChat(client, buffer);
	}
}

static void PrintToAllClients(const char[] arg, any ...) {
	if(IsNullString(arg)) return;

	char preBuffer[512], buffer[512];
	VFormat(preBuffer, sizeof(preBuffer), arg, 2);
	Format(buffer, sizeof(buffer), "{crimson}Killbox-DM{default}| %s", preBuffer);
	CPrintToChatAll(buffer);
}

//Used to print to all
static void ChatToAll(const char[] arg, any ...) {
	if(IsNullString(arg)) return;
	char buffer[512];
	VFormat(buffer, sizeof(buffer), arg, 2);
	CPrintToChatAll(buffer);
}

//Directly converts float to int
static int FloatToInt(float value) {
	char strVal[10];
	FloatToString(value, strVal, sizeof(strVal));
	return StringToInt(strVal);
}

//Formats numbers XXX.XXX.XXX
static void Engine_FormatNumber(int Number, char Output[32], int MaxLen) {
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

//Dynamically gets models and precaches them
static void Engine_DynamicPrecache() {
	//Player models
	for(int i = 0; i < sizeof(PlayerModels); i++) {
		int result = PrecacheModel(PlayerModels[i], true);
		PrintToServer("%s - Precache model: %s", PLUGIN_PREFIX, PlayerModels[i]);
		if(result == 0) {
			Engine_Error("Engine_DynamicPrecache", "Failed to precache a model");
		}
	}

	//Respected models
	for(int i = 0; i < sizeof(RespectedModels); i++) {
		int result = PrecacheModel(RespectedModels[i], true);
		PrintToServer("%s - Precache model: %s", PLUGIN_PREFIX, PlayerModels[i]);
		if(result == 0) {
			Engine_Error("Engine_DynamicPrecache", "Failed to precache a model");
		}
	}
}

//Cleans up global variables after player leaves
static void Engine_ResetPlayerGlobals(int index) {
	if(index != 0) {
		PlyMoney[index] = 0;
		PlyKills[index] = 0;
		PlyDeaths[index] = 0;
		PlyLevel[index] = 0;
		PlyXP[index] = 0;
		PlyBounty[index] = 0;

		if(PlyHudTimer[index] != null) {
			KillTimer(PlyHudTimer[index]);
			PlyHudTimer[index] = null;
		}
	}
	else {
		Engine_Error("Engine_ResetPlayerGlobals", "Index was equal to 0");
	}
}

//Custom override for error reporting.
static void Engine_Error(char method[32], char content[255]) {
	PrintToServer("%s - Error at (%s): %s.", PLUGIN_PREFIX, method, content);
	LogError("%s - Error at (%s): %s.", PLUGIN_PREFIX, method, content);
}