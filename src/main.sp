#include <sourcemod>
#include <sdktools>
#include <morecolors>

#pragma semicolon 1
#pragma newdecls required

//Server/Plugin related globals
static float[] PlayerSpawnPos = {-1002412101, -1006626218, -1012073472};
static float[] CopSpawnPos = {-1017074004, -1132854018, -1026297856};
char DatabaseName[] = "RPDM";
char PlayerTableName[] = "Players";
char PLUGIN_VERSION[5] = "1.0.0";
char AdvertArr[] = {"Type {green}!cmds{default} or {green}/cmds{default}", "Test", "text2" };
char CmdArr[2][20] = { "sm_uptime", "sm_cmds" };
float[] HudPosition = {0.015, -0.50, 1.0}; //X,Y,Holdtime
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
int PlyIsCop[MAXPLAYERS + 1];
float PlyXP[MAXPLAYERS + 1];


//Player non-database globals
int PlySalaryCount[MAXPLAYERS + 1];
bool PlyHasMenuOpen[MAXPLAYERS + 1];
Handle PlySalaryTimer[MAXPLAYERS + 1];
Handle PlyHudTimer[MAXPLAYERS + 1];
Handle PlyCheckDoor[MAXPLAYERS + 1];

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
	RegAdminCmd("sm_setwallet", Command_SetPlayerWallet, ADMFLAG_ROOT, "Sets the players wallet.");
	RegAdminCmd("sm_fakeclient", Command_CreateFakeClient, ADMFLAG_ROOT, "Creates and connects a fake client.");
	RegAdminCmd("sm_getcords", Command_GetPlayerCords, ADMFLAG_ROOT, "Returns players current vector cords");
	RegAdminCmd("sm_testdisplay", Command_TestDisplay, ADMFLAG_ROOT, "DEBUG: Used for testing hud cords");
	RegAdminCmd("sm_setcop", Command_SetPlayerCop, ADMFLAG_ROOT, "Gives the player cop.");

	//Register forwards
	HookEvent("player_connect_client", Event_PlayerConnectClient, EventHookMode_Pre);
	HookEvent("player_connect", Event_PlayerConnect, EventHookMode_Pre);
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	HookEvent("player_activate", Event_PlayerActivate, EventHookMode_Pre);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Pre);
	
	//Add listener for chat to override
	AddCommandListener(Event_PlayerChat, "say");

	//Load the database
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
	PrecacheSound("Friends/friend_join.wav", true);
}

//Use this to setup timers ect
public void OnClientPostAdminCheck(int client) {
	char authID[255];
	GetClientAuthId(client, AuthId_Steam3, authID, sizeof(authID));
	PlySteamAuth[client] = authID;

	//Load player
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

	if(PlyCheckDoor[client] != null) {
		KillTimer(PlyCheckDoor[client]);
		PlyCheckDoor[client] = null;
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
	PlySalaryCount[client] = 0;
	CurrentPlayerCount--;
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
	int client = 0, attacker = 0, amount = 0;
	char victimName[32], attackerName[32];

	client = GetClientOfUserId(event.GetInt("userid", 0));
	attacker = GetClientOfUserId(event.GetInt("attacker", 0));

	if(client == attacker) { PrintToClientEx(client, "You killed yourself."); return Plugin_Handled; }

	if(IsClientConnected(client) && IsClientInGame(client) && client != 0) {
		if(!IsClientConnected(attacker)) {
			PrintToClientEx(client, "You've been killed by an unknown entity.");
		}
		GetClientName(client, attackerName, sizeof(attackerName));
		PrintToClientEx(client, "You've been killed by: {fullred}%s{default}", attackerName);
	}

	if(IsClientConnected(attacker) && IsClientInGame(attacker) && attacker != 0) {
		GetClientName(client, victimName, sizeof(victimName));
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
		prefix = "{aqua}Admin{default}";
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
	int client = GetClientOfUserId(event.GetInt("userid", 0));
	if(PlyIsCop[client] == 1) {
		TeleportEntity(client, CopSpawnPos, NULL_VECTOR, NULL_VECTOR);
	}
	else {
		TeleportEntity(client, PlayerSpawnPos, NULL_VECTOR, NULL_VECTOR);
	}
	StripWeapons(client);
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

//Called on movement controls 
public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	if(buttons == IN_USE) {
		//Are we looking at a door?
		Use_ProcessDoorFunc(client);

		//Are we looking at a player?
		Use_ProcessPlayerFunc(client);
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
	if(StrEqual(entClassname, "func_door_rotating", false) || StrEqual(entClassname, "func_door", false)) {
		int distance = FloatToInt(GetEntityDistance(client, entity));
		if(distance <= 80) {
			if(GetUserAdmin(client) != INVALID_ADMIN_ID) {
				AcceptEntityInput(entity, "Open");
			}
		}
	}
}

public void Use_ProcessPlayerFunc(int client) {
	int player = GetClientAimTarget(client, true);
	if(player == -1 || player == -2) return;

	//TODO: Add check to see if bot
	if(IsClientConnected(player) && IsClientInGame(player)) {
		Menu_OpenPlayer(client);
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

//Used to check if player
public Action Timer_CheckDoorHud(Handle timer, any client) {
	int entity = GetClientAimTarget(client, false);
	if(entity == -1 || entity == -2) return Plugin_Continue;
	if(!IsValidEntity(entity)) return Plugin_Continue;

	char entClassname[32];
	bool result = GetEntityClassname(entity, entClassname, sizeof(entClassname));
	if(!result) return Plugin_Continue;
	if(StrEqual(entClassname, "func_door_rotating", false) || StrEqual(entClassname, "func_door", false)) {
		int distance = FloatToInt(GetEntityDistance(client, entity));
		if(distance <= 100) {
			char buffer[255];
			Format(buffer, sizeof(buffer), "Property for sale: $10,000");
			SetHudTextParams(-1.0, -1.0, 1.0, 0, 255, 0, 255, 0, 0.0, 0.0, 0.0);
			ShowHudText(client, -1, buffer);
		}
	}
	return Plugin_Continue;
}

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
	SQL_Save(client);
	return Plugin_Continue;
}

public Action Timer_ProcessHud(Handle timer, any client) {
	if(IsClientInGame(client)) {
		char hudText[512], goodGrammar[32], copString[32];

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

		Format(hudText, sizeof(hudText), "Wallet: $%s\nBank: $%s\nDebt: $%s\nSalary: $%s\nNext Pay: %i %s\nKills: %s\nLevel: %i\nXP: %d/100\nIsCop: %s", 
			reWallet, reBank, reDebt, reSalary, PlySalaryCount[client], goodGrammar, reKills, PlyLevel[client], PlyXP[client], isCop);
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

public Action Command_SetPlayerCop(int client, int args) {
	char arg1[32], playerName[32];
	GetCmdArg(1, arg1, sizeof(arg1));

	int target = FindTarget(client, arg1, true, false);
	if (target == -1) { PrintToClientEx(client, "Could not find player."); return Plugin_Handled; }

	PlyIsCop[target] = 1;
	GetClientName(target, playerName, sizeof(playerName));
	PrintToClientEx(client, "Gave %s cop.", playerName);
	SQL_Save(target);
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
		int clientIndex = CreateFakeClient(name);
		PrintToClientEx(client, "Create client %s with index %i", name, clientIndex);
	}
	else {
		PrintToClientEx(client, "Command only takes 1 argument (name)");
	}
	return Plugin_Handled;
}

//===MENUS







//DATABASE
//Inserts a new entry into the database
static void SQL_InsertNew(int client) {
	char query[250], playerAuth[32];
	GetClientAuthId(client, AuthId_Steam3, playerAuth, sizeof(playerAuth));
	Format(query, sizeof(query), "INSERT INTO %s ('ID') VALUES ('%s')", PlayerTableName, playerAuth);
	SQL_TQuery(RPDMDatabase, SQL_InsertCallback, query, client);
}

//Load player call
static void SQL_Load(int client) {
	char query[200];
	Format(query, sizeof(query), "SELECT * FROM `%s` WHERE `ID` = '%s'", PlayerTableName, PlySteamAuth[client]);
	SQL_TQuery(RPDMDatabase, SQL_LoadCallback, query, client);
}

static void SQL_Save(int clientIndex) {
	char query[200];
	int client = GetClientUserId(clientIndex);
	Format(query, sizeof(query), "UPDATE %s SET Wallet = '%i', Bank = '%i', Salary = '%i', Debt = '%i', Kills = '%i', Level = '%i', IsCop = '%i', XP = '%d' WHERE ID = '%s'", PlayerTableName, PlyWallet[client], PlyBank[client], PlySalary[client], PlyDebt[client], PlyKills[client], PlyLevel[client], PlyIsCop[client], PlyXP[client], PlySteamAuth[client]);
	SQL_TQuery(RPDMDatabase, SQL_SaveCallback, query, clientIndex);
	PrintToServer("Profile %s saved.", PlySteamAuth[client]);
}

//Inital database call
static void SQL_Initialise() {
	char error[200];
	RPDMDatabase = SQLite_UseDatabase(DatabaseName, error, sizeof(error));
	if(RPDMDatabase == null) {
		PrintToServer("[RPDM] Error at SQL_Initialise: %s", error);
		LogError("[RPDM] Error at SQL_Initialise: %s", error);
	}
	else {
		SQL_CreateDatabase();
	}
}

//Creates or loads database
static Action SQL_CreateDatabase() {
	char query[600];
	Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS '%s' ('ID' VARCHAR(32), Wallet INT(9) NOT NULL DEFAULT 0,Bank INT(9) NOT NULL DEFAULT 100,Salary INT(9) NOT NULL DEFAULT 1,Debt INT(9) NOT NULL DEFAULT 0,Kills INT(9) NOT NULL DEFAULT 0,Level INT(9) NOT NULL DEFAULT 1, IsCop INT(9) NOT NULL DEFAULT 0, XP DECIMAL(10,5) NOT NULL DEFAULT 0)", PlayerTableName);
	SQL_TQuery(RPDMDatabase, SQL_CreateCallback, query);
	return Plugin_Handled;
}

//Load callback function
static void SQL_LoadCallback(Handle owner, Handle hndl, const char[] error, any data) {
	if(hndl != null) {
		if(!SQL_GetRowCount(hndl)) {
			SQL_InsertNew(data);
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

			//Timers
			PlySalaryTimer[data] = CreateTimer(1.0, Timer_CalculateSalary, data, TIMER_REPEAT);
			PlyHudTimer[data] = CreateTimer(1.0, Timer_ProcessHud, data, TIMER_REPEAT);
			PlyCheckDoor[data] = CreateTimer(1.0, Timer_CheckDoorHud, data, TIMER_REPEAT);
			PrintToServer("[RPDM] Profile loaded successfully: %s", PlySteamAuth[data]);
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
		char playerName[32];
		GetClientName(data, playerName, sizeof(playerName));
		SQL_Load(data);
		PrintToServer("[RPDM] Inserted new player: %s", playerName);
	}
	else {
		PrintToServer("[RPDM] Error at SQL_InsertCallback: %s", error);
		LogError("[RPDM] Error at SQL_InsertCallback: %s", error);
	}
}

//Save callback function
static void SQL_SaveCallback(Handle owner, Handle hndl, const char[] error, any data) {
	if(hndl == null) {
		PrintToServer("[RPDM] Error at SQL_SaveCallback: %s", error);
		LogError("[RPDM] Error at SQL_SaveCallback: %s", error);
	}
}

//Create callback function
static void SQL_CreateCallback(Handle owner, Handle hndl, const char[] error, any data) {
	if(hndl != null) {
		PrintToServer("[RPDM] Successfully loaded / created database.");
		LogError("[RPDM] Successfully loaded / created database.");
	}
	else {
		PrintToServer("[RPDM] Error at SQL_CreateCallback: %s", error);
		LogError("[RPDM] Error at SQL_CreateCallback: %s", error);
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

public int FloatToInt(float value) {
	char strVal[10];
	FloatToString(value, strVal, sizeof(strVal));
	return StringToInt(strVal);
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

public void StripWeapons(int client) {
	for(int i = 0; i <= 32; i++)  {
		int result = GetPlayerWeaponSlot(client, i);
		if(result != -1) {
			RemovePlayerItem(client, result);
		}
	}
}

public void GiveCopOutfit(int client) {


}

public void GivePlayerOutfit(int client) {


}

public float GetEntityDistance(int client, int entity) {
	float playerPos[3], entityPos[3], retVal;
	GetClientAbsOrigin(client, playerPos);
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", entityPos);
	retVal = GetVectorDistance(playerPos, entityPos, false);
	return retVal;
}