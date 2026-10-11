[Setup]
AppId={{6B1F7E2A-3C4D-4E5F-9A8B-1D2C3E4F5A6B}
AppName=Zumba & Pédagogie
AppVersion=0.1.2
AppPublisher=Association
DefaultDirName={autopf}\Zumbadeline
DefaultGroupName=Zumba & Pédagogie
UninstallDisplayIcon={app}\zumbadeline.exe
SetupIconFile=..\windows\runner\resources\app_icon.ico
OutputDir=output
OutputBaseFilename=zumbadeline-setup-0.1.2
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
WizardStyle=modern

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "Créer un raccourci sur le Bureau"; GroupDescription: "Raccourcis :"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Zumba & Pédagogie"; Filename: "{app}\zumbadeline.exe"
Name: "{autodesktop}\Zumba & Pédagogie"; Filename: "{app}\zumbadeline.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\zumbadeline.exe"; Description: "Lancer l'application"; Flags: nowait postinstall skipifsilent
