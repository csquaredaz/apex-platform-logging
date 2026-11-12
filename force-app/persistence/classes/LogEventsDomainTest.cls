/**
 * @description Unit tests for `LogEventsDomain` with a Stub API Unit of Work: mapping, the upsert
 * key, bulk, retries and give-up, and suppression (ADR 0005).
 */
@IsTest
private class LogEventsDomainTest {
  private static final String REQUEST_ID = '4ZHvAbCdEfGhIjKl';

  private static Mocks unitOfWorkMock;
  private static RecordingLogger fallback;

  private static void useMocks() {
    unitOfWorkMock = new Mocks();
    Application.UnitOfWork.setMock((IUnitOfWork) unitOfWorkMock.stub(IUnitOfWork.class));
    fallback = new RecordingLogger();
    LogEventsDomain.fallbackLogger = fallback;
  }

  private static List<Log_Event__e> events(Integer count) {
    List<Log_Event__e> events = new List<Log_Event__e>();
    for (Integer i = 1; i <= count; i++) {
      events.add(LoggerTestFixtures.deliveredEvent(REQUEST_ID, i, null));
    }
    return events;
  }

  private static List<Log__c> upsertedRows() {
    return (List<Log__c>) unitOfWorkMock.argumentsOf('registerUpsert', 0)[0];
  }

  @IsTest
  static void onAfterInsert_oneEvent_mapsEveryField() {
    useMocks();

    new LogEventsDomain(events(1)).onAfterInsert();

    Log__c row = upsertedRows()[0];
    Assert.areEqual(REQUEST_ID + '-1', row.Log_Key__c, 'Key is Request_Id-Sequence');
    Assert.areEqual('ERROR', row.Level__c, 'Level');
    Assert.areEqual('Booking shipment for order 42', row.Message__c, 'Message');
    Assert.areEqual('System.DmlException', row.Exception_Type__c, 'Exception type');
    Assert.areEqual('Required field missing', row.Exception_Message__c, 'Exception message');
    Assert.areEqual('Class.ShipmentService.book: line 7', row.Stack_Trace__c, 'Stack trace');
    Assert.areEqual(REQUEST_ID, row.Request_Id__c, 'Request Id');
    Assert.areEqual(1, row.Sequence__c, 'Sequence');
    Assert.areEqual('SYNCHRONOUS', row.Quiddity__c, 'Quiddity');
    Assert.areEqual(Datetime.newInstanceGmt(2026, 11, 12, 9, 30, 0), row.Logged_At__c, 'Logged at');
    Assert.areEqual(UserInfo.getUserId(), row.Logged_By__c, 'Logged by is the event creator');
  }

  @IsTest
  static void onAfterInsert_200Events_upsertsOnceOnLogKey() {
    useMocks();

    new LogEventsDomain(events(200)).onAfterInsert();

    unitOfWorkMock.verify('registerUpsert', 1);
    unitOfWorkMock.verify('commitWork', 1);
    Assert.areEqual(200, upsertedRows().size(), 'One row per event, one registration');
    Assert.areEqual(
      Log__c.Log_Key__c,
      unitOfWorkMock.argumentsOf('registerUpsert', 0)[1],
      'The match key is Log_Key__c'
    );
    Assert.areEqual(0, fallback.entries(LoggingLevel.ERROR).size(), 'Nothing was given up');
  }

  @IsTest
  static void onAfterInsert_repeatedKey_upsertsOneRowWithTheLastEvent() {
    useMocks();
    List<Log_Event__e> batch = events(1);
    Log_Event__e repeat = LoggerTestFixtures.deliveredEvent(REQUEST_ID, 1, null);
    repeat.Message__c = 'Second copy';
    batch.add(repeat);

    new LogEventsDomain(batch).onAfterInsert();

    Assert.areEqual(1, upsertedRows().size(), 'A repeated key would fail the whole upsert');
    Assert.areEqual('Second copy', upsertedRows()[0].Message__c, 'The last event wins');
  }

  @IsTest
  static void keyOf_missingSequence_usesEventUuid() {
    Log_Event__e event = LoggerTestFixtures.deliveredEvent(REQUEST_ID, null, 'a1b2c3');

    Assert.areEqual('uuid-a1b2c3', LogEventsDomain.keyOf(event), 'Falls back to the event UUID');
  }

  @IsTest
  static void keyOf_missingRequestId_usesEventUuid() {
    Log_Event__e event = LoggerTestFixtures.deliveredEvent(null, 3, 'a1b2c3');

    Assert.areEqual('uuid-a1b2c3', LogEventsDomain.keyOf(event), 'Falls back to the event UUID');
  }

  @IsTest
  static void onAfterInsert_noKeyParts_insertsWithNullKey() {
    useMocks();
    List<Log_Event__e> batch = new List<Log_Event__e>{
      LoggerTestFixtures.deliveredEvent(null, null, null),
      LoggerTestFixtures.deliveredEvent(null, null, null)
    };

    new LogEventsDomain(batch).onAfterInsert();

    Assert.areEqual(2, upsertedRows().size(), 'Keyless rows are not merged');
    Assert.isNull(upsertedRows()[0].Log_Key__c, 'A null key makes the upsert insert');
  }

  @IsTest
  static void onAfterInsert_commitFailsBelowMaxRetries_throwsRetryable() {
    useMocks();
    unitOfWorkMock.stubThrow('commitWork', new DmlException('Storage limit exceeded'));
    LogEventsDomain.retriesOverride = LogEventsDomain.MAX_RETRIES - 1;

    try {
      new LogEventsDomain(events(2)).onAfterInsert();
      Assert.fail('A failed commit with retries left must ask for redelivery');
    } catch (EventBus.RetryableException expected) {
      Assert.isTrue(expected.getMessage().contains('attempt 3 of 4'), expected.getMessage());
      Assert.isTrue(expected.getMessage().contains('Storage limit exceeded'), expected.getMessage());
    }
    Assert.areEqual(0, fallback.entries(LoggingLevel.ERROR).size(), 'Nothing was given up');
    Assert.isFalse(LogBuffer.isSuppressed(), 'Suppression is cleared when the domain throws');
  }

  @IsTest
  static void onAfterInsert_commitFailsAtMaxRetries_givesUpToDebugLog() {
    useMocks();
    DmlException cause = new DmlException('Storage limit exceeded');
    unitOfWorkMock.stubThrow('commitWork', cause);
    LogEventsDomain.retriesOverride = LogEventsDomain.MAX_RETRIES;

    new LogEventsDomain(events(2)).onAfterInsert();

    Assert.areEqual(1, fallback.entries(LoggingLevel.ERROR).size(), 'The batch was given up once');
    Assert.areEqual(cause, fallback.entries(LoggingLevel.ERROR)[0].cause, 'The cause is logged');
    Assert.areEqual(2, fallback.entries(LoggingLevel.WARN).size(), 'One line per unpersisted entry');
    Assert.isTrue(
      fallback.entries(LoggingLevel.WARN)[0].message.contains(REQUEST_ID + '-1'),
      'Each unpersisted entry is written with its key'
    );
  }

  @IsTest
  static void onAfterInsert_loggingDuringCommit_isNeverPublished() {
    Mocks publisherMock = new Mocks();
    LogBuffer.useNew((ILogEventPublisher) publisherMock.stub(ILogEventPublisher.class));
    LoggingSettings.useRow(LoggerTestFixtures.settings('DEBUG', 1));
    LoggingUnitOfWork unitOfWork = new LoggingUnitOfWork();
    Application.UnitOfWork.setMock((IUnitOfWork) Test.createStub(IUnitOfWork.class, unitOfWork));

    new LogEventsDomain(events(1)).onAfterInsert();

    Assert.isTrue(unitOfWork.suppressedDuringCommit, 'LogBuffer is suppressed while persisting');
    publisherMock.verify('publish', 0);
    Assert.areEqual(LogBuffer.SUPPRESSED_REASON, LogBuffer.lastFallbackReason, 'The entry went to the debug log');
    Assert.isFalse(LogBuffer.isSuppressed(), 'Suppression is cleared after a successful commit');
  }

  @IsTest
  static void constructor_buildsTheDomainForLogEvents() {
    IDomain domain = new LogEventsDomain.Constructor().construct(events(1));

    Assert.isInstanceOfType(domain, LogEventsDomain.class, 'The binding row names this constructor');
    Assert.areEqual(Log_Event__e.SObjectType, domain.getSObjectType(), 'The domain owns Log_Event__e');
  }

  /** Logs through the real logger on commit, the way A's dispatcher or host code might. */
  private class LoggingUnitOfWork implements System.StubProvider {
    Boolean suppressedDuringCommit = false;

    // The six parameters are the platform's System.StubProvider signature.
    @SuppressWarnings('PMD.ExcessiveParameterList')
    public Object handleMethodCall(
      Object stubbedObject,
      String stubbedMethodName,
      Type returnType,
      List<Type> listOfParamTypes,
      List<String> listOfParamNames,
      List<Object> listOfArgs
    ) {
      if (stubbedMethodName == 'commitWork') {
        suppressedDuringCommit = LogBuffer.isSuppressed();
        new PlatformEventLogger().error('Logged inside the subscriber', null);
      }
      return null;
    }
  }
}
