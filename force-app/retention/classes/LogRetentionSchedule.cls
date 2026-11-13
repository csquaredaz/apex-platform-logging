/**
 * @description Schedules `LogRetentionBatch` (ADR 0007, D18). An unlocked package can't run a
 * post-install script (R8: the CLI rejects one for an Unlocked package), so an admin schedules
 * retention once after installing, from anonymous Apex:
 *
 * ```apex
 * LogRetentionSchedule.schedule();                  // daily at 02:00, org time
 * LogRetentionSchedule.schedule('0 30 3 ? * SUN');  // or any cron expression
 * LogRetentionSchedule.unschedule();                // stop
 * ```
 *
 * The job runs as the user who scheduled it (proven in a scratch org). `schedule` replaces any job
 * with the same name, so running it twice leaves one job.
 * @group Retention
 */
public with sharing class LogRetentionSchedule implements Schedulable {
  /** @description The scheduled job's name; `schedule` and `unschedule` find the job by it. */
  public static final String JOB_NAME = 'Log retention (apex-platform-logging)';
  /** @description Daily at 02:00 in the org's time zone. */
  public static final String DEFAULT_CRON = '0 0 2 * * ?';

  /**
   * @description Starts one retention run.
   * @param context The schedule context.
   */
  public void execute(SchedulableContext context) {
    Database.executeBatch(new LogRetentionBatch(), LogRetentionBatch.BATCH_SIZE);
  }

  /**
   * @description Schedules retention daily at 02:00, replacing an existing retention job.
   * @return The scheduled job's `CronTrigger` Id.
   */
  public static Id schedule() {
    return schedule(DEFAULT_CRON);
  }

  /**
   * @description Schedules retention on a cron expression, replacing an existing retention job.
   * Limits: 1 SOQL, plus one abort per existing job.
   * @param cronExpression A Salesforce cron expression, for example `0 0 2 * * ?`.
   * @return The scheduled job's `CronTrigger` Id.
   * @throws StringException If the cron expression is invalid; the existing job is kept.
   */
  public static Id schedule(String cronExpression) {
    Savepoint beforeChange = Database.setSavepoint();
    try {
      unschedule();
      return System.schedule(JOB_NAME, cronExpression, new LogRetentionSchedule());
    } catch (Exception invalid) {
      Database.rollback(beforeChange);
      throw invalid;
    }
  }

  /**
   * @description Aborts every retention job. Limits: 1 SOQL, plus one abort per job.
   * @return The number of jobs aborted; 0 when none was scheduled.
   */
  public static Integer unschedule() {
    List<CronTrigger> jobs = new CronTriggersSelector().selectByJobName(JOB_NAME);
    for (CronTrigger job : jobs) {
      System.abortJob(job.Id);
    }
    return jobs.size();
  }
}
