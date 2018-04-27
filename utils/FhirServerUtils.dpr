{
Copyright (c) 2017+, Health Intersections Pty Ltd (http://www.healthintersections.com.au)
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

 * Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.
 * Neither the name of HL7 nor the names of its contributors may be used to
   endorse or promote products derived from this software without specific
   prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS 'AS IS' AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
}
program FhirServerUtils;

uses
  FastMM4 in '..\Libraries\FMM\FastMM4.pas',
  FastMM4Messages in '..\Libraries\FMM\FastMM4Messages.pas',
  Vcl.Forms,
  UtilitiesForm in 'UtilitiesForm.pas' {Form4},
  Windows,
  SysUtils,
  Classes,
  IdSSLOpenSSLHeaders,
  JclDebug,
  FHIR.Support.Strings in '..\reference-platform\Support\FHIR.Support.Strings.pas',
  FHIR.Support.Math in '..\reference-platform\Support\FHIR.Support.Math.pas',
  FHIR.Support.DateTime in '..\reference-platform\Support\FHIR.Support.DateTime.pas',
  FHIR.Support.Binary in '..\reference-platform\Support\FHIR.Support.Binary.pas',
  FHIR.Support.Objects in '..\reference-platform\Support\FHIR.Support.Objects.pas',
  FHIR.Support.Exceptions in '..\reference-platform\Support\FHIR.Support.Exceptions.pas',
  FHIR.Support.Factory in '..\reference-platform\Support\FHIR.Support.Factory.pas',
  FHIR.Support.System in '..\reference-platform\Support\FHIR.Support.System.pas',
  FHIR.Support.Filers in '..\reference-platform\Support\FHIR.Support.Filers.pas',
  FHIR.Support.Collections in '..\reference-platform\Support\FHIR.Support.Collections.pas',
  FHIR.Support.Stream in '..\reference-platform\Support\FHIR.Support.Stream.pas',
  FHIR.Web.ParseMap in '..\reference-platform\Support\FHIR.Web.ParseMap.pas',
  FHIR.Support.Decimal in '..\reference-platform\Support\FHIR.Support.Decimal.pas',
  FHIR.Support.WInInet in '..\reference-platform\Support\FHIR.Support.WInInet.pas',
  FHIR.Support.Json in '..\reference-platform\Support\FHIR.Support.Json.pas',
  FHIR.Ucum.Services in '..\Libraries\Ucum\FHIR.Ucum.Services.pas',
  FHIR.Ucum.Handlers in '..\Libraries\Ucum\FHIR.Ucum.Handlers.pas',
  FHIR.Ucum.Base in '..\Libraries\Ucum\FHIR.Ucum.Base.pas',
  FHIR.Ucum.Validators in '..\Libraries\Ucum\FHIR.Ucum.Validators.pas',
  FHIR.Ucum.Expressions in '..\Libraries\Ucum\FHIR.Ucum.Expressions.pas',
  FHIR.Ucum.Search in '..\Libraries\Ucum\FHIR.Ucum.Search.pas',
  YuStemmer in '..\Libraries\Stem\YuStemmer.pas',
  FHIR.Loinc.Services in '..\Libraries\loinc\FHIR.Loinc.Services.pas',
  DISystemCompat in '..\Libraries\Stem\DISystemCompat.pas',
  FHIR.Snomed.Services in '..\Libraries\Snomed\FHIR.Snomed.Services.pas',
  FHIR.Web.Fetcher in '..\reference-platform\Support\FHIR.Web.Fetcher.pas',
  FHIR.Misc.Facebook in '..\reference-platform\Support\FHIR.Misc.Facebook.pas',
  FHIR.Support.Service in '..\reference-platform\Support\FHIR.Support.Service.pas',
  DBInstaller in '..\server\DBInstaller.pas',
  FHIR.Database.Dialects in '..\reference-platform\Support\FHIR.Database.Dialects.pas',
  FHIR.Database.Logging in '..\Libraries\db\FHIR.Database.Logging.pas',
  FHIR.Database.Manager in '..\Libraries\db\FHIR.Database.Manager.pas',
  FHIR.Database.Utilities in '..\Libraries\db\FHIR.Database.Utilities.pas',
  FHIR.Database.Settings in '..\Libraries\db\FHIR.Database.Settings.pas',
  FHIR.Snomed.Importer in '..\Libraries\snomed\FHIR.Snomed.Importer.pas',
  FHIR.Snomed.Publisher in '..\Libraries\snomed\FHIR.Snomed.Publisher.pas',
  FHIR.Snomed.Expressions in '..\Libraries\snomed\FHIR.Snomed.Expressions.pas',
  FHIR.Web.HtmlGen in '..\reference-platform\Support\FHIR.Web.HtmlGen.pas',
  FHIR.Loinc.Importer in '..\Libraries\loinc\FHIR.Loinc.Importer.pas',
  FHIR.Loinc.Publisher in '..\Libraries\loinc\FHIR.Loinc.Publisher.pas',
  TerminologyServer in '..\server\TerminologyServer.pas',
  TerminologyServerStore in '..\server\TerminologyServerStore.pas',
  FHIR.Tx.Service in '..\Libraries\FHIR.Tx.Service.pas',
  TerminologyWebServer in '..\server\TerminologyWebServer.pas',
  FHIRServerConstants in '..\server\FHIRServerConstants.pas',
  FHIRServerUtilities in '..\server\FHIRServerUtilities.pas',
  AuthServer in '..\server\AuthServer.pas',
  SCIMServer in '..\server\SCIMServer.pas',
  SCIMSearch in '..\server\SCIMSearch.pas',
  FHIR.Misc.Twilio in '..\Libraries\security\FHIR.Misc.Twilio.pas',
  FHIR.Support.Shell in '..\reference-platform\Support\FHIR.Support.Shell.pas',
  RectSupport in '..\server\RectSupport.pas',
  CoordinateSupport in '..\server\CoordinateSupport.pas',
  FHIR.Support.Generics in '..\reference-platform\Support\FHIR.Support.Generics.pas',
  FHIR.Support.Signatures in '..\reference-platform\Support\FHIR.Support.Signatures.pas',
  UriServices in '..\server\UriServices.pas',
  UniiServices in '..\server\UniiServices.pas',
  RxNormServices in '..\server\RxNormServices.pas',
  IETFLanguageCodeServices in '..\server\IETFLanguageCodeServices.pas',
  FHIR.Snomed.Analysis in '..\Libraries\snomed\FHIR.Snomed.Analysis.pas',
  AreaCodeServices in '..\server\AreaCodeServices.pas',
  FHIRSubscriptionManager in '..\server\FHIRSubscriptionManager.pas',
  ServerValidator in '..\server\ServerValidator.pas',
  FHIR.Web.Socket in '..\reference-platform\Support\FHIR.Web.Socket.pas',
  FHIR.Support.Mime in '..\reference-platform\Support\FHIR.Support.Mime.pas',
  FHIR.Support.Lock in '..\reference-platform\Support\FHIR.Support.Lock.pas',
  FHIR.R4.Questionnaire in '..\reference-platform\r4\FHIR.R4.Questionnaire.pas',
  FHIR.Base.Scim in '..\reference-platform\base\FHIR.Base.Scim.pas',
  FHIR.R4.Narrative2 in '..\reference-platform\r4\FHIR.R4.Narrative2.pas',
  FHIR.Tools.Security in '..\reference-platform\tools\FHIR.Tools.Security.pas',
  FHIR.R4.Narrative in '..\reference-platform\r4\FHIR.R4.Narrative.pas',
  FHIR.Client.SmartUtilities in '..\reference-platform\client\FHIR.Client.SmartUtilities.pas',
  FHIR.R4.PathEngine in '..\reference-platform\r4\FHIR.R4.PathEngine.pas',
  FHIR.R4.Tags in '..\reference-platform\r4\FHIR.R4.Tags.pas',
  FHIR.R4.Profiles in '..\reference-platform\r4\FHIR.R4.Profiles.pas',
  FHIR.Base.Objects in '..\reference-platform\base\FHIR.Base.Objects.pas',
  FHIR.R4.Types in '..\reference-platform\r4\FHIR.R4.Types.pas',
  FHIR.R4.Resources in '..\reference-platform\r4\FHIR.R4.Resources.pas',
  FHIR.Tools.Parser in '..\reference-platform\tools\FHIR.Tools.Parser.pas',
  FHIR.Base.Parser in '..\reference-platform\base\FHIR.Base.Parser.pas',
  FHIR.R4.Constants in '..\reference-platform\r4\FHIR.R4.Constants.pas',
  FHIR.Tools.Session in '..\reference-platform\tools\FHIR.Tools.Session.pas',
  FHIR.Base.Lang in '..\reference-platform\base\FHIR.Base.Lang.pas',
  FHIR.R4.Utilities in '..\reference-platform\r4\FHIR.R4.Utilities.pas',
  FHIR.Tools.Client in '..\reference-platform\client\FHIR.Tools.Client.pas',
  FHIR.R4.Validator in '..\reference-platform\r4\FHIR.R4.Validator.pas',
  ClosureManager in '..\server\ClosureManager.pas',
  FHIR.CdsHooks.Utilities in '..\reference-platform\support\FHIR.CdsHooks.Utilities.pas',
  MarkdownProcessor in '..\..\markdown\source\MarkdownProcessor.pas',
  MarkdownDaringFireball in '..\..\markdown\source\MarkdownDaringFireball.pas',
  MarkdownDaringFireballTests in '..\..\markdown\source\MarkdownDaringFireballTests.pas',
  AccessControlEngine in '..\server\AccessControlEngine.pas',
  FHIR.Web.Rdf in '..\reference-platform\support\FHIR.Web.Rdf.pas',
  FHIR.R4.Operations in '..\reference-platform\r4\FHIR.R4.Operations.pas',
  FHIR.R4.OpBase in '..\reference-platform\r4\FHIR.R4.OpBase.pas',
  FHIR.R4.IndexInfo in '..\reference-platform\r4\FHIR.R4.IndexInfo.pas',
  FHIR.R4.ElementModel in '..\reference-platform\r4\FHIR.R4.ElementModel.pas',
  FHIR.Base.Xhtml in '..\reference-platform\base\FHIR.Base.Xhtml.pas',
  FHIR.R4.MapUtilities in '..\reference-platform\r4\FHIR.R4.MapUtilities.pas',
  FHIR.R4.Context in '..\reference-platform\r4\FHIR.R4.Context.pas',
  FHIR.Debug.Logging in '..\reference-platform\support\FHIR.Debug.Logging.pas',
  FHIR.R4.AuthMap in '..\reference-platform\r4\FHIR.R4.AuthMap.pas',
  FHIRIndexManagers in '..\Server\FHIRIndexManagers.pas',
  ServerUtilities in '..\Server\ServerUtilities.pas',
  ServerAdaptations in '..\Server\ServerAdaptations.pas',
  FHIRValueSetChecker in '..\Server\FHIRValueSetChecker.pas',
  FHIRValueSetExpander in '..\Server\FHIRValueSetExpander.pas',
  MPISearch in '..\Server\MPISearch.pas',
  SearchProcessor in '..\Server\SearchProcessor.pas',
  FHIRSearchSyntax in '..\Server\FHIRSearchSyntax.pas',
  SnomedCombiner in 'SnomedCombiner.pas',
  ObservationStatsEvaluator in '..\Server\ObservationStatsEvaluator.pas',
  FHIR.Tools.DiffEngine in '..\reference-platform\tools\FHIR.Tools.DiffEngine.pas',
  ACIRServices in '..\Server\ACIRServices.pas',
  FHIRStorageService in '..\Server\FHIRStorageService.pas',
  FHIRNativeStorage in '..\Server\FHIRNativeStorage.pas',
  FHIRServerContext in '..\Server\FHIRServerContext.pas',
  FHIRTagManager in '..\Server\FHIRTagManager.pas',
  FHIRSessionManager in '..\Server\FHIRSessionManager.pas',
  FHIRUserProvider in '..\Server\FHIRUserProvider.pas',
  FHIR.Tools.GraphQL in '..\reference-platform\tools\FHIR.Tools.GraphQL.pas',
  FHIR.Support.MXml in '..\reference-platform\support\FHIR.Support.MXml.pas',
  MarkdownCommonMark in '..\..\markdown\source\MarkdownCommonMark.pas',
  FHIR.Tools.CodeGen in '..\reference-platform\tools\FHIR.Tools.CodeGen.pas',
  CDSHooksServices in '..\Server\CDSHooksServices.pas',
  CDSHooksServer in '..\Server\CDSHooksServer.pas',
  FHIR.Support.Turtle in '..\reference-platform\support\FHIR.Support.Turtle.pas',
  FHIR.R4.Turtle in '..\reference-platform\r4\FHIR.R4.Turtle.pas',
  FHIR.R4.Json in '..\reference-platform\r4\FHIR.R4.Json.pas',
  FHIR.R4.Xml in '..\reference-platform\r4\FHIR.R4.Xml.pas',
  GraphDefinitionEngine in '..\Server\GraphDefinitionEngine.pas',
  FHIR.Misc.ApplicationVerifier in '..\Libraries\security\FHIR.Misc.ApplicationVerifier.pas',
  JWTService in '..\Server\JWTService.pas',
  FHIR.CdsHooks.Client in '..\reference-platform\support\FHIR.CdsHooks.Client.pas',
  HackingHealthLogic in '..\Server\Modules\HackingHealthLogic.pas',
  FHIR.Utilities.SCrypt in '..\Libraries\security\FHIR.Utilities.SCrypt.pas',
  ApplicationCache in '..\Server\ApplicationCache.pas',
  TerminologyOperations in '..\Server\TerminologyOperations.pas',
  WebSourceProvider in '..\Server\WebSourceProvider.pas',
  FHIR.Tools.Indexing in '..\reference-platform\tools\FHIR.Tools.Indexing.pas',
  FHIR.Database.ODBC in '..\Libraries\db\FHIR.Database.ODBC.pas',
  FHIR.Database.ODBC.Objects in '..\Libraries\db\FHIR.Database.ODBC.Objects.pas',
  FHIR.Database.ODBC.Headers in '..\Libraries\db\FHIR.Database.ODBC.Headers.pas',
  FHIR.Database.SQLite3.Objects in '..\Libraries\db\FHIR.Database.SQLite3.Objects.pas',
  FHIR.Database.SQLite3.Utilities in '..\Libraries\db\FHIR.Database.SQLite3.Utilities.pas',
  FHIR.Database.SQLite3.Wrapper in '..\Libraries\db\FHIR.Database.SQLite3.Wrapper.pas',
  FHIR.Database.SQLite in '..\Libraries\db\FHIR.Database.SQLite.pas',
  ServerPostHandlers in '..\Server\ServerPostHandlers.pas',
  ICD10Services in '..\Server\ICD10Services.pas',
  ServerJavascriptHost in '..\Server\ServerJavascriptHost.pas',
  FHIR.Javascript.Base in '..\Libraries\js\FHIR.Javascript.Base.pas',
  FHIR.Javascript in '..\Libraries\js\FHIR.Javascript.pas',
  FHIR.Support.Javascript in '..\Libraries\js\FHIR.Support.Javascript.pas',
  FHIR.Javascript.Chakra in '..\Libraries\js\FHIR.Javascript.Chakra.pas',
  FHIR.R4.Javascript in '..\reference-platform\r4\FHIR.R4.Javascript.pas',
  FHIR.Client.Javascript in '..\Libraries\js\FHIR.Client.Javascript.pas',
  ServerEventJs in '..\Server\ServerEventJs.pas',
  FHIR.Tools.Factory in '..\reference-platform\tools\FHIR.Tools.Factory.pas',
  USStatesServices in '..\Server\USStatesServices.pas',
  CountryCodeServices in '..\Server\CountryCodeServices.pas',
  FHIR.R4.PathNode in '..\reference-platform\r4\FHIR.R4.PathNode.pas',
  FHIR.Ucum.IFace in '..\reference-platform\support\FHIR.Ucum.IFace.pas',
  FHIR.R4.ParserBase in '..\reference-platform\r4\FHIR.R4.ParserBase.pas',
  FHIR.Tools.XhtmlComp in '..\reference-platform\tools\FHIR.Tools.XhtmlComp.pas',
  FHIR.R4.Base in '..\reference-platform\r4\FHIR.R4.Base.pas',
  FHIR.R4.Parser in '..\reference-platform\r4\FHIR.R4.Parser.pas',
  FHIR.R4.Client in '..\reference-platform\r4\FHIR.R4.Client.pas',
  FHIR.Client.HTTP in '..\reference-platform\client\FHIR.Client.HTTP.pas',
  FHIR.Client.Base in '..\reference-platform\client\FHIR.Client.Base.pas',
  FHIR.Client.Threaded in '..\reference-platform\client\FHIR.Client.Threaded.pas',
  FHIR.Support.Text in '..\reference-platform\support\FHIR.Support.Text.pas',
  FHIR.Support.Zip in '..\reference-platform\support\FHIR.Support.Zip.pas',
  FHIR.Support.Xml in '..\reference-platform\support\FHIR.Support.Xml.pas',
  FHIR.Support.Controllers in '..\reference-platform\support\FHIR.Support.Controllers.pas',
  FHIR.Support.Certs in '..\reference-platform\support\FHIR.Support.Certs.pas',
  FHIR.Misc.GraphQL in '..\reference-platform\support\FHIR.Misc.GraphQL.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm4, Form4);
  Application.Run;
end.
