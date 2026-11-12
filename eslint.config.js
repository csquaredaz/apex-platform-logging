const lwcConfig = require("@salesforce/eslint-config-lwc");
const jest = require("eslint-plugin-jest");

module.exports = [
  { ignores: ["node_modules/**", "coverage/**", ".sf/**", ".sfdx/**"] },
  ...lwcConfig.configs.recommended,
  {
    files: ["**/lwc/**/__tests__/**/*.js"],
    ...jest.configs["flat/recommended"]
  }
];
