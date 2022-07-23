unit webfilelnet_main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, EditBtn, MaskEdit, lNetComponents, lNet, lhttp, lwebserver;

type


  { TForm1 }

  TForm1 = class(TForm)
    Button1: TButton;
    CheckBoxAuth: TCheckBox;
    DirectoryEdit1: TDirectoryEdit;
    Edit1: TEdit;
    EditUser: TEdit;
    EditPass: TEdit;
    GroupBox1: TGroupBox;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    MaskSub: TMaskEdit;
    Panel1: TPanel;
    TimerUDP: TTimer;
    TimerStart: TTimer;
    TrayIcon1: TTrayIcon;
    procedure Button1Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormWindowStateChange(Sender: TObject);
    procedure LHTTPServerComponent1Accept(aSocket: TLSocket);
    procedure LHTTPServerComponent1Error(const msg: string; aSocket: TLSocket);
    procedure MaskSubEditingDone(Sender: TObject);
    procedure TimerStartTimer(Sender: TObject);
    procedure TimerUDPTimer(Sender: TObject);
    procedure TrayIcon1DblClick(Sender: TObject);
  private
    { private declarations }
  public
    procedure SetupMyHTTP;
    procedure SaveDocPath;
    procedure LoadDocPath;
    { public declarations }
  end;

var
  Form1: TForm1;

implementation

uses lMimeTypes, lHTTPUtil, uFileHandler, loglistfpc, Sockets, DefaultTranslator;

{$R *.lfm}

resourcestring
  rsUDPError = '* UDP error';
  rsDisconnected = 'Disconnected.';
  rsBasicAuthori = 'Basic Authorization Mode! User: %s, Pass:%s';
  rsAddressSD = '* Address: %s:%d';
  rsErrorInWriti = 'Error in Writing ';
  rsPeerS = 'Peer %s';


const
  DocRootIni='DocRoot.ini';

var
  loglist: TLogListFPC;
  ExePath: string;
  MyHttpServer: TBigFileLHTTPServerComponent;
  IPBuf: array[0..255] of char;
  ipudp: string;
  msgbuf: string;
  udpsock: longint;
  udpaddr: sockaddr;
  nmask, nmask_tmp: string;

{ TForm1 }

procedure TForm1.FormShow(Sender: TObject);
var
  b: TStringObject;
begin
  ExePath:=ExtractFilePath(ParamStr(0));
  LoadDocPath;

  MaskSub.Text:=nmask;

  // must exist for filehandler
  if FileExists(ExtractFilePath(ParamStr(0))+'mime.types') then
   InitMimeList(ExtractFilePath(ParamStr(0))+'mime.types')
   else begin
    InitMimeList('');
    b:=TStringObject.Create;
    b.Str:='text/html';
    MimeList.AddObject('.html', b);
    b:=TStringObject.Create;
    b.Str:='text';
    MimeList.AddObject('.txt', b);
    b:=TStringObject.Create;
    b.Str:='image';
    MimeList.AddObject('.jpg', b);
    b:=TStringObject.Create;
    b.Str:='image';
    MimeList.AddObject('.png', b);
   end;
  //

  TimerStart.Enabled:=True;
end;

procedure TForm1.FormWindowStateChange(Sender: TObject);
begin
  if Form1.WindowState=wsMinimized then begin
    Form1.Hide;
    TrayIcon1.Visible:=True;
  end;
end;

procedure TForm1.MaskSubEditingDone(Sender: TObject);
var
  s, buf, temp: string;
begin
  buf:=MaskSub.Text;
  s:=Copy(buf,1,3);
  temp:=trim(s);
  s:=Copy(buf,5,3);
  temp:=Temp+'.'+trim(s);
  s:=Copy(buf,9,3);
  temp:=temp+'.'+trim(s);
  s:=Copy(buf,13,3);
  temp:=temp+'.'+trim(s);
  nmask:=temp;
end;

procedure TForm1.LHTTPServerComponent1Accept(aSocket: TLSocket);
begin
  loglist.AddLog(Format(rsPeerS, [aSocket.PeerAddress]));
end;

procedure TForm1.Button1Click(Sender: TObject);
begin
  Button1.Enabled:=False;
  try
    SetupMyHTTP;
  finally
    Button1.Enabled:=True;
  end;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  loglist:=TLogListFPC.Create(Self);
  loglist.Name:='loglist1';
  loglist.Parent:=Panel1;
  loglist.Align:=alClient;
  loglist.Color:=clWhite;
  loglist.LineLimit:=1000;
  udpsock:=fpsocket(AF_INET,SOCK_DGRAM,IPPROTO_UDP);
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  (*
  if MyHttpServer<>nil then
    MyHttpServer.Free;
  loglist.Free;
  *)
  TimerUDP.Enabled:=False;
  SaveDocPath;
  CloseSocket(udpsock);
  Sleep(100);
end;

procedure TForm1.LHTTPServerComponent1Error(const msg: string; aSocket: TLSocket
  );
begin
  loglist.AddLog(AnsiToUtf8(msg));
end;

procedure TForm1.TimerStartTimer(Sender: TObject);
begin
  TimerStart.Enabled:=False;
  SetupMyHTTP;
end;

procedure TForm1.TimerUDPTimer(Sender: TObject);
begin
  if -1=fpsendto(udpsock,@msgbuf[1],length(msgbuf),0,@udpaddr,sizeof(udpaddr)) then
    loglist.AddLog(rsUDPError);
end;

procedure TForm1.TrayIcon1DblClick(Sender: TObject);
begin
  Form1.WindowState:=wsNormal;
  Form1.Show;
  Form1.SetFocus;
  TrayIcon1.Visible:=False;
end;

function makebroadcastip(const s:string):string;
var
  l:integer;
  ip, mask : in_addr;
begin
  ip:=StrToHostAddr(s);
  mask:=StrToHostAddr(nmask);
  ip.s_addr:=ip.s_addr or (not mask.s_addr);
  Result:=HostAddrToStr(ip);
end;

procedure TForm1.SetupMyHTTP;
var
  c: TBigFileURIHandler;
  //a:TCGIHandler;
  sdir: string;
begin
  if MyHttpServer<>nil then begin
    MyHttpServer.Disconnect(True);
    Sleep(100);
    FreeAndNil(MyHttpServer);
    loglist.AddLog(rsDisconnected);
  end;

  MyHttpServer:=TBigFileLHTTPServerComponent.Create(self);
  MyHttpServer.Name:='Server1';
  MyHttpServer.OnError:=@LHTTPServerComponent1Error;
  MyHttpServer.OnAccept:=@LHTTPServerComponent1Accept;

  c:=TBigFileURIHandler.Create;
  c.Methods:=[hmHead, hmGet, hmPost];

  sdir:=pchar(DirectoryEdit1.Directory);
  if sdir<>'' then
    if sdir[Length(sdir)]<>PathDelim then
      sdir:=sdir+PathDelim;
  c.DocRoot:=UTF8Decode(sdir);

  // c.UploadLimit:=40*1024*1024;
  c.UploadLimit:=1024*1024*1024;

  c.AuthEnable:=CheckBoxAuth.Checked;
  if c.AuthEnable then begin
    c.AuthUser:=pchar(EditUser.Text);
    c.AuthPass:=pchar(EditPass.Text);
  end;

  MyHttpServer.RegisterHandler(c);

  if not DirectoryExists(c.DocRoot) then
    CreateDir(c.DocRoot);
  {
  a:=TCGIHandler.Create;
  a.FCGIRoot:=ExtractFilePath(ParamStr(0))+'cgi-bin'+PathDelim;
  a.FDocumentRoot:=ExtractFilePath(ParamStr(0))+'files'+PathDelim;
  a.FEnvPath:=ExtractFilePath(ParamStr(0))+'cgi-bin'+PathDelim;
  a.FScriptPathPrefix:='cgi-bin/';
  LHTTPServerComponent1.RegisterHandler(a);
  }

  MyHttpServer.Port:=StrToIntDef(Edit1.Text,80);
  MyHttpServer.Listen(MyHttpServer.Port);

  if c.AuthEnable then
    loglist.AddLog(Format(rsBasicAuthori, [c.AuthUser, c.AuthPass]));

  //SaveDocPath;
  GetIPAddr(IPBuf,sizeof(IPBuf));
  ipudp:=makebroadcastip(IPBuf);
  //setup UDP
  TimerUDP.Enabled:=False;
  fillchar(udpaddr,sizeof(udpaddr),0);
  udpaddr.sin_port:=htons(51000);
  udpaddr.sin_family:=AF_INET;
  udpaddr.sin_addr:=StrToNetAddr(ipudp);
  msgbuf:=IPBuf+':'+IntToStr(MyHttpServer.Port)+'|WEBFILELNET'#13#10;
  TimerUDP.Enabled:=True;

  loglist.AddLog(Format(rsAddressSD, [IPBuf, MyHttpServer.Port]));
end;

procedure TForm1.SaveDocPath;
var
  iFile:TFileStream;
  chauth:char;
begin
  try
    iFile:=TFileStream.Create(ExePath+DocRootIni,fmCreate or fmOpenWrite or fmShareDenyWrite);
    try
      iFile.Write(DirectoryEdit1.Directory[1],Length(DirectoryEdit1.Directory));
      iFile.Write(#13#10,2);
      iFile.Write(EditUser.Text[1],Length(EditUser.Text));
      iFile.Write(#13#10,2);
      iFile.Write(EditPass.Text[1],Length(EditPass.Text));
      iFile.Write(#13#10,2);
      iFile.Write(Edit1.Text[1],Length(Edit1.Text));
      iFile.Write(#13#10,2);
      if CheckBoxAuth.Checked then
        chauth:='1'
        else
          chauth:='0';
      iFile.Write(chauth,1);
      iFile.Write(#13#10,2);
      iFile.Write(nmask[1],Length(nmask));
      iFile.Write(#13#10,2);
    finally
      iFile.Free;
    end;
  except
    loglist.AddLog(rsErrorInWriti+DocRootIni);
  end;
end;

procedure TForm1.LoadDocPath;
var
  iFile:TFileStream;
  rets:string;
  ch:char;

  function ReadLine:string;
  begin
    Result:='';
    repeat
      if iFile.Read(ch,1)=1 then begin
        if ch=#13 then begin
          iFile.Read(ch,1);
          break;
          end else
            Result:=Result+ch;
      end else
        break;
    until ch=#13;
  end;

begin
  try
    if FileExists(ExePath+DocRootIni) then begin
      iFile:=TFileStream.Create(ExePath+DocRootIni,fmOpenRead or fmShareDenyWrite);
      try
        DirectoryEdit1.Directory:=ReadLine;
        rets:=ReadLine;
        if rets='' then
          rets:='root';
        EditUser.Text:=rets;
        rets:=ReadLine;
        if rets='' then
          rets:='root';
        EditPass.Text:=rets;
        rets:=ReadLine;
        if rets='' then
          rets:='80';
        Edit1.Text:=rets;
        rets:=ReadLine;
        if rets='' then
          rets:='0';
        CheckBoxAuth.Checked:=rets='1';
        nmask:=ReadLine;
        if nmask='' then
          nmask:='255.255.255.0';
      finally
        iFile.Free;
      end;
    end else
      DirectoryEdit1.Directory:=ExePath+'files';
  except
    DirectoryEdit1.Directory:=ExePath+'files';
  end;
end;


end.

