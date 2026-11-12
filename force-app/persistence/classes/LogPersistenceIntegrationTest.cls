/**
 * @description Real event bus, real DML: an entry logged and delivered becomes one `Log__c` row,
 * redelivery doesn't duplicate it, retries use the real `EventBus.TriggerContext`, and `Log__c` is
 * visible only through `Log_Viewer` (ADR 0005).
 */
@IsTest
private class LogPersistenceIntegrationTest {
  private static List<Log__c> persistedLogs() {
    return [
      SELECT Log_Key__c, Level__c, Message__c, Request_Id__c, Sequence__c, Logged_By__c, Exception_Type__c
      FROM Log__c
      WITH SYSTEM_MODE
      ORDER BY Sequence__c
    ];
  }

  /** A separate runAs context avoids MIXED_DML_OPERATION after the user setup. */
  private static void insertLogAsTestUser(String message) {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert as system new Log__c(Log_Key__c = 'visibility-1', Message__c = message);
    }
  }

  @IsTest
  static void domainBinding_forLogEvents_resolvesLogEventsDomain() {
    IDomain domain = Application.Domain.newInstance(new List<Log_Event__e>(), Log_Event__e.SObjectType);

    Assert.isInstanceOfType(domain, LogEventsDomain.class, 'DI_Binding.Log_Events_Domain binds the domain');
  }

  @IsTest
  static void logFlushDeliver_oneEntry_persistsOneRow() {
    ILogger logger = (ILogger) Application.Service.newInstance(ILogger.class);

    Test.startTest();
    logger.error('Booking shipment for order 42', new DmlException('Required field missing'));
    Test.getEventBus().deliver();
    Test.stopTest();

    List<Log__c> logs = persistedLogs();
    Assert.areEqual(1, logs.size(), 'One entry, one row');
    Assert.areEqual('ERROR', logs[0].Level__c, 'Level');
    Assert.areEqual('Booking shipment for order 42', logs[0].Message__c, 'Message');
    Assert.areEqual('System.DmlException', logs[0].Exception_Type__c, 'Exception type');
    Assert.areEqual(logs[0].Request_Id__c + '-1', logs[0].Log_Key__c, 'Key is Request_Id-Sequence');
    Assert.areEqual(UserInfo.getUserId(), logs[0].Logged_By__c, 'Logged by the publishing user');
    Assert.isFalse(LogBuffer.isSuppressed(), 'Suppression ends with the subscriber');
  }

  @IsTest
  static void callerRollsBack_entryStillPersists() {
    ILogger logger = (ILogger) Application.Service.newInstance(ILogger.class);

    Test.startTest();
    Savepoint beforeWork = Database.setSavepoint();
    logger.info('Booking shipment for order 42');
    logger.flush();
    Database.rollback(beforeWork);
    Test.getEventBus().deliver();
    Test.stopTest();

    Assert.areEqual(1, persistedLogs().size(), 'Publish Immediately survives the rollback (R3)');
  }

  @IsTest
  static void deliver_sameKeyTwice_keepsOneRow() {
    Log_Event__e first = new Log_Event__e(Request_Id__c = 'redelivered', Sequence__c = 1, Message__c = 'first');
    Log_Event__e second = new Log_Event__e(Request_Id__c = 'redelivered', Sequence__c = 1, Message__c = 'second');

    Test.startTest();
    EventBus.publish(first);
    Test.getEventBus().deliver();
    EventBus.publish(second);
    Test.getEventBus().deliver();
    Test.stopTest();

    List<Log__c> logs = persistedLogs();
    Assert.areEqual(1, logs.size(), 'The upsert matched the existing row');
    Assert.areEqual('second', logs[0].Message__c, 'The redelivered event updated it');
  }

  @IsTest
  static void deliver_commitAlwaysFails_retriesThenGivesUp() {
    Mocks unitOfWorkMock = new Mocks();
    unitOfWorkMock.stubThrow('commitWork', new DmlException('Storage limit exceeded'));
    Application.UnitOfWork.setMock((IUnitOfWork) unitOfWorkMock.stub(IUnitOfWork.class));
    RecordingLogger fallback = new RecordingLogger();
    LogEventsDomain.fallbackLogger = fallback;

    Test.startTest();
    EventBus.publish(new Log_Event__e(Request_Id__c = 'poison', Sequence__c = 1));
    for (Integer attempt = 0; attempt <= LogEventsDomain.MAX_RETRIES; attempt++) {
      Test.getEventBus().deliver();
    }
    Test.stopTest();

    unitOfWorkMock.verify('commitWork', LogEventsDomain.MAX_RETRIES + 1);
    Assert.areEqual(1, fallback.entries(LoggingLevel.ERROR).size(), 'The batch was given up once');
  }

  @IsTest
  static void minimumAccessPublisher_withPermissionSet_persistsAsThatUser() {
    User publisher = LoggerTestFixtures.minimumAccessUser();
    LoggerTestFixtures.assignPublisherPermissionSet(publisher);

    Test.startTest();
    System.runAs(publisher) {
      ILogger logger = (ILogger) Application.Service.newInstance(ILogger.class);
      logger.error('Commit failed', null);
    }
    Test.getEventBus().deliver();
    Test.stopTest();

    List<Log__c> logs = persistedLogs();
    Assert.areEqual(1, logs.size(), 'The subscriber writes in system mode, whoever published');
    Assert.areEqual(publisher.Id, logs[0].Logged_By__c, 'Logged by the Minimum Access publisher');
  }

  @IsTest
  static void minimumAccessUser_withoutLogViewer_cannotReadLogs() {
    User reader = LoggerTestFixtures.minimumAccessUser();
    insertLogAsTestUser('secret');

    System.runAs(reader) {
      try {
        List<Log__c> visible = [SELECT Id FROM Log__c WITH USER_MODE];
        Assert.fail('Expected no access to Log__c, but read ' + visible.size() + ' rows');
      } catch (QueryException expected) {
        Assert.isNotNull(expected.getMessage(), 'No object permission on Log__c');
      }
    }
  }

  @IsTest
  static void minimumAccessUser_withLogViewer_readsEveryRow() {
    User reader = LoggerTestFixtures.minimumAccessUser();
    LoggerTestFixtures.assignPermissionSet(reader, 'Log_Viewer');
    insertLogAsTestUser('owned by the test user');

    System.runAs(reader) {
      List<Log__c> visible = [SELECT Message__c, Log_Key__c FROM Log__c WITH USER_MODE];
      Assert.areEqual(1, visible.size(), 'View All shows rows the reader does not own');
      Assert.areEqual('owned by the test user', visible[0].Message__c, 'Field read is granted');
    }
  }

  @IsTest
  static void logKeyField_isAnUpsertKey() {
    DescribeFieldResult key = Log__c.Log_Key__c.getDescribe();

    Assert.isTrue(key.isIdLookup(), 'A 1.1.0 registerUpsert needs an idLookup field');
    Assert.isTrue(key.isExternalId(), 'External Id');
    Assert.isTrue(key.isUnique(), 'Unique, so a key matches at most one row');
    Assert.isTrue(key.isCaseSensitive(), 'Request Ids are case-sensitive');
  }
}
