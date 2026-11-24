[Setup]
AppId=BanmakuPortable
AppName=Banmaku
AppVersion={#PackageVersion}
AppPublisher=Banmaku
DefaultDirName={src}\Banmaku
DisableDirPage=no
DisableProgramGroupPage=yes
DirExistsWarning=no
PrivilegesRequired=lowest
Uninstallable=no
CreateUninstallRegKey=no
UsePreviousAppDir=no
UsePreviousTasks=no
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=no
AppMutex=Local\BanmakuPortableRunning
SetupMutex=Local\BanmakuPortableSetup
OutputDir={#PackageOutputDir}
OutputBaseFilename=Banmaku-{#PackageVersion}-windows-x64-portable
SetupIconFile=..\windows\runner\resources\banmaku_icon.ico
Compression=lzma2/normal
SolidCompression=yes

[Languages]
Name: "zh"; MessagesFile: "compiler:Default.isl"

[Messages]
SetupAppTitle=Banmaku 便携安装包
ButtonBack=上一步
ButtonNext=下一步
ButtonInstall=解压
ButtonCancel=取消
ButtonFinish=完成
SelectDirDesc=选择便携目录
SelectDirLabel3=程序和用户数据将保存在这个文件夹中。
SelectDirBrowseLabel=可以选择本机文件夹或 U 盘中的目录。
SelectTasksDesc=导入数据
SelectTasksLabel2=可将当前 Windows 用户的 Banmaku 数据复制到便携目录。
ReadyLabel1=已准备好解压 Banmaku。
ReadyLabel2a=点击「解压」继续，或返回上一步检查设置。
ReadyLabel2b=点击「解压」继续。
ReadyMemoDir=便携目录
ReadyMemoTasks=数据导入
InstallingLabel=正在解压 Banmaku，请稍候。
FinishedHeadingLabel=Banmaku 已就绪
FinishedLabelNoIcons=可以从所选文件夹中的 app\Banmaku.exe 启动 Banmaku。
FinishedLabel=可以从所选文件夹中的 app\Banmaku.exe 启动 Banmaku。

[Tasks]
Name: "importlocal"; Description: "首次启动时复制已有观看记录、收藏、设置和下载"; Flags: unchecked

[Files]
Source: "{#PayloadDir}\*"; DestDir: "{code:GetStagingDirectory}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Run]
Filename: "{app}\app\Banmaku.exe"; WorkingDir: "{app}\app"; Description: "启动 Banmaku"; Flags: postinstall nowait skipifsilent

[Code]
var
  StagingDirectory: String;

function GetStagingDirectory(Param: String): String;
begin
  Result := StagingDirectory;
end;

function ExistingProgram(const Directory: String): String;
begin
  Result := Directory + '\Banmaku.exe';
  if not FileExists(Result) then
    Result := Directory + '\nova_play.exe';
end;

function IsBanmakuProgram(const Directory: String): Boolean;
begin
  Result := FileExists(Directory + '\portable.ini') and
    FileExists(ExistingProgram(Directory));
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Root, Current, Previous, Candidate: String;
  Attempt: Integer;
begin
  Root := ExpandConstant('{app}');
  Current := Root + '\app';
  Previous := Root + '\app.previous';
  if (FileExists(Current) or (DirExists(Current) and not IsBanmakuProgram(Current))) or
     (FileExists(Previous) or (DirExists(Previous) and not IsBanmakuProgram(Previous))) then
  begin
    Result := 'The selected folder contains other program files. Pick a new Banmaku folder.';
    Exit;
  end;
  if DirExists(Root + '\UserData') and not (DirExists(Current) or DirExists(Previous)) then
  begin
    Result := 'The selected folder already contains UserData. Pick a new Banmaku folder.';
    Exit;
  end;
  if not ForceDirectories(Root) then
  begin
    Result := 'The selected folder cannot be created. Pick a writable folder.';
    Exit;
  end;
  for Attempt := 1 to 8 do
  begin
    Candidate := Root + '\.banmaku-stage-' + IntToStr(Random(1000000000));
    if CreateDir(Candidate) then
    begin
      StagingDirectory := Candidate;
      Result := '';
      Exit;
    end;
  end;
  Result := 'Could not stage the update. Check free space and folder permissions.';
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Root, Current, Previous, Data: String;
  BackedUp: Boolean;
begin
  if CurStep <> ssPostInstall then Exit;

  Root := ExpandConstant('{app}');
  Current := Root + '\app';
  Previous := Root + '\app.previous';
  Data := Root + '\UserData';

  if not (FileExists(StagingDirectory + '\Banmaku.exe') and
          FileExists(StagingDirectory + '\flutter_windows.dll') and
          FileExists(StagingDirectory + '\data\app.so') and
          SaveStringToFile(StagingDirectory + '\portable.ini', '[Banmaku]' + #13#10, False)) then
    RaiseException('The new package could not be prepared. Existing program files are intact.');
  if CheckForMutexes('Local\BanmakuPortableRunning') then
    RaiseException('Close Banmaku and all player windows, then run Setup again.');

  BackedUp := False;
  if DirExists(Current) then
  begin
    if DirExists(Previous) and not DelTree(Previous, True, True, True) then
      RaiseException('Could not remove the previous program backup. Existing program files are intact.');
    if not RenameFile(Current, Previous) then
      RaiseException('Could not back up the program. Close Banmaku and run Setup again.');
    BackedUp := True;
  end;

  if not RenameFile(StagingDirectory, Current) then
  begin
    if BackedUp and not RenameFile(Previous, Current) then
      RaiseException('The update stopped. Start the previous program at ' + ExistingProgram(Previous) + '.');
    RaiseException('Could not activate the new program. Run Setup again to retry.');
  end;
  StagingDirectory := '';

  if WizardIsTaskSelected('importlocal') and not FileExists(Data + '\shared_preferences.json') then
  begin
    if not (ForceDirectories(Data) and
            SaveStringToFile(Data + '\import-local-profile', '', False)) then
      MsgBox('Banmaku was unpacked, but Setup could not request an import of your old data.', mbInformation, MB_OK);
  end;
end;

procedure DeinitializeSetup;
begin
  if (StagingDirectory <> '') and DirExists(StagingDirectory) then
    DelTree(StagingDirectory, True, True, True);
end;
