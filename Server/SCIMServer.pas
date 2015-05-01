unit SCIMServer;

interface

uses
  SysUtils, Classes, System.Generics.Collections,
  IdContext, IdCustomHTTPServer, IdHashSHA,
  DCPsha256, ParseMap, TextUtilities,
  KDBManager, AdvJSON, KCritSct, DateAndTime,
  StringSupport, EncodeSupport,  FHIRSupport,
  AdvObjects, AdvObjectLists,
  SCIMSearch, SCIMObjects;

Const
  SCIM_ANONYMOUS_USER = 'ANONYMOUS';
  SCIM_SYSTEM_USER = 'SYSTEM';

Type
  TProcessFileEvent = procedure (response : TIdHTTPResponseInfo; session : TFhirSession; named, path : String; secure : boolean; variables: TDictionary<String, String> = nil) of Object;

  TSCIMCharIssuer = class (TAdvObject)
  private
    cursor : char;
  public
    constructor Create; override;
    function next : char;
  end;

  TSCIMServer = class (TAdvObject)
  private
    db : TKDBManager;
    lock : TCriticalSection;
    lastUserKey : integer;
    lastUserIndexKey : integer;
    salt : String;
    host : String;
    FAnonymousRights : TStringList;
    FOnProcessFile : TProcessFileEvent;
    FFilePath : String;


    function GetNextUserKey : Integer;
    function GetNextUserIndexKey : Integer;
    function HashPassword(uk : integer; pw : String):String;
    function BuildUserFilter(filter : TSCIMSearchFilter; prefix : String; parent : char; issuer : TSCIMCharIssuer) : String;
    function BuildUserFilterTest(filter : TSCIMSearchFilterTest; prefix : String; parent : char; issuer : TSCIMCharIssuer) : String;
    function BuildUserFilterCriteria(filter : TSCIMSearchFilterCriteria; prefix : String; parent : char; issuer : TSCIMCharIssuer) : String;
    function BuildUserFilterValuePath(filter : TSCIMSearchFilterValuePath; prefix : String; parent : char; issuer : TSCIMCharIssuer) : String;

    function RecogniseUserAttribute(path : String) : String;
    procedure IndexUser(conn : TKDBConnection; user : TSCIMUser; userKey : integer);

    function LoadIncoming(request: TIdHTTPRequestInfo) : TJsonObject;
    procedure WriteOutgoing(response: TIdHTTPResponseInfo; json : TJsonObject);
    function ProcessUserFilter(filter : String) : String;

    procedure EncodeErrorResponse(response: TIdHTTPResponseInfo; status : Integer; statusCode : String; scimType : String; message : String);

    Procedure processUserGet(context: TIdContext; request: TIdHTTPRequestInfo; response: TIdHTTPResponseInfo);
    Procedure processUserQuery(context: TIdContext; request: TIdHTTPRequestInfo; response: TIdHTTPResponseInfo);
    Procedure processUserPost(context: TIdContext; request: TIdHTTPRequestInfo; response: TIdHTTPResponseInfo);
    Procedure processUserPut(context: TIdContext; request: TIdHTTPRequestInfo; response: TIdHTTPResponseInfo);
    Procedure processUserDelete(context: TIdContext; request: TIdHTTPRequestInfo; response: TIdHTTPResponseInfo);
    Procedure processUserRequest(context: TIdContext; request: TIdHTTPRequestInfo; response: TIdHTTPResponseInfo);

    Procedure processWebRequest(context: TIdContext; session : TFhirSession; request: TIdHTTPRequestInfo; response: TIdHTTPResponseInfo);
    function AltFile(path: String): String;
    procedure processWebUserList(context: TIdContext; session : TFhirSession; request: TIdHTTPRequestInfo; response: TIdHTTPResponseInfo);
    procedure processWebUserId(context: TIdContext; session : TFhirSession; request: TIdHTTPRequestInfo; response: TIdHTTPResponseInfo);
  public
    Constructor Create(db : TKDBManager; filePath, salt, host, defaultRights : String; forInstall : boolean);
    Destructor Destroy; override;
    Function Link : TSCIMServer; overload;

    Procedure processRequest(context: TIdContext; request: TIdHTTPRequestInfo; response: TIdHTTPResponseInfo; session : TFHIRSession);
    Function loadUser(id : String) : TSCIMUser;
    function loadOrCreateUser(id, name, email : String) : TSCIMUser;
    function CheckLogin(username, password : String) : boolean;

    // install
    Procedure DefineSystem(conn : TKDBConnection);
    Procedure DefineAdminUser(conn : TKDBConnection; un, pw, em : String);
    Procedure DefineAnonymousUser(conn : TKDBConnection);

    property AnonymousRights : TStringList read FAnonymousRights;
    property OnProcessFile : TProcessFileEvent read FOnProcessFile write FOnProcessFile;
  end;


implementation

uses
  FHIRSecurity;

{ TSCIMServer }

function TSCIMServer.CheckLogin(username, password: String): boolean;
var
  conn : TKDBConnection;
begin
  conn := db.GetConnection('scim.checkpassword');
  try
    conn.SQL := 'Select UserKey, Password from Users where Status = 1 and UserName = '''+SQLWrapString(username)+'''';
    conn.Prepare;
    try
      conn.Execute;
      if not conn.FetchNext then
        result := false
      else
        result := HashPassword(conn.ColIntegerByName['UserKey'], password) = conn.ColStringByName['Password'];
    finally
      conn.Terminate;
    end;
    conn.Release;
  except
    on e:Exception do
    begin
      conn.Error(e);
      raise;
    end;
  end;
end;

constructor TSCIMServer.Create(db: TKDBManager; filePath, salt, host, defaultRights : String; forInstall : boolean);
var
  conn : TKDBConnection;
  s : String;
begin
  Inherited Create;
  self.db := db;
  self.salt := salt;
  self.host := host;
  FAnonymousRights := TStringList.Create;
  for s in defaultRights.split([',']) do
    FAnonymousRights.add(UriForScope(s));
  FFilePath := filePath;
  lock := TCriticalSection.Create('scim');

  if not forInstall then
  begin
    conn := db.GetConnection('scim.load');
    try
      lastUserKey := conn.CountSQL('select Max(UserKey) from Users');
      lastUserIndexKey := conn.CountSQL('select Max(UserIndexKey) from UserIndexes');
      conn.Release;
    except
      on e:Exception do
      begin
        conn.Error(e);
        raise;
      end;
    end;
  end;
end;

procedure TSCIMServer.DefineAdminUser(conn : TKDBConnection; un, pw, em: String);
var
  now : TDateAndTime;
  user : TSCIMUser;
  key : integer;
  list : TStringList;
  s : String;
begin
  now := NowUTC;
  user := TSCIMUser.Create(TJsonObject.create);
  try
    user.username := un;
    user.addEmail('em', 'work').Primary := true;

    user.check;

    key := GetNextUserKey;
    user.id := inttostr(key);
    user.created := now.Link;
    user.lastModified := now.Link;
    user.location := 'https://'+host+'/scim/Users/'+inttostr(key);
    user.version := '1';
    user.resourceType := 'User';
    user.addEntitlement(SCIM_ADMINISTRATOR);
    list := TFHIRSecurityRights.allScopesAsUris;
    try
      for s in list do
        user.addEntitlement(s);
    finally
      list.Free;
    end;

    if conn.CountSQL('select UserKey from Users where Status = 1 and UserName = '''+SQLWrapString(un)+'''') > 0 then
      raise ESCIMException.Create(400, 'BAD REQUEST', 'mutability', 'Duplicate User name');
    conn.SQL := 'Insert into Users (UserKey, UserName, Password, Status, Content) values (:uk, :un, :pw, 1, :cnt)';
    conn.Prepare;
    try
      conn.BindInteger('uk', key);
      conn.BindString('un', un);
      conn.BindString('pw', HashPassword(key, pw));
      conn.BindBlobFromBytes('cnt', TJSONWriter.writeObject(user.json, false));
      conn.Execute;
    finally
      conn.Terminate;
    end;
    IndexUser(conn, user, key);

  finally
    user.Free;
    now.Free;
  end;
end;

procedure TSCIMServer.DefineSystem(conn : TKDBConnection);
var
  now : TDateAndTime;
  user : TSCIMUser;
  key : integer;
  list : TStringList;
  s : String;
begin
  now := NowUTC;
  user := TSCIMUser.Create(TJsonObject.create);
  try
    user.username := SCIM_SYSTEM_USER;
    user.check;

    key := GetNextUserKey;
    assert(key = 1);
    user.id := inttostr(key);
    user.created := now.Link;
    user.lastModified := now.Link;
    user.location := 'https://'+host+'/scim/Users/'+inttostr(key);
    user.version := '1';
    user.resourceType := 'User';
    list := TFHIRSecurityRights.allScopesAsUris;
    try
      for s in list do
        user.addEntitlement(s);
    finally
      list.Free;
    end;

    conn.SQL := 'Insert into Users (UserKey, UserName, Password, Status, Content) values (:uk, :un, :pw, 1, :cnt)';
    conn.Prepare;
    try
      conn.BindInteger('uk', key);
      conn.BindString('un', user.username);
      conn.BindNull('pw');
      conn.BindBlobFromBytes('cnt', TJSONWriter.writeObject(user.json, false));
      conn.Execute;
    finally
      conn.Terminate;
    end;
    IndexUser(conn, user, key);
  finally
    user.Free;
    now.Free;
  end;
end;

procedure TSCIMServer.DefineAnonymousUser(conn : TKDBConnection);
var
  now : TDateAndTime;
  user : TSCIMUser;
  key : integer;
  list : TStringList;
  s : String;
begin
  now := NowUTC;
  user := TSCIMUser.Create(TJsonObject.create);
  try
    user.username := SCIM_ANONYMOUS_USER;
    user.check;

    key := GetNextUserKey;
    user.id := inttostr(key);
    user.created := now.Link;
    user.lastModified := now.Link;
    user.location := 'https://'+host+'/scim/Users/'+inttostr(key);
    user.version := '1';
    user.resourceType := 'User';
    for s in AnonymousRights do
      user.addEntitlement(s);

    conn.SQL := 'Insert into Users (UserKey, UserName, Password, Status, Content) values (:uk, :un, :pw, 1, :cnt)';
    conn.Prepare;
    try
      conn.BindInteger('uk', key);
      conn.BindString('un', user.username);
      conn.BindNull('pw');
      conn.BindBlobFromBytes('cnt', TJSONWriter.writeObject(user.json, false));
      conn.Execute;
    finally
      conn.Terminate;
    end;
    IndexUser(conn, user, key);
  finally
    user.Free;
    now.Free;
  end;
end;

destructor TSCIMServer.Destroy;
begin
  lock.Free;
  FAnonymousRights.Free;
  inherited;
end;

procedure TSCIMServer.EncodeErrorResponse(response: TIdHTTPResponseInfo; status: Integer; statusCode, scimType, message: String);
var
  json : TJsonObject;
begin
  json := TJsonObject.Create;
  try
    json['status'] := inttostr(status);
    if scimType <> '' then
      json['scimType'] := scimType;
    json['detail'] := message;
    WriteOutgoing(response, json);
    response.ResponseNo := status;
    response.ResponseText := statusCode;
  finally
    json.Free;
  end;
end;

function TSCIMServer.GetNextUserKey: Integer;
begin
  lock.Lock;
  try
    inc(lastUserkey);
    result := lastUserkey;
  finally
    lock.Unlock;
  end;
end;

function TSCIMServer.GetNextUserIndexKey: Integer;
begin
  lock.Lock;
  try
    inc(lastUserIndexKey);
    result := lastUserIndexKey;
  finally
    lock.Unlock;
  end;
end;

function TSCIMServer.HashPassword(uk : integer; pw: String): String;
var
  hash : TDCP_sha256;
  res : TBytes;
begin
  result := '';
  hash := TDCP_sha256.Create(nil);
  try
    hash.Init;
    hash.UpdateStr(inttostr(uk)+salt+pw);
    SetLength(res, hash.GetHashSize div 8);
    hash.Final(res[0]);
  finally
    hash.free;
  end;
  result := String(EncodeHexadecimal(res));
end;


function TSCIMServer.Link: TSCIMServer;
begin
  result := TSCIMServer(Inherited Link);
end;

function TSCIMServer.LoadIncoming(request: TIdHTTPRequestInfo): TJsonObject;
begin
  if request.ContentType <> 'application/scim+json' then
    raise ESCIMException.Create(400, 'BAD REQUEST', 'invalidSyntax', 'Unknown Content Type : '+request.ContentType);
  result := TJSONParser.Parse(request.PostStream);
end;

function TSCIMServer.loadOrCreateUser(id, name, email: String): TSCIMUser;
var
  conn : TKDBConnection;
  new, upd : boolean;
  now : TDateAndTime;
  key : integer;
  s : String;
begin
  upd := false;
  key := 0;
  conn := db.GetConnection('scim.loadOrCreateUser');
  try
    if id = SCIM_ANONYMOUS_User then
      conn.SQL := 'Select Content from Users where Status = 1 and UserKey = 1'
    else
      conn.SQL := 'Select Content from Users where Status = 1 and UserName = '''+SQLWrapString(id)+'''';

    conn.Prepare;
    result := nil;
    try
      conn.Execute;
      new := not conn.FetchNext;
      if not new then
        result := TSCIMUser.Create(TJSONParser.Parse(conn.ColBlobByName['Content']))
      else
      begin
        result := TSCIMUser.Create(TJsonObject.Create);
        result.ExternalId := id;
      end;

      if result.username <> name then
      begin
        upd := true;
        result.username := name;
      end;
      if result.formattedName <> name then
      begin
        upd := true;
        result.formattedName := name;
      End;

      if result.DisplayName <> name then
      begin
        upd := true;
        result.DisplayName := name;
      end;

      if (email <> '') and not result.hasEmail(email) then
      begin
        result.AddEmail(email, '');
        upd := true;
      end;

      if new or upd then
      begin
        now := NowUTC;
        try
          if new then
          begin
            key := GetNextUserKey;
            result.id := inttostr(key);
            result.created := now.Link;
            result.location := 'https://'+Host+'/scim/Users/'+inttostr(key);
            result.version := '1';
            result.resourceType := 'User';
            for s in AnonymousRights do
              result.addEntitlement(s);
          end
          else
            result.Version := inttostr(StrToInT(result.version)+1);
          result.lastModified := now.Link;

          conn.StartTransact;
          try
            if new then
              conn.SQL := 'Insert into Users (UserKey, UserName, Status, Content) values (:uk, :un, 1, :cnt)'
            else
              conn.SQL := 'Update Users set Content = :cnt where UserKey = :uk';
            conn.Prepare;
            try
              conn.BindInteger('uk', key);
              if new then
                conn.BindString('un', id);
              conn.BindBlobFromBytes('cnt', TJSONWriter.writeObject(result.json, false));
              conn.Execute;
            finally
              conn.Terminate;
            end;
            IndexUser(conn, result, key);
            conn.Commit;
          except
            conn.Rollback;
            raise;
          end;
        finally
          now.Free;
        end;
      end;

      result.Link;
    finally
      result.Free;
      conn.Terminate;
    end;
    conn.Release;
  except
    on e:Exception do
    begin
      conn.Error(e);
      raise;
    end;
  end;
end;

function TSCIMServer.loadUser(id: String): TSCIMUser;
var
  conn : TKDBConnection;
  s : String;
begin
  conn := db.GetConnection('scim.loadUser');
  try
    conn.SQL := 'Select Content from Users where Status = 1 and UserName = '''+SQLWrapString(id)+'''';
    conn.Prepare;
    try
      conn.Execute;
      if not conn.FetchNext then
        raise ESCIMException.Create(404, 'Not Found', '', 'User '+id+' not found');
      result := TSCIMUser.Create(TJSONParser.Parse(conn.ColBlobByName['Content']));
    finally
      conn.Terminate;
    end;
    conn.Release;
  except
    on e:Exception do
    begin
      conn.Error(e);
      raise;
    end;
  end;
end;

procedure TSCIMServer.processRequest(context: TIdContext; request: TIdHTTPRequestInfo; response: TIdHTTPResponseInfo; session : TFHIRSession);
var
  path : String;
begin
  try
    path := request.Document;
    if (path.StartsWith('/scim/Users')) then
      processUserRequest(context, request, response)
    else if (path.StartsWith('/scim/web')) then
      processWebRequest(context, session, request, response)
    else
      raise ESCIMException.Create(501, 'NOT IMPLEMENTED', '', 'Not done yet');
  except
    on e: ESCIMException do
    begin
      EncodeErrorResponse(response, e.Status, e.StatusText, e.ScimType, e.Message);
    end;
    on e : exception do
    begin
      EncodeErrorResponse(response, 500, 'INTERNAL SERVER ERROR', '', e.Message);
    end;
  end;
end;

procedure TSCIMServer.processUserDelete(context: TIdContext; request: TIdHTTPRequestInfo; response: TIdHTTPResponseInfo);
var
  id : String;
  conn : TKDBConnection;
begin
  id := request.Document.Substring(12);
  conn := db.GetConnection('scim.user.delete');
  try
    if conn.CountSQL('Select Count(*) from Users where Status = 1 and UserKey = '''+SQLWrapString(id)+'''') = 0 then
      raise ESCIMException.Create(404, 'Not Found', '', 'User not found');
    conn.execSQL('Update Users set Status = 0 where UserKey = '''+SQLWrapString(id)+'''');
    conn.execSQL('delete from UserIndexes where UserKey = '''+SQLWrapString(id)+'''');
    response.ResponseNo := 200;
    response.ResponseText := 'OK';
    conn.Release;
  except
    on e:Exception do
    begin
      conn.Error(e);
      raise;
    end;
  end;
end;

procedure TSCIMServer.processUserGet(context: TIdContext; request: TIdHTTPRequestInfo; response: TIdHTTPResponseInfo);
var
  id : String;
  conn : TKDBConnection;
  b : TBytes;
begin
  id := request.Document.Substring(12);
  conn := db.GetConnection('scim.user.read');
  try
    conn.SQL := 'Select Content from Users where Status = 1 and UserKey = '''+SQLWrapString(id)+'''';
    conn.Prepare;
    try
      conn.Execute;
      if not conn.FetchNext then
        raise ESCIMException.Create(404, 'Not Found', '', 'User not found');
      response.CustomHeaders.Add('Location: https://'+request.Host+'/scim/Users/'+id);
      response.ContentType := 'application/scim+json';
      response.ContentStream := TMemoryStream.create;
      b := conn.ColBlobByName['Content'];
      response.ContentStream.write(b[0], length(b));
      response.ContentStream.Position := 0;
    finally
      conn.Terminate;
    end;

    response.ResponseNo := 200;
    response.ResponseText := 'OK';
    conn.Release;
  except
    on e:Exception do
    begin
      conn.Error(e);
      raise;
    end;
  end;
end;

procedure TSCIMServer.processUserPost(context: TIdContext; request: TIdHTTPRequestInfo; response: TIdHTTPResponseInfo);
var
  user : TSCIMUser;
  password : String;
  username : String;
  conn : TKDBConnection;
  key : integer;
  now : TDateAndTime;
begin
  if (request.Document <> '/scim/Users') then
    raise ESCIMException.Create(404, 'NOT FOUND', '', 'Path Error - must be /scim/Users');

  now := NowUTC;
  try
    user := TSCIMUser.Create(LoadIncoming(request));
    try
      user.check;
      if user.id <> '' then
        raise ESCIMException.Create(400, 'BAD REQUEST', 'mutability', 'Cannot include an id in a resource submitted to the server');

      password := user.password;
      username := user.username;
      if Username = '' then
        raise ESCIMException.Create(400, 'BAD REQUEST', 'invalidValue', 'Missing User name');

      user.password := '';

      key := GetNextUserKey;
      user.id := inttostr(key);
      user.created := now.Link;
      user.lastModified := now.Link;
      user.location := 'https://'+request.Host+'/scim/Users/'+inttostr(key);
      user.version := '1';
      user.resourceType := 'User';

      conn := db.GetConnection('scim.user.create');
      try
        conn.StartTransact;
        try
          if conn.CountSQL('select UserKey from Users where Status = 1 and UserName = '''+SQLWrapString(username)+'''') > 0 then
            raise ESCIMException.Create(400, 'BAD REQUEST', 'mutability', 'Duplicate User name');
          conn.SQL := 'Insert into Users (UserKey, UserName, Password, Status, Content) values (:uk, :un, :pw, 1, :cnt)';
          conn.Prepare;
          try
            conn.BindInteger('uk', key);
            conn.BindString('un', username);
            if (password <> '') then
              conn.BindString('pw', HashPassword(key, password))
            else
              conn.BindNull('pw');
            conn.BindBlobFromBytes('cnt', TJSONWriter.writeObject(user.json, false));
            conn.Execute;
          finally
            conn.Terminate;
          end;
          IndexUser(conn, user, key);
          conn.Commit;
        except
          conn.Rollback;
          raise;
        end;

        response.CustomHeaders.Add('Location: '+user.location);
        WriteOutgoing(response, user.json);
        response.ResponseNo := 201;
        response.ResponseText := 'Created';
        conn.Release;
      except
        on e:Exception do
        begin
          conn.Error(e);
          raise;
        end;
      end;
    finally
      user.Free;
    end;
  finally
    now.Free;
  end;
end;


procedure TSCIMServer.processUserPut(context: TIdContext; request: TIdHTTPRequestInfo; response: TIdHTTPResponseInfo);
var
  nUser, eUser : TSCIMUser;
  password : String;
  conn : TKDBConnection;
  now : TDateAndTime;
  id : String;
  b : TBytes;
begin
  id := request.Document.Substring(12);
  if (id = '1') or (id = '2') then
    raise ESCIMException.Create(409, 'Forbidden', '', 'Server does not allow update to system defined users');

  now := NowUTC;
  try
    nUser := TSCIMUser.Create(LoadIncoming(request));
    try
      nUser.id := id;
      nUser.check;
      password := nUser.password;
      nUser.password := '';

      // now, get the existing user
      conn := db.GetConnection('scim.user.create');
      try
        conn.StartTransact;
        try
          conn.SQL := 'Select Content from Users where Status = 1 and UserKey = '''+SQLWrapString(id)+'''';
          conn.Prepare;
          try
            conn.Execute;
            if not conn.FetchNext then
              raise ESCIMException.Create(404, 'Not Found', '', 'User not found');
            b := conn.ColBlobByName['Content']
          finally
            conn.Terminate;
          end;

          eUser := TSCIMUser.Create(TJSONParser.Parse(b));
          try
            if eUser.username <> nUser.username then
              raise ESCIMException.Create(400, 'BAD REQUEST', 'mutability', 'UserName is an immutable field - was '+eUser.username+', set to '+nUser.username);
            nUser.copyFrom(eUser);
            nUser.resourceType := eUser.resourceType;
            nUser.created := eUser.created.Link;
            nUser.location := eUser.location;
            nUser.lastModified := now.Link;
            nUser.Version := inttostr(StrToInT(eUser.version)+1);


            conn.SQL := 'Update Users set Password = :pw, Content = :cnt where UserKey = :uk';
            conn.Prepare;
            try
              conn.BindString('uk', id);
              if (password <> '') then
                conn.BindString('pw', HashPassword(StrToInt(id), password))
              else
                conn.BindNull('pw');
              conn.BindBlobFromBytes('cnt', TJSONWriter.writeObject(nUser.json, false));
              conn.Execute;
            finally
              conn.Terminate;
            end;
            IndexUser(conn, nUser, StrToInt(id));
            WriteOutgoing(response, nUser.json);
            response.CustomHeaders.Add('Location: '+nUser.location);
            response.ResponseNo := 200;
            response.ResponseText := 'OK';
          finally
            eUser.Free;
          end;
          conn.Commit;
        except
          conn.Rollback;
          raise;
        end;
        conn.Release;
      except
        on e:Exception do
        begin
          conn.Error(e);
          raise;
        end;
      end;
    finally
      nUser.Free;
    end;
  finally
    now.Free;
  end;
end;

procedure TSCIMServer.processUserQuery(context: TIdContext; request: TIdHTTPRequestInfo; response: TIdHTTPResponseInfo);
var
  params : TParseMap;
  conn : TKDBConnection;
  json : TJsonObject;
  list : TJsonArray;
  c, t, l, s : integer;
  sql, sort : String;
begin
  params := TParseMap.create(request.QueryParams);
  try
    json := TJsonObject.Create;
    try
      json.forceArr['schemas'].add('urn:scim:api:messages:2.0:ListResponse');
      conn := db.GetConnection('scim.user.search');
      try
        sql := ProcessUserFilter(params.GetVar('filter'));
        json['totalResults'] := inttostr(Conn.CountSQL('Select Count(*) from Users where status = 1 '+sql));
        list := json.forceArr['Resources'];

        s := StrToIntDef(params.GetVar('startIndex'), 0);
        l := StrToIntDef(params.GetVar('count'), 50);
        json['itemsPerPage'] := inttostr(l);
        json['startIndex'] := inttostr(s+1);

        sort := RecogniseUserAttribute(params.GetVar('sortBy'));
        if (sort=  '') then
          conn.SQL := 'Select Content from Users where status = 1 '+ sql
        else if params.GetVar('sortOrder') = 'descending' then
          conn.SQL := 'Select Content from Users LEFT OUTER JOIN UserIndexes on Users.UserKey = UserIndexes.UserKey and sortBy = 1 and IndexName = '''+sort+''' where status = 1'+ sql + ' order by Value DESC'
        else
          conn.SQL := 'Select Content from Users LEFT OUTER JOIN UserIndexes on Users.UserKey = UserIndexes.UserKey and sortBy = 1 and IndexName = '''+sort+''' where status = 1'+ sql + ' order by Value ASC';

        json['sql'] := conn.SQL;
        conn.Prepare;
        try
          conn.Execute;
          c := 0;
          t := 0;
          while conn.FetchNext do
          begin
            if (c >= s) then
            begin
              list.add(TJSONParser.Parse(conn.ColBlobByName['Content']));
              inc(t);
            end;
            inc(c);
            if (t >= l) then
              break;
          end;
        finally
          conn.Terminate;
        end;
        conn.Release;
      except
        on e:Exception do
        begin
          conn.Error(e);
          raise;
        end;
      end;

      response.ResponseNo := 200;
      response.ResponseText := 'OK';
      response.ContentType := 'application/scim+json';
      response.ContentStream := TMemoryStream.create;
      TJSONWriter.writeObject(response.ContentStream, json, false);
      response.ContentStream.Position := 0;
    finally
      json.free;
    end;
  finally
    params.Free;
  end;
end;

function TSCIMServer.ProcessUserFilter(filter: String): String;
var
  f : TSCIMSearchFilter;
  issuer : TSCIMCharIssuer;
begin
  if filter = '' then
    result := ''
  else
  begin
    issuer := TSCIMCharIssuer.Create;
    try
      f := TSCIMSearchParser.parse(filter);
      try
        result := ' and ' + BuildUserFilter(f, '', ' ', issuer);
      finally
        f.Free;
      end;
    finally
      issuer.Free;
    end;
  end;
end;


procedure TSCIMServer.processUserRequest(context: TIdContext; request: TIdHTTPRequestInfo; response: TIdHTTPResponseInfo);
begin
  case request.CommandType of
    hcGET : if (request.Document = '/scim/Users') and (request.UnparsedParams <> '') then
        processUserQuery(context, request, response)
      else
        processUserGet(context, request, response);
    hcPOST : processUserPost(context, request, response);
    hcPUT : processUserPut(context, request, response);
    hcDELETE : processUserDelete(context, request, response);
  else
    raise ESCIMException.Create(403, 'FORBIDDEN', '', 'This method is not supported');
  end;
end;


function extractProvider(s : String) : String;
begin
  if s = '' then
    result := 'n/a'
  else if s.StartsWith('http://www.facebook.com') then
    result := 'Facebook'
  else if s.StartsWith('http://www.google.com') then
    result := 'Google'
  else if s.StartsWith('http://www.hl7.org') then
    result := 'HL7'
  else
    result := '??';
end;

procedure TSCIMServer.processWebRequest(context: TIdContext; session : TFhirSession; request: TIdHTTPRequestInfo; response: TIdHTTPResponseInfo);
begin
  if (request.Document = '/scim/web') then
    processWebUserList(context, session, request, response)
  else if StringIsInteger16(request.Document.Substring(10)) then
    processWebUserId(context, session, request, response)
  else
    raise ESCIMException.Create(403, 'FORBIDDEN', '', 'URL not understood');
end;

procedure TSCIMServer.processWebUserId(context: TIdContext; session : TFhirSession; request: TIdHTTPRequestInfo; response: TIdHTTPResponseInfo);
var
  variables : TDictionary<String,String>;
  conn : TKDBConnection;
  user : TSCIMUser;
  i : integer;
  s : String;
  st : TStringList;
  p : TParseMap;
begin
  variables := TDictionary<String,String>.create;
  try
    conn := db.GetConnection('scim.user.search');
    try
      conn.SQL := 'Select Content from Users where status = 1 and UserKey = '+SQLWrapString(request.Document.Substring(10));
      conn.Prepare;
      try
        conn.Execute;
        if not conn.FetchNext then
          raise ESCIMException.Create(403, 'FORBIDDEN', '', 'User not found');
        user := TSCIMUser.Create(TJSONParser.Parse(conn.ColBlobByName['Content']));
        try
          if request.Command = 'POST' then
          begin
            p := TParseMap.Create(request.UnparsedParams);
            st := TStringList.create;
            try
              user.DisplayName := p.GetVar('display');
              st.Text := p.GetVar('emails');
              user.emails.Clear;
              for i := 0 to st.Count - 1 do
                user.AddEmail(st[i], '');
              st.Text := p.GetVar('rights');
              user.clearEntitlements;
              for i := 0 to st.Count - 1 do
                user.addEntitlement(st[i]);
              conn.terminate;
              conn.SQL := 'Update Users set Content = :c where UserKey = '+SQLWrapString(request.Document.Substring(10));
              conn.prepare;
              conn.BindBlobFromBytes('c', TJSONWriter.writeObject(user.json));
              conn.Execute;
            finally
              st.Free;
              p.Free;
            end;
          end;
          variables.Add('user.id', user.id);
          variables.Add('user.name', user.username);
          variables.Add('user.display', user.DisplayName);
          variables.Add('user.external', user.ExternalId);
          s := '';
          for i := 0 to user.emails.Count - 1 do
            s := s + user.emails[i].Value+#13#10;
          variables.Add('user.email', s);
          s := '';
          for i := 0 to user.entitlementCount - 1 do
            s := s + user.entitlement[i]+#13#10;
          variables.Add('user.rights', s);
          variables.Add('user.json', TJSONWriter.writeObjectStr(user.json, true));
        finally
          user.Free;
        end;
      finally
        conn.Terminate;
      end;
      conn.Release;
    except
      on e:Exception do
      begin
        conn.Error(e);
        raise;
      end;
    end;

    OnProcessFile(response, session, '/scimuser.html', AltFile('/scimuser.html'), true, variables);
  finally
    variables.free;
  end;
end;

procedure TSCIMServer.processWebUserList(context: TIdContext; session : TFhirSession; request: TIdHTTPRequestInfo; response: TIdHTTPResponseInfo);
var
  variables : TDictionary<String,String>;
  conn : TKDBConnection;
  b : TStringBuilder;
  user : TSCIMUser;
  i : integer;
begin
  b := TStringBuilder.Create;
  try
    conn := db.GetConnection('scim.user.search');
    try
      conn.SQL := 'Select Content from Users where status = 1';
      conn.Prepare;
      try
        conn.Execute;
        while conn.FetchNext do
        begin
          user := TSCIMUser.Create(TJSONParser.Parse(conn.ColBlobByName['Content']));
          try
            b.Append('<tr>');
            b.Append('<td>');
            b.Append(user.id);
            b.Append('</td>');
            b.Append('<td><a href="/scim/web/');
            b.Append(user.id);
            b.Append('">');
            b.Append(user.username);
            b.Append('</a></td>');
            b.Append('<td>');
            b.Append(extractProvider(user.ExternalId));
            b.Append('</td>');
            b.Append('<td>');
            for i := 0 to user.emails.Count - 1 do
            begin
              if i > 0 then
                b.Append(', ');
              b.Append('<a href="mailto:'+user.emails[i].Value+'">'+user.emails[i].Value+'</a>');
            end;
            b.Append('</td>');
            b.Append('<td>');
            for i := 0 to user.entitlementCount - 1 do
            begin
              if i > 0 then
                b.Append(',<br/> ');
              b.Append(prefixScope(user.entitlement[i]));
            end;
            b.Append('</td>');
//            b.Append('<td>');
//            b.Append(TJSONWriter.writeObjectStr(user.json, true));
//            b.Append('</td>');
            b.Append('</tr>'#13#10);
          finally
            user.Free;
          end;
        end;
      finally
        conn.Terminate;
      end;
      conn.Release;
    except
      on e:Exception do
      begin
        conn.Error(e);
        raise;
      end;
    end;

    variables := TDictionary<String,String>.create;
    try
      variables.Add('usertable', b.ToString);
      OnProcessFile(response, session, '/scimusers.html', AltFile('/scimusers.html'), true, variables);
    finally
      variables.free;
    end;
  finally
    b.Free;
  end;
end;

function TSCIMServer.AltFile(path : String) : String;
begin
  if path.StartsWith('/') then
    result := FFilePath+path.Substring(1).Replace('/', '\')
  else
    result := '';
end;

procedure TSCIMServer.IndexUser(conn: TKDBConnection; user: TSCIMUser; userKey: integer);
  function ndxStruc(parent : integer; name : String) : integer;
  begin
    result := GetNextUserIndexKey;
    conn.BindInteger('ik', result);
    if (parent = 0) then
      conn.BindNull('p')
    else
      conn.BindInteger('p', parent);
    conn.BindString('in', name);
    conn.BindNull('v');
    conn.BindNull('sb');
    conn.Execute;
  end;
  procedure ndx(parent : integer; name, value : String; sort : boolean);
  begin
    if (value <> '') then
    begin
      conn.BindInteger('ik', GetNextUserIndexKey);
      if (parent = 0) then
        conn.BindNull('p')
      else
        conn.BindInteger('p', parent);
      conn.BindString('in', name);
      conn.BindString('v', copy(value, 1, 255));
      conn.BindInteger('sb', ord(sort));
      conn.Execute;
    end;
  end;
var
  b : boolean;
  i, p : integer;
begin
  conn.ExecSQL('delete from UserIndexes where UserKey = '+inttostr(UserKey));
  conn.SQL := 'Insert into UserIndexes (UserIndexKey, UserKey, IndexName, Parent, Value, sortBy) values (:ik, '+inttostr(userkey)+', :in, :p, :v, :sb)';
  conn.Prepare;
  try
    ndx(0, 'id', user.id, true);
    ndx(0, 'externalId', user.externalId, true);
    ndx(0, 'resourceType', user.resourceType, true);
    ndx(0, 'created', user.createdUTC.AsXML, true);
    ndx(0, 'lastModified', user.lastModifiedUTC.AsXML, true);
    ndx(0, 'location', user.location, true);
    ndx(0, 'version', user.version, true);
    ndx(0, 'formattedName', user.formattedName, true);
    ndx(0, 'familyName', user.familyName, true);
    ndx(0, 'givenName', user.givenName, true);
    ndx(0, 'middleName', user.middleName, true);
    ndx(0, 'prefix', user.prefix, true);
    ndx(0, 'suffix', user.suffix, true);
    ndx(0, 'displayName', user.displayName, true);
    ndx(0, 'nickName', user.nickName, true);
    ndx(0, 'profileUrl', user.profileUrl, true);
    ndx(0, 'title', user.title, true);
    ndx(0, 'userType', user.userType, true);
    ndx(0, 'preferredLanguage', user.preferredLanguage, true);
    ndx(0, 'locale', user.locale, true);
    ndx(0, 'timezone', user.timezone, true);

    b := true;
    for i := 0 to user.emails.count - 1 do
      if user.emails[i].primary then
      begin
        p := ndxStruc(0, 'emails');
        ndx(p, 'emails.type', user.emails[i].type_, b);
        ndx(p, 'emails.value', user.emails[i].value, b);
        ndx(p, 'emails.primary', 'true', b);
        b := false;
      end;

    for i := 0 to user.emails.count - 1 do
      if not user.emails[i].primary then
      begin
        p := ndxStruc(0, 'emails');
        ndx(p, 'emails.type', user.emails[i].type_, b);
        ndx(p, 'emails.value', user.emails[i].value, b);
        ndx(p, 'emails.primary', 'false', b);
        b := false;
      end;

    b := true;
    for i := 0 to user.phoneNums.count - 1 do
      if user.phoneNums[i].primary then
      begin
        p := ndxStruc(0, 'phones');
        ndx(p, 'phones.type', user.phoneNums[i].type_, b);
        ndx(p, 'phones.value', user.phoneNums[i].value, b);
        ndx(p, 'phones.primary', 'true', b);
        b := false;
      end;

    for i := 0 to user.phoneNums.count - 1 do
      if not user.phoneNums[i].primary then
      begin
        p := ndxStruc(0, 'phones');
        ndx(p, 'phones.type', user.phoneNums[i].type_, b);
        ndx(p, 'phones.value', user.phoneNums[i].value, b);
        ndx(p, 'phones.primary', 'false', b);
        b := false;
      end;

    b := true;
    for i := 0 to user.ims.count - 1 do
      if user.ims[i].primary then
      begin
        p := ndxStruc(0, 'ims');
        ndx(p, 'ims.type', user.ims[i].type_, b);
        ndx(p, 'ims.value', user.ims[i].value, b);
        ndx(p, 'ims.primary', 'true', b);
        b := false;
      end;

    for i := 0 to user.ims.count - 1 do
      if not user.ims[i].primary then
      begin
        p := ndxStruc(0, 'ims');
        ndx(p, 'ims.type', user.ims[i].type_, b);
        ndx(p, 'ims.value', user.ims[i].value, b);
        ndx(p, 'ims.primary', 'false', b);
        b := false;
      end;

    b := true;
    for i := 0 to user.addresses.count - 1 do
      if user.addresses[i].primary then
      begin
        p := ndxStruc(0, 'addresses');
        ndx(p, 'addresses.type', user.addresses[i].type_, b);
        ndx(p, 'addresses.locality', user.addresses[i].locality, b);
        ndx(p, 'addresses.region', user.addresses[i].region, b);
        ndx(p, 'addresses.postalCode', user.addresses[i].postalCode, b);
        ndx(p, 'addresses.country', user.addresses[i].country, b);
        ndx(p, 'addresses.primary', 'true', b);
        b := false;
      end;

    for i := 0 to user.addresses.count - 1 do
      if not user.addresses[i].primary then
      begin
        p := ndxStruc(0, 'addresses');
        ndx(p, 'addresses.type', user.addresses[i].type_, b);
        ndx(p, 'addresses.locality', user.addresses[i].locality, b);
        ndx(p, 'addresses.region', user.addresses[i].region, b);
        ndx(p, 'addresses.postalCode', user.addresses[i].postalCode, b);
        ndx(p, 'addresses.country', user.addresses[i].country, b);
        ndx(p, 'addresses.primary', 'true', b);
        b := false;
      end;

    b := true;
    for i := 0 to user.entitlementcount - 1 do
    begin
      ndx(0, 'entitlements', user.entitlement[i], b);
      b := false;
    end;

    // things we do not index:
//    groups
//    entitlements
//    roles
//    x509Certificates
  finally
    conn.Terminate;
  end;
end;


function TSCIMServer.RecogniseUserAttribute(path: String): String;
begin
  if path = 'id' then result := 'id'
  else if path = 'externalId' then result := 'externalId'
  else if path = 'meta.resourceType' then result := 'resourceType'
  else if path = 'meta.created' then result := 'created'
  else if path = 'meta.lastModified' then result := 'lastModified'
  else if path = 'meta.location' then result := 'location'
  else if path = 'meta.version' then result := 'version'
  else if path = 'name.formattedName' then result := 'formattedName'
  else if path = 'name.familyName' then result := 'familyName'
  else if path = 'name.givenName' then result := 'givenName'
  else if path = 'name.middleName' then result := 'middleName'
  else if path = 'name.prefix' then result := 'prefix'
  else if path = 'name.suffix' then result := 'suffix'
  else if path = 'displayName' then result := 'displayName'
  else if path = 'nickName' then result := 'nickName'
  else if path = 'profileUrl' then result := 'profileUrl'
  else if path = 'title' then result := 'title'
  else if path = 'userType' then result := 'userType'
  else if path = 'preferredLanguage' then result := 'preferredLanguage'
  else if path = 'locale' then result := 'locale'
  else if path = 'timezone' then result := 'timezone'
  else if path = 'emails' then result := 'emails'
  else if path = 'emails.type' then result := 'emails.type'
  else if path = 'emails.value' then result := 'emails.value'
  else if path = 'emails.primary' then result := 'emails.primary'
  else if path = 'phones' then result := 'phones'
  else if path = 'phones.type' then result := 'phones.type'
  else if path = 'phones.value' then result := 'phones.value'
  else if path = 'phones.primary' then result := 'phones.primary'
  else if path = 'ims' then result := 'ims'
  else if path = 'ims.type' then result := 'ims.type'
  else if path = 'ims.value' then result := 'ims.value'
  else if path = 'ims.primary' then result := 'ims.primary'
  else if path = 'addresses' then result := 'addresses'
  else if path = 'addresses.type' then result := 'addresses.type'
  else if path = 'addresses.locality' then result := 'addresses.locality'
  else if path = 'addresses.region' then result := 'addresses.region'
  else if path = 'addresses.postalCode' then result := 'addresses.postalCode'
  else if path = 'addresses.country' then result := 'addresses.country'
  else if path = 'addresses.primary' then result := 'addresses.primary'
  else if path = 'entitlements' then result := 'entitlements'
  else
    result := '';
end;

procedure TSCIMServer.WriteOutgoing(response: TIdHTTPResponseInfo; json: TJsonObject);
begin
  response.ContentType := 'application/scim+json';
  response.ContentStream := TMemoryStream.create;
  TJSONWriter.writeObject(response.contentStream, json, false);
  response.ContentStream.Position := 0;
end;

function TSCIMServer.BuildUserFilter(filter: TSCIMSearchFilter; prefix : String; parent : char; issuer : TSCIMCharIssuer): String;
begin
  case filter.SearchItemType of
    sitTest : result := BuildUserFilterTest(filter as TSCIMSearchFilterTest, prefix, parent, issuer);
    sitCriteria : result := BuildUserFilterCriteria(filter as TSCIMSearchFilterCriteria, prefix, parent, issuer);
    sitValuePath : result := BuildUserFilterValuePath(filter as TSCIMSearchFilterValuePath, prefix, parent, issuer);
  else
    raise Exception.Create('Unknown type');
  end;
end;

function TSCIMServer.BuildUserFilterTest(filter: TSCIMSearchFilterTest; prefix : String; parent : char; issuer : TSCIMCharIssuer): String;
var
  index : String;
  n : char;
  j : string;
begin
  // do we recognise the attribute path?
  index := RecogniseUserAttribute(prefix+filter.AttributePath);
  n := issuer.next;
  if parent = ' ' then
    j := ''
  else
    j := ' and '+n+'.parent = '+parent+'.UserIndexKey';

  if index = '' then
    // if we don't, then just status = 1 (cause we can't return nothing
    result := 'status = 1'
  else case filter.Operation of
    sfoEq: result := 'Users.UserKey in (select UserKey from UserIndexes as '+n+' where '+n+'.IndexName = '''+index+''' and '+n+'.Value = '''+SQLWrapString(filter.Value)+''''+j+')';
    sfoNe: result := 'Users.UserKey in (select UserKey from UserIndexes as '+n+' where '+n+'.IndexName = '''+index+''' and '+n+'.Value <> '''+SQLWrapString(filter.Value)+''''+j+')';
    sfoCo: result := 'Users.UserKey in (select UserKey from UserIndexes as '+n+' where '+n+'.IndexName = '''+index+''' and '+n+'.Value like ''%'+SQLWrapString(filter.Value)+'%'''+j+')';
    sfoSw: result := 'Users.UserKey in (select UserKey from UserIndexes as '+n+' where '+n+'.IndexName = '''+index+''' and '+n+'.Value like '''+SQLWrapString(filter.Value)+'%'''+j+')';
    sfoEw: result := 'Users.UserKey in (select UserKey from UserIndexes as '+n+' where '+n+'.IndexName = '''+index+''' and '+n+'.Value like ''%'+SQLWrapString(filter.Value)+''''+j+')';
    sfoGt: result := 'Users.UserKey in (select UserKey from UserIndexes as '+n+' where '+n+'.IndexName = '''+index+''' and '+n+'.Value > '''+SQLWrapString(filter.Value)+''''+j+')';
    sfoLt: result := 'Users.UserKey in (select UserKey from UserIndexes as '+n+' where '+n+'.IndexName = '''+index+''' and '+n+'.Value < '''+SQLWrapString(filter.Value)+''''+j+')';
    sfoGe: result := 'Users.UserKey in (select UserKey from UserIndexes as '+n+' where '+n+'.IndexName = '''+index+''' and '+n+'.Value >= '''+SQLWrapString(filter.Value)+''''+j+')';
    sfoLe: result := 'Users.UserKey in (select UserKey from UserIndexes as '+n+' where '+n+'.IndexName = '''+index+''' and '+n+'.Value <= '''+SQLWrapString(filter.Value)+''''+j+')';
    sfoPr: result := 'Users.UserKey in (select UserKey from UserIndexes as '+n+' where '+n+'.IndexName = '''+index+''''+j+')';
  end;
end;

function TSCIMServer.BuildUserFilterCriteria(filter: TSCIMSearchFilterCriteria; prefix : String; parent : char; issuer : TSCIMCharIssuer): String;
begin
  if filter.Operation = sfloNot then
    result := '(Not '+BuildUserFilter(filter.Criterion2, prefix, parent, issuer)+')'
  else if filter.Operation = sfloOr then
    result := '('+BuildUserFilter(filter.Criterion1, prefix, parent, issuer)+' or '+BuildUserFilter(filter.Criterion2, prefix, parent, issuer)+')'
  else
    result := '('+BuildUserFilter(filter.Criterion1, prefix, parent, issuer)+' and '+BuildUserFilter(filter.Criterion2, prefix, parent, issuer)+')';
end;

function TSCIMServer.BuildUserFilterValuePath(filter: TSCIMSearchFilterValuePath; prefix : String; parent : char; issuer : TSCIMCharIssuer): String;
var
  n : char;
  index : string;
begin
  n := issuer.next;
  index := RecogniseUserAttribute(prefix+filter.AttributePath);
  if index = '' then
    result := 'status = 1'
  else
    result := 'Users.UserKey in (select UserKey from UserIndexes as '+n+' where (indexName = '''+index+''' and '+BuildUserFilter(filter.Filter, prefix+filter.AttributePath+'.', n, issuer) +'))';
end;


{ TSCIMCharIssuer }

constructor TSCIMCharIssuer.Create;
begin
  inherited;
  cursor := 'a';
end;

function TSCIMCharIssuer.next: char;
begin
  result := cursor;
  inc(cursor);
end;


end.
