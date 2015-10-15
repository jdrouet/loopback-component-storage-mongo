coffee  = require 'gulp-coffee'
gulp    = require 'gulp'
mocha   = require 'gulp-mocha'
plumber = require 'gulp-plumber'

gulp.task 'build', ->
  gulp.src './source/{,**/}*.coffee'
  .pipe plumber()
  .pipe coffee bare: true
  .pipe plumber.stop()
  .pipe gulp.dest './lib/'
  return

gulp.task 'test', ->
  gulp.src './test/{,**/}*.coffee', read: false
  .pipe plumber()
  .pipe mocha
    reporter: 'spec'
  .pipe plumber.stop()
  return

gulp.task 'default', ['build']

gulp.task 'watch', ['build', 'test'], ->
  gulp.watch ['{source,test}/{,**/}*.coffee'], ['build', 'test']
  gulp.watch ['test/{,**/}*.coffee'], ['test']

