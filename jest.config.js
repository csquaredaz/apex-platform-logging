const { jestConfig } = require("@salesforce/sfdx-lwc-jest/config");

module.exports = {
  ...jestConfig,
  modulePathIgnorePatterns: ["<rootDir>/.localdevserver"],
  // Passes when a repo has no LWC yet; components bring their own tests.
  passWithNoTests: true
};
