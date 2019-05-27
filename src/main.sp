#include <sourcemod>
#include <sdktools>
#include <morecolors>

#pragma semicolon 1
#pragma newdecls required

char Prefix[32] = "{red}[Server]{default}";
char OwnerPrefix[32] = "{darkred}Owner{default} | ";
char PlayerPrefix[32] = "Player | ";

public Plugin myinfo = {
	name        = "HL2DM Mod",
	author      = "SirTiggs",
	description = "Donno",
	version     = "1.0.0",
	url         = ""
};

public void OnPluginStart() {
	RegAdminCmd("sm_test", CmdTest, ADMFLAG_ROOT, "Command used for testing");
	RegAdminCmd("sm_reload", CmdReloadServer, ADMFLAG_ROOT, "Reloads server on current map.");
	RegAdminCmd("sm_place", CmdPlaceObject, ADMFLAG_ROOT, "Place an object");
	RegAdminCmd("sm_createfake", CmdCreateFake, ADMFLAG_ROOT, "Creates a fake client.");
	RegAdminCmd("sm_createnpc", CmdCreateNpc, ADMFLAG_ROOT, "Creates an npc.");

	HookEvent("player_connect", EventPlayerConnect, EventHookMode_Pre);
	HookEvent("player_disconnect", EventPlayerDisconnect, EventHookMode_Pre);
	HookEvent("client_beginconnect", EventPlayerBeginConnect, EventHookMode_Pre);

	AddCommandListener(EventListenSay, "say");

	PrintToServer("HL2DM Mod - v1.0.0 loaded.");
}

public void OnMapStart() {
	PrecacheModel("models/barney.mdl", true);
	PrecacheModel("models/props_c17/FurnitureArmchair001a.mdl", true);
	PrecacheSound("Friends/friend_join.wav", true);
}

public void OnClientConnected(int client) {
	char playerName[32];
	GetClientName(client, playerName, sizeof(playerName));
	CPrintToChatAll("%s Player {green}%s{default} has joined.", Prefix, playerName);
}

public Action EventPlayerConnect(Event event, const char[] name, bool dontBroadcast) {
	char playerName[32];
	char address[32];

	event.GetString("address", address, sizeof(address));
	event.GetString("name", playerName, sizeof(playerName));

	CPrintToChatAll("%s {green}%s(%d){default} has connected!", Prefix, playerName, address);
	return Plugin_Handled;
}

public Action EventPlayerBeginConnect(Event event, const char[] name, bool dontBroadcast) {
	char playerName[32];
	char source[32];
	float ip[32];

	ip[0] = event.GetFloat("ip");

	event.GetString("address", playerName, sizeof(playerName));
	event.GetString("source", source, sizeof(source));

	CPrintToChatAll("%s {green}%s(%d){default} is joining from: {red}%s{default}", Prefix, playerName, ip[0], source);
	return Plugin_Handled;
}

public Action EventListenSay(int client, const char[] command, int argc) {
	char buffer[256];
	char prefix[32];
	char playerName[32];
	char authID[32];

	GetCmdArg(1, buffer, sizeof(buffer));
	GetClientName(client, playerName, sizeof(playerName));
	GetClientAuthId(client, AuthId_Steam3, authID, sizeof(authID));

	if(buffer[0] == '/') return Plugin_Handled;

	for(int i = 1; i <= GetMaxClients(); i++){
		if(IsClientConnected(i) && IsClientInGame(i)){
			ClientCommand(i, "play %s", "Friends/friend_join.wav");
		}
	}

	if(IsClientAuthorized(client)) {
		prefix = OwnerPrefix;
	}
	else {
		prefix = PlayerPrefix;
	}

	CPrintToChatAll("%s{green}%s{default}: %s", prefix, playerName, buffer);
	return Plugin_Handled;
}

public Action EventPlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	char playerName[32];
	char playerID[32];
	char reason[32];

	event.GetString("reason", reason, sizeof(reason));
	event.GetString("networkid", playerID, sizeof(playerID));
	GetClientName(event.GetInt("userid"), playerName, sizeof(playerName));

	CPrintToChatAll("%s {olive}%s(%s){default} has disconnected. (reason: %s)", Prefix, playerName, playerID, reason);
	return Plugin_Handled;
}

public Action CmdTest(int client, int args) {
	CPrintToChatAll("%s test", Prefix);
}

public Action CmdReloadServer(int client, int args) {
	char mapName[32];
	GetCurrentMap(mapName, sizeof(mapName));
	ForceChangeLevel(mapName, "CmdReloadServer executed.");
	return Plugin_Handled;
}

public Action CmdPlaceObject(int client, int args) {
	float playerVec[3];
	float playerAng[3];

	GetClientAbsOrigin(client, playerVec);
	GetClientAbsAngles(client, playerAng);

	int entity = CreateEntityByName("prop_physics_override");
	DispatchKeyValue(entity, "model", "models/props_c17/FurnitureArmchair001a.mdl");
	DispatchSpawn(entity);
	TeleportEntity(entity, playerVec, playerAng, NULL_VECTOR);
	SetEntityMoveType(entity, MOVETYPE_VPHYSICS);

	CPrintToChat(client, "%s Placed a box.", Prefix);

	return Plugin_Handled;
}

public Action CmdCreateFake(int client, int args) {
	int newClient = CreateFakeClient("John");
	CPrintToChat(client, "%s Created client %d", Prefix, newClient);

	return Plugin_Handled;
}

public Action CmdCreateNpc(int client, int args) {
	float playerVec[3];
	float playerAng[3];

	GetClientAbsOrigin(client, playerVec);
	GetClientAbsAngles(client, playerAng);

	int entity = CreateEntityByName("prop_dynamic");
	DispatchKeyValue(entity, "model", "models/player/barney.mdl");
	DispatchSpawn(entity);
	TeleportEntity(entity, playerVec, playerAng, NULL_VECTOR);
	SetEntityMoveType(entity, MOVETYPE_VPHYSICS);

	return Plugin_Handled;
}