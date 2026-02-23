[Setup]
AppName=Burlington
AppVersion=1.0.0
DefaultDirName={pf}\Burlington
DefaultGroupName=Burlington
OutputBaseFilename=BurlingtonSetup
Compression=lzma
SolidCompression=yes

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs

[Icons]
Name: "{group}\Burlington"; Filename: "{app}\tv_app_books.exe"; WorkingDir: "{app}"
Name: "{commondesktop}\Burlington"; Filename: "{app}\tv_app_books.exe"; WorkingDir: "{app}"

[Run]
Filename: "{app}\tv_app_books.exe"; Description: "Launch Burlington"; Flags: nowait postinstall
