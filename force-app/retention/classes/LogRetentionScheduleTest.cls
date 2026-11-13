/**
 * @description Tests for `LogRetentionSchedule` with real scheduled jobs: one job per name,
 * the default and custom cron, unscheduling, and that a run starts the batch.
 */
@IsTest
private class LogRetentionScheduleTest {
  private static List<CronTrigger> retentionJobs() {
    return new CronTriggersSelector().selectByJobName(LogRetentionSchedule.JOB_NAME);
  }

  @IsTest
  static void schedule_default_createsOneDailyJob() {
    Test.startTest();
    Id jobId = LogRetentionSchedule.schedule();
    Test.stopTest();

    List<CronTrigger> jobs = retentionJobs();
    Assert.areEqual(1, jobs.size(), 'One job');
    Assert.areEqual(jobId, jobs[0].Id, 'The returned Id');
    Assert.areEqual(LogRetentionSchedule.DEFAULT_CRON, jobs[0].CronExpression, 'Daily at 02:00');
  }

  @IsTest
  static void schedule_twice_replacesTheJob() {
    Test.startTest();
    LogRetentionSchedule.schedule();
    Id second = LogRetentionSchedule.schedule('0 30 3 ? * SUN');
    Test.stopTest();

    List<CronTrigger> jobs = retentionJobs();
    Assert.areEqual(1, jobs.size(), 'Still one job');
    Assert.areEqual(second, jobs[0].Id, 'The newer job');
    Assert.areEqual('0 30 3 ? * SUN', jobs[0].CronExpression, 'The custom cron');
  }

  @IsTest
  static void schedule_invalidCron_throwsAndKeepsTheExistingJob() {
    Id existing = LogRetentionSchedule.schedule();

    try {
      LogRetentionSchedule.schedule('not a cron expression');
      Assert.fail('An invalid cron expression throws');
    } catch (StringException expected) {
      List<CronTrigger> jobs = retentionJobs();
      Assert.areEqual(1, jobs.size(), 'The existing job is kept');
      Assert.areEqual(existing, jobs[0].Id, 'The same job');
    }
  }

  @IsTest
  static void unschedule_scheduledAndNot_returnsTheCount() {
    LogRetentionSchedule.schedule();

    Assert.areEqual(1, LogRetentionSchedule.unschedule(), 'One job aborted');
    Assert.areEqual(0, retentionJobs().size(), 'No job left');
    Assert.areEqual(0, LogRetentionSchedule.unschedule(), 'Nothing to abort');
  }

  @IsTest
  static void execute_scheduledRun_startsTheRetentionBatch() {
    Test.startTest();
    new LogRetentionSchedule().execute(null);
    Test.stopTest();

    List<AsyncApexJob> runs = [
      SELECT Status
      FROM AsyncApexJob
      WHERE JobType = 'BatchApex' AND ApexClass.Name = 'LogRetentionBatch'
      WITH SYSTEM_MODE
    ];
    Assert.areEqual(1, runs.size(), 'One batch run');
    Assert.areEqual('Completed', runs[0].Status, 'It ran to completion');
  }
}
