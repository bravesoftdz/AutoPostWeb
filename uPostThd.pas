unit uPostThd;

interface

uses
  Classes,
  SysUtils,
  Windows,
  Messages,
  uDM,
  IniFiles,
  Math;

const
  WM_SHOW_POSTINFO = WM_USER+101;

type
  TPostStatus = Procedure (Sender: TObject; bPost: Boolean; PostStatus: Boolean; PostNum: Integer; PostID: Integer; PostTitle: String) of Object;

type
  TPostThd = class(TThread)
  private
    FHandle: THandle;
    FEvent: THandle;
    bPost: Boolean;
    FCount, FPostCount: Integer;
    FIsBreak: Boolean;
    FOnPostStatus: TPostStatus;
    FWaitTime: Integer;
    LstGongLue: TStringList;
    procedure GetPostConfig(date: string);
    function GetRandomTime: Integer;
    procedure InitGongLueList;
    function SetPost: Boolean;
    { Private declarations }
  protected
    procedure Execute; override;
  public
    constructor Create(aHandle: THandle);
    destructor Destroy; override;
    procedure SetBreak;
    procedure StartWork;
    property OnPostStatus: TPostStatus read FOnPostStatus write FOnPostStatus;
  end;

implementation

constructor TPostThd.Create(aHandle: THandle);
begin
  inherited Create(False);
  FreeOnTerminate := True;
  FEvent:= CreateEvent(nil, False, False, 'AUTOPOSTTOWEB');
  FHandle := aHandle;
  LstGongLue := TStringList.Create;
end;

destructor TPostThd.Destroy;
begin
  LstGongLue.Free;
  inherited Destroy;
end;

{ Important: Methods and properties of objects in visual components can only be
  used in a method called using Synchronize, for example,

      Synchronize(UpdateCaption);

  and UpdateCaption could look like,

    procedure TPostThd.UpdateCaption;
    begin
      Form1.Caption := 'Updated in a thread';
    end; }

{ TPostThd }

procedure TPostThd.Execute;
var
  sToday: String;
begin
  FPostCount := 0;
  while Not FIsBreak do
  begin
    //获取当天发送数据
    sToday := FormatDateTime('yyyy-mm-dd', Now);
    GetPostConfig(sToday);
    //还没有发够，再取数据
    if (FPostCount < FCount) and (LstGongLue.Count=0) then
      InitGongLueList;
    //发布
    if SetPost then
    begin
      OutputDebugString('AutoPost:今天的发完了，等待。。。');
      WaitForSingleObject(FEvent, INFINITE);
    end;
  end;
end;

procedure TPostThd.GetPostConfig(date: string);
var
  ini: TIniFile;
  path: string;
begin
  path := ExtractFilePath(ParamStr(0))+'config.ini';
  if Not FileExists(path) then
  begin
    OutputDebugString('配置文件不存在！');
    Exit;
  end;
  ini := TIniFile.Create(path);
  try
    FCount := ini.ReadInteger('date', date, 100);
  finally
    ini.Free;
  end;

  FWaitTime := GetRandomTime;
end;

function TPostThd.GetRandomTime: Integer;
var
  iMin, iMax: Integer;
begin
  //5-10分钟取随机时间
  Result := 5*60;

  iMin := 5*60;
  iMax := 10*60;
  Randomize;
  Result := RandomRange(iMin, iMax);
end;

procedure TPostThd.InitGongLueList;
var
  sSQL: String;
  id: Integer;
  str, Title: String;
begin
  sSQL := 'select id, title from GameNews where sortId<>1 and isAddLink=1 and gameid >0 and islock=1 order by id DESC';
  if DM.OpenTable(DM.qy_SQL, sSQL) = 0 then Exit;
  LstGongLue.Clear;
  while Not DM.qy_SQL.Eof do
  begin
    id := DM.qy_SQL.FieldByName('id').AsInteger;
    Title := DM.qy_SQL.FieldByName('title').AsString;
    str := IntToStr(id)+'|'+Title;
    LstGongLue.Append(str);
    //if LstGongLue.Count = 5 then Break;   //test
    DM.qy_SQL.Next;
  end;

  SendMessage(FHandle, WM_SHOW_POSTINFO, FWaitTime, FCount);
end;

procedure TPostThd.SetBreak;
begin
  FIsBreak := True;
  SetEvent(FEvent);
end;

function TPostThd.SetPost: Boolean;
var
  I, iPos: Integer;
  str, PostID, PostTitle: String;
  sSQL: String;
  ini: TIniFile;
  sToday: String;
begin
  Result := False;
  ini := TIniFile.Create(ExtractFilePath(ParamStr(0))+'config.ini');
  for I := LstGongLue.Count-1 downto 0 do
  begin
    if FIsBreak then Exit;
    if FPostCount >= FCount then
    begin
      bPost := False;
      
      if Assigned(FOnPostStatus) then
        FOnPostStatus(Self, bPost, False, 0, 0, '');
      Result := True;
      
      Exit;  //发够了，不发了！
    end;
    Inc(FPostCount);
    
    bPost := True;
    str := LstGongLue[I];
    iPos := Pos('|', str);
    PostID := Copy(str, 1, iPos-1);
    PostTitle := Copy(Str, iPos+1, Length(str)-iPos);
    sSQL := 'update GameNews Set PubTime = GETDATE(), lastUpdateTime = GETDATE(), isLock = 0 Where id = '+PostID;
    DM.conn_SQL.BeginTrans;
    try
      DM.conn_SQL.Execute(sSQL);
      DM.conn_SQL.CommitTrans;
      if Assigned(FOnPostStatus) then
        FOnPostStatus(Self, bPost, True, FPostCount, StrToInt(PostID), PostTitle);

      //记录剩余条数
      sToday := FormatDateTime('yyyy-mm-dd', Now);
      ini.WriteInteger('date', sToday, FCount-FPostCount);
    except
      DM.conn_SQL.RollbackTrans;
      if Assigned(FOnPostStatus) then
        FOnPostStatus(Self, bPost, False, FPostCount, StrToInt(PostID), PostTitle);
    end;
    //等待
    if FIsBreak then Exit;
    Sleep(FWaitTime*1000);
    //Sleep(2*1000);  //test
  end;
  Result := FPostCount = FCount;
  ini.Free;
end;
//******************************************************************************
// 换醒线程
//******************************************************************************
procedure TPostThd.StartWork;
begin
  FPostCount := 0;
  SetEvent(FEvent);
end;

end.
