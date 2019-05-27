#include <sourcemod>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
	name        = "HL2DM Mod",
	author      = "SirTiggs",
	description = "",
	version     = "1.0.0",
	url         = ""
};

public void OnPluginStart()
{
	PrintToServer("Hello, World!");
}
