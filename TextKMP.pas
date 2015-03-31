unit TextKMP;

// KMP search algorithm delphi implementation
// by Do-wan Kim
// added MBCS or non-MBCS condition
// 2008.02.23
// add OnDoing event
// change File Scan to Stream Scan

// for fpc
// added position property

interface

uses classes;

type
  //
  TDWKMPScanRec = record
    sublen : integer;
    substr : pansichar;
    buftable : array of integer;           // KMP Shift
    position : array of integer;           // useless
    IgnoreCase : boolean;
    matchand : boolean;
    UseMBCS : boolean;
  end;
  pDWKMPScanRec = ^TDWKMPScanRec;
  //

  { TDWKMPScan }

  TDWKMPScan = class(TList)
    private
      FOnDoing : TNotifyEvent;  // added 2008.02
      procedure PreKMPText(item: pDWKMPScanRec; str: pansichar; len: integer);
      function GetItemScan(Idx : integer):pDWKMPScanRec;
      function GetItemPos(Idx,PosIdx:Integer):Integer;
    protected
      FileBuf : pansichar;
      MaxSubStrLen : integer;
      function AddPosition(p : pDWKMPScanRec; pos : integer):boolean;
      procedure Notify(Ptr: Pointer; Action: TListNotification); override;
    public
      AllMatches : boolean;
      constructor Create;
      destructor Destroy; override;
      procedure ClearPosition;
      procedure AddScanStr(str : pansichar; len : integer; ignorecase : boolean = true;
                            matchAnd : boolean = false; UseMBCS : boolean = true);
      function FindKMP(src : pansichar; len : integer; stopflag : PInteger; basePos : integer):boolean;
      function FindStream(Stream : TStream; stopflag : PInteger):boolean;
      property ItemScan[Idx : integer]:pDWKMPScanRec read GetItemScan;
      property OnDoing : TNotifyEvent read FOnDoing write FOnDoing; // added 2008.02
      property Position[Idx, PosIdx:Integer]:Integer read GetItemPos;
  end;

  function FindKMPStr(str, substr:string; IgnoreCase:Boolean=False; MBCS:Boolean=False):Integer;

implementation

uses sysutils;

const
  FileBufSize = 16384;

function CompareChar(ch1, ch2 : pansichar; idx1, idx2 : integer; ignorecase : boolean; UseMBCS : boolean):boolean;
var
  cht1, cht2 : char;
  uConv1, uConv2 : boolean;
begin
  cht1 := (ch1+idx1)^;
  cht2 := (ch2+idx2)^;
  if ignorecase then begin
    UConv1 := True;
    UConv2 := True;
    if UseMBCS then begin
      if idx1>0 then
        UConv1 := not (StrByteType(ch1,idx1-1)=mbLeadByte);
      if idx2>0 then
        UConv2 := not (StrByteType(ch2,idx2-1)=mbLeadByte);
    end;
    if uConv1 then cht1 := UpCase(cht1);
    if uConv2 then cht2 := UpCase(cht2);
  end;
  result := cht1 = cht2;
end;

function FindKMPStr(str, substr: string; IgnoreCase: Boolean; MBCS: Boolean
  ): Integer;
var
  KMP:TDWKMPScan;
begin
  KMP:=TDWKMPScan.Create;
  try
    KMP.AddScanStr(@substr[1],Length(substr),IgnoreCase,False,MBCS);
    if KMP.FindKMP(@str[1],Length(str),nil,0) then
      Result:=KMP.Position[0,0];
  finally
    KMP.Free;
  end;
end;

constructor TDWKMPScan.Create;
begin
  inherited Create;
  MaxSubStrLen := 0;
  AllMatches := false;
end;

destructor TDWKMPScan.Destroy;
begin
  self.Clear;
  inherited destroy;
end;

(*
procedure TDWKMPScan.Clear;
var
  i : integer;
  p : pDWKMPScanRec;
begin
  i := self.Count;
  if i>0 then
    while i>0 do begin
      dec(i);
      p := pDWKMPScanRec(self.Items[i]);
      if p<>nil then begin
        if p^.substr <> nil then freemem(p^.substr,p^.sublen+1);
        SetLength(p^.buftable,0);
        SetLength(p^.position,0);
      end;
      dispose(p);
      self.Items[i] := nil;
    end;
  inherited Clear;
end;
*)

procedure TDWKMPScan.ClearPosition;
var
  i : integer;
  p : pDWKMPScanRec;
begin
  i := self.Count;
  if i>0 then
    while i>0 do begin
      dec(i);
      p := pDWKMPScanRec(self.Items[i]);
      if p<>nil then
        SetLength(p^.position,0);
    end;
end;

procedure TDWKMPScan.PreKMPText(item : pDWKMPScanRec; str : pansichar; len : integer);
var
  i, j : integer;
  strp : string;
  strpx : pansichar;
begin
  //
  setlength(item^.buftable,len+1);
  //
  setlength(strp,len);
  system.Move(str^,strp[1],len);
  // ignorecase with MBCS
  if item^.IgnoreCase then
    if len>0 then begin
      i := 1;
      while i<=len do begin
        if item^.UseMBCS then begin
            if ByteType(strp,i)<>mbLeadByte then
              strp[i]:=UpCase(strp[i])
              else
                inc(i);
        end else
          strp[i] := UpCase(strp[i]);
        inc(i);
      end;
    end;
  strpx := @strp[1];
  // preKMP
  i := 0;
  j := -1;
  item^.buftable[0]:=j;

  while i<len do begin
    while (j > -1) and not CompareChar(strpx,strpx,i,j,item^.IgnoreCase,item^.UseMBCS) do
      j := item^.buftable[j];
    inc(i);
    inc(j);
    if CompareChar(strpx,strpx,i,j,item^.IgnoreCase,item^.UseMBCS) then
      item^.buftable[i] := item^.buftable[j]
      else
        item^.buftable[i] := j;
  end;
end;


function TDWKMPScan.AddPosition(p : pDWKMPScanRec; pos: integer): boolean;
var
  ix : integer;
begin
  result := true;
  ix := length(p^.position);
  inc(ix);                          //
  SetLength(p^.position,ix);         // bug fix
  dec(ix);
  p^.position[ix] := pos;
end;

procedure TDWKMPScan.AddScanStr(str : pansichar; len : integer;
            ignorecase : boolean = true; matchAnd : boolean = false; UseMBCS : boolean = true);
var
  p : pDWKMPScanRec;
begin
  new(p);
  try
    if p<>nil then begin
      // init values
      // p^.position := -1;
      p^.sublen := 0;
      p^.substr := nil;
      p^.matchand := matchAnd;
      p^.UseMBCS := UseMBCS;
      p^.IgnoreCase := ignorecase;
      SetLength(p^.buftable,0);
      SetLength(p^.position,0);
      getmem(p^.substr,len+1);
      try
        if p^.substr<>nil then begin
          p^.sublen := len;
          if MaxSubStrLen<len then MaxSubStrLen := len;
          // copy string
          system.Move(str[0],p^.substr[0],len);
          p^.substr[len]:=#0;
          // make table
          PreKMPText(p,str,len);
          self.Add(p);
        end;
      except
        freemem(p^.substr,len);
        raise exception.Create('AddScanStr01');
      end;
    end;
  except
    dispose(p);
    raise exception.Create('AddScanStr00');
  end;
end;

function TDWKMPScan.FindKMP(src: pansichar; len: integer;
  stopflag: PInteger; basePos: integer): boolean;
var
  SrcPos, iloop, SubPos : integer;
  p : pDWKMPScanRec;
  bres : boolean;
begin
  result := false;
  for iloop := 0 to Count-1 do begin
    bres :=false;
    p := pDWKMPScanRec(self.Items[iloop]);
    if p<>nil then begin
      //
      SrcPos := 0;
      SubPos := 0;
      while(SrcPos<len) do begin
        while (SubPos > -1) and not CompareChar(p^.substr,src,SubPos,SrcPos,p^.IgnoreCase,p^.UseMBCS) do SubPos := p^.buftable[SubPos];
        inc(SubPos);
        inc(SrcPos);
        if SubPos>=p^.sublen then begin
          AddPosition(p,(SrcPos-SubPos) + BasePos);
          bres := true;
          if not AllMatches then break;
          // for continue search
          SubPos := p^.buftable[SubPos];
        end;
        if stopflag<>nil then
          if stopflag^<>0 then
            break;
      end;
    end;
    if stopflag<>nil then
      if stopflag^<>0 then
        break;
    if p^.matchand then begin
      if iloop=0 then result := true;
      result := result and bres;
    end else result := result or bres;
    if assigned(FOnDoing) then FOnDoing(Self);
  end;
  if stopflag<>nil then
    if stopflag^<>0 then
      result := false;
end;

function TDWKMPScan.GetItemScan(Idx: integer): pDWKMPScanRec;
begin
  Result := Items[Idx];
end;

function TDWKMPScan.GetItemPos(Idx, PosIdx: Integer): Integer;
var
  p:pDWKMPScanRec;
  l:integer;
begin
  Result:=-1;
  if (Idx<0) or (Idx>=Count) then
    exit;
  p:=pDWKMPScanRec(Items[Idx]);
  l:=Length(p^.position);
  if (PosIdx<0) or (PosIdx>=l) then
    exit;
  Result:=p^.position[PosIdx];
end;

procedure TDWKMPScan.Notify(Ptr: Pointer; Action: TListNotification);
var
  p : pDWKMPScanRec;
begin
  if Action <> lnAdded then begin
      p := pDWKMPScanRec(Ptr);
      if p<>nil then begin
        if p^.substr <> nil then
          freemem(p^.substr,p^.sublen+1);
        SetLength(p^.buftable,0);
        SetLength(p^.position,0);
        dispose(p);
      end;
  end;
end;

function TDWKMPScan.FindStream(Stream : TStream; stopflag : PInteger): boolean;
var
  fLastread, fReadSize, FBase : integer;
begin
{$I-}
  result := false;
  getmem(self.FileBuf,FileBufSize);
  try
    if self.FileBuf <> nil then begin
        FBase :=0;
        fReadSize := FileBufSize - self.MaxSubStrLen;
        fLastRead := Stream.Read(self.FileBuf[0],FileBufSize);
        while fLastRead>0 do begin
          if FindKMP(FileBuf,fLastRead,stopflag,FBase) then begin
            result := true;
            break;
          end;
          if fLastRead=FileBufSize then begin
            system.Move(self.FileBuf[fReadSize],self.FileBuf[0],self.MaxSubStrLen);
            fLastRead := Stream.Read(filebuf[self.MaxSubStrLen],fReadSize);
            if fLastRead>0 then
              inc(fLastRead,self.MaxSubStrLen);
          end else fLastRead := 0;
          inc(FBase,fReadSize);
          if stopflag<>nil then
            if stopflag^<>0 then
              break;
        end;
    end;
  finally
    if self.FileBuf<>nil then
      freemem(self.FileBuf,FileBufSize);
  end;
end;

end.
