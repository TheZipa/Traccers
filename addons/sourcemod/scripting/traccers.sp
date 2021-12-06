#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <csgo_colors>

#pragma semicolon 1
#pragma newdecls required

#define TASER "weapon_tracers_taser"
#define GLOW "weapon_taser_glow_impact"
#define SOUND_IMPACT "weapons/taser/taser_hit.wav"
#define SOUND_SHOOT "weapons/taser/taser_shoot.wav"

bool g_bSelectTraccers[MAXPLAYERS+1];
bool g_bEnable[MAXPLAYERS+1];
bool g_bAccess[MAXPLAYERS+1];
bool g_bIsLighting[MAXPLAYERS+1];

int g_iColor[MAXPLAYERS+1][4];
int g_iBeamSprite;

float g_fLife,
	g_fStartWidth,
	g_fEndWidth,
	g_fAmplitude;
float g_fLastAngles[MAXPLAYERS + 1][3];

char g_szPath[PLATFORM_MAX_PATH];
KeyValues g_hKeyValues;
Handle g_hTimer;

public Plugin myinfo = 
{
	name = "Traccers",
	author = "TheZipa",
	description = "Bullet traccers from AWP and Desert Eagle",
	version = "1.0",
	url = "vk.com/surfserver24go"
}

public void OnPluginStart()
{
	HookEvent("bullet_impact",	Event_BulletImpact);
	AddTempEntHook("Shotgun Shot", Hook_BulletShot);
	
	RegConsoleCmd("sm_traccers", Cmd_Traccers, "Traccers Settings");
	RegAdminCmd("sm_give_traccers", Cmd_GiveTraccers, ADMFLAG_ROOT, "Giving traccers for player");
	
	BuildPath(Path_SM, g_szPath, sizeof(g_szPath), "configs/traccers.ini");
	
	g_hKeyValues = new KeyValues("Traccers");
	
	if(FileExists(g_szPath) == false)
		g_hKeyValues.ExportToFile(g_szPath);
	else
		g_hKeyValues.ImportFromFile(g_szPath);
		
	g_hTimer = CreateTimer(600.0, UpdateTraccersTime, _, TIMER_REPEAT);
	
	g_fLife = 0.3;
	g_fStartWidth = 4.0;
	g_fEndWidth = 4.0;
	g_fAmplitude = 0.0;
	
	LoadTranslations("traccers.phrases");
	LoadTranslations("common.phrases");
}

public void OnConfigsExecuted()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
			
		OnClientPostAdminCheck(i);
		
		if (!IsPlayerAlive(i))
			continue;
			
		int weapon = GetEntPropEnt(i, Prop_Send, "m_hActiveWeapon");
		Hook_WeaponSwitch(i, weapon);
	}
}

public void OnPluginEnd()
{
	CloseHandle(g_hKeyValues);
	CloseHandle(g_hTimer);
}

public void OnMapStart()
{
	g_iBeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt");
	PrecacheEffect("ParticleEffect");
	PrecacheParticleEffect(TASER);
	PrecacheParticleEffect(GLOW);
	PrecacheSound(SOUND_IMPACT);
	PrecacheSound(SOUND_SHOOT);
}

public void OnClientPostAdminCheck(int iClient)
{
	LoadPlayerData(iClient);

	SDKHook(iClient, SDKHook_WeaponCanSwitchTo, Hook_WeaponSwitch);
}

public void OnClientDisconnect(int iClient)
{
	g_bSelectTraccers[iClient] = false;
	g_bAccess[iClient] = false;
	g_bEnable[iClient] = false;
}

public Action UpdateTraccersTime(Handle timer)
{
	ArrayList hDeletePlayersList = new ArrayList(ByteCountToCells(32));
	
	g_hKeyValues.Rewind();
	
	if(g_hKeyValues.GotoFirstSubKey()) 
	{
		char szKeyName[32];
		int iPlayerTime = 0;
		bool bDelete = false;
		
		do
		{
			iPlayerTime = g_hKeyValues.GetNum("time");
			
			if(iPlayerTime == -1)
				continue;
			
			if(GetTime() >= iPlayerTime)
			{
				g_hKeyValues.GetSectionName(szKeyName, sizeof(szKeyName));
				// DEBUG
				PrintToServer("[Traccers] Deleting Key: %s", szKeyName);
				hDeletePlayersList.PushString(szKeyName);
				bDelete = true;
			}
		}while(g_hKeyValues.GotoNextKey());
		
		if(bDelete == true)
		{
			for(int i = 0; i < hDeletePlayersList.Length; i++)
			{
				hDeletePlayersList.GetString(i, szKeyName, sizeof(szKeyName));
				g_hKeyValues.Rewind();
				
				if(g_hKeyValues.JumpToKey(szKeyName, false))
					g_hKeyValues.DeleteThis();
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
	if(!IsClientInGame(iClient))
		return Plugin_Handled;
	
	if(!g_bAccess[iClient])
	{
		CGOPrintToChat(iClient, "%t", "No Access");
		return Plugin_Handled;
	}
	
	DisplayTraccersMenu(iClient);
	
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
	
	if(iMonths < -1 || iMonths == 0 || iMonths > 12)
	{
		ReplyToCommand(iClient, "%t", "Traccers Usage");
		return Plugin_Handled;
	}
	
	for(int i = 0; i < iTargetCount; i++)
	{
		if(IsClientInGame(iTargetList[i]))
		{
			GiveTraccers(iTargetList[i], iClient, iMonths);
		}
	}
	
	LogMessage("%t", "Log Receive Traccers", iClient, szTargetName, iMonths);
	
	return Plugin_Handled;
}

public int TraccersMenu_Handler(Menu hMenu, MenuAction action, int iClient, int iItem)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			if(iItem == 0)
			{
				g_bEnable[iClient] = !g_bEnable[iClient];
				UpdatePlayerData(iClient);
				DisplayTraccersMenu(iClient);
			}
			else if(iItem == 1)
			{
				DisplaySelectColorMenu(iClient);
			}
			else
			{
				PrintTraccersTerm(iClient);
				DisplayTraccersMenu(iClient);
			}
		}
		case MenuAction_End:
		{
			delete hMenu;
		}
	}
}

public int SelectColorMenu_Handler(Menu hMenu, MenuAction action, int iClient, int iItem)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			char szItem[12];
			hMenu.GetItem(iItem, szItem, sizeof(szItem));
			
			if(StrEqual(szItem, "lighting"))
			{
				g_bIsLighting[iClient] = true;
			}else if(StrEqual(szItem, "red"))
			{
				SetColor(iClient, 255, 0, 0, 225);
			}else if(StrEqual(szItem, "green"))
			{
				SetColor(iClient, 0, 255, 0, 225);	
			}else if(StrEqual(szItem, "blue"))
			{
				SetColor(iClient, 0, 0, 255, 225);
			}else if(StrEqual(szItem, "yellow"))
			{
				SetColor(iClient, 255, 255, 0, 225);
			}else if(StrEqual(szItem, "pink"))
			{
				SetColor(iClient, 255, 0, 255, 225);
			}else if(StrEqual(szItem, "white"))
			{
				SetColor(iClient, 255, 255, 255, 225);
			}
			
			UpdatePlayerData(iClient);
			DisplayTraccersMenu(iClient);
		}
		case MenuAction_Cancel:
		{
			if(iItem == MenuCancel_ExitBack)
			{
				DisplayTraccersMenu(iClient);
			}
		}
		case MenuAction_End:
		{
			delete hMenu;
		}
	}
}

public void Hook_WeaponSwitch(int iClient, int iWeapon)
{
	if (iWeapon == -1)
		return;
		
	char szWeaponname[32];
	GetEntityClassname(iWeapon, szWeaponname, sizeof(szWeaponname));
	
	if(StrEqual(szWeaponname, "weapon_awp") || StrEqual(szWeaponname, "weapon_deagle"))
		g_bSelectTraccers[iClient] = true;
	else
		g_bSelectTraccers[iClient] = false;
}

public Action Event_BulletImpact(Handle hEvent, const char[] sEvName, bool dontBroadcast)
{
	int iClient = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	
	if(!g_bSelectTraccers[iClient] || !g_bEnable[iClient] || !g_bAccess[iClient])
		return Plugin_Continue;
		
	float fEndPos[3], fPercentage;
	
	fEndPos[0] = GetEventFloat(hEvent, "x");
	fEndPos[1] = GetEventFloat(hEvent, "y");
	fEndPos[2] = GetEventFloat(hEvent, "z");
	
	if(g_bIsLighting[iClient])
	{	
		float fMuzzlePos[3], fCameraPos[3];
		GetWeaponAttachmentPosition(iClient, "muzzle_flash", fMuzzlePos);
		GetWeaponAttachmentPosition(iClient, "camera_buymenu", fCameraPos);
		
		float fPovPos[3];
		fPovPos[0] = fMuzzlePos[0] - fCameraPos[0];
		fPovPos[1] = fMuzzlePos[1] - fCameraPos[1];
		fPovPos[2] = fMuzzlePos[2] - fCameraPos[2] + 0.1;
		ScaleVector(fPovPos, 0.4);
		SubtractVectors(fMuzzlePos, fPovPos, fPovPos);
		
		float fDistance = GetVectorDistance(fPovPos, fEndPos);
		fPercentage = 0.2 / (fDistance / 100);
		fPovPos[0] = fPovPos[0] + ((fEndPos[0] - fPovPos[0]) * fPercentage);
		fPovPos[1] = fPovPos[1] + ((fEndPos[1] - fPovPos[1]) * fPercentage);
		fPovPos[2] = fPovPos[2] + ((fEndPos[2] - fPovPos[2]) * fPercentage);
		
		TE_DispatchEffect(TASER, fMuzzlePos, fEndPos, g_fLastAngles[iClient]);
		
	}
	else
	{
		float fClientOrigin[3], fStartPos[3];
		GetClientEyePosition(iClient, fClientOrigin);
		
		fPercentage = 0.4/(GetVectorDistance(fClientOrigin, fEndPos)/100.0);
		
		fStartPos[0] = fClientOrigin[0] + ((fEndPos[0]-fClientOrigin[0]) * fPercentage); 
		fStartPos[1] = fClientOrigin[1] + ((fEndPos[1]-fClientOrigin[1]) * fPercentage)-0.08; 
		fStartPos[2] = fClientOrigin[2] + ((fEndPos[2]-fClientOrigin[2]) * fPercentage);
		
		TE_SetupBeamPoints(fStartPos, fEndPos, g_iBeamSprite, 0, 0, 0, g_fLife, g_fStartWidth, g_fEndWidth, 1, g_fAmplitude, g_iColor[iClient], 0);
	}
	TE_SendToAll();
	
	return Plugin_Continue;
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
	if (TR_DidHit(trace))
	{
		TR_GetEndPosition(fImpactPos, trace);
	}
	delete trace;
	//Play the taser sounds
	EmitAmbientSound(SOUND_IMPACT, fImpactPos, SOUND_FROM_WORLD, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.5, SNDPITCH_LOW);
	EmitAmbientSound(SOUND_SHOOT, fOrigin, SOUND_FROM_WORLD, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.3, SNDPITCH_LOW);
	return Plugin_Continue;
}

public bool TR_DontHitSelf(int entity, int mask, any data)
{
	if (entity == data) 
		return false;
	return true;
}

void DisplayTraccersMenu(int iClient)
{
	if(IsClientInGame(iClient))
	{
		char szTitle[32], szMode[32], szSelectColor[32], szTerm[32];
		FormatEx(szTitle, sizeof(szTitle), "%T", "Traccers", iClient);
		FormatEx(szSelectColor, sizeof(szSelectColor), "%T", "Select Color", iClient);
		FormatEx(szTerm, sizeof(szTerm), "%T", "Term", iClient);
		
		if(g_bEnable[iClient])
			FormatEx(szMode, sizeof(szMode), "%T", "Disable", iClient);
		else
			FormatEx(szMode, sizeof(szMode), "%T", "Enable", iClient);
		
		Menu hTraccerMenu = new Menu(TraccersMenu_Handler);
		hTraccerMenu.SetTitle(szTitle);
		hTraccerMenu.AddItem("mode", szMode);
		hTraccerMenu.AddItem("color", szSelectColor);
		hTraccerMenu.AddItem("term", szTerm);
		hTraccerMenu.ExitButton = true;
		hTraccerMenu.Display(iClient, MENU_TIME_FOREVER);
	}
}

void DisplaySelectColorMenu(int iClient)
{
	if(IsClientInGame(iClient))
	{
		char szTitle[32], szRed[32], szGreen[32], szBlue[32], szYellow[32], szPink[32], szWhite[32];
		FormatEx(szTitle, sizeof(szTitle), "%T", "Color", iClient);
		FormatEx(szRed, sizeof(szRed), "%T", "Red", iClient);
		FormatEx(szGreen, sizeof(szGreen), "%T", "Green", iClient);
		FormatEx(szBlue, sizeof(szBlue), "%T", "Blue", iClient);
		FormatEx(szYellow, sizeof(szYellow), "%T", "Yellow", iClient);
		FormatEx(szPink, sizeof(szPink), "%T", "Pink", iClient);
		FormatEx(szWhite, sizeof(szWhite), "%T", "White", iClient);
		
		Menu hSelectColorMenu = new Menu(SelectColorMenu_Handler);
		hSelectColorMenu.SetTitle(szTitle);
		
		if(GetUserFlagBits(iClient) & ADMFLAG_GENERIC || GetUserFlagBits(iClient) & ADMFLAG_ROOT)
		{
			char szLighting[32];
			FormatEx(szLighting, sizeof(szLighting), "%T", "Lighting", iClient);
			hSelectColorMenu.AddItem("lighting", szLighting);
		}
		
		hSelectColorMenu.AddItem("red", szRed);
		hSelectColorMenu.AddItem("green", szGreen);
		hSelectColorMenu.AddItem("blue", szBlue);
		hSelectColorMenu.AddItem("yellow", szYellow);
		hSelectColorMenu.AddItem("pink", szPink);
		hSelectColorMenu.AddItem("white", szWhite);
		hSelectColorMenu.ExitBackButton = true;
		hSelectColorMenu.ExitButton = true;
		hSelectColorMenu.Display(iClient, MENU_TIME_FOREVER);
	}
}

void GiveTraccers(int iClient, int iAdmin, const int iMonths)
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
				
			g_bAccess[iClient] = true;
			g_bEnable[iClient] = true;
			SetColor(iClient, 0, 255, 0, 225);
		}
		
		g_hKeyValues.Rewind();
		g_hKeyValues.ExportToFile(g_szPath);
		
		CGOPrintToChat(iClient, "%t", "Receive Traccers");
	}
}

void SetColor(int iClient, const int r, const int g, const int b, const int a)
{
	g_iColor[iClient][0] = r;
	g_iColor[iClient][1] = g;
	g_iColor[iClient][2] = b;
	g_iColor[iClient][3] = a;
	g_bIsLighting[iClient] = false;
}

void UpdatePlayerData(int iClient)
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

void LoadPlayerData(int iClient)
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
}

void PrintTraccersTerm(int iClient)
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
			{
				CGOPrintToChat(iClient, "%t", "Traccers Permanent");
			}
			else
			{
				int iTotalDays = (iTotalTime - GetTime()) / 86400;
				CGOPrintToChat(iClient, "%t", "Traccers Term", iTotalDays + 1);
			}
		}
	}
}

void GetWeaponAttachmentPosition(int client, const char[] attachment, float pos[3])
{
	if (!attachment[0])
		return;
		
	int entity = CreateEntityByName("info_target");
	DispatchSpawn(entity);
	
	int weapon;
	
	if ((weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon")) == -1)
		return;
	
	if ((weapon = GetEntPropEnt(weapon, Prop_Send, "m_hWeaponWorldModel")) == -1)
		return;
		
	SetVariantString("!activator");
	AcceptEntityInput(entity, "SetParent", weapon, entity, 0);
	
	SetVariantString(attachment); 
	AcceptEntityInput(entity, "SetParentAttachment", weapon, entity, 0);
	
	TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, NULL_VECTOR);
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", pos);
	AcceptEntityInput(entity, "kill");
}

void TE_DispatchEffect(const char[] particle, const float pos[3], const float endpos[3], const float angles[3] = NULL_VECTOR)
{
	TE_Start("EffectDispatch");
	TE_WriteFloatArray("m_vStart.x", pos, 3);
	TE_WriteFloatArray("m_vOrigin.x", endpos, 3);
	TE_WriteVector("m_vAngles", angles);
	TE_WriteNum("m_nHitBox", GetParticleEffectIndex(particle));
	TE_WriteNum("m_iEffectName", GetEffectIndex("ParticleEffect"));
}

void PrecacheParticleEffect(const char[] sEffectName)
{
	static int table = INVALID_STRING_TABLE;
	
	if (table == INVALID_STRING_TABLE)
		table = FindStringTable("ParticleEffectNames");
		
	bool save = LockStringTables(false);
	AddToStringTable(table, sEffectName);
	LockStringTables(save);
}

int GetParticleEffectIndex(const char[] sEffectName)
{
	static int table = INVALID_STRING_TABLE;

	if (table == INVALID_STRING_TABLE)
		table = FindStringTable("ParticleEffectNames");

	int iIndex = FindStringIndex(table, sEffectName);

	if (iIndex != INVALID_STRING_INDEX)
		return iIndex;

	return 0;
}

void PrecacheEffect(const char[] sEffectName)
{
	static int table = INVALID_STRING_TABLE;
	
	if (table == INVALID_STRING_TABLE)
		table = FindStringTable("EffectDispatch");
		
	bool save = LockStringTables(false);
	AddToStringTable(table, sEffectName);
	LockStringTables(save);
}

int GetEffectIndex(const char[] sEffectName)
{
	static int table = INVALID_STRING_TABLE;

	if (table == INVALID_STRING_TABLE)
		table = FindStringTable("EffectDispatch");

	int iIndex = FindStringIndex(table, sEffectName);

	if (iIndex != INVALID_STRING_INDEX)
		return iIndex;

	return 0;
}