#pragma semicolon 1

#include <csgo_colors>

#pragma newdecls required

#include <sdkhooks>
#include <sdktools>

#define TASER			"weapon_tracers_taser"

#define SOUND_IMPACT	"weapons/taser/taser_hit.wav"
#define SOUND_SHOOT		"weapons/taser/taser_shoot.wav"

KeyValues
	g_hKeyValues;
bool
	g_bSelectTraccers[MAXPLAYERS+1],
	g_bEnable[MAXPLAYERS+1],
	g_bAccess[MAXPLAYERS+1],
	g_bIsLighting[MAXPLAYERS+1];
int g_iColor[MAXPLAYERS+1][4],
	g_iBeamSprite;
float
	g_fLife,
	g_fStartWidth,
	g_fEndWidth,
	g_fAmplitude,
	g_fLastAngles[MAXPLAYERS + 1][3];
char
	g_szPath[PLATFORM_MAX_PATH];

public Plugin myinfo =
{
	name		= "Traccers",
	author		= "TheZipa",
	description	= "Bullet traccers from AWP and Desert Eagle",
	version		= "1.0",
	url			= "vk.com/surfserver24go"
}

public void OnPluginStart()
{
	HookEvent("bullet_impact", Event_BulletImpact);
	AddTempEntHook("Shotgun Shot", Hook_BulletShot);

	RegConsoleCmd("sm_traccers", Cmd_Traccers, "Traccers Settings");
	RegConsoleCmd("sm_traccers_term", Cmd_Traccers_Term, "Display traccers term");
	RegAdminCmd("sm_give_traccers", Cmd_GiveTraccers, ADMFLAG_ROOT, "Giving traccers for player");

	BuildPath(Path_SM, g_szPath, sizeof(g_szPath), "configs/traccers.ini");

	g_hKeyValues = new KeyValues("Traccers");
	if(!FileExists(g_szPath))
		g_hKeyValues.ExportToFile(g_szPath);
	else g_hKeyValues.ImportFromFile(g_szPath);

	g_fLife			= 0.3;
	g_fStartWidth	= 4.0;
	g_fEndWidth		= 4.0;

	LoadTranslations("traccers.phrases");
	LoadTranslations("common.phrases");
}

public void OnConfigsExecuted()
{
	for(int i = 1; i <= MaxClients; i++) if(IsClientInGame(i))
	{
		OnClientPostAdminCheck(i);
		if(!IsPlayerAlive(i)) Hook_WeaponSwitch(i, GetEntPropEnt(i, Prop_Send, "m_hActiveWeapon"));
	}
}

public void OnMapStart()
{
	g_iBeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt");

	bool save = LockStringTables(false);
	AddToStringTable(FindStringTable("EffectDispatch"), "ParticleEffect");
	LockStringTables(save);

	save = LockStringTables(false);
	AddToStringTable(FindStringTable("ParticleEffectNames"), TASER);
	LockStringTables(save);

	PrecacheSound(SOUND_IMPACT);
	PrecacheSound(SOUND_SHOOT);

	CreateTimer(600.0, UpdateTraccersTime, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientPostAdminCheck(int iClient)
{
	char szClientID[32];
	GetClientAuthId(iClient, AuthId_Steam2, szClientID, sizeof(szClientID));

	g_hKeyValues.Rewind();
	if(g_hKeyValues.JumpToKey(szClientID, false))
	{
		g_bAccess[iClient] = true;
		g_bEnable[iClient] = view_as<bool>(g_hKeyValues.GetNum("enable", 1));
		g_bIsLighting[iClient] = view_as<bool>(g_hKeyValues.GetNum("isLighting", 0));
		g_hKeyValues.GetColor4("color", g_iColor[iClient]);
	}

	SDKHook(iClient, SDKHook_WeaponCanSwitchTo, Hook_WeaponSwitch);
}

public void OnClientDisconnect(int iClient)
{
	g_bSelectTraccers[iClient] = g_bAccess[iClient] = g_bEnable[iClient] = false;
}

public Action UpdateTraccersTime(Handle timer)
{
	g_hKeyValues.Rewind();

	ArrayList hDeletePlayersList = new ArrayList(ByteCountToCells(32));

	if(g_hKeyValues.GotoFirstSubKey())
	{
		char szKeyName[32];
		int iPlayerTime;
		bool bDelete;

		do
		{
			iPlayerTime = g_hKeyValues.GetNum("time");
			if(iPlayerTime != -1 && GetTime() >= iPlayerTime)
			{
				g_hKeyValues.GetSectionName(szKeyName, sizeof(szKeyName));
				// DEBUG
				PrintToServer("[Traccers] Deleting Key: %s", szKeyName);
				hDeletePlayersList.PushString(szKeyName);
				bDelete = true;
			}
		} while(g_hKeyValues.GotoNextKey());

		if(bDelete)
		{
			for(int i; i < hDeletePlayersList.Length; i++)
			{
				hDeletePlayersList.GetString(i, szKeyName, sizeof(szKeyName));
				g_hKeyValues.Rewind();

				if(g_hKeyValues.JumpToKey(szKeyName, false)) g_hKeyValues.DeleteThis();
			}

			g_hKeyValues.Rewind();
			g_hKeyValues.ExportToFile(g_szPath);
		}
	}

	CloseHandle(hDeletePlayersList);

	return Plugin_Continue;
}

public Action Cmd_Traccers(int iClient, int args)
{
	if(!iClient || !IsClientInGame(iClient))
		return Plugin_Handled;

	if(!g_bAccess[iClient])
	{
		CGOPrintToChat(iClient, "%t", "No Access");
		return Plugin_Handled;
	}

	DisplayTraccersMenu(iClient);

	return Plugin_Handled;
}

public Action Cmd_Traccers_Term(int iClient, int args)
{
	if(!iClient || !IsClientInGame(iClient))
		return Plugin_Handled;
	
	if(!g_bAccess[iClient])
	{
		CGOPrintToChat(iClient, "%t", "No Access");
		return Plugin_Handled;
	}
	
	PrintTraccersTerm(iClient);
	
	return Plugin_Handled;
}

public Action Cmd_GiveTraccers(int iClient, int args)
{
	if(args < 2)
	{
		ReplyToCommand(iClient, "%t", "Traccers Usage");
		return Plugin_Handled;
	}

	char szTargetName[MAX_TARGET_LENGTH], szBuffer[128];
	int iTargetList[MAXPLAYERS], iTargetCount;
	bool tn_is_ml;

	GetCmdArg(1, szBuffer, sizeof(szBuffer));
	if((iTargetCount = ProcessTargetString(szBuffer, iClient, iTargetList, MAXPLAYERS, COMMAND_FILTER_CONNECTED, szTargetName, sizeof(szTargetName), tn_is_ml)) <= 0)
	{
		ReplyToTargetError(iClient, iTargetCount);
		return Plugin_Handled;
	}

	GetCmdArg(2, szBuffer, sizeof(szBuffer));
	int iMonths = StringToInt(szBuffer);
	if(iMonths < 1 || iMonths > 12)
	{
		ReplyToCommand(iClient, "%t", "Traccers Usage");
		return Plugin_Handled;
	}

	for(int i; i < iTargetCount; i++) if(IsClientInGame(iTargetList[i])) GiveTraccers(iTargetList[i], iClient, iMonths);

	LogMessage("%t", "Log Receive Traccers", iClient, szTargetName, iMonths);

	return Plugin_Handled;
}

stock void GiveTraccers(int iClient, int iAdmin, const int iMonths)
{
	if(IsClientInGame(iClient))
	{
		char szClientID[32], szColor[32];
		GetClientAuthId(iClient, AuthId_Steam2, szClientID, sizeof(szClientID));

		g_hKeyValues.Rewind();
		if(g_hKeyValues.JumpToKey(szClientID, false))
		{
			ReplyToCommand(iAdmin, "%t", "Already Have Traccers", iClient);
			return;
		}

		g_hKeyValues.Rewind();
		if(g_hKeyValues.JumpToKey(szClientID, true))
		{
			g_hKeyValues.SetNum("enable", 1);
			g_hKeyValues.SetNum("isLighting", 0);
			FormatEx(szColor, sizeof(szColor), "%i %i %i %i", 0, 255, 0, 225);
			g_hKeyValues.SetString("color", szColor);

			if(iMonths == -1)
				g_hKeyValues.SetNum("time", iMonths);
			else
				g_hKeyValues.SetNum("time", GetTime() + (iMonths * 2592000));

			g_bAccess[iClient] = g_bEnable[iClient] = true;
			SetHexColor(iClient, 0x00ff00);
		}

		g_hKeyValues.Rewind();
		g_hKeyValues.ExportToFile(g_szPath);

		CGOPrintToChat(iClient, "%t", "Receive Traccers");
	}
}

stock void DisplayTraccersMenu(int iClient)
{
	if(IsClientInGame(iClient))
	{
		char buffer[32];
		Menu menu = new Menu(TraccersMenu_Handler);
		menu.SetTitle("%t", "Traccers");

		FormatEx(buffer, sizeof(buffer), "%T", g_bEnable[iClient] ? "Disable" : "Enable", iClient);
		menu.AddItem("", buffer);
		FormatEx(buffer, sizeof(buffer), "%T", "Select Color", iClient);
		menu.AddItem("", buffer);
		FormatEx(buffer, sizeof(buffer), "%T", "Term", iClient);
		menu.AddItem("", buffer);

		menu.ExitButton = true;
		menu.Display(iClient, MENU_TIME_FOREVER);
	}
}

public int TraccersMenu_Handler(Menu hMenu, MenuAction action, int iClient, int iItem)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			switch(iItem)
			{
				case 0:	// mode
				{
					g_bEnable[iClient] = !g_bEnable[iClient];
					UpdatePlayerData(iClient);
					DisplayTraccersMenu(iClient);
				}
				case 1:	// color
					DisplaySelectColorMenu(iClient);
				case 2:	// term
				{
					PrintTraccersTerm(iClient);
					DisplayTraccersMenu(iClient);
				}
			}
		}
		case MenuAction_End:
			delete hMenu;
	}
}

stock void PrintTraccersTerm(int iClient)
{
	if(IsClientInGame(iClient))
	{
		char szClientID[32];
		GetClientAuthId(iClient, AuthId_Steam2, szClientID, sizeof(szClientID));

		g_hKeyValues.Rewind();
		if(g_hKeyValues.JumpToKey(szClientID, false))
		{
			int iTotalTime = g_hKeyValues.GetNum("time");
			if(iTotalTime == -1)
				CGOPrintToChat(iClient, "%t", "Traccers Permanent");
			else
				CGOPrintToChat(iClient, "%t", "Traccers Term", ((iTotalTime - GetTime()) / 86400) + 1);
		}
	}
}

stock void DisplaySelectColorMenu(int iClient)
{
	if(IsClientInGame(iClient))
	{
		Menu menu = new Menu(SelectColorMenu_Handler);
		menu.SetTitle("%t", "Color");

		char buffer[32];
		if(GetUserFlagBits(iClient) & (ADMFLAG_GENERIC | ADMFLAG_ROOT))
		{
			FormatEx(buffer, sizeof(buffer), "%T", "Lighting", iClient);
			menu.AddItem("", buffer);
		}
		FormatEx(buffer, sizeof(buffer), "%T", "Red", iClient);
		menu.AddItem("", buffer);
		FormatEx(buffer, sizeof(buffer), "%T", "Green", iClient);
		menu.AddItem("", buffer);
		FormatEx(buffer, sizeof(buffer), "%T", "Blue", iClient);
		menu.AddItem("", buffer);
		FormatEx(buffer, sizeof(buffer), "%T", "Yellow", iClient);
		menu.AddItem("", buffer);
		FormatEx(buffer, sizeof(buffer), "%T", "Pink", iClient);
		menu.AddItem("", buffer);
		FormatEx(buffer, sizeof(buffer), "%T", "White", iClient);
		menu.AddItem("", buffer);

		menu.ExitBackButton = true;
		menu.ExitButton = true;
		menu.Display(iClient, MENU_TIME_FOREVER);
	}
}

public int SelectColorMenu_Handler(Menu hMenu, MenuAction action, int iClient, int iItem)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			int pos = iItem + view_as<int>((GetMenuItemCount(hMenu) == 6));
			switch(pos)
			{
				case 0:	g_bIsLighting[iClient] = true;	// lighting
				case 1:	SetHexColor(iClient, 0xff0000);	// red
				case 2:	SetHexColor(iClient, 0x00ff00);	// green
				case 3:	SetHexColor(iClient, 0x0000ff);	// blue
				case 4:	SetHexColor(iClient, 0xffff00);	// yellow
				case 5:	SetHexColor(iClient, 0xff00ff);	// pink
				case 6:	SetHexColor(iClient);				// white
			}

			UpdatePlayerData(iClient);
			DisplayTraccersMenu(iClient);
		}
		case MenuAction_Cancel:
			if(iItem == MenuCancel_ExitBack) DisplayTraccersMenu(iClient);
		case MenuAction_End:
			delete hMenu;
	}
}

stock void SetHexColor(int iClient, const int color = 0xffffff)
{
	g_bIsLighting[iClient] = false;

	g_iColor[iClient][0] = (color & 0xff0000) >> 16;
	g_iColor[iClient][1] = (color & 0x00ff00) >> 8;
	g_iColor[iClient][2] =  color & 0x0000ff;
	g_iColor[iClient][3] = 0xFF;
}

stock void UpdatePlayerData(int iClient)
{
	char szClientID[32], szColor[32];
	GetClientAuthId(iClient, AuthId_Steam2, szClientID, sizeof(szClientID));

	g_hKeyValues.Rewind();
	if(g_hKeyValues.JumpToKey(szClientID, false))
	{
		g_hKeyValues.SetNum("enable", view_as<int>(g_bEnable[iClient]));
		g_hKeyValues.SetNum("isLighting", view_as<int>(g_bIsLighting[iClient]));
		FormatEx(szColor, sizeof(szColor), "%i %i %i %i", g_iColor[iClient][0], g_iColor[iClient][1], g_iColor[iClient][2], g_iColor[iClient][3]);
		g_hKeyValues.SetString("color", szColor);
	}

	g_hKeyValues.Rewind();
	g_hKeyValues.ExportToFile(g_szPath);
}

public void Hook_WeaponSwitch(int iClient, int iWeapon)
{
	if(iWeapon == -1)
		return;

	char wpn[16];
	GetEntityClassname(iWeapon, wpn, sizeof(wpn));
	g_bSelectTraccers[iClient] = !strcmp(wpn[7], "awp") || !strcmp(wpn[7], "deagle");
}

public void Event_BulletImpact(Event hEvent, const char[] sEvName, bool dontBroadcast)
{
	int iClient = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	if(!iClient || !g_bSelectTraccers[iClient] || !g_bEnable[iClient] || !g_bAccess[iClient])
		return;

	float fEndPos[3];
	fEndPos[0] = GetEventFloat(hEvent, "x");
	fEndPos[1] = GetEventFloat(hEvent, "y");
	fEndPos[2] = GetEventFloat(hEvent, "z");

	int clients[MAXPLAYERS], num;
	for(int i = 1; i <= MaxClients; i++)
		if(i != iClient && IsClientInGame(i) && (!IsFakeClient(i) || IsClientReplay(i) || IsClientSourceTV(i)))
			clients[num++] = i;

	float fMuzzlePos[3], fCameraPos[3];
	if(num) GetWeaponAttachmentPosition(iClient, "muzzle_flash", fMuzzlePos);
	GetWeaponAttachmentPosition(iClient, "camera_buymenu", fCameraPos);

	if(g_bIsLighting[iClient])
	{
		if(num)
		{
			TE_DispatchEffect(TASER, fMuzzlePos, fEndPos, g_fLastAngles[iClient]);
			TE_Send(clients, num);
		}

		clients[0] = iClient;
		TE_DispatchEffect(TASER, fCameraPos, fEndPos, g_fLastAngles[iClient]);
		TE_Send(clients, 1);
	}
	else
	{
		if(num)
		{
			TE_SetupBeamPoints(fMuzzlePos, fEndPos, g_iBeamSprite, 0, 0, 0, g_fLife, g_fStartWidth, g_fEndWidth, 1, g_fAmplitude, g_iColor[iClient], 0);
			TE_Send(clients, num);
		}

		clients[0] = iClient;
		TE_SetupBeamPoints(fCameraPos, fEndPos, g_iBeamSprite, 0, 0, 0, g_fLife, g_fStartWidth, g_fEndWidth, 1, g_fAmplitude, g_iColor[iClient], 0);
		TE_Send(clients, 1);
	}
}

stock void GetWeaponAttachmentPosition(int client, const char[] attachment, float pos[3])
{
	if(!attachment[0])
		return;

	int weapon;
	if((weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon")) == -1
	|| (weapon = GetEntPropEnt(weapon, Prop_Send, "m_hWeaponWorldModel")) == -1)
		return;

	int entity = CreateEntityByName("info_target");
	DispatchSpawn(entity);

	SetVariantString("!activator");
	AcceptEntityInput(entity, "SetParent", weapon, entity, 0);

	SetVariantString(attachment); 
	AcceptEntityInput(entity, "SetParentAttachment", weapon, entity, 0);

	TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, NULL_VECTOR);
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", pos);
	AcceptEntityInput(entity, "kill");
}

public Action Hook_BulletShot(const char[] te_name, const int[] Players, int numClients, float delay)
{
	int iClient = TE_ReadNum("m_iPlayer") + 1;
	if(!g_bAccess[iClient] || !g_bSelectTraccers[iClient] || !g_bEnable[iClient] || !g_bIsLighting[iClient])
		return Plugin_Continue;

	float fOrigin[3];
	TE_ReadVector("m_vecOrigin", fOrigin);
	g_fLastAngles[iClient][0] = TE_ReadFloat("m_vecAngles[0]");
	g_fLastAngles[iClient][1] = TE_ReadFloat("m_vecAngles[1]");
	g_fLastAngles[iClient][2] = 0.0;

	float fImpactPos[3];
	Handle trace = TR_TraceRayFilterEx(fOrigin, g_fLastAngles[iClient], MASK_SHOT, RayType_Infinite, TR_DontHitSelf, iClient);
	if(TR_DidHit(trace)) TR_GetEndPosition(fImpactPos, trace);
	delete trace;
	//Play the taser sounds
	EmitAmbientSound(SOUND_IMPACT, fImpactPos, _, _, _, 0.5, SNDPITCH_LOW);
	EmitAmbientSound(SOUND_SHOOT, fOrigin, _, _, _, 0.3, SNDPITCH_LOW);
	return Plugin_Continue;
}

public bool TR_DontHitSelf(int entity, int mask, any data)
{
	return entity != data;
}

stock void TE_DispatchEffect(const char[] particle, const float pos[3], const float endpos[3], const float angles[3] = NULL_VECTOR)
{
	TE_Start("EffectDispatch");
	TE_WriteFloatArray("m_vStart.x", pos, 3);
	TE_WriteFloatArray("m_vOrigin.x", endpos, 3);
	TE_WriteVector("m_vAngles", angles);
	TE_WriteNum("m_nHitBox", GetParticleEffectIndex(particle));
	TE_WriteNum("m_iEffectName", GetEffectIndex("ParticleEffect"));
}

int GetParticleEffectIndex(const char[] sEffectName)
{
	static int table = INVALID_STRING_TABLE;
	if(table == INVALID_STRING_TABLE) table = FindStringTable("ParticleEffectNames");

	int iIndex = FindStringIndex(table, sEffectName);
	if(iIndex != INVALID_STRING_INDEX)
		return iIndex;

	return 0;
}

int GetEffectIndex(const char[] sEffectName)
{
	static int table = INVALID_STRING_TABLE;
	if(table == INVALID_STRING_TABLE) table = FindStringTable("EffectDispatch");

	int iIndex = FindStringIndex(table, sEffectName);
	if(iIndex != INVALID_STRING_INDEX)
		return iIndex;

	return 0;
}