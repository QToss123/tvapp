[Setup]
AppName=BurlingtonEnglish
AppVersion=1.0.0
DefaultDirName={pf}\BurlingtonEnglish
DefaultGroupName=BurlingtonEnglish
OutputBaseFilename=BurlingtonEnglishSetup
Compression=lzma
SolidCompression=yes

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs

[Icons]
Name: "{group}\BurlingtonEnglish"; Filename: "{app}\tv_app_books.exe"
Name: "{commondesktop}\BurlingtonEnglish"; Filename: "{app}\tv_app_books.exe"

[Run]
Filename: "{app}\tv_app_books.exe"; Description: "Launch BurlingtonEnglish"; Flags: nowait postinstall
