_           = require 'lodash'
DataSource  = require('loopback-datasource-juggler').DataSource
debug       = require('debug') 'loopback:storage:mongo'
mongo       = require 'mongodb'

generateUrl = (options) ->
  host      = options.host or options.hostname or 'localhost'
  port      = options.port or 27017
  database  = options.database or 'test'
  if options.username and options.password
    return "mongodb://#{options.username}:#{options.password}@#{host}:#{port}/#{database}"
  else
    return "mongodb://#{host}:#{port}/#{database}"

class MongoStorage
  constructor: (@settings) ->
    if not @settings.url
      @settings.url = generateUrl @settings

  connect: (callback) ->
    self = @
    if @db
      process.nextTick ->
        if callback
          callback null, self.db
    else
      mongo.MongoClient.connect @settings.url, @settings, (err, db) ->
        if not err
          debug 'Mongo connection established: ' + self.settings.url
          self.db = db
        if callback
          callback err, db

  getContainers: (callback) ->
    @db.collection 'fs.files'
    .find
      metadata:
        'mongo-storage': true
    .toArray (err, files) ->
      return callback err, files

  getContainer: (name, callback) ->
    @db.collection 'fs.files'
    .findOne
      metadata:
        'mongo-storage': true
        container: name
    , callback

  upload: (container, file, options, callback) ->
    console.log container, file, options

exports.initialize = (dataSource, callback) ->
  settings = dataSource.settings or {}
  connector = new MongoStorage settings
  dataSource.connector = connector
  dataSource.connector.dataSource = dataSource
  connector.DataAccessObject = -> return
  for m, method of MongoStorage.prototype
    if _.isFunction method
      connector.DataAccessObject[m] = method.bind connector
      for k, opt of method
        connector.DataAccessObject[m][k] = opt
  connector.define = (model, properties, settings) -> return
  if callback
    dataSource.connector.connect callback
  return
