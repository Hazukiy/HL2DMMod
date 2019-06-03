//FULLRED = BAD
//GREEN = GOOD
//DEFAULT = FOR ALL TEXT
//CRIMSON = PREFIXES

#include <sourcemod>
#include <sdktools>
#include <morecolors>

#pragma semicolon 1
#pragma newdecls required

//Server/Plugin related globals
char PLUGIN_VERSION[5] = "1.0.0";
int TotalUptime;
Handle UptimeTimer;

//Player Database Globals
//We'll perform actions on these then save to SQL database
char PlySteamAuth[255][MAXPLAYERS + 1];
int PlyWallet[MAXPLAYERS + 1];
int PlyBank[MAXPLAYERS + 1];
int PlySalary[MAXPLAYERS + 1];
int PlyDebt[MAXPLAYERS + 1];
int PlyKills[MAXPLAYERS + 1];
int PlyLevel[MAXPLAYERS + 1];
float PlyXP[MAXPLAYERS + 1];

//Player non-database globals
int PlySalaryCount[MAXPLAYERS + 1];
Handle PlySalaryTimer[MAXPLAYERS + 1];

public Plugin myinfo = {
	name        = "RPDM Mod",
	author      = "SirTiggs",
	description = "N/A",
	version     = PLUGIN_VERSION,
	url         = ""
};

//===FORWARDS===
public void OnPluginStart() {
	//Register commands
	RegConsoleCmd("sm_uptime", Command_GetUptime, "Returns the uptime of the server.");
	RegAdminCmd("sm_reload", Command_ReloadServer, ADMFLAG_ROOT, "Reloads server on current map.");

	//Register forwards
	HookEvent("player_connect", OnPlayerConnectEvent, EventHookMode_Pre);
	HookEvent("player_disconnect", OnPlayerDisconnectEvent, EventHookMode_Pre);
	
	//Add listener for chat to override
	AddCommandListener(OnPlayerChatEvent, "say");

	//Timers
	UptimeTimer = CreateTimer(1.0, Timer_CalculateUptime, _, TIMER_REPEAT);

	PrintToServer("HL2DM Mod - v%s loaded.", PLUGIN_VERSION);
}

public void OnPluginEnd() {
	KillTimer(UptimeTimer, true);
}

public void OnMapStart() {
	//TODO: Grim, hardcoded paths... yuk
	PrecacheModel("models/barney.mdl", true);
	PrecacheModel("models/props_c17/FurnitureArmchair001a.mdl", true);
	PrecacheSound("Friends/friend_join.wav", true);
}

//Use this to setup timers ect
public void OnPlayerConnected(int client) {
	char authID[255];
	GetClientAuthId(client, AuthId_Steam3, authID, sizeof(authID));

	//Do this everytime a client connects
	PlySteamAuth[255][client] = authID;
	PlySalary[client] = 10;
	PlySalaryCount[client] = 0;

	//IF SQL does not exist, create 
	//If new, create

	PlySalaryTimer[client] = CreateTimer(1.0, Timer_CalculateSalary, client, TIMER_REPEAT);
}

public void OnPlayerDisconnect(int client) {
	//Save profile

	KillTimer(PlySalaryTimer[client], true);

	PlySteamAuth[client] = "";
	PlyWallet[client] = 0;
	PlyBank[client] = 0;
	PlySalary[client] = 0;
	PlyDebt[client] = 0;
	PlyKills[client] = 0;
	PlyLevel[client] = 0;
	PlyXP[client] = 0.0;
	PlySalaryCount[client] = 0;
}

public Action OnPlayerConnectEvent(Event event, const char[] name, bool dontBroadcast) {
	char playerName[32], address[32];

	event.GetString("address", address, sizeof(address));
	event.GetString("name", playerName, sizeof(playerName));

	PrintToAllClients("{green}%s(%s){default} has joined the game.", playerName, address);
	return Plugin_Handled;
}

public Action OnPlayerDisconnectEvent(Event event, const char[] name, bool dontBroadcast) {
	char playerName[32], playerID[32], reason[32];

	event.GetString("reason", reason, sizeof(reason));
	event.GetString("networkid", playerID, sizeof(playerID));
	GetClientName(event.GetInt("userid"), playerName, sizeof(playerName));

	PrintToAllClients("{fullred}%s(%s){default} has left the game. (reason: %s)", playerName, playerID, reason);
	return Plugin_Handled;
}

public Action OnPlayerChatEvent(int client, const char[] command, int argc) {
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

	if(IsClientAuthorized(client)) {
		prefix = "{darkred}Admin{default}";
	}
	else {
		prefix = "Player";
	}

	//(Admin) SirTiggs: hello
	ChatToAll("(%s) {green}%s{default}: {ghostwhite}%s{default}", prefix, playerName, buffer);
	return Plugin_Handled;
}


//==TIMERS==
public Action Timer_CalculateUptime(Handle timer) {
	TotalUptime++;
	return Plugin_Continue;
}

public Action Timer_CalculateSalary(Handle timer, int client) {
	if(PlySalaryCount[client] >= 60) {
		PlySalaryCount[client] = 0;
		PlyBank[client] += PlySalary[client];
	}
	PlySalaryCount[client]++;
	return Plugin_Continue;
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
	char buffer[255]; //TODO: SIZE
	FormatTime(buffer, sizeof(buffer), "%H:%M:%S", TotalUptime);
	PrintToClientEx(client, "Server uptime: {green}%s{default}", buffer);
	return Plugin_Handled;
}



//OVERRIDES
public void PrintToClientEx(int client, const char[] arg, any ...) {
	if(IsNullString(arg)) return;
	if(IsClientInGame(client)) {
		char preBuffer[512], buffer[512]; //Maybe figure out a better solution than hardcoding size, maybe using sizeof
		VFormat(preBuffer, sizeof(preBuffer), arg, 2);
		Format(buffer, sizeof(buffer), "{crimson}RPDM{default}| %s", preBuffer);
		CPrintToChat(client, buffer);
	}
}

public void PrintToAllClients(const char[] arg, any ...) {
	if(IsNullString(arg)) return;
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