unit uFileHandler;

{ simple LNetHTTP File Handler

  Copyright (C) 2013 Do-wan Kim  lovelust at hanmail.net

  This library is free software; you can redistribute it and/or modify it
  under the terms of the GNU Library General Public License as published by
  the Free Software Foundation; either version 2 of the License, or (at your
  option) any later version.

  This program is distributed in the hope that it will be useful, but WITHOUT
  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
  FITNESS FOR A PARTICULAR PURPOSE. See the GNU Library General Public License
  for more details.

  You should have received a copy of the GNU Library General Public License
  along with this library; if not, write to the Free Software Foundation,
  Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
}


{$mode objfpc}{$H+}

interface

uses
  sysutils, Classes, lNetComponents, lhttp, lwebserver, TextKMP, Sockets;

type

  { TBigFileOutput }

  TBigFileOutput=class(TBufferOutput)
    private
      FFileStream:TFileStream;

      function Getsize:int64;
    protected
      function FillBuffer: TWriteBlockStatus; override;
    public
      StartPos:Int64;
      EndPos:Int64;

      function Open(const AFilename:string):Boolean;

      constructor Create(ASocket: TLHTTPSocket);
      destructor Destroy; override;

      property Size:int64 read GetSize;
  end;

{ TBigStreamOutput }

  TBigHandleInput=function(ABuffer: pchar; ASize: integer):integer of object;

  TBigStreamOutput=class(TStreamOutput)
    private
      FOnHandleInput:TBigHandleInput;
    protected
      function HandleInput(ABuffer: pchar; ASize: integer): integer; override;
      procedure DoneInput; override;
    public
      Boundary:AnsiString;
      BS,BE,WorkBuff:AnsiString;
      BSL,BEL:integer;
      FindText:TDWKMPScan;
      IncNext:Integer;
      UploadFolder:string;
      OutFile:TFileStream;
      InHeader:Boolean;
      bHeader:string;
      bFilename,oFilename,tFilename:string;
      bBuffer:PAnsiChar;
      bRemain:Integer;

      constructor Create(ASocket: TLHTTPSocket; AStream: TStream;
        AFreeStream: boolean);
      destructor Destroy; override;
      // multipart-handler
      function PostHandleInput(ABuffer: pchar; ASize: integer): integer;

      function MakeTempFilename(filename: string): string; virtual;
      function MakeNewFilename(filename: string): string; virtual;

      procedure SetBoundary(b:string);
      property OnHandleInput:TBigHandleInput read FOnHandleInput write FOnHandleInput;
  end;

{ TBigFileURIHandler }

  TBigFileURIHandler=class(TURIHandler)
    private
      FAuthUser:string;
      FAuthPass:string;
      FAuthBase64:string;
      procedure SetAuthUser(const User:string);
      procedure SetAuthPass(const Pass:string);
      procedure SetAuthUserPass(const User,Pass:string);
    protected
      function HandleURI(ASocket: TLHTTPServerSocket): TOutputItem; override;
    public
      DocRoot:string;
      IndexFile:string;

      AuthEnable:Boolean;
      realm:string;

      UploadLimit:Int64;

      constructor Create;

      property AuthUser:string read FAuthUser write SetAuthUser;
      property AuthPass:string read FAuthPass write SetAuthPass;
      property AuthBase64:string read FAuthBase64;
  end;

  { TBigFileLHttpServerSocket }

  TBigFileLHttpServerSocket=class(TLHTTPServerSocket)
    protected
      procedure ParseLine(pLineEnd: pchar); override;
    public
      AuthCode:string;

      constructor Create; override;
  end;


  { TBigFileLHTTPServerComponent }

  TBigFileLHTTPServerComponent=class(TLHTTPServerComponent)
    public
      constructor Create(aOwner: TComponent); override;
  end;

  procedure GetIPAddr(var buf: array of char; const len: longint);


implementation

uses lMimeTypes,lHTTPUtil,FileUtil,lStrBuffer,base64;

resourcestring
  rsHtmlBodyPUpl = '<html><body><p>Uploaded</p><br/><a href="/%s">back</a></'
    +'body></html>';
  rsHtmlBodyPFol = '<html><body><p>Folder creation done.</p><br/><a href="/%s"'
    +'>back</a></body></html>';
  rsHtmlBodyPFolFail = '<html><body><p>Folder creation fail.</p><br/><a href="/%s'
    +'">back</a></body></html>';

const
  {$ifdef UNIX}
  allfiles='*';
  {$else}
  allfiles='*.*';
  {$endif}

{ TBigFileLHTTPServerComponent }

constructor TBigFileLHTTPServerComponent.Create(aOwner: TComponent);
begin
  inherited Create(aOwner);
  SocketClass:=TBigFileLHttpServerSocket;
end;

{ TBigFileLHttpServerSocket }

procedure TBigFileLHttpServerSocket.ParseLine(pLineEnd: pchar);
begin
  if FBufferPos[0]<>#0 then begin
    if pLineEnd-FBufferPos>=21 then
      if strlicomp(FBufferPos,'Authorization: Basic ',21)=0 then
        AuthCode:=FBufferPos+21;
  end;
  inherited ParseLine(pLineEnd);
end;

constructor TBigFileLHttpServerSocket.Create;
begin
  inherited Create;
  AuthCode:='';
end;

{ TBigFileOutput }

function TBigFileOutput.Getsize: int64;
begin
  if FFileStream<>nil then
    Result:=FFileStream.Size
    else
      Result:=0;
end;

function TBigFileOutput.FillBuffer: TWriteBlockStatus;
var
  lRead, RAmount: integer;
begin
  if FFileStream.Position>=FFileStream.Size then
    exit(wsDone);
  if (StartPos>0) and (FFileStream.Position<StartPos) then
    FFileStream.Seek(StartPos,soBeginning);
  if (EndPos>0) and (FFileStream.Position>EndPos) then
    exit(wsDone);
  RAmount:=FBufferSize-FBufferPos;
  if (EndPos>0) and (RAmount>(EndPos-FFileStream.Position+1)) then
    RAmount:=EndPos-FFileStream.Position+1;
  lRead:=FFileStream.Read(FBuffer[FBufferPos],RAmount);
  Inc(FBufferPos, lRead);
  if lRead = 0 then
  begin
    { EOF reached }
    if FFileStream<>nil then
      FreeAndNil(FFileStream);
    exit(wsDone);
  end;
  Result := wsPendingData;
end;

function TBigFileOutput.Open(const AFilename: string): Boolean;
begin
  Result:=False;
  try
    FFileStream:=TFileStream.Create(AFilename,fmOpenRead or fmShareDenyWrite);
    Result:=True;
  except
    on e:Exception do begin
      if FFileStream<>nil then
        FreeAndNil(FFileStream);
      LogError(e.Message);
    end;
  end;
end;

constructor TBigFileOutput.Create(ASocket: TLHTTPSocket);
begin
  inherited;
  FFileStream:=nil;
  StartPos:=0;
  EndPos:=0;
end;

destructor TBigFileOutput.Destroy;
begin
  if FFileStream<>nil then
    FreeAndNil(FFileStream);
  inherited Destroy;
end;

{ TBigStreamOutput }

function TBigStreamOutput.HandleInput(ABuffer: pchar; ASize: integer): integer;
begin
  if Assigned(FOnHandleInput) then begin
    Result:=FOnHandleInput(ABuffer,ASize);
    end else
      Result:=ASize;
end;

function TBigStreamOutput.PostHandleInput(ABuffer: pchar; ASize: integer
  ): integer;
var
  head,tail,endp,poswork:PAnsiChar;

  function AppendLine(var p:PAnsiChar; ep:PAnsiChar):string;
  begin
    Result:='';
    IncNext:=2;
    while p<ep do begin
      if not (p^ in [#13,#10]) then
        Result:=Result+p^
        else begin
          if p^<>#10 then begin
            Inc(p);
            if p=ep then
              IncNext:=1
              else
                IncNext:=0;
          end;
          Inc(p);
          break;
        end;
      Inc(p);
    end;
  end;

  procedure GetNewFileName;
  var
    temp: string;
    j: Integer;
    i: Integer;
  begin
    temp:=LowerCase(bHeader);
    i:=Pos('filename=',temp);
    if i>0 then begin
      inc(i,9);
      if temp[i]='"' then begin
        Inc(i);
        j:=i;
        while j<=Length(temp) do begin
          if temp[j]='"' then begin
            bFilename:=Utf8ToAnsi(Copy(bHeader,i,j-i));
            break;
          end;
          Inc(j);
        end;
      end else begin
        j:=i;
        while j<=Length(temp) do begin
          if temp[j]<#32 then begin
            bFilename:=Copy(bHeader,i,j-i);
            break;
          end;
          Inc(j);
        end;
      end;
    end;
  end;

begin
  system.Move(ABuffer^,(bBuffer+bRemain)^,ASize);
  endp:=bBuffer+ASize+bRemain;
  if IncNext>1 then begin
    poswork:=bBuffer;
  end else begin
    poswork:=bBuffer+IncNext;
  end;
  Result:=ASize;

  if InHeader then begin
     InHeader:=False;
     // check previous null line
     if (IncNext<>1) or (bHeader<>'') then begin
       // read header
       repeat
        if IncNext>1 then
          bHeader:=bHeader+AppendLine(poswork,endp)
          else
            bHeader:=AppendLine(poswork,endp);
        if (IncNext<2) and (bHeader<>'') then
          GetNewFileName;
        // need more
        if IncNext<>0 then begin
          InHeader:=True;
          bRemain:=0;
          exit;
        end;
       until bHeader='';
     end else
        IncNext:=0;
     // open file
     head:=poswork;
     try
       if OutFile<>nil then begin
         FreeAndNil(OutFile);
         RenameFile(tFilename,MakeNewFilename(oFilename));
       end;

       if bFilename<>'' then begin
         oFilename:=bFilename;
         tFilename:=MakeTempFilename(oFilename);
         OutFile:=TFileStream.Create(tFilename,fmCreate or fmOpenWrite or fmShareDenyWrite);
       end;
     except
       if OutFile<>nil then
         FreeAndNil(OutFile);
       LogError(Format('Error in creating file: %s',[UploadFolder+bFilename]));
       Socket.Disconnect(True);
       exit;
     end;
  end;

  while poswork<endp do begin
    head:=poswork;
    FindText.ClearPosition;
    FindText.FindKMP(poswork,endp-poswork,nil,0);
    if FindText.Position[0,0]<>-1 then begin
      // save previous file data
      if OutFile<>nil then begin
        tail:=poswork+FindText.Position[0,0]-2;
        try
          OutFile.Write(poswork^,tail-poswork);
        except
          on e:Exception do begin
            LogError(e.Message);
            Socket.Disconnect(True);
            exit;
          end;
        end;
      end;
      Inc(poswork,FindText.Position[0,0]+BSL);
      // start new file header
      bFilename:='';
      repeat
        bHeader:=AppendLine(poswork,endp);
       if (IncNext<2) and (bHeader<>'') then
         GetNewFileName;
        if IncNext<>0 then begin
          bRemain:=0;
          InHeader:=True;
          exit;
        end;
      until bHeader='';
      head:=poswork;
      try
        if OutFile<>nil then begin
          FreeAndNil(OutFile);
          RenameFile(tFilename,MakeNewFilename(oFilename));
        end;

        if bFilename<>'' then begin
          oFilename:=bFilename;
          tFilename:=MakeTempFilename(oFilename);
          OutFile:=TFileStream.Create(tFilename,fmCreate or fmOpenWrite or fmShareDenyWrite);
        end;
      except
        if OutFile<>nil then
          FreeAndNil(OutFile);
        LogError(Format('Cannot Create File: %s',[UploadFolder+bFilename]));
        Socket.Disconnect(True);
        exit;
      end;
    end else
    if FindText.Position[1,0]<>-1 then begin
      tail:=poswork+FindText.Position[1,0]-2;
      try
        if OutFile<>nil then begin
          OutFile.Write(head^,tail-head);
          FreeAndNil(OutFile);
          RenameFile(tFilename,MakeNewFilename(oFilename));
        end;
      except
        on e:Exception do begin
          if OutFile<>nil then
            FreeAndNil(OutFile);
          LogError(e.Message);
          Socket.Disconnect(True);
          exit;
        end;
      end;
      poswork:=tail+BEL+4;
    end else begin
      tail:=endp-(BEL+4);
      if tail<=poswork then begin
        tail:=poswork;
      end else
      begin
        try
          if OutFile<>nil then
            OutFile.Write(poswork^,tail-poswork);
        except
          on e:Exception do begin
            LogError(e.Message);
            Socket.Disconnect(True);
            exit;
          end;
        end;
      end;
      bRemain:=endp-tail;
      if bRemain>0 then
        system.Move(tail^,bBuffer^,bRemain);
      poswork:=endp;
    end;
  end;
end;

function TBigStreamOutput.MakeTempFilename(filename: string): string;
var
  i:integer;
  nfile,ext:string;
begin
  Result:=UploadFolder+filename+'.tmp';
  nfile:=ExtractFileNameWithoutExt(filename);
  ext:=ExtractFileExt(filename);
  i:=0;
  while FileExists(Result) do begin
    Result:=UploadFolder+nfile+'('+IntToStr(i)+')'+ext+'.tmp';
    Inc(i);
    if i>99999 then
      break;
  end;
end;

function TBigStreamOutput.MakeNewFilename(filename: string): string;
var
  i:integer;
  nfile,ext:string;
begin
  Result:=UploadFolder+filename;
  nfile:=ExtractFileNameWithoutExt(filename);
  ext:=ExtractFileExt(filename);
  i:=0;
  while FileExists(Result) do begin
    Result:=UploadFolder+nfile+'('+IntToStr(i)+')'+ext;
    Inc(i);
    if i>99999 then
      break;
  end;
end;

procedure TBigStreamOutput.SetBoundary(b: string);
begin
  bRemain:=0;
  Boundary:=b;
  BS:='--'+b+#13#10;
  BE:='--'+b+'--';
  BSL:=Length(BS);
  BEL:=Length(BE);
  IncNext:=0;
  InHeader:=False;
  bHeader:='';
  bFilename:='';
  FindText.AddScanStr(PAnsiChar(BS),Length(BS),False,False,False);
  FindText.AddScanStr(PAnsiChar(BE),Length(BE),False,False,False);
end;

procedure TBigStreamOutput.DoneInput;
var
  mStream:TMemoryOutput;
begin
  if OutFile<>nil then begin
    FreeAndNil(OutFile);
  end;

  MStream:=TMemoryOutput.Create(Socket,TMemoryStream(FStream).Memory,0,TMemoryStream(FStream).Size,False);
  TLHTTPServerSocket(Socket).StartMemoryResponse(MStream);
end;

constructor TBigStreamOutput.Create(ASocket: TLHTTPSocket; AStream: TStream;
  AFreeStream: boolean);
begin
  FOnHandleInput:=nil;
  OutFile:=nil;
  inherited Create(ASocket,AStream,AFreeStream);
  GetMem(bBuffer,FBufferMemSize+128);
  FindText:=TDWKMPScan.Create;
end;

destructor TBigStreamOutput.Destroy;
begin
  if OutFile<>nil then
    FreeAndNil(OutFile);
  Freemem(bBuffer);
  FindText.Free;
  inherited Destroy;
end;


{ TBigFileURIHandler }

procedure TBigFileURIHandler.SetAuthUser(const User: string);
begin
  if User<>FAuthUser then begin
    FAuthUser:=User;
    SetAuthUserPass(FAuthUser,FAuthPass);
  end;
end;

procedure TBigFileURIHandler.SetAuthPass(const Pass: string);
begin
  if Pass<>FAuthPass then begin
    FAuthPass:=Pass;
    SetAuthUserPass(FAuthUser,FAuthPass);
  end;
end;

procedure TBigFileURIHandler.SetAuthUserPass(const User, Pass: string);
begin
  FAuthBase64:=EncodeStringBase64(User+':'+Pass);
end;

function TBigFileURIHandler.HandleURI(ASocket: TLHTTPServerSocket): TOutputItem;
const
  uploadaction='upload.action.htm';
  folderaction='folder=';
var
  fstream:TBigFileOutput;
  srec:TSearchRec;
  outmsg:string;
  uri,urlstr:string;
  i,j:integer;
  contenttype:string;
  urifile:string;
  contentlength:int64;
  dummy:TMemoryStream;
  existdir:Boolean;
  rangeparam:pchar;
  lSize:int64;
  bOutStream:Boolean;

  function GetRangeLow(buf:pchar):string;
  var
    pos:pchar;
  begin
    Result:='';
    if buf<>nil then begin
      pos:=strscan(buf,'=');
      if pos<>nil then begin
        Inc(pos);
        while pos^<>'-' do begin
          if pos^=#0 then
            break;
          Result:=Result+pos^;
          Inc(pos);
        end;
      end;
    end;
  end;

  function GetRangeHigh(buf:pchar):string;
  var
    pos:pchar;
  begin
    Result:='';
    if buf<>nil then begin
      pos:=strscan(buf,'-');
      if pos<>nil then begin
        inc(pos);
        while pos^<>#0 do begin
          Result:=Result+pos^;
          Inc(pos);
        end;
      end;
    end;
  end;

  procedure ResposeMsg;
  var
    MessageOut:TStreamOutput;
    MemMsgOut:TMemoryOutput;
    msg:TMemoryStream;
  begin
    msg:=TMemoryStream.Create;
    msg.Write(outmsg[1],Length(outmsg));
    msg.Position:=0;
    MemMsgOut:=TMemoryOutput.Create(ASocket,msg.Memory,0,msg.Size,False);
    MessageOut:=TStreamOutput.Create(ASocket,msg,True);
    ASocket.FResponseInfo.ContentType:='text';
    ASocket.FHeaderOut.ContentLength:=msg.Size;
    ASocket.FResponseInfo.LastModified:=LocalTimeToGMT(Now);
    ASocket.StartMemoryResponse(MemMsgOut);
    Result:=MessageOut;
  end;

begin
  Result:=nil; // if you want process input data, must retuen TOutputItem and define Result.HandleInput
  uri:=pchar(Utf8ToAnsi(HTTPDecode(ASocket.FRequestInfo.Argument)));
  DoDirSeparators(uri);
  if ASocket.FRequestInfo.RequestType=hmHead then begin
    // HEAD get file size only.
    ASocket.FResponseInfo.LastModified:=LocalTimeToGMT(Now);
    if FileExists(DocRoot+uri) then begin
      lSize:=FileSize(DocRoot+uri);
      TLHTTPServerSocket(ASocket).SendMessage('HTTP/1.0 200 OK'+#13#10+'Accept-Ranges: bytes'+#13#10+
                                              Format('Content-Length: %d'+#13#10,[lSize])+#13#10);
      ASocket.Disconnect(True);
    end else begin
      ASocket.FResponseInfo.Status:=hsNotFound;
      ResposeMsg;
    end;
  end else
  if ASocket.FRequestInfo.RequestType=hmGet then begin
    // basic auth support
    if AuthEnable then begin
      if TBigFileLHttpServerSocket(ASocket).AuthCode<>AuthBase64 then begin
        ASocket.SendMessage('HTTP/1.1 401 Not Authorized'+#13#10+
                            'WWW-Authenticate: Basic realm="'+realm+'"'+#13#10+
                            'Content-Length: 15'+#13#10+#13#10+
                            'Not Authorized.');
        ASocket.Disconnect(True);
        exit;
      end;
    end;

    existdir:=DirectoryExists(DocRoot+uri);
    // index file
    if existdir and (IndexFile<>'') then begin
      urifile:=uri;
      if uri<>'' then
        urifile:=uri+PathDelim;
      urifile:=urifile+IndexFile;
      if FileExists(DocRoot+urifile) then
        uri:=urifile;
    end;

    { must process directory first in linux.
      fileexist return true at directory. }
    if DirectoryExists(DocRoot+uri) then begin
      if existdir or (uri='') then begin
        // list directory
        if (uri<>'') and (uri[Length(uri)]<>PathDelim) then begin
          uri:=uri+PathDelim;
          urlstr:=StringReplace(uri,PathDelim,'/',[rfReplaceAll]);
          urlstr:=pchar(HTTPEncode(AnsiToUtf8(urlstr)));
          urlstr:=StringReplace(urlstr,'%2F','/',[rfIgnoreCase,rfReplaceAll]);
        end;
        outmsg:='<html><head><meta http-equiv="Content-Type" content="text/html; charset=utf-8">'+
                '</head><body><div><form name="file" method="post" action="/'+urlstr+uploadaction+'" enctype="multipart/form-data">'+
                '<input type="file" name="fileupload"><input type="submit" value="send">'+
                '<input name="MAX_FILE_SIZE" value="'+IntToStr(UploadLimit)+'" type="hidden" /></form></div><p><hr /></p><div>';
        i:=FindFirst(DocRoot+uri+allfiles,faAnyFile,srec);
        if i{$ifdef WINDOWS}=0{$else}<>-1{$endif} then begin
          repeat
            if (srec.Attr and faDirectory)<>faDirectory then begin
              contenttype:=pchar(AnsiToUtf8(srec.Name));
              outmsg:=outmsg+Format('<br/><a href="/%s%s">%s</a>',[urlstr,HTTPEncode(contenttype),contenttype]);
            end else begin
              if (srec.Name<>'.') and (srec.Name<>'..') then begin
                contenttype:=pchar(AnsiToUtf8(srec.Name));
                outmsg:=outmsg+Format('<br/><a href="/%s%s">%s/</a>',[urlstr,HTTPEncode(contenttype),contenttype]);
              end;
            end;
          until FindNext(srec){$ifdef WINDOWS}<>0{$else}=-1{$endif};
          FindClose(srec);
        end;
        outmsg:=outmsg+'</div></body></html>';
        ASocket.FResponseInfo.Status:=hsOK;
      end else begin
        // not found
        outmsg:='File not found.';
        ASocket.FResponseInfo.Status:=hsNotFound;
      end;
      ResposeMsg;
    end else
    // process files
    if FileExists(DocRoot+uri) then begin
      // Send File
      fstream:=TBigFileOutput.Create(ASocket);
      try
        if fstream.Open(DocRoot+uri) then begin
          bOutStream:=True;
          lSize:=fstream.Size;
          rangeparam:=ASocket.Parameters[hpRange];
          if rangeparam<>nil then begin
            // range
            urifile:=GetRangeLow(rangeparam);
            if urifile='' then begin
              urifile:=GetRangeHigh(rangeparam);
              fstream.StartPos:=lSize-StrToInt64Def(urifile,0);
              if fstream.StartPos<0 then
                fstream.StartPos:=lSize;
              fstream.EndPos:=lSize-1;
            end else begin
              fstream.StartPos:=StrToInt64Def(urifile,0);
              fstream.EndPos:=StrToInt64Def(GetRangeHigh(rangeparam),lSize-1);
            end;
            if (fstream.StartPos>fstream.EndPos) or (fstream.StartPos>=lSize)
                or (fstream.EndPos>=lSize) then
                  bOutStream:=False
                    else begin
                  AppendString(ASocket.FHeaderOut.ExtraHeaders,Format('Content-Length: %d'+#13#10,[fstream.EndPos-fstream.StartPos+1]));
                  AppendString(ASocket.FHeaderOut.ExtraHeaders,Format('Content-Range: bytes %d-%d/%d'+#13#10,[fstream.StartPos,fstream.EndPos,lSize]));
                  AppendString(ASocket.FHeaderOut.ExtraHeaders,'Accept-Ranges: bytes'+#13#10);
                  ASocket.FResponseInfo.Status:=hsPartialContent;
                    end;
          end else begin
            // full
            AppendString(ASocket.FHeaderOut.ExtraHeaders,Format('Content-Length: %d'+#13#10,[lSize]));
            AppendString(ASocket.FHeaderOut.ExtraHeaders,Format('Content-Range: bytes %d-%d/%d'+#13#10,[0,lSize-1,lSize]));
            ASocket.FResponseInfo.Status:=hsOK;
          end;
          if bOutStream then begin
            // send file
            i:=MimeList.IndexOf(LowerCase(ExtractFileExt(uri)));
            if i<>-1 then begin
              ASocket.FResponseInfo.ContentType:=TStringObject(MimeList.Objects[i]).Str;
              // multimedia support
              urifile:=Copy(ASocket.FResponseInfo.ContentType,1,5);
              if (CompareText(urifile,'video')=0) or (CompareText(urifile,'audio')=0) then
                ASocket.FResponseInfo.Status:=hsPartialContent;
            end;
            ASocket.StartResponse(fstream,True);
            Result:=fstream;
          end else begin
            // error message
            ASocket.FResponseInfo.Status:=hsBadRequest;
            outmsg:='Bad request';
            ResposeMsg;
          end;
        end else begin
          outmsg:='File cannot accessible.';
          ASocket.FResponseInfo.Status:=hsInternalError;
          ResposeMsg;
        end;
      except
        on e:Exception do begin
          Result:=nil;
          fstream.LogError(e.Message);
          fstream.Free;
        end;
      end;
    end else
    begin
      // folder creation
      // check upload action url
      i:=Pos(uploadaction,uri);
      if i>0 then begin
        // get parameter processing here
        // get create folder
        urifile:=ASocket.FRequestInfo.QueryParams;
        i:=Pos(folderaction,ASocket.FRequestInfo.QueryParams);
        if i>0 then begin
          j:=i+length(folderaction);
          // get folder name from query
          while j<=Length(urifile) do begin
            if urifile[j]='&' then
              break;
            Inc(j);
          end;
          urifile:=Utf8ToAnsi(HTTPDecode(Copy(urifile,i+length(folderaction),j-i-length(folderaction))));
          // get folder name
          i:=Pos(uploadaction,uri);
          if i>0 then
            urlstr:=Copy(uri,1,i-1)
            else
              urlstr:='';
          urifile:=DocRoot+urlstr+urifile;
          if (i>0) and (not DirectoryExists(urifile)) then
            if not CreateDir(urifile) then
              i:=0;
          // response return address
          if urlstr<>'' then
            Delete(urlstr,Length(urlstr),1);
          if urlstr<>'' then begin
            urlstr:=HTTPEncode(AnsiToUtf8(StringReplace(urlstr,PathDelim,'/',[rfReplaceAll])));
            urlstr:=StringReplace(urlstr,'%2F','/',[rfReplaceAll,rfIgnoreCase]);
          end;
          // response
          if i>0 then begin
            outmsg:=Format(rsHtmlBodyPFol, [pchar(urlstr)]);
            ASocket.FResponseInfo.Status:=hsOK;
          end else begin
            outmsg:=Format(rsHtmlBodyPFolFail, [pchar(urlstr)]);
            ASocket.FResponseInfo.Status:=hsInternalError;
            i:=1;  // skip "file not found" error
          end;
        end;
      end;
      // no file or meta-file found
      if i=0 then begin
        outmsg:='File not found.';
        ASocket.FResponseInfo.Status:=hsNotFound;
      end;
      ResposeMsg;
    end;

  // process file posting
  end else if ASocket.FRequestInfo.RequestType=hmPost then begin
    contentlength:=StrToInt64Def(ASocket.Parameters[hpContentLength],0);

    dummy:=TMemoryStream.Create;
    Result:=TBigStreamOutput.Create(ASocket,dummy,True);
    ASocket.FResponseInfo.ContentType:='text';
    // get upload folder
    i:=Pos(uploadaction,uri);
    if i>0 then
      urlstr:=Copy(uri,1,i-1)
      else
        urlstr:='';

    contenttype:=ASocket.Parameters[hpContentType];
    if strlicomp(pchar(contenttype),'multipart/form-data',19)=0 then begin
      // copy boundary value
      i:=Pos('=',contenttype);
      if i>0 then begin
        Inc(i);
        j:=Pos(#13#10,contenttype);
        if j=0 then
          j:=Length(contenttype)+1;
        outmsg:=copy(contenttype,i,j-i);
        TBigStreamOutput(Result).SetBoundary(outmsg);
        TBigStreamOutput(Result).UploadFolder:=DocRoot+urlstr;
        if contentlength>UploadLimit then begin
            // disconnect when bigger
            ASocket.Disconnect(True);
            TBigStreamOutput(Result).LogError(Format('%d Upload Limit',[UploadLimit]));
          end else
            TBigStreamOutput(Result).OnHandleInput:=@TBigStreamOutput(Result).PostHandleInput;
      end;
    end;
    // response
    if urlstr<>'' then
      Delete(urlstr,Length(urlstr),1);
    if urlstr<>'' then begin
      urlstr:=HTTPEncode(AnsiToUtf8(StringReplace(urlstr,PathDelim,'/',[rfReplaceAll])));
      urlstr:=StringReplace(urlstr,'%2F','/',[rfReplaceAll,rfIgnoreCase]);
    end;

    outmsg:=Format(rsHtmlBodyPUpl, [pchar(urlstr)]);
    dummy.Write(outmsg[1],Length(outmsg));
  end;
end;

constructor TBigFileURIHandler.Create;
begin
  inherited Create;

  AuthEnable:=False;
  UploadLimit:=1024*1024*1024;
  IndexFile:='index.html';

  realm:='lhttpFileServer';
  FAuthUser:='root';
  FAuthPass:='root';
  SetAuthUserPass(FAuthUser,FAuthPass);
end;

procedure GetIPAddr(var buf: array of char; const len: longint);
const
 CN_GDNS_ADDR = '127.0.0.1';
 CN_GDNS_PORT = 53;
var
 s: string;
 sock: longint;
 err: longint;
 HostAddr: TSockAddr;
 l: Integer;
 IPAddr: TInetSockAddr;

begin
 err := 0;
 Assert(len >= 16);

 sock := fpsocket(AF_INET, SOCK_DGRAM, 0);
 assert(sock <> -1);

 IPAddr.sin_family := AF_INET;
 IPAddr.sin_port := htons(CN_GDNS_PORT);
 IPAddr.sin_addr.s_addr := StrToHostAddr(CN_GDNS_ADDR).s_addr;

 if (fpConnect(sock,@IPAddr,SizeOf(IPAddr)) = 0) then
 begin
   try
     l := SizeOf(HostAddr);
     if (fpgetsockname(sock, @HostAddr, @l) = 0) then
     begin
       s := NetAddrToStr(HostAddr.sin_addr);
       StrPCopy(PChar(Buf), s);
     end
     else
     begin
       err:=socketError;
     end;
   finally
     if (CloseSocket(sock) <> 0) then
     begin
       err := socketError;
     end;
   end;
 end
 else
 begin
   err:=socketError;
 end;
end;

end.

