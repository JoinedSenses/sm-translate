#pragma semicolon 1 

#include <sourcemod> 
#include <sdktools>
#include <tf2>
#include <system2>
#include <files>
#include <smjansson>
#include <stringescape>
#include <menus>
#include <clientprefs>
#include <morecolors>

//#define DEBUG

public Plugin myinfo = 
{ 
    name = "sm-translate", 
    author = "Larry", 
    description = "Realtime chat translation", 
    version = "1.0.2", 
    url = "http://steamcommunity.com/id/pancakelarry" 
}; 

char g_cChatPrefix[] = {"[{unusual}Translate{default}]"};
char g_cApiUrl[128];
char g_cApiKey[64];

char g_cLanguages[][] = {"Afrikaans", "Albanian", "Amharic", "Arabic", "Armenian",\
						"Azeerbaijani", "Basque", "Belarusian", "Bengali", "Bosnian",\
						"Bulgarian", "Catalan", "Cebuano", "Chinese (Simplified)", "Chinese (Traditional)",\
						"Corsican", "Croatian", "Czech", "Danish", "Dutch",\ 
						"English", "Esperanto", "Estonian", "Finnish", "French",\
						"Frisian", "Galician", "Georgian", "German", "Greek",\
						"Gujarati", "Haitian Creole", "Hausa", "Hawaiian", "Hebrew",\
						"Hindi", "Hmong", "Hungarian", "Icelandic", "Igbo",\
						"Indonesian", "Irish", "Italian", "Japanese", "Javanese",\
						"Kannada", "Kazakh", "Khmer", "Korean", "Kurdish",\
						"Kyrgyz", "Lao", "Latin", "Latvian", "Lithuanian",\
						"Luxembourgish", "Macedonian", "Malagasy", "Malay", "Malayalam",\
						"Maltese", "Maori", "Marathi", "Mongolian", "Myanmar (Burmese)",\
						"Nepali", "Norweigian", "Nyanja (Chichewa)", "Pashto", "Persian",\
						"Polish", "Portuguese", "Punjabi", "Romanian", "Russian",\
						"Samoan", "Scots Gaelic", "Serbian", "Sesotho", "Shona",\
						"Sindhi", "Sinhala", "Slovak", "Slovenian", "Somali",\
						"Spanish", "Sundanese", "Swahili", "Swedish", "Tagalog",\
						"Tajik", "Tamil", "Telugu", "Thai", "Turkish",\
						"Ukrainian", "Urdu", "Uzbek", "Vietnamese", "Welsh",\
						"Xhosa", "Yiddish", "Yoruba", "Zulu"};
						
char g_cLanguageCodes[][] = {"af", "sq", "am", "ar", "hy",\
							"az", "eu", "be", "bn", "bs",\
							"bg", "ca", "ceb", "zh-CN", "zh-TW",\
							"co", "hr", "cs", "da", "nl",\
							"en", "eo", "et", "fi", "fr",\
							"fy", "gl", "ka", "de", "el",\
							"gu", "ht", "ha", "haw", "iw",\ 
							"hi", "hmn", "hu", "is", "ig",\
							"id", "ga", "it", "ja", "jw",\
							"kn", "kk", "km", "ko", "ku",\
							"ky", "lo", "la", "lv", "lt",\
							"lb", "mk", "mg", "ms", "ml",\
							"mt", "mi", "mr", "mn", "my",\
							"ne", "no", "ny", "ps", "fa",\
							"pl", "pt", "pa", "ro", "ru",\
							"sm", "gd", "sr", "st", "sn",\
							"sd", "si", "sk", "sl", "so",\
							"es", "su", "sw", "sv", "tl",\
							"tg", "ta", "te", "th", "tr",\
							"uk", "ur", "uz", "vi", "cy",\
							"xh", "yi", "yo", "zu"};
							
int g_iClientTargetLanguage[MAXPLAYERS];

bool g_bClientSourceLanguages[MAXPLAYERS][sizeof(g_cLanguages)];

Menu g_mLanguageMenu = null;
Menu g_mTargetLanguageMenu = null;
Menu g_mSourceLanguageMenu = null;

Handle g_hTargetPrefs;
Handle g_hSourcePrefs;

int g_iMaxLoadAttempts = 5;
int g_iLoadAttempts;


public void OnPluginStart()
{	
	Handle hApiKeyHandle = OpenFile("\\addons\\sourcemod\\configs\\sm-translate\\api-key.txt", "r");
	if(hApiKeyHandle == INVALID_HANDLE)
	{
		SetFailState("Couldn't find 'api-key.txt' in tf/addons/sourcemod/configs/sm-translate/.");
	}

	ReadFileString(hApiKeyHandle, g_cApiKey, sizeof(g_cApiKey), -1);
	CloseHandle(hApiKeyHandle);
	if(strlen(g_cApiKey) <= 0)
	{
		SetFailState("Couldn't find 'api-key.txt' in tf/addons/sourcemod/configs/sm-translate/.");
	}

	g_cApiUrl = "https://translation.googleapis.com/language/translate/v2?key=";
	StrCat(g_cApiUrl, sizeof(g_cApiUrl), g_cApiKey);
	
	RegConsoleCmd("sm_languagemenu", Command_ShowLanguageMenu, "Opens language settings menu");
	RegConsoleCmd("sm_lmenu", Command_ShowLanguageMenu, "Opens language settings menu");
	
	g_mLanguageMenu = BuildLanguageMenu();
	g_mTargetLanguageMenu = BuildTargetLanguageMenu();	
	g_mSourceLanguageMenu = BuildSourceLanguageMenu();
	g_hTargetPrefs = RegClientCookie("target_prefs", "Target language cookies", CookieAccess_Protected);
	g_hSourcePrefs = RegClientCookie("source_prefs", "Source language cookies", CookieAccess_Protected);
	
	// if plugin is reloaded while players are on the server
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		g_iLoadAttempts = 0;
		CreateTimer(1.0, Timer_LoadClientCookies, i, TIMER_REPEAT);
	}
}

public void OnClientConnected(int client)
{
	g_iLoadAttempts = 0;
	CreateTimer(1.0, Timer_LoadClientCookies, client, TIMER_REPEAT);
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	char Args[256];
	strcopy(Args, sizeof(Args), sArgs);
	TrimString(Args);

	if(strcmp(command, "say", false) == 0)
	{
		if(strlen(Args) > 0)
		{
			TranslateToChat(Args);
		}			
	}
	return Plugin_Continue;
}

public Action Timer_LoadClientCookies(Handle timer, any client)
{
	g_iLoadAttempts++;
	if(AreClientCookiesCached(client))
	{	
		char target[5];
		GetClientCookie(client, g_hTargetPrefs, target, sizeof(target));
		
		// defaults
		if(strlen(target) <= 0)
		{
			SetClientCookie(client, g_hTargetPrefs, "en");
			char sources[sizeof(g_cLanguages)];
			for(int i = 0; i<sizeof(sources); i++)
				sources[i] = 't';
			return Plugin_Stop;
		}
		else
		{
			for(int i = 0; i<sizeof(g_cLanguages); i++)
			{
				if(strcmp(target, g_cLanguageCodes[i], false) == 0)
				{
					g_iClientTargetLanguage[client] = i;
				}
			}
		}
		SetClientCookie(client, g_hTargetPrefs, target);
		
		// t = true
		// f = false
		char sources[sizeof(g_cLanguages)];
		GetClientCookie(client, g_hSourcePrefs, sources, sizeof(sources));
		for(int i = 0; i<sizeof(sources); i++)
		{
			if(sources[i] == '\0')
				g_bClientSourceLanguages[client][i] = true;
			if(sources[i] == 't')
				g_bClientSourceLanguages[client][i] = true;
			if(sources[i] == 'f')
				g_bClientSourceLanguages[client][i] = false;
		}
		SetClientCookie(client, g_hSourcePrefs, sources);
		return Plugin_Stop;
	}
	if(g_iLoadAttempts >= g_iMaxLoadAttempts)
	{
		return Plugin_Stop;
	}
	
	return Plugin_Continue;
}

void SetClientCookies(int client)
{
	SetClientCookie(client, g_hTargetPrefs, g_cLanguageCodes[g_iClientTargetLanguage[client]]);
	
	char sources[sizeof(g_cLanguages)];
	for(int i = 0; i<sizeof(sources); i++)
	{
		if(g_bClientSourceLanguages[client][i])
		{
			sources[i] = 't';
		}
		else
			sources[i] = 'f';
	}
	
	SetClientCookie(client, g_hSourcePrefs, sources);	
}

Menu BuildLanguageMenu()
{
	Menu menu = new Menu(Menu_Main);
	menu.SetTitle("Language settings");
	menu.AddItem("target", "Select target language");
	menu.AddItem("source", "Select source languages");
	return menu;
}

Menu BuildTargetLanguageMenu()
{
	Menu menu = new Menu(Menu_ChooseTargetLanguage, MenuAction_DrawItem);
	for(int i = 0; i<sizeof(g_cLanguages); i++)
	{
		menu.AddItem(g_cLanguageCodes[i], g_cLanguages[i]);
	}
	menu.SetTitle("Select target language. Other languages will be translated to this.");
	menu.ExitBackButton = true;
	
	return menu;
}

Menu BuildSourceLanguageMenu()
{
	Menu menu = new Menu(Menu_ChooseSourceLanguage, MenuAction_DisplayItem);
	menu.SetTitle("Select languages to translate from.");
	for(int i = 0; i<sizeof(g_cLanguages); i++)
	{
		menu.AddItem(g_cLanguageCodes[i], g_cLanguages[i]);
	}
	menu.ExitBackButton = true;
	return menu;
}

public int Menu_Main(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		switch(param2)
		{
			case 0:
				ShowTargetMenu(param1);
			case 1:
				ShowSourceMenu(param1);
		}
	}
}

public int Menu_ChooseTargetLanguage(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		g_iClientTargetLanguage[param1] = param2;
		SetClientCookies(param1);
		DisplayMenuAtItem(menu, param1, GetMenuSelectionPosition(), MENU_TIME_FOREVER);
		CPrintToChat(param1, "%s Target language set to %s.", g_cChatPrefix, g_cLanguages[param2]);
	}
	if(action == MenuAction_DrawItem)
	{		
		if(g_iClientTargetLanguage[param1] == param2)
		{			
			return ITEMDRAW_DISABLED;
		}
		else
			return ITEMDRAW_DEFAULT;
	}
	if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
			ShowLanguageMenu(param1);
	}
	
	return 0;
}

public int Menu_ChooseSourceLanguage(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		g_bClientSourceLanguages[param1][param2] = !g_bClientSourceLanguages[param1][param2];
		SetClientCookies(param1);
		DisplayMenuAtItem(menu, param1, GetMenuSelectionPosition(), MENU_TIME_FOREVER);
	}
	if(action == MenuAction_DisplayItem)
	{
		char display[64];
		menu.GetItem(param2, "", 0, _, display, sizeof(display));
		
		if(g_bClientSourceLanguages[param1][param2])
		{
			StrCat(display, sizeof(display), " (ON)");
		}
		else
			StrCat(display, sizeof(display), " (OFF)");
		
		return RedrawMenuItem(display);
	}
	if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
			ShowLanguageMenu(param1);
	}
	
	return 0;
}

public Action Command_ShowLanguageMenu(int client, int args)
{
	if(!IsClientInGame(client))
		return Plugin_Handled;
	g_mLanguageMenu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

void ShowLanguageMenu(int client)
{
	if(!IsClientInGame(client))
		return;
	g_mLanguageMenu.Display(client, MENU_TIME_FOREVER);
}

void ShowTargetMenu(int client)
{
	if(!IsClientInGame(client))
		return;
		
	if (g_mTargetLanguageMenu == null)
	{
		return;
	}	
	g_mTargetLanguageMenu.Display(client, MENU_TIME_FOREVER);
}

void ShowSourceMenu(int client)
{
	if (g_mSourceLanguageMenu == null)
	{
		return;
	}	
	g_mSourceLanguageMenu.Display(client, MENU_TIME_FOREVER);
}

public void TranslateToChat(char[] originalMessage)
{	
	// Escape stuff for JSON
	char message[512];
	char tempBuffer[512];
	
	// automatically escaped by tf2 chat
	//EscapeString(originalMessage, '\\', '\\', tempBuffer, sizeof(tempBuffer));
	//EscapeString(tempBuffer, '"', '\\', message, sizeof(message));

	strcopy(tempBuffer, sizeof(tempBuffer), originalMessage);
	
	EscapeString(tempBuffer, '\'', '\\', message, sizeof(message));

	for(int i = 1; i<=MaxClients; i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		for(int a = i; a>0; a--)
		{
			// Make sure no duplicate elements exist
			// don't check against self
			if(a == i)
				a--;
			if(strcmp(g_cLanguageCodes[g_iClientTargetLanguage[a]], g_cLanguageCodes[g_iClientTargetLanguage[i]], false) == 0 && i>1)
				break;
			System2HTTPRequest httpRequest = new System2HTTPRequest(TranslateCallback, g_cApiUrl); 
			httpRequest.Any = i;
			httpRequest.SetHeader("Content-Type", "application/json; charset=utf-8");
			httpRequest.SetData("{ \
			'q':'%s', \
			'target':'%s' \
			}", message, g_cLanguageCodes[g_iClientTargetLanguage[i]]);
			httpRequest.POST(); 
		
			delete httpRequest; 
		}
	}	
}

public void TranslateCallback(bool success, const char[] error, System2HTTPRequest request, System2HTTPResponse response, HTTPRequestMethod method) 
{ 
    if (success) 
    {
    	int client = request.Any;
    	// DISGUSTING YET FUNCTIONAL CODE
    	
		int arraySize = response.ContentLength + 1;
		
		char[] content = new char[arraySize];
		response.GetContent(content, arraySize);
		
		// The whole JSON object
		new Handle:hObj = json_load(content);
		if(hObj == INVALID_HANDLE || !json_is_object(hObj))
		{
			if(hObj != INVALID_HANDLE)
				CloseHandle(hObj);
			#if defined DEBUG
			PrintToServer("response: \n%s", content);
			#endif
			return ThrowError("Couldn't Parse JSON");
		}
		#if defined DEBUG
		char temp[1024];
		json_dump(hObj, temp, 1024);
		#endif
		
		// Data object
		new Handle:hObj2 = json_object_get(hObj, "data");
		if(hObj2 == INVALID_HANDLE || !json_is_object(hObj2))
		{
			if(hObj2 != INVALID_HANDLE)
				CloseHandle(hObj2);
			#if defined DEBUG
			PrintToServer("hObj: \n%s", temp);
			#endif
			return ThrowError("Couldn't Parse JSON");
		}
		#if defined DEBUG
		json_dump(hObj2, temp, 1024);
		#endif
		CloseHandle(hObj);
		
		// Translations array
		new Handle:hArray = json_object_get(hObj2, "translations");
		if(hArray == INVALID_HANDLE || !json_is_array(hArray))
		{
			if(hArray != INVALID_HANDLE)
				CloseHandle(hArray);
			#if defined DEBUG
			PrintToServer("hObj2: \n%s", temp);
			#endif
			return ThrowError("Couldn't Parse JSON");
		}
		#if defined DEBUG
		json_dump(hArray, temp, 1024);
		#endif
		CloseHandle(hObj2);
		
		// Make translations array into an object
		new Handle:hArrayContent = json_array_get(hArray, 0);
		if(hArrayContent == INVALID_HANDLE || !json_is_object(hArrayContent))
		{
			if(hArrayContent != INVALID_HANDLE)
				CloseHandle(hArrayContent);
			#if defined DEBUG
			PrintToServer("hArray: \n%s", temp);
			#endif
			return ThrowError("Couldn't Parse JSON");
		}
		
		CloseHandle(hArray);
		
		// Get value from translations object
		char[] buffer = new char[arraySize];
		json_object_get_string(hArrayContent, "translatedText", buffer, arraySize);
		
		char[] sourceLangBuffer = new char[arraySize];
		json_object_get_string(hArrayContent, "detectedSourceLanguage", sourceLangBuffer, arraySize);
		CloseHandle(hArrayContent);
		
		// Remove escape chars
		ReplaceString(buffer, arraySize, "&#39;", "\'", false);
		ReplaceString(buffer, arraySize, "\\\\", "\\", false);
		
		for(int i = 1; i<=MaxClients; i++)
		{
			if(!IsClientInGame(i))
				continue;
			
			// Don't translate from clients target language
			if(strcmp(sourceLangBuffer, g_cLanguageCodes[g_iClientTargetLanguage[i]], false) == 0)
				continue;
			
			#if !defined DEBUG
			// Don't translate clients own messages
			if(i == client)
				continue;
			#endif
			
			// Check wanted source languages
			bool brk = false;
			for(int e = 0; e<sizeof(g_cLanguages); e++)
			{
				if(!g_bClientSourceLanguages[i][e])
				{
					if(strcmp(sourceLangBuffer, g_cLanguageCodes[e], false) == 0)
						brk = true;
				}				
			}
			if(brk)
				break;
			
			char name[64];
			GetClientName(client, name, sizeof(name));
			CPrintToChat(i, "%s (%s > %s) %s: %s", g_cChatPrefix, sourceLangBuffer, g_cLanguageCodes[g_iClientTargetLanguage[i]], name, buffer);
		}
    } 
	else 
	{ 
        return ThrowError("HTTP Request Failed \n%s", error);
    } 
} 