/**
 * @description Test data for the logger tests: settings rows, publish results and a Minimum
 * Access user. `Database.SaveResult` has no public constructor, so results are deserialised.
 * @group Testing
 */
@IsTest
public class LoggerTestFixtures {
  /**
   * @description A settings row.
   * @param minimumLevel The minimum level name, for example `WARN`.
   * @param bufferSize The buffer size.
   * @return An in-memory `Logging_Setting__mdt` row, enabled.
   */
  public static Logging_Setting__mdt settings(String minimumLevel, Integer bufferSize) {
    return new Logging_Setting__mdt(
      DeveloperName = 'Test',
      Is_Enabled__c = true,
      Minimum_Level__c = minimumLevel,
      Buffer_Size__c = bufferSize
    );
  }

  /**
   * @description Successful publish results.
   * @param count The number of results.
   * @return `count` successful results.
   */
  public static List<Database.SaveResult> successes(Integer count) {
    List<Database.SaveResult> results = new List<Database.SaveResult>();
    for (Integer i = 0; i < count; i++) {
      results.add((Database.SaveResult) JSON.deserialize('{"success":true}', Database.SaveResult.class));
    }
    return results;
  }

  /**
   * @description A failed publish result.
   * @param message The error message.
   * @return A result with one error.
   */
  public static Database.SaveResult failure(String message) {
    return (Database.SaveResult) JSON.deserialize(
      '{"success":false,"errors":[{"statusCode":"UNKNOWN_EXCEPTION","message":' +
        JSON.serialize(message) +
        ',"fields":[]}]}',
      Database.SaveResult.class
    );
  }

  /**
   * @description Inserts a user with the Minimum Access profile and no permission sets.
   * @return The inserted user.
   */
  public static User minimumAccessUser() {
    Profile minimumAccess = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
    String unique = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
    User logUser = new User(
      ProfileId = minimumAccess.Id,
      LastName = 'Logger',
      Alias = 'logger',
      Email = 'logger' + unique + '@example.com',
      Username = 'logger' + unique + '@example.com.apl',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      TimeZoneSidKey = 'America/Phoenix'
    );
    insert as system logUser;
    return logUser;
  }

  /**
   * @description Assigns the `Log_Event_Publisher` permission set.
   * @param target The user to assign it to.
   */
  public static void assignPublisherPermissionSet(User target) {
    assignPermissionSet(target, 'Log_Event_Publisher');
  }

  /**
   * @description Assigns one of the packaged permission sets.
   * @param target The user to assign it to.
   * @param permissionSetName The permission set API name, for example `Log_Viewer`.
   */
  public static void assignPermissionSet(User target, String permissionSetName) {
    PermissionSet permissionSet = [SELECT Id FROM PermissionSet WHERE Name = :permissionSetName LIMIT 1];
    insert as system new PermissionSetAssignment(AssigneeId = target.Id, PermissionSetId = permissionSet.Id);
  }

  /**
   * @description An in-memory event as the subscriber receives it. `CreatedById` and `EventUuid`
   * are read-only, so the event is deserialised.
   * @param requestId The request Id, or null.
   * @param sequence The sequence, or null.
   * @param eventUuid The event UUID, or null.
   * @return The event, created by the running user.
   */
  public static Log_Event__e deliveredEvent(String requestId, Integer sequence, String eventUuid) {
    Map<String, Object> fields = new Map<String, Object>{
      'attributes' => new Map<String, Object>{ 'type' => 'Log_Event__e' },
      'CreatedById' => UserInfo.getUserId(),
      'EventUuid' => eventUuid,
      'Request_Id__c' => requestId,
      'Sequence__c' => sequence,
      'Level__c' => 'ERROR',
      'Message__c' => 'Booking shipment for order 42',
      'Exception_Type__c' => 'System.DmlException',
      'Exception_Message__c' => 'Required field missing',
      'Stack_Trace__c' => 'Class.ShipmentService.book: line 7',
      'Quiddity__c' => 'SYNCHRONOUS',
      'Logged_At__c' => Datetime.newInstanceGmt(2026, 11, 12, 9, 30, 0)
    };
    return (Log_Event__e) JSON.deserialize(JSON.serialize(fields), Log_Event__e.class);
  }
}
