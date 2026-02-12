#define AppName "Voidbreaker"
#define AppVersion "0.1.0"
#define AppPublisher "p4ndepravitygaming"
#define AppURL "https://www.youtube.com/@p4ndepravitygaming"
#define AppExeName "Voidbreaker.exe"
#define RootDir "..\\.."

[Setup]
AppId={{D1D3B8E0-AFA7-46E8-BD79-08DCA2A645D0}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}
DefaultDirName={autopf}\{#AppName}
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
LicenseFile={#RootDir}\docs\release\EULA.txt
InfoBeforeFile={#RootDir}\docs\release\THIRD_PARTY_NOTICES.txt
OutputDir={#RootDir}\build\installer
OutputBaseFilename=Voidbreaker-Setup-{#AppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#RootDir}\build\windows\Voidbreaker.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#RootDir}\build\windows\Voidbreaker.pck"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#RootDir}\docs\release\README.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#RootDir}\docs\release\THIRD_PARTY_NOTICES.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
