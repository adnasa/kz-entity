module.exports = function(config) {
  config.set({
    preprocessors: {
      // source files, that you wanna generate coverage for
      // do not include tests or libraries
      // (these files will be instrumented by Istanbul via Ibrik unless
      // specified otherwise in coverageReporter.instrumenter)
      'lib/*.js': ['coverage']
    },
    coverageReporter: {
      type: 'html',
      dir: 'coverage/'
    },
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
    reporters: ['progress', 'coverage'],
    // web server port
    port: 9876,
    // cli runner port
    runnerPort: 9100,
    autoWatch: true,
    browsers: ['Chrome', 'Firefox', 'PhantomJS']
  });
};
