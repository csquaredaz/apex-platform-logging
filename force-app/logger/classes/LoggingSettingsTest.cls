@IsTest
private class LoggingSettingsTest {
  @IsTest
  static void constructor_nullRow_usesSafeDefaults() {
    LoggingSettings settings = new LoggingSettings(null);

    Assert.isTrue(settings.isEnabled, 'Enabled by default');
    Assert.areEqual(LoggingLevel.DEBUG, settings.minimumLevel, 'DEBUG by default');
    Assert.areEqual(LoggingSettings.DEFAULT_BUFFER_SIZE, settings.bufferSize, 'Default buffer size');
  }

  @IsTest
  static void constructor_configuredRow_readsEveryField() {
    LoggingSettings settings = new LoggingSettings(LoggerTestFixtures.settings('WARN', 7));

    Assert.areEqual(LoggingLevel.WARN, settings.minimumLevel, 'Minimum level');
    Assert.areEqual(7, settings.bufferSize, 'Buffer size');
  }

  @IsTest
  static void constructor_blankOrUnknownLevel_meansDebug() {
    Assert.areEqual(
      LoggingLevel.DEBUG,
      new LoggingSettings(LoggerTestFixtures.settings(null, 5)).minimumLevel,
      'Blank'
    );
    Assert.areEqual(
      LoggingLevel.DEBUG,
      new LoggingSettings(LoggerTestFixtures.settings('FINEST', 5)).minimumLevel,
      'Not a supported level'
    );
  }

  @IsTest
  static void constructor_outOfRangeBufferSize_isClamped() {
    Assert.areEqual(
      LoggingSettings.DEFAULT_BUFFER_SIZE,
      new LoggingSettings(LoggerTestFixtures.settings('DEBUG', 0)).bufferSize,
      'Below 1 means the default'
    );
    Assert.areEqual(
      LoggingSettings.DEFAULT_BUFFER_SIZE,
      new LoggingSettings(LoggerTestFixtures.settings('DEBUG', null)).bufferSize,
      'Blank means the default'
    );
    Assert.areEqual(
      LoggingSettings.MAX_BUFFER_SIZE,
      new LoggingSettings(LoggerTestFixtures.settings('DEBUG', 999)).bufferSize,
      'Capped at the maximum'
    );
  }

  @IsTest
  static void accepts_minimumWarn_dropsLowerLevels() {
    LoggingSettings settings = new LoggingSettings(LoggerTestFixtures.settings('WARN', 5));

    Assert.isFalse(settings.accepts(LoggingLevel.DEBUG), 'DEBUG is below WARN');
    Assert.isFalse(settings.accepts(LoggingLevel.INFO), 'INFO is below WARN');
    Assert.isTrue(settings.accepts(LoggingLevel.WARN), 'WARN is kept');
    Assert.isTrue(settings.accepts(LoggingLevel.ERROR), 'ERROR is kept');
    Assert.isFalse(settings.accepts(LoggingLevel.FINE), 'Unsupported levels are dropped');
    Assert.isFalse(settings.accepts(null), 'A null level is dropped');
  }

  @IsTest
  static void accepts_disabled_dropsEverything() {
    Logging_Setting__mdt row = LoggerTestFixtures.settings('DEBUG', 5);
    row.Is_Enabled__c = false;

    Assert.isFalse(new LoggingSettings(row).accepts(LoggingLevel.ERROR), 'The kill switch drops even errors');
  }

  @IsTest
  static void current_deployedDefaultRow_isReadOnceAndCached() {
    LoggingSettings first = LoggingSettings.current();

    Assert.isNotNull(first, 'Settings are always available');
    Assert.areEqual(first, LoggingSettings.current(), 'The same instance for the rest of the transaction');
  }

  @IsTest
  static void useRow_injectedRow_replacesCurrent() {
    LoggingSettings.useRow(LoggerTestFixtures.settings('ERROR', 2));

    Assert.areEqual(LoggingLevel.ERROR, LoggingSettings.current().minimumLevel, 'The injected row applies');
  }
}
