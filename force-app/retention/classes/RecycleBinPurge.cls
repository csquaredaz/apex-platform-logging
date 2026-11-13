/**
 * @description Empties deleted records from the Recycle Bin, as Unit of Work work that runs after
 * the commit's deletes (ADR 0007, D20). Retention hard-deletes so the bin stays free for users'
 * deleted business records: its capacity is about 25 records per MB of data storage, and when it
 * fills, the oldest entries are purged early. It also removes the log text for good.
 *
 * A failed result throws, so the Unit of Work rolls the deletes back with it.
 *
 * Note: `SELECT ... ALL ROWS` still returns an emptied record with `IsDeleted = true` for a while
 * afterwards; `Database.undelete` failing with `UNDELETE_FAILED` is the reliable check.
 * @group Retention
 */
public with sharing class RecycleBinPurge implements IDoWork {
  private final List<SObject> records;

  /**
   * @description Creates the work for records the same Unit of Work deletes.
   * @param records The records; null or empty does nothing.
   */
  public RecycleBinPurge(List<SObject> records) {
    this.records = records == null ? new List<SObject>() : records;
  }

  /**
   * @description Empties the records from the Recycle Bin. Limits: 1 DML statement and one DML row
   * per record; none for an empty list.
   * @throws DmlException If any record can't be emptied, for example because it isn't deleted.
   */
  public void doWork() {
    if (records.isEmpty()) {
      return;
    }
    Integer failures = 0;
    String firstError;
    for (Database.EmptyRecycleBinResult result : Database.emptyRecycleBin(records)) {
      if (!result.isSuccess()) {
        failures++;
        firstError = firstError == null ? describe(result) : firstError;
      }
    }
    if (failures > 0) {
      throw new DmlException(
        'Recycle Bin purge failed for ' + failures + ' of ' + records.size() + ' records: ' + firstError
      );
    }
  }

  // A failed result always carries at least one error.
  private static String describe(Database.EmptyRecycleBinResult result) {
    Database.Error error = result.getErrors()[0];
    return result.getId() + ' ' + error.getStatusCode() + ' ' + error.getMessage();
  }
}
