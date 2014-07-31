module.exports = function(config) {
  config.set({
    basePath: '',
    frameworks: ['jasmine'],
    files: [
      'bower_components/angular/angular.js',
      'bower_components/angular-mocks/angular-mocks.js',
      'bower_components/lodash/dist/lodash.js',
      'lib/*.js',
      'test/*.js'
    ],
    logLevel: config.LOG_INFO,
    // test results reporter to use
    // possible values: 'dots', 'progress', 'junit'
    reporters: ['progress'],
    // web server port
    port: 9876,
    // cli runner port
    runnerPort: 9100,
    autoWatch: true,
    browsers: ['Chrome']
  });
};
