#include <sourcemod>
#include <sdktools>
#include <morecolors>

#pragma semicolon 1
#pragma newdecls required

//Server/Plugin related globals
char DatabaseName[] = "RPDM";
char PlayerTableName[] = "Players";
char ServerTableName[] = "Server";
char PLUGIN_VERSION[5] = "1.0.0";
char AdvertArr[] = {"Type {green}!cmds{default} or {green}/cmds{default}", "Test", "text2" };
char CmdArr[2][20] = { "sm_uptime", "sm_cmds" };
float[] HudPosition = {0.015, -0.60, 1.0}; //X,Y,Holdtime
int HudColor[4] = {45, 173, 107, 255}; //RGBA 
int TotalUptime;
int CurrentAdvertPos;
int CurrentPlayerCount;
Handle UptimeTimer;
Handle AdvertTimer;
static Handle RPDMDatabase;

//Player Database Globals
//We'll perform actions on these then save to SQL database
char PlySteamAuth[MAXPLAYERS + 1][255];
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
Handle PlyHudTimer[MAXPLAYERS + 1];

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
	RegAdminCmd("sm_reload", Command_ReloadServer, ADMFLAG_ROOT, "Reloads server on current map.");

	//Register forwards
	HookEvent("player_connect", OnPlayerConnectEvent, EventHookMode_Pre);
	HookEvent("player_death", OnPlayerDeathEvent, EventHookMode_Pre);
	
	//Add listener for chat to override
	AddCommandListener(OnPlayerChatEvent, "say");

	//Load the database
	SQL_Initialise();

	//Timers
	UptimeTimer = CreateTimer(1.0, Timer_CalculateUptime, _, TIMER_REPEAT);
	AdvertTimer = CreateTimer(600.0, Timer_ProcessAdvert, _, TIMER_REPEAT); //10 minutes

	PrintToServer("HL2DM Mod - v%s loaded.", PLUGIN_VERSION);
}

public void OnPluginEnd() {
	KillTimer(UptimeTimer, true);
	KillTimer(AdvertTimer, true);
}

public void OnMapStart() {
	//TODO: Grim, hardcoded paths... yuk
	PrecacheModel("models/barney.mdl", true);
	PrecacheModel("models/props_c17/FurnitureArmchair001a.mdl", true);
	PrecacheSound("Friends/friend_join.wav", true);
}

//Use this to setup timers ect
public void OnClientPostAdminCheck(int client) {
	char authID[255];
	GetClientAuthId(client, AuthId_Steam3, authID, sizeof(authID));

	//Load player
	SQL_Load(client);

	//Setup client
	PlySteamAuth[client] = authID;
	PlySalaryTimer[client] = CreateTimer(1.0, Timer_CalculateSalary, client, TIMER_REPEAT);
	PlyHudTimer[client] = CreateTimer(1.0, Timer_ProcessHud, client, TIMER_REPEAT);
	
	CurrentPlayerCount++;
}

public void OnClientDisconnect(int client) {	
	char playerName[32];
	GetClientName(client, playerName, sizeof(playerName));
	PrintToAllClients("{fullred}%s{default} has left the game.", playerName);
	
	//Save
	SQL_Save(client);

	//Destroy timers
	KillTimer(PlySalaryTimer[client], true);
	KillTimer(PlyHudTimer[client], true);

	//Clear globals
	InitialiseGlobals(client);

	CurrentPlayerCount--;
}

public Action OnPlayerConnectEvent(Event event, const char[] name, bool dontBroadcast) {
	char playerName[32], address[32];

	event.GetString("address", address, sizeof(address));
	event.GetString("name", playerName, sizeof(playerName));

	PrintToAllClients("{green}%s(%s){default} has joined the game.", playerName, address);
	return Plugin_Handled;
}

public Action OnPlayerDeathEvent(Event event, const char[] name, bool dontBroadcast) {
	int userID = 0, attacker = 0, amount = 0;
	char victimName[32], attackerName[32];

	userID = event.GetInt("userid", 0);
	attacker = event.GetInt("attacker", 0);

	if(IsClientConnected(userID) && IsClientInGame(userID) && userID != 0) {
		if(!IsClientConnected(attacker)) {
			PrintToClientEx(userID, "You've been killed by an unknown entity.");
			return Plugin_Handled;
		}

		GetClientName(userID, victimName, sizeof(victimName));
		PrintToClientEx(userID, "You've been killed by: {fullred}%s{default}", attackerName);
	}

	if(IsClientConnected(attacker) && IsClientInGame(attacker) && attacker != 0) {
		GetClientName(attacker, attackerName, sizeof(attackerName));
		amount = GetKillAmount(attacker);
		PlyKills[attacker]++;
		PlyWallet[attacker]+= amount;
		PrintToClientEx(attacker, "You've killed {fullred}%s{default} and earned {green}$%i{default}", attackerName, amount);
	}
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
		prefix = "{cyan}Admin{default}";
	}
	else {
		prefix = "Player";
	}

	//(Admin) SirTiggs: hello
	//(Player) SirTiggs: hello
	ChatToAll("(%s) {green}%s{default}: {ghostwhite}%s{default}", prefix, playerName, buffer);
	return Plugin_Handled;
}








//==TIMERS==
public Action Timer_CalculateUptime(Handle timer) {
	TotalUptime++;
	return Plugin_Continue;
}

public Action Timer_CalculateSalary(Handle timer, any client) {
	if(PlySalaryCount[client] <= 0) {
		PlySalaryCount[client] = 60;
		PlyBank[client] += PlySalary[client];
	}
	PlySalaryCount[client]--;
	return Plugin_Continue;
}

public Action Timer_ProcessHud(Handle timer, any client) {
	if(IsClientInGame(client)) {
		char hudText[512];
		char goodGrammar[32];

		//Lel
		if(PlySalaryCount[client] == 1) {
			goodGrammar = "Second";
		}
		else {
			goodGrammar = "Seconds";
		}

		Format(hudText, sizeof(hudText), "Wallet: $%i\nBank: $%i\nDebt: $%i\nSalary: $%i\nNext Pay: %i %s\nKills: %i\nLevel: %i\nXP: %d/100", 
			PlyWallet[client], PlyBank[client], PlyDebt[client], PlySalary[client], PlySalaryCount[client], goodGrammar, PlyKills[client], PlyLevel[client], PlyXP[client]);
		SetHudTextParams(HudPosition[0], HudPosition[1], HudPosition[2], HudColor[0], HudColor[1], HudColor[2], HudColor[3], 0, 0.0, 0.0);
		ShowHudText(client, -1, hudText);
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






//DATABASE
//Inserts a new entry into the database
static void SQL_InsertNew(int client) {
	if(client != 0) {
		char query[250], playerAuth[32] = "";
		GetClientAuthId(client, AuthId_Steam3, playerAuth, sizeof(playerAuth));
		Format(query, sizeof(query), "INSERT INTO %s ('ID') VALUES ('%s')", PlayerTableName, playerAuth);
		SQL_TQuery(RPDMDatabase, SQL_InsertCallback, query, client);
		PrintToServer("RPDM - Inserted new player");
	}
}

//Load player call
static void SQL_Load(int client) {
	char query[200];
	int index = GetClientOfUserId(client);
	Format(query, sizeof(query), "SELECT * FROM `%s` WHERE `ID` = '%s'", PlayerTableName, PlySteamAuth[index]);
	SQL_TQuery(RPDMDatabase, SQL_LoadCallback, query, index);
	LogMessage("RPDM - Profile %s loaded.", PlySteamAuth[index]);
}

static void SQL_Save(int client) {
	char query[200];
	Format(query, sizeof(query), "UPDATE %s SET Wallet = '%i', Bank = '%i', Salary = '%i', Debt = '%i', Kills = '%i', Level = '%i', XP = '%d' WHERE ID = '%s'", 
		PlyWallet[client], 
		PlyBank[client], 
		PlySalary[client], 
		PlyDebt[client], 
		PlyKills[client],
		PlyLevel[client],
		PlyXP[client],
		PlySteamAuth[client]);
	SQL_TQuery(RPDMDatabase, SQL_SaveCallback, query);
}

//Inital database call
static void SQL_Initialise() {
	char error[200];
	RPDMDatabase = SQLite_UseDatabase(DatabaseName, error, sizeof(error));
	if(RPDMDatabase == null) {
		LogError("RPDM - Error at SQL_Initialise: %s", error);
	}
	else {
		SQL_CreateDatabase();
	}
}

//Creates database
static Action SQL_CreateDatabase() {
	char query[600];
	Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS '%s' ('ID' VARCHAR(32), Wallet INT(9) NOT NULL DEFAULT 0,Bank INT(9) NOT NULL DEFAULT 100,Salary INT(9) NOT NULL DEFAULT 1,Debt INT(9) NOT NULL DEFAULT 0,Kills INT(9) NOT NULL DEFAULT 0,Level INT(9) NOT NULL DEFAULT 1,XP DECIMAL(10,5) NOT NULL DEFAULT 0.0)", PlayerTableName);
	SQL_TQuery(RPDMDatabase, SQL_CreateCallback, query);
	PrintToServer("RPDM - Loaded database");
	return Plugin_Handled;
}

//Insert callback function
static void SQL_InsertCallback(Handle owner, Handle hndl, const char[] error, any data) {
	if(hndl == null) {
		LogError("RPDM - Error at SQL_InsertCallback: %s", error);
	}
}

//Save callback function
static void SQL_SaveCallback(Handle owner, Handle hndl, const char[] error, any data) {
	if(hndl == null) LogError("RPDM - Error at SQL_SaveCallback: %s", error);
}

//Create callback function
static void SQL_CreateCallback(Handle owner, Handle hndl, const char[] error, any data) {
	if(hndl == null) LogError("RPDM - Error at SQL_CreateCallback: %s", error);
}

//Load callback function
static void SQL_LoadCallback(Handle owner, Handle hndl, const char[] error, any data) {
	int client = GetClientOfUserId(data);
	if(client == 0) return;
	if(hndl == null) {
		LogError("RPDM - Found error on LoadPlayer: %s", error);
		return;
	}
	else {
		if(!SQL_GetRowCount(hndl)){
			SQL_InsertNew(client);
		}
		else {
			PlyWallet[client] = SQL_FetchInt(hndl, 1);
			PlyBank[client] = SQL_FetchInt(hndl, 2);
			PlySalary[client] = SQL_FetchInt(hndl, 3);
			PlyDebt[client] = SQL_FetchInt(hndl, 4);
			PlyKills[client] = SQL_FetchInt(hndl, 5);
			PlyLevel[client] = SQL_FetchInt(hndl, 6);
			PlyXP[client] = SQL_FetchFloat(hndl, 7);
			PrintToServer("Loaded %s's profile", PlySteamAuth[client]);
		}
	}
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

public void InitialiseGlobals(int client) {
	PlySteamAuth[client] = "";
	PlyWallet[client] = 0;
	PlyBank[client] = 0;
	PlySalary[client] = 0;
	PlyDebt[client] = 0;
	PlyKills[client] = 0;
	PlyLevel[client] = 0;
	PlyXP[client] = 0.00;
	PlySalaryCount[client] = 0;
	PlySalaryTimer[client] = null;
	PlyHudTimer[client] = null;
}