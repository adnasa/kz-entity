var gulp = require('gulp'),
    concat = require('gulp-concat'),
    coffee = require('gulp-coffee'),
    connect = require('gulp-connect'),
    karma = require('gulp-karma'),
    jsDependencies = [
      "lodash/dist/lodash.js",
    ],
    appRoot = './web/calendar';

gulp.task('dependencies', function() {
  var result = _.map(jsDependencies, function (val) {
    return 'bower_components/' + val;
  });
  return gulp.src(result)
    .pipe(concat('dependencies.js'))
    .pipe(gulp.dest(appRoot + '/js'));
});

gulp.task('scripts', function() {
  gulp.src('src/*.coffee')
    .pipe(coffee())
    .pipe(gulp.dest('lib'));
});

gulp.task('testscripts', function() {
  gulp.src('testsrc/*.coffee')
    .pipe(coffee())
    .pipe(gulp.dest('test'));
});

gulp.task('test', function() {
  testFiles = [
    'bower_components/angular/angular.js',
    'bower_components/angular-mocks/angular-mocks.js',
    'bower_components/lodash/dist/lodash.js',
    'lib/*.js',
    'test/*.js'
  ];
  // Be sure to return the stream
  return gulp.src(testFiles)
    .pipe(karma({
      configFile: 'karma.conf.js',
      action: 'start'
    }));
});

gulp.task('watch', function() {
  gulp.watch('src/*.coffee', ['scripts', 'test']);
  gulp.watch('testsrc/*.coffee', ['testscripts', 'test']);
});

gulp.task('default', ['scripts', 'testscripts']);
